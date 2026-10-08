# Identity: Sign in with Apple via Supabase; the demo profile is never a credential; testers come from config

Status: accepted (2026-10-07); amended 2026-10-07 after review round 2 (server-enforced tester sign-up,
re-authentication for deletion, deletion of a coach's excerpts in other projects).

JOVRA identity is optional and is needed only for opt-in cloud features (ADR-0014). There are three kinds, and they
never blur:

- **Demo profile.** "Use demo profile" starts an in-process adapter with fictional Sample data. It has no network,
  token, upload or charge, and it is visibly labelled. It is not authentication, so no gateway or Supabase project
  will ever accept it. There is no hardcoded password, no "demo token" and no UI role flag that any API trusts.
- **Tester identity.** A real account in the **isolated test** environment only. Testers sign in with email one-time
  codes. Sign-ups are **disabled on the test Auth project** (`enable_signup = false`), testers are pre-created by an
  operator script from an untracked allow-list, and a `before_user_created` hook that rejects any email not on the
  allow-list is **mandatory** as a second lock. `shouldCreateUser: false` is only a client convenience: it is a request
  parameter that anyone holding the test URL and publishable key can change, so it is never the control. In test the
  gateway also requires the operator-set tester flag before accepting a quote. No credential is ever
  committed, and because the OTP flow has no passwords, there are none to commit. Fixture logins are compiled out of
  release builds.
- **Live account.** In the live environment, once activated. On iOS it is created with **Sign in with Apple** through
  Supabase's native flow (`signInWithIdToken` with a raw nonce whose SHA-256 goes to Apple), or with an email code.
  The app saves the user's name on first sign-in, because Apple sends it only once. Anonymous sign-in stays **off**
  in live and is optional in test. Android adds email codes and, after its own review, a native Google option.

**Camera guests** never need an account. They get a scoped upload capability (ADR-0018).

**Rules.** Tokens are ES256, verified against JWKS, with the issuer pinned per environment, so a test token fails in
live. The UI always shows which mode it is in: demo, test or live. Signing out keeps offline access to local projects.

**Account deletion** is in-app (App Review 5.1.1(v)). It needs a fresh authentication (a sign-in within the last
10 minutes: the token's Auth session must have been created by that sign-in, checked on the server; a silent refresh
keeps the old session, and a refreshed token's `iat` is never accepted; `security-model.md` §2.2, §13.4). It
deletes the Supabase user, every cloud row the user owns (their projects, lessons and everything under them) and every
R2 object derived from them, including the clip excerpts of their lessons that live under another owner's project
prefix (enumerated through their lessons' clips, not by project prefix), but never local originals unless the user
chooses that separately. **Amendment (2026-10-07):** rows a user authored inside *another owner's* project as a
coach (observations, story plans and plan versions, sync or calibration reviews) belong to that project, not to the
author. They are kept with the project and their actor columns become null ("a former collaborator"); their text is
not scrubbed, because the project owner relies on it and the author wrote it into a project they did not own. Every
actor column is `on delete set null` so the deletion never stalls on these rows (`docs/backend/architecture.md` §4.1,
test T-GW-20b). The author can ask the project owner to delete specific notes before deleting the account. It also **revokes the user's Apple
tokens** through the Sign in with Apple REST API. That needs a server-held Apple key, even though native sign-in
does not, and it is an activation gate for the live environment. Whether Supabase revokes Apple tokens itself is
UNVERIFIED.

Under IDC Rule 07, auth emails are sent from the venture's role address (`hello@islanddevcrew.com` today), never from
a personal address.

## Considered Options

- **Shared test password or demo credentials in the repo.** Rejected under CLAUDE.md rule 5, and because such a
  login would be one config mistake away from production.
- **Anonymous accounts as the default "try it" path.** Rejected. They need a CAPTCHA, count toward MAU, are never
  cleaned up automatically, and give live API access to unauthenticated people. The demo profile serves the same
  purpose offline.
- **A custom identity service.** Rejected. Supabase Auth already issues the JWTs that RLS policies read.

## Consequences

Sign in with Apple end-to-end can be proven only with a real device and a real Apple account. Locally, nonce handling,
name persistence and token rejection are what can be tested. The core app's existing local-only "Continue with
Apple" does not change.

Sources: https://supabase.com/docs/guides/auth/social-login/auth-apple ;
https://supabase.com/docs/guides/auth/auth-email-passwordless ;
https://supabase.com/docs/guides/auth/auth-anonymous ; https://supabase.com/docs/guides/auth/signing-keys ;
https://developer.apple.com/app-store/review/guidelines/ ;
https://developer.apple.com/support/offering-account-deletion-in-your-app/ ;
`docs/research/studio/backend-architecture.md` §3.
