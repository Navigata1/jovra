-- Migration 2: sources, manifests, sync maps, calibrations, event revisions and plan versions (S77 / B-04).
-- T-DB-12, 13, 14, 15, 16, 24, 43, 59 (FK half), and the parent_revision variant of T-DB-65 that migration 1 left
-- for this table. docs/backend/security-model.md §5.3, §5.5, §6.2, §13.5, §13.11; architecture.md §4.3, §4.4.
-- Fixtures are written as postgres (the server path); assertions run as the role under test. The file rolls back.
begin;
select plan(45);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('owner_b');
select tests.create_supabase_user('coach');
select tests.create_supabase_user('camera');
select tests.create_supabase_user('unrelated');

-- A: owner's match (coached); B: owner_b's match.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a2000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'),
   'a2100000-0000-4000-8000-000000000001', 'Club final'),
  ('b2000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_b'),
   'b2100000-0000-4000-8000-000000000001', 'Other match');
insert into public.project_members (project_id, user_id, role, granted_by, approved_at) values
  ('a2000000-0000-4000-8000-000000000001', tests.get_supabase_uid('coach'), 'coach',
   tests.get_supabase_uid('owner'), now());

-- The signed-in camera redeemed an approved invite for A's far corner.
insert into public.camera_invites (id, project_id, slot, display_label, code_hash, created_by, redeem_by, redeemed_at,
                                   redeemed_by_user_id, device_key_thumbprint, approved_at, capability_expires_at)
values ('c2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'far_ad_corner',
        'Far corner', sha256('m2-invite'::bytea), tests.get_supabase_uid('owner'), now() + interval '10 minutes',
        now(), tests.get_supabase_uid('camera'), sha256('m2-device'::bytea), now(), now() + interval '1 hour');

-- Sources: the owner's baseline and the camera's corner in A; one in B.
insert into public.camera_sources (id, project_id, slot, local_source_id, invite_id, uploader_user_id, label,
                                   declared_bytes, declared_sha256, r2_key)
values
  ('5a200000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), null, tests.get_supabase_uid('owner'), 'Baseline', 1000, sha256('src-a1'::bytea),
   'staging/p/a2/s/1/original/x'),
  ('5a200000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-000000000001', 'far_ad_corner',
   gen_random_uuid(), 'c2000000-0000-4000-8000-000000000001', tests.get_supabase_uid('camera'), 'Far corner',
   1000, sha256('src-a2'::bytea), null),
  ('5b200000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), null, tests.get_supabase_uid('owner_b'), 'Baseline', 1000, sha256('src-b1'::bytea), null);

-- A server stage writes the first source manifest of A and of B (revision assigned by trigger).
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a2000000-0000-4000-8000-000000000001', '{"sources": []}', sha256('m-a'::bytea), 'gateway'),
  ('b2000000-0000-4000-8000-000000000001', '{"sources": []}', sha256('m-b'::bytea), 'gateway');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a200000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Coach cut'),
  ('9b200000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', 'coach-cut', 1, 'B cut');

select results_eq($$select revision, (select current_source_manifest_revision from public.projects p
                                       where p.id = m.project_id)
                      from public.source_manifests m where m.project_id = 'a2000000-0000-4000-8000-000000000001'$$,
  $$values (1, 1)$$, 'a server-written manifest gets revision 1 and becomes the project''s current manifest');

-- T-DB-12: a coach cannot append to the event log ---------------------------------------------------------------------
select tests.authenticate_as('coach');
select throws_ok($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                             schema_version, event_log)
                   values ('a2000000-0000-4000-8000-000000000001', null, gen_random_uuid(), '1', '[]')$$,
  '42501', 'new row violates row-level security policy for table "point_event_revisions"',
  'T-DB-12: coach inserting an event revision is an RLS violation');
select is((select count(*)::int from public.point_event_revisions), 0, 'T-DB-12: nothing was appended');

-- T-DB-13: the owner appends; a stale parent is P0409 -----------------------------------------------------------------
select tests.authenticate_as('owner');
select results_eq($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                              schema_version, event_log, client_device_id)
                    values ('a2000000-0000-4000-8000-000000000001', null, 'e2000000-0000-4000-8000-000000000001',
                            '1', '[{"type": "pointWon"}]', gen_random_uuid())
                    returning revision, parent_revision, created_by, octet_length(event_log_sha256)$$,
  $$values (1, null::int, tests.get_supabase_uid('owner'), 32)$$,
  'T-DB-13: the first revision is 1, created_by is the caller, the log hash is computed by the server');
select throws_ok($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                             schema_version, event_log)
                   values ('a2000000-0000-4000-8000-000000000001', null, gen_random_uuid(), '1', '[]')$$,
  'P0409', 'revision_conflict', 'T-DB-13: a second device still on parent null gets P0409 revision_conflict');
select throws_ok($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                             schema_version, event_log)
                   values ('a2000000-0000-4000-8000-000000000001', 7, gen_random_uuid(), '1', '[]')$$,
  'P0409', 'revision_conflict', 'T-DB-13: a parent ahead of the current revision is P0409 too');
select throws_ok($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                             schema_version, event_log, created_by)
                   values ('a2000000-0000-4000-8000-000000000001', 1, gen_random_uuid(), '1', '[]',
                           tests.get_supabase_uid('coach'))$$,
  '42501', 'permission denied for table point_event_revisions', 'created_by is not client-writable');
reset role;

-- Derived media bound to revision 1: a film, its thumbnail, a preview, a clip excerpt and a plan version.
insert into public.artifacts (id, project_id, parent_artifact_id, kind, bucket_class, r2_key, state, event_revision)
values
  ('f2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', null, 'film', 'films',
   'films/p/a2/f1', 'ready', 1),
  ('f2000000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-000000000001',
   'f2000000-0000-4000-8000-000000000001', 'thumbnail', 'films', 'films/p/a2/f1.jpg', 'ready', 1),
  ('f2000000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-000000000001', null, 'preview', 'work',
   'work/p/a2/p1', 'ready', 1),
  ('f2000000-0000-4000-8000-000000000004', 'a2000000-0000-4000-8000-000000000001', null, 'clip_excerpt', 'films',
   'films/p/a2/x1', 'ready', 1);
insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version, story_plan,
                                        bound_source_manifest_revision, bound_event_revision)
values ('9a200000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}', 1, 1);

-- T-DB-13 (current parent) and T-DB-15 (stale marking) ----------------------------------------------------------------
select tests.authenticate_as('owner');
select results_eq($$insert into public.point_event_revisions (project_id, parent_revision, local_session_id,
                                                              schema_version, event_log)
                    values ('a2000000-0000-4000-8000-000000000001', 1, 'e2000000-0000-4000-8000-000000000001',
                            '1', '[{"type": "pointWon"}, {"type": "pointWon"}]')
                    returning revision$$,
  $$values (2)$$, 'T-DB-13: with the current parent the insert succeeds as revision + 1');
select is((select current_event_revision from public.projects where id = 'a2000000-0000-4000-8000-000000000001'), 2,
  'T-DB-13: the project''s current_event_revision follows');
select results_eq($$select kind::text, stale from public.artifacts order by kind::text$$,
  $$values ('clip_excerpt', true), ('film', true), ('preview', true), ('thumbnail', false)$$,
  'T-DB-15: the new revision marks the older film, preview and clip excerpt stale (not the thumbnail)');
select results_eq($$select stale from public.story_plan_versions$$, $$values (true)$$,
  'T-DB-15: and the plan version bound to the older revision');

-- T-DB-14: append-only, behaviourally (owner and coach) ---------------------------------------------------------------
select throws_ok($$update public.point_event_revisions set event_log = '[]'$$, '42501',
  'permission denied for table point_event_revisions', 'T-DB-14: owner cannot update an event revision');
select throws_ok($$delete from public.point_event_revisions$$, '42501',
  'permission denied for table point_event_revisions', 'T-DB-14: owner cannot delete an event revision');
select throws_ok($$update public.source_manifests set manifest = '{}'$$, '42501',
  'permission denied for table source_manifests', 'T-DB-14: owner cannot update a source manifest');
select throws_ok($$delete from public.story_plan_versions$$, '42501',
  'permission denied for table story_plan_versions', 'T-DB-14: owner cannot delete a plan version');
select throws_ok($$update public.story_plan_versions set stale = false$$, '42501',
  'permission denied for table story_plan_versions', 'T-DB-14: owner cannot clear stale on a plan version');

-- T-DB-43: sync maps, owner only, reviewer forced to the caller -------------------------------------------------------
select throws_ok($$insert into public.sync_maps (project_id, source_manifest_revision, map, review_state, reviewed_by)
                   values ('a2000000-0000-4000-8000-000000000001', 1, '{}', 'reviewed',
                           tests.get_supabase_uid('coach'))$$,
  '42501', 'permission denied for table sync_maps', 'T-DB-43: reviewed_by cannot be supplied by a client');
select results_eq($$insert into public.sync_maps (project_id, source_manifest_revision, map, review_state, method)
                    values ('a2000000-0000-4000-8000-000000000001', 1, '{"offsets": []}', 'reviewed', 'manual')
                    returning revision, reviewed_by, reviewed_at is not null, created_by$$,
  $$values (1, tests.get_supabase_uid('owner'), true, tests.get_supabase_uid('owner'))$$,
  'T-DB-43: a reviewed sync map records the caller as reviewer and author, revision 1');
select results_eq($$insert into public.sync_maps (project_id, source_manifest_revision, map, review_state)
                    values ('a2000000-0000-4000-8000-000000000001', 1, '{}', 'estimated')
                    returning revision, reviewed_by$$,
  $$values (2, null::uuid)$$, 'an estimated sync map has no reviewer; the next revision is 2');
select throws_ok($$insert into public.sync_maps (project_id, source_manifest_revision, map, review_state)
                   values ('a2000000-0000-4000-8000-000000000001', 1, '{}', 'rejected')$$,
  '42501', 'new row violates row-level security policy for table "sync_maps"',
  'a client cannot insert a sync map in review state rejected');
select throws_ok($$insert into public.sync_maps (project_id, source_manifest_revision, map)
                   values ('a2000000-0000-4000-8000-000000000001', 9, '{}')$$,
  '23503', null, 'a sync map must name an existing manifest revision of its own project');
select throws_ok($$update public.sync_maps set review_state = 'reviewed'$$, '42501',
  'permission denied for table sync_maps', 'T-DB-14: owner cannot update a sync map');

-- Calibrations: owner only, manual/estimated only, versioned per source -----------------------------------------------
select results_eq($$insert into public.calibration_versions (project_id, source_id, calibration, provenance)
                    values ('a2000000-0000-4000-8000-000000000001', '5a200000-0000-4000-8000-000000000001',
                            '{"homography": [1,0,0,0,1,0,0,0,1]}', 'manual')
                    returning version, created_by$$,
  $$values (1, tests.get_supabase_uid('owner'))$$, 'owner adds a manual calibration as version 1');
select results_eq($$insert into public.calibration_versions (project_id, source_id, calibration, provenance)
                    values ('a2000000-0000-4000-8000-000000000001', '5a200000-0000-4000-8000-000000000001',
                            '{}', 'estimated') returning version$$,
  $$values (2)$$, 'the next calibration of the same source is version 2');
select throws_ok($$insert into public.calibration_versions (project_id, source_id, calibration, provenance)
                   values ('a2000000-0000-4000-8000-000000000001', '5a200000-0000-4000-8000-000000000001',
                           '{}', 'validated')$$,
  '42501', 'new row violates row-level security policy for table "calibration_versions"',
  'a client cannot claim a validated calibration');
select throws_ok($$delete from public.calibration_versions$$, '42501',
  'permission denied for table calibration_versions', 'T-DB-14: owner cannot delete a calibration');

-- T-DB-24: plan versions from a client are user/heuristic drafts ------------------------------------------------------
select throws_ok($$insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version,
                                                           story_plan)
                   values ('9a200000-0000-4000-8000-000000000001', 'model', 'm1', '{}')$$,
  '42501', 'new row violates row-level security policy for table "story_plan_versions"',
  'T-DB-24: owner inserting a model-planned version is an RLS violation');
select throws_ok($$insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version,
                                                           story_plan, validation_state)
                   values ('9a200000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}', 'valid')$$,
  '42501', 'permission denied for table story_plan_versions', 'T-DB-24: owner cannot set validation_state');
select results_eq($$insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version,
                                                            story_plan, bound_event_revision)
                    values ('9a200000-0000-4000-8000-000000000001', 'user', 'u1', '{"beats": []}', 2)
                    returning version, project_id, validation_state, stale, created_by$$,
  $$values (2, 'a2000000-0000-4000-8000-000000000001'::uuid, 'unvalidated'::text, false,
            tests.get_supabase_uid('owner'))$$,
  'T-DB-24: a user draft is accepted unvalidated; the trigger sets version 2 and the plan''s project');
select throws_ok($$insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version,
                                                           story_plan)
                   values ('9b200000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}')$$,
  '42501', 'new row violates row-level security policy for table "story_plan_versions"',
  'owner A adding a version to B''s plan is an RLS violation (the guard resolves the plan''s own project)');
select is((select current_version from public.story_plans where id = '9a200000-0000-4000-8000-000000000001'), 2,
  'the plan''s current_version follows its newest version');

select tests.authenticate_as('coach');
select results_eq($$insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version,
                                                            story_plan)
                    values ('9a200000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}') returning version$$,
  $$values (3)$$, 'T-DB-24: a coach may add a heuristic draft');
select throws_ok($$insert into public.story_plan_versions (story_plan_id, planner_kind, planner_adapter_version,
                                                           story_plan)
                   values ('9a200000-0000-4000-8000-000000000001', 'model', 'm1', '{}')$$,
  '42501', 'new row violates row-level security policy for table "story_plan_versions"',
  'T-DB-24: a coach inserting a model-planned version is an RLS violation');
select throws_ok($$update public.point_event_revisions set event_log = '[]'$$, '42501',
  'permission denied for table point_event_revisions', 'T-DB-14: coach cannot update an event revision');
select is((select count(*)::int from public.camera_sources), 2, 'coach sees the project''s two sources');
reset role;

-- T-DB-59 (FK half): even the table owner cannot pair project A with B's plan --------------------------------------
create function pg_temp.as_owner_error(p_sql text) returns text language plpgsql as $$
declare
  v_state text;
begin
  execute 'set local role jovra_owner';
  execute p_sql;
  execute 'reset role';
  return 'no error';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate;
  return v_state;
end $$;
select is(pg_temp.as_owner_error($$insert into public.story_plan_versions (story_plan_id, project_id, planner_kind,
                                                                         planner_adapter_version, story_plan)
                                   values ('9b200000-0000-4000-8000-000000000001',
                                           'a2000000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}')$$),
  '23503', 'T-DB-59 (FK half): as jovra_owner, a version pairing project A with B''s plan is an FK violation');
select is(pg_temp.as_owner_error($$insert into public.story_plan_versions (story_plan_id, project_id, planner_kind,
                                                                         planner_adapter_version, story_plan)
                                   values ('9b200000-0000-4000-8000-000000000001',
                                           'b2000000-0000-4000-8000-000000000001', 'model', 'm1', '{}')$$),
  'no error', 'T-DB-59 (FK half): the same insert with B''s own project passes (the check is the FK, not the role)');
select is(current_user::text, 'postgres', 'the helper restored the session role');

-- T-DB-65 (parent_revision variant): an unrelated user learns nothing about A's event log ------------------------------
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
declare
  v_state text; v_message text; v_detail text;
begin
  execute p_sql;
  return 'no error';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_message = message_text, v_detail = pg_exception_detail;
  return v_state || ' | ' || v_message || ' | ' || coalesce(v_detail, '');
end $$;
grant execute on function pg_temp.error_of(text) to authenticated;
select tests.authenticate_as('unrelated');
select is_empty($$
  select p::text from unnest(array[null, 0, 1, 2, 3]) p
   where pg_temp.error_of(format($q$insert into public.point_event_revisions (project_id, parent_revision,
                                     local_session_id, schema_version, event_log)
                                   values ('a2000000-0000-4000-8000-000000000001', %s, gen_random_uuid(), '1', '[]')$q$,
                                 coalesce(p::text, 'null')))
         <> '42501 | new row violates row-level security policy for table "point_event_revisions" | '
$$, 'T-DB-65: every parent_revision value gets the identical 42501 (the current one, 2, included)');
select is((select count(*)::int from public.point_event_revisions) + (select count(*)::int from public.sync_maps)
          + (select count(*)::int from public.camera_sources) + (select count(*)::int from public.source_manifests)
          + (select count(*)::int from public.story_plan_versions)
          + (select count(*)::int from public.calibration_versions), 0,
  'T-DB-06: an unrelated user sees 0 rows of A''s events, sync maps, sources, manifests, versions, calibrations');
reset role;
select is((select current_event_revision from public.projects where id = 'a2000000-0000-4000-8000-000000000001'), 2,
  'T-DB-65: A''s current_event_revision is untouched');

-- T-DB-16: the signed-in camera sees its own source and nothing else --------------------------------------------------
select tests.authenticate_as('camera');
select results_eq($$select id::text, label from public.camera_sources$$,
  $$values ('5a200000-0000-4000-8000-000000000002', 'Far corner')$$,
  'T-DB-16: the camera sees only its own source');
select is((select count(*)::int from public.projects) + (select count(*)::int from public.source_manifests)
          + (select count(*)::int from public.artifacts) + (select count(*)::int from public.point_event_revisions),
  0, 'T-DB-16: and 0 rows of projects, manifests, artifacts and events');
select throws_ok('select r2_key from public.camera_sources', '42501', 'permission denied for table camera_sources',
  'T-DB-17: camera_sources.r2_key is not selectable');
reset role;
update public.camera_invites set revoked_at = now() where id = 'c2000000-0000-4000-8000-000000000001';
select tests.authenticate_as('camera');
select is((select count(*)::int from public.camera_sources), 0, 'T-DB-16: after the invite is revoked, 0 rows at once');
reset role;

select * from finish();
rollback;
