# JOVRA backend

The Studio cloud backend (ADR-0014, ADR-0018, ADR-0022), built as code and tested locally. Nothing here is
provisioned: there is no hosted project, URL, key or account in this tree, and none may be added by an agent
(ADR-0014, activation gate 1). The app never needs this backend; recording, scoring and local films work offline.

Design: `docs/backend/architecture.md` (layout §1.2, local test strategy §12, gates §13, tickets §15) and
`docs/backend/security-model.md`.

## Subprojects

| Folder | What | Test command | CI workflow | Status |
|---|---|---|---|---|
| `supabase/` | Local Supabase project: config, migrations, seed testers, pgTAP suite | `supabase test db` (see below) | `.github/workflows/backend-db.yml` | Scaffold (S75 / B-02) |
| `gateway/` | Cloudflare signing gateway Worker | — | — | Not started (B-07) |
| `render/` | Render-host image | — | — | Not started (B-13) |
| `contracts/` | Gateway and queue JSON Schemas | — | — | Not started (B-01) |

## `supabase/` (S75)

What it holds:

- `config.toml`: the local stack. Sign-ups off (`enable_signup = false`), anonymous sign-in off, a mandatory
  `before_user_created` allow-list hook, six-digit email codes delivered to Mailpit, an ES256 signing key read from
  `signing_keys.json` (generated locally, gitignored). Storage, Realtime, Studio, Edge Runtime and Analytics are off:
  media lives in private R2 behind the gateway (ADR-0018).
- `migrations/20261008000000_tester_signup_lock.sql`: `app_ops.tester_allowlist` (HMACs only, never addresses),
  `app_private.email_hmac` (key in Vault) and the hook `app_private.before_user_created`, which refuses every email
  that is not allow-listed, every sign-up without an email, and everything when the key is missing.
- `seed/00_testers.sql`: a random local HMAC key and five fictional testers at `example.test` (owner, coach, viewer,
  camera, unrelated), plus `pending.tester@example.test`, allow-listed but not created. No passwords.
- `seed/testers.allowlist.example`: the format of the untracked allow-list the operator keeps for the hosted test
  project (`seed/testers.allowlist`, gitignored). One address per line, `#` comments; addresses are trimmed and
  lower-cased before hashing.
- `tests/database/`: the pgTAP suite. `000_harness.test.sql` installs basejump-style helpers in a `tests` schema
  (`create_supabase_user`, `get_supabase_uid`, `authenticate_as`, `authenticate_as_service_role`,
  `clear_authentication`, `rls_enabled`); later files run inside `begin; ... rollback;`.
- `scripts/`: `gen-signing-key.sh`, `otp_smoke.py` (sign-in through Auth and Mailpit, refusals) and
  `check-hosted-identifiers.sh` (no `*.supabase.co`, API key, JWT or non-`example.test` email in the tree).

### Run it locally

Needs Docker and the Supabase CLI (2.100.1 in CI). From `backend/`:

```sh
supabase/scripts/gen-signing-key.sh          # once per checkout; the CLI will not load config.toml without it
supabase start
supabase db reset                            # migrations + seed from scratch
supabase db advisors --local --type security --fail-on warn
supabase test db
supabase status -o env > /tmp/jovra-status.env && python3 supabase/scripts/otp_smoke.py /tmp/jovra-status.env
supabase/scripts/check-hosted-identifiers.sh
supabase stop --no-backup
```

To sign in by hand, request a code for a seeded tester (for example `owner.tester@example.test`) and read it in
Mailpit at http://127.0.0.1:54324. Advisors run before `supabase test db` because the harness leaves its `tests`
helpers in the local database; `supabase db reset` removes them.

### What CI proves

`backend-db` runs on every pull request touching `backend/supabase/**` or the workflow: the identifier check, then
`supabase start`, `supabase db reset`, the security advisors (fail on warn), `supabase test db` and the OTP smoke
test. A failing pgTAP assertion turns it red.

### Two facts found while building this (OBSERVED)

- In the CLI, `[auth.email] enable_signup` switches the email provider on or off (`GOTRUE_EXTERNAL_EMAIL_ENABLED`);
  setting it to false disables email codes for everyone. Sign-ups are closed by `[auth] enable_signup = false`.
- Supabase Auth runs `before_user_created` on sign-up, OTP, anonymous, OAuth, SAML, Web3 and invite, but not on
  `POST /auth/v1/admin/users` (no call in `internal/api/admin.go` of supabase/auth). The operator's admin creation
  is therefore not checked by the hook; it needs the secret key, which never leaves the operator. The smoke test
  proves the hook alone through the invite path, which also ignores the sign-up switch.

### Not covered yet

- Everything hosted is UNVERIFIED until gate G1: the hook's availability, config keys and payload shape on the
  chosen plan, the operator script that creates testers from the untracked allow-list, and where the hosted HMAC key
  lives (security-model §13.2–13.3).
- The rest of migration 1 (B-03) builds on the `app_private` and `app_ops` schemas created here; it must use
  `create schema if not exists` and keep their grants.
- `gateway/` will hold its own `.dev.vars` (already gitignored).
