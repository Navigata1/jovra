-- Local seed (S75 / B-02): fictional testers for the local stack only. `supabase db reset` runs this after the
-- migrations. Every address is at example.test, a reserved name that can never receive mail; local auth email
-- lands in Mailpit. There are no passwords: testers sign in with an email one-time code (ADR-0022).
--
-- The hosted isolated-test project is never seeded from this file. There, the operator script reads the untracked
-- allow-list (format: seed/testers.allowlist.example) at gate G1.

-- 1. A local-only HMAC key, random on every reset. The hosted key is set by the operator in Vault, never committed.
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'jovra_email_hmac_key',
                           'Local stack only: key for app_private.email_hmac');

-- 2. The allow-list. pending.tester is allow-listed but not created, so the operator path (admin create with
--    sign-ups off) can be exercised by scripts/otp_smoke.py.
insert into app_ops.tester_allowlist (email_hmac)
select app_private.email_hmac(e)
from unnest(array[
  'owner.tester@example.test',
  'coach.tester@example.test',
  'viewer.tester@example.test',
  'camera.tester@example.test',
  'unrelated.tester@example.test',
  'pending.tester@example.test'
]) as e;

-- 3. The pre-created testers (what the operator script does through the admin API on the hosted test project).
--    One per role in the security-model §6 matrix. Token columns are '' rather than null, as Supabase Auth expects.
with testers(id, email) as (
  values
    ('00000000-0000-4000-8000-00000000a001'::uuid, 'owner.tester@example.test'),
    ('00000000-0000-4000-8000-00000000a002'::uuid, 'coach.tester@example.test'),
    ('00000000-0000-4000-8000-00000000a003'::uuid, 'viewer.tester@example.test'),
    ('00000000-0000-4000-8000-00000000a004'::uuid, 'camera.tester@example.test'),
    ('00000000-0000-4000-8000-00000000a005'::uuid, 'unrelated.tester@example.test')
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change_token_current, email_change,
  phone_change, phone_change_token, reauthentication_token
)
select '00000000-0000-0000-0000-000000000000'::uuid, t.id, 'authenticated', 'authenticated', t.email, '', now(),
       '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
       '', '', '', '', '', '', '', ''
from testers t;

insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id::text, u.id,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', null, now(), now()
from auth.users u
where u.email like '%@example.test';
