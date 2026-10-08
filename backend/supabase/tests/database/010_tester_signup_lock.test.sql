-- Server-enforced tester sign-up (S75 / B-02; ADR-0022; security-model §13.3; finding 15, database half of T-GW-30).
-- The HTTP half (an OTP request with create_user true for an unknown email is refused by the running Auth service)
-- is scripts/otp_smoke.py.
begin;
select plan(30);

-- Shape and privileges -------------------------------------------------------------------------------------------
select has_function('app_private', 'before_user_created', array['jsonb'], 'the before_user_created hook exists');
select is((select prosecdef from pg_proc where oid = 'app_private.before_user_created(jsonb)'::regprocedure), true,
  'the hook is security definer');
select is((select proconfig from pg_proc where oid = 'app_private.before_user_created(jsonb)'::regprocedure),
  array['search_path=""'], 'the hook pins an empty search_path');
select is((select proconfig from pg_proc where oid = 'app_private.email_hmac(text)'::regprocedure),
  array['search_path=""'], 'email_hmac pins an empty search_path');

select ok(has_function_privilege('supabase_auth_admin', 'app_private.before_user_created(jsonb)', 'execute'),
  'supabase_auth_admin can run the hook');
select ok(not has_function_privilege('anon', 'app_private.before_user_created(jsonb)', 'execute'),
  'anon cannot run the hook');
select ok(not has_function_privilege('authenticated', 'app_private.before_user_created(jsonb)', 'execute'),
  'authenticated cannot run the hook');
select ok(not has_function_privilege('service_role', 'app_private.before_user_created(jsonb)', 'execute'),
  'service_role cannot run the hook');
select ok(not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                       where p.oid = 'app_private.before_user_created(jsonb)'::regprocedure and a.grantee = 0),
  'PUBLIC has no EXECUTE on the hook');

select ok(not has_function_privilege('anon', 'app_private.email_hmac(text)', 'execute'), 'anon cannot run email_hmac');
select ok(not has_function_privilege('authenticated', 'app_private.email_hmac(text)', 'execute'),
  'authenticated cannot run email_hmac');
select ok(not has_function_privilege('supabase_auth_admin', 'app_private.email_hmac(text)', 'execute'),
  'supabase_auth_admin cannot run email_hmac directly');
select ok(not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                       where p.oid = 'app_private.email_hmac(text)'::regprocedure and a.grantee = 0),
  'PUBLIC has no EXECUTE on email_hmac');

select ok(not has_schema_privilege('anon', 'app_private', 'usage')
          and not has_schema_privilege('authenticated', 'app_private', 'usage')
          and not has_schema_privilege('anon', 'app_ops', 'usage')
          and not has_schema_privilege('authenticated', 'app_ops', 'usage'),
  'client roles cannot use app_private or app_ops');
select ok(not has_table_privilege('authenticated', 'app_ops.tester_allowlist', 'select')
          and not has_table_privilege('authenticated', 'app_ops.tester_allowlist', 'insert')
          and not has_table_privilege('anon', 'app_ops.tester_allowlist', 'select')
          and not has_table_privilege('service_role', 'app_ops.tester_allowlist', 'insert'),
  'no client or API role can read or write the allow-list');
select tests.rls_enabled('app_ops');
select ok(not exists (select 1 from information_schema.columns
                       where table_schema = 'app_ops' and table_name = 'tester_allowlist'
                         and column_name ilike '%email%' and column_name <> 'email_hmac'),
  'the allow-list stores only an HMAC, never the address');

-- Behaviour ------------------------------------------------------------------------------------------------------
select is(app_private.before_user_created('{"user": {"email": "owner.tester@example.test"}}'::jsonb), '{}'::jsonb,
  'an allow-listed tester may be created');
select is(app_private.before_user_created('{"user": {"email": "pending.tester@example.test"}}'::jsonb), '{}'::jsonb,
  'an allow-listed address that has no account yet may be created');
select is(app_private.before_user_created('{"user": {"email": "  Owner.Tester@EXAMPLE.test "}}'::jsonb), '{}'::jsonb,
  'the address is trimmed and lower-cased before it is checked');
select is(app_private.before_user_created('{"user": {"email": "stranger@example.test"}}'::jsonb),
  '{"error": {"http_code": 403, "message": "signup_not_allowed"}}'::jsonb,
  'an address that is not on the allow-list is refused with 403 signup_not_allowed');
select is(app_private.before_user_created('{"user": {"phone": "15555550100"}}'::jsonb) -> 'error' ->> 'http_code',
  '403', 'a sign-up without an email (phone) is refused');
select is(app_private.before_user_created('{"user": {"is_anonymous": true}}'::jsonb) -> 'error' ->> 'http_code',
  '403', 'an anonymous sign-up is refused');
select is(app_private.before_user_created('{}'::jsonb) -> 'error' ->> 'http_code', '403',
  'an event without a user is refused');

-- Seed -----------------------------------------------------------------------------------------------------------
select is((select count(*)::int from auth.users), 5, 'the seed creates five testers');
select is((select count(*)::int from auth.users where email !~ '^[a-z.]+@example\.test$'), 0,
  'every seeded address is at example.test');
select is((select count(*)::int from auth.users u
            where u.email_confirmed_at is null or coalesce(u.encrypted_password, '') <> ''),
  0, 'every seeded tester has a confirmed email and no password');
select is((select count(*)::int from auth.users u
            where not exists (select 1 from app_ops.tester_allowlist a
                               where a.email_hmac = app_private.email_hmac(u.email))),
  0, 'every seeded tester is on the allow-list');

-- Without the Vault key every address is refused (fail closed); rolled back with the rest of the file.
delete from vault.secrets where name = 'jovra_email_hmac_key';
select is(app_private.email_hmac('owner.tester@example.test'), null, 'with no HMAC key email_hmac returns null');
select is(app_private.before_user_created('{"user": {"email": "owner.tester@example.test"}}'::jsonb) -> 'error'
  ->> 'message', 'signup_not_allowed', 'with no HMAC key even an allow-listed tester is refused');

select * from finish();
rollback;
