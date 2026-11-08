-- Migration 3 under every role that reaches it (S78 / B-05): money is the owner's alone and credits only (T-DB-25,
-- T-DB-17), coaches read jobs and attempts but never money or measurements (finding 32), owners cannot create or
-- change a quote, hold, job, attempt, ready artifact, grant or deletion request (T-DB-26), grantees read their own
-- grants (T-DB-27), provider rows are their user's alone (T-DB-29, T-DB-28), unrelated users see nothing (T-DB-06)
-- and project deletion hides everything at once, also from viewers (T-DB-50, T-DB-31). User stories 199, 201, 241.
-- docs/backend/security-model.md §5.6, §5.7, §6.1, §6.2. Fixtures are written as postgres (the server path).
-- The file rolls back.
begin;
select plan(67);

select tests.create_supabase_user('owner');        -- owns project A
select tests.create_supabase_user('owner_b');      -- owns project B
select tests.create_supabase_user('coach');        -- approved coach of A
select tests.create_supabase_user('viewer');       -- film_view on film F of A
select tests.create_supabase_user('clip_viewer');  -- lesson_clip_view on clip C of A
select tests.create_supabase_user('unrelated');
select tests.create_supabase_user('anonymous_user');
update auth.users set is_anonymous = true where id = tests.get_supabase_uid('anonymous_user');

insert into public.projects (id, owner_id, local_project_id, title) values
  ('a7800000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), 'Club final'),
  ('b7800000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_b'), gen_random_uuid(), 'Other match');
insert into public.project_members (project_id, user_id, role, granted_by, approved_at) values
  ('a7800000-0000-4000-8000-000000000001', tests.get_supabase_uid('coach'), 'coach',
   tests.get_supabase_uid('owner'), now());
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a780000-0000-4000-8000-000000000001', 'a7800000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Coach cut'),
  ('9b780000-0000-4000-8000-000000000001', 'b7800000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Other cut');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a780000-0000-4000-8000-000000000001', '9a780000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}'),
  ('5b780000-0000-4000-8000-000000000001', '9b780000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}');

-- An accepted quote of A, its hold, the job and one plan attempt with measurements; a quote of B for B's owner.
insert into public.quotes (id, project_id, owner_id, story_plan_id, story_plan_version_id, output_spec_sha256, inputs,
                           inputs_sha256, rates_version, planner_choice, retention_days, estimate_low_credits,
                           estimate_high_credits, cap_credits, estimate_high_cost_micro_usd, cap_cost_micro_usd, state,
                           expires_at, accepted_at, consent, sample)
values
  ('0a780000-0000-4000-8000-000000000001', 'a7800000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'),
   '9a780000-0000-4000-8000-000000000001', '5a780000-0000-4000-8000-000000000001', sha256('out-a'::bytea), '{}',
   sha256('in-a'::bytea), 'rates-test-1', 'heuristic', 7, 2, 4, 4, 1290000, 1500000, 'accepted',
   now() + interval '30 minutes', now(),
   '{"consentRecordId": "consent-upload-01", "uploadSelectedSources": true, "modelProvider": false,
     "textClasses": [], "retentionDays": 7, "consentTextVersion": "studio-cloud-consent@1.0.0",
     "at": "2026-10-07T22:49:30Z"}', true),
  ('0b780000-0000-4000-8000-000000000001', 'b7800000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_b'),
   '9b780000-0000-4000-8000-000000000001', null, sha256('out-b'::bytea), '{}', sha256('in-b'::bytea),
   'rates-test-1', 'heuristic', 7, 2, 4, 4, 1290000, 1500000, 'open', now() + interval '30 minutes', null, null,
   true);
insert into public.usage_reservations (id, project_id, owner_id, quote_id, initial_quote_id, story_plan_id,
                                       story_plan_version_id, output_spec_sha256, cap_credits, cap_cost_micro_usd,
                                       reserved_cost_micro_usd, sample)
values ('ae780000-0000-4000-8000-000000000001', 'a7800000-0000-4000-8000-000000000001',
        tests.get_supabase_uid('owner'), '0a780000-0000-4000-8000-000000000001',
        '0a780000-0000-4000-8000-000000000001', '9a780000-0000-4000-8000-000000000001',
        '5a780000-0000-4000-8000-000000000001', sha256('out-a'::bytea), 4, 1500000, 400000, true);
insert into public.render_jobs (id, project_id, story_plan_id, story_plan_version_id, quote_id, reservation_id,
                                requested_by, output_spec_sha256, output_spec, state, stage, stage_progress_milli,
                                sample)
values ('1a780000-0000-4000-8000-000000000001', 'a7800000-0000-4000-8000-000000000001',
        '9a780000-0000-4000-8000-000000000001', '5a780000-0000-4000-8000-000000000001',
        '0a780000-0000-4000-8000-000000000001', 'ae780000-0000-4000-8000-000000000001',
        tests.get_supabase_uid('owner'), sha256('out-a'::bytea), '{"width": 1920, "height": 1080}', 'planning',
        'plan', 420, true);
update public.usage_reservations set job_id = '1a780000-0000-4000-8000-000000000001'
 where id = 'ae780000-0000-4000-8000-000000000001';
insert into public.render_attempts (id, job_id, stage, attempt, state, reserved_cost_micro_usd, measurements,
                                    lease_token_hash, claimed_by_host, leased_until, host_kind, planner_budget)
values ('2a780000-0000-4000-8000-000000000001', '1a780000-0000-4000-8000-000000000001', 'plan', 1, 'running',
        400000, '{"plannerTokens": {"input": 12000, "output": 900}, "wallMs": 41000}', sha256('lease'::bytea),
        'host-local-1', now() + interval '5 minutes', 'local-test',
        '{"maxImages": 8, "maxInputTokens": 20000, "maxOutputTokens": 4000, "effort": "medium",
          "repairAllowed": true}');

-- Media of A: film F (verified) with its thumbnail; owner lesson L with clip C and its excerpt X.
insert into public.artifacts (id, project_id, job_id, parent_artifact_id, kind, bucket_class, r2_key, state,
                              verified_at, verification)
values
  ('f7800000-0000-4000-8000-000000000001', 'a7800000-0000-4000-8000-000000000001',
   '1a780000-0000-4000-8000-000000000001', null, 'film', 'films', 'films/a78/f1', 'ready', now(), '{"ok": true}'),
  ('f7800000-0000-4000-8000-000000000002', 'a7800000-0000-4000-8000-000000000001',
   '1a780000-0000-4000-8000-000000000001', 'f7800000-0000-4000-8000-000000000001', 'thumbnail', 'films',
   'films/a78/f1.jpg', 'ready', now(), '{"ok": true}');
insert into public.lessons (id, owner_id, local_lesson_id, lesson_date, title) values
  ('1e780000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), current_date,
   'Serve lesson');
insert into public.lesson_clips (id, lesson_id, project_id, match_start_us, match_end_us) values
  ('c1780000-0000-4000-8000-000000000001', '1e780000-0000-4000-8000-000000000001',
   'a7800000-0000-4000-8000-000000000001', 1000000, 5000000);
insert into public.artifacts (id, project_id, lesson_clip_id, kind, bucket_class, r2_key, state) values
  ('f7800000-0000-4000-8000-000000000003', 'a7800000-0000-4000-8000-000000000001',
   'c1780000-0000-4000-8000-000000000001', 'clip_excerpt', 'films', 'films/a78/x-c', 'ready');
update public.lesson_clips set excerpt_artifact_id = 'f7800000-0000-4000-8000-000000000003'
 where id = 'c1780000-0000-4000-8000-000000000001';
insert into public.access_grants (id, kind, project_id, artifact_id, lesson_clip_id, grantee_user_id,
                                  invitee_email_hmac, created_by, redeem_by, redeemed_at)
values
  ('6a780000-0000-4000-8000-000000000001', 'film_view', 'a7800000-0000-4000-8000-000000000001',
   'f7800000-0000-4000-8000-000000000001', null, tests.get_supabase_uid('viewer'), sha256('v'::bytea),
   tests.get_supabase_uid('owner'), now() + interval '1 day', now()),
  ('6a780000-0000-4000-8000-000000000002', 'lesson_clip_view', null, null, 'c1780000-0000-4000-8000-000000000001',
   tests.get_supabase_uid('clip_viewer'), sha256('cv'::bytea), tests.get_supabase_uid('owner'),
   now() + interval '1 day', now());
insert into public.deletion_requests (id, requested_by, scope, target_id) values
  ('de780000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), 'artifact',
   'f7800000-0000-4000-8000-000000000002');

-- Owner: money as credits only; no write to anything money, job, media or grant shaped -----------------------------
select tests.authenticate_as('owner');
select results_eq($$select id::text, cap_credits, state from public.quotes$$,
  $$values ('0a780000-0000-4000-8000-000000000001', 4, 'accepted')$$,
  'story 201: the owner reads their own quote (credits, state), not B''s');
select results_eq($$select id::text, cap_credits, state, job_id::text from public.usage_reservations$$,
  $$values ('ae780000-0000-4000-8000-000000000001', 4, 'held', '1a780000-0000-4000-8000-000000000001')$$,
  'story 201: the owner reads the hold that bounds the job (credits only)');
select results_eq($$select state::text, stage::text, stage_progress_milli from public.render_jobs$$,
  $$values ('planning', 'plan', 420)$$, 'the owner reads the job''s state, stage and stage progress');
select throws_ok('select cap_cost_micro_usd from public.quotes', '42501', 'permission denied for table quotes',
  'T-DB-17: quotes.cap_cost_micro_usd is not selectable, even by the owner');
select throws_ok('select reserved_cost_micro_usd from public.usage_reservations', '42501',
  'permission denied for table usage_reservations', 'T-DB-17: reservation micro-USD columns are not selectable');
select throws_ok('select lease_token_hash from public.render_attempts', '42501',
  'permission denied for table render_attempts', 'T-DB-17: render_attempts.lease_token_hash is not selectable');
select throws_ok('select measurements from public.render_attempts', '42501',
  'permission denied for table render_attempts', 'finding 32: the owner reads usage through the gateway, not rows');
select throws_ok('select reservation_id from public.render_jobs', '42501', 'permission denied for table render_jobs',
  'render_jobs.reservation_id is not selectable');

-- T-DB-26: no direct create or update of a quote, hold, job, attempt, ready artifact, grant or deletion request
select throws_ok($$insert into public.quotes (project_id, owner_id, story_plan_id, output_spec_sha256, inputs,
                                              inputs_sha256, rates_version, planner_choice, retention_days,
                                              estimate_low_credits, estimate_high_credits, cap_credits,
                                              estimate_high_cost_micro_usd, cap_cost_micro_usd, expires_at)
                   values ('a7800000-0000-4000-8000-000000000001', auth.uid(), '9a780000-0000-4000-8000-000000000001',
                           sha256('x'::bytea), '{}', sha256('y'::bytea), 'r', 'heuristic', 7, 0, 0, 0, 1, 1,
                           now() + interval '1 hour')$$,
  '42501', 'permission denied for table quotes', 'T-DB-26: owner cannot create a quote');
select throws_ok($$update public.quotes set state = 'accepted', cap_credits = 1000$$, '42501',
  'permission denied for table quotes', 'T-DB-26: owner cannot accept or re-price a quote directly');
select throws_ok($$insert into public.usage_reservations (project_id, owner_id, quote_id, initial_quote_id,
                                                          story_plan_id, output_spec_sha256, cap_credits,
                                                          cap_cost_micro_usd)
                   values ('a7800000-0000-4000-8000-000000000001', auth.uid(),
                           '0a780000-0000-4000-8000-000000000001', '0a780000-0000-4000-8000-000000000001',
                           '9a780000-0000-4000-8000-000000000001', sha256('x'::bytea), 2147483647,
                           9223372036854775807)$$,
  '42501', 'permission denied for table usage_reservations', 'T-DB-26: owner cannot create an unbounded reservation');
select throws_ok($$update public.usage_reservations set cap_credits = 1000$$, '42501',
  'permission denied for table usage_reservations', 'T-DB-26: owner cannot raise a hold''s cap');
select throws_ok($$insert into public.render_jobs (project_id, story_plan_id, quote_id, reservation_id,
                                                   output_spec_sha256, output_spec)
                   values ('a7800000-0000-4000-8000-000000000001', '9a780000-0000-4000-8000-000000000001',
                           '0a780000-0000-4000-8000-000000000001', 'ae780000-0000-4000-8000-000000000001',
                           sha256('z'::bytea), '{}')$$,
  '42501', 'permission denied for table render_jobs', 'T-DB-26: owner cannot create a job');
select throws_ok($$update public.render_jobs set state = 'ready'$$, '42501', 'permission denied for table render_jobs',
  'T-DB-26: owner cannot move a job to ready');
select throws_ok($$insert into public.render_attempts (job_id, stage, attempt, reserved_cost_micro_usd)
                   values ('1a780000-0000-4000-8000-000000000001', 'final_render', 1, 1)$$,
  '42501', 'permission denied for table render_attempts', 'T-DB-26: owner cannot create an attempt');
select throws_ok($$insert into public.artifacts (project_id, kind, bucket_class, r2_key, state, verified_at)
                   values ('a7800000-0000-4000-8000-000000000001', 'film', 'films', 'films/a78/forged', 'ready',
                           now())$$,
  '42501', 'permission denied for table artifacts', 'T-DB-26: owner cannot create a ready artifact');
select throws_ok($$update public.artifacts set state = 'ready', stale = false$$, '42501',
  'permission denied for table artifacts', 'T-DB-26: owner cannot mark an artifact ready');
select throws_ok($$update public.access_grants set revoked_at = null, expires_at = null$$, '42501',
  'permission denied for table access_grants', 'T-DB-26: owner cannot extend or un-revoke a grant directly');
select throws_ok($$insert into public.deletion_requests (scope, target_id)
                   values ('project', 'a7800000-0000-4000-8000-000000000001')$$,
  '42501', 'permission denied for table deletion_requests', 'T-DB-26: deletion requests go through the gateway');
select throws_ok($$update public.deletion_requests set state = 'done'$$, '42501',
  'permission denied for table deletion_requests', 'T-DB-26: owner cannot mark a deletion done');
select throws_ok($$insert into public.artifact_sources (artifact_id, project_id, source_id)
                   values ('f7800000-0000-4000-8000-000000000001', 'a7800000-0000-4000-8000-000000000001',
                           gen_random_uuid())$$,
  '42501', 'permission denied for table artifact_sources', 'artifact_sources is server-written');
select results_eq($$select id::text, scope::text, state from public.deletion_requests$$,
  $$values ('de780000-0000-4000-8000-000000000001', 'artifact', 'requested')$$,
  'the requester reads their own deletion request');

-- T-DB-27 (creator half): the creator reads the grants they made, without the token hash
select results_eq($$select id::text from public.access_grants order by id$$,
  $$values ('6a780000-0000-4000-8000-000000000001'), ('6a780000-0000-4000-8000-000000000002')$$,
  'T-DB-27: the creator reads both grants they created');

-- T-DB-29: provider status rows are the user's own -----------------------------------------------------------------
select results_eq($$insert into public.provider_connections (provider, state, account_label, scopes)
                    values ('google_drive', 'connected', 'Match archive', '{drive.file}')
                    returning user_id, revision$$,
  $$values (tests.get_supabase_uid('owner'), 1::bigint)$$, 'T-DB-29: a user records a provider status row as themself');
select throws_ok($$insert into public.provider_connections (user_id, provider)
                   values (tests.get_supabase_uid('unrelated'), 'box')$$,
  '42501', 'permission denied for table provider_connections', 'T-DB-29: user_id is never client-chosen');
select throws_ok($$insert into public.provider_connections (provider) values ('google_drive')$$,
  'P0409', 'already_exists', 'one row per (user, provider), with a coded error');
select throws_ok($$insert into public.provider_connections (provider, account_label)
                   values ('dropbox', 'owner.tester@example.test')$$,
  'P0422', 'invalid_value:account_label', 'no email address is copied into account_label');
select throws_ok($$insert into public.provider_connections (provider, scopes)
                   values ('dropbox', '{https://www.googleapis.com/auth/drive.file}')$$,
  'P0422', 'invalid_value:scopes', '§13.17: a scope can never carry a URL');
select results_eq($$update public.provider_connections set state = 'expired' where provider = 'google_drive'
                    returning state, revision$$,
  $$values ('expired', 2::bigint)$$, 'T-DB-29: the user updates their status row; the revision is bumped');
reset role;

-- Coach: jobs and attempts yes; money and measurements never (T-DB-25, finding 32) -------------------------------
select tests.authenticate_as('coach');
select is((select count(*)::int from public.quotes), 0, 'T-DB-25: a coach sees 0 quotes');
select is((select count(*)::int from public.usage_reservations), 0, 'T-DB-25: a coach sees 0 reservations');
select results_eq($$select id::text, state::text from public.render_jobs$$,
  $$values ('1a780000-0000-4000-8000-000000000001', 'planning')$$, 'a coach reads the project''s job');
select results_eq($$select id::text, stage::text, attempt, state from public.render_attempts$$,
  $$values ('2a780000-0000-4000-8000-000000000001', 'plan', 1, 'running')$$,
  'a coach reads the job''s attempts (granted columns)');
select throws_ok('select measurements from public.render_attempts', '42501',
  'permission denied for table render_attempts',
  'T-DB-25 / finding 32: a coach selecting render_attempts.measurements is denied (no cost is derivable)');
select throws_ok('select * from public.render_attempts', '42501', 'permission denied for table render_attempts',
  'finding 32: select * cannot reach measurements either');
select throws_ok('select planner_budget from public.render_attempts', '42501',
  'permission denied for table render_attempts', 'finding 32: planner_budget (derived from cost) is hidden');
select is((select count(*)::int from public.access_grants), 0, 'a coach sees no grants they neither made nor hold');
select is((select count(*)::int from public.provider_connections), 0, 'T-DB-29: a coach sees 0 of the owner''s providers');
reset role;

-- Viewer and clip viewer: their own grants only (T-DB-27) ------------------------------------------------------
select tests.authenticate_as('viewer');
select results_eq($$select id::text, kind::text from public.access_grants$$,
  $$values ('6a780000-0000-4000-8000-000000000001', 'film_view')$$, 'T-DB-27: the grantee reads their own grant row');
select throws_ok('select token_hash from public.access_grants', '42501', 'permission denied for table access_grants',
  'T-DB-17: the grantee cannot read the token hash');
select is((select count(*)::int from public.artifacts), 2, 'the film viewer sees the film and its thumbnail');
select is((select count(*)::int from public.render_jobs) + (select count(*)::int from public.quotes)
          + (select count(*)::int from public.render_attempts), 0, 'a viewer sees no job, attempt or quote');
reset role;
select tests.authenticate_as('clip_viewer');
select results_eq($$select id::text from public.access_grants$$, $$values ('6a780000-0000-4000-8000-000000000002')$$,
  'T-DB-27: the clip viewer reads their own grant row');
select is((select count(*)::int from public.lesson_clips), 1, 'the clip viewer sees the clip');
reset role;

-- Unrelated user: nothing of A (T-DB-06 for the new tables, T-DB-27, T-DB-29) ------------------------------------
select tests.authenticate_as('unrelated');
select is((select count(*)::int from public.quotes), 0, 'T-DB-06: unrelated user sees 0 quotes');
select is((select count(*)::int from public.usage_reservations), 0, 'T-DB-06: unrelated user sees 0 reservations');
select is((select count(*)::int from public.render_jobs), 0, 'T-DB-06: unrelated user sees 0 jobs');
select is((select count(*)::int from public.render_attempts), 0, 'T-DB-06: unrelated user sees 0 attempts');
select is((select count(*)::int from public.artifacts), 0, 'T-DB-06: unrelated user sees 0 artifacts');
select is((select count(*)::int from public.access_grants), 0, 'T-DB-27: unrelated user sees 0 grants');
select is((select count(*)::int from public.deletion_requests), 0, 'unrelated user sees 0 deletion requests');
select is((select count(*)::int from public.provider_connections), 0,
  'T-DB-29: unrelated user sees 0 of another user''s provider rows');
select is_empty($$update public.provider_connections set state = 'revoked' returning id$$,
  'T-DB-29: unrelated user updates 0 provider rows');
select is_empty($$delete from public.provider_connections returning id$$,
  'T-DB-29: unrelated user deletes 0 provider rows');
reset role;

-- T-DB-28: an anonymous-authenticated user touches nothing, provider rows included -------------------------------
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', tests.get_supabase_uid('anonymous_user')::text,
  'role', 'authenticated', 'aud', 'authenticated', 'is_anonymous', true)::text, true);
select set_config('role', 'authenticated', true);
select is((select count(*)::int from public.provider_connections) + (select count(*)::int from public.render_jobs)
          + (select count(*)::int from public.deletion_requests), 0,
  'T-DB-28: an anonymous user sees 0 provider rows, jobs and deletion requests');
select throws_ok($$insert into public.provider_connections (provider) values ('box')$$, '42501',
  'new row violates row-level security policy for table "provider_connections"',
  'T-DB-28: an anonymous user cannot record a provider row (RLS violation)');
reset role;
select set_config('request.jwt.claims', '', true);

-- Owner deletes their provider row (status only; nothing derived) --------------------------------------------------
select tests.authenticate_as('owner');
select results_eq($$delete from public.provider_connections returning provider::text$$, $$values ('google_drive')$$,
  'T-DB-29: the user deletes their own provider status row');
reset role;

-- T-DB-50 / T-DB-31: once the owner starts project deletion, viewers, coaches and the owner see 0 rows at once ----
update public.projects set deleted_at = now() where id = 'a7800000-0000-4000-8000-000000000001';
select tests.authenticate_as('viewer');
select is((select count(*)::int from public.artifacts), 0, 'T-DB-50: the film viewer sees 0 artifacts');
select is((select count(*)::int from public.access_grants), 0, 'T-DB-50: the film viewer sees 0 grant rows');
reset role;
select tests.authenticate_as('clip_viewer');
select is((select count(*)::int from public.lesson_clips), 0, 'T-DB-50: the clip viewer sees 0 clips');
select is((select count(*)::int from public.artifacts), 0, 'T-DB-50: the clip viewer sees 0 excerpts');
select is((select count(*)::int from public.access_grants), 0, 'T-DB-50: the clip viewer sees 0 grant rows');
reset role;
select tests.authenticate_as('coach');
select is((select count(*)::int from public.render_jobs) + (select count(*)::int from public.render_attempts), 0,
  'T-DB-31: a coach sees 0 jobs and attempts of a project being deleted');
reset role;
select tests.authenticate_as('owner');
select is((select count(*)::int from public.quotes) + (select count(*)::int from public.usage_reservations)
          + (select count(*)::int from public.render_jobs) + (select count(*)::int from public.render_attempts), 0,
  'T-DB-31: the owner sees 0 quotes, holds, jobs and attempts of a project being deleted');
select is((select count(*)::int from public.access_grants), 0,
  'T-DB-31: the creator no longer sees the grants of a project being deleted');
select is((select count(*)::int from public.deletion_requests), 1,
  'the deletion request itself stays visible to its requester');
reset role;
select tests.authenticate_as('owner_b');
select results_eq($$select id::text from public.quotes$$, $$values ('0b780000-0000-4000-8000-000000000001')$$,
  'B''s owner still reads B''s own quote (the deletion of A changes nothing for B)');
reset role;

select * from finish();
rollback;
