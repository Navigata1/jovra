# Storage providers sit behind one adapter interface with truthful capability states

Status: accepted (2026-10-07); extends ADR-0008, which stands for Google Drive.

Jon wants "icloud, google drive, box, dropbox, etc" as optional integrations added afterwards (Studio addendum,
OBSERVED). Every user-owned storage service is a **storage provider** behind one `StorageProvider` interface:

- **Capability status:** one of the contract's values (`jovra.storage-providers/1`): `active`, `choose-folder`,
  `not-connected`, `token-expired` (shown as "Needs reconnect"), `disconnected`, `planned` or `unavailable` (with a
  reason; Google Drive's core "Awaiting Google Drive setup" is `unavailable` with the setup reason and keeps the core
  copy). The first draft of this ADR used other words (`available`, `awaiting setup`, `unsupported`); the contract
  names win (amended 2026-10-07, review round 3).
- **Account and folder selection.**
- **Resumable read and write**, with state persisted per ADR-0002.
- **Quota.**
- **Expired-token and disconnect handling.**
- **Sidecar versioning.**
- **Integrity checks.** A file counts as a verified backup only when the provider-reported size and checksum match the
  local file, per ADR-0008's rule.

A provider plays one or more of three roles: archive, import and export. It never acts as the database, the analysis
engine or the cloud render store (the contract pins `processing: false`), and JOVRA's servers never store or follow a
provider URL or token: provider connections are status rows only, and tokens stay on the device. Each role is a
separate choice, and none of them is consent for cloud processing (ADR-0019).

**Order of work:**
1. **Files / iCloud Drive** through the system document picker: folder export and import. This is not CloudKit sync,
   and not iCloud on Android.
2. **Google Drive**, as already built under ADR-0008: plain REST with the `drive.file` scope.
3. **Box and Dropbox**, each with its own verified OAuth integration and minimal scopes, later.

Import is allowed from any provider the Files app can reach, without claiming a dedicated integration exists.

**Credentials.** Provider credentials are per provider, live in the Keychain, and are separate from the JOVRA
identity (ADR-0022). Signing out of JOVRA does not disconnect an archive, and disconnecting an archive does not touch
the JOVRA account. OAuth client IDs come from configuration (CLAUDE.md rule 5).

A provider logo or row in Settings only means a wired integration when its status is `active`. Otherwise it shows
"Planned" or "Awaiting setup".

## Considered Options

- **One SDK per provider wired directly into features.** Rejected. It spreads auth and resume logic around the app,
  is hard to fake in tests, and repeats the dependency weight ADR-0008 avoided.
- **Treating R2 or the JOVRA cloud as the user's archive.** Rejected. Footage the user owns belongs in storage the
  user owns, and cloud staging expires (ADR-0018).
- **An aggregator service.** Rejected. It adds a third party holding tokens for every provider.

## Consequences

Each new provider ships with a local fake (a `URLProtocol` stub, as for Drive) and a capability state. Its real
behaviour stays UNVERIFIED until Jon registers the OAuth app. ADR-0008's statement that Google Drive is the only
archive provider in v1 core remains true until another provider passes its gate.

Sources: `design-reference/studio/brief/backend-media-design.md` (Storage providers); ADR-0008 and its Drive sources.
Provider documentation to verify at each provider's gate (UNVERIFIED, not fetched for this ADR):
https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller ;
https://developer.box.com/guides/authentication/oauth2/ ; https://developers.dropbox.com/oauth-guide .

Note (2026-10-07): YouTube is not a storage provider. "Prepare for YouTube" is a local export, and the backend's
`provider_kind` enum has no `youtube` value; any YouTube connection needs its own ADR.
