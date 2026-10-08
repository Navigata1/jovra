-- S75 / B-02: server-enforced tester sign-up (ADR-0022; docs/backend/security-model.md §13.2, §13.3).
--
-- The second lock behind `enable_signup = false`: Supabase Auth calls app_private.before_user_created before it
-- creates any user (OTP sign-up, admin API, anonymous, phone). The hook allows an email only when its HMAC is in
-- app_ops.tester_allowlist; everything else, including a missing email or a missing HMAC key, is refused.
--
-- B-03 (migration 1) adds the rest of these schemas; it must use `create schema if not exists` and keep the
-- grants below.

create schema if not exists app_private;
create schema if not exists app_ops;

revoke all on schema app_private from public, anon, authenticated, service_role;
revoke all on schema app_ops from public, anon, authenticated, service_role;
-- Supabase Auth runs hooks as supabase_auth_admin; it needs to reach the hook and nothing else.
grant usage on schema app_private to supabase_auth_admin;

-- Only the HMAC of an allow-listed address is stored; the address itself never is (security-model §13.2).
create table app_ops.tester_allowlist (
  email_hmac bytea primary key check (octet_length(email_hmac) = 32),
  added_at timestamptz not null default now()
);
alter table app_ops.tester_allowlist enable row level security;
revoke all on table app_ops.tester_allowlist from public, anon, authenticated, service_role;

-- HMAC-SHA256 of the trimmed, lower-cased email under the Vault key `jovra_email_hmac_key` (hex). With no key the
-- result is null, which matches nothing: the hook then refuses every address (fail closed).
create function app_private.email_hmac(p_email text) returns bytea
language sql stable security definer set search_path = '' as $$
  select extensions.hmac(convert_to(lower(btrim(p_email)), 'UTF8'),
                         (select decode(s.decrypted_secret, 'hex') from vault.decrypted_secrets s
                           where s.name = 'jovra_email_hmac_key'),
                         'sha256')
$$;
revoke execute on function app_private.email_hmac(text) from public, anon, authenticated, service_role;

create function app_private.before_user_created(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hmac bytea := app_private.email_hmac(event -> 'user' ->> 'email');
begin
  if v_hmac is null
     or not exists (select 1 from app_ops.tester_allowlist a where a.email_hmac = v_hmac) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'signup_not_allowed'));
  end if;
  return '{}'::jsonb;
end
$$;
revoke execute on function app_private.before_user_created(jsonb) from public, anon, authenticated, service_role;
grant execute on function app_private.before_user_created(jsonb) to supabase_auth_admin;
