-- Migration 1 triggers (S76 / B-03 with B-23/B-25): the role-first a00_rls_guard (finding 24), the client-path
-- test, coded length errors before constraints, the owner-row invariant and the claim reader the definer helpers
-- use. docs/backend/security-model.md §9, §13.0, §13.11; architecture.md §4.4. The file rolls back.
begin;
select plan(30);

select tests.create_supabase_user('victim');
select tests.create_supabase_user('intruder');
select tests.create_supabase_user('anonymous_user');
update auth.users set is_anonymous = true where id = tests.get_supabase_uid('anonymous_user');

insert into public.projects (id, owner_id, local_project_id, title) values
  ('e0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('victim'),
   'e1000000-0000-4000-8000-000000000001', 'Victim match');

-- Errors are inspected whole: SQLSTATE, message and DETAIL (security-model §9: no "Failing row contains" DETAIL).
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

-- The claim reader -------------------------------------------------------------------------------------------------
-- Definer helpers run as jovra_owner, which has no access to the auth schema; they read the same request claims
-- auth.uid() reads. These pin the two together.
select tests.authenticate_as('victim');
select is(app_private.current_actor(), auth.uid(), 'current_actor() equals auth.uid() for a signed-in user');
select is(app_private.is_real_user(), true, 'is_real_user() is true for a signed-in, non-anonymous user');
reset role;
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', tests.get_supabase_uid('victim')::text, true);
select is(app_private.current_actor(), auth.uid(), 'current_actor() follows auth.uid() for the legacy claim setting');
select set_config('request.jwt.claim.sub', '', true);
select is(app_private.current_actor(), null, 'current_actor() is null when no claim is set');

-- T-DB-67 (b): the client path is the PostgREST role, also inside a security definer function --------------------------
select is(app_private.is_client_path(), false, 'T-DB-67: postgres (operator, migrations) is not the client path');
select tests.authenticate_as('intruder');
select is(app_private.can_insert_projects(tests.get_supabase_uid('victim'), null), false,
  'T-DB-67: the projects predicate refuses a row owned by someone else');
reset role;
-- A stand-in for a server command (B-06 adds the real ones): a definer function in app_gateway, owned by
-- jovra_owner, that inserts a project for an explicit owner.
create function app_gateway.t67_insert_project(p_owner uuid) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare v_id uuid;
begin
  insert into public.projects (owner_id, local_project_id, title)
  values (p_owner, gen_random_uuid(), 'Server-created') returning id into v_id;
  return v_id;
end $$;
alter function app_gateway.t67_insert_project(uuid) owner to jovra_owner;
revoke all on function app_gateway.t67_insert_project(uuid) from public;
grant execute on function app_gateway.t67_insert_project(uuid) to jovra_gateway, authenticated;
grant usage on schema app_gateway to authenticated;
grant jovra_gateway to postgres;

-- jovra_gateway can reach nothing but app_gateway, so the call stores its result in a setting for the checks below.
select set_config('t67.victim', tests.get_supabase_uid('victim')::text, true);
set local role jovra_gateway;
select set_config('t67.created', app_gateway.t67_insert_project(current_setting('t67.victim')::uuid)::text, true);
reset role;
select is((select owner_id from public.projects where id = current_setting('t67.created')::uuid),
  tests.get_supabase_uid('victim'),
  'T-DB-67: a server command run by jovra_gateway inserts past the guard (is_client_path() false)');
select tests.authenticate_as('intruder');
select throws_ok($$select app_gateway.t67_insert_project(tests.get_supabase_uid('victim'))$$, '42501',
  'new row violates row-level security policy for table "projects"',
  'T-DB-67: the same definer insert called through the client role is refused by the guard');
reset role;
select is((select count(*)::int from public.projects where owner_id = tests.get_supabase_uid('victim')), 2,
  'T-DB-67: exactly the server-created project was added for the victim');

-- T-DB-65: the guard answers first, with RLS's own error, whatever the row holds ---------------------------------------
-- Anonymous-authenticated: every variant (valid row, over-long title, bad kind, missing local id) gets one answer.
select set_config('request.jwt.claims', jsonb_build_object('sub', tests.get_supabase_uid('anonymous_user')::text,
  'role', 'authenticated', 'is_anonymous', true)::text, true);
select set_config('role', 'authenticated', true);
select is(pg_temp.error_of($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), 'ok')$$),
  '42501 | new row violates row-level security policy for table "projects" | ',
  'T-DB-65: anonymous user, valid row: 42501 RLS error, no DETAIL');
select is(pg_temp.error_of(format($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), %L)$$,
  repeat('x', 500))),
  '42501 | new row violates row-level security policy for table "projects" | ',
  'T-DB-65: anonymous user, over-long title: the same 42501, not the length error');
select is(pg_temp.error_of($$insert into public.projects (local_project_id, title, kind)
                             values (gen_random_uuid(), 'x', 'tournament')$$),
  '42501 | new row violates row-level security policy for table "projects" | ',
  'T-DB-65: anonymous user, invalid kind: the same 42501');
select is(pg_temp.error_of($$insert into public.projects (local_project_id, title)
                             values ('e1000000-0000-4000-8000-000000000001', 'x')$$),
  '42501 | new row violates row-level security policy for table "projects" | ',
  'T-DB-65: anonymous user naming the victim''s local project id: the same 42501');
reset role;

-- A real user naming the victim's local project id gets their own project: no unique-violation oracle.
select tests.authenticate_as('intruder');
select is(pg_temp.error_of($$insert into public.projects (local_project_id, title)
                             values ('e1000000-0000-4000-8000-000000000001', 'Mine')$$), 'no error',
  'T-DB-65: an unrelated user reusing the victim''s local project id learns nothing (own row, no conflict)');
reset role;
select results_eq($$select title, revision from public.projects where id = 'e0000000-0000-4000-8000-000000000001'$$,
  $$values ('Victim match'::text, 1::bigint)$$, 'T-DB-65: the victim''s project and revision are untouched');

-- Coded length and value errors before constraints (P0422, no DETAIL) ------------------------------------------------
select tests.authenticate_as('victim');
select is(pg_temp.error_of(format($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), %L)$$,
  repeat('x', 121))), 'P0422 | field_too_long:title | ', 'a 121-character title: P0422 field_too_long:title');
select is(pg_temp.error_of(format($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), %L)$$,
  repeat('x', 120))), 'no error', 'a 120-character title is accepted');
select is(pg_temp.error_of($$insert into public.projects (local_project_id, title, kind)
                             values (gen_random_uuid(), 'x', 'tournament')$$),
  'P0422 | invalid_value:kind | ', 'an unknown kind: P0422 invalid_value:kind (no CHECK DETAIL)');
select is(pg_temp.error_of($$insert into public.projects (title) values ('no local id')$$),
  'P0422 | required:local_project_id | ', 'a missing local project id: P0422 required:local_project_id');
select is(pg_temp.error_of($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), null)$$),
  'P0422 | required:title | ', 'a null title: P0422 required:title (no NOT NULL DETAIL)');
select is(pg_temp.error_of(format($$update public.projects set title = %L where id = 'e0000000-0000-4000-8000-000000000001'$$,
  repeat('x', 121))), 'P0422 | field_too_long:title | ', 'an over-long title on update: P0422');
select is(pg_temp.error_of(format($$update public.profiles set display_name = %L where id = auth.uid()$$,
  repeat('n', 81))), 'P0422 | field_too_long:display_name | ', 'an 81-character display name: P0422');
select is(pg_temp.error_of(format($$update public.profiles set display_name = %L where id = auth.uid()$$,
  repeat('n', 80))), 'no error', 'an 80-character display name is accepted');
reset role;

-- Server-written tables validate too (a guest-supplied label or hash must never reach a CHECK DETAIL).
select is(pg_temp.error_of(format($$insert into public.camera_invites (project_id, slot, display_label, code_hash,
                                      created_by, redeem_by)
                                    values ('e0000000-0000-4000-8000-000000000001', 'far_ad_corner', %L,
                                            sha256('c1'::bytea), %L, now() + interval '5 minutes')$$,
  repeat('l', 61), tests.get_supabase_uid('victim'))), 'P0422 | field_too_long:display_label | ',
  'camera_invites: a 61-character label is P0422');
select is(pg_temp.error_of(format($$insert into public.camera_invites (project_id, slot, code_hash, created_by, redeem_by)
                                    values ('e0000000-0000-4000-8000-000000000001', 'far_ad_corner',
                                            '\x0102'::bytea, %L, now() + interval '5 minutes')$$,
  tests.get_supabase_uid('victim'))), 'P0422 | invalid_value:code_hash | ',
  'camera_invites: a code hash that is not 32 bytes is P0422 without echoing it');
select is(pg_temp.error_of(format($$insert into public.camera_invites (project_id, slot, code_hash, created_by, redeem_by)
                                    values ('e0000000-0000-4000-8000-000000000001', 'far_ad_corner',
                                            sha256('c2'::bytea), %L, now() + interval '11 minutes')$$,
  tests.get_supabase_uid('victim'))), 'P0422 | invalid_value:redeem_by | ',
  'camera_invites: redeem_by more than 10 minutes out is P0422');
select is(pg_temp.error_of(format($$insert into public.camera_invites (project_id, slot, code_hash, created_by, redeem_by)
                                    values ('e0000000-0000-4000-8000-000000000001', 'far_ad_corner',
                                            sha256('c3'::bytea), %L, now() + interval '5 minutes')$$,
  tests.get_supabase_uid('intruder'))), 'P0422 | invalid_value:created_by | ',
  'camera_invites: an invite created by someone other than the project owner is P0422');

-- Owner-row invariant (architecture §4.3: exactly one owner row, equal to projects.owner_id) -------------------------
select is(pg_temp.error_of(format($$insert into public.project_members (project_id, user_id, role)
                                    values ('e0000000-0000-4000-8000-000000000001', %L, 'owner')$$,
  tests.get_supabase_uid('intruder'))), 'P0422 | invalid_value:role | ',
  'a second owner row (not the project owner) is refused');
select is((select count(*)::int from public.project_members
            where project_id = 'e0000000-0000-4000-8000-000000000001' and role = 'owner'), 1,
  'the project still has exactly one owner row');

-- Revision and updated_at are server-managed --------------------------------------------------------------------------
select tests.authenticate_as('victim');
select results_eq($$update public.projects set title = 'Victim match, set 2'
                    where id = 'e0000000-0000-4000-8000-000000000001' returning revision, updated_at >= created_at$$,
  $$values (2::bigint, true)$$, 'an update bumps revision by one');
reset role;

select * from finish();
rollback;
