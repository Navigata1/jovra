-- Orchestrator stage commands (S80 / B-06): set_job_state, reserve_stage, claim_attempt, finish_attempt and
-- mark_artifact_verified as jovra_orchestrator. T-DB-36 (beyond the cap is P0402; the same (job, stage, attempt) twice is
-- one attempt row), T-DB-55 (the estimate is computed in SQL and never zero; input_refs hold only the job project's
-- verified sources and this job's verified artifacts), T-DB-72 SQL half (the planner budget follows the stage
-- reservation; an overrun is committed and stops the job; the next reservation sees it), T-DB-53 (verifying -> ready
-- without a verified film is P0409; with one the hold settles), consumption once per (job, stage) and the transition
-- table. User stories 193 (real stages, each with its own state) and 199 (a retry never charges twice). Rolls back.
-- Expected values are worked by hand from the rate card rates-v0-inferred: 2 sources x 100,000,000 bytes (191 MiB),
-- 120 s output: normalize max(5,000, 191 x 20 = 3,820) = 5,000; plan 1,000; final render 1,500 x 120 x 2 = 360,000;
-- verify 2,000; a model planner call (8 x 1,500 + 8,000) input tokens x 3 + 2,000 output tokens x 15 = 90,000; container
-- time 60 micro-USD per second. Quote caps from the S79 worked example: heuristic 455,584, model 705,584.
begin;
select plan(62);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('owner_b');
grant jovra_gateway to postgres;
grant jovra_orchestrator to postgres;
insert into app_ops.settings (env) values ('local') on conflict (id) do update set env = excluded.env;
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
values ('environment', null, 1000000000000, 50000000);

-- Run one command as a command role; the result is its jsonb, or {"error": SQLSTATE, "message": ...}.
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
create function pg_temp.quote_sql(p_plan uuid, p_version uuid, p_planner text) returns text language sql as $$
  select format('select app_gateway.create_quote(%L, %L, %L, %L, %L, %L::jsonb, %L::uuid[], 7, gen_random_uuid())',
                pg_temp.uid('owner'), 'a8000000-0000-4000-8000-000000000001', p_plan, p_version, p_planner,
                '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9","container":"mp4",
                  "videoCodec":"h264","audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}',
                array['5c800000-0000-4000-8000-000000000001', '5c800000-0000-4000-8000-000000000002']::uuid[])
$$;
create function pg_temp.accept_sql(p_quote_key text, p_key text, p_model boolean) returns text language sql as $$
  select format('select app_gateway.accept_quote(%L, %L, decode(%L, ''hex''), %L::jsonb, %s, %L, gen_random_uuid())',
                pg_temp.uid('owner'), pg_temp.got(p_quote_key, 'quoteId'), pg_temp.got(p_quote_key, 'inputsSha256'),
                jsonb_build_object('at', '2026-11-08T10:00:00Z', 'consentRecordId', 'consent-s80',
                                   'consentTextVersion', 'studio-cloud-consent@1.0.0', 'modelProvider', p_model,
                                   'retentionDays', 7, 'textClasses', '[]'::jsonb, 'uploadSelectedSources', true),
                pg_temp.got(p_quote_key, 'capCredits'), p_key)
$$;
-- Move a job from its current state to p_to through set_job_state; returns the new state or the refusal message.
create function pg_temp.move(p_job uuid, p_to text) returns text language plpgsql as $$
declare
  v jsonb;
begin
  v := pg_temp.orch(format('select app_gateway.set_job_state(%L, %L, %L, null, gen_random_uuid())',
                           p_job, (select state from public.render_jobs where id = p_job), p_to));
  return coalesce(v ->> 'message', v ->> 'state');
end $$;
create function pg_temp.walk(p_job uuid, p_states text[]) returns text language plpgsql as $$
declare
  s text;
  r text;
begin
  foreach s in array p_states loop
    r := pg_temp.move(p_job, s);
    if r is distinct from s then
      return 'stopped at ' || s || ': ' || coalesce(r, 'null');
    end if;
  end loop;
  return 'ok';
end $$;
create function pg_temp.reserve_sql(p_job uuid, p_stage text, p_attempt int) returns text language sql as $$
  select format('select app_gateway.reserve_stage(%L, %L, %s, gen_random_uuid())', p_job, p_stage, p_attempt)
$$;
create function pg_temp.claim_sql(p_attempt text) returns text language sql as $$
  select format('select app_gateway.claim_attempt(%L, ''host-1'', ''local-test'', gen_random_uuid())', p_attempt)
$$;
create function pg_temp.m(p_wall_ms bigint, p_in bigint default null, p_out bigint default null) returns jsonb
language sql as $$
  select jsonb_build_object('wallMs', p_wall_ms, 'cpuMs', p_wall_ms, 'bytesIn', 1000, 'bytesOut', 1000)
         || case when p_in is null then '{}'::jsonb
                 else jsonb_build_object('plannerTokens', jsonb_build_object('input', p_in, 'cache', 0, 'output', p_out))
            end
$$;
create function pg_temp.finish_sql(p_attempt text, p_token text, p_outcome text, p_outputs jsonb, p_m jsonb,
                                   p_err text default null, p_retry boolean default null, p_version uuid default null)
returns text language sql as $$
  select format('select app_gateway.finish_attempt(%L, sha256(convert_to(%L, ''UTF8'')), %L, %L::jsonb, %L::jsonb, '
                '%L, %L::boolean, %L::uuid, gen_random_uuid())',
                p_attempt, p_token, p_outcome, p_outputs, p_m, p_err, p_retry, p_version)
$$;
create function pg_temp.hold(p_job_key text) returns public.usage_reservations language sql as $$
  select r.* from public.usage_reservations r where r.id = pg_temp.got(p_job_key, 'reservationId')::uuid
$$;
create function pg_temp.job(p_job_key text) returns uuid language sql as $$ select pg_temp.got(p_job_key, 'jobId')::uuid $$;
create function pg_temp.sha(p_text text) returns text language sql as $$ select encode(sha256(p_text::bytea), 'hex') $$;
create function pg_temp.today_stage_total() returns bigint language sql as $$
  select coalesce(sum(amount_micro_usd), 0)::bigint from app_ops.spend_commitments
   where at >= date_trunc('day', now(), 'UTC') and kind in ('stage_reserve', 'stage_overrun')
$$;

-- Fixtures (server writes, as postgres): project A of owner with verified sources S1, S2 and a declared S3 in manifest
-- revision 1, plans P1 (version V1), P3 and P4; project B of owner_b with a verified source.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a8000000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Club final'),
  ('b8000000-0000-4000-8000-000000000001', pg_temp.uid('owner_b'), gen_random_uuid(), 'Other match');
insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, declared_sha256) values
  ('5c800000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s1'::bytea)),
  ('5c800000-0000-4000-8000-000000000002', 'a8000000-0000-4000-8000-000000000001', 'opposite_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s2'::bytea)),
  ('5c800000-0000-4000-8000-000000000003', 'a8000000-0000-4000-8000-000000000001', 'near_deuce_corner',
   gen_random_uuid(), 'declared', 100000000, sha256('s3'::bytea)),
  ('5b800000-0000-4000-8000-000000000001', 'b8000000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('sb'::bytea));
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a8000000-0000-4000-8000-000000000001',
   '{"sources": [{"sourceId": "5c800000-0000-4000-8000-000000000001"},
                 {"sourceId": "5c800000-0000-4000-8000-000000000002"},
                 {"sourceId": "5c800000-0000-4000-8000-000000000003"}]}', sha256('ma'::bytea), 'render'),
  ('b8000000-0000-4000-8000-000000000001',
   '{"sources": [{"sourceId": "5b800000-0000-4000-8000-000000000001"}]}', sha256('mb'::bytea), 'render');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a800000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan P1'),
  ('9a800000-0000-4000-8000-000000000003', 'a8000000-0000-4000-8000-000000000001', 'rally-pulse', 1, 'Plan P3'),
  ('9a800000-0000-4000-8000-000000000004', 'a8000000-0000-4000-8000-000000000001', 'court-memories', 1, 'Plan P4');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a800000-0000-4000-8000-000000000001', '9a800000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}');

-- J1: a heuristic job of P1 V1; J3 and J4: model plan-by-job jobs of P3 and P4.
select pg_temp.keep('q1', pg_temp.gw(pg_temp.quote_sql('9a800000-0000-4000-8000-000000000001',
                                                       '5a800000-0000-4000-8000-000000000001', 'heuristic')));
select pg_temp.keep('q3', pg_temp.gw(pg_temp.quote_sql('9a800000-0000-4000-8000-000000000003', null, 'model')));
select pg_temp.keep('q4', pg_temp.gw(pg_temp.quote_sql('9a800000-0000-4000-8000-000000000004', null, 'model')));
select pg_temp.keep('j1', pg_temp.gw(pg_temp.accept_sql('q1', 'key-j1', false)));
select pg_temp.keep('j3', pg_temp.gw(pg_temp.accept_sql('q3', 'key-j3', true)));
select pg_temp.keep('j4', pg_temp.gw(pg_temp.accept_sql('q4', 'key-j4', true)));
select is((select array_agg(cap_cost_micro_usd order by cap_cost_micro_usd)
             from public.usage_reservations where id in ((pg_temp.hold('j1')).id, (pg_temp.hold('j3')).id,
                                                         (pg_temp.hold('j4')).id)),
  array[455584, 705584, 705584]::bigint[], 'fixture: three held jobs (heuristic cap 455,584; model caps 705,584)');

-- set_job_state: the contract's transition table, compare-and-set, replay, pause and resume ---------------------------
select is(pg_temp.move(pg_temp.job('j1'), 'ready'), 'transition_not_allowed',
  'consented -> ready is not a transition of the contract (P0409 transition_not_allowed)');
select is(pg_temp.orch(format('select app_gateway.set_job_state(%L, ''queued'', ''normalizing'', null, gen_random_uuid())',
                              pg_temp.job('j1'))) ->> 'message', 'state_conflict',
  'compare-and-set: the job is not in the expected state (P0409 state_conflict)');
select is(pg_temp.walk(pg_temp.job('j1'), array['upload_pending', 'queued', 'normalizing']), 'ok',
  'story 193: the job walks its real stages consented -> upload_pending -> queued -> normalizing');
select is(pg_temp.orch(format('select app_gateway.set_job_state(%L, ''queued'', ''normalizing'', null, gen_random_uuid())',
                              pg_temp.job('j1'))) ->> 'replayed', 'true',
  'a redelivered step whose target the job already reached replays');
select is(pg_temp.move(pg_temp.job('j1'), 'paused'), 'paused', 'normalizing -> paused');
select is((select resume_state::text || ' ' || (paused_at is not null)::text from public.render_jobs
            where id = pg_temp.job('j1')), 'normalizing true', 'pausing stores the state to resume and the pause time');
select is(pg_temp.move(pg_temp.job('j1'), 'planning'), 'transition_not_allowed',
  'a resume can only return to the stored state, never skip ahead');
select is(pg_temp.move(pg_temp.job('j1'), 'normalizing'), 'normalizing', 'resume returns to the stored state');
select ok((select resume_state is null and paused_at is null from public.render_jobs where id = pg_temp.job('j1')),
  'resuming clears the resume state and the pause time');
select throws_ok(format('update public.render_jobs set state = ''paused'', resume_state = ''ready'' where id = %L',
                        pg_temp.job('j1')),
  'P0422', 'invalid_value:resume_state', 'a stored resume state must be one the job can return to (never ready)');

-- reserve_stage: SQL estimate, inputs, output plan, ledger and outbox (T-DB-55, T-DB-36) ------------------------------
select is(pg_temp.keep('n1', pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'normalize', 1))) ->> 'state', 'reserved',
  'reserve_stage reserves the normalize stage of J1 (no lease yet)');
select is((select reserved_cost_micro_usd from public.render_attempts where id = pg_temp.got('n1', 'attemptId')::uuid),
  5000::bigint, 'T-DB-55: the estimate is computed in SQL (191 MiB x 20 = 3,820 lifted to the 5,000 floor, never zero)');
select is((select jsonb_agg(e ->> 'id' order by o) from public.render_attempts a,
                  jsonb_array_elements(a.input_refs) with ordinality x(e, o)
            where a.id = pg_temp.got('n1', 'attemptId')::uuid),
  '["5c800000-0000-4000-8000-000000000001", "5c800000-0000-4000-8000-000000000002"]'::jsonb,
  'T-DB-55: input_refs are the quote''s verified sources of the job''s project (not the declared one, not B''s)');
select is((select array_agg(e ->> 'outputRef' || ':' || (e ->> 'maxBytes') order by o)
             from public.render_attempts a, jsonb_array_elements(a.output_plan) with ordinality x(e, o)
            where a.id = pg_temp.got('n1', 'attemptId')::uuid),
  array['analysis-proxy-1:4294967296', 'render-proxy-1:8589934592', 'pts-table-1:67108864',
        'analysis-proxy-2:4294967296', 'render-proxy-2:8589934592', 'pts-table-2:67108864'],
  'the output plan lists the stage''s outputs per angle, each with its kind''s byte cap');
select ok((pg_temp.hold('j1')).reserved_cost_micro_usd = 5000
          and (select count(*) = 1 from app_ops.spend_commitments
                where reservation_id = (pg_temp.hold('j1')).id and kind = 'stage_reserve' and amount_micro_usd = 5000)
          and (select count(*) = 1 from app_ops.job_outbox
                where job_id = pg_temp.job('j1') and kind = 'dispatch_attempt'
                  and payload = jsonb_build_object('attemptId', pg_temp.got('n1', 'attemptId'))),
  'the hold, the spend ledger (stage_reserve) and an ids-only dispatch outbox row move in the same transaction');
select is(pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'normalize', 1)) ->> 'attemptId', pg_temp.got('n1', 'attemptId'),
  'T-DB-36: the same (job, stage, attempt) again returns the same attempt');
select ok((select count(*) = 1 from public.render_attempts where job_id = pg_temp.job('j1') and stage = 'normalize')
          and (pg_temp.hold('j1')).reserved_cost_micro_usd = 5000
          and (select count(*) = 1 from app_ops.spend_commitments
                where reservation_id = (pg_temp.hold('j1')).id and kind = 'stage_reserve'),
  'T-DB-36: one attempt row, nothing reserved or committed twice');
select is(pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'final_render', 1)) ->> 'message', 'job_state_mismatch',
  'a stage is reserved only while the job is in that stage''s state');

-- claim_attempt and finish_attempt: outputs within the plan, one charge per stage -------------------------------------
select matches(pg_temp.keep('c_n1', pg_temp.orch(pg_temp.claim_sql(pg_temp.got('n1', 'attemptId')))) ->> 'leaseToken',
  '^jvl_[A-Za-z0-9_-]{43}$', 'claim_attempt returns a jvl_ lease token once');
select ok((select a.lease_token_hash = sha256(convert_to(pg_temp.got('c_n1', 'leaseToken'), 'UTF8')) and a.state = 'running'
                  and a.claimed_by_host = 'host-1' and a.leased_until > now()
             from public.render_attempts a where a.id = pg_temp.got('n1', 'attemptId')::uuid)
          and pg_temp.got('c_n1', 'inputRefs')::jsonb = (select input_refs from public.render_attempts
                                                           where id = pg_temp.got('n1', 'attemptId')::uuid),
  'only the token''s SHA-256 is stored; the attempt runs under a 5-minute lease with its stored inputs');
select is(pg_temp.orch(pg_temp.finish_sql(pg_temp.got('n1', 'attemptId'), pg_temp.got('c_n1', 'leaseToken'), 'succeeded',
            jsonb_build_array(jsonb_build_object('outputRef', 'film', 'bytes', 1000, 'sha256', pg_temp.sha('f'))),
            pg_temp.m(60000))) ->> 'message', 'invalid_value:outputs',
  'an output the stage''s plan does not list is refused (P0422)');
select is(pg_temp.orch(pg_temp.finish_sql(pg_temp.got('n1', 'attemptId'), pg_temp.got('c_n1', 'leaseToken'), 'succeeded',
            jsonb_build_array(jsonb_build_object('outputRef', 'analysis-proxy-1', 'bytes', 4294967297,
                                                 'sha256', pg_temp.sha('p'))),
            pg_temp.m(60000))) ->> 'message', 'invalid_value:outputs',
  'finding 32: an output above its byte cap is refused (P0422)');
select is(pg_temp.orch(pg_temp.finish_sql(pg_temp.got('n1', 'attemptId'), pg_temp.got('c_n1', 'leaseToken'), 'succeeded',
            '[]', '{"wallMs": -1, "cpuMs": 0, "bytesIn": 0, "bytesOut": 0}')) ->> 'message', 'invalid_value:measurements',
  'measurements are non-negative integers only');
select is((select count(*)::int from public.artifacts where job_id = pg_temp.job('j1')), 0,
  'no artifact is registered by a refused result');
select is(pg_temp.keep('f_n1', pg_temp.orch(pg_temp.finish_sql(pg_temp.got('n1', 'attemptId'),
            pg_temp.got('c_n1', 'leaseToken'), 'succeeded',
            jsonb_build_array(jsonb_build_object('outputRef', 'analysis-proxy-1', 'bytes', 1000,
                                                 'sha256', pg_temp.sha('p'))),
            pg_temp.m(60000)))) ->> 'state', 'succeeded', 'the normalize stage succeeds with one listed output');
select ok((select a.charged_cost_micro_usd = 3600 and a.actual_cost_micro_usd = 3600 and a.finished_at is not null
             from public.render_attempts a where a.id = pg_temp.got('n1', 'attemptId')::uuid)
          and (pg_temp.hold('j1')).consumed_cost_micro_usd = 3600 and (pg_temp.hold('j1')).reserved_cost_micro_usd = 3600,
  'the stage is charged its actual cost (60 s x 60 = 3,600) and the rest of its reservation returns to the hold');
select ok((select a.kind = 'analysis_proxy' and a.state = 'verifying' and a.bucket_class = 'work' and a.bytes = 1000
                  and a.r2_key = 'proxies/p/a8000000-0000-4000-8000-000000000001/j/' || pg_temp.job('j1') || '/'
                                 || pg_temp.got('n1', 'attemptId') || '/analysis-proxy-1'
                  and a.verified_at is null
             from public.artifacts a where a.id = (pg_temp.got('f_n1', 'outputRefs')::jsonb ->> 0)::uuid)
          and (select count(*) = 2 from public.artifact_sources
                where artifact_id = (pg_temp.got('f_n1', 'outputRefs')::jsonb ->> 0)::uuid),
  'the output is registered as verifying under a server-generated key, with both sources in artifact_sources');
select ok((pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'normalize', 2)) @> jsonb_build_object(
             'attemptId', pg_temp.got('n1', 'attemptId'), 'alreadyCharged', true))
          and (select count(*) = 1 from public.render_attempts where job_id = pg_temp.job('j1') and stage = 'normalize'),
  'story 199: a later attempt of a charged stage replays the charged attempt; nothing is reserved again');
select throws_ok(format('insert into public.render_attempts (job_id, stage, attempt, state, reserved_cost_micro_usd) '
                        'values (%L, ''normalize'', 3, ''succeeded'', 1)', pg_temp.job('j1')),
  '23505', null, 'consumption once per (job, stage): a second succeeded attempt of a stage cannot exist');

-- T-DB-55: the job's verified artifacts feed later stages; nothing unverified or foreign does --------------------------
update public.artifacts set state = 'ready', verified_at = now(), verification = '{"decoded": true}'
 where id = (pg_temp.got('f_n1', 'outputRefs')::jsonb ->> 0)::uuid;
insert into public.artifacts (id, project_id, job_id, kind, bucket_class, r2_key, state) values
  ('f8000000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000001', pg_temp.job('j1'), 'frame_set',
   'work', 'frames/s80/writing', 'verifying');
insert into public.artifacts (id, project_id, kind, bucket_class, r2_key, state, verified_at, verification) values
  ('f8000000-0000-4000-8000-000000000002', 'a8000000-0000-4000-8000-000000000001', 'frame_set', 'work',
   'frames/s80/other-job', 'ready', now(), '{"decoded": true}'),
  ('f8000000-0000-4000-8000-000000000003', 'b8000000-0000-4000-8000-000000000001', 'frame_set', 'work',
   'frames/s80/project-b', 'ready', now(), '{"decoded": true}');
select is(pg_temp.walk(pg_temp.job('j1'), array['planning']), 'ok', 'J1 moves on to planning');
select is(pg_temp.keep('p1', pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'plan', 1))) ->> 'state', 'reserved',
  'the plan stage of J1 is reserved');
select is((select jsonb_agg(e ->> 'kind' || ':' || (e ->> 'id') order by o) from public.render_attempts a,
                  jsonb_array_elements(a.input_refs) with ordinality x(e, o) where a.id = pg_temp.got('p1', 'attemptId')::uuid),
  jsonb_build_array('source:5c800000-0000-4000-8000-000000000001', 'source:5c800000-0000-4000-8000-000000000002',
                    'artifact:' || (pg_temp.got('f_n1', 'outputRefs')::jsonb ->> 0)),
  'T-DB-55: inputs are the verified sources plus this job''s verified artifacts; a writing artifact, another job''s '
  'and another project''s are never listed');
select ok((select a.reserved_cost_micro_usd = 1000 and a.planner_budget = '{"effort": "none", "maxImages": 0,
             "maxInputTokens": 0, "maxOutputTokens": 0, "repairAllowed": false}'::jsonb
             from public.render_attempts a where a.id = pg_temp.got('p1', 'attemptId')::uuid),
  'T-DB-72: a heuristic plan stage reserves the floor and writes a planner budget of zero (no provider call)');
update public.camera_sources set state = 'rejected', rejected_reason = 'hash_mismatch'
 where id = '5c800000-0000-4000-8000-000000000002';
select is(pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'validate', 1)) ->> 'message', 'inputs_changed',
  'a stage never runs on a changed source set: a source rejected since the quote is P0409 inputs_changed');
update public.camera_sources set state = 'verified', rejected_reason = null where id = '5c800000-0000-4000-8000-000000000002';

-- T-DB-36: beyond the cap, and beyond the environment ceiling, is P0402 ---------------------------------------------
select is(pg_temp.walk(pg_temp.job('j1'), array['preview_rendering', 'final_rendering']), 'ok',
  'J1 moves on to final_rendering');
select is(pg_temp.keep('r1', pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'final_render', 1))) ->> 'state',
  'reserved', 'the final render (1,500 x 120 s x 2 angles = 360,000) fits: 3,600 + 1,000 + 360,000 <= 455,584');
select is(pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'final_render', 2)) ->> 'error', 'P0402',
  'T-DB-36: a second final render while the first is open would cross the cap: P0402');
select ok((select count(*) = 1 from public.render_attempts where job_id = pg_temp.job('j1') and stage = 'final_render')
          and (pg_temp.hold('j1')).reserved_cost_micro_usd = 364600,
  'T-DB-36: the refused reservation left no attempt row and nothing reserved');
update app_ops.spend_limits set daily_ceiling_micro_usd = pg_temp.today_stage_total() + 1000 where scope = 'environment';
select is(pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'remux_no_audio', 1)) ->> 'error', 'P0402',
  'a stage reservation that would cross the environment''s daily ceiling is P0402 (2,000 > 1,000 left)');
update app_ops.spend_limits set daily_ceiling_micro_usd = 50000000 where scope = 'environment';

-- T-DB-72 (SQL half): the planner budget is what the stage reservation covers ------------------------------------------
select is(pg_temp.walk(pg_temp.job('j3'), array['upload_pending', 'queued', 'normalizing', 'planning']), 'ok',
  'J3 (model planner, plan-by-job) reaches planning');
select is(pg_temp.keep('p3', pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j3'), 'plan', 1))) ->> 'state', 'reserved',
  'J3''s plan stage is reserved');
select ok((select a.reserved_cost_micro_usd = 180000 and a.planner_budget = '{"effort": "medium", "maxImages": 8,
             "maxInputTokens": 8000, "maxOutputTokens": 2000, "repairAllowed": true}'::jsonb
             from public.render_attempts a where a.id = pg_temp.got('p3', 'attemptId')::uuid),
  'T-DB-72 (a): the reservation covers the worst case of the first call and its one repair (2 x 90,000), and the '
  'budget carries exactly those numbers');
update public.usage_reservations set reserved_cost_micro_usd = cap_cost_micro_usd - 100000
 where id = (pg_temp.hold('j4')).id;
select is(pg_temp.walk(pg_temp.job('j4'), array['upload_pending', 'queued', 'normalizing', 'planning']), 'ok',
  'J4 (model planner) reaches planning with only 100,000 left in its hold');
select ok((select a.reserved_cost_micro_usd = 90000 and (a.planner_budget ->> 'repairAllowed')::boolean = false
                  and (a.planner_budget ->> 'maxOutputTokens')::int = 2000
             from public.render_attempts a
            where a.id = (pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j4'), 'plan', 1)) ->> 'attemptId')::uuid),
  'T-DB-72 (b): when the hold covers one call but not the repair, the budget allows no repair call');
select ok((select a.reserved_cost_micro_usd = 1000 and a.planner_budget ->> 'effort' = 'none'
                  and (a.planner_budget ->> 'maxImages')::int = 0
             from public.render_attempts a
            where a.id = (pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j4'), 'plan', 2)) ->> 'attemptId')::uuid),
  'T-DB-72 (a): when not even one call fits (10,000 left), the budget is zero: no provider call, heuristic fallback');
select is(pg_temp.keep('c_p3', pg_temp.orch(pg_temp.claim_sql(pg_temp.got('p3', 'attemptId')))) ->> 'outputPlan',
  '[{"kind": "edit_manifest", "maxBytes": 1048576, "outputRef": "edit-manifest"}]'::jsonb::text,
  'the claim returns the plan stage''s output plan');
select is(pg_temp.keep('f_p3', pg_temp.orch(pg_temp.finish_sql(pg_temp.got('p3', 'attemptId'),
            pg_temp.got('c_p3', 'leaseToken'), 'succeeded', '[]', pg_temp.m(0, 50000, 10000)))) ->> 'jobState',
  'budget_exceeded',
  'T-DB-72 (c): measured tokens above the reservation (50,000 x 3 + 10,000 x 15 = 300,000 > 180,000) stop the job');
select ok((select count(*) = 1 from app_ops.spend_commitments
            where reservation_id = (pg_temp.hold('j3')).id and kind = 'stage_overrun' and amount_micro_usd = 120000)
          and (select a.actual_cost_micro_usd = 300000 and a.charged_cost_micro_usd = 180000
                 from public.render_attempts a where a.id = pg_temp.got('p3', 'attemptId')::uuid)
          and (pg_temp.hold('j3')).consumed_cost_micro_usd = 180000
          and (select resume_state::text || ' ' || error_code from public.render_jobs where id = pg_temp.job('j3'))
              = 'planning stage_overrun',
  'T-DB-72 (c): one stage_overrun commitment (120,000); the hold is charged at most the reservation');
update app_ops.spend_limits set daily_ceiling_micro_usd = pg_temp.today_stage_total() + 999 where scope = 'environment';
select ok(pg_temp.today_stage_total() - 120000 + 1000 <= (select daily_ceiling_micro_usd from app_ops.spend_limits
                                                           where scope = 'environment'),
  'T-DB-72 (c): without the overrun the next reservation (1,000) would fit under this ceiling');
select is(pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'cleanup', 1)) ->> 'error', 'P0402',
  'T-DB-72 (c): the next reserve_stage sees the overrun in the day''s total and is P0402');
update app_ops.spend_limits set daily_ceiling_micro_usd = 50000000 where scope = 'environment';

-- T-DB-53 (SQL half): ready needs a verified film; the verify stage verifies it; ready settles the hold -------------
select is(pg_temp.keep('c_r1', pg_temp.orch(pg_temp.claim_sql(pg_temp.got('r1', 'attemptId')))) ->> 'leaseToken' ~ '^jvl_',
  true, 'the final render is claimed');
select is(pg_temp.keep('f_r1', pg_temp.orch(pg_temp.finish_sql(pg_temp.got('r1', 'attemptId'),
            pg_temp.got('c_r1', 'leaseToken'), 'succeeded',
            jsonb_build_array(jsonb_build_object('outputRef', 'film', 'bytes', 5000, 'sha256', pg_temp.sha('film')),
                              jsonb_build_object('outputRef', 'thumbnail', 'bytes', 500, 'sha256', pg_temp.sha('t'))),
            pg_temp.m(600000)))) ->> 'state', 'succeeded', 'the final render registers the film and its thumbnail');
select ok((select f.state = 'verifying' and f.bucket_class = 'films' and f.r2_key = 'films/p/' || f.project_id || '/a/' || f.id
                  and t.parent_artifact_id = f.id
             from public.artifacts f join public.artifacts t on t.attempt_id = f.attempt_id and t.kind = 'thumbnail'
            where f.id = (pg_temp.got('f_r1', 'outputRefs')::jsonb ->> 0)::uuid),
  'the film is keyed by its artifact id in the films bucket and its thumbnail is its child');
select is(pg_temp.walk(pg_temp.job('j1'), array['verifying']), 'ok', 'J1 moves on to verifying');
select is(pg_temp.move(pg_temp.job('j1'), 'ready'), 'artifact_not_verified',
  'T-DB-53: as jovra_orchestrator, set_job_state(verifying -> ready) without a verified film is P0409');
select is(pg_temp.keep('v1', pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'verify_output', 1))) ->> 'state',
  'reserved', 'the verify stage is reserved');
select pg_temp.keep('c_v1', pg_temp.orch(pg_temp.claim_sql(pg_temp.got('v1', 'attemptId'))));
select ok(pg_temp.orch(format('select app_gateway.mark_artifact_verified(%L, sha256(convert_to(%L, ''UTF8'')), %L, '
                              '''{"decoded": true, "frames": 3600}''::jsonb, gen_random_uuid())',
                              pg_temp.got('v1', 'attemptId'), pg_temp.got('c_v1', 'leaseToken'),
                              pg_temp.got('f_r1', 'outputRefs')::jsonb ->> 0)) ? 'error' = false
          and (select state = 'ready' and verified_at is not null and verification ->> 'frames' = '3600'
                 from public.artifacts where id = (pg_temp.got('f_r1', 'outputRefs')::jsonb ->> 0)::uuid),
  'mark_artifact_verified, under the verify stage''s lease, makes the film ready and verified');
select is(pg_temp.orch(pg_temp.finish_sql(pg_temp.got('v1', 'attemptId'), pg_temp.got('c_v1', 'leaseToken'),
            'succeeded', '[]', pg_temp.m(1000))) ->> 'state', 'succeeded', 'the verify stage succeeds');
select is(pg_temp.move(pg_temp.job('j1'), 'ready'), 'ready', 'T-DB-53: with a verified film the job reaches ready');
select ok((select r.state = 'settled' and r.consumed_cost_micro_usd = 39660 and r.reserved_cost_micro_usd = 40660
                  and r.released_cost_micro_usd = 1000
             from public.usage_reservations r where r.id = (pg_temp.hold('j1')).id)
          and (select state = 'canceled' from public.render_attempts where id = pg_temp.got('p1', 'attemptId')::uuid),
  'ready settles the hold: 3,600 + 36,000 + 60 consumed, the open plan reservation (1,000) released and its attempt '
  'canceled');
select is(pg_temp.orch(pg_temp.reserve_sql(pg_temp.job('j1'), 'cleanup', 2)) ->> 'message', 'reservation_closed',
  'nothing more can be reserved against a settled hold');

select * from finish();
rollback;
