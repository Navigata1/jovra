-- Gateway project, source, camera-invite and upload commands (S79 / B-06) as jovra_gateway.
-- T-DB-38 (complete_upload_check refuses a missing part, a wrong last-part size and a session bound to another
-- project's source, plus a stale session), T-DB-39 (redeem_camera_invite after redeem_by, twice, after revoke;
-- issue_guest_capability before approval or with another device key), T-DB-54 command half (coded P0422 with no
-- DETAIL), and the happy paths those refusals are measured against (architecture §6.2, §6.3; security-model §8.2).
-- User stories 199 and 244. The file rolls back.
begin;
select plan(55);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('owner_b');
select tests.create_supabase_user('camera');
grant jovra_gateway to postgres;

create function pg_temp.call(p_sql text) returns jsonb language plpgsql as $$
declare
  v_out    jsonb;
  v_text   text;
  v_state  text;
  v_msg    text;
  v_detail text;
begin
  execute 'set local role jovra_gateway';
  execute p_sql into v_text;   -- any scalar result, as text
  execute 'reset role';
  begin
    v_out := v_text::jsonb;     -- a jsonb result
  exception when others then
    v_out := to_jsonb(v_text);  -- a uuid, timestamptz or enum result
  end;
  return coalesce(v_out, '{}'::jsonb);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text, v_detail = pg_exception_detail;
  return jsonb_build_object('error', v_state, 'message', v_msg, 'detail', coalesce(v_detail, ''));
end $$;
create temp table t_out (k text primary key, v jsonb not null);
create function pg_temp.keep(p_key text, p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb := pg_temp.call(p_sql);
begin
  insert into pg_temp.t_out (k, v) values (p_key, v) on conflict (k) do update set v = excluded.v;
  return v;
end $$;
create function pg_temp.got(p_key text, p_field text default null) returns text language sql as $$
  select case when p_field is null then v #>> '{}' else v ->> p_field end from pg_temp.t_out where k = p_key
$$;
create function pg_temp.uid(p_who text) returns uuid language sql as $$ select tests.get_supabase_uid(p_who) $$;
create function pg_temp.err(p_sql text) returns text language sql as $$ select pg_temp.call(p_sql) ->> 'error' $$;
create function pg_temp.msg(p_sql text) returns text language sql as $$ select pg_temp.call(p_sql) ->> 'message' $$;
-- record_part(session, capability, n, bytes, etag, sha256, client sha256)
create function pg_temp.part_sql(p_session text, p_cap text, p_n int, p_bytes int, p_digest text default null)
returns text language sql as $$
  select format('select app_gateway.record_part(%L, sha256(%L::bytea), %s, %s, %L, sha256(%L::bytea), '
                'sha256(%L::bytea), gen_random_uuid())',
                p_session, p_cap, p_n, p_bytes, 'etag-' || p_n, 'part-' || p_n, coalesce(p_digest, 'part-' || p_n))
$$;
create function pg_temp.complete_sql(p_session text, p_cap text, p_parts jsonb) returns text language sql as $$
  select format('select app_gateway.complete_upload_check(%L, sha256(%L::bytea), %L::jsonb, gen_random_uuid())',
                p_session, p_cap, p_parts)
$$;

-- Projects -----------------------------------------------------------------------------------------------------------
select ok(pg_temp.keep('p', format('select to_jsonb(app_gateway.create_project(%L, %L, %L, %L, false, gen_random_uuid()))',
            pg_temp.uid('owner'), '11790000-0000-4000-8000-000000000001', 'Club final', 'match')) ? 'error' is false,
  'a real user creates a project through the gateway');
select ok(exists (select 1 from public.projects p join public.project_members m on m.project_id = p.id
                   where p.id = pg_temp.got('p')::uuid and p.owner_id = pg_temp.uid('owner')
                     and m.user_id = p.owner_id and m.role = 'owner'),
  'the project is the actor''s and its owner membership follows');
select is(pg_temp.call(format('select to_jsonb(app_gateway.create_project(%L, %L, %L, %L, false, gen_random_uuid()))',
            pg_temp.uid('owner'), '11790000-0000-4000-8000-000000000001', 'Club final', 'match')) #>> '{}',
  pg_temp.got('p'), 'story 199: a retry with the same local id returns the same project, never a second');
select is(pg_temp.call(format('select to_jsonb(app_gateway.create_project(%L, %L, %L, %L, false, gen_random_uuid()))',
            pg_temp.uid('owner'), gen_random_uuid(), repeat('x', 121), 'match')),
  '{"error": "P0422", "message": "field_too_long:title", "detail": ""}'::jsonb,
  'T-DB-54: a title over 120 characters is P0422 field_too_long:title with no DETAIL (no row values)');
select is(pg_temp.err(format('select app_gateway.create_project(%L, %L, %L, %L, false, gen_random_uuid())',
            gen_random_uuid(), gen_random_uuid(), 'Ghost', 'match')), 'P0401',
  'an actor with no account is P0401');

insert into public.projects (id, owner_id, local_project_id, title) values
  ('b7910000-0000-4000-8000-000000000001', pg_temp.uid('owner_b'), gen_random_uuid(), 'Other match');
insert into public.camera_sources (id, project_id, slot, local_source_id, declared_bytes, declared_sha256) values
  ('5b910000-0000-4000-8000-000000000001', 'b7910000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 70000000, sha256('sb'::bytea));

-- Sources ------------------------------------------------------------------------------------------------------------
create function pg_temp.declare_sql(p_slot text, p_local uuid, p_bytes bigint, p_seed text) returns text
language sql as $$
  select format('select to_jsonb(app_gateway.declare_source(%L, %L, %L, %L, %s, sha256(%L::bytea), %L::jsonb, '
                'gen_random_uuid()))', pg_temp.uid('owner'), pg_temp.got('p'), p_slot, p_local, p_bytes, p_seed,
                '{"codec": "hevc", "width": 3840, "height": 2160, "fps": 30, "duration": 3600, "rotation": 0}')
$$;
select ok(pg_temp.keep('s1', pg_temp.declare_sql('primary_baseline', '5d790000-0000-4000-8000-000000000001',
            70000000, 'source-1')) ? 'error' is false, 'the owner declares a 70,000,000-byte source');
select is(pg_temp.call(pg_temp.declare_sql('primary_baseline', '5d790000-0000-4000-8000-000000000001', 70000000,
            'source-1')) #>> '{}', pg_temp.got('s1'), 'story 199: the same declaration again returns the same source');
select is(pg_temp.msg(pg_temp.declare_sql('primary_baseline', '5d790000-0000-4000-8000-000000000009', 70000000,
            'source-9')), 'slot_taken', 'a second source for an occupied slot is P0409 slot_taken');
select is(pg_temp.msg(pg_temp.declare_sql('opposite_baseline', '5d790000-0000-4000-8000-000000000008', 8589934593,
            'source-8')), 'invalid_value:declared_bytes', 'a declaration over the 8 GiB cap is P0422');
select is((select state::text || ' ' || (client_probe ->> 'codec') || ' ' || coalesce(probe::text, 'no probe')
             from public.camera_sources where id = pg_temp.got('s1')::uuid),
  'declared hevc no probe', 'the device''s probe is stored as client_probe, never as probe');

-- Uploads: open, attach, parts -------------------------------------------------------------------------------------
select is(pg_temp.keep('x1', format('select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
            'user', pg_temp.uid('owner'), pg_temp.got('s1'), 70000000, 'source-1')) ->> 'partCount', '3',
  'authorize_upload opens a session of three 32 MiB parts for 70,000,000 bytes');
select is(pg_temp.got('x1', 'r2Key'),
  'staging/p/' || pg_temp.got('p') || '/s/' || pg_temp.got('s1') || '/original/' || pg_temp.got('x1', 'sessionId'),
  'each session writes its own server-generated key');
select is(pg_temp.msg(format('select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
            'user', pg_temp.uid('owner'), pg_temp.got('s1'), 70000001, 'source-1')), 'declaration_mismatch',
  'bytes other than the declaration are P0409 declaration_mismatch');
select is(pg_temp.err(format('select app_gateway.attach_upload_id(%L, %L, %L, %L, sha256(%L::bytea), gen_random_uuid())',
            'user', pg_temp.uid('owner'), pg_temp.got('x1', 'sessionId'), 'r2-upload-1', 'cap-1')), null,
  'the gateway attaches the R2 upload id and the session capability hash');
select is(pg_temp.call(pg_temp.part_sql(pg_temp.got('x1', 'sessionId'), 'cap-1', 1, 33554432)) ->> 'etag', 'etag-1',
  'part 1 (full size) is recorded');
select is(pg_temp.err(pg_temp.part_sql(pg_temp.got('x1', 'sessionId'), 'cap-1', 2, 33554432)), null,
  'part 2 (full size) is recorded');
select is(pg_temp.msg(pg_temp.part_sql(pg_temp.got('x1', 'sessionId'), 'cap-1', 3, 33554432)),
  'invalid_value:part_bytes', 'a last part of the wrong length is refused when it arrives');
select is(pg_temp.msg(pg_temp.part_sql(pg_temp.got('x1', 'sessionId'), 'cap-1', 3, 2891136, 'tampered')),
  'part_digest_mismatch', 'a streamed digest that differs from X-Jovra-Part-Sha256 is refused');
select is(pg_temp.err(pg_temp.part_sql(pg_temp.got('x1', 'sessionId'), 'cap-other', 3, 2891136)), 'P0404',
  'another session capability is P0404');

-- T-DB-38: completion against server-held expectations -------------------------------------------------------------
select is(pg_temp.msg(pg_temp.complete_sql(pg_temp.got('x1', 'sessionId'), 'cap-1',
            '[{"n": 1, "etag": "etag-1"}, {"n": 2, "etag": "etag-2"}]')), 'parts_incomplete',
  'T-DB-38: completion with a missing part is refused (P0409 parts_incomplete)');
select is(pg_temp.err(pg_temp.part_sql(pg_temp.got('x1', 'sessionId'), 'cap-1', 3, 2891136)), null,
  'the last part (2,891,136 bytes) is recorded');
select is(pg_temp.msg(pg_temp.complete_sql(pg_temp.got('x1', 'sessionId'), 'cap-1',
            '[{"n": 1, "etag": "etag-1"}, {"n": 2, "etag": "etag-2"}, {"n": 3, "etag": "forged"}]')), 'parts_mismatch',
  'a request part list that differs from the stored ETags is P0409 parts_mismatch');
-- a part row whose size bypassed record_part (defence in depth: completion re-checks every size)
update app_ops.upload_parts set bytes = bytes - 1
 where session_id = pg_temp.got('x1', 'sessionId')::uuid and part_number = 3;
select is(pg_temp.msg(pg_temp.complete_sql(pg_temp.got('x1', 'sessionId'), 'cap-1',
            '[{"n": 1, "etag": "etag-1"}, {"n": 2, "etag": "etag-2"}, {"n": 3, "etag": "etag-3"}]')),
  'part_size_mismatch', 'T-DB-38: completion with a wrong last-part size is refused (P0409 part_size_mismatch)');
update app_ops.upload_parts set bytes = 2891136
 where session_id = pg_temp.got('x1', 'sessionId')::uuid and part_number = 3;

-- A session bound to another project's source: impossible through the commands and the composite FK, so the test
-- removes the FK inside this transaction and plants one; completion still refuses it (architecture §6.3 step 2).
do $$
declare
  v_name text;
begin
  select c.conname into v_name from pg_constraint c
   where c.conrelid = 'app_ops.upload_sessions'::regclass and c.contype = 'f'
     and c.confrelid = 'public.camera_sources'::regclass;
  execute format('alter table app_ops.upload_sessions drop constraint %I', v_name);
end $$;
insert into app_ops.upload_sessions (id, project_id, source_id, actor_kind, actor_id, r2_key, expected_bytes,
                                     expected_sha256, part_count, state, capability_hash, expires_at, hard_expires_at)
values ('e5790000-0000-4000-8000-00000000000f', pg_temp.got('p')::uuid, '5b910000-0000-4000-8000-000000000001',
        'owner', pg_temp.uid('owner'), 'staging/forged', 1, sha256('sb'::bytea), 1, 'open', sha256('cap-f'::bytea),
        now() + interval '1 hour', now() + interval '48 hours');
insert into app_ops.upload_parts (session_id, part_number, bytes, etag, sha256)
values ('e5790000-0000-4000-8000-00000000000f', 1, 1, 'etag-f', sha256('f'::bytea));
select is(pg_temp.err(pg_temp.complete_sql('e5790000-0000-4000-8000-00000000000f', 'cap-f',
            '[{"n": 1, "etag": "etag-f"}]')), 'P0404',
  'T-DB-38: a session of project A bound to project B''s source is refused (wrong-project completion)');

select ok(pg_temp.keep('x2', format('select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
            'user', pg_temp.uid('owner'), pg_temp.got('s1'), 70000000, 'source-1')) ? 'sessionId',
  'opening a second session for the source aborts the first in the same transaction');
select is(pg_temp.msg(pg_temp.complete_sql(pg_temp.got('x1', 'sessionId'), 'cap-1',
            '[{"n": 1, "etag": "etag-1"}, {"n": 2, "etag": "etag-2"}, {"n": 3, "etag": "etag-3"}]')),
  'session_not_open', 'T-DB-38: the superseded (stale) session can never complete');
select is((select current_session_id::text from public.camera_sources where id = pg_temp.got('s1')::uuid),
  pg_temp.got('x2', 'sessionId'), 'the new session is the source''s current_session_id');

-- The happy path: complete with the parts from the database, then the head check ------------------------------------
select is(pg_temp.err(format('select app_gateway.attach_upload_id(%L, %L, %L, %L, sha256(%L::bytea), gen_random_uuid())',
            'user', pg_temp.uid('owner'), pg_temp.got('x2', 'sessionId'), 'r2-upload-2', 'cap-2')), null,
  'session x2 is attached');
select is((select count(*)::int from (
            select pg_temp.err(pg_temp.part_sql(pg_temp.got('x2', 'sessionId'), 'cap-2', n,
                                                case when n < 3 then 33554432 else 2891136 end)) e
              from generate_series(1, 3) n) x where e is null), 3, 'all three parts of x2 are recorded');
select is(pg_temp.keep('c2', pg_temp.complete_sql(pg_temp.got('x2', 'sessionId'), 'cap-2',
            '[{"n": 3, "etag": "etag-3"}, {"n": 1, "etag": "etag-1"}, {"n": 2, "etag": "etag-2"}]')) -> 'parts',
  '[{"n": 1, "etag": "etag-1"}, {"n": 2, "etag": "etag-2"}, {"n": 3, "etag": "etag-3"}]'::jsonb,
  'completion returns the ETags from upload_parts, in part order');
select is(pg_temp.msg(format('select app_gateway.mark_uploaded_unverified(%L, sha256(%L::bytea), %s, gen_random_uuid())',
            pg_temp.got('x2', 'sessionId'), 'cap-2', 69999999)), 'size_mismatch',
  'an R2 head size other than the declaration is P0409 size_mismatch');
select is(pg_temp.call(format('select to_jsonb(app_gateway.mark_uploaded_unverified(%L, sha256(%L::bytea), %s, gen_random_uuid()))',
            pg_temp.got('x2', 'sessionId'), 'cap-2', 70000000)) #>> '{}', 'uploaded_unverified',
  'the source becomes uploaded_unverified (verify_sources decides verified)');
select ok((select s.state = 'uploaded_unverified' and s.r2_key = pg_temp.got('x2', 'r2Key') and s.verified_at is null
                  and u.state = 'completed' and u.completed_at is not null
             from public.camera_sources s join app_ops.upload_sessions u on u.id = s.current_session_id
            where s.id = pg_temp.got('s1')::uuid),
  'the source records the session''s key; the session is completed; nothing claims verification');

-- Camera invites (T-DB-39) -------------------------------------------------------------------------------------------
create function pg_temp.invite_sql(p_slot text, p_label text, p_code text) returns text language sql as $$
  select format('select app_gateway.create_camera_invite(%L, %L, %L, %L, sha256(%L::bytea), gen_random_uuid())',
                pg_temp.uid('owner'), pg_temp.got('p'), p_slot, p_label, p_code)
$$;
create function pg_temp.redeem_sql(p_code text, p_device text) returns text language sql as $$
  select format('select app_gateway.redeem_camera_invite(sha256(%L::bytea), sha256(%L::bytea), %L, %L, gen_random_uuid())',
                p_code, p_device, 'Guest phone', pg_temp.uid('camera'))
$$;
create function pg_temp.capability_sql(p_invite text, p_device text, p_cap text) returns text language sql as $$
  select format('select to_jsonb(app_gateway.issue_guest_capability(%L, sha256(%L::bytea), sha256(%L::bytea), '
                'gen_random_uuid()))', p_invite, p_device, p_cap)
$$;
select is(pg_temp.call(pg_temp.invite_sql('near_deuce_corner', repeat('x', 61), 'code-0')),
  '{"error": "P0422", "message": "field_too_long:display_label", "detail": ""}'::jsonb,
  'T-DB-54: a 61-character invite label is P0422 field_too_long:display_label with no DETAIL');
select ok(pg_temp.keep('i1', pg_temp.invite_sql('near_deuce_corner', 'Corner phone', 'code-1')) ? 'inviteId',
  'the owner creates a one-slot camera invite');
select ok((select v ->> 'redeemBy' from pg_temp.t_out where k = 'i1')::timestamptz <= now() + interval '10 minutes',
  'the code must be redeemed within 10 minutes');
select is(pg_temp.msg(pg_temp.invite_sql('near_deuce_corner', 'Again', 'code-1b')), 'slot_taken',
  'one open invite per slot');
select is(pg_temp.keep('r1', pg_temp.redeem_sql('code-1', 'device-1')),
  jsonb_build_object('redemptionId', pg_temp.got('i1', 'inviteId'), 'deviceCode', '188785', 'status', 'awaiting_host'),
  'redemption returns the device code derived from the key thumbprint (188785) and no project text');
select is(pg_temp.err(pg_temp.redeem_sql('code-1', 'device-2')), 'P0404',
  'T-DB-39: redeeming the same code twice is P0404');
select is(pg_temp.err(pg_temp.capability_sql(pg_temp.got('i1', 'inviteId'), 'device-1', 'jvg-cap-1')), 'P0404',
  'T-DB-39: issue_guest_capability before the host''s approval is P0404');
select is(pg_temp.msg(format('select app_gateway.approve_camera_invite(%L, %L, %L, gen_random_uuid())',
            pg_temp.uid('owner'), pg_temp.got('i1', 'inviteId'), '000000')), 'device_code_mismatch',
  'the host approves only the device code shown on both phones');
select is(pg_temp.err(format('select app_gateway.approve_camera_invite(%L, %L, %L, gen_random_uuid())',
            pg_temp.uid('owner'), pg_temp.got('i1', 'inviteId'), '188785')), null,
  'the host approves the matching device code');
select is(pg_temp.err(pg_temp.capability_sql(pg_temp.got('i1', 'inviteId'), 'device-2', 'jvg-cap-1')), 'P0404',
  'T-DB-39: issue_guest_capability with another device key is P0404');
select ok((pg_temp.call(pg_temp.capability_sql(pg_temp.got('i1', 'inviteId'), 'device-1', 'jvg-cap-1')) #>> '{}')::timestamptz
            <= now() + interval '24 hours',
  'the redeeming device gets a capability that ends within 24 hours of approval');
select ok(pg_temp.keep('gs', format('select to_jsonb(app_gateway.guest_declare_source(%L, sha256(%L::bytea), %L, %s, '
            'sha256(%L::bytea), %L::jsonb, gen_random_uuid()))', pg_temp.got('i1', 'inviteId'), 'jvg-cap-1',
            gen_random_uuid(), 50000000, 'guest-src', '{}')) ? 'error' is false,
  'the guest declares exactly one source for its slot');
select is(pg_temp.err(format('select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
            'user', pg_temp.uid('owner'), pg_temp.got('gs'), 50000000, 'guest-src')), 'P0404',
  'the owner cannot open an upload for the guest''s angle');
select ok(pg_temp.call(format('select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
            'camera_guest', pg_temp.got('i1', 'inviteId'), pg_temp.got('gs'), 50000000, 'guest-src')) ? 'sessionId',
  'the guest opens the upload of its own source');

select ok(pg_temp.keep('i2', pg_temp.invite_sql('far_ad_corner', 'Far phone', 'code-2')) ? 'inviteId', 'a second invite');
update public.camera_invites set created_at = now() - interval '1 hour', redeem_by = now() - interval '50 minutes'
 where id = pg_temp.got('i2', 'inviteId')::uuid;
select is(pg_temp.err(pg_temp.redeem_sql('code-2', 'device-3')), 'P0404', 'T-DB-39: redeeming after redeem_by is P0404');
select ok(pg_temp.keep('i3', pg_temp.invite_sql('near_ad_corner', 'Near phone', 'code-3')) ? 'inviteId', 'a third invite');
select is(pg_temp.err(format('select app_gateway.revoke_camera_invite(%L, %L, gen_random_uuid())',
            pg_temp.uid('owner'), pg_temp.got('i3', 'inviteId'))), null, 'the owner revokes the third invite');
select is(pg_temp.err(pg_temp.redeem_sql('code-3', 'device-4')), 'P0404', 'T-DB-39: redeeming after revoke is P0404');
select is(pg_temp.err(format('select app_gateway.revoke_camera_invite(%L, %L, gen_random_uuid())',
            pg_temp.uid('owner'), pg_temp.got('i1', 'inviteId'))), null, 'the owner revokes the approved invite');
select is(pg_temp.err(pg_temp.capability_sql(pg_temp.got('i1', 'inviteId'), 'device-1', 'jvg-cap-2')), 'P0404',
  'T-DB-39: a revoked invite gets no new capability');

-- Project deletion stops uploads --------------------------------------------------------------------------------------
update public.projects set deleted_at = now() where id = pg_temp.got('p')::uuid;
select is(pg_temp.err(format('select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
            'user', pg_temp.uid('owner'), pg_temp.got('s1'), 70000000, 'source-1')), 'P0404',
  'authorize_upload is refused once the project''s deletion has started');

select * from finish();
rollback;
