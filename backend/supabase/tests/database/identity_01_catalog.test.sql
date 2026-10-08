-- Migration 1 catalog checks (S76 / B-03, with the B-23/B-25 items that land in these tables): schemas, roles,
-- grants, ownership and the trigger-order lint. docs/backend/security-model.md §3, §4, §5.1, §6.2 and §13.0/§13.11.
-- Every query is data-driven over the catalog, so objects added by later migrations are held to the same rules.
begin;
select plan(32);

-- Schemas and roles ------------------------------------------------------------------------------------------------
select has_schema('app_private', 'schema app_private exists');
select has_schema('app_gateway', 'schema app_gateway exists');
select has_schema('app_ops', 'schema app_ops exists');

select ok((select not rolcanlogin and not rolinherit and not rolbypassrls and not rolsuper
             from pg_roles where rolname = 'jovra_owner'),
  'jovra_owner exists and cannot log in, inherit, bypass RLS or act as superuser');
select ok((select rolcanlogin and not rolinherit and not rolbypassrls and not rolsuper and rolconnlimit = 20
             from pg_roles where rolname = 'jovra_gateway'),
  'jovra_gateway: login, noinherit, nobypassrls, connection limit 20');
select ok((select rolcanlogin and not rolinherit and not rolbypassrls and not rolsuper and rolconnlimit = 10
             from pg_roles where rolname = 'jovra_orchestrator'),
  'jovra_orchestrator: login, noinherit, nobypassrls, connection limit 10');
select ok(not pg_has_role('jovra_gateway', 'jovra_owner', 'usage')
          and not pg_has_role('jovra_orchestrator', 'jovra_owner', 'usage')
          and not pg_has_role('authenticated', 'jovra_owner', 'usage')
          and not pg_has_role('anon', 'jovra_owner', 'usage'),
  'no client, gateway or orchestrator role holds the privileges of jovra_owner');

select ok(has_schema_privilege('authenticated', 'app_private', 'usage')
          and not has_schema_privilege('anon', 'app_private', 'usage'),
  'policies may call app_private helpers as authenticated (security-model §3); anon may not reach them');
select ok(not has_schema_privilege('anon', 'app_ops', 'usage')
          and not has_schema_privilege('authenticated', 'app_ops', 'usage'),
  'app_ops is unreachable for client roles');

-- T-DB-02: RLS on every table in public, each with the restrictive real-user policy (§5.1) -------------------------
select tests.rls_enabled('public');
select ok((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p')) >= 4,
  'T-DB-02: public holds the migration 1 tables (the checks below are not vacuous)');
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
     and not exists (select 1 from pg_policy p
                      where p.polrelid = c.oid and not p.polpermissive
                        and p.polname = c.relname || '_real_users_only'
                        and p.polroles = array['authenticated'::regrole::oid]
                        and pg_get_expr(p.polqual, p.polrelid) like '%app_private.is_real_user()%')
$$, 'T-DB-02: every public table has the restrictive <table>_real_users_only policy for authenticated');

-- T-DB-03: function lint ------------------------------------------------------------------------------------------
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
$$, 'T-DB-03: no security definer function in public');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app_private', 'app_gateway', 'app_ops')
     and not coalesce(p.proconfig @> array['search_path=""'], false)
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
$$, 'T-DB-03: every function in public and app_* pins search_path=''''');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app_private', 'app_gateway', 'app_ops')
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'search_path=%public%')
$$, 'T-DB-03: no function pins search_path to public');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app_private', 'app_gateway')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where a.grantee = 0 and a.privilege_type = 'EXECUTE'))
$$, 'T-DB-03: no function in public, app_private or app_gateway is executable by PUBLIC or anon');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_gateway' and p.provolatile <> 'v'
$$, 'T-DB-03: every app_gateway function is volatile (the backstop against Hyperdrive result caching)');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_private' and p.prorettype = 'trigger'::regtype
     and has_function_privilege('authenticated', p.oid, 'execute')
$$, 'T-DB-03: no trigger function is executable by authenticated');

-- T-DB-04: client roles cannot reach app_gateway ------------------------------------------------------------------
select ok(not has_schema_privilege('authenticated', 'app_gateway', 'usage')
          and not has_schema_privilege('anon', 'app_gateway', 'usage'),
  'T-DB-04: authenticated and anon have no USAGE on app_gateway');
select is_empty($$
  select p.oid::regprocedure::text || ' ' || r.rolname from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   cross join (values ('authenticated'), ('anon')) r(rolname)
   where n.nspname = 'app_gateway' and has_function_privilege(r.rolname, p.oid, 'execute')
$$, 'T-DB-04: no app_gateway function is executable by authenticated or anon');
select ok(has_schema_privilege('jovra_gateway', 'app_gateway', 'usage')
          and has_schema_privilege('jovra_orchestrator', 'app_gateway', 'usage'),
  'T-DB-04: the gateway and orchestrator roles may use app_gateway');

-- T-DB-05: the command roles hold no table privilege anywhere -------------------------------------------------------
select is_empty($$
  select c.oid::regclass::text || ' ' || r.rolname from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   cross join (values ('jovra_gateway'), ('jovra_orchestrator')) r(rolname)
   where n.nspname in ('public', 'app_private', 'app_ops') and c.relkind in ('r', 'p', 'v', 'm')
     and (has_any_column_privilege(r.rolname, c.oid, 'select')
          or has_any_column_privilege(r.rolname, c.oid, 'insert')
          or has_any_column_privilege(r.rolname, c.oid, 'update')
          or has_table_privilege(r.rolname, c.oid, 'delete')
          or has_table_privilege(r.rolname, c.oid, 'truncate'))
$$, 'T-DB-05: jovra_gateway and jovra_orchestrator have no privilege on any table in public, app_private or app_ops');
select ok(not has_schema_privilege('jovra_gateway', 'app_private', 'usage')
          and not has_schema_privilege('jovra_orchestrator', 'app_private', 'usage')
          and not has_schema_privilege('jovra_gateway', 'app_ops', 'usage')
          and not has_schema_privilege('jovra_orchestrator', 'app_ops', 'usage'),
  'T-DB-05: the command roles cannot use app_private or app_ops');

-- T-DB-66: one owner, and no FORCE ROW LEVEL SECURITY (finding 26) -------------------------------------------------
select is_empty($$
  select c.oid::regclass::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'app_ops') and c.relkind in ('r', 'p')
     and c.relowner <> 'jovra_owner'::regrole
$$, 'T-DB-66: every table in public and app_ops is owned by jovra_owner');
select is_empty($$
  select t.oid::regtype::text from pg_type t join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public' and t.typtype = 'e' and t.typowner <> 'jovra_owner'::regrole
$$, 'T-DB-66: every enum in public is owned by jovra_owner');
-- The two S75 auth-hook functions read Vault and run for supabase_auth_admin; they are not RLS helpers, read no
-- Studio table and keep the migration owner (README "Not covered yet"). Every other function is jovra_owner's.
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'app_private', 'app_gateway')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and p.oid not in ('app_private.before_user_created(jsonb)'::regprocedure,
                       'app_private.email_hmac(text)'::regprocedure)
     and p.proowner <> 'jovra_owner'::regrole
$$, 'T-DB-66: every helper, trigger and command function is owned by jovra_owner');
-- SQL-language bodies record no dependency on the tables they read, so the pairing is checked exhaustively.
select is_empty($$
  select p.oid::regprocedure::text || ' vs ' || c.oid::regclass::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   cross join pg_class c
   where n.nspname in ('app_private', 'app_gateway') and p.prosecdef
     and p.oid not in ('app_private.before_user_created(jsonb)'::regprocedure,
                       'app_private.email_hmac(text)'::regprocedure)
     and c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
     and p.proowner <> c.relowner
$$, 'T-DB-66: proowner = relowner for every definer helper and every public table');
select is_empty($$
  select c.oid::regclass::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'app_ops') and c.relkind in ('r', 'p') and c.relforcerowsecurity
$$, 'T-DB-66: no table is FORCE ROW LEVEL SECURITY, so definer helpers read rows as the owner');

-- T-DB-67 (a): every client-insertable table has a00_rls_guard, first among its BEFORE INSERT triggers, and its
-- INSERT policy calls the same predicate function as the guard (§13.0, §13.11; finding 24) -------------------------
select ok((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r'
              and has_any_column_privilege('authenticated', c.oid, 'insert')) >= 1,
  'T-DB-67: at least one client-insertable table exists (the lint below is not vacuous)');
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and has_any_column_privilege('authenticated', c.oid, 'insert')
     and not exists (select 1 from pg_trigger g
                      where g.tgrelid = c.oid and not g.tgisinternal and g.tgname = 'a00_rls_guard'
                        and g.tgtype & 1 = 1 and g.tgtype & 2 = 2 and g.tgtype & 4 = 4)
$$, 'T-DB-67: every client-insertable table has a row-level BEFORE INSERT trigger a00_rls_guard');
select is_empty($$
  select c.relname::text || ': ' || g.tgname::text from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_trigger g on g.tgrelid = c.oid and not g.tgisinternal and g.tgtype & 2 = 2 and g.tgtype & 4 = 4
   where n.nspname = 'public' and c.relkind = 'r' and has_any_column_privilege('authenticated', c.oid, 'insert')
     and g.tgname::text collate "C" < 'a00_rls_guard'
$$, 'T-DB-67: no BEFORE INSERT trigger sorts before a00_rls_guard');
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and has_any_column_privilege('authenticated', c.oid, 'insert')
     and not exists (select 1 from pg_policy p
                      where p.polrelid = c.oid and p.polcmd = 'a' and p.polpermissive
                        and pg_get_expr(p.polwithcheck, p.polrelid) like '%app_private.can_insert_' || c.relname || '(%')
     or not exists (select 1 from pg_trigger g join pg_proc f on f.oid = g.tgfoid
                     where g.tgrelid = c.oid and g.tgname = 'a00_rls_guard'
                       and f.prosrc like '%app_private.can_insert_' || c.relname || '(%')
$$, 'T-DB-67: the INSERT policy and a00_rls_guard call the same app_private.can_insert_<table> predicate');

select * from finish();
rollback;
