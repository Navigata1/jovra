-- Migration 3 invariants on the server path (S78 / B-05): one hold per (project, plan, version, output) also while
-- the version is null (finding 18), one live job per key, project-bound plans and versions even for the table owner
-- (T-DB-59 FK half), bounded holds, coded consent and output-plan checks (finding 32), `ready` only with a verified
-- film (T-DB-53 table half), no secret storable in app_ops (T-DB-47 table half), lesson-scope deletion objects first
-- and its row cascade (T-DB-48), clip-share audit rows and delete_object outbox rows (finding 20), project-bound
-- excerpts and artifact sources (finding 31) and append-only ledgers. User stories 199 and 201.
-- Fixtures and server writes run as postgres; table-owner writes as jovra_owner; command roles as jovra_gateway and
-- jovra_orchestrator. The file rolls back.
begin;
select plan(84);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('owner_b');
grant jovra_gateway, jovra_orchestrator to postgres;

-- Run SQL as another role; the result is the SQLSTATE, or 'no error'. The SQL never calls tests.* (only the client
-- roles may), so ids are formatted in by the caller.
create function pg_temp.err(p_role text, p_sql text) returns text language plpgsql as $$
declare
  v_state text;
begin
  execute format('set local role %I', p_role);
  execute p_sql;
  execute 'reset role';
  return 'no error';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate;
  return v_state;
end $$;
create function pg_temp.uid(p_who text) returns text language sql as $$ select quote_literal(tests.get_supabase_uid(p_who)) $$;

insert into public.projects (id, owner_id, local_project_id, title) values
  ('a7830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), 'Club final'),
  ('b7830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_b'), gen_random_uuid(), 'Other match');
insert into public.camera_sources (id, project_id, slot, local_source_id, declared_bytes, declared_sha256) values
  ('5c830000-0000-4000-8000-000000000001', 'a7830000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 100000000, sha256('sa'::bytea)),
  ('5c830000-0000-4000-8000-000000000002', 'b7830000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 100000000, sha256('sb'::bytea));
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a830000-0000-4000-8000-000000000001', 'a7830000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan A1'),
  ('9a830000-0000-4000-8000-000000000002', 'a7830000-0000-4000-8000-000000000001', 'rally-pulse', 1, 'Plan A2'),
  ('9b830000-0000-4000-8000-000000000001', 'b7830000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan B');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a830000-0000-4000-8000-000000000001', '9a830000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}'),
  ('5b830000-0000-4000-8000-000000000001', '9b830000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}');

-- Quotes of A: q1..q6 for plan A1 (q1 names version VA; the rest are plan-by-job), q7 for plan A2. All open.
create function pg_temp.quote(p_id uuid, p_plan uuid, p_version uuid) returns void language sql as $$
  insert into public.quotes (id, project_id, owner_id, story_plan_id, story_plan_version_id, output_spec_sha256,
                             inputs, inputs_sha256, rates_version, planner_choice, retention_days,
                             estimate_low_credits, estimate_high_credits, cap_credits, estimate_high_cost_micro_usd,
                             cap_cost_micro_usd, expires_at, sample)
  values (p_id, 'a7830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), p_plan, p_version,
          sha256('out'::bytea), '{}', sha256('in'::bytea), 'rates-test-1', 'heuristic', 7, 2, 4, 4, 1290000, 1500000,
          now() + interval '30 minutes', true)
$$;
select pg_temp.quote(('0a830000-0000-4000-8000-00000000000' || n)::uuid, '9a830000-0000-4000-8000-000000000001',
                     case when n = 1 then '5a830000-0000-4000-8000-000000000001'::uuid end)
  from generate_series(1, 6) n;
select pg_temp.quote('0a830000-0000-4000-8000-000000000007', '9a830000-0000-4000-8000-000000000002', null);

-- A hold as the server writes it (accept_quote, S79); the result is the SQLSTATE or 'ok'.
create function pg_temp.hold(p_id uuid, p_quote uuid, p_plan uuid, p_output text) returns text
language plpgsql as $$
declare
  v_state text;
begin
  insert into public.usage_reservations (id, project_id, owner_id, quote_id, initial_quote_id, story_plan_id,
                                         story_plan_version_id, output_spec_sha256, cap_credits, cap_cost_micro_usd,
                                         sample)
  values (p_id, 'a7830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), p_quote, p_quote, p_plan,
          null, sha256(convert_to(p_output, 'UTF8')), 4, 1500000, true);
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate;
  return v_state;
end $$;

-- Finding 18 / §13.6: one hold per (project, plan, version, output), NULLS NOT DISTINCT ---------------------------
select is(pg_temp.hold('ae830000-0000-4000-8000-000000000001', '0a830000-0000-4000-8000-000000000002',
                       '9a830000-0000-4000-8000-000000000001', 'film-1080p'), 'ok',
  'finding 18: a plan-by-job hold (story_plan_version_id null) is accepted');
select is(pg_temp.hold('ae830000-0000-4000-8000-000000000002', '0a830000-0000-4000-8000-000000000003',
                       '9a830000-0000-4000-8000-000000000001', 'film-1080p'), '23505',
  'finding 18: a second held reservation with story_plan_version_id null for the same project, plan and output fails');
select is(pg_temp.hold('ae830000-0000-4000-8000-000000000003', '0a830000-0000-4000-8000-000000000007',
                       '9a830000-0000-4000-8000-000000000002', 'film-1080p'), 'ok',
  '§13.6: plan-by-job work for a different plan of the project is a different key');
select is(pg_temp.hold('ae830000-0000-4000-8000-000000000004', '0a830000-0000-4000-8000-000000000004',
                       '9a830000-0000-4000-8000-000000000001', 'film-4k'), 'ok',
  '§13.6: the same plan with a different output is a different key');
update public.usage_reservations set state = 'released' where id = 'ae830000-0000-4000-8000-000000000001';
select is(pg_temp.hold('ae830000-0000-4000-8000-000000000005', '0a830000-0000-4000-8000-000000000005',
                       '9a830000-0000-4000-8000-000000000001', 'film-1080p'), 'ok',
  '§13.6: once the hold is released, identical work may be held again');
select is(pg_temp.hold('ae830000-0000-4000-8000-000000000006', '0a830000-0000-4000-8000-000000000005',
                       '9a830000-0000-4000-8000-000000000001', 'film-720p'), '23505',
  'an accepted quote funds exactly one hold (quote_id unique)');

-- Bounded holds (T-DB-26: never unbounded, also on the server path), coded before any CHECK -----------------------
select throws_ok($$insert into public.usage_reservations (project_id, owner_id, quote_id, initial_quote_id,
                                                          story_plan_id, output_spec_sha256, cap_credits,
                                                          cap_cost_micro_usd)
                   values ('a7830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'),
                           '0a830000-0000-4000-8000-000000000006', '0a830000-0000-4000-8000-000000000006',
                           '9a830000-0000-4000-8000-000000000001', sha256('cap0'::bytea), 4, 0)$$,
  'P0422', 'invalid_value:cap_cost_micro_usd', 'a hold always has a positive micro-USD cap');
select throws_ok($$update public.usage_reservations set reserved_cost_micro_usd = 1500001
                    where id = 'ae830000-0000-4000-8000-000000000003'$$,
  'P0422', 'invalid_value:reserved_cost_micro_usd', 'stage reservations never exceed the hold''s cap');
select throws_ok($$update public.usage_reservations set reserved_cost_micro_usd = 100, consumed_cost_micro_usd = 80,
                           released_cost_micro_usd = 30 where id = 'ae830000-0000-4000-8000-000000000003'$$,
  'P0422', 'invalid_value:consumed_cost_micro_usd', 'consumed plus released never exceed reserved');
select throws_ok($$insert into public.usage_reservations (project_id, owner_id, quote_id, initial_quote_id,
                                                          story_plan_id, output_spec_sha256, cap_credits,
                                                          cap_cost_micro_usd)
                   values ('a7830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_b'),
                           '0a830000-0000-4000-8000-000000000006', '0a830000-0000-4000-8000-000000000006',
                           '9a830000-0000-4000-8000-000000000001', sha256('ob'::bytea), 4, 1)$$,
  'P0422', 'invalid_value:owner_id', 'a hold belongs to the project''s owner');

-- Consent (contract jovra.quote/1 consent; security-model §13.14) ----------------------------------------------------
create function pg_temp.consent(p_model boolean, p_classes text, p_days int) returns jsonb language sql as $$
  select format('{"consentRecordId": "consent-01", "uploadSelectedSources": true, "modelProvider": %s,
                  "textClasses": %s, "retentionDays": %s, "consentTextVersion": "studio-cloud-consent@1.0.0",
                  "at": "2026-11-08T10:00:00Z"}', p_model, p_classes, p_days)::jsonb
$$;
select throws_ok($$update public.quotes set state = 'accepted', accepted_at = now(),
                           consent = pg_temp.consent(true, '[]', 7)
                    where id = '0a830000-0000-4000-8000-000000000006'$$,
  'P0422', 'invalid_value:consent', 'modelProvider consent on a heuristic quote is refused');
select throws_ok($$update public.quotes set state = 'accepted', accepted_at = now(),
                           consent = pg_temp.consent(false, '["ownerNotes"]', 7)
                    where id = '0a830000-0000-4000-8000-000000000006'$$,
  'P0422', 'invalid_value:consent', '§13.14: no note text class without model consent');
select throws_ok($$update public.quotes set state = 'accepted', accepted_at = now(),
                           consent = pg_temp.consent(false, '[]', 30)
                    where id = '0a830000-0000-4000-8000-000000000006'$$,
  'P0422', 'invalid_value:consent', 'the consented retention must equal the quote''s retention_days');
select throws_ok($$update public.quotes set state = 'accepted', accepted_at = now(),
                           consent = pg_temp.consent(false, '[]', 7) - 'consentTextVersion'
                    where id = '0a830000-0000-4000-8000-000000000006'$$,
  'P0422', 'invalid_value:consent', 'consent without its consentTextVersion is refused');
select throws_ok($$update public.quotes set state = 'accepted', accepted_at = now(), consent = null
                    where id = '0a830000-0000-4000-8000-000000000006'$$,
  'P0422', 'invalid_value:accepted_at', 'an accepted quote always carries its consent');
select lives_ok($$update public.quotes set planner_choice = 'model', state = 'accepted', accepted_at = now(),
                          consent = pg_temp.consent(true, '["ownerNotes", "ownerLessonNotes"]', 7)
                   where id = '0a830000-0000-4000-8000-000000000006'$$,
  '§13.14: a model quote accepted with modelProvider consent and owner text classes is stored');
select throws_ok($$update public.quotes set planner_choice = 'model', consent = pg_temp.consent(true,
                           '["ownerNotes", "ownerNotes"]', 7) where id = '0a830000-0000-4000-8000-000000000006'$$,
  'P0422', 'invalid_value:consent', 'text classes are unique');

-- Jobs: one live job per key (§13.6) ---------------------------------------------------------------------------------
create function pg_temp.job(p_id uuid, p_quote uuid, p_reservation uuid, p_output text) returns text
language plpgsql as $$
declare
  v_state text;
begin
  insert into public.render_jobs (id, project_id, story_plan_id, story_plan_version_id, quote_id, reservation_id,
                                  requested_by, output_spec_sha256, output_spec, sample)
  values (p_id, 'a7830000-0000-4000-8000-000000000001', '9a830000-0000-4000-8000-000000000001', null, p_quote,
          p_reservation, tests.get_supabase_uid('owner'), sha256(convert_to(p_output, 'UTF8')), '{}', true);
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate;
  return v_state;
end $$;
select is(pg_temp.job('1a830000-0000-4000-8000-000000000001', '0a830000-0000-4000-8000-000000000005',
                      'ae830000-0000-4000-8000-000000000005', 'film-1080p'), 'ok',
  'story 199: the accepted plan-by-job work runs as one job');
select is(pg_temp.job('1a830000-0000-4000-8000-000000000002', '0a830000-0000-4000-8000-000000000002',
                      'ae830000-0000-4000-8000-000000000001', 'film-1080p'), '23505',
  'story 199 / §13.6: identical work never runs as a second live job, also with version null');
select is((select state::text from public.render_jobs where id = '1a830000-0000-4000-8000-000000000001'), 'consented',
  'a job created by acceptance starts at consented');
select throws_ok($$update public.render_jobs set stage_progress_milli = 1001
                    where id = '1a830000-0000-4000-8000-000000000001'$$,
  'P0422', 'invalid_value:stage_progress_milli', 'stage progress is per mille, coded before the CHECK');
select is(pg_temp.job('1a830000-0000-4000-8000-000000000003', '0a830000-0000-4000-8000-000000000004',
                      'ae830000-0000-4000-8000-000000000004', 'film-4k'), 'ok',
  'a second job for different work of the plan is allowed');

-- T-DB-53 (table half): `ready` needs a verified, delivered film of this job; the command roles hold no table right --
select is(pg_temp.err('jovra_gateway', 'update public.render_jobs set state = ''ready'''), '42501',
  'T-DB-53: jovra_gateway cannot move a job by writing the table');
select is(pg_temp.err('jovra_orchestrator', 'update public.render_jobs set state = ''ready'''), '42501',
  'T-DB-53: jovra_orchestrator moves jobs only through its commands (S80), never the table');
update public.render_jobs set state = 'verifying' where id = '1a830000-0000-4000-8000-000000000001';
select throws_ok($$update public.render_jobs set state = 'ready' where id = '1a830000-0000-4000-8000-000000000001'$$,
  'P0409', 'artifact_not_verified', 'T-DB-53: verifying -> ready without a verified artifact is P0409');
insert into public.artifacts (id, project_id, job_id, kind, bucket_class, r2_key, state) values
  ('f7830000-0000-4000-8000-000000000001', 'a7830000-0000-4000-8000-000000000001',
   '1a830000-0000-4000-8000-000000000001', 'film', 'films', 'films/a783/f1', 'verifying');
select throws_ok($$update public.render_jobs set state = 'ready' where id = '1a830000-0000-4000-8000-000000000001'$$,
  'P0409', 'artifact_not_verified', 'T-DB-53: a film still verifying is not enough');
insert into public.artifacts (id, project_id, job_id, kind, bucket_class, r2_key, state, verified_at, verification)
values ('f7830000-0000-4000-8000-000000000002', 'a7830000-0000-4000-8000-000000000001',
        '1a830000-0000-4000-8000-000000000001', 'preview', 'work', 'work/a783/p1', 'ready', now(), '{"ok": true}');
select throws_ok($$update public.render_jobs set state = 'ready' where id = '1a830000-0000-4000-8000-000000000001'$$,
  'P0409', 'artifact_not_verified', 'T-DB-53: a verified preview is not a delivered film');
update public.artifacts set state = 'ready', verified_at = now(), verification = '{"fullDecode": "pass"}'
 where id = 'f7830000-0000-4000-8000-000000000001';
select results_eq($$update public.render_jobs set state = 'ready' where id = '1a830000-0000-4000-8000-000000000001'
                    returning state::text, finished_at is not null$$,
  $$values ('ready', true)$$, 'T-DB-53: with a verified film the job reaches ready and is stamped finished');

-- T-DB-59 (FK half): even the table owner cannot pair project A with B's plan or version ---------------------------
create function pg_temp.quote_sql(p_plan text, p_version text) returns text language sql as $$
  select format($f$insert into public.quotes (project_id, owner_id, story_plan_id, story_plan_version_id,
      output_spec_sha256, inputs, inputs_sha256, rates_version, planner_choice, retention_days, estimate_low_credits,
      estimate_high_credits, cap_credits, estimate_high_cost_micro_usd, cap_cost_micro_usd, expires_at)
    values ('a7830000-0000-4000-8000-000000000001', %s, %L, %L, sha256('x'::bytea), '{}', sha256('y'::bytea), 'r',
            'heuristic', 7, 0, 0, 0, 1, 1, now() + interval '1 hour')$f$, pg_temp.uid('owner'), p_plan, p_version)
$$;
create function pg_temp.hold_sql(p_quote text, p_plan text, p_version text) returns text language sql as $$
  select format($f$insert into public.usage_reservations (project_id, owner_id, quote_id, initial_quote_id,
      story_plan_id, story_plan_version_id, output_spec_sha256, cap_credits, cap_cost_micro_usd)
    values ('a7830000-0000-4000-8000-000000000001', %s, %L, %L, %L, %L, sha256('h'::bytea), 1, 1)$f$,
    pg_temp.uid('owner'), p_quote, p_quote, p_plan, p_version)
$$;
create function pg_temp.job_sql(p_plan text, p_version text) returns text language sql as $$
  select format($f$insert into public.render_jobs (project_id, story_plan_id, story_plan_version_id, quote_id,
      reservation_id, output_spec_sha256, output_spec)
    values ('a7830000-0000-4000-8000-000000000001', %L, %L, '0a830000-0000-4000-8000-000000000007',
            'ae830000-0000-4000-8000-000000000003', sha256('j'::bytea), '{}')$f$, p_plan, p_version)
$$;
select is(pg_temp.err('jovra_owner', pg_temp.quote_sql('9b830000-0000-4000-8000-000000000001', null)), '23503',
  'T-DB-59: as jovra_owner, a quote pairing project A with B''s plan is an FK violation');
select is(pg_temp.err('jovra_owner', pg_temp.quote_sql('9a830000-0000-4000-8000-000000000001',
                                                       '5b830000-0000-4000-8000-000000000001')), '23503',
  'T-DB-59: as jovra_owner, a quote naming A''s plan with B''s plan version is an FK violation');
select is(pg_temp.err('jovra_owner', pg_temp.hold_sql('0a830000-0000-4000-8000-000000000003',
                                                      '9b830000-0000-4000-8000-000000000001', null)), '23503',
  'T-DB-59: as jovra_owner, a reservation pairing project A with B''s plan is an FK violation');
select is(pg_temp.err('jovra_owner', pg_temp.hold_sql('0a830000-0000-4000-8000-000000000003',
                                                      '9a830000-0000-4000-8000-000000000001',
                                                      '5b830000-0000-4000-8000-000000000001')), '23503',
  'T-DB-59: as jovra_owner, a reservation naming B''s plan version is an FK violation');
select is(pg_temp.err('jovra_owner', pg_temp.job_sql('9b830000-0000-4000-8000-000000000001', null)), '23503',
  'T-DB-59: as jovra_owner, a job pairing project A with B''s plan is an FK violation');
select is(pg_temp.err('jovra_owner', pg_temp.job_sql('9a830000-0000-4000-8000-000000000002',
                                                     '5b830000-0000-4000-8000-000000000001')), '23503',
  'T-DB-59: as jovra_owner, a job naming B''s plan version is an FK violation');
select is(pg_temp.err('jovra_owner', pg_temp.quote_sql('9a830000-0000-4000-8000-000000000001',
                                                       '5a830000-0000-4000-8000-000000000001')), 'no error',
  'T-DB-59: the same quote with A''s own plan and version passes (the check is the FK, not the role)');
select is(current_user::text, 'postgres', 'the role helper restored the session role');

-- Finding 32: every output carries a byte cap within its kind's ceiling; planner budgets only on the plan stage ------
create function pg_temp.attempt(p_attempt int, p_stage text, p_plan jsonb, p_inputs jsonb, p_budget jsonb,
                                p_reserved bigint) returns text language plpgsql as $$
declare
  v_state text;
  v_msg   text;
begin
  insert into public.render_attempts (job_id, stage, attempt, reserved_cost_micro_usd, output_plan, input_refs,
                                      planner_budget)
  values ('1a830000-0000-4000-8000-000000000003', p_stage::public.job_stage, p_attempt, p_reserved, p_plan, p_inputs,
          p_budget);
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return v_state || ' ' || v_msg;
end $$;
select is(pg_temp.attempt(1, 'final_render', '[{"outputRef": "film-main", "kind": "film", "maxBytes": 4294967297}]',
                          '[]', null, 1000), 'P0422 invalid_value:output_plan',
  'finding 32: an output cap above the film ceiling (4 GiB) is refused');
select is(pg_temp.attempt(1, 'final_render', '[{"outputRef": "film-main", "kind": "film"}]', '[]', null, 1000),
  'P0422 invalid_value:output_plan', 'finding 32: an output without a byte cap is refused');
select is(pg_temp.attempt(1, 'final_render', '[{"outputRef": "x", "kind": "source", "maxBytes": 1}]', '[]', null,
                          1000), 'P0422 invalid_value:output_plan', 'an output must be an artifact kind');
select is(pg_temp.attempt(1, 'final_render', '[{"outputRef": "film-main", "kind": "film", "maxBytes": 4294967296},
                                              {"outputRef": "thumb", "kind": "thumbnail", "maxBytes": 2097152}]',
                          '[{"kind": "source", "id": "5c830000-0000-4000-8000-000000000001"}]', null, 1000), 'ok',
  'finding 32: a film and a thumbnail at their ceilings are accepted');
select is(pg_temp.attempt(2, 'final_render', '[]', '[{"kind": "source", "id": "not-a-uuid"}]', null, 1000),
  'P0422 invalid_value:input_refs', 'input refs name a source or artifact id');
select is(pg_temp.attempt(2, 'final_render', '[]', '[]',
                          '{"maxImages": 8, "maxInputTokens": 1, "maxOutputTokens": 1, "effort": "low",
                            "repairAllowed": false}', 1000),
  'P0422 invalid_value:planner_budget', 'a planner budget only on the plan stage');
select is(pg_temp.attempt(1, 'plan', '[]', '[]', '{"maxImages": 8}', 1000), 'P0422 invalid_value:planner_budget',
  'a planner budget has exactly its five fields');
select is(pg_temp.attempt(1, 'plan', '[]', '[]', null, 0), 'P0422 invalid_value:reserved_cost_micro_usd',
  'T-DB-55 (table half): a zero stage reservation is impossible');
select throws_ok($$insert into public.artifacts (project_id, kind, bucket_class, r2_key, bytes)
                   values ('a7830000-0000-4000-8000-000000000001', 'thumbnail', 'films', 'films/a783/big.jpg',
                           3000000)$$,
  'P0422', 'invalid_value:bytes', 'finding 32: an artifact larger than its kind''s ceiling is refused');

-- Finding 31: excerpts and artifact sources are bound to their own project ----------------------------------------
select tests.create_supabase_user('coach');
insert into public.lessons (id, owner_id, local_lesson_id, title) values
  ('1e830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), 'Serve lesson');
insert into public.lesson_clips (id, lesson_id, project_id, source_id, match_start_us, match_end_us) values
  ('c1830000-0000-4000-8000-000000000001', '1e830000-0000-4000-8000-000000000001',
   'a7830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000001', 1000000, 5000000),
  ('c1830000-0000-4000-8000-000000000002', '1e830000-0000-4000-8000-000000000001',
   'a7830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000001', 6000000, 9000000),
  ('c1830000-0000-4000-8000-000000000003', '1e830000-0000-4000-8000-000000000001',
   'a7830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000001', 10000000, 12000000);
insert into public.artifacts (id, project_id, lesson_clip_id, parent_artifact_id, kind, bucket_class, r2_key, state)
values
  ('f7830000-0000-4000-8000-000000000011', 'a7830000-0000-4000-8000-000000000001',
   'c1830000-0000-4000-8000-000000000001', null, 'clip_excerpt', 'films', 'films/a783/x1', 'ready'),
  ('f7830000-0000-4000-8000-000000000012', 'a7830000-0000-4000-8000-000000000001', null,
   'f7830000-0000-4000-8000-000000000011', 'thumbnail', 'films', 'films/a783/x1.jpg', 'ready'),
  ('f7830000-0000-4000-8000-000000000021', 'a7830000-0000-4000-8000-000000000001',
   'c1830000-0000-4000-8000-000000000002', null, 'clip_excerpt', 'films', 'films/a783/x2', 'ready'),
  ('f7830000-0000-4000-8000-000000000031', 'a7830000-0000-4000-8000-000000000001',
   'c1830000-0000-4000-8000-000000000003', null, 'clip_excerpt', 'films', 'films/a783/x3', 'ready');
update public.lesson_clips c set excerpt_artifact_id = x.id
  from (values ('c1830000-0000-4000-8000-000000000001'::uuid, 'f7830000-0000-4000-8000-000000000011'::uuid),
               ('c1830000-0000-4000-8000-000000000002', 'f7830000-0000-4000-8000-000000000021'),
               ('c1830000-0000-4000-8000-000000000003', 'f7830000-0000-4000-8000-000000000031')) x(clip, id)
 where c.id = x.clip;
insert into public.observations (lesson_id, kind, body, provenance, review_state, created_by) values
  ('1e830000-0000-4000-8000-000000000001', 'note', 'Lesson only', 'manual', 'reviewed',
   tests.get_supabase_uid('owner'));
select throws_ok($$insert into public.artifacts (project_id, lesson_clip_id, kind, bucket_class, r2_key)
                   values ('b7830000-0000-4000-8000-000000000001', 'c1830000-0000-4000-8000-000000000001',
                           'clip_excerpt', 'films', 'films/b783/forged')$$,
  '23503', null, 'finding 31: an excerpt of project B naming A''s clip is an FK violation');
select throws_ok($$insert into public.artifact_sources (artifact_id, project_id, source_id)
                   values ('f7830000-0000-4000-8000-000000000001', 'a7830000-0000-4000-8000-000000000001',
                           '5c830000-0000-4000-8000-000000000002')$$,
  '23503', null, 'finding 31: an artifact of A listing B''s source is an FK violation');
select lives_ok($$insert into public.artifact_sources (artifact_id, project_id, source_id)
                  values ('f7830000-0000-4000-8000-000000000001', 'a7830000-0000-4000-8000-000000000001',
                          '5c830000-0000-4000-8000-000000000001')$$,
  '§13.9 (a): the film lists the source whose frames it holds');

-- Finding 20 (S78 half): clip-share commands write audit rows; every unlinked excerpt queues its object's deletion -----
select is(pg_temp.err('jovra_gateway', format('select app_gateway.approve_clip_share(%s, %L, %L)', pg_temp.uid('owner'),
                                              'c1830000-0000-4000-8000-000000000002',
                                              'eeee0000-0000-4000-8000-000000000001')), 'no error',
  'the project owner approves sharing clip C2');
select is((select count(*)::int from app_ops.audit_events
            where action = 'clip_share.approve' and outcome = 'allowed' and actor_kind = 'user'
              and actor_id = tests.get_supabase_uid('owner') and target_kind = 'lesson_clip'
              and target_id = 'c1830000-0000-4000-8000-000000000002'
              and request_id = 'eeee0000-0000-4000-8000-000000000001'
              and project_id = 'a7830000-0000-4000-8000-000000000001'), 1,
  'approve_clip_share writes one allowed audit row (ids only)');
select is(pg_temp.err('jovra_gateway', format('select app_gateway.revoke_clip_share(%s, %L, %L)', pg_temp.uid('owner'),
                                              'c1830000-0000-4000-8000-000000000002',
                                              'eeee0000-0000-4000-8000-000000000002')), 'no error',
  'the project owner withdraws the share');
select results_eq($$select c.share_approved_at is null, c.excerpt_artifact_id is null, a.deleted_at is not null
                      from public.lesson_clips c, public.artifacts a
                     where c.id = 'c1830000-0000-4000-8000-000000000002'
                       and a.id = 'f7830000-0000-4000-8000-000000000021'$$,
  $$values (true, true, true)$$, 'T-DB-62: revoke_clip_share clears the approval, unlinks and hides the excerpt');
select is((select count(*)::int from app_ops.job_outbox
            where kind = 'delete_object' and job_id is null
              and payload = '{"artifactId": "f7830000-0000-4000-8000-000000000021"}'::jsonb), 1,
  'the withdrawn excerpt''s object deletion is queued in the outbox (ids only)');
select is((select count(*)::int from app_ops.audit_events
            where action = 'clip_share.revoke' and target_id = 'c1830000-0000-4000-8000-000000000002'), 1,
  'revoke_clip_share writes an audit row');
update public.lesson_clips set match_start_us = 10500000 where id = 'c1830000-0000-4000-8000-000000000003';
select is((select count(*)::int from app_ops.job_outbox
            where kind = 'delete_object'
              and payload = '{"artifactId": "f7830000-0000-4000-8000-000000000031"}'::jsonb), 1,
  'finding 20: a moved window also queues the unlinked excerpt''s object deletion');
select is(pg_temp.err('jovra_gateway', format('select app_gateway.revoke_clip_share(%L, %L, %L)',
                                              tests.get_supabase_uid('coach'), 'c1830000-0000-4000-8000-000000000001',
                                              'eeee0000-0000-4000-8000-000000000003')), 'P0404',
  'anyone but the project owner gets P0404, and nothing is written (the failed command rolls back)');
select is((select count(*)::int from app_ops.audit_events where request_id = 'eeee0000-0000-4000-8000-000000000003'), 0,
  'a refused command leaves no allowed audit row (denials are audited by audit_denial, S79)');

-- T-DB-48: lesson-scope deletion removes excerpt objects first, then the clips, lesson-only observations and excerpts --
select tests.authenticate_as('owner');
select throws_ok('delete from public.lesson_clips', '42501', 'permission denied for table lesson_clips',
  'T-DB-48: the owner cannot delete a lesson clip directly');
select throws_ok('delete from public.lessons', '42501', 'permission denied for table lessons',
  'T-DB-48: the owner cannot delete a lesson directly');
reset role;
select results_eq($$select id::text from app_private.lesson_deletion_artifacts('1e830000-0000-4000-8000-000000000001')
                    order by 1$$,
  $$values ('f7830000-0000-4000-8000-000000000011'), ('f7830000-0000-4000-8000-000000000012'),
           ('f7830000-0000-4000-8000-000000000021'), ('f7830000-0000-4000-8000-000000000031')$$,
  'T-DB-48: the deletion step enumerates every excerpt of the lesson and the excerpts'' children (objects first)');
insert into public.deletion_requests (id, requested_by, scope, target_id) values
  ('de830000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), 'lesson',
   '1e830000-0000-4000-8000-000000000001');
select throws_ok($$insert into public.deletion_requests (requested_by, scope, target_id)
                   values (tests.get_supabase_uid('owner'), 'lesson', '1e830000-0000-4000-8000-000000000001')$$,
  '23505', null, 'story 199: a double tap never starts a second deletion of the same lesson');
select throws_ok($$insert into public.deletion_requests (requested_by, scope, target_id)
                   values (tests.get_supabase_uid('owner'), 'account', tests.get_supabase_uid('owner_b'))$$,
  'P0422', 'invalid_value:target_id', 'an account deletion is always the requester''s own account');
select throws_ok($$update public.deletion_requests set counts = '{"objects": "many"}'
                    where id = 'de830000-0000-4000-8000-000000000001'$$,
  'P0422', 'invalid_value:counts', 'deletion counts are numbers only');
delete from public.lessons where id = '1e830000-0000-4000-8000-000000000001';   -- the deleting_rows step
select is((select count(*)::int from public.lesson_clips where lesson_id = '1e830000-0000-4000-8000-000000000001')
          + (select count(*)::int from public.observations where lesson_id = '1e830000-0000-4000-8000-000000000001'),
  0, 'T-DB-48: the row step removes the lesson''s clips and lesson-only observations');
select is((select count(*)::int from public.artifacts
            where id in ('f7830000-0000-4000-8000-000000000011', 'f7830000-0000-4000-8000-000000000012',
                         'f7830000-0000-4000-8000-000000000021', 'f7830000-0000-4000-8000-000000000031')), 0,
  'T-DB-48: and the excerpt rows and their children');
select is((select count(*)::int from public.artifacts where id = 'f7830000-0000-4000-8000-000000000001'), 1,
  'T-DB-48: the match film is untouched');
update public.deletion_requests set state = 'done', finished_at = now(), counts = '{"objects": 4, "rows": 9}'
 where id = 'de830000-0000-4000-8000-000000000001';
select is((select state from public.deletion_requests where id = 'de830000-0000-4000-8000-000000000001'), 'done',
  'the request reaches done with numeric counts');

-- T-DB-47 (table half): no bearer token, JWT or email is storable in app_ops ---------------------------------------
select throws_ok($$insert into app_ops.idempotency_records (actor_id, route, key, request_sha256, response_status,
                                                            response_body)
                   values (gen_random_uuid(), 'POST /v1/projects/{id}/coach-invites', 'k1', sha256('r'::bytea), 201,
                           jsonb_build_object('grantId', gen_random_uuid(), 'code', 'jvc_' || repeat('A', 43)))$$,
  'P0422', 'secret_not_storable', 'T-DB-47: an idempotency body holding an invitation code is refused');
select lives_ok($$insert into app_ops.idempotency_records (actor_id, route, key, request_sha256, response_status,
                                                           response_body, redacted)
                  values (gen_random_uuid(), 'POST /v1/projects/{id}/coach-invites', 'k2', sha256('r'::bytea), 201,
                          jsonb_build_object('grantId', gen_random_uuid(), 'expiresAt', '2026-11-15T00:00:00Z'), true)$$,
  'T-DB-47: the redacted body (ids and expiry) is stored');
select throws_ok($$insert into app_ops.job_outbox (job_id, kind, payload)
                   values ('1a830000-0000-4000-8000-000000000001', 'dispatch_attempt',
                           jsonb_build_object('attemptId', 'jvl_' || repeat('b', 43)))$$,
  'P0422', 'secret_not_storable', 'T-DB-47: a lease token never lands in the outbox');
select throws_ok($$insert into app_ops.job_outbox (job_id, kind, payload)
                   values ('1a830000-0000-4000-8000-000000000001', 'start_workflow',
                           jsonb_build_object('jobId', '1a830000-0000-4000-8000-000000000001', 'note', 'x'))$$,
  'P0422', 'invalid_value:payload', 'outbox payloads hold ids only, one shape per kind');
select throws_ok($$insert into app_ops.audit_events (env, actor_kind, action, outcome, detail)
                   values ('local', 'gateway', 'grant.create', 'allowed', '{"to": "owner.tester@example.test"}')$$,
  'P0422', 'secret_not_storable', 'T-DB-47: an email address never lands in the audit log');
select throws_ok($$insert into app_ops.upload_sessions (project_id, source_id, actor_kind, r2_key, r2_upload_id,
                                                        expected_bytes, expected_sha256, part_count, expires_at,
                                                        hard_expires_at)
                   values ('a7830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000001', 'owner',
                           'staging/p/a783/s/1/original/1', 'jvs_' || repeat('c', 43), 100000000,
                           sha256('o'::bytea), 3, now() + interval '24 hours', now() + interval '48 hours')$$,
  'P0422', 'secret_not_storable', 'T-DB-47: a session capability never lands in an upload session row');
create function pg_temp.app_ops_rows_matching(p_pattern text) returns int language plpgsql as $$
declare
  v_table regclass;
  v_n     int;
  v_total int := 0;
begin
  for v_table in select c.oid::regclass from pg_class c
                  where c.relnamespace = 'app_ops'::regnamespace and c.relkind = 'r' loop
    execute format('select count(*)::int from %s x where to_jsonb(x)::text ~ %L', v_table, p_pattern) into v_n;
    v_total := v_total + v_n;
  end loop;
  return v_total;
end $$;
-- The scan can fail: with the guard bypassed (table owner only), a secret row is found; then it is removed.
alter table app_ops.idempotency_records disable trigger a05_refuse_secrets;
insert into app_ops.idempotency_records (actor_id, route, key, request_sha256, response_status, response_body)
values (gen_random_uuid(), 'POST /v1/films/{id}/share-links', 'k3', sha256('r'::bytea), 201,
        jsonb_build_object('url', 'https://gateway.example.test/s/jvh_' || repeat('d', 43)));
select is(pg_temp.app_ops_rows_matching('jv[igslhc]_'), 1, 'T-DB-47: the app_ops scan finds a planted secret');
delete from app_ops.idempotency_records where key = 'k3';
alter table app_ops.idempotency_records enable trigger a05_refuse_secrets;
select is(pg_temp.app_ops_rows_matching('jv[igslhc]_'), 0,
  'T-DB-47: after every write in this file (holds, jobs, outbox, audit, idempotency), no jv[igslhc]_ value in app_ops');

-- Upload sessions: one open per source, an absolute 48 h ceiling ----------------------------------------------------
select lives_ok($$insert into app_ops.upload_sessions (project_id, source_id, actor_kind, r2_key, expected_bytes,
                                                       expected_sha256, part_count, expires_at, hard_expires_at)
                  values ('a7830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000001', 'owner',
                          'staging/p/a783/s/1/original/2', 100000000, sha256('o'::bytea), 3,
                          now() + interval '24 hours', now() + interval '48 hours')$$,
  'an upload session for a source of the project is opened (3 parts of 32 MiB for 100 MB)');
select throws_ok($$insert into app_ops.upload_sessions (project_id, source_id, actor_kind, r2_key, expected_bytes,
                                                        expected_sha256, part_count, expires_at, hard_expires_at)
                   values ('a7830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000001', 'owner',
                           'staging/p/a783/s/1/original/3', 100000000, sha256('o'::bytea), 3,
                           now() + interval '24 hours', now() + interval '48 hours')$$,
  '23505', null, 'one open session per source');
update app_ops.upload_sessions set state = 'completed', completed_at = now()
 where r2_key = 'staging/p/a783/s/1/original/2';
select throws_ok($$insert into app_ops.upload_sessions (project_id, source_id, actor_kind, r2_key, expected_bytes,
                                                        expected_sha256, part_count, expires_at, hard_expires_at)
                   values ('b7830000-0000-4000-8000-000000000001', '5c830000-0000-4000-8000-000000000001', 'owner',
                           'staging/p/b783/s/1/original/4', 100000000, sha256('o'::bytea), 3,
                           now() + interval '24 hours', now() + interval '48 hours')$$,
  '23503', null, 'finding 31: a session of project B naming A''s source is an FK violation');

-- Append-only ledgers and fail-closed limits (§13.7) ---------------------------------------------------------------
insert into app_ops.spend_commitments (owner_id, reservation_id, kind, amount_micro_usd)
values (tests.get_supabase_uid('owner'), 'ae830000-0000-4000-8000-000000000005', 'cap_open', 1500000);
select throws_ok($$update app_ops.spend_commitments set amount_micro_usd = 1$$, 'P0409', 'append_only',
  'the spend ledger cannot be rewritten');
select throws_ok($$delete from app_ops.spend_commitments$$, 'P0409', 'append_only',
  'the spend ledger cannot be trimmed');
select throws_ok($$delete from app_ops.audit_events$$, 'P0409', 'append_only',
  'recent audit rows cannot be deleted');
insert into app_ops.audit_events (at, env, actor_kind, action, outcome)
values (now() - interval '401 days', 'local', 'cron', 'audit.sample', 'allowed');
select lives_ok($$delete from app_ops.audit_events where at < now() - interval '400 days'$$,
  'the 400-day audit purge is allowed');
select throws_ok($$insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
                   values ('owner', null, 1, 1)$$, '23505', null, 'at most one default owner spend-limit row');
select throws_ok($$insert into app_ops.spend_limits (scope, max_open_cap_micro_usd, daily_ceiling_micro_usd)
                   values ('environment', 1, null)$$, '23502', null, 'a spend limit is never NULL');

select * from finish();
rollback;
