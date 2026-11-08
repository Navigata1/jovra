-- Quotas on direct PostgREST writes (S77 / finding 23, security-model §13.10): per-table limits per project or per
-- user, the per-user aggregate across every quota'd table and project, fail-closed on a missing limits row, and
-- refusals that roll their counter increments back. T-DB-64 and T-DB-70. The limits are lowered inside this
-- transaction so the boundaries are reachable; the shipped values are in the migration. The file rolls back.
begin;
select plan(25);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('owner2');
select tests.create_supabase_user('owner3');
select tests.create_supabase_user('lcoach');

update app_ops.quota_limits set max_rows_per_day = 3
 where table_name in ('point_event_revisions', 'story_plan_versions', 'sync_maps', 'lessons');
update app_ops.quota_limits set max_rows_per_day = 2 where table_name = 'projects';

insert into public.projects (id, owner_id, local_project_id, title) values
  ('a4000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), 'Quota match');
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a4000000-0000-4000-8000-000000000001', '{}', sha256('q'::bytea), 'gateway');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a400000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-000000000001', 'rally-pulse', 1, 'Pulse');

create function pg_temp.today() returns date language sql stable as $$ select (now() at time zone 'UTC')::date $$;
grant execute on function pg_temp.today() to authenticated;

-- T-DB-64: each per-project and per-user table refuses past its limit, allows one below it ----------------------------
select tests.authenticate_as('owner');
select results_eq($$
  with r1 as (insert into public.point_event_revisions (project_id, parent_revision, local_session_id, schema_version,
                                                         event_log)
              values ('a4000000-0000-4000-8000-000000000001', null, gen_random_uuid(), '1', '[]') returning revision)
  select revision from r1$$, $$values (1)$$, 'T-DB-64: event revision 1 of 3 allowed');
insert into public.point_event_revisions (project_id, parent_revision, local_session_id, schema_version, event_log)
values ('a4000000-0000-4000-8000-000000000001', 1, gen_random_uuid(), '1', '[]');
select results_eq($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                              schema_version, event_log)
                    values ('a4000000-0000-4000-8000-000000000001', 2, gen_random_uuid(), '1', '[]')
                    returning revision$$,
  $$values (3)$$, 'T-DB-64: the third event revision (the limit) is allowed');
select throws_ok($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                             schema_version, event_log)
                   values ('a4000000-0000-4000-8000-000000000001', 3, gen_random_uuid(), '1', '[]')$$,
  'P0429', 'quota_exceeded', 'T-DB-64: the fourth event revision of the day is P0429');

insert into public.sync_maps (project_id, source_manifest_revision, map) values
  ('a4000000-0000-4000-8000-000000000001', 1, '{}'), ('a4000000-0000-4000-8000-000000000001', 1, '{}'),
  ('a4000000-0000-4000-8000-000000000001', 1, '{}');
select throws_ok($$insert into public.sync_maps (project_id, source_manifest_revision, map)
                   values ('a4000000-0000-4000-8000-000000000001', 1, '{}')$$,
  'P0429', 'quota_exceeded', 'T-DB-64: the fourth sync map of the day is P0429');

insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('9a400000-0000-4000-8000-000000000001', 'user', 'u1', '{}'),
  ('9a400000-0000-4000-8000-000000000001', 'user', 'u1', '{}'),
  ('9a400000-0000-4000-8000-000000000001', 'user', 'u1', '{}');
select throws_ok($$insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version,
                                                           story_plan)
                   values ('9a400000-0000-4000-8000-000000000001', 'user', 'u1', '{}')$$,
  'P0429', 'quota_exceeded', 'T-DB-64: the fourth plan version of the day is P0429');

insert into public.lessons (local_lesson_id, title) values (gen_random_uuid(), 'L1'), (gen_random_uuid(), 'L2'),
  (gen_random_uuid(), 'L3');
select throws_ok($$insert into public.lessons (local_lesson_id, title) values (gen_random_uuid(), 'L4')$$,
  'P0429', 'quota_exceeded', 'T-DB-64: the fourth lesson of the day is P0429 (a per-user limit)');
reset role;

select results_eq($$select n from app_ops.quota_counters
                     where table_name = 'point_event_revisions' and subject_id = 'a4000000-0000-4000-8000-000000000001'
                     order by day$$,
  $$values (3), (3)$$, 'T-DB-70: the day row and the lifetime row both hold 3: the refused insert rolled back');
select results_eq($$select n from app_ops.quota_counters
                     where table_name = 'lessons' and subject_id = tests.get_supabase_uid('owner') order by day$$,
  $$values (3), (3)$$, 'lessons are counted against the user');
select results_eq($$select n from app_ops.quota_counters
                     where table_name = '*user_total' and subject_id = tests.get_supabase_uid('owner') order by day$$,
  $$values (12), (12)$$, 'the per-user aggregate counted all 12 accepted rows and none of the 4 refused');
select is((select count(*)::int from app_ops.quota_counters where day = 'infinity'
            and subject_id in ('a4000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'))), 5,
  'one lifetime row per (table, subject): events, sync maps, versions, lessons and the aggregate');

-- T-DB-64: the per-user aggregate stops N projects x the per-project limit -------------------------------------------
update app_ops.quota_limits set max_rows_per_day = 7 where table_name = '*user_total';
insert into public.projects (id, owner_id, local_project_id, title)
select ('a4100000-0000-4000-8000-00000000000' || i)::uuid, tests.get_supabase_uid('owner2'), gen_random_uuid(),
       'Match ' || i
  from generate_series(1, 5) i;

create function pg_temp.append_two(p_project uuid) returns text language plpgsql as $$
declare
  v_state text;
begin
  insert into public.point_event_revisions (project_id, parent_revision, local_session_id, schema_version, event_log)
  values (p_project, null, gen_random_uuid(), '1', '[]');
  insert into public.point_event_revisions (project_id, parent_revision, local_session_id, schema_version, event_log)
  values (p_project, 1, gen_random_uuid(), '1', '[]');
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate;
  return v_state;
end $$;
grant execute on function pg_temp.append_two(uuid) to authenticated;
select tests.authenticate_as('owner2');
select is(pg_temp.append_two('a4100000-0000-4000-8000-000000000001'), 'ok', 'T-DB-64: project 1: 2 rows (total 2)');
select is(pg_temp.append_two('a4100000-0000-4000-8000-000000000002'), 'ok', 'T-DB-64: project 2: 2 rows (total 4)');
select is(pg_temp.append_two('a4100000-0000-4000-8000-000000000003'), 'ok', 'T-DB-64: project 3: 2 rows (total 6)');
select results_eq($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                              schema_version, event_log)
                    values ('a4100000-0000-4000-8000-000000000004', null, gen_random_uuid(), '1', '[]')
                    returning revision$$,
  $$values (1)$$, 'T-DB-64: project 4, first row: the seventh of the day is allowed (one below the aggregate)');
select throws_ok($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                             schema_version, event_log)
                   values ('a4100000-0000-4000-8000-000000000004', 1, gen_random_uuid(), '1', '[]')$$,
  'P0429', 'quota_exceeded',
  'T-DB-64: project 4, second row: refused at the *user_total limit though the project is under its own');
select is(pg_temp.append_two('a4100000-0000-4000-8000-000000000005'), 'P0429',
  'T-DB-64: a fresh project 5 is refused too: the aggregate is per user, never N x the per-project limit');
reset role;
select results_eq($$select count(*)::int, max(n) from app_ops.quota_counters
                     where table_name = '*user_total' and subject_id = tests.get_supabase_uid('owner2')
                       and day = pg_temp.today()$$,
  $$values (1, 7)$$, 'T-DB-64: one aggregate row for the user and day, holding 7');
select is((select count(*)::int from public.point_event_revisions p join public.projects j on j.id = p.project_id
            where j.owner_id = tests.get_supabase_uid('owner2')), 7, 'exactly 7 revisions landed across 5 projects');

-- T-DB-64: a lesson-only observation counts against the writing user (no NULL subject, no 23502) ----------------------
update app_ops.quota_limits set max_rows_per_day = 2000 where table_name = '*user_total';
insert into public.lessons (id, owner_id, local_lesson_id, title) values
  ('1e400000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), 'Lesson');
insert into public.access_grants (kind, lesson_id, grantee_user_id, invitee_email_hmac, created_by, redeem_by,
                                  redeemed_at)
values ('lesson_coach', '1e400000-0000-4000-8000-000000000001', tests.get_supabase_uid('lcoach'),
        sha256('lc'::bytea), tests.get_supabase_uid('owner'), now() + interval '1 day', now());
select tests.authenticate_as('lcoach');
select results_eq($$insert into public.observations (lesson_id, kind, body)
                    values ('1e400000-0000-4000-8000-000000000001', 'note', 'Coach note') returning project_id$$,
  $$values (null::uuid)$$, 'T-DB-64: a lesson coach''s lesson-only observation (project_id null) is allowed');
reset role;
select results_eq($$select n from app_ops.quota_counters
                     where table_name = 'observations' and subject_id = tests.get_supabase_uid('lcoach')
                       and day = pg_temp.today()$$,
  $$values (1)$$, 'T-DB-64: and counted against the coach''s user subject');

-- projects are quota'd per user too (the item migration 1 left for this ticket) ---------------------------------------
select tests.authenticate_as('owner3');
insert into public.projects (local_project_id, title) values (gen_random_uuid(), 'P1'), (gen_random_uuid(), 'P2');
select throws_ok($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), 'P3')$$,
  'P0429', 'quota_exceeded', 'the third project of the day is P0429');
reset role;

-- T-DB-70: a table without a limits row refuses; nothing is counted -----------------------------------------------
delete from app_ops.quota_limits where table_name = 'story_plans';
select tests.authenticate_as('owner');
select throws_ok($$insert into public.story_plans (project_id, profile_id, profile_revision, title)
                   values ('a4000000-0000-4000-8000-000000000001', 'coach-cut', 1, 'No limit row')$$,
  'P0429', 'quota_exceeded', 'T-DB-70: with no quota_limits row for story_plans the insert is P0429 (fail closed)');
reset role;
select is((select count(*)::int from app_ops.quota_counters where table_name = 'story_plans'), 0,
  'T-DB-70: no counter row was left behind');
select results_eq($$select n from app_ops.quota_counters
                     where table_name = '*user_total' and subject_id = tests.get_supabase_uid('owner') order by day$$,
  $$values (12), (12)$$, 'T-DB-70: the refused insert left the aggregate unchanged');
delete from app_ops.quota_limits where table_name = '*user_total';
select tests.authenticate_as('owner');
select throws_ok($$insert into public.observations (project_id, kind, body)
                   values ('a4000000-0000-4000-8000-000000000001', 'note', 'x')$$,
  'P0429', 'quota_exceeded', 'T-DB-70: with no *user_total row a table under its own limit is P0429 too');
reset role;

select * from finish();
rollback;
