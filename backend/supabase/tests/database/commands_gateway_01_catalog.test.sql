-- Gateway command catalog (S79 / B-06): the user-route commands exist, are the gateway's alone and reach nothing else.
-- T-DB-04 (no client role may execute any app_gateway function; function_privs_are per command), T-DB-05 (the command
-- roles hold no table privilege, including the new app_ops.settings), T-DB-57 (a render actor is refused by
-- authorize_upload; no function is executable by both command roles), and the §4.1 template (volatile, definer,
-- search_path '', owned by jovra_owner). identity_01 lints every function of every migration as well. Rolls back.
begin;
select plan(26);

create temp table t_commands (sig regprocedure primary key);
insert into t_commands values
  ('app_gateway.audit_denial(text, uuid, text, text, uuid, text, uuid)'),
  ('app_gateway.create_project(uuid, uuid, text, text, boolean, uuid)'),
  ('app_gateway.declare_source(uuid, uuid, public.camera_slot, uuid, bigint, bytea, jsonb, uuid)'),
  ('app_gateway.create_camera_invite(uuid, uuid, public.camera_slot, text, bytea, uuid)'),
  ('app_gateway.revoke_camera_invite(uuid, uuid, uuid)'),
  ('app_gateway.redeem_camera_invite(bytea, bytea, text, uuid, uuid)'),
  ('app_gateway.approve_camera_invite(uuid, uuid, text, uuid)'),
  ('app_gateway.issue_guest_capability(uuid, bytea, bytea, uuid)'),
  ('app_gateway.guest_declare_source(uuid, bytea, uuid, bigint, bytea, jsonb, uuid)'),
  ('app_gateway.authorize_upload(text, uuid, uuid, bigint, bytea, uuid)'),
  ('app_gateway.attach_upload_id(text, uuid, uuid, text, bytea, uuid)'),
  ('app_gateway.record_part(uuid, bytea, int, int, text, bytea, bytea, uuid)'),
  ('app_gateway.complete_upload_check(uuid, bytea, jsonb, uuid)'),
  ('app_gateway.mark_uploaded_unverified(uuid, bytea, bigint, uuid)'),
  ('app_gateway.abort_upload(uuid, bytea, uuid, uuid)'),
  ('app_gateway.create_grant(uuid, public.grant_kind, text, uuid, uuid, uuid, uuid, int, bytea, uuid)'),
  ('app_gateway.redeem_grant(uuid, bytea, uuid)'),
  ('app_gateway.list_pending_members(uuid, uuid, uuid)'),
  ('app_gateway.approve_member(uuid, uuid, uuid, text, uuid)'),
  ('app_gateway.revoke_grant(uuid, uuid, uuid)'),
  ('app_gateway.revoke_member(uuid, uuid, uuid, uuid)'),
  ('app_gateway.create_share_link(uuid, uuid, int, boolean, bytea, uuid)'),
  ('app_gateway.redeem_share_link(bytea, uuid)'),
  ('app_gateway.request_deletion(uuid, public.deletion_scope, uuid, uuid, boolean, uuid)'),
  ('app_gateway.create_quote(uuid, uuid, uuid, uuid, text, jsonb, uuid[], int, uuid)'),
  ('app_gateway.accept_quote(uuid, uuid, bytea, jsonb, int, text, uuid)'),
  ('app_gateway.review_job(uuid, uuid, text, uuid, uuid)');

select is((select count(*)::int from pg_temp.t_commands), 27, 'the S79 user-route command list has 27 functions');

-- T-DB-04 ----------------------------------------------------------------------------------------------------------
select is_empty($$
  select c.sig::text || ' ' || r.rolname from pg_temp.t_commands c
   cross join (values ('authenticated'), ('anon'), ('service_role')) r(rolname)
   where has_function_privilege(r.rolname, c.sig, 'execute')
$$, 'T-DB-04: no S79 command is executable by authenticated, anon or service_role');
select is_empty($$
  select c.sig::text from pg_temp.t_commands c join pg_proc p on p.oid = c.sig
   where exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where a.grantee = 0 and a.privilege_type = 'EXECUTE')
$$, 'T-DB-04: no S79 command is executable by PUBLIC');
select function_privs_are('app_gateway', 'accept_quote', array['uuid', 'uuid', 'bytea', 'jsonb', 'integer', 'text', 'uuid'],
  'authenticated', '{}'::text[], 'T-DB-04: authenticated has no EXECUTE on accept_quote');
select function_privs_are('app_gateway', 'accept_quote', array['uuid', 'uuid', 'bytea', 'jsonb', 'integer', 'text', 'uuid'],
  'anon', '{}'::text[], 'T-DB-04: anon has no EXECUTE on accept_quote');
select function_privs_are('app_gateway', 'create_quote',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'jsonb', 'uuid[]', 'integer', 'uuid'],
  'authenticated', '{}'::text[], 'T-DB-04: authenticated has no EXECUTE on create_quote');
select function_privs_are('app_gateway', 'redeem_grant', array['uuid', 'bytea', 'uuid'], 'authenticated', '{}'::text[],
  'T-DB-04: authenticated has no EXECUTE on redeem_grant');
select function_privs_are('app_gateway', 'complete_upload_check', array['uuid', 'bytea', 'jsonb', 'uuid'], 'anon',
  '{}'::text[], 'T-DB-04: anon has no EXECUTE on complete_upload_check');
select function_privs_are('app_gateway', 'accept_quote', array['uuid', 'uuid', 'bytea', 'jsonb', 'integer', 'text', 'uuid'],
  'jovra_gateway', array['EXECUTE'], 'the gateway role may execute accept_quote');
select is_empty($$
  select c.sig::text from pg_temp.t_commands c where not has_function_privilege('jovra_gateway', c.sig, 'execute')
$$, 'jovra_gateway may execute every S79 command');

-- T-DB-57: user commands are never the orchestrator's; nothing is executable by both ----------------------------------
select is_empty($$
  select c.sig::text from pg_temp.t_commands c where has_function_privilege('jovra_orchestrator', c.sig, 'execute')
$$, 'T-DB-57: jovra_orchestrator cannot execute any user-route command');
select is_empty($$
  select p.oid::regprocedure::text
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_gateway'
     and has_function_privilege('jovra_gateway', p.oid, 'execute')
     and has_function_privilege('jovra_orchestrator', p.oid, 'execute')
$$, 'T-DB-57: the §13.1 lint query returns zero rows (no function executable by both roles)');
grant jovra_gateway to postgres;
create function pg_temp.gw_state(p_sql text) returns text language plpgsql as $$
declare
  v_state text;
  v_msg   text;
begin
  execute 'set local role jovra_gateway';
  execute p_sql;
  execute 'reset role';
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return v_state || ' ' || v_msg;
end $$;
select is(pg_temp.gw_state($$select app_gateway.authorize_upload('render_host', gen_random_uuid(), gen_random_uuid(),
                                1, sha256('x'::bytea), gen_random_uuid())$$),
  'P0422 actor_kind_not_accepted', 'T-DB-57: authorize_upload(''render_host'', ...) is P0422 actor_kind_not_accepted');
select is(pg_temp.gw_state($$select app_gateway.attach_upload_id('render_host', gen_random_uuid(), gen_random_uuid(),
                                'u', sha256('x'::bytea), gen_random_uuid())$$),
  'P0422 actor_kind_not_accepted', 'T-DB-57: attach_upload_id refuses a render actor the same way');

-- §4.1 template ------------------------------------------------------------------------------------------------------
select is_empty($$
  select c.sig::text from pg_temp.t_commands c join pg_proc p on p.oid = c.sig
   where p.provolatile <> 'v' or not p.prosecdef or p.proconfig is distinct from array['search_path=""']
      or p.proowner <> 'jovra_owner'::regrole
$$, 'every S79 command is volatile, security definer, search_path '''' and owned by jovra_owner');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p
   where p.oid in ('app_private.commit_spend(uuid, uuid, text, bigint)'::regprocedure,
                   'app_private.quote_inputs(uuid, uuid, uuid, text, jsonb, uuid[], int)'::regprocedure,
                   'app_private.lock_owned_project(uuid, uuid)'::regprocedure,
                   'app_private.lock_upload_session(uuid, bytea)'::regprocedure,
                   'app_private.upload_actor_ok(text, uuid, uuid, uuid)'::regprocedure,
                   'app_private.require_real_user(uuid)'::regprocedure)
     and (has_function_privilege('authenticated', p.oid, 'execute')
          or has_function_privilege('jovra_gateway', p.oid, 'execute')
          or has_function_privilege('jovra_orchestrator', p.oid, 'execute'))
$$, 'the spend ledger, quote inputs and actor helpers run only inside definer commands');
select ok((select proowner <> 'jovra_owner'::regrole from pg_proc
            where oid = 'app_private.auth_user_facts(uuid, uuid)'::regprocedure)
          and has_function_privilege('jovra_owner', 'app_private.auth_user_facts(uuid, uuid)', 'execute')
          and not has_function_privilege('authenticated', 'app_private.auth_user_facts(uuid, uuid)', 'execute')
          and not has_function_privilege('jovra_gateway', 'app_private.auth_user_facts(uuid, uuid)', 'execute')
          and not has_function_privilege('service_role', 'app_private.auth_user_facts(uuid, uuid)', 'execute'),
  'auth_user_facts reads the auth schema as the migration owner and is executable by jovra_owner only');
select ok(has_function_privilege('jovra_owner', 'app_private.email_hmac(text)', 'execute')
          and not has_function_privilege('jovra_gateway', 'app_private.email_hmac(text)', 'execute'),
  '§13.2: commands owned by jovra_owner may bind invitations to an email HMAC; the gateway role may not');

-- T-DB-05: the command roles reach no table, the new one included -------------------------------------------------
select has_table('app_ops', 'settings', 'app_ops.settings exists');
select is_empty($$
  select r.rolname from (values ('jovra_gateway'), ('jovra_orchestrator'), ('authenticated'), ('anon')) r(rolname)
   where has_any_column_privilege(r.rolname, 'app_ops.settings', 'select')
      or has_any_column_privilege(r.rolname, 'app_ops.settings', 'insert')
      or has_any_column_privilege(r.rolname, 'app_ops.settings', 'update')
      or has_table_privilege(r.rolname, 'app_ops.settings', 'delete')
$$, 'T-DB-05: no client or command role may read or write app_ops.settings');
select is_empty($$
  select c.oid::regclass::text || ' ' || r.rolname from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   cross join (values ('jovra_gateway'), ('jovra_orchestrator')) r(rolname)
   where n.nspname in ('public', 'app_private', 'app_ops') and c.relkind in ('r', 'p', 'v', 'm')
     and (has_any_column_privilege(r.rolname, c.oid, 'select')
          or has_any_column_privilege(r.rolname, c.oid, 'insert')
          or has_any_column_privilege(r.rolname, c.oid, 'update')
          or has_table_privilege(r.rolname, c.oid, 'delete'))
$$, 'T-DB-05: jovra_gateway and jovra_orchestrator still hold no table privilege anywhere');
select ok(pg_temp.gw_state('select count(*) from public.quotes') like '42501 %',
  'T-DB-05: as jovra_gateway, select on quotes is denied (42501)');
select is(pg_temp.gw_state($$insert into app_ops.audit_events (env, actor_kind, action, outcome)
                              values ('local', 'gateway', 'x.y', 'allowed')$$),
  '42501 permission denied for schema app_ops', 'T-DB-05: as jovra_gateway, app_ops is unreachable except through commands');
select ok((select relrowsecurity from pg_class where oid = 'app_ops.settings'::regclass)
          and exists (select 1 from pg_trigger where tgrelid = 'app_ops.settings'::regclass
                       and tgname = 'a05_refuse_secrets'),
  'app_ops.settings has RLS and the a05 secret guard like every app_ops table');
select ok(exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'camera_invites' and column_name = 'capability_hash')
          and not has_column_privilege('authenticated', 'public.camera_invites', 'capability_hash', 'select'),
  'camera_invites.capability_hash exists and is never selectable by a client');
select is((select env from app_ops.settings), 'local', 'the local seed names this stack ''local''');

select * from finish();
rollback;
