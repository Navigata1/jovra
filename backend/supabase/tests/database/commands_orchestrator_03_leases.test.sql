-- Orchestrator lease fencing (S80 / B-06): claim_attempt, heartbeat_attempt, finish_attempt, expire_attempt_leases,
-- mark_artifact_verified and audit_denial_for_attempt as jovra_orchestrator. T-DB-37 (finish_attempt with a stale token,
-- and after lease_expired, is rejected and registers no artifact), a second claim is fenced, a failed attempt charges
-- nothing and returns its reservation, redelivered results replay, cancel releases the hold, denial rows for host
-- routes, and T-DB-47's command half for the lease token (only its SHA-256 is stored anywhere). Threat S4 (render host
-- impersonated to post results). Rolls back. Rate card rates-v0-inferred: normalize reserves 5,000; container time is
-- 60 micro-USD per second.
begin;
select plan(35);

select tests.create_supabase_user('owner');
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
create function pg_temp.move(p_job uuid, p_to text) returns text language plpgsql as $$
declare
  v jsonb;
begin
  v := pg_temp.orch(format('select app_gateway.set_job_state(%L, %L, %L, null, gen_random_uuid())',
                           p_job, (select state from public.render_jobs where id = p_job), p_to));
  return coalesce(v ->> 'message', v ->> 'state');
end $$;
create function pg_temp.reserve(p_key text, p_stage text, p_attempt int) returns jsonb language sql as $$
  select pg_temp.keep(p_key, pg_temp.orch(format('select app_gateway.reserve_stage(%L, %L, %s, gen_random_uuid())',
                                                 pg_temp.got('j', 'jobId'), p_stage, p_attempt)))
$$;
create function pg_temp.claim(p_key text, p_attempt_key text) returns jsonb language sql as $$
  select pg_temp.keep(p_key, pg_temp.orch(format(
    'select app_gateway.claim_attempt(%L, ''host-1'', ''local-test'', gen_random_uuid())',
    pg_temp.got(p_attempt_key, 'attemptId'))))
$$;
create function pg_temp.m(p_wall_ms bigint) returns jsonb language sql as $$
  select jsonb_build_object('wallMs', p_wall_ms, 'cpuMs', p_wall_ms, 'bytesIn', 1000, 'bytesOut', 1000)
$$;
-- finish_attempt(attempt of p_attempt_key, SHA-256 of p_token, ...)
create function pg_temp.finish(p_attempt_key text, p_token text, p_outcome text, p_outputs jsonb, p_m jsonb,
                               p_err text default null, p_retry boolean default null) returns jsonb
language sql as $$
  select pg_temp.orch(format('select app_gateway.finish_attempt(%L, sha256(convert_to(%L, ''UTF8'')), %L, %L::jsonb, '
                             '%L::jsonb, %L, %L::boolean, null, gen_random_uuid())',
                             pg_temp.got(p_attempt_key, 'attemptId'), p_token, p_outcome, p_outputs, p_m, p_err,
                             p_retry))
$$;
create function pg_temp.proxy_output() returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('outputRef', 'analysis-proxy-1', 'bytes', 1000,
                                              'sha256', encode(sha256('proxy'::bytea), 'hex')))
$$;
create function pg_temp.hold() returns public.usage_reservations language sql as $$
  select r.* from public.usage_reservations r where r.id = pg_temp.got('j', 'reservationId')::uuid
$$;
create function pg_temp.artifacts() returns int language sql as $$
  select count(*)::int from public.artifacts where job_id = pg_temp.got('j', 'jobId')::uuid
$$;

-- Fixtures: a project with two verified sources in its current manifest, plan P1 with version V1, and job J of P1 V1
-- (created by the gateway's create_quote and accept_quote), moved to normalizing.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a8300000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Club final');
insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, declared_sha256) values
  ('5c830000-0000-4000-8000-000000000001', 'a8300000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s1'::bytea)),
  ('5c830000-0000-4000-8000-000000000002', 'a8300000-0000-4000-8000-000000000001', 'opposite_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s2'::bytea));
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a8300000-0000-4000-8000-000000000001',
   '{"sources": [{"sourceId": "5c830000-0000-4000-8000-000000000001"},
                 {"sourceId": "5c830000-0000-4000-8000-000000000002"}]}', sha256('ma'::bytea), 'render');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a830000-0000-4000-8000-000000000001', 'a8300000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan P1');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a830000-0000-4000-8000-000000000001', '9a830000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}');
select pg_temp.keep('q', pg_temp.gw(format(
  'select app_gateway.create_quote(%L, %L, %L, %L, ''heuristic'', %L::jsonb, %L::uuid[], 7, gen_random_uuid())',
  pg_temp.uid('owner'), 'a8300000-0000-4000-8000-000000000001', '9a830000-0000-4000-8000-000000000001',
  '5a830000-0000-4000-8000-000000000001',
  '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9","container":"mp4","videoCodec":"h264",
    "audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}',
  array['5c830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000002']::uuid[])));
select pg_temp.keep('j', pg_temp.gw(format(
  'select app_gateway.accept_quote(%L, %L, decode(%L, ''hex''), %L::jsonb, %s, ''key-j'', gen_random_uuid())',
  pg_temp.uid('owner'), pg_temp.got('q', 'quoteId'), pg_temp.got('q', 'inputsSha256'),
  '{"at": "2026-11-08T10:00:00Z", "consentRecordId": "consent-s80", "consentTextVersion": "studio-cloud-consent@1.0.0",
    "modelProvider": false, "retentionDays": 7, "textClasses": [], "uploadSelectedSources": true}',
  pg_temp.got('q', 'capCredits'))));
select is(pg_temp.move(pg_temp.got('j', 'jobId')::uuid, 'upload_pending') || ' '
          || pg_temp.move(pg_temp.got('j', 'jobId')::uuid, 'queued') || ' '
          || pg_temp.move(pg_temp.got('j', 'jobId')::uuid, 'normalizing'),
  'upload_pending queued normalizing', 'fixture: job J is consented by the owner and moved to normalizing');

-- Claim: one lease per attempt ----------------------------------------------------------------------------------------
select is(pg_temp.reserve('a1', 'normalize', 1) ->> 'state', 'reserved', 'attempt 1 of normalize is reserved');
select ok(pg_temp.claim('c1', 'a1') ->> 'leaseToken' ~ '^jvl_[A-Za-z0-9_-]{43}$', 'the host claims attempt 1');
select is(pg_temp.claim('c1b', 'a1') ->> 'message', 'already_claimed', 'a second claim of the same attempt is fenced');
select is(pg_temp.orch($$select app_gateway.claim_attempt(gen_random_uuid(), 'host-1', 'local-test', gen_random_uuid())$$)
          ->> 'error', 'P0404', 'a claim of an unknown attempt is P0404');
select is(pg_temp.orch(format('select app_gateway.claim_attempt(%L, ''Host 1'', ''local-test'', gen_random_uuid())',
                              pg_temp.got('a1', 'attemptId'))) ->> 'message', 'invalid_value:host',
  'the host label is a lower-case slug (never free text)');

-- Heartbeat: only the current token extends the lease ----------------------------------------------------------------
select is(pg_temp.orch(format('select app_gateway.heartbeat_attempt(%L, sha256(''jvl_forged''::bytea), 100, '
                              'gen_random_uuid())', pg_temp.got('a1', 'attemptId'))) ->> 'message', 'stale_lease',
  'a heartbeat with another token is P0409 stale_lease');
select is(pg_temp.orch(format('select app_gateway.heartbeat_attempt(%L, sha256(convert_to(%L, ''UTF8'')), 500, '
                              'gen_random_uuid())', pg_temp.got('a1', 'attemptId'), pg_temp.got('c1', 'leaseToken')))
          ->> 'cancel', 'false', 'the current token extends the lease and is told not to cancel');
select is((select stage_progress_milli from public.render_jobs where id = pg_temp.got('j', 'jobId')::uuid), 500,
  'the heartbeat mirrors the stage''s progress onto the job');

-- T-DB-37: a stale token is rejected and registers nothing --------------------------------------------------------
select is(pg_temp.finish('a1', 'jvl_' || repeat('A', 43), 'succeeded', pg_temp.proxy_output(), pg_temp.m(1000))
          ->> 'message', 'stale_lease', 'T-DB-37: finish_attempt with a stale token is P0409 stale_lease');
select ok(pg_temp.artifacts() = 0 and (select state = 'running' from public.render_attempts
                                        where id = pg_temp.got('a1', 'attemptId')::uuid)
          and (pg_temp.hold()).consumed_cost_micro_usd = 0,
  'T-DB-37: no artifact is registered and nothing is charged; the attempt keeps running');

-- T-DB-37: after the lease expired, even the right token is rejected ----------------------------------------------
update public.render_attempts set leased_until = now() - interval '1 second'
 where id = pg_temp.got('a1', 'attemptId')::uuid;
select is(pg_temp.finish('a1', pg_temp.got('c1', 'leaseToken'), 'succeeded', pg_temp.proxy_output(), pg_temp.m(1000))
          ->> 'message', 'lease_expired', 'T-DB-37: finish_attempt past leased_until is P0409 lease_expired');
select is(pg_temp.orch(format('select app_gateway.heartbeat_attempt(%L, sha256(convert_to(%L, ''UTF8'')), 600, '
                              'gen_random_uuid())', pg_temp.got('a1', 'attemptId'), pg_temp.got('c1', 'leaseToken')))
          ->> 'message', 'lease_expired', 'an expired lease cannot be extended');
select is(pg_temp.orch('select app_gateway.expire_attempt_leases(gen_random_uuid())')::text, '1',
  'the reconciler''s sweep marks the one expired attempt');
select ok((select state = 'lease_expired' and retryable and error_code = 'lease_expired' and finished_at is not null
             from public.render_attempts where id = pg_temp.got('a1', 'attemptId')::uuid)
          and (pg_temp.hold()).reserved_cost_micro_usd = 0,
  'the attempt is lease_expired (retryable) and its reservation returned to the hold');
select is(pg_temp.finish('a1', pg_temp.got('c1', 'leaseToken'), 'succeeded', pg_temp.proxy_output(), pg_temp.m(1000))
          ->> 'message', 'lease_expired', 'T-DB-37: a result after lease_expired is rejected');
select ok(pg_temp.artifacts() = 0 and (pg_temp.hold()).consumed_cost_micro_usd = 0,
  'T-DB-37: no artifact registered and nothing charged for the zombie attempt');

-- A failed attempt charges nothing and returns its reservation; a redelivered result replays ----------------------
select is(pg_temp.reserve('a2', 'normalize', 2) ->> 'state', 'reserved', 'the retry (attempt 2) reserves again');
select pg_temp.claim('c2', 'a2');
select is(pg_temp.finish('a2', pg_temp.got('c2', 'leaseToken'), 'failed', pg_temp.proxy_output(), pg_temp.m(2000),
                         'decode_failed', true) ->> 'message', 'invalid_value:outputs',
  'a failed attempt registers no outputs (P0422)');
select is(pg_temp.finish('a2', pg_temp.got('c2', 'leaseToken'), 'failed', '[]', pg_temp.m(2000), 'decode_failed', true)
          ->> 'state', 'failed', 'attempt 2 fails (retryable)');
select ok((select actual_cost_micro_usd = 120 and charged_cost_micro_usd is null and error_code = 'decode_failed'
             from public.render_attempts where id = pg_temp.got('a2', 'attemptId')::uuid)
          and (pg_temp.hold()).reserved_cost_micro_usd = 0 and (pg_temp.hold()).consumed_cost_micro_usd = 0,
  'a failed attempt''s real cost is recorded (2 s x 60 = 120) but never charged; its reservation returns');
select is(pg_temp.finish('a2', pg_temp.got('c2', 'leaseToken'), 'failed', '[]', pg_temp.m(2000), 'decode_failed', true)
          ->> 'replayed', 'true', 'a redelivered failure replays');
select is(pg_temp.finish('a2', pg_temp.got('c2', 'leaseToken'), 'succeeded', pg_temp.proxy_output(), pg_temp.m(2000))
          ->> 'message', 'already_finished', 'another result for a finished attempt is P0409 already_finished');

-- mark_artifact_verified belongs to the verify stage only ----------------------------------------------------------
select pg_temp.reserve('a3', 'normalize', 3);
select pg_temp.claim('c3', 'a3');
select is(pg_temp.orch(format('select app_gateway.mark_artifact_verified(%L, sha256(convert_to(%L, ''UTF8'')), '
                              'gen_random_uuid(), ''{"decoded": true}'', gen_random_uuid())',
                              pg_temp.got('a3', 'attemptId'), pg_temp.got('c3', 'leaseToken'))) ->> 'message',
  'not_verify_stage', 'only the verify_output stage may mark an artifact verified');
select tests.write_attempt_output(pg_temp.got('a3', 'attemptId')::uuid, pg_temp.got('c3', 'leaseToken'),
                                  'analysis-proxy-1', 1000, sha256('proxy'::bytea));
select is(pg_temp.finish('a3', pg_temp.got('c3', 'leaseToken'), 'succeeded', pg_temp.proxy_output(), pg_temp.m(30000))
          ->> 'state', 'succeeded', 'attempt 3 succeeds');
select is(pg_temp.finish('a3', pg_temp.got('c3', 'leaseToken'), 'succeeded', pg_temp.proxy_output(), pg_temp.m(30000))
          ->> 'replayed', 'true', 'story 199: the redelivered success replays');
select ok(pg_temp.artifacts() = 1 and (pg_temp.hold()).consumed_cost_micro_usd = 1800,
  'story 199: one artifact and one charge (30 s x 60 = 1,800) for the stage, whatever the redeliveries');

-- audit_denial_for_attempt: append only; the attempt id or null ----------------------------------------------------
select is(pg_temp.orch(format('select app_gateway.audit_denial_for_attempt(%L, ''attempt.result'', ''stale_lease'', '
                              'gen_random_uuid())', pg_temp.got('a1', 'attemptId'))) ? 'error', false,
  'the host route records a refused result after the command rolled back');
select is(pg_temp.orch($$select app_gateway.audit_denial_for_attempt(gen_random_uuid(), 'attempt.claim', 'not_found',
                                                                     gen_random_uuid())$$) ? 'error', false,
  'a refusal for an unknown attempt is recorded too');
select is((select array_agg(coalesce(actor_id::text, 'null') || ' ' || action || ' ' || reason_code
                            order by id)
             from app_ops.audit_events where actor_kind = 'render_attempt' and outcome = 'denied'),
  array[pg_temp.got('a1', 'attemptId') || ' attempt.result stale_lease', 'null attempt.claim not_found'],
  'one denied row each: actor_kind render_attempt, the attempt id when it resolves, else null');
select is(pg_temp.orch(format('select app_gateway.audit_denial_for_attempt(%L, ''attempt.result'', ''Stale lease'', '
                              'gen_random_uuid())', pg_temp.got('a1', 'attemptId'))) ->> 'message',
  'invalid_value:reason', 'the reason is a machine code, never free text');

-- Cancel releases the hold and fences the open attempts; T-DB-47 for the lease token ------------------------------
select is(pg_temp.reserve('a4', 'cleanup', 1) ->> 'state', 'reserved', 'an open cleanup reservation (1,000)');
select is(pg_temp.move(pg_temp.got('j', 'jobId')::uuid, 'canceled'), 'canceled', 'the job is canceled');
select ok((select r.state = 'released' and r.consumed_cost_micro_usd = 1800 and r.reserved_cost_micro_usd = 2800
                  and r.released_cost_micro_usd = 1000 from public.usage_reservations r where r.id = (pg_temp.hold()).id)
          and (select state = 'canceled' from public.render_attempts where id = pg_temp.got('a4', 'attemptId')::uuid)
          and pg_temp.claim('c4', 'a4') ->> 'message' = 'already_claimed',
  'canceling releases the unconsumed reservation, cancels the open attempt and fences its claim');
create function pg_temp.secret_rows() returns int language plpgsql as $$
declare
  v_table regclass;
  v_n     int := 0;
  v_c     int;
begin
  for v_table in select c.oid::regclass from pg_class c
                  where c.relkind = 'r' and (c.relnamespace = 'app_ops'::regnamespace
                                             or c.oid in ('public.render_attempts'::regclass,
                                                          'public.render_jobs'::regclass))
  loop
    execute format('select count(*) from %s t where to_jsonb(t)::text ~ ''jv[igslhc]_''', v_table) into v_c;
    v_n := v_n + v_c;
  end loop;
  return v_n;
end $$;
select is(pg_temp.secret_rows(), 0,
  'T-DB-47: three lease tokens were minted and none is stored in an app_ops row, an attempt or a job');

select * from finish();
rollback;
