-- Orchestrator command catalog (S80 / B-06): the orchestration commands exist, are jovra_orchestrator's alone and
-- follow the §4.1 template. T-DB-53 (the gateway role is refused every orchestration command), T-DB-57 (no function is
-- executable by both command roles; the §13.1 lint returns zero rows; every *_for_attempt function is refused to the
-- gateway), T-DB-04 for the new commands, T-DB-55 catalog half (every stage of the rate card has a positive floor and a
-- zero floor cannot be stored) and the new app_ops tables' guards. Rolls back.
begin;
select plan(24);

create temp table t_orch (sig regprocedure primary key, args text not null);
insert into t_orch values
  ('app_gateway.set_job_state(uuid, public.job_state, public.job_state, text, uuid)',
   $$gen_random_uuid(), 'verifying', 'ready', null, gen_random_uuid()$$),
  ('app_gateway.reserve_stage(uuid, public.job_stage, int, uuid)', $$gen_random_uuid(), 'normalize', 1, gen_random_uuid()$$),
  ('app_gateway.claim_attempt(uuid, text, text, uuid)', $$gen_random_uuid(), 'host-1', 'local-test', gen_random_uuid()$$),
  ('app_gateway.heartbeat_attempt(uuid, bytea, int, uuid)', $$gen_random_uuid(), sha256('x'::bytea), 0, gen_random_uuid()$$),
  ('app_gateway.finish_attempt(uuid, bytea, text, jsonb, jsonb, text, boolean, uuid, uuid)',
   $$gen_random_uuid(), sha256('x'::bytea), 'succeeded', '[]', '{}', null, null, null, gen_random_uuid()$$),
  ('app_gateway.mark_artifact_verified(uuid, bytea, uuid, jsonb, uuid)',
   $$gen_random_uuid(), sha256('x'::bytea), gen_random_uuid(), '{"decoded": true}', gen_random_uuid()$$),
  ('app_gateway.expire_attempt_leases(uuid)', $$gen_random_uuid()$$),
  ('app_gateway.delete_lesson_rows(uuid, uuid)', $$gen_random_uuid(), gen_random_uuid()$$),
  ('app_gateway.audit_denial_for_attempt(uuid, text, text, uuid)',
   $$gen_random_uuid(), 'attempt.result', 'stale_lease', gen_random_uuid()$$);

select is((select count(*)::int from pg_temp.t_orch), 9, 'the S80 orchestration command list has 9 functions');

-- T-DB-04: no client role reaches them ------------------------------------------------------------------------------
select is_empty($$
  select o.sig::text || ' ' || r.rolname from pg_temp.t_orch o
   cross join (values ('authenticated'), ('anon'), ('service_role')) r(rolname)
   where has_function_privilege(r.rolname, o.sig, 'execute')
$$, 'T-DB-04: no S80 command is executable by authenticated, anon or service_role');
select is_empty($$
  select o.sig::text from pg_temp.t_orch o join pg_proc p on p.oid = o.sig
   where exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where a.grantee = 0 and a.privilege_type = 'EXECUTE')
$$, 'T-DB-04: no S80 command is executable by PUBLIC');

-- T-DB-53 / T-DB-57: the orchestrator's alone -------------------------------------------------------------------------
select is_empty($$
  select o.sig::text from pg_temp.t_orch o where not has_function_privilege('jovra_orchestrator', o.sig, 'execute')
$$, 'jovra_orchestrator may execute every S80 command');
select is_empty($$
  select o.sig::text from pg_temp.t_orch o where has_function_privilege('jovra_gateway', o.sig, 'execute')
$$, 'T-DB-53 / T-DB-57: jovra_gateway cannot execute any orchestration command');
select is_empty($$
  select p.oid::regprocedure::text
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_gateway'
     and has_function_privilege('jovra_gateway', p.oid, 'execute')
     and has_function_privilege('jovra_orchestrator', p.oid, 'execute')
$$, 'T-DB-57: the §13.1 lint query returns zero rows (no function executable by both roles)');
select ok((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app_gateway' and has_function_privilege('jovra_gateway', p.oid, 'execute')) >= 27
          and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'app_gateway' and has_function_privilege('jovra_orchestrator', p.oid, 'execute')) >= 9,
  'T-DB-57: both roles hold commands, so the zero-row lint above is not vacuous');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_gateway' and p.proname like '%\_for\_attempt'
     and (has_function_privilege('jovra_gateway', p.oid, 'execute')
          or not has_function_privilege('jovra_orchestrator', p.oid, 'execute'))
$$, 'T-DB-57: every *_for_attempt function is executable by jovra_orchestrator and never by jovra_gateway');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app_gateway'
     and not has_function_privilege('jovra_gateway', p.oid, 'execute')
     and not has_function_privilege('jovra_orchestrator', p.oid, 'execute')
$$, 'every app_gateway function belongs to exactly one command role (none is orphaned)');

-- Called as jovra_gateway, every orchestration command is refused by the privilege system, before any row is read.
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
select is_empty($$
  select o.sig::text || ': ' || pg_temp.gw_state(format('select %s(%s)', p.oid::regproc::text, o.args))
    from pg_temp.t_orch o join pg_proc p on p.oid = o.sig
   where pg_temp.gw_state(format('select %s(%s)', p.oid::regproc::text, o.args))
         <> '42501 permission denied for function ' || p.proname
$$, 'T-DB-53: as jovra_gateway, every orchestration command (set_job_state, reserve_stage, finish_attempt, '
    'mark_artifact_verified, ...) is 42501 permission denied');
select is(pg_temp.gw_state($$select app_gateway.set_job_state(gen_random_uuid(), 'verifying', 'ready', null,
                                                              gen_random_uuid())$$),
  '42501 permission denied for function set_job_state', 'T-DB-53: jovra_gateway calling set_job_state is denied');
select is(pg_temp.gw_state($$select app_gateway.audit_denial_for_attempt(gen_random_uuid(), 'attempt.claim',
                                                                         'already_claimed', gen_random_uuid())$$),
  '42501 permission denied for function audit_denial_for_attempt',
  'T-DB-57: a *_for_attempt function called as jovra_gateway is denied');

-- §4.1 template -----------------------------------------------------------------------------------------------------
select is_empty($$
  select o.sig::text from pg_temp.t_orch o join pg_proc p on p.oid = o.sig
   where p.provolatile <> 'v' or not p.prosecdef or p.proconfig is distinct from array['search_path=""']
      or p.proowner <> 'jovra_owner'::regrole
$$, 'every S80 command is volatile, security definer, search_path '''' and owned by jovra_owner');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p
   where p.oid in ('app_private.job_transition_allowed(public.job_state, public.job_state, public.job_state)'::regprocedure,
                   'app_private.lock_attempt(uuid, bytea)'::regprocedure,
                   'app_private.hold_rate_card(public.usage_reservations)'::regprocedure,
                   'app_private.attempt_actual_cost(app_ops.rate_cards, jsonb)'::regprocedure,
                   'app_private.attempt_outputs_are_valid(jsonb, jsonb)'::regprocedure,
                   'app_private.stage_output_plan(public.job_stage, int)'::regprocedure)
     and (has_function_privilege('authenticated', p.oid, 'execute')
          or has_function_privilege('jovra_gateway', p.oid, 'execute')
          or has_function_privilege('jovra_orchestrator', p.oid, 'execute'))
$$, 'the transition table, lease lock, rate-card and output helpers run only inside definer commands');

-- New columns and the one-success index --------------------------------------------------------------------------
select has_column('public', 'render_jobs', 'resume_state', 'render_jobs.resume_state exists');
select has_column('public', 'render_attempts', 'charged_cost_micro_usd', 'render_attempts.charged_cost_micro_usd exists');
select ok(not has_column_privilege('authenticated', 'public.render_attempts', 'charged_cost_micro_usd', 'select')
          and not has_column_privilege('authenticated', 'public.render_jobs', 'resume_state', 'select'),
  'finding 32: the charge of a stage and the resume state are never granted to a client');
select matches((select indexdef from pg_indexes where schemaname = 'public' and indexname = 'render_attempts_one_success'),
  'UNIQUE INDEX .* \(job_id, stage\) WHERE \(state = ''succeeded''::text\)',
  'consumption once per (job, stage): a unique index allows one succeeded attempt per stage');

-- T-DB-55 (catalog half): the rate card and its guards ----------------------------------------------------------------
select is((select count(*)::int from app_ops.stage_rates where rates_version = 'rates-v0-inferred'),
  (select count(*)::int from unnest(enum_range(null::public.job_stage))),
  'T-DB-55: rates-v0-inferred prices every job stage');
select is_empty($$select stage::text from app_ops.stage_rates where floor_micro_usd <= 0$$,
  'T-DB-55: every stage floor is positive');
select throws_ok($$insert into app_ops.stage_rates (rates_version, stage, floor_micro_usd)
                   values ('rates-v0-inferred', 'cleanup', 0)$$, '23514', null,
  'T-DB-55: a zero stage floor cannot be stored (CHECK floor_micro_usd > 0)');
select ok((select bool_and(c.relrowsecurity and exists (select 1 from pg_trigger t
                                                         where t.tgrelid = c.oid and t.tgname = 'a05_refuse_secrets'))
             from pg_class c where c.oid in ('app_ops.rate_cards'::regclass, 'app_ops.stage_rates'::regclass)),
  'the rate-card tables have RLS and the a05 secret guard like every app_ops table');
select is_empty($$
  select r.rolname from (values ('jovra_gateway'), ('jovra_orchestrator'), ('authenticated'), ('anon'),
                                ('service_role')) r(rolname)
   where has_any_column_privilege(r.rolname, 'app_ops.rate_cards', 'select')
      or has_any_column_privilege(r.rolname, 'app_ops.stage_rates', 'select')
      or has_table_privilege(r.rolname, 'app_ops.stage_rates', 'delete')
$$, 'T-DB-05: no client or command role reads or writes the rate card');
select ok((select pg_get_constraintdef(oid) from pg_constraint
            where conname = 'audit_events_actor_kind_check' and conrelid = 'app_ops.audit_events'::regclass)
          like '%orchestrator%render_attempt%',
  'audit rows can name the orchestrator and a render attempt as their actor');

select * from finish();
rollback;
