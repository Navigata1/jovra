-- Render-host reads and writes (S80 / B-06, finding 13's database half): authorize_output_upload_for_attempt,
-- attach_upload_id_for_attempt, record_part_for_attempt, complete_upload_check_for_attempt,
-- mark_output_written_for_attempt, authorize_attempt_input and authorize_artifact_read_for_attempt as
-- jovra_orchestrator (security-model §4.1, §13.1, §13.15; architecture §5.1 internal routes, §6.1-§6.3). The output ref
-- must be in the attempt's output_plan and within its byte cap (finding 32), a stale or expired lease is refused
-- (T-DB-37 for the upload path), a session belongs to the attempt that opened it, the user upload commands refuse a
-- render-host session (T-DB-57), an input must be in the attempt's input_refs, the verify stage reads only its listed
-- inputs and the job's outputs awaiting it, finish_attempt registers only outputs the attempt wrote, and an attempt
-- that ends leaves no upload open. Threats S4, T6 and T8 (render host impersonated or reading what it was not given).
-- Rolls back.
begin;
select plan(49);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('owner_b');
grant jovra_gateway to postgres;
grant jovra_orchestrator to postgres;
insert into app_ops.settings (env) values ('local') on conflict (id) do update set env = excluded.env;
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
values ('environment', null, 1000000000000, 50000000);

create function pg_temp.call(p_role text, p_sql text) returns jsonb language plpgsql as $$
declare
  v_out   jsonb;
  v_text  text;
  v_state text;
  v_msg   text;
begin
  execute format('set local role %I', p_role);
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
create function pg_temp.orch(p_sql text) returns jsonb language sql as $$ select pg_temp.call('jovra_orchestrator', p_sql) $$;
create function pg_temp.gw(p_sql text) returns jsonb language sql as $$ select pg_temp.call('jovra_gateway', p_sql) $$;
create temp table t_out (k text primary key, v jsonb not null);
create function pg_temp.keep(p_key text, p_v jsonb) returns jsonb language plpgsql as $$
begin
  insert into pg_temp.t_out (k, v) values (p_key, p_v) on conflict (k) do update set v = excluded.v;
  return p_v;
end $$;
create function pg_temp.got(p_key text, p_field text) returns text language sql as $$
  select v ->> p_field from pg_temp.t_out where k = p_key
$$;
create function pg_temp.uid(p_who text) returns uuid language sql as $$ select tests.get_supabase_uid(p_who) $$;
create function pg_temp.job() returns uuid language sql as $$ select pg_temp.got('j', 'jobId')::uuid $$;
create function pg_temp.move(p_to text) returns text language plpgsql as $$
declare
  v jsonb;
begin
  v := pg_temp.orch(format('select app_gateway.set_job_state(%L, %L, %L, null, gen_random_uuid())',
                           pg_temp.job(), (select state from public.render_jobs where id = pg_temp.job()), p_to));
  return coalesce(v ->> 'message', v ->> 'state');
end $$;
create function pg_temp.walk(p_states text[]) returns text language plpgsql as $$
declare
  s text;
  r text;
begin
  foreach s in array p_states loop
    r := pg_temp.move(s);
    if r is distinct from s then
      return 'stopped at ' || s || ': ' || coalesce(r, 'null');
    end if;
  end loop;
  return 'ok';
end $$;
-- Reserve and claim one attempt: keeps {attemptId, leaseToken} under p_key.
create function pg_temp.start(p_key text, p_stage text, p_attempt int) returns jsonb language plpgsql as $$
declare
  v_try   jsonb := pg_temp.orch(format('select app_gateway.reserve_stage(%L, %L, %s, gen_random_uuid())',
                                       pg_temp.job(), p_stage, p_attempt));
  v_claim jsonb := pg_temp.orch(format('select app_gateway.claim_attempt(%L, ''host-1'', ''local-test'', '
                                       'gen_random_uuid())', v_try ->> 'attemptId'));
begin
  return pg_temp.keep(p_key, jsonb_build_object('attemptId', v_try ->> 'attemptId', 'state', v_try ->> 'state',
                                                'leaseToken', v_claim ->> 'leaseToken'));
end $$;
-- One host command of attempt p_key: app_gateway.<p_fn>(attempt, SHA-256 of its lease token, <p_rest>, request id).
-- p_token overrides the attempt's own token (a forged or another attempt's lease).
create function pg_temp.host(p_fn text, p_key text, p_rest text, p_token text default null) returns jsonb
language sql as $$
  select pg_temp.orch(format('select app_gateway.%s(%L, sha256(convert_to(%L, ''UTF8'')), %s, gen_random_uuid())',
                             p_fn, pg_temp.got(p_key, 'attemptId'), coalesce(p_token, pg_temp.got(p_key, 'leaseToken')),
                             p_rest))
$$;
create function pg_temp.authorize(p_key text, p_ref text, p_bytes bigint, p_sha text, p_token text default null)
returns jsonb language sql as $$
  select pg_temp.host('authorize_output_upload_for_attempt', p_key,
                      format('%L, %s, sha256(%L::bytea)', p_ref, p_bytes, p_sha), p_token)
$$;
create function pg_temp.sess(p_key text) returns app_ops.upload_sessions language sql as $$
  select u.* from app_ops.upload_sessions u where u.id = pg_temp.got(p_key, 'sessionId')::uuid
$$;
create function pg_temp.art(p_id text) returns public.artifacts language sql as $$
  select a.* from public.artifacts a where a.id = p_id::uuid
$$;
create function pg_temp.outputs(p_ref text, p_bytes bigint, p_sha text) returns text language sql as $$
  select jsonb_build_array(jsonb_build_object('outputRef', p_ref, 'bytes', p_bytes,
                                              'sha256', encode(sha256(p_sha::bytea), 'hex')))::text
$$;
create function pg_temp.finish(p_key text, p_outputs text) returns jsonb language sql as $$
  select pg_temp.host('finish_attempt', p_key,
                      format('''succeeded'', %L::jsonb, ''{"wallMs": 1000, "cpuMs": 1000, "bytesIn": 1000, '
                             '"bytesOut": 1000}''::jsonb, null, null, null', p_outputs))
$$;

-- Fixtures: project A with two verified sources (stored under their R2 keys and verified etags) in its current
-- manifest, plan P1 with version V1 and job J (create_quote and accept_quote), moved to normalizing; project B of
-- owner_b with its own verified source.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a8500000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Club final'),
  ('b8500000-0000-4000-8000-000000000001', pg_temp.uid('owner_b'), gen_random_uuid(), 'Ladder match');
insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, declared_sha256,
                                   verified_sha256, verified_etag, r2_key) values
  ('5c850000-0000-4000-8000-000000000001', 'a8500000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s1'::bytea), sha256('s1'::bytea), '"etag-s1"',
   'staging/p/a8500000-0000-4000-8000-000000000001/s/5c850000-0000-4000-8000-000000000001/original/1'),
  ('5c850000-0000-4000-8000-000000000002', 'a8500000-0000-4000-8000-000000000001', 'opposite_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s2'::bytea), sha256('s2'::bytea), '"etag-s2"',
   'staging/p/a8500000-0000-4000-8000-000000000001/s/5c850000-0000-4000-8000-000000000002/original/1'),
  ('5c850000-0000-4000-8000-0000000000b1', 'b8500000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('sb'::bytea), sha256('sb'::bytea), '"etag-sb"',
   'staging/p/b8500000-0000-4000-8000-000000000001/s/5c850000-0000-4000-8000-0000000000b1/original/1');
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a8500000-0000-4000-8000-000000000001',
   '{"sources": [{"sourceId": "5c850000-0000-4000-8000-000000000001"},
                 {"sourceId": "5c850000-0000-4000-8000-000000000002"}]}', sha256('ma'::bytea), 'render');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a850000-0000-4000-8000-000000000001', 'a8500000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan P1');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a850000-0000-4000-8000-000000000001', '9a850000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}');
select pg_temp.keep('q', pg_temp.gw(format(
  'select app_gateway.create_quote(%L, %L, %L, %L, ''heuristic'', %L::jsonb, %L::uuid[], 7, gen_random_uuid())',
  pg_temp.uid('owner'), 'a8500000-0000-4000-8000-000000000001', '9a850000-0000-4000-8000-000000000001',
  '5a850000-0000-4000-8000-000000000001',
  '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9","container":"mp4","videoCodec":"h264",
    "audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}',
  array['5c850000-0000-4000-8000-000000000001', '5c850000-0000-4000-8000-000000000002']::uuid[])));
select pg_temp.keep('j', pg_temp.gw(format(
  'select app_gateway.accept_quote(%L, %L, decode(%L, ''hex''), %L::jsonb, %s, ''key-j'', gen_random_uuid())',
  pg_temp.uid('owner'), pg_temp.got('q', 'quoteId'), pg_temp.got('q', 'inputsSha256'),
  '{"at": "2026-11-08T10:00:00Z", "consentRecordId": "consent-s80", "consentTextVersion": "studio-cloud-consent@1.0.0",
    "modelProvider": false, "retentionDays": 7, "textClasses": [], "uploadSelectedSources": true}',
  pg_temp.got('q', 'capCredits'))));
select is(pg_temp.walk(array['upload_pending', 'queued', 'normalizing']), 'ok',
  'fixture: job J is consented by the owner and moved to normalizing');
select pg_temp.start('a1', 'normalize', 1);
select pg_temp.start('b1', 'cleanup', 1);

-- authorize_output_upload_for_attempt: lease first, then the attempt's own output plan and caps ------------------
select is(pg_temp.authorize('a1', 'analysis-proxy-1', 70000000, 'ap', 'jvl_forged') ->> 'message', 'stale_lease',
  'T-DB-37 (upload path): an output upload with another lease token is P0409 stale_lease');
select is(pg_temp.orch($$select app_gateway.authorize_output_upload_for_attempt(gen_random_uuid(), sha256('x'::bytea),
                          'analysis-proxy-1', 1000, sha256('ap'::bytea), gen_random_uuid())$$) ->> 'error', 'P0404',
  'an output upload for an unknown attempt is P0404');
select is(pg_temp.authorize('a1', 'film', 1000, 'f') ->> 'message', 'output_not_in_plan',
  'an output ref the normalize stage''s stored output_plan does not list (film) is refused (P0422)');
select is(pg_temp.authorize('a1', 'pts-table-1', 67108865, 'pts') ->> 'message', 'output_over_cap',
  'finding 32: declared bytes one above the plan''s cap for that output (64 MiB for a PTS table) are refused (P0422)');
select is(pg_temp.authorize('a1', 'analysis-proxy-1', 0, 'ap') ->> 'message', 'invalid_value:declared_bytes',
  'an empty output cannot be declared');
select ok((pg_temp.keep('s1', pg_temp.authorize('a1', 'analysis-proxy-1', 70000000, 'ap'))
           @> jsonb_build_object('partCount', 3, 'partSize', 33554432, 'bucketClass', 'work', 'replayed', false,
                                 'state', 'opening', 'outputRef', 'analysis-proxy-1',
                                 'r2Key', 'proxies/p/a8500000-0000-4000-8000-000000000001/j/' || pg_temp.job() || '/'
                                          || pg_temp.got('a1', 'attemptId') || '/analysis-proxy-1'))
          and not (pg_temp.got('s1', 'sessionId') is null),
  'a planned output within its cap opens a 3-part session under the server-generated key of the work bucket');
select ok((select a.state = 'writing' and a.kind = 'analysis_proxy' and a.job_id = pg_temp.job()
                  and a.attempt_id = pg_temp.got('a1', 'attemptId')::uuid and a.bytes is null and a.sha256 is null
                  and a.verified_at is null and a.r2_key = (pg_temp.sess('s1')).r2_key
             from public.artifacts a where a.id = pg_temp.got('s1', 'artifactId')::uuid)
          and (select u.actor_kind = 'render_host' and u.attempt_id = pg_temp.got('a1', 'attemptId')::uuid
                      and u.output_ref = 'analysis-proxy-1' and u.source_id is null and u.capability_hash is null
                      and u.expected_bytes = 70000000 and u.expected_sha256 = sha256('ap'::bytea)
                 from app_ops.upload_sessions u where u.id = pg_temp.got('s1', 'sessionId')::uuid),
  'the output is a writing artifact of the job and attempt; its session names the attempt and output and holds no '
  'capability (the lease token is the host''s only credential)');
select ok(pg_temp.authorize('a1', 'analysis-proxy-1', 70000000, 'ap')
          @> jsonb_build_object('sessionId', pg_temp.got('s1', 'sessionId'), 'replayed', true),
  'a redelivered authorization returns the same open session');
select is(pg_temp.authorize('a1', 'analysis-proxy-1', 70000000, 'other') ->> 'message', 'declaration_mismatch',
  'a second declaration of the same output with other bytes is P0409 declaration_mismatch');

-- T-DB-57: the session protocol is fenced by the attempt; user commands refuse it --------------------------------
select ok(pg_temp.gw(format('select app_gateway.record_part(%L, sha256(''x''::bytea), 1, 33554432, ''e'', '
                            'sha256(''p''::bytea), sha256(''p''::bytea), gen_random_uuid())',
                            pg_temp.got('s1', 'sessionId'))) ->> 'message' = 'not_found'
          and pg_temp.gw(format('select app_gateway.complete_upload_check(%L, sha256(''x''::bytea), ''[]'', '
                                'gen_random_uuid())', pg_temp.got('s1', 'sessionId'))) ->> 'message' = 'not_found',
  'T-DB-57: the user commands record_part and complete_upload_check refuse a render-host session (P0404)');
select is(pg_temp.host('attach_upload_id_for_attempt', 'b1', format('%L, ''upload-a1''', pg_temp.got('s1', 'sessionId')))
          ->> 'message', 'not_found',
  'a session belongs to the attempt that opened it: another attempt''s current lease cannot touch it (P0404)');
select ok(not (pg_temp.host('attach_upload_id_for_attempt', 'a1',
                            format('%L, ''upload-a1''', pg_temp.got('s1', 'sessionId'))) ? 'error')
          and (pg_temp.sess('s1')).state = 'open' and (pg_temp.sess('s1')).r2_upload_id = 'upload-a1',
  'the attempt records the multipart upload id; the session is open');
select is(pg_temp.host('record_part_for_attempt', 'a1', format('%L, 1, 1000, ''e1'', sha256(''p1''::bytea), '
                       'sha256(''p1''::bytea)', pg_temp.got('s1', 'sessionId'))) ->> 'message', 'invalid_value:part_bytes',
  'a part that is not exactly 32 MiB (except the last) is refused');
select is(pg_temp.host('record_part_for_attempt', 'a1', format('%L, 1, 33554432, ''e1'', sha256(''p1''::bytea), '
                       'sha256(''other''::bytea)', pg_temp.got('s1', 'sessionId'))) ->> 'message', 'part_digest_mismatch',
  'a part whose streamed SHA-256 differs from the host''s digest is refused');
select is(pg_temp.host('record_part_for_attempt', 'a1', format('%L, 1, 33554432, ''e1'', sha256(''p1''::bytea), '
                       'sha256(''p1''::bytea)', pg_temp.got('s1', 'sessionId'))) ->> 'etag', 'e1', 'part 1 is recorded');
select is(pg_temp.host('complete_upload_check_for_attempt', 'a1', format('%L, ''[{"n": 1, "etag": "e1"}]''',
                       pg_temp.got('s1', 'sessionId'))) ->> 'message', 'parts_incomplete',
  'completion with parts 2 and 3 missing is P0409 parts_incomplete');
select is(pg_temp.host('record_part_for_attempt', 'a1', format('%L, 2, 33554432, ''e2'', sha256(''p2''::bytea), '
                       'sha256(''p2''::bytea)', pg_temp.got('s1', 'sessionId'))) ->> 'etag'
          || ' ' || (pg_temp.host('record_part_for_attempt', 'a1', format('%L, 3, 2891136, ''e3'', sha256(''p3''::bytea), '
                       'sha256(''p3''::bytea)', pg_temp.got('s1', 'sessionId'))) ->> 'etag'),
  'e2 e3', 'parts 2 and 3 (the last, 70,000,000 - 2 x 32 MiB = 2,891,136 bytes) are recorded');
select is(pg_temp.host('complete_upload_check_for_attempt', 'a1',
                       format('%L, ''[{"n": 1, "etag": "e1"}, {"n": 2, "etag": "e2"}, {"n": 3, "etag": "forged"}]''',
                              pg_temp.got('s1', 'sessionId'))) ->> 'message', 'parts_mismatch',
  'a part list that differs from the stored one is P0409 parts_mismatch');
select is(pg_temp.host('complete_upload_check_for_attempt', 'a1',
                       format('%L, ''[{"n": 3, "etag": "e3"}, {"n": 1, "etag": "e1"}, {"n": 2, "etag": "e2"}]''',
                              pg_temp.got('s1', 'sessionId'))) -> 'parts',
  '[{"n": 1, "etag": "e1"}, {"n": 2, "etag": "e2"}, {"n": 3, "etag": "e3"}]'::jsonb,
  'the completion check returns the stored parts in order, the only list R2''s complete() is given');
select is(pg_temp.host('mark_output_written_for_attempt', 'a1', format('%L, 69999999', pg_temp.got('s1', 'sessionId')))
          ->> 'message', 'size_mismatch', 'an object whose R2 size differs from the declaration is refused');
select ok((pg_temp.host('mark_output_written_for_attempt', 'a1', format('%L, 70000000', pg_temp.got('s1', 'sessionId')))
           ->> 'state') = 'writing'
          and (pg_temp.sess('s1')).state = 'completed'
          and (select a.state = 'writing' and a.bytes = 70000000 and a.sha256 = sha256('ap'::bytea)
                 from public.artifacts a where a.id = pg_temp.got('s1', 'artifactId')::uuid),
  'the written output keeps state writing, now with its bytes and declared SHA-256, until finish_attempt reports it');
select is(pg_temp.authorize('a1', 'analysis-proxy-1', 70000000, 'ap') ->> 'message', 'output_already_written',
  'a written output cannot be authorized again within the attempt');

-- authorize_attempt_input: only what the attempt's stored input_refs list -----------------------------------------
select ok(pg_temp.host('authorize_attempt_input', 'a1', quote_literal('5c850000-0000-4000-8000-000000000001'))
          @> jsonb_build_object('kind', 'source', 'bucketClass', 'work', 'verifiedEtag', '"etag-s1"',
                                'r2Key', 'staging/p/a8500000-0000-4000-8000-000000000001/s/'
                                         || '5c850000-0000-4000-8000-000000000001/original/1'),
  'a listed source is read under its R2 key and the etag it was verified at (T-R2-15)');
select ok(pg_temp.host('authorize_attempt_input', 'a1', quote_literal('5c850000-0000-4000-8000-0000000000b1'))
          ->> 'message' = 'input_not_listed'
          and pg_temp.host('authorize_attempt_input', 'a1', 'gen_random_uuid()') ->> 'message' = 'input_not_listed'
          and pg_temp.host('authorize_attempt_input', 'a1', quote_literal(pg_temp.got('s1', 'artifactId')))
              ->> 'message' = 'input_not_listed',
  'another project''s source, an unknown id and the attempt''s own unverified output are not in input_refs (P0404)');
select is(pg_temp.host('authorize_attempt_input', 'a1', quote_literal('5c850000-0000-4000-8000-000000000001'),
                       'jvl_forged') ->> 'message', 'stale_lease', 'an input read with another lease token is refused');
update public.camera_sources set state = 'rejected', rejected_reason = 'hash_mismatch'
 where id = '5c850000-0000-4000-8000-000000000002';
select is(pg_temp.host('authorize_attempt_input', 'a1', quote_literal('5c850000-0000-4000-8000-000000000002'))
          ->> 'error', 'P0410', 'a listed source rejected since the reservation is gone (P0410), never read');
update public.camera_sources set state = 'verified', rejected_reason = null where id = '5c850000-0000-4000-8000-000000000002';
select is(pg_temp.host('authorize_artifact_read_for_attempt', 'a1', 'gen_random_uuid()') ->> 'message',
  'not_verify_stage', 'only the verify_output stage reads artifacts through authorize_artifact_read_for_attempt');

-- finish_attempt registers only outputs the attempt wrote ---------------------------------------------------------
select pg_temp.keep('s2', pg_temp.authorize('a1', 'render-proxy-1', 1000, 'rp'));
select is(pg_temp.finish('a1', pg_temp.outputs('pts-table-1', 1000, 'pts')) ->> 'message', 'output_not_written',
  'a planned output that was never written cannot be reported (P0409 output_not_written)');
select is(pg_temp.finish('a1', pg_temp.outputs('render-proxy-1', 1000, 'rp')) ->> 'message', 'output_not_written',
  'an output whose upload is still open cannot be reported either');
select is(pg_temp.finish('a1', pg_temp.outputs('analysis-proxy-1', 70000000, 'other')) ->> 'message', 'output_mismatch',
  'a reported output with other bytes than were written is P0409 output_mismatch');
select ok((select state = 'running' and charged_cost_micro_usd is null from public.render_attempts
            where id = pg_temp.got('a1', 'attemptId')::uuid)
          and (pg_temp.art(pg_temp.got('s1', 'artifactId'))).state = 'writing',
  'the refused results changed nothing: no charge, the attempt runs, the output is still writing');
select is(pg_temp.keep('f1', pg_temp.finish('a1', pg_temp.outputs('analysis-proxy-1', 70000000, 'ap'))) ->> 'state',
  'succeeded', 'the attempt succeeds reporting the output it wrote');
select ok(pg_temp.got('f1', 'outputRefs')::jsonb = jsonb_build_array(pg_temp.got('s1', 'artifactId'))
          and (pg_temp.art(pg_temp.got('s1', 'artifactId'))).state = 'verifying'
          and (pg_temp.art(pg_temp.got('s2', 'artifactId'))).state = 'failed'
          and (pg_temp.sess('s2')).state = 'aborted'
          and (select count(*) = 2 from public.artifact_sources where artifact_id = pg_temp.got('s1', 'artifactId')::uuid),
  'the written output moves to verifying with both sources recorded; the unreported one is failed and its session '
  'aborted');
select is(pg_temp.host('record_part_for_attempt', 'a1', format('%L, 1, 1000, ''e1'', sha256(''p1''::bytea), '
                       'sha256(''p1''::bytea)', pg_temp.got('s2', 'sessionId'))) ->> 'message', 'not_running',
  'a finished attempt writes nothing more');

-- An expired lease ends the attempt's uploads -----------------------------------------------------------------------
select is(pg_temp.keep('s3', pg_temp.authorize('b1', 'cleanup-report', 2048, 'cr')) ->> 'replayed', 'false',
  'the cleanup attempt opens a session for its report');
update public.render_attempts set leased_until = now() - interval '1 second'
 where id = pg_temp.got('b1', 'attemptId')::uuid;
select is(pg_temp.host('attach_upload_id_for_attempt', 'b1', format('%L, ''upload-b1''', pg_temp.got('s3', 'sessionId')))
          ->> 'message', 'lease_expired', 'T-DB-37 (upload path): the right token past leased_until is P0409 lease_expired');
select ok(pg_temp.orch('select app_gateway.expire_attempt_leases(gen_random_uuid())')::text = '1'
          and (pg_temp.sess('s3')).state = 'aborted' and (pg_temp.art(pg_temp.got('s3', 'artifactId'))).state = 'failed',
  'the reconciler''s sweep aborts the expired attempt''s session and fails its unfinished output');

-- authorize_artifact_read_for_attempt: the verify stage's listed inputs and the job's outputs awaiting it ------------
insert into public.artifacts (id, project_id, job_id, kind, bucket_class, r2_key, bytes, sha256, state, verified_at,
                              verification) values
  ('f8500000-0000-4000-8000-000000000001', 'a8500000-0000-4000-8000-000000000001', pg_temp.job(), 'edit_manifest',
   'work', 'frames/s80-05/listed', 100, sha256('y'::bytea), 'ready', now(), '{"decoded": true}');
insert into public.artifacts (id, project_id, kind, bucket_class, r2_key, state, verified_at, verification) values
  ('f8500000-0000-4000-8000-000000000002', 'a8500000-0000-4000-8000-000000000001', 'edit_manifest', 'work',
   'frames/s80-05/other-job', 'ready', now(), '{"decoded": true}'),
  ('f8500000-0000-4000-8000-000000000003', 'b8500000-0000-4000-8000-000000000001', 'edit_manifest', 'work',
   'frames/s80-05/project-b', 'ready', now(), '{"decoded": true}');
select is(pg_temp.walk(array['planning', 'preview_rendering', 'final_rendering', 'verifying']), 'ok',
  'J moves on to verifying');
select is(pg_temp.start('v1', 'verify_output', 1) ->> 'state', 'reserved', 'the verify stage is reserved and claimed');
select ok(pg_temp.host('authorize_artifact_read_for_attempt', 'v1', quote_literal(pg_temp.got('s1', 'artifactId')))
          @> jsonb_build_object('artifactId', pg_temp.got('s1', 'artifactId'), 'state', 'verifying',
                                'r2Key', (pg_temp.sess('s1')).r2_key, 'bytes', 70000000),
  'the verify stage reads the output another attempt of its job wrote and that waits for verification');
select ok(pg_temp.host('authorize_artifact_read_for_attempt', 'v1', quote_literal('f8500000-0000-4000-8000-000000000001'))
          @> '{"state": "ready", "r2Key": "frames/s80-05/listed"}'::jsonb,
  'the verify stage reads a ready artifact listed in its input_refs');
select ok(pg_temp.host('authorize_artifact_read_for_attempt', 'v1', quote_literal('f8500000-0000-4000-8000-000000000002'))
          ->> 'message' = 'not_found'
          and pg_temp.host('authorize_artifact_read_for_attempt', 'v1',
                           quote_literal('f8500000-0000-4000-8000-000000000003')) ->> 'message' = 'not_found'
          and pg_temp.host('authorize_artifact_read_for_attempt', 'v1', quote_literal(pg_temp.got('s2', 'artifactId')))
              ->> 'message' = 'not_found',
  'another job''s artifact, another project''s artifact and a failed output are not the verify stage''s to read (P0404)');
select is(pg_temp.host('authorize_artifact_read_for_attempt', 'v1', quote_literal(pg_temp.got('s1', 'artifactId')),
                       'jvl_forged') ->> 'message', 'stale_lease', 'an artifact read with another lease token is refused');
select ok(pg_temp.host('authorize_attempt_input', 'v1', quote_literal(pg_temp.got('s1', 'artifactId'))) ->> 'message'
            = 'input_not_listed'
          and pg_temp.host('authorize_attempt_input', 'v1', quote_literal('f8500000-0000-4000-8000-000000000001'))
              @> '{"kind": "edit_manifest", "r2Key": "frames/s80-05/listed"}'::jsonb,
  'authorize_attempt_input stays limited to input_refs for the verify stage too');

-- Cancel ends the open attempts' uploads; the audit trail; T-DB-47 -----------------------------------------------
select pg_temp.keep('s4', pg_temp.authorize('v1', 'verify-report', 512, 'vr'));
select is(pg_temp.move('canceled'), 'canceled', 'the job is canceled');
select ok((pg_temp.sess('s4')).state = 'aborted' and (pg_temp.art(pg_temp.got('s4', 'artifactId'))).state = 'failed'
          and (select state = 'canceled' from public.render_attempts where id = pg_temp.got('v1', 'attemptId')::uuid),
  'canceling the job aborts the canceled attempt''s open session and fails its unfinished output');
select is((select array_agg(action || ' ' || actor_kind || ' ' || outcome order by id) from app_ops.audit_events
            where action in ('attempt.output_authorize', 'attempt.output_written')),
  array['attempt.output_authorize orchestrator allowed', 'attempt.output_written orchestrator allowed',
        'attempt.output_authorize orchestrator allowed', 'attempt.output_authorize orchestrator allowed',
        'attempt.output_authorize orchestrator allowed'],
  'each opened session and each written output leaves one audit row (redeliveries and refusals leave none)');
create function pg_temp.secret_rows() returns int language plpgsql as $$
declare
  v_table regclass;
  v_n     int := 0;
  v_c     int;
begin
  for v_table in select c.oid::regclass from pg_class c
                  where c.relkind = 'r' and (c.relnamespace = 'app_ops'::regnamespace
                                             or c.oid in ('public.render_attempts'::regclass,
                                                          'public.artifacts'::regclass))
  loop
    execute format('select count(*) from %s t where to_jsonb(t)::text ~ ''jv[igslhc]_''', v_table) into v_c;
    v_n := v_n + v_c;
  end loop;
  return v_n;
end $$;
select is(pg_temp.secret_rows(), 0,
  'T-DB-47: no lease token is stored in an upload session, part, artifact, attempt or audit row');

select * from finish();
rollback;
