-- Migration 3 catalog checks (S78 / B-05): the money, job, provider, deletion and app_ops tables exist; composite
-- foreign keys bind plans, versions, quotes, reservations, jobs, attempts, excerpts and artifact sources to their own
-- project (findings 17, 31; T-DB-59 catalog half); one hold and one live job per key with NULLS NOT DISTINCT
-- (finding 18); hidden columns (T-DB-17, finding 32); no client writes to money, jobs, artifacts, grants or deletion
-- requests (T-DB-26 catalog half); no token or secret column on provider_connections (T-DB-29); server-only app_ops
-- with the secret guard on every text/JSON table (T-DB-47) and fail-closed spend limits (§13.7).
-- docs/backend/architecture.md §4.3; security-model.md §5.6, §5.7, §6, §13.5-§13.7, §13.15-§13.17.
-- identity_01 and media_01 hold every table, function and trigger to the T-DB-02/03/05/66/67 lints, the quota lint,
-- the FK-covering-index lint and the permissive-policy lint, so the new objects are linted there too. Rolls back.
begin;
select plan(76);

-- Tables -----------------------------------------------------------------------------------------------------------
select has_table('public', 'quotes', 'quotes exists');
select has_table('public', 'usage_reservations', 'usage_reservations exists');
select has_table('public', 'render_jobs', 'render_jobs exists');
select has_table('public', 'render_attempts', 'render_attempts exists');
select has_table('public', 'artifact_sources', 'artifact_sources exists');
select has_table('public', 'provider_connections', 'provider_connections exists');
select has_table('public', 'deletion_requests', 'deletion_requests exists');
select has_table('app_ops', 'upload_sessions', 'app_ops.upload_sessions exists');
select has_table('app_ops', 'upload_parts', 'app_ops.upload_parts exists');
select has_table('app_ops', 'job_outbox', 'app_ops.job_outbox exists');
select has_table('app_ops', 'idempotency_records', 'app_ops.idempotency_records exists');
select has_table('app_ops', 'spend_limits', 'app_ops.spend_limits exists');
select has_table('app_ops', 'spend_commitments', 'app_ops.spend_commitments exists');
select has_table('app_ops', 'audit_events', 'app_ops.audit_events exists');
select has_column('public', 'quotes', 'consent', 'quotes.consent holds the jovra.quote/1 consent object');
select has_column('public', 'quotes', 'planner_choice', 'quotes.planner_choice exists');
select has_column('public', 'usage_reservations', 'initial_quote_id', 'usage_reservations.initial_quote_id exists');
select has_column('public', 'render_attempts', 'planner_budget', 'render_attempts.planner_budget exists');
select has_column('public', 'render_attempts', 'output_plan', 'render_attempts.output_plan (byte caps) exists');

-- Composite foreign keys -----------------------------------------------------------------------------------------
-- One row per (table, local columns): referenced table and columns, delete action, SET NULL column list.
create function pg_temp.fk(p_table regclass, p_cols text[]) returns text language sql stable as $$
  select c.confrelid::regclass::text || '(' ||
         (select string_agg(a.attname, ',' order by k.ord) from unnest(c.confkey) with ordinality k(n, ord)
            join pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.n) || ') on delete ' ||
         c.confdeltype::text ||
         coalesce(' set null (' || (select string_agg(a.attname, ',') from unnest(c.confdelsetcols) n
                                       join pg_attribute a on a.attrelid = c.conrelid and a.attnum = n) || ')', '')
    from pg_constraint c
   where c.contype = 'f' and c.conrelid = p_table
     and (select array_agg(a.attname::text order by k.ord) from unnest(c.conkey) with ordinality k(n, ord)
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.n) = p_cols
$$;

select is(pg_temp.fk('public.quotes', '{project_id,story_plan_id}'), 'story_plans(project_id,id) on delete a',
  'T-DB-59: quotes (project_id, story_plan_id) -> story_plans(project_id, id)');
select is(pg_temp.fk('public.quotes', '{story_plan_id,story_plan_version_id}'),
  'story_plan_versions(story_plan_id,id) on delete a',
  'T-DB-59: quotes (story_plan_id, story_plan_version_id) -> story_plan_versions(story_plan_id, id)');
select is(pg_temp.fk('public.usage_reservations', '{project_id,story_plan_id}'),
  'story_plans(project_id,id) on delete a', 'T-DB-59: usage_reservations (project_id, story_plan_id) -> story_plans');
select is(pg_temp.fk('public.usage_reservations', '{story_plan_id,story_plan_version_id}'),
  'story_plan_versions(story_plan_id,id) on delete a',
  'T-DB-59: usage_reservations (story_plan_id, story_plan_version_id) -> story_plan_versions');
select is(pg_temp.fk('public.render_jobs', '{project_id,story_plan_id}'), 'story_plans(project_id,id) on delete a',
  'T-DB-59: render_jobs (project_id, story_plan_id) -> story_plans(project_id, id)');
select is(pg_temp.fk('public.render_jobs', '{story_plan_id,story_plan_version_id}'),
  'story_plan_versions(story_plan_id,id) on delete a',
  'T-DB-59: render_jobs (story_plan_id, story_plan_version_id) -> story_plan_versions(story_plan_id, id)');
select is(pg_temp.fk('public.usage_reservations', '{project_id,quote_id}'), 'quotes(project_id,id) on delete a',
  'a hold is funded by a quote of its own project');
select is(pg_temp.fk('public.render_jobs', '{project_id,reservation_id}'),
  'usage_reservations(project_id,id) on delete a', 'a job is bounded by a hold of its own project');
select is(pg_temp.fk('public.render_jobs', '{project_id,quote_id}'), 'quotes(project_id,id) on delete a',
  'a job is accepted from a quote of its own project');
select is(pg_temp.fk('public.usage_reservations', '{project_id,job_id}'),
  'render_jobs(project_id,id) on delete n set null (job_id)', 'a hold names a job of its own project');
select is(pg_temp.fk('public.artifacts', '{project_id,job_id}'),
  'render_jobs(project_id,id) on delete n set null (job_id)',
  'finding 31: artifacts (project_id, job_id) -> render_jobs(project_id, id), SET NULL (job_id)');
select is(pg_temp.fk('public.artifacts', '{job_id,attempt_id}'),
  'render_attempts(job_id,id) on delete n set null (attempt_id)',
  'finding 31: artifacts (job_id, attempt_id) -> render_attempts(job_id, id), SET NULL (attempt_id)');
select is(pg_temp.fk('public.artifacts', '{project_id,lesson_clip_id}'), 'lesson_clips(project_id,id) on delete c',
  'finding 31 (excerpt): artifacts (project_id, lesson_clip_id) -> lesson_clips(project_id, id)');
select is(pg_temp.fk('public.lesson_clips', '{project_id,excerpt_artifact_id}'),
  'artifacts(project_id,id) on delete n set null (excerpt_artifact_id)',
  'finding 31 (excerpt): lesson_clips (project_id, excerpt_artifact_id) -> artifacts(project_id, id)');
select ok(pg_temp.fk('public.artifacts', '{lesson_clip_id}') is null
          and pg_temp.fk('public.lesson_clips', '{excerpt_artifact_id}') is null,
  'finding 31 (excerpt): the single-column excerpt FKs of migration 2 are gone');
select is(pg_temp.fk('public.artifact_sources', '{project_id,artifact_id}'), 'artifacts(project_id,id) on delete c',
  'artifact_sources name an artifact of their own project');
select is(pg_temp.fk('public.artifact_sources', '{project_id,source_id}'),
  'camera_sources(project_id,id) on delete c', 'artifact_sources name a source of their own project (§13.9 (a))');
select is(pg_temp.fk('app_ops.upload_sessions', '{project_id,source_id}'),
  'camera_sources(project_id,id) on delete c', 'an upload session targets a source of its own project');

-- One hold and one live job per (project, plan, version, output), NULLS NOT DISTINCT (finding 18, §13.6) ------------
create function pg_temp.idx(p_index regclass) returns text language sql stable as $$
  select (select string_agg(a.attname, ',' order by k.ord) from unnest(i.indkey::int2[]) with ordinality k(n, ord)
            join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.n)
         || case when i.indisunique then ' unique' else '' end
         || case when i.indnullsnotdistinct then ' nulls not distinct' else '' end
         || coalesce(' where ' || pg_get_expr(i.indpred, i.indrelid), '')
    from pg_index i where i.indexrelid = p_index
$$;
select is(pg_temp.idx('public.usage_reservations_one_hold'),
  'project_id,story_plan_id,story_plan_version_id,output_spec_sha256 unique nulls not distinct where (state = ''held''::text)',
  'finding 18: one held reservation per (project, plan, version, output), NULLS NOT DISTINCT');
select matches(pg_temp.idx('public.render_jobs_one_live'),
  '^project_id,story_plan_id,story_plan_version_id,output_spec_sha256 unique nulls not distinct where .*ready.*canceled.*failed_terminal.*quote_expired.*deleted',
  'finding 18: one non-terminal job per (project, plan, version, output), NULLS NOT DISTINCT');
select ok(exists (select 1 from pg_constraint c where c.conrelid = 'public.usage_reservations'::regclass
                   and c.contype = 'u' and pg_get_constraintdef(c.oid) = 'UNIQUE (quote_id)')
          and exists (select 1 from pg_constraint c where c.conrelid = 'public.render_jobs'::regclass
                       and c.contype = 'u' and pg_get_constraintdef(c.oid) = 'UNIQUE (reservation_id)'),
  'an accepted quote funds exactly one hold, and a hold bounds exactly one job');

-- T-DB-17 / finding 32: internal cost, leases, refs and measurements are never selectable ---------------------------
select is_empty($$
  select t || '.' || c from (values
    ('quotes', 'cap_cost_micro_usd'), ('quotes', 'estimate_high_cost_micro_usd'), ('quotes', 'owner_id'),
    ('quotes', 'output_spec_sha256'),
    ('usage_reservations', 'cap_cost_micro_usd'), ('usage_reservations', 'reserved_cost_micro_usd'),
    ('usage_reservations', 'consumed_cost_micro_usd'), ('usage_reservations', 'released_cost_micro_usd'),
    ('usage_reservations', 'output_spec_sha256'), ('usage_reservations', 'owner_id'),
    ('render_jobs', 'requested_by'), ('render_jobs', 'idempotency_key'), ('render_jobs', 'quote_id'),
    ('render_jobs', 'reservation_id'), ('render_jobs', 'output_spec_sha256'),
    ('render_attempts', 'lease_token_hash'), ('render_attempts', 'measurements'), ('render_attempts', 'input_refs'),
    ('render_attempts', 'output_plan'), ('render_attempts', 'output_refs'), ('render_attempts', 'input_hash'),
    ('render_attempts', 'reserved_cost_micro_usd'), ('render_attempts', 'actual_cost_micro_usd'),
    ('render_attempts', 'planner_budget'), ('render_attempts', 'claimed_by_host'), ('render_attempts', 'leased_until'),
    ('deletion_requests', 'requested_by')) v(t, c)
   where has_column_privilege('authenticated', ('public.' || t)::regclass, c, 'select')
$$, 'T-DB-17 / finding 32: cost, lease, ref, measurement and requester columns are not granted to clients');
select ok(has_column_privilege('authenticated', 'public.quotes', 'cap_credits', 'select')
          and has_column_privilege('authenticated', 'public.usage_reservations', 'cap_credits', 'select')
          and has_column_privilege('authenticated', 'public.render_attempts', 'state', 'select'),
  'credits and attempt states stay readable (the hidden-column check is not vacuous)');

-- T-DB-26 (catalog): no client role writes money, jobs, attempts, artifacts, grants or deletion requests -------------
select is_empty($$
  select t || ' ' || r from unnest(array['quotes', 'usage_reservations', 'render_jobs', 'render_attempts',
                                         'artifacts', 'artifact_sources', 'access_grants', 'deletion_requests']) t
   cross join (values ('authenticated'), ('anon')) v(r)
   where has_any_column_privilege(r, ('public.' || t)::regclass, 'insert')
      or has_any_column_privilege(r, ('public.' || t)::regclass, 'update')
      or has_table_privilege(r, ('public.' || t)::regclass, 'delete')
      or has_table_privilege(r, ('public.' || t)::regclass, 'truncate')
$$, 'T-DB-26: no client role may insert, update, delete or truncate money, jobs, artifacts, grants or deletions');
select ok(not has_any_column_privilege('authenticated', 'public.artifact_sources', 'select'),
  'artifact_sources is not readable by clients at all');

-- T-DB-29: provider_connections are status rows; no token, secret, URL or endpoint column ------------------------
select hasnt_column('public', 'provider_connections', 'token', 'T-DB-29: no token column');
select hasnt_column('public', 'provider_connections', 'access_token', 'T-DB-29: no access_token column');
select hasnt_column('public', 'provider_connections', 'refresh_token', 'T-DB-29: no refresh_token column');
select hasnt_column('public', 'provider_connections', 'id_token', 'T-DB-29: no id_token column');
select hasnt_column('public', 'provider_connections', 'token_hash', 'T-DB-29: no token_hash column');
select hasnt_column('public', 'provider_connections', 'secret', 'T-DB-29: no secret column');
select hasnt_column('public', 'provider_connections', 'client_secret', 'T-DB-29: no client_secret column');
select hasnt_column('public', 'provider_connections', 'api_key', 'T-DB-29: no api_key column');
select hasnt_column('public', 'provider_connections', 'url', '§13.17: no url column');
select hasnt_column('public', 'provider_connections', 'endpoint', '§13.17: no endpoint column');
select is_empty($$
  select a.attname::text from pg_attribute a
   where a.attrelid = 'public.provider_connections'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname ~* '(token|secret|password|passwd|key|credential|url|uri|endpoint|callback|webhook|email)'
$$, 'T-DB-29: no provider_connections column is named like a token, secret, key, credential, URL or email');
select ok('youtube' <> all (enum_range(null::public.provider_kind)::text[]),
  'provider_kind has no youtube value (its own ADR first)');

-- app_ops: server-only, secret-guarded (T-DB-47), fail-closed spend limits (§13.7) ---------------------------------
select is_empty($$
  select c.oid::regclass::text || ' ' || r from pg_class c
   cross join (values ('anon'), ('authenticated'), ('service_role')) v(r)
   where c.relnamespace = 'app_ops'::regnamespace and c.relkind = 'r'
     and (has_any_column_privilege(r, c.oid, 'select') or has_any_column_privilege(r, c.oid, 'insert')
          or has_any_column_privilege(r, c.oid, 'update') or has_table_privilege(r, c.oid, 'delete'))
$$, 'no client role and not service_role holds any privilege on an app_ops table');
select tests.rls_enabled('app_ops');
select ok((select count(*) from pg_class c where c.relnamespace = 'app_ops'::regnamespace and c.relkind = 'r'
             and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0
                          and a.atttypid in ('text'::regtype, 'jsonb'::regtype))) >= 9,
  'T-DB-47: the app_ops tables with text or JSON columns exist (the lint below is not vacuous)');
select is_empty($$
  select c.oid::regclass::text from pg_class c
   where c.relnamespace = 'app_ops'::regnamespace and c.relkind = 'r'
     and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                  and a.atttypid in ('text'::regtype, 'jsonb'::regtype, 'json'::regtype, 'text[]'::regtype,
                                     'varchar'::regtype))
     and not exists (select 1 from pg_trigger g
                      where g.tgrelid = c.oid and g.tgname = 'a05_refuse_secrets'
                        and g.tgfoid = 'app_private.refuse_secrets()'::regprocedure
                        and g.tgtype & 1 = 1 and g.tgtype & 2 = 2 and g.tgtype & 4 = 4 and g.tgtype & 16 = 16)
$$, 'T-DB-47: every app_ops table with a text or JSON column refuses secrets BEFORE INSERT OR UPDATE');
select ok(app_private.has_secret('{"code": "jvc_' || repeat('A', 43) || '"}')
          and app_private.has_secret('https://x.test/s/jvh_' || repeat('b', 43))
          and app_private.has_secret('Bearer eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig')
          and app_private.has_secret('{"to": "owner.tester@example.test"}'),
  'T-DB-47: the guard recognises invite codes, share links, JWTs and email addresses');
select ok(not app_private.has_secret('{"inviteId": "6a300000-0000-4000-8000-000000000001", "expiresAt": "2026-10-08"}')
          and not app_private.has_secret('staging/p/a/s/b/original/c')
          and not app_private.has_secret('AbCjvl_' || repeat('x', 43)),
  'T-DB-47: ids, R2 keys and a token-like run inside a longer base64url string are not flagged');
select is((select count(*)::int from app_ops.spend_limits where scope = 'owner' and owner_id is null), 1,
  '§13.7: exactly one default owner spend-limit row is seeded');
select is((select count(*)::int from app_ops.spend_limits where scope = 'environment'), 0,
  '§13.7 / finding 19: no environment row is seeded, so spend fails closed until the operator sets it');
select ok(exists (select 1 from pg_indexes where schemaname = 'app_ops' and indexname = 'spend_limits_env')
          and exists (select 1 from pg_indexes where schemaname = 'app_ops' and indexname = 'spend_limits_default')
          and exists (select 1 from pg_indexes where schemaname = 'app_ops' and indexname = 'spend_limits_owner'),
  '§13.7: at most one environment row, one default owner row and one row per owner');
select ok(exists (select 1 from pg_trigger where tgrelid = 'app_ops.spend_commitments'::regclass
                   and tgname = 'b00_append_only')
          and exists (select 1 from pg_trigger where tgrelid = 'app_ops.audit_events'::regclass
                       and tgname = 'b00_append_only'),
  'the spend ledger and the audit log are append-only');
select is((select count(*)::int from app_ops.quota_limits where table_name = 'provider_connections'), 1,
  'finding 23: provider_connections has a quota limits row');

-- Function roles: the new helpers are policy helpers or server-only ---------------------------------------------
select ok(has_function_privilege('authenticated', 'app_private.can_read_job(uuid)', 'execute')
          and has_function_privilege('authenticated', 'app_private.grant_target_live(uuid, uuid)', 'execute')
          and has_function_privilege('authenticated', 'app_private.can_insert_provider_connections(uuid)', 'execute'),
  'policies may call can_read_job, grant_target_live and can_insert_provider_connections');
select is_empty($$
  select p.oid::regprocedure::text || ' ' || r from pg_proc p
   cross join (values ('authenticated'), ('jovra_gateway'), ('jovra_orchestrator')) v(r)
   where p.oid in ('app_private.write_audit(text, uuid, uuid, text, text, uuid, text, text, uuid, jsonb)'::regprocedure,
                   'app_private.retire_excerpt(uuid)'::regprocedure,
                   'app_private.lesson_deletion_artifacts(uuid)'::regprocedure,
                   'app_private.has_secret(text)'::regprocedure)
     and has_function_privilege(r, p.oid, 'execute')
$$, 'audit, excerpt retirement and deletion enumeration run only inside definer commands');

-- T-DB-01 for the new tables: unauthenticated requests fail before RLS ------------------------------------------------
select tests.clear_authentication();
select throws_ok('select count(*) from public.quotes', '42501', 'permission denied for table quotes',
  'T-DB-01: unauthenticated select on quotes is denied');
select throws_ok('select count(*) from public.usage_reservations', '42501',
  'permission denied for table usage_reservations', 'T-DB-01: unauthenticated select on usage_reservations');
select throws_ok('select count(*) from public.render_jobs', '42501', 'permission denied for table render_jobs',
  'T-DB-01: unauthenticated select on render_jobs is denied');
select throws_ok('select count(*) from public.render_attempts', '42501', 'permission denied for table render_attempts',
  'T-DB-01: unauthenticated select on render_attempts is denied');
select throws_ok('select count(*) from public.provider_connections', '42501',
  'permission denied for table provider_connections', 'T-DB-01: unauthenticated select on provider_connections');
select throws_ok($$insert into public.provider_connections (provider) values ('box')$$, '42501',
  'permission denied for table provider_connections', 'T-DB-01: unauthenticated insert into provider_connections');
select throws_ok('select count(*) from public.deletion_requests', '42501',
  'permission denied for table deletion_requests', 'T-DB-01: unauthenticated select on deletion_requests');
reset role;

select * from finish();
rollback;
