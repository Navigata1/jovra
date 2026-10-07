# Google Drive archive over plain OAuth and REST, `drive.file` only

The Drive archive uses **no Google SDK**. Sign-in is OAuth 2.0 with PKCE (S256) for an iOS client type through
`ASWebAuthenticationSession`, redirecting to the reversed-client-ID scheme, with no client secret. The only scope is
`drive.file`, which reaches files JOVRA created or the user picked and nothing else. The client ID comes from an
xcconfig, never from source; tokens live in the Keychain. Uploads, status queries, restore and revoke are a small
hand-written Drive v3 REST client whose resumable state machine is persisted per ADR-0002, so an archive job resumes
from the provider's confirmed offset after the app is killed. A file is a **verified backup**, and only then shown as
"Backed up" or allowed to leave the phone, when the provider's `size` and `md5Checksum` equal the local file's (and
`sha256Checksum` too when Drive returns it).

## Considered Options

- GoogleSignIn-iOS 10 with `GTMSessionUploadFetcher` (the research recommendation): pulls in AppAuth, GTMAppAuth,
  gtm-session-fetcher and App Check, speaks an upload dialect the Drive guide does not document, and is hard to fake in
  tests. The flow it saves us is short and fully documented.
- Broader scopes (`drive`, `drive.readonly`, `drive.metadata*`): restricted, need an annual security assessment, and
  read far more than an archive needs. `drive.appdata`: hidden from the user and deleted with the app, which defeats
  ownership.

## Consequences

The whole flow (auth, resumable upload with resume after kill, size and MD5 verification, JSON sidecar, restore,
disconnect and revoke) is tested against a local fake Drive (a `URLProtocol` stub). Until Jon creates the Google Cloud
OAuth client and publishes the project "In production" (Testing status caps at 100 listed users whose tokens expire
after 7 days), the UI shows "Awaiting setup", never a fake "Connected", and real-Drive behaviour is **unverified**.
Revoking from the app removes every scope the Cloud project holds for that account, including on a future Android
client. Import through the Google Picker (P1-08) is out of v1; Drive files can still come in through the Files app.
