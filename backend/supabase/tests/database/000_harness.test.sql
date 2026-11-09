-- pgTAP harness (S75 / B-02): basejump-style helpers to create users and act as them, after
-- https://github.com/usebasejump/supabase-test-helpers (MIT), written out here so the suite needs no network.
--
-- `supabase test db` runs the files in this folder in name order, each in its own session. This file runs first and
-- is the only one that commits: it installs the `tests` schema that later files use inside `begin; ... rollback;`.
-- The schema exists only in a database the suite has run against; migrations never create it.
--
--   tests.create_supabase_user(identifier, email default null) -> uuid   an auth.users row, email confirmed
--   tests.get_supabase_uid(identifier) -> uuid                           raises if the identifier is unknown
--   tests.authenticate_as(identifier)                                     role authenticated + that user's claims
--   tests.authenticate_as_service_role()                                  role service_role, no user
--   tests.clear_authentication()                                          role anon, no claims
--   tests.rls_enabled(schema) -> text (TAP)                               every table in the schema has RLS on

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

create or replace function tests.create_supabase_user(identifier text, email text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change_token_current, email_change,
    phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000'::uuid, v_id, 'authenticated', 'authenticated',
    coalesce(email, identifier || '@example.test'), '', now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    jsonb_build_object('test_identifier', identifier), now(), now(),
    '', '', '', '', '', '', '', ''
  );
  return v_id;
end
$$;

create or replace function tests.get_supabase_uid(identifier text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  select u.id into v_id from auth.users u where u.raw_user_meta_data ->> 'test_identifier' = identifier;
  if v_id is null then
    raise exception 'tests: no test user with identifier %', identifier;
  end if;
  return v_id;
end
$$;

create or replace function tests.get_supabase_user_email(identifier text)
returns text language sql stable security definer set search_path = '' as $$
  select u.email from auth.users u where u.id = tests.get_supabase_uid(identifier)
$$;

-- Security invoker on purpose: Postgres refuses SET ROLE inside a security definer function.
create or replace function tests.authenticate_as(identifier text)
returns void language plpgsql set search_path = '' as $$
declare
  v_id uuid := tests.get_supabase_uid(identifier);
  v_email text := tests.get_supabase_user_email(identifier);
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_id::text,
    'role', 'authenticated',
    'aud', 'authenticated',
    'email', v_email,
    'is_anonymous', false,
    'aal', 'aal1',
    'session_id', gen_random_uuid()::text,
    'amr', jsonb_build_array(jsonb_build_object('method', 'otp', 'timestamp', extract(epoch from now())::bigint)),
    'app_metadata', jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    'user_metadata', '{}'::jsonb
  )::text, true);
end
$$;

create or replace function tests.authenticate_as_service_role()
returns void language plpgsql set search_path = '' as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true);
end
$$;

create or replace function tests.clear_authentication()
returns void language plpgsql set search_path = '' as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '', true);
end
$$;

-- pgTAP's own functions call each other unqualified, so this helper needs `extensions` on its search_path.
create or replace function tests.rls_enabled(testing_schema text)
returns text language sql volatile set search_path = extensions as $$
  select extensions.is(
    (select count(*)::int
       from pg_catalog.pg_class c
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = testing_schema and c.relkind in ('r', 'p') and not c.relrowsecurity),
    0,
    'every table in schema ' || testing_schema || ' has row level security enabled')
$$;

-- A render host writes one planned output of its running attempt through the lease-fenced upload commands (S80):
-- authorize, attach, every 32 MiB part, the completion check and "written". Returns the artifact id, or
-- 'SQLSTATE message' of the first refusal (the commands' effects roll back with it). The caller must be a member of
-- jovra_orchestrator; security invoker, so the commands are reached through that role's own privileges.
create or replace function tests.write_attempt_output(p_attempt uuid, p_lease_token text, p_output_ref text,
                                                      p_bytes bigint, p_sha256 bytea)
returns text language plpgsql set search_path = '' as $$
declare
  v_lease   bytea := pg_catalog.sha256(pg_catalog.convert_to(p_lease_token, 'UTF8'));
  v_auth    jsonb;
  v_session uuid;
  v_count   int;
  v_bytes   bigint;
  v_parts   jsonb := '[]';
  v_state   text;
  v_msg     text;
begin
  execute 'set local role jovra_orchestrator';
  v_auth := app_gateway.authorize_output_upload_for_attempt(p_attempt, v_lease, p_output_ref, p_bytes, p_sha256,
                                                            gen_random_uuid());
  v_session := (v_auth ->> 'sessionId')::uuid;
  v_count := (v_auth ->> 'partCount')::int;
  perform app_gateway.attach_upload_id_for_attempt(p_attempt, v_lease, v_session, 'test-upload-' || v_session,
                                                   gen_random_uuid());
  for n in 1 .. v_count loop
    v_bytes := case when n < v_count then 33554432 else p_bytes - (v_count - 1)::bigint * 33554432 end;
    perform app_gateway.record_part_for_attempt(p_attempt, v_lease, v_session, n, v_bytes::int, 'etag-' || n,
                                                pg_catalog.sha256(pg_catalog.convert_to('part-' || n, 'UTF8')),
                                                pg_catalog.sha256(pg_catalog.convert_to('part-' || n, 'UTF8')),
                                                gen_random_uuid());
    v_parts := v_parts || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('n', n, 'etag', 'etag-' || n));
  end loop;
  perform app_gateway.complete_upload_check_for_attempt(p_attempt, v_lease, v_session, v_parts, gen_random_uuid());
  perform app_gateway.mark_output_written_for_attempt(p_attempt, v_lease, v_session, p_bytes, gen_random_uuid());
  execute 'reset role';
  return v_auth ->> 'artifactId';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return v_state || ' ' || v_msg;
end
$$;

revoke all on all functions in schema tests from public;
grant execute on all functions in schema tests to anon, authenticated, service_role;

begin;
select plan(1);
select ok(to_regprocedure('tests.authenticate_as(text)') is not null, 'harness: tests schema installed');
select * from finish();
rollback;
