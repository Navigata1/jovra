-- Plan keys and lesson-scope deletion (S80 / B-06). T-DB-68: plan-by-job holds for two different plans of a project
-- with the same output are both allowed, a second one for the same plan is P0409, the planning stage moves the job and
-- its hold to (plan, V, hash of V) in the transaction that records its success so a quote for V meets the existing
-- hold, an in-job revise moves version and output hash on both, and a move onto a key another hold owns is P0409
-- requote_conflict. T-DB-73: the lesson-scope deletion step on the server path keeps a Progress plan's other lesson,
-- invalidates and stales its versions and finishes the request; a client still cannot rewrite lesson_ids or bind a
-- lesson it cannot access. Finding D9 and user story 199. Rolls back. Expected output hashes come from the reference
-- spec/reference/studio/core.py output_spec_sha256 for project a8400000-...-000000000001 and the 120 s output:
-- planRevision null 1c947feb..., 1 457ecdca..., 2 fce704da....
begin;
select plan(27);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('coach');
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
create function pg_temp.quote(p_key text, p_plan uuid, p_version uuid) returns jsonb language sql as $$
  select pg_temp.keep(p_key, pg_temp.gw(format(
    'select app_gateway.create_quote(%L, %L, %L, %L, ''heuristic'', %L::jsonb, %L::uuid[], 7, gen_random_uuid())',
    pg_temp.uid('owner'), 'a8400000-0000-4000-8000-000000000001', p_plan, p_version,
    '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9","container":"mp4","videoCodec":"h264",
      "audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}',
    array['5c840000-0000-4000-8000-000000000001', '5c840000-0000-4000-8000-000000000002']::uuid[])))
$$;
create function pg_temp.accept(p_key text, p_quote_key text) returns jsonb language sql as $$
  select pg_temp.keep(p_key, pg_temp.gw(format(
    'select app_gateway.accept_quote(%L, %L, decode(%L, ''hex''), %L::jsonb, %s, %L, gen_random_uuid())',
    pg_temp.uid('owner'), pg_temp.got(p_quote_key, 'quoteId'), pg_temp.got(p_quote_key, 'inputsSha256'),
    '{"at": "2026-11-08T10:00:00Z", "consentRecordId": "consent-s80", "consentTextVersion": "studio-cloud-consent@1.0.0",
      "modelProvider": false, "retentionDays": 7, "textClasses": [], "uploadSelectedSources": true}',
    pg_temp.got(p_quote_key, 'capCredits'), 'key-' || p_key)))
$$;
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
-- The plan stage of a job, reserved and claimed; returns the attempt id and lease token.
create function pg_temp.plan_stage(p_key text, p_job uuid) returns jsonb language plpgsql as $$
declare
  v_attempt text := pg_temp.orch(format('select app_gateway.reserve_stage(%L, ''plan'', 1, gen_random_uuid())', p_job))
                    ->> 'attemptId';
  v_claim   jsonb := pg_temp.orch(format(
                       'select app_gateway.claim_attempt(%L, ''host-1'', ''local-test'', gen_random_uuid())', v_attempt));
begin
  return pg_temp.keep(p_key, jsonb_build_object('attemptId', v_attempt, 'leaseToken', v_claim ->> 'leaseToken'));
end $$;
create function pg_temp.finish_plan(p_key text, p_version uuid) returns jsonb language sql as $$
  select pg_temp.orch(format(
    'select app_gateway.finish_attempt(%L, sha256(convert_to(%L, ''UTF8'')), ''succeeded'', %L::jsonb, '
    '''{"wallMs": 1000, "cpuMs": 1000, "bytesIn": 1000, "bytesOut": 1000}''::jsonb, null, null, %L::uuid, '
    'gen_random_uuid())',
    pg_temp.got(p_key, 'attemptId'), pg_temp.got(p_key, 'leaseToken'),
    jsonb_build_array(jsonb_build_object('outputRef', 'edit-manifest', 'bytes', 2048,
                                         'sha256', encode(sha256(p_key::bytea), 'hex'))), p_version))
$$;
create function pg_temp.key_of(p_job_key text) returns text language sql as $$
  select coalesce(j.story_plan_version_id::text, 'null') || ' ' || encode(j.output_spec_sha256, 'hex') || ' | '
         || coalesce(r.story_plan_version_id::text, 'null') || ' ' || encode(r.output_spec_sha256, 'hex')
    from public.render_jobs j join public.usage_reservations r on r.id = j.reservation_id
   where j.id = pg_temp.got(p_job_key, 'jobId')::uuid
$$;

-- Fixtures: project A of owner with two verified sources, plans PA and PB; lessons L1 and L2 of owner; coach is an
-- approved coach of A without any grant on the owner's lessons.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a8400000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Season');
insert into public.project_members (project_id, user_id, role, granted_by, approved_at) values
  ('a8400000-0000-4000-8000-000000000001', pg_temp.uid('coach'), 'coach', pg_temp.uid('owner'), now());
insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, declared_sha256) values
  ('5c840000-0000-4000-8000-000000000001', 'a8400000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s1'::bytea)),
  ('5c840000-0000-4000-8000-000000000002', 'a8400000-0000-4000-8000-000000000001', 'opposite_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s2'::bytea));
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a8400000-0000-4000-8000-000000000001',
   '{"sources": [{"sourceId": "5c840000-0000-4000-8000-000000000001"},
                 {"sourceId": "5c840000-0000-4000-8000-000000000002"}]}', sha256('ma'::bytea), 'render');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a840000-0000-4000-8000-00000000000a', 'a8400000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan PA'),
  ('9a840000-0000-4000-8000-00000000000b', 'a8400000-0000-4000-8000-000000000001', 'rally-pulse', 1, 'Plan PB');

-- T-DB-68: plan-by-job holds for two different plans with the same output; never two for one plan ------------------
select pg_temp.quote('qa', '9a840000-0000-4000-8000-00000000000a', null);
select pg_temp.quote('qb', '9a840000-0000-4000-8000-00000000000b', null);
select pg_temp.quote('qa2', '9a840000-0000-4000-8000-00000000000a', null);
select is(pg_temp.accept('ja', 'qa') ->> 'state', 'consented', 'T-DB-68: a plan-by-job hold for PA');
select is(pg_temp.accept('jb', 'qb') ->> 'state', 'consented',
  'T-DB-68: a plan-by-job hold for PB with the same output spec is allowed (another plan, another key)');
select is(pg_temp.accept('ja2', 'qa2') ->> 'message', 'duplicate_work',
  'T-DB-68: a second plan-by-job acceptance for PA with the same output is P0409');
select is(pg_temp.key_of('ja'),
  'null 1c947feb10b04acabe3f38a8469eb14dc98cbb2163a39e9c25be59cc3b011402 | '
  || 'null 1c947feb10b04acabe3f38a8469eb14dc98cbb2163a39e9c25be59cc3b011402',
  'the plan-by-job job and its hold are keyed (PA, NULL, hash of the unplanned output)');

-- T-DB-68: the planning stage moves job and hold to (PA, V, hash of V) in one transaction --------------------------
select is(pg_temp.walk(pg_temp.got('ja', 'jobId')::uuid, array['upload_pending', 'queued', 'normalizing', 'planning']),
  'ok', 'job A reaches planning');
select ok(pg_temp.plan_stage('pa', pg_temp.got('ja', 'jobId')::uuid) ->> 'leaseToken' ~ '^jvl_',
  'job A''s plan stage is reserved and claimed');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a840000-0000-4000-8000-0000000000a1', '9a840000-0000-4000-8000-00000000000a', 'heuristic', 'h1', '{}');
select is(pg_temp.finish_plan('pa', '5a840000-0000-4000-8000-0000000000a1') ->> 'state', 'succeeded',
  'the plan stage succeeds and names the version V it produced');
select is(pg_temp.key_of('ja'),
  '5a840000-0000-4000-8000-0000000000a1 457ecdca816eb1fb3cb7ac263b48d4c8888bf81dafd1134560da1b38bda0aef2 | '
  || '5a840000-0000-4000-8000-0000000000a1 457ecdca816eb1fb3cb7ac263b48d4c8888bf81dafd1134560da1b38bda0aef2',
  'T-DB-68: job and hold both moved to (PA, V, core.output_spec_sha256 with planRevision 1)');
select ok((select state = 'succeeded' and charged_cost_micro_usd = 60 from public.render_attempts
            where id = pg_temp.got('pa', 'attemptId')::uuid)
          and (select consumed_cost_micro_usd = 60 from public.usage_reservations
                where id = pg_temp.got('ja', 'reservationId')::uuid),
  'the key moved in the transaction that recorded the stage''s one charge');
select is(pg_temp.walk(pg_temp.got('ja', 'jobId')::uuid, array['preview_rendering', 'awaiting_review']), 'ok',
  'job A reaches awaiting_review');
select is(pg_temp.quote('qv', '9a840000-0000-4000-8000-00000000000a', '5a840000-0000-4000-8000-0000000000a1')
          ->> 'state', 'open', 'the owner asks for a quote naming V with the same output');
select is(pg_temp.accept('jv', 'qv') ->> 'message', 'duplicate_work',
  'T-DB-68: the quote for V meets the moved hold: P0409, never a second hold and job');
select is((select count(*)::int from public.usage_reservations
            where story_plan_id = '9a840000-0000-4000-8000-00000000000a' and state = 'held'), 1,
  'T-DB-68: PA still has exactly one held reservation');

-- T-DB-68: an in-job revise moves version and output hash on job and hold together -----------------------------------
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a840000-0000-4000-8000-0000000000a2', '9a840000-0000-4000-8000-00000000000a', 'user', 'h1', '{}');
select is(pg_temp.gw(format('select app_gateway.review_job(%L, %L, ''revise'', %L, gen_random_uuid())',
                            pg_temp.uid('owner'), pg_temp.got('ja', 'jobId'), '5a840000-0000-4000-8000-0000000000a2'))
          ->> 'state', 'planning', 'the owner revises to V2 within the remaining reservation');
select is(pg_temp.key_of('ja'),
  '5a840000-0000-4000-8000-0000000000a2 fce704da345d7625ce53e93cfefd3da99c2e110b269307124c60742daec58d54 | '
  || '5a840000-0000-4000-8000-0000000000a2 fce704da345d7625ce53e93cfefd3da99c2e110b269307124c60742daec58d54',
  'T-DB-68: the revise moved output_spec_sha256 and the version on both job and reservation');

-- A move onto a key another hold owns is P0409 requote_conflict, and nothing is charged ------------------------------
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a840000-0000-4000-8000-0000000000b1', '9a840000-0000-4000-8000-00000000000b', 'heuristic', 'h1', '{}');
select pg_temp.quote('qb1', '9a840000-0000-4000-8000-00000000000b', '5a840000-0000-4000-8000-0000000000b1');
select is(pg_temp.accept('jb1', 'qb1') ->> 'state', 'consented', 'a separate job for (PB, VB1) holds that key');
select is(pg_temp.walk(pg_temp.got('jb', 'jobId')::uuid, array['upload_pending', 'queued', 'normalizing', 'planning']),
  'ok', 'job B (plan-by-job of PB) reaches planning');
select pg_temp.plan_stage('pb', pg_temp.got('jb', 'jobId')::uuid);
select is(pg_temp.finish_plan('pb', '5a840000-0000-4000-8000-0000000000b1') ->> 'message', 'requote_conflict',
  '§13.6: job B''s plan stage producing VB1 cannot move onto the key job B1 holds (P0409 requote_conflict)');
select ok((select state = 'running' and charged_cost_micro_usd is null from public.render_attempts
            where id = pg_temp.got('pb', 'attemptId')::uuid)
          and pg_temp.key_of('jb') like 'null %'
          and (select consumed_cost_micro_usd = 0 from public.usage_reservations
                where id = pg_temp.got('jb', 'reservationId')::uuid),
  'the refused success changed nothing: no charge, the job and its hold keep their key, the attempt is still open');

-- T-DB-73: lesson-scope deletion on the server path ------------------------------------------------------------------
insert into public.lessons (id, owner_id, local_lesson_id, lesson_date, title) values
  ('1e840000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), current_date, 'Serve'),
  ('1e840000-0000-4000-8000-000000000002', pg_temp.uid('owner'), gen_random_uuid(), current_date, 'Return');
insert into public.story_plans (id, project_id, lesson_ids, profile_id, profile_revision, title) values
  ('9a840000-0000-4000-8000-00000000000c', 'a8400000-0000-4000-8000-000000000001',
   '{1e840000-0000-4000-8000-000000000001,1e840000-0000-4000-8000-000000000002}', 'progress-story', 1, 'Progress');
insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version, story_plan,
                                        validation_state) values
  ('9a840000-0000-4000-8000-00000000000c', 'heuristic', 'h1', '{}', 'valid'),
  ('9a840000-0000-4000-8000-00000000000c', 'heuristic', 'h1', '{}', 'valid');
insert into public.deletion_requests (id, requested_by, scope, target_id) values
  ('de840000-0000-4000-8000-000000000001', pg_temp.uid('owner'), 'lesson', '1e840000-0000-4000-8000-000000000001');
select is(auth.uid(), null::uuid, 'the server path carries no user claims (auth.uid() is null)');
select is(pg_temp.keep('del', pg_temp.orch($$select app_gateway.delete_lesson_rows('de840000-0000-4000-8000-000000000001',
                                                                                 gen_random_uuid())$$)) ->> 'state',
  'done', 'T-DB-73: the lesson-scope deletion step completes (no P0401 from check_story_plan_lessons)');
select is((select lesson_ids from public.story_plans where id = '9a840000-0000-4000-8000-00000000000c'),
  '{1e840000-0000-4000-8000-000000000002}'::uuid[], 'T-DB-73: the Progress plan keeps its other lesson');
select is((select array_agg(validation_state || ' ' || stale::text) from public.story_plan_versions
            where story_plan_id = '9a840000-0000-4000-8000-00000000000c'),
  array['invalid true', 'invalid true'], 'T-DB-73: the plan''s versions are invalid and stale');
select ok(not exists (select 1 from public.lessons where id = '1e840000-0000-4000-8000-000000000001')
          and exists (select 1 from public.lessons where id = '1e840000-0000-4000-8000-000000000002')
          and (select state = 'done' and finished_at is not null
                      and counts = '{"lessons": 1, "plans": 1, "planVersions": 2, "staleMedia": 0}'::jsonb
                 from public.deletion_requests where id = 'de840000-0000-4000-8000-000000000001'),
  'T-DB-73: the lesson is gone, the other stays, and the request reached done with its counts');
select is(pg_temp.orch($$select app_gateway.delete_lesson_rows('de840000-0000-4000-8000-000000000001',
                                                               gen_random_uuid())$$) ->> 'replayed', 'true',
  'a retried deletion step replays');
-- The same lesson_ids rewrite by a client is still refused, and so is binding a lesson the client cannot access.
select tests.authenticate_as('coach');
select throws_ok($$update public.story_plans set lesson_ids = '{}' where id = '9a840000-0000-4000-8000-00000000000c'$$,
  '42501', 'permission denied for table story_plans',
  'T-DB-73: a client cannot rewrite lesson_ids (only the server path may remove a lesson)');
select throws_ok($$insert into public.story_plans (project_id, lesson_ids, profile_id, profile_revision, title)
                   values ('a8400000-0000-4000-8000-000000000001', '{1e840000-0000-4000-8000-000000000002}',
                           'progress-story', 1, 'Coach progress')$$,
  'P0401', 'lesson_not_accessible',
  'T-DB-73: a coach without access to the remaining lesson cannot bind it into a plan (client path still checked)');

select * from finish();
rollback;
