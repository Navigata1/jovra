-- Gateway grant, membership, share-link and deletion commands (S79 / B-06) as jovra_gateway.
-- T-DB-51 (a project_coach redemption is pending until approve_member; revoke_grant revokes the membership in the same
-- transaction), T-DB-58 (a forwarded code of every invitation kind redeemed by a stranger, or by the invitee with an
-- unconfirmed email, is P0404 like an unknown code; the intended invitee succeeds; the owner's approval view shows the
-- masked verified email, never display_name), share links (≤ 24 h, ready films, previews and excerpts only, no-audio
-- variant), deletion requests (dependents, re-authentication, idempotency) and T-DB-47's command half (no bearer token
-- reaches any app_ops row). Security-model §13.2, §13.4, §8.3; user stories 199 and 244. The file rolls back.
begin;
select plan(56);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('coach', 'coach.invitee@example.test');
select tests.create_supabase_user('stranger', 'stranger@example.test');
select tests.create_supabase_user('unconfirmed', 'unconfirmed@example.test');
select tests.create_supabase_user('viewer', 'viewer.invitee@example.test');
update auth.users set email_confirmed_at = null where id = tests.get_supabase_uid('unconfirmed');
update public.profiles set display_name = 'Project Owner (official)' where id = tests.get_supabase_uid('coach');
grant jovra_gateway to postgres;

create function pg_temp.call(p_sql text) returns jsonb language plpgsql as $$
declare
  v_out   jsonb;
  v_text  text;
  v_state text;
  v_msg   text;
begin
  execute 'set local role jovra_gateway';
  execute p_sql into v_text;
  execute 'reset role';
  begin
    v_out := v_text::jsonb;
  exception when others then
    v_out := to_jsonb(v_text);
  end;
  return coalesce(v_out, '{}'::jsonb);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return jsonb_build_object('error', v_state, 'message', v_msg);
end $$;
create temp table t_out (k text primary key, v jsonb not null);
create function pg_temp.keep(p_key text, p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb := pg_temp.call(p_sql);
begin
  insert into pg_temp.t_out (k, v) values (p_key, v) on conflict (k) do update set v = excluded.v;
  return v;
end $$;
create function pg_temp.got(p_key text, p_field text) returns text language sql as $$
  select v ->> p_field from pg_temp.t_out where k = p_key
$$;
create function pg_temp.uid(p_who text) returns uuid language sql as $$ select tests.get_supabase_uid(p_who) $$;
create function pg_temp.err(p_sql text) returns text language sql as $$ select pg_temp.call(p_sql) ->> 'error' $$;
create function pg_temp.msg(p_sql text) returns text language sql as $$ select pg_temp.call(p_sql) ->> 'message' $$;
-- Tokens are shaped like the real jv*_ bearer secrets; only their SHA-256 ever reaches the database.
create function pg_temp.tok(p_kind text, p_n int) returns text language sql as $$
  select 'jv' || p_kind || '_' || rpad('S79sample' || p_n, 43, 'x')
$$;
create function pg_temp.grant_sql(p_actor text, p_kind text, p_email text, p_project uuid, p_lesson uuid,
                                  p_artifact uuid, p_clip uuid, p_token text) returns text language sql as $$
  select format('select app_gateway.create_grant(%L, %L, %L, %L, %L, %L, %L, null, sha256(%L::bytea), gen_random_uuid())',
                pg_temp.uid(p_actor), p_kind, p_email, p_project, p_lesson, p_artifact, p_clip, p_token)
$$;
create function pg_temp.redeem_sql(p_actor text, p_token text) returns text language sql as $$
  select format('select app_gateway.redeem_grant(%L, sha256(%L::bytea), gen_random_uuid())', pg_temp.uid(p_actor), p_token)
$$;

-- Fixtures: the owner's project P with a verified source, a ready film F (and a ready preview, a proxy), the owner's
-- lesson L with a clip C of P.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a7920000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Club final');
insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, declared_sha256) values
  ('5c920000-0000-4000-8000-000000000001', 'a7920000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s1'::bytea));
insert into public.artifacts (id, project_id, kind, bucket_class, r2_key, state, verified_at, verification) values
  ('f7920000-0000-4000-8000-000000000001', 'a7920000-0000-4000-8000-000000000001', 'film', 'films', 'films/a792/f1',
   'ready', now(), '{}'),
  ('f7920000-0000-4000-8000-000000000002', 'a7920000-0000-4000-8000-000000000001', 'preview', 'work', 'work/a792/p1',
   'writing', null, null),
  ('f7920000-0000-4000-8000-000000000003', 'a7920000-0000-4000-8000-000000000001', 'analysis_proxy', 'work',
   'work/a792/x1', 'ready', now(), '{}');
insert into public.artifact_sources (artifact_id, project_id, source_id) values
  ('f7920000-0000-4000-8000-000000000001', 'a7920000-0000-4000-8000-000000000001', '5c920000-0000-4000-8000-000000000001');
insert into public.lessons (id, owner_id, local_lesson_id, title) values
  ('1e920000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Footwork');
insert into public.lesson_clips (id, lesson_id, project_id, source_id, match_start_us, match_end_us) values
  ('c1920000-0000-4000-8000-000000000001', '1e920000-0000-4000-8000-000000000001',
   'a7920000-0000-4000-8000-000000000001', '5c920000-0000-4000-8000-000000000001', 1000000, 5000000);

-- create_grant: bound to the invitee's email, never storing it ---------------------------------------------------
select ok(pg_temp.keep('g_pc', pg_temp.grant_sql('owner', 'project_coach', 'Coach.Invitee@example.test ',
            'a7920000-0000-4000-8000-000000000001', null, null, null, pg_temp.tok('i', 1))) ? 'grantId',
  'the owner invites a coach to P');
select ok(pg_temp.keep('g_lc', pg_temp.grant_sql('owner', 'lesson_coach', 'coach.invitee@example.test', null,
            '1e920000-0000-4000-8000-000000000001', null, null, pg_temp.tok('i', 2))) ? 'grantId', 'a lesson_coach invitation');
select ok(pg_temp.keep('g_lv', pg_temp.grant_sql('owner', 'lesson_view', 'viewer.invitee@example.test', null,
            '1e920000-0000-4000-8000-000000000001', null, null, pg_temp.tok('i', 3))) ? 'grantId', 'a lesson_view invitation');
select ok(pg_temp.keep('g_fv', pg_temp.grant_sql('owner', 'film_view', 'viewer.invitee@example.test', null, null,
            'f7920000-0000-4000-8000-000000000001', null, pg_temp.tok('i', 4))) ? 'grantId', 'a film_view invitation');
select ok(pg_temp.keep('g_cv', pg_temp.grant_sql('owner', 'lesson_clip_view', 'viewer.invitee@example.test', null, null,
            null, 'c1920000-0000-4000-8000-000000000001', pg_temp.tok('i', 5))) ? 'grantId',
  'a lesson_clip_view invitation');
select ok(pg_temp.keep('g_un', pg_temp.grant_sql('owner', 'film_view', 'unconfirmed@example.test', null, null,
            'f7920000-0000-4000-8000-000000000001', null, pg_temp.tok('i', 6))) ? 'grantId',
  'an invitation for an address whose account is not confirmed yet');
select ok((select g.invitee_email_hmac = app_private.email_hmac('coach.invitee@example.test')
                  and g.project_id = 'a7920000-0000-4000-8000-000000000001'
                  and g.redeem_by <= g.created_at + interval '7 days' and g.grantee_user_id is null
             from public.access_grants g where g.id = pg_temp.got('g_pc', 'grantId')::uuid),
  '§13.2: the grant stores the HMAC of the trimmed, lower-cased email, redeemable for 7 days');
select is((select count(*)::int from public.access_grants g, app_ops.audit_events a
            where g.id = pg_temp.got('g_pc', 'grantId')::uuid
              and (to_jsonb(g)::text ilike '%invitee@%' or to_jsonb(a)::text ilike '%invitee@%')), 0,
  'the invitee''s email appears in no grant row and no audit row');
select is(pg_temp.msg(pg_temp.grant_sql('owner', 'project_coach', 'not an email',
            'a7920000-0000-4000-8000-000000000001', null, null, null, pg_temp.tok('i', 7))), 'invalid_value:invitee_email',
  'an invitation needs an invitee email (P0422)');
select is(pg_temp.msg(pg_temp.grant_sql('owner', 'film_view', 'viewer.invitee@example.test', null, null,
            'f7920000-0000-4000-8000-000000000002', null, pg_temp.tok('i', 8))), 'not_found',
  'a film_view grant needs a ready film (a preview in writing is P0404)');
select is(pg_temp.msg(pg_temp.grant_sql('owner', 'share_link', 'viewer.invitee@example.test',
            'a7920000-0000-4000-8000-000000000001', null, 'f7920000-0000-4000-8000-000000000001', null,
            pg_temp.tok('s', 9))), 'invalid_value:kind', 'share links are made by create_share_link only');

-- T-DB-58: a forwarded code is P0404 for a stranger, for every invitation kind ------------------------------------
select is(pg_temp.call(pg_temp.redeem_sql('stranger', pg_temp.tok('i', 1))),
  '{"error": "P0404", "message": "not_found"}'::jsonb, 'T-DB-58: a stranger redeeming a forwarded project_coach code is P0404');
select is(pg_temp.call(pg_temp.redeem_sql('stranger', pg_temp.tok('i', 2))),
  '{"error": "P0404", "message": "not_found"}'::jsonb, 'T-DB-58: ... a forwarded lesson_coach code is P0404');
select is(pg_temp.call(pg_temp.redeem_sql('stranger', pg_temp.tok('i', 3))),
  '{"error": "P0404", "message": "not_found"}'::jsonb, 'T-DB-58: ... a forwarded lesson_view code is P0404');
select is(pg_temp.call(pg_temp.redeem_sql('stranger', pg_temp.tok('i', 4))),
  '{"error": "P0404", "message": "not_found"}'::jsonb, 'T-DB-58: ... a forwarded film_view code is P0404');
select is(pg_temp.call(pg_temp.redeem_sql('stranger', pg_temp.tok('i', 5))),
  '{"error": "P0404", "message": "not_found"}'::jsonb, 'T-DB-58: ... a forwarded lesson_clip_view code is P0404');
select is(pg_temp.call(pg_temp.redeem_sql('stranger', pg_temp.tok('i', 99))),
  '{"error": "P0404", "message": "not_found"}'::jsonb, 'T-DB-58: identical to an unknown code');
select is(pg_temp.call(pg_temp.redeem_sql('unconfirmed', pg_temp.tok('i', 6))),
  '{"error": "P0404", "message": "not_found"}'::jsonb, 'T-DB-58: the invitee with an unconfirmed email gets P0404');
select is((select count(*)::int from public.access_grants where redeemed_at is not null or grantee_user_id is not null),
  0, 'T-DB-58: none of the refused redemptions bound a grantee');

select is(pg_temp.keep('r_lc', pg_temp.redeem_sql('coach', pg_temp.tok('i', 2))) ->> 'status', 'active',
  'T-DB-58: the intended invitee redeems the lesson_coach code');
select is(pg_temp.call(pg_temp.redeem_sql('viewer', pg_temp.tok('i', 3))) ->> 'status', 'active',
  'T-DB-58: the intended invitee redeems the lesson_view code');
select is(pg_temp.call(pg_temp.redeem_sql('viewer', pg_temp.tok('i', 4))) ->> 'status', 'active',
  'T-DB-58: the intended invitee redeems the film_view code');
select is(pg_temp.call(pg_temp.redeem_sql('viewer', pg_temp.tok('i', 5))) ->> 'status', 'active',
  'T-DB-58: the intended invitee redeems the lesson_clip_view code');
select is(pg_temp.err(pg_temp.redeem_sql('viewer', pg_temp.tok('i', 4))), 'P0404',
  'a redeemed code cannot be redeemed again');
select tests.authenticate_as('viewer');
select is((select count(*)::int from public.artifacts where id = 'f7920000-0000-4000-8000-000000000001'), 1,
  'the redeemed film_view grant shows the viewer that film');
reset role;

-- T-DB-51: a coach redemption is pending until the owner approves --------------------------------------------------
select is(pg_temp.keep('r_pc', pg_temp.redeem_sql('coach', pg_temp.tok('i', 1))) ->> 'status', 'awaiting_owner',
  'T-DB-51: redeeming the project_coach code leaves the membership pending');
select ok(pg_temp.got('r_pc', 'approvalCode') ~ '^[0-9]{6}$', 'the coach gets a 6-digit code to read to the owner');
select tests.authenticate_as('coach');
select is(app_private.has_project_role('a7920000-0000-4000-8000-000000000001', '{owner,coach}'), false,
  'T-DB-51: has_project_role is false while the membership is pending');
select is((select count(*)::int from public.projects where id = 'a7920000-0000-4000-8000-000000000001'), 0,
  'T-DB-51: the pending coach sees no project row');
reset role;
select is((pg_temp.call(format('select app_gateway.list_pending_members(%L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            'a7920000-0000-4000-8000-000000000001')) #> '{0}') - 'redeemedAt',
  jsonb_build_object('userId', pg_temp.uid('coach'), 'maskedEmail', 'c•••@e•••.test'),
  'T-DB-58: the approval view shows the verified email masked, and no display_name');
select ok(pg_temp.call(format('select app_gateway.list_pending_members(%L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            'a7920000-0000-4000-8000-000000000001'))::text not like '%Project Owner%',
  'T-DB-58: the redeemer-chosen display name never reaches the owner''s approval view');
select is(pg_temp.msg(format('select app_gateway.approve_member(%L, %L, %L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            'a7920000-0000-4000-8000-000000000001', pg_temp.uid('coach'),
            case when pg_temp.got('r_pc', 'approvalCode') = '000000' then '111111' else '000000' end)), 'code_mismatch',
  'approval needs the code the coach reads out');
select is(pg_temp.err(format('select app_gateway.approve_member(%L, %L, %L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            'a7920000-0000-4000-8000-000000000001', pg_temp.uid('coach'), pg_temp.got('r_pc', 'approvalCode'))), null,
  'T-DB-51: the owner approves with the matching code');
select tests.authenticate_as('coach');
select is(app_private.has_project_role('a7920000-0000-4000-8000-000000000001', '{coach}'), true,
  'T-DB-51: after approve_member the coach holds the coach role');
reset role;
select is(pg_temp.err(format('select app_gateway.revoke_grant(%L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            pg_temp.got('g_pc', 'grantId'))), null, 'the owner revokes the project_coach grant');
select ok((select m.revoked_at is not null and m.revoked_at = g.revoked_at
             from public.project_members m join public.access_grants g on g.id = m.grant_id
            where g.id = pg_temp.got('g_pc', 'grantId')::uuid),
  'T-DB-51: revoke_grant revoked the membership it created, in the same transaction');
select tests.authenticate_as('coach');
select is(app_private.has_project_role('a7920000-0000-4000-8000-000000000001', '{coach}'), false,
  'T-DB-51: the revoked coach holds no role at once');
reset role;

-- Share links (security-model §8.3) -------------------------------------------------------------------------------
create function pg_temp.link_sql(p_artifact uuid, p_secs int, p_audio boolean, p_token text) returns text
language sql as $$
  select format('select app_gateway.create_share_link(%L, %L, %s, %L, sha256(%L::bytea), gen_random_uuid())',
                pg_temp.uid('owner'), p_artifact, p_secs, p_audio, p_token)
$$;
select is(pg_temp.keep('l1', pg_temp.link_sql('f7920000-0000-4000-8000-000000000001', 3600, true, pg_temp.tok('s', 1)))
          ->> 'artifactId', 'f7920000-0000-4000-8000-000000000001', 'the owner shares the ready film for an hour');
select is(pg_temp.msg(pg_temp.link_sql('f7920000-0000-4000-8000-000000000001', 86401, true, pg_temp.tok('s', 2))),
  'invalid_value:expires_in_sec', 'a share link lives at most 24 hours');
select is(pg_temp.msg(pg_temp.link_sql('f7920000-0000-4000-8000-000000000003', 3600, true, pg_temp.tok('s', 3))),
  'not_shareable', 'a proxy is never shareable');
select is(pg_temp.msg(pg_temp.link_sql('f7920000-0000-4000-8000-000000000002', 3600, true, pg_temp.tok('s', 4))),
  'not_shareable', 'a preview that is not ready is not shareable');
select is(pg_temp.msg(pg_temp.link_sql('f7920000-0000-4000-8000-000000000001', 3600, false, pg_temp.tok('s', 5))),
  'audio_variant_pending', 'a film without audio waits for its verified no-audio variant');
insert into public.artifacts (id, project_id, parent_artifact_id, kind, bucket_class, r2_key, state, verified_at,
                              verification)
values ('f7920000-0000-4000-8000-000000000004', 'a7920000-0000-4000-8000-000000000001',
        'f7920000-0000-4000-8000-000000000001', 'film', 'films', 'films/a792/f1-noaudio', 'ready', now(), '{}');
select is(pg_temp.call(pg_temp.link_sql('f7920000-0000-4000-8000-000000000001', 3600, false, pg_temp.tok('s', 5)))
          ->> 'artifactId', 'f7920000-0000-4000-8000-000000000004', 'the link without audio serves the no-audio child');
select is(pg_temp.call(format('select app_gateway.redeem_share_link(sha256(%L::bytea), gen_random_uuid())',
            pg_temp.tok('s', 1))) #>> '{}', 'f7920000-0000-4000-8000-000000000001',
  'redeem_share_link authorizes the linked artifact');
select is(pg_temp.err(format('select app_gateway.revoke_grant(%L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            pg_temp.got('l1', 'shareLinkId'))), null, 'the owner revokes the share link');
select is(pg_temp.err(format('select app_gateway.redeem_share_link(sha256(%L::bytea), gen_random_uuid())',
            pg_temp.tok('s', 1))), 'P0404', 'a revoked link is P0404 on the next request');

-- Deletion requests -------------------------------------------------------------------------------------------------
create function pg_temp.delete_sql(p_actor text, p_scope text, p_target uuid, p_session uuid, p_confirm boolean)
returns text language sql as $$
  select format('select app_gateway.request_deletion(%L, %L, %L, %L, %L, gen_random_uuid())', pg_temp.uid(p_actor),
                p_scope, p_target, p_session, p_confirm)
$$;
select is(pg_temp.call(pg_temp.delete_sql('owner', 'source', '5c920000-0000-4000-8000-000000000001', null, false)),
  '{"deletionRequestId": null, "state": "dependents", "dependents": ["f7920000-0000-4000-8000-000000000001"]}'::jsonb,
  'deleting a source used in a film first lists the film (409 dependents) and starts nothing');
select is(pg_temp.keep('d1', pg_temp.delete_sql('owner', 'source', '5c920000-0000-4000-8000-000000000001', null, true))
          ->> 'state', 'requested', 'after the owner confirms, the source deletion is requested');
select is(pg_temp.call(pg_temp.delete_sql('owner', 'source', '5c920000-0000-4000-8000-000000000001', null, true))
          ->> 'deletionRequestId', pg_temp.got('d1', 'deletionRequestId'),
  'story 199: a repeated request returns the open one');
select is(pg_temp.msg(pg_temp.delete_sql('viewer', 'account', pg_temp.uid('viewer'), gen_random_uuid(), false)),
  'reauth_required', '§13.4: account deletion without a fresh Auth session is P0401 reauth_required');
insert into auth.sessions (id, user_id, created_at, updated_at) values
  ('5e920000-0000-4000-8000-000000000001', pg_temp.uid('viewer'), now() - interval '2 hours', now()),
  ('5e920000-0000-4000-8000-000000000002', pg_temp.uid('viewer'), now() - interval '2 minutes', now()),
  ('5e920000-0000-4000-8000-000000000003', pg_temp.uid('stranger'), now() - interval '1 minute', now());
select is(pg_temp.msg(pg_temp.delete_sql('viewer', 'account', pg_temp.uid('viewer'),
            '5e920000-0000-4000-8000-000000000001', false)), 'reauth_required',
  '§13.4: a session created two hours ago (only refreshed since) is not enough');
select is(pg_temp.msg(pg_temp.delete_sql('viewer', 'account', pg_temp.uid('viewer'),
            '5e920000-0000-4000-8000-000000000003', false)), 'reauth_required',
  '§13.4: another user''s fresh session is refused');
select is(pg_temp.call(pg_temp.delete_sql('viewer', 'account', pg_temp.uid('viewer'),
            '5e920000-0000-4000-8000-000000000002', false)) ->> 'state', 'requested',
  '§13.4: a session created two minutes ago may request the account deletion');
select is(pg_temp.call(pg_temp.delete_sql('owner', 'project', 'a7920000-0000-4000-8000-000000000001', null, false))
          ->> 'state', 'requested', 'the owner requests the project deletion');
select ok((select deleted_at is not null from public.projects where id = 'a7920000-0000-4000-8000-000000000001'),
  'the project is hidden at once (deleted_at set)');

-- T-DB-47 (command half): every secret-minting command above took a hash; no jv*_ token is anywhere ---------------
create function pg_temp.secret_rows() returns int language plpgsql as $$
declare
  v_table regclass;
  v_n     int := 0;
  v_c     int;
begin
  for v_table in select c.oid::regclass from pg_class c
                  where c.relkind = 'r' and (c.relnamespace = 'app_ops'::regnamespace
                                             or c.oid in ('public.access_grants'::regclass,
                                                          'public.camera_invites'::regclass))
  loop
    execute format('select count(*) from %s t where to_jsonb(t)::text ~ ''jv[igslhc]_''', v_table) into v_c;
    v_n := v_n + v_c;
  end loop;
  return v_n;
end $$;
select is(pg_temp.secret_rows(), 0, 'T-DB-47: no jv[igslhc]_ value in any app_ops row, grant or invite');

select * from finish();
rollback;
