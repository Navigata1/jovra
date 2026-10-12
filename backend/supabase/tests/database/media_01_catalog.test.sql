-- Migration 2 catalog checks (S77 / B-04 with the B-23/B-25 items that land in these tables): the tables exist, the
-- composite foreign keys that make cross-project references impossible (findings 17 and 31), ON DELETE SET NULL
-- (source_id) where a source deletion would otherwise stall (finding 22a), append-only grants (T-DB-14), hidden
-- columns (T-DB-17), unauthenticated denial (T-DB-01 for the new tables) and the clip-share commands' role.
-- docs/backend/architecture.md §4.1, §4.3; security-model.md §5.3-§5.6, §13.5, §13.8, §13.9, §13.16.
-- identity_01 holds every table, function and trigger in public/app_* to the T-DB-02/03/05/66/67 lints, so the new
-- objects are linted there too. The file rolls back.
begin;
select plan(42);

-- Tables -----------------------------------------------------------------------------------------------------------
select has_table('public', 'camera_sources', 'camera_sources exists');
select has_table('public', 'source_manifests', 'source_manifests exists');
select has_table('public', 'sync_maps', 'sync_maps exists');
select has_table('public', 'calibration_versions', 'calibration_versions exists');
select has_table('public', 'point_event_revisions', 'point_event_revisions exists');
select has_table('public', 'observations', 'observations exists');
select has_table('public', 'lessons', 'lessons exists');
select has_table('public', 'lesson_clips', 'lesson_clips exists');
select has_table('public', 'story_plans', 'story_plans exists');
select has_table('public', 'story_plan_versions', 'story_plan_versions exists');
select has_table('public', 'artifacts', 'artifacts exists (lesson_clips.excerpt_artifact_id and stale marking need it)');
select has_table('public', 'access_grants', 'access_grants exists (lesson_access and clip sharing need it)');
select has_table('app_ops', 'quota_limits', 'app_ops.quota_limits exists');
select has_table('app_ops', 'quota_counters', 'app_ops.quota_counters exists');

-- Composite foreign keys (finding 31: sources; finding 17: plans and versions) -------------------------------------
-- One row per (table, local columns, referenced table, referenced columns, delete action, SET NULL column list).
create function pg_temp.fk(p_table text, p_cols text[]) returns text language sql stable as $$
  select c.confrelid::regclass::text || '(' ||
         (select string_agg(a.attname, ',' order by k.ord) from unnest(c.confkey) with ordinality k(n, ord)
            join pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.n) || ') on delete ' ||
         c.confdeltype::text ||
         coalesce(' set null (' || (select string_agg(a.attname, ',') from unnest(c.confdelsetcols) n
                                       join pg_attribute a on a.attrelid = c.conrelid and a.attnum = n) || ')', '')
    from pg_constraint c
   where c.contype = 'f' and c.conrelid = ('public.' || p_table)::regclass
     and (select array_agg(a.attname::text order by k.ord) from unnest(c.conkey) with ordinality k(n, ord)
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.n) = p_cols
$$;

select is(pg_temp.fk('lesson_clips', '{project_id,source_id}'),
  'camera_sources(project_id,id) on delete n set null (source_id)',
  'finding 31/22a: lesson_clips (project_id, source_id) -> camera_sources(project_id, id), SET NULL (source_id) only');
select is(pg_temp.fk('observations', '{project_id,source_id}'),
  'camera_sources(project_id,id) on delete n set null (source_id)',
  'finding 31/22a: observations (project_id, source_id) -> camera_sources(project_id, id), SET NULL (source_id) only');
select is(pg_temp.fk('calibration_versions', '{project_id,source_id}'),
  'camera_sources(project_id,id) on delete c',
  'finding 31: calibration_versions (project_id, source_id) -> camera_sources(project_id, id), cascade');
select is(pg_temp.fk('artifacts', '{project_id,source_id}'), 'camera_sources(project_id,id) on delete c',
  'finding 31: artifacts (project_id, source_id) -> camera_sources(project_id, id)');
select is(pg_temp.fk('artifacts', '{project_id,parent_artifact_id}'), 'artifacts(project_id,id) on delete c',
  'finding 31: artifacts (project_id, parent_artifact_id) -> artifacts(project_id, id)');
select is(pg_temp.fk('access_grants', '{project_id,artifact_id}'), 'artifacts(project_id,id) on delete c',
  'finding 31: access_grants (project_id, artifact_id) -> artifacts(project_id, id)');
select is(pg_temp.fk('story_plan_versions', '{project_id,story_plan_id}'), 'story_plans(project_id,id) on delete c',
  'finding 17: story_plan_versions (project_id, story_plan_id) -> story_plans(project_id, id)');
select is(pg_temp.fk('sync_maps', '{project_id,source_manifest_revision}'),
  'source_manifests(project_id,revision) on delete c',
  'sync_maps name a manifest revision of their own project');
select is(pg_temp.fk('observations', '{calibration_version_id}'), 'calibration_versions(id) on delete n',
  'finding 22a: deleting a source (and its calibrations) never stalls on an observation that used the calibration');
select ok(exists (select 1 from pg_constraint c where c.conrelid = 'public.story_plan_versions'::regclass
                   and c.contype = 'u' and pg_get_constraintdef(c.oid) = 'UNIQUE (story_plan_id, id)')
          and exists (select 1 from pg_constraint c where c.conrelid = 'public.story_plan_versions'::regclass
                       and c.contype = 'u' and pg_get_constraintdef(c.oid) = 'UNIQUE (project_id, id)')
          and exists (select 1 from pg_constraint c where c.conrelid = 'public.story_plans'::regclass
                       and c.contype = 'u' and pg_get_constraintdef(c.oid) = 'UNIQUE (project_id, id)'),
  'finding 17: the composite targets render_jobs, quotes and usage_reservations will reference exist');

-- T-DB-14: append-only tables have no UPDATE or DELETE for any client role ------------------------------------------
select is_empty($$
  select t || ' ' || r from unnest(array['point_event_revisions', 'sync_maps', 'calibration_versions',
                                         'source_manifests', 'story_plan_versions']) t
   cross join (values ('authenticated'), ('anon')) v(r)
   where has_any_column_privilege(r, ('public.' || t)::regclass, 'update')
      or has_table_privilege(r, ('public.' || t)::regclass, 'delete')
      or has_table_privilege(r, ('public.' || t)::regclass, 'truncate')
$$, 'T-DB-14: no client role may update, delete or truncate an append-only table');
select is_empty($$
  select t from unnest(array['lessons', 'lesson_clips', 'observations', 'story_plans', 'camera_sources',
                             'artifacts', 'access_grants']) t
   where has_table_privilege('authenticated', ('public.' || t)::regclass, 'delete')
$$, 'no client deletes: lessons, clips and media go through deletion_requests (objects first)');
select is_empty($$
  select t from unnest(array['camera_sources', 'source_manifests', 'artifacts', 'access_grants']) t
   where has_any_column_privilege('authenticated', ('public.' || t)::regclass, 'insert')
$$, 'camera_sources, source_manifests, artifacts and access_grants are written only through app_gateway');

-- T-DB-17: secret and internal columns are never selectable ---------------------------------------------------------
select is_empty($$
  select t || '.' || c from (values ('camera_sources', 'r2_key'), ('camera_sources', 'verified_etag'),
                                    ('camera_sources', 'current_session_id'), ('camera_sources', 'client_probe'),
                                    ('artifacts', 'r2_key'), ('artifacts', 'bucket_class'),
                                    ('access_grants', 'token_hash'), ('access_grants', 'invitee_email_hmac'),
                                    ('camera_invites', 'code_hash')) v(t, c)
   where has_column_privilege('authenticated', ('public.' || t)::regclass, c, 'select')
$$, 'T-DB-17: r2 keys, etags, sessions, client probes, token hashes and invitee HMACs are not granted');
select ok(not has_column_privilege('authenticated', 'public.story_plan_versions', 'validation_state', 'insert')
          and not has_column_privilege('authenticated', 'public.story_plan_versions', 'planner_model_id', 'insert')
          and not has_column_privilege('authenticated', 'public.story_plan_versions', 'edl_sha256', 'insert')
          and not has_column_privilege('authenticated', 'public.story_plan_versions', 'project_id', 'insert'),
  'T-DB-24: validation_state, planner_model_id, edl_sha256 and project_id are server-set on plan versions');
select ok(not has_column_privilege('authenticated', 'public.observations', 'provenance', 'insert')
          and not has_column_privilege('authenticated', 'public.observations', 'provenance', 'update'),
  'T-DB-23: observations.provenance is never written by a client');
select ok(not has_column_privilege('authenticated', 'public.lesson_clips', 'share_approved_at', 'update')
          and not has_column_privilege('authenticated', 'public.lesson_clips', 'share_approved_sha256', 'update')
          and not has_column_privilege('authenticated', 'public.lesson_clips', 'excerpt_artifact_id', 'update')
          and not has_column_privilege('authenticated', 'public.lesson_clips', 'project_id', 'update')
          and not has_column_privilege('authenticated', 'public.lesson_clips', 'source_id', 'update'),
  'finding 20: share approval, the excerpt link and the clip''s project and source are not client-writable');

-- Quotas: every client-insertable table has a20_enforce_quota and a limits row (finding 23) ---------------------------
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and has_any_column_privilege('authenticated', c.oid, 'insert')
     and not exists (select 1 from pg_trigger g join pg_proc f on f.oid = g.tgfoid
                      where g.tgrelid = c.oid and g.tgname = 'a20_enforce_quota'
                        and f.oid = 'app_private.enforce_quota()'::regprocedure
                        and g.tgtype & 1 = 1 and g.tgtype & 2 = 2 and g.tgtype & 4 = 4)
$$, 'finding 23: every client-insertable table has the BEFORE INSERT a20_enforce_quota trigger');
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and has_any_column_privilege('authenticated', c.oid, 'insert')
     and not exists (select 1 from app_ops.quota_limits q where q.table_name = c.relname)
$$, 'finding 23: every client-insertable table has an app_ops.quota_limits row');
select is((select subject from app_ops.quota_limits where table_name = '*user_total'), 'user',
  'finding 23: the per-user aggregate limit row exists');
select ok(not has_table_privilege('authenticated', 'app_ops.quota_counters', 'select')
          and not has_table_privilege('authenticated', 'app_ops.quota_limits', 'select'),
  'quota tables are server-only');

-- Clip-share commands: gateway only (finding 20) ---------------------------------------------------------------------
select ok(has_function_privilege('jovra_gateway', 'app_gateway.approve_clip_share(uuid, uuid, uuid)', 'execute')
          and has_function_privilege('jovra_gateway', 'app_gateway.revoke_clip_share(uuid, uuid, uuid)', 'execute'),
  'finding 20: jovra_gateway may call approve_clip_share and revoke_clip_share');
select ok(not has_function_privilege('jovra_orchestrator', 'app_gateway.approve_clip_share(uuid, uuid, uuid)', 'execute')
          and not has_function_privilege('jovra_orchestrator', 'app_gateway.revoke_clip_share(uuid, uuid, uuid)',
                                         'execute')
          and not has_function_privilege('authenticated', 'app_gateway.revoke_clip_share(uuid, uuid, uuid)',
                                         'execute'),
  'finding 20: neither the orchestrator nor a client may call the clip-share commands');
select ok('lesson_clip' = any (enum_range(null::public.deletion_scope)::text[]),
  'finding 20: deletion_scope has lesson_clip');

-- T-DB-01 for the new tables: unauthenticated requests fail before RLS ------------------------------------------------
select tests.clear_authentication();
select throws_ok('select count(*) from public.camera_sources', '42501', 'permission denied for table camera_sources',
  'T-DB-01: unauthenticated select on camera_sources is denied');
select throws_ok('select count(*) from public.point_event_revisions', '42501',
  'permission denied for table point_event_revisions', 'T-DB-01: unauthenticated select on point_event_revisions');
select throws_ok('select count(*) from public.lessons', '42501', 'permission denied for table lessons',
  'T-DB-01: unauthenticated select on lessons is denied');
select throws_ok($$insert into public.lessons (local_lesson_id, title) values (gen_random_uuid(), 'x')$$, '42501',
  'permission denied for table lessons', 'T-DB-01: unauthenticated insert into lessons is denied');
reset role;

select * from finish();
rollback;
