# JOVRA: Google Drive archive and Android port, technical feasibility

Research date: 2026-10-07. Scope: assignment (A) Google Drive as an optional, user-owned archive for large videos on iOS and Android, and (B) the Android stack for the port. Inputs read first: `docs/handoff/JON-ORIGINAL-PROMPT.md`, `design-reference/brief/research.md`, `product-brief.md` and `screens.json` (screens 4, 7, 19 and 20 touch storage, import and permissions).

Method: I fetched official Google, Android and Apple documentation live on 2026-10-07 and recorded each page's "Last updated" stamp where it had one. I also read source code from Google-maintained client libraries on GitHub. Nothing here was run on a device. No Drive project, OAuth client or Android build exists yet.

Labels: **[OBSERVED]** means I saw it in the cited source. **[INFERRED]** is my reasoning from observed facts. **[UNVERIFIED]** means plausible but not confirmed by a primary source, or confirmed only by a secondary one. Source tags `[S#]` resolve in the Sources section at the end.

---

## 0. Decision summary

1. **Use the single scope `https://www.googleapis.com/auth/drive.file`.** Google classifies it as non-sensitive and recommended [S1]. Apps that request only non-sensitive scopes get no "unverified app" screen and no 100-user cap [S5][S6]. The app does still need brand verification before its name and logo show on the consent screen [S9]. Do not request `drive`, `drive.readonly` or `drive.metadata*`. Those are restricted [S1], and restricted scopes require an annual third-party security assessment [S8]. **[OBSERVED + INFERRED]**
2. **Use Drive's mobile Google Picker for "Import from Google Drive" (screen 7).** As of 2026, a mobile app can open the Google Picker during OAuth. On iOS you add `trigger_onepick=true` to the authorization URL. On Android you pass `PICKER_OAUTH_TRIGGER` to `AuthorizationRequest`. Either way the app gets `drive.file` access to the files the user picks [S11][S12]. This answers the open item in the prior research to "validate the chosen picker/native OAuth implementation". The system document pickers (iOS Files app, Android Storage Access Framework) can also import from Drive with no Google scope at all [S35][S36]. **[OBSERVED]**
3. **iOS auth: use the GoogleSignIn SDK (10.0.0, 2026-09-04, iOS 15+) for connect, refresh and disconnect.** Use AppAuth directly only for the Picker flow. Plain OAuth with PKCE, an iOS client type, a reversed-client-ID redirect, `ASWebAuthenticationSession` and no client secret does work [S3]. The SDK adds App Check (Apple App Attest), Keychain persistence and revocation [S14][S18]. It has no hook for arbitrary authorization parameters, so it cannot trigger the Picker [S14]. **[OBSERVED + INFERRED]**
4. **Android auth: use `AuthorizationClient` from Google Identity Services (`play-services-auth` 22.0.0).** Credential Manager is for sign-in, not Drive scopes [S13]. AppAuth is not a good fit, because Google no longer supports custom-URI-scheme redirects for Android clients [S3]. The device never receives a refresh token. The app calls `authorize()` again whenever it needs a fresh access token [S13]. **[OBSERVED + INFERRED]**
5. **The upload engine follows the documented resumable protocol.** Each session URI lasts one week. Chunks must be multiples of 256 KiB, and Google prefers a single PUT when possible. The client resumes by sending a status query with `Content-Range: bytes */N`. It must persist the session URI and the pre-generated file ID before the first byte goes out [S2][S28]. Verify with `size`, `md5Checksum` and `sha256Checksum` before showing "Backed up" [S23]. **[OBSERVED]**
6. **iOS background uploads: prefer Google's `GTMSessionUploadFetcher` (gtm-session-fetcher 5.3.1, used by GoogleAPIClientForREST 5.4.0) with `useBackgroundSession`.** It speaks Google's `X-Goog-Upload-*` resumable dialect and writes temporary chunk files that a background `URLSession` can upload. That sidesteps two problems with a hand-written client: iOS background sessions only upload from whole files [S37], and a 308 "Resume Incomplete" response inside a background session behaves in an untested way [S41][S42]. **[OBSERVED + UNVERIFIED on device]**
7. **The Android upload worker should not be a bare WorkManager plus `dataSync` worker, which the assignment assumed.** For a transfer the user starts, Google now recommends a user-initiated data transfer job (UIDT, Android 14+) [S44][S45]. Since Android 15, `dataSync` foreground services are capped at 6 hours per 24 hours [S48]. Since Android 16, long-running workers can use up the app's job quota [S46][S49]. The design that holds up: UIDT for "Back up now", constrained WorkManager for automatic background backup, and chunk-level checkpoints so any interrupted run resumes. **[OBSERVED + INFERRED]**
8. **Drive quotas changed on 2026-05-01 for new Cloud projects.** Limits are now 1,000,000 quota units per minute per project and 325,000 per minute per user. Each project gets 1 TB per day of egress before charges apply, and a daily billing threshold of 400,000,000 units. Google says billing details will follow later in 2026 with at least 90 days' notice [S20][S21]. Uploads are cheap. Restores (downloads) are what count against project egress, so restore through the Drive app's Files or SAF provider where possible. **[OBSERVED + INFERRED]**
9. **Storage reality.** A free Google account has 15 GB, shared across Gmail, Drive and Photos [S34]. One hour at 8 Mbps is about 3.6 GB, and one hour at 20 Mbps is about 9 GB. Screen 4's "3.2 GB for 54 min" implies roughly 7.9 Mbps. A free account therefore holds only 2 to 4 matches. The product needs a quota preflight (`about.get` with `storageQuota` [S29]), clean handling of `storageQuotaExceeded` [S22], and an optional smaller "archive copy" or clips-only backup. **[OBSERVED + INFERRED]**
10. **Android SDK levels: the assignment's "target 35/36" is out of date.** Since 2026-08-31, Google Play requires new apps and updates to target API 36, with an extension available to 2026-11-01 [S52]. Android 17 (API 37) has shipped [S51]. Recommendation: `compileSdk 37`, `targetSdk 36` (move to 37 after testing), `minSdk 29`. The library floor is 24, set by WorkManager 2.12 [S67]. **[OBSERVED + INFERRED]**
11. **Android capture: CameraX 1.6.2 has first-class 60 fps support.** Use `SessionConfig.Builder.setFrameRateRange`, `CameraInfo.getSupportedFrameRateRanges(SessionConfig)` and `GroupableFeature.FPS_60`. High-speed 120 and 240 fps go through `HighSpeedVideoSessionConfig`. Camera2 interop is no longer needed for 60 fps [S54][S56]. Since 1.6, VideoCapture uses the Media3 muxer by default, which Google says protects the file if the app crashes mid-recording [S54]. That directly supports the "Recording is safe" promise. **[OBSERVED]**
12. **ML Kit Pose Detection is a poor fit for match footage.** It is still in beta, tracks one person only, and needs the subject's face visible [S61]. A camera behind the baseline sees players' backs at a distance. Limit ML Kit or MediaPipe pose to close, side-on Stroke Lab clips. MediaPipe Pose Landmarker supports `num_poses > 1` [S62]. Every pose claim stays behind a per-platform benchmark gate, as the prior research said. **[OBSERVED + INFERRED]**
13. **The emulator can feed recorded tennis video as camera input** with `-camera-back videofile:<file>` [S70]. That lets the CameraX → analysis pipeline run in CI. It does not prove real sensor frame rates, thermal behaviour or encoder throughput. **[OBSERVED + INFERRED]**

---

## 1. Relationship to the prior research (`design-reference/brief/research.md`)

- **Confirmed:** Google documents resumable uploads for large files and unreliable networks [S2]. `drive.file` is the narrow, recommended scope [S1]. Local-first storage, with Drive as an optional archive and not the database or analysis engine, matches Google's own guidance to keep Drive features optional [S13] and fits the founder's request to use Google Drive as cloud storage (JON-ORIGINAL-PROMPT). **[OBSERVED]**
- **Gap closed:** the prior research said to "validate the chosen picker/native OAuth implementation". The desktop and mobile Google Picker settles it: it permits only `drive.file`, which cannot be combined with any other scope in that request, and returns `picked_file_ids` [S11]. **[OBSERVED]**
- **New since the prior research:** the 2026-05-01 quota model and coming billing [S20][S21]. The API 36 Play target deadline [S52]. Android 15/16 limits on `dataSync` and jobs [S48][S49]. CameraX 1.5/1.6 frame-rate and session APIs [S54]. Media3 1.8+ scrubbing mode and the 1.10+ `FrameExtractor` [S58]. ML Kit's single-person, face-visible pose limits [S61]. The emulator's `videofile:` camera mode [S70]. **[OBSERVED]**
- **Not covered here:** iOS capture with AVFoundation. That belongs to a separate assignment.

---

## A. Google Drive as an optional user-owned archive

### A1. Scope choice and classification

| Scope | Classification [S1] | What it grants | JOVRA use |
|---|---|---|---|
| `drive.file` | Non-sensitive, recommended | Files the app creates; files the user opens with the app; files the user shares with the app through the Google Picker or the app's file picker [S1] | **Yes, the only scope** |
| `drive.appdata` (also `drive.appfolder`) | Non-sensitive | A hidden per-app folder. The user can't see it. It is deleted when the user removes the app from My Drive. Its files can't be shared, moved between spaces or trashed [S24] | **No.** Videos the user owns must be visible. Adding it would also need a second scope, and the Picker flow forbids combining `drive.file` with others [S11] |
| `drive` | Restricted | All files | No |
| `drive.readonly`, `drive.metadata`, `drive.metadata.readonly`, `drive.activity*`, `drive.meet.readonly`, `drive.scripts` | Restricted | Broad read or metadata access | No |
| `drive.apps.readonly` | Sensitive | Lists authorized apps | No |

- Restricted scopes require an annual security assessment by a Google-empanelled assessor. Sensitive and restricted scopes also require a demo video and a written justification for each scope [S8]. **[OBSERVED]**
- `about.get` (quota preflight, "Connected as" email), `files.generateIds` and folder or file creation all accept `drive.file` [S29][S28]. **[OBSERVED]**
- **Grants are per Cloud project, not per OAuth client (INFERRED).** The Picker web guide says to set the Drive App ID to the Cloud project number so the app can reach the user's files [S32]. That points to the iOS and Android OAuth clients in one Cloud project sharing `drive.file` access to the same archive. A forum thread reports that a different client could not see files made by an earlier one [S73]. It doesn't say whether both clients lived in the same project. **Add an acceptance test: create a file from iOS, then list it from Android.** One consequence is likely: separate dev and prod Cloud projects (which Google's policy asks for [S7]) won't see each other's archives. **[INFERRED + UNVERIFIED]**

### A2. Consent screen, verification and testing mode

- **"Unverified app" applies only to sensitive or restricted scopes.** Google defines an unverified app as one that requests a sensitive or restricted scope without completing verification. The lifetime cap of 100 new users applies to apps that show that screen [S6][S5]. **[OBSERVED]**
- **Brand verification.** All apps must show accurate identity. The homepage must sit on a domain you own and have verified. The privacy policy must be on the same domain, linked from the homepage, and match the URL on the consent screen. Authorized domains must be verified in Search Console by a project owner or editor [S8][S9]. App name and logo appear on the consent screen only after verification. The "Verify Branding" check usually finishes in a few minutes. Logo: square, 120×120 px recommended, 1 MB or smaller, JPG, PNG or BMP. Changing the logo of an External app in production triggers verification again. The user support email must be the signed-in Google account or a Google Group that account manages [S9]. **[OBSERVED]**
- **Testing status.** External apps in Testing allow at most 100 listed test users, show a warning screen, and test users' authorizations, refresh token included, **expire 7 days after consent**. The only exception is apps that request nothing beyond name, email and profile [S5][S4]. **[OBSERVED]**
- **Practical consequence:** JOVRA requests only `drive.file`. It can move to "In production" as soon as brand verification passes. That removes the 7-day expiry and the 100-user limit, with no scope review needed. Use Testing only in a separate dev project [S7]. **[INFERRED]**
- **Policy still applies without review.** All apps must comply with the Google API Services User Data Policy, including Limited Use [S7][S8]. Do not send Drive-derived data to AI services or use it for model training without explicit, prominent consent. That matches the build prompt's rule against sending raw video to AI services by default. **[OBSERVED + INFERRED]**
- **IDC domain doctrine (local rule, INFERRED application):** JOVRA owns no brand domain, so it uses the IDC lanes. Put the consent-screen homepage and privacy policy on a **path** of `islanddevcrew.com`, for example `/jovra`, not a subdomain. The doctrine lists `sc-domain:islanddevcrew.com` as a verified Search Console property. Use `hello@islanddevcrew.com` as the support address. A Workspace group meets Google's "Google Group you manage" option [S9]. Under the doctrine's rule 1, don't submit until those URLs resolve. [S75]
- **App Store 4.8:** that guideline applies to third-party login used to set up or sign in to the user's *primary account* [S72]. Connecting Google Drive is not the primary account login (JOVRA uses Sign in with Apple on screen 20). **[OBSERVED + INFERRED]**

### A3. iOS OAuth (native app)

**[OBSERVED] Protocol facts [S3] (page updated 2026-09-14):**
- Client type **iOS**: bundle ID, optional App Store ID, optional Team ID. The Team ID becomes required once App Check is enabled. `client_secret` doesn't apply to iOS, Android or Chrome clients.
- Authorization endpoint `https://accounts.google.com/o/oauth2/v2/auth`. Token and refresh endpoint `https://oauth2.googleapis.com/token`. Parameters: `response_type=code`, `code_challenge`, `code_challenge_method=S256` (`plain` is allowed but S256 is recommended). The code verifier must be 43 to 128 characters. DPoP is optional but recommended.
- Redirect URI: a custom scheme, either `com.example.app:/path` on a domain you control or `com.googleusercontent.apps.<id>:/oauth2redirect`. The path is optional and starts with a single slash. Loopback redirects are **deprecated** for mobile. Out-of-band copy and paste is no longer supported.
- Embedded web views (`WKWebView`) fail with `disallowed_useragent`. Google points iOS developers to the Google Sign-In SDK or AppAuth.
- **Doc conflict.** In the redirect table, Google says custom URI schemes are no longer supported "on Android and Chrome apps". The custom-scheme section says, without qualification, that custom URI schemes are no longer supported because of impersonation risk. Google's own iOS SDK setup guide, updated 2026-03-22, still has you register the reversed client ID as `CFBundleURLSchemes` [S15]. So the iOS custom scheme still works today. Using Google's SDK protects JOVRA if that changes. Turn on **App Check** to reduce impersonation risk. **[OBSERVED conflict; INFERRED resolution]**
- Incremental authorization isn't supported for installed apps under the raw protocol. Granular consent means users can untick scopes, so always read the granted `scope` list.
- Revocation: `POST https://oauth2.googleapis.com/revoke?token={token}` with form encoding. It returns 200 on success and 400 on error. **Revoking removes every scope granted to the project across all its clients.** A "Disconnect" on iPhone therefore also invalidates the Android grant for the same user. **[OBSERVED + INFERRED consequence]**

**[OBSERVED] Token lifetimes [S3][S4]:** Google's sample access token response shows `expires_in: 3920`, about an hour. Treat the value as opaque. Installed apps always receive a refresh token. A refresh token stops working when: the user revokes access; it goes unused for 6 months; the account passes 100 live refresh tokens per OAuth client (the oldest is invalidated without warning); time-based access expires; or an admin restricts the scope. Handle `invalid_grant` by asking the user to reconnect.

**[OBSERVED] GoogleSignIn-iOS [S14][S15][S16][S17][S18]:**
- **10.0.0, released 2026-09-04:** needed for Xcode 27. Requires AppAuth 3.0.0 and GTMAppAuth 6.0.0, which raise the minimum to **iOS 15**. Stay on 9.2.0 to support older iOS. 9.2.0 (2026-06-15) exposed the refresh token's expiration date and removes stale Keychain entries on a fresh install, so users reconnect after reinstalling.
- Setup: `GIDClientID` in Info.plist, the reversed client ID in `CFBundleURLTypes`, and `GIDSignIn.sharedInstance.handle(url)` in `onOpenURL`. Call `restorePreviousSignIn` at launch.
- API: `signIn(withPresenting:hint:additionalScopes:)` adds scopes *on top of* the basic profile scopes. `currentUser.addScopes(_:presenting:)`, `grantedScopes`, `refreshTokensIfNeeded`, `accessToken.tokenString`, `fetcherAuthorizer`, and `disconnect`, which revokes and signs out.
- The SDK depends on AppAuth-iOS. AppAuth's external user agent is `ASWebAuthenticationSession`. AppAuth 2.1.0 (2026-06-12) removed the Safari fallback when that session can't start, for example under Guided Access [S19].
- App Check: Apple App Attest validates OAuth requests from the client. Initialize with `GIDSignIn.sharedInstance.configure`. Use `configureDebugProvider(withAPIKey:)` in Simulator or CI builds, since App Attest doesn't work there. Watch the metrics before enforcing, because enforcement rejects every unverified request [S18].

**Is the SDK needed? [INFERRED]** No, AppAuth alone can run the documented flow. But the SDK gives App Check, Keychain storage, refresh and disconnect for very little code. `GIDSignIn` has **no way to add custom authorization parameters**: its public header exposes only hint, additional scopes, nonce and claims [S14]. It also always bundles the basic profile scopes. The mobile Picker needs `trigger_onepick=true` and `drive.file` on its own [S11]. **Recommendation:** use GoogleSignIn for "Connect Google Drive". For "Import from Google Drive (Picker)", build an `OIDAuthorizationRequest` with `scope = drive.file` and `additionalParameters = ["trigger_onepick":"true","prompt":"consent", "mimetypes":"video/mp4,video/quicktime", "allow_multiple":"true"]`. Exchange the code once, read `picked_file_ids`, download, then throw that token away. The per-file grant stays with the project.

### A4. Android authorization

**[OBSERVED] [S13] (developer.android.com/identity/authorization):**
- Credential Manager is for authentication. `AuthorizationClient` is for scopes such as Drive. Ask for Drive access when the user takes an action that needs it.
- Flow: `Identity.getAuthorizationClient(ctx).authorize(AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(DriveScopes.DRIVE_FILE))).build())`. If `result.hasResolution()`, launch `result.pendingIntent` with `StartIntentSenderForResult`. Otherwise the access token is ready. `getServerAuthCode()` and `requestOfflineAccess(serverClientId)` exist only for a backend that exchanges the code. **The device never holds a refresh token.**
- `revokeAccess(RevokeAccessRequest.builder().setAccount(account).setScopes(...))` revokes **all** scopes previously granted to the app, not just the ones listed, and clears cached tokens. `clearToken(ClearTokenRequest)` evicts an invalid cached token, for example after an `IllegalStateException` or a 401.
- The authorization response doesn't say which account was used. JOVRA can call `GET /drive/v3/about?fields=user(displayName,emailAddress)` (allowed with `drive.file` [S29]) to show "Connected as …".
- Cloud setup: an **Android** OAuth client per signing key (package name plus SHA-1). Use one for the debug keystore and one for the Play App Signing key. Play-registered apps can optionally verify app ownership. `play-services-auth` is at 22.0.0, the newest on Google Maven, last updated 2026-08-25.
- **Picker on Android [S11][S12]:** `AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(DRIVE_FILE))).setOptOutIncludingGrantedScopes(true).setPrompt(Prompt.CONSENT).addResourceParameter(ResourceParameter.PICKER_OAUTH_TRIGGER, "true")`. Optional parameters: `PICKER_ALLOW_MULTIPLE`, `PICKER_MIMETYPES`, `PICKER_FILE_IDS`, `PICKER_ALLOW_FOLDER_SELECTION`. Read `picked_file_ids` from `AuthorizationResult.getTokenResponseParams()`.

**[INFERRED] Background uploads:** a worker can call `authorize()` with the application context. If the user granted access earlier, it returns a token without UI. If it returns `hasResolution()`, the worker can't show UI. It should mark the item "Needs reconnect" and post a notification that deep-links into the app. Test this on a device, including after a revoke at myaccount.google.com.

**[OBSERVED + INFERRED] AppAuth-Android** (0.11.1, last commit 2026-03-22) recommends custom-scheme redirects [S74]. Google no longer supports custom schemes for Android OAuth clients [S3]. Getting AppAuth working with Google on Android would need a different client type and an HTTPS App Link or a client secret, both of which work against Google's guidance. Don't use it for Google on Android.

### A5. Importing from Google Drive (screen 7 "Google Drive" tile)

| Path | Scope and verification | API egress | Notes |
|---|---|---|---|
| **System picker.** iOS `UIDocumentPickerViewController`, with Google Drive in the Files app since 2017 [S35]. Android `ACTION_OPEN_DOCUMENT`, with Google Drive as a document provider [S36] | **None** | None (the Drive app downloads) | Needs the Drive app installed and signed in **[INFERRED]**. Copy into the app sandbox before analysis. The best default for importing. |
| **Google Picker (mobile)** [S11][S12] | `drive.file` only, consent prompt each time | Counts against the project when JOVRA downloads | Best when the Drive app isn't installed. Gives stable file IDs, so the files can be restored later. |
| **JOVRA's own archive** | `drive.file`, since the files were app-created | Counts | Find with an `appProperties` query (A10) |

### A6. Resumable upload protocol (Drive v3) [S2] (updated 2026-09-03)

**[OBSERVED]**
1. **Initiate.** `POST https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable` with headers `Authorization: Bearer …`, `Content-Type: application/json; charset=UTF-8`, `X-Upload-Content-Type: video/mp4` and `X-Upload-Content-Length: <bytes>`. The body is metadata: `name`, `mimeType`, `parents`, `appProperties`, and optionally a pre-generated `id`. The response is **200 OK**, a `Location` header holding the session URI (`…&upload_id=…`) and an empty body. For an existing file, use `PATCH`.
2. **Session lifetime.** One page says a session URI expires after one week. Another says sessions expire after one week of inactivity. Plan for one week from creation.
3. **Upload.** Google prefers one `PUT` of the whole file with `Content-Length`. If you chunk, each chunk must be a **multiple of 256 KiB (262,144 bytes)** except the last. Send `Content-Range: bytes start-end/total` and keep chunks as large as practical. Don't assume the server received every byte you sent.
4. **Query status.** Send an empty `PUT` with `Content-Range: bytes */<total>`, or `*/*` if the size is unknown. Responses:
   - **200/201** means done, and the body is the file resource.
   - **308 Resume Incomplete** comes with `Range: bytes=0-N`, so resume at N+1. If there is no `Range` header, nothing was stored.
   - **404** means the session expired. Start a new one.
5. **Errors.** On 5xx, resume or retry with exponential backoff. On a 403 rate limit (`rateLimitExceeded`, `userRateLimitExceeded`) or a 429, retry with backoff. On other 4xx during a resumable upload, start a new session. **[INFERRED]** Treat 403 `storageQuotaExceeded` as terminal for the item: stop and show the user, don't loop.
6. **Pre-generated IDs.** `GET /drive/v3/files/generateIds?count=N&space=drive&type=files` (allowed with `drive.file`) [S28]. A create that reuses an ID returns **409 Conflict** on retry, never a duplicate. This works for binary files and folders, but not for Google Docs editor types.
7. **Size limits.** Up to 5,120 GB per file via `files.create` [S30]. Google Workspace users may upload 750 GB per day [S20].

**[OBSERVED in Google samples and code; behaviour UNVERIFIED by test] Session URI needs no bearer token.** Google's JavaScript samples send the data `PUT`s to the session URI **without** an `Authorization` header [S2]. Google's iOS upload fetcher comments that the chunk upload URL needs no authentication header [S41]. If that holds, an access token expiring during a multi-hour upload doesn't break it. Only initiation and verification need a fresh token. Test this explicitly.

**[INFERRED] Resuming after the app is killed. Per-item state machine, persisted in SQLite/SwiftData on iOS and Room on Android before any network I/O:**
`queued → hashing → session_created(sessionUri, driveFileId, createdAt) → uploading(lastConfirmedOffset) → verifying → backed_up | failed(reason) | needs_reconnect | quota_blocked`.
On relaunch: if the session is less than 7 days old, send a status query and continue from `Range+1`. If it returns 404 or is too old, first `files.get(driveFileId)`. The upload may have finished before the app died. If the file exists and verifies, mark it done. Otherwise create a new session reusing the same pre-generated ID.

### A7. iOS background uploads

**[OBSERVED] Apple background session rules [S37]:** create `URLSessionConfiguration.background(withIdentifier:)`. `sessionSendsLaunchEvents` defaults to true. The transfer runs in a separate system process. If the system terminated the app, it relaunches it in the background and calls `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. Recreate the session with the same identifier, then call the stored handler from `urlSessionDidFinishEvents`. Limitations: a delegate is required; redirects are always followed; **only uploads from a file survive app exit** (uploads from data or a stream fail); a rate limiter delays tasks started while the app is in the background; tasks created in the background are treated as discretionary. Set `countOfBytesClientExpectsToSend` to help scheduling. For "Wi-Fi only", set `allowsExpensiveNetworkAccess = false`, `allowsConstrainedNetworkAccess = false` (Low Data Mode) and `waitsForConnectivity = true` [S40].

**Consequences for Drive [INFERRED]:**
- To resume from a byte offset, you need a **file holding exactly the remaining bytes**. A single-PUT design must rewrite gigabytes after an interruption. Chunk files are better: 64 to 256 MiB each, multiples of 256 KiB, written on demand and deleted after a 308 confirms them.
- **The 308 risk.** RFC 7538 uses 308 for "Permanent Redirect", Google uses it for "Resume Incomplete", and background sessions always follow redirects. A 308 with no `Location` header probably arrives as a normal response, but **I found no Apple documentation of this. Test it on a device.** **[UNVERIFIED]**
- **Google's iOS library avoids both problems.** `GTMSessionUploadFetcher` (gtm-session-fetcher v5.3.1, 2026-08-04) implements Google's resumable protocol with `X-Goog-Upload-Protocol: resumable` and the commands `start`, `upload, finalize`, `query` and `cancel`. Progress comes back in `X-Goog-Upload-Status` (active, final, cancelled) and `X-Goog-Upload-Size-Received`. It supports `useBackgroundSession`, makes temporary files from slices of the data, restores fetchers with `uploadFetchersForBackgroundSessions`, and supports `pauseFetching` and `resumeFetching` [S41]. GoogleAPIClientForREST v5.4.0 (2026-08-04) drives Drive uploads through it with `uploadType=resumable`, and `GTLRUploadParameters.useBackgroundSession` passes through [S42]. **[OBSERVED in source.]** This header dialect is **not described on the Drive upload guide** [S2]. It works only because Google's own client uses it. **[UNVERIFIED as a public contract]**
- **iOS 17 resumable uploads** (`cancel(byProducingResumeData:)`, `uploadTaskResumeData`) need a server that implements the IETF draft `draft-ietf-httpbis-resumable-upload-01` [S38]. Drive doesn't document support, so don't rely on them. **[INFERRED]**
- **iOS 26 `BGContinuedProcessingTask`** handles work the user starts, begins in the foreground, shows progress in a system Live Activity the user can cancel, may use the network, and must report progress or risk being killed when resources run short [S39]. Use it for "Export video + analysis" (screen 19) and possibly "Back up now" with visible progress. Keep background `URLSession` for long, unattended uploads. **[OBSERVED + INFERRED]**
- Don't upload while recording. Heat and bandwidth both compete with capture. Queue uploads until recording ends and the device's thermal state is nominal. **[INFERRED]**

### A8. Android background uploads: corrected recommendation

**[OBSERVED] Google's decision table [S44]:**
- **WorkManager** is for work under about 10 minutes that runs when the app isn't visible, with constraints such as unmetered network.
- **User-initiated data transfer job (UIDT)** is for transfers the user starts and needs progress for, such as uploading a photo.
- **Foreground service** is for short critical work. `mediaProcessing` covers encoding and decoding.

**[OBSERVED] UIDT [S45]:**
- Introduced in Android 14 (API 34). Declare `<uses-permission android:name="android.permission.RUN_USER_INITIATED_JOBS"/>` and a `JobService`.
- Build with `JobInfo.Builder(id, component).setUserInitiated(true).setRequiredNetwork(NetworkRequest…NET_CAPABILITY_NOT_METERED…).setEstimatedNetworkBytes(...)`.
- A notification is required. The job must be scheduled while the app is visible. It starts immediately and may run for a long time if the system allows.
- UIDT jobs are exempt from ordinary job quotas [S46]. WorkManager 2.12.0 (2026-09-23) has **no** UIDT API, so use `JobScheduler` directly. **[OBSERVED absence in release notes]** [S67]

**[OBSERVED] WorkManager long-running workers [S46][S47][S48][S49]:**
- Use `setForeground(ForegroundInfo(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC))`. Merge the manifest override `<service android:name="androidx.work.impl.foreground.SystemForegroundService" android:foregroundServiceType="dataSync" tools:node="merge"/>` and add the `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_DATA_SYNC` permissions. A type is mandatory when targeting 34+.
- Android 15: `dataSync` and `mediaProcessing` foreground services each get **6 hours per rolling 24 hours**. At the limit the system calls `Service.onTimeout(int,int)` and you must call `stopSelf()` within seconds, or the app crashes with `RemoteServiceException`. The timer resets when the user brings the app to the foreground. Apps targeting 15+ can't start `dataSync` from `BOOT_COMPLETED`.
- Android 16: jobs that run alongside a foreground service, or that started while visible and continue after the app leaves view, count toward the runtime quota. Google suggests UIDT for user-initiated transfers. Use `WorkInfo.getStopReason()` for diagnosis.

**[INFERRED] Recommended Android design:**
1. One upload queue in Room, mirroring the iOS state machine.
2. **"Back up now" or "Retry backup" while the app is visible:**
   - API 34+: start a UIDT job with an estimate of the remaining bytes. The notification shows progress, and "Wi-Fi only" maps to `NOT_METERED`.
   - API 29–33: a WorkManager `OneTimeWorkRequest` marked `setExpedited` plus a long-running `dataSync` foreground worker.
3. **Automatic backup after a session:** WorkManager with `Constraints(requiredNetworkType = UNMETERED, requiresBatteryNotLow = true)`. The worker uploads **32 to 64 MiB chunks** and saves the confirmed offset after each 308, so a run that ends after about 10 minutes still made progress.
4. HTTP: OkHttp with a streaming `RequestBody` that reads a `FileChannel` from the offset. The Java client's `MediaHttpUploader` enforces 256 KiB multiples (`MINIMUM_CHUNK_SIZE = 256 KiB`, `DEFAULT_CHUNK_SIZE = 10 MiB`) [S43]. It doesn't offer a simple way to resume a persisted session after the process dies, so a small custom client is clearer. **[OBSERVED constants; INFERRED judgement]**

### A9. Verifying completion

- **[OBSERVED] [S23]** `md5Checksum` exists for files with binary content. `sha1Checksum` and `sha256Checksum` are filled "if available" for content stored in Drive. `size` is in bytes. `videoMediaMetadata{width,height,durationMillis}`, `originalFilename`, `trashed`, `isAppAuthorized` and `appProperties` are also available. Request fields explicitly, for example `fields=id,name,size,md5Checksum,sha256Checksum,appProperties,trashed`.
- **[INFERRED] Rule:** show "Backed up" (screens 8 and 19) only if Drive `size` equals the local size **and** `md5Checksum` equals the local MD5, plus `sha256Checksum` when present. Compute both hashes in one streaming pass when recording finalizes (CryptoKit `Insecure.MD5` and `SHA256` on iOS, `MessageDigest` on Android). Store them in the local manifest and the sidecar. `videoMediaMetadata` may fill in after processing **[UNVERIFIED timing]**, so it is an extra check only.
- **[INFERRED] Optional restore probe:** a ranged GET of the first and last 1 MiB [S26] confirms the file can be read without downloading all of it.

### A10. App archive folder and JSON sidecars

- **Folder [S25]:** `files.create` with `mimeType: application/vnd.google-apps.folder`, a `name`, and `parents: ["root"]` or a folder the user chose through the Picker's folder selection. Limits: 500,000 items per folder (the root of My Drive is exempt), 100 levels of nesting. Use a pre-generated ID so retries can't create duplicate "JOVRA" folders [S2].
- **Re-discovery after reinstall or on another device [S31]:** `q = "appProperties has { key='jovraRole' and value='archiveRoot' } and mimeType = 'application/vnd.google-apps.folder' and trashed = false"`. If the user moved or renamed the folder, the ID still works.
- **`appProperties` limits [S27]:** at most 30 private properties per app per file, 100 properties in total, and **124 bytes per key plus value** in UTF-8. Store only identifiers there, such as `jovraRole`, `sessionId` (UUID), `schema=1` and a short hash prefix. Everything else goes in the sidecar.
- **Suggested layout [INFERRED]:** `JOVRA/2026/2026-10-06 Jon vs Alex/` containing `original.mp4`, `session.jovra.json`, and `clips/point-042.mp4` (optional).
- **Sidecar [INFERRED]:** upload as `application/json` with a multipart upload (5 MB or less) [S2]. Update with a `PATCH` media upload. Contents: a versioned schema with `schemaVersion`, `sessionId`, `createdAt`, `app {platform, version}`, `video {fileName, bytes, md5, sha256, durationMs, fps, codec, width, height}`, `score[]`, `points[]`, `shots[]`, `calibration`, `annotations[]`, `equipment`, `strings`. Keep it independent of any provider, matching the build prompt's "provider-independent archive manifests". Restore therefore needs nothing more than `originals + sidecar`.

### A11. Rate limits, quotas and coming costs

**[OBSERVED] [S20][S21]:**
- Since 2026-05-01, for new projects:

  | Limit | Value |
  |---|---|
  | Per minute per project | 1,000,000 units |
  | Per minute per user per project | 325,000 units |
  | Egress per day per project, before charges | 1 TB |
  | Daily billing threshold | 400,000,000 units, cannot be raised |

- Units per call: read (`files.get`) 5, list (`files.list`) 100, download (`files.download`) 200, edit (`files.update`) 50, other (`generateIds`) 5.
- Errors when over a limit: 403 `User rate limit exceeded` or 429. Use truncated exponential backoff (1 s, 2 s, 4 s … plus random milliseconds, up to a maximum).
- Projects that used the API between November 2025 and April 2026 keep their old quotas. Later in 2026, after 90 days' notice, usage above the standard daily thresholds will generate Cloud charges, and quota increases will require billing to be enabled.

**[INFERRED]**
- An upload costs about 3 to 5 calls: initiate, PUT, status queries, then `files.get` to verify. That is trivial in units, though per-PUT unit accounting isn't documented. **[UNVERIFIED]**
- **Restores are the exposure.** 1 TB divided by 3.2 GB is about 312 full-session restores per day across all users before charges. It isn't documented whether `files.get?alt=media` counts as "download items" (200 units) or "read" (5), or exactly how it maps to project egress. **[UNVERIFIED]** Mitigations: route restores through the Files or SAF Drive provider where possible, restore on demand only, and track bytes restored per day in telemetry.

### A12. Storage quota errors and preflight

- **[OBSERVED]** `403 storageQuotaExceeded`, message "The user's Drive storage quota has been exceeded." [S22]. `about.get?fields=storageQuota(limit,usage,usageInDrive,usageInDriveTrash),maxUploadSize` works with `drive.file`. `limit` is missing for unlimited accounts and reflects the whole organisation for pooled Workspace storage [S29].
- **[INFERRED]** Before creating a session, compare `limit - usage` with the file size plus a 5% margin. If it doesn't fit, set the item to `quota_blocked` and offer three options on screen 19: back up an archive copy (HEVC re-encode with Transformer or AVAssetExportSession), back up flagged clips only, or open Google One. Never delete the local original because a backup failed.

### A13. Restore and download

- **[OBSERVED] [S26]** `GET /drive/v3/files/{id}?alt=media` supports `Range: bytes=start-end`, so restores can resume. `revisions.get` also takes `alt=media`. Files flagged as abusive need `acknowledgeAbuse=true` and a warning to the user first. `files.download` is a long-running operation needed only for Google Vids and editor formats.
- **[INFERRED]** On iOS, background `downloadTask`s survive app exit [S37]. On Android, use the same UIDT or WorkManager split as uploads. Check MD5 and SHA-256 after download, then register the file as the local original and re-link the sidecar.

### A14. Drive branding in the UI (screens 7, 19)

**[OBSERVED] [S33]:**
- Always write "Google Drive" in full, and use verb phrases such as "Back up to Google Drive".
- The Drive logo may be resized but not otherwise altered. Use it for actions or to show where a file is stored. An icon-only button needs a tooltip.
- First mention in marketing is "Google Drive™". Include the trademark attribution.

Screen 19's "Google Drive · Connected · Demo" pill follows these rules if the label stays the full name.

### A15. Falsifiable acceptance checks for the archive (to add to the build gates)

1. Kill the app at 10%, 50% and 99% of a 3 GB upload, relaunch, and confirm it continues from `Range+1` with no duplicate file (pre-generated ID).
2. Run an upload longer than 90 minutes so the access token expires. Confirm data PUTs succeed without a refresh, or that refresh happens cleanly.
3. iOS background session: confirm on a device how a 308 status query response is delivered (UNVERIFIED item in A7).
4. Simulate an expired session (a 404 stub) and confirm `files.get` is checked before a fresh session starts.
5. Use an account with less than 1 GB free and confirm `storageQuotaExceeded` leads to `quota_blocked` without retry storms.
6. Revoke access at myaccount.google.com, then confirm iOS (`invalid_grant`) and Android (`hasResolution` or 401) both reach "Needs reconnect".
7. Create a file on iOS and list it from Android in the same Cloud project (A1, UNVERIFIED).
8. Import with the Picker on both platforms. Confirm `picked_file_ids` resolve and download with a matching MD5.
9. Reinstall, reconnect, and confirm the archive folder is found again by its `appProperties`.
10. Toggle "Wi-Fi only" and confirm no cellular bytes move (`allowsExpensiveNetworkAccess` / `NOT_METERED`).

---

## B. Android stack for the port

### B1. SDK levels and platform behaviour

- **[OBSERVED] Play target requirement [S52]:** since 2026-08-31, new apps and updates must target **API 36 (Android 16)**, with extensions to 2026-11-01. Existing apps below API 35 stop being offered to new users on newer Android versions.
- **[OBSERVED] Android 17 (API 37)** has released documentation and behaviour changes [S51].
- **[OBSERVED] Targeting 36 [S50]:**
  - Edge-to-edge can't be switched off.
  - Predictive back is on by default. `onBackPressed` isn't called and `KEYCODE_BACK` isn't sent.
  - On screens with smallest width 600 dp or more, `screenOrientation`, `resizeableActivity`, `minAspectRatio`, `maxAspectRatio` and `setRequestedOrientation()` are **ignored**. The temporary opt-out `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` goes away when targeting 37 [S51].
  - So the recording and replay screens must handle any orientation on tablets and foldables.
- **[OBSERVED] Android 17 [S51]:** RAM-based app memory limits (relevant to video decoding and ML). Background audio hardening.
- **[OBSERVED] 16 KB pages [S53]:** apps targeting 35+ must support 16 KB pages on 64-bit devices. From **2027-02-01**, Play won't accept updates that don't. Use AGP 8.5.1+, NDK r28+ and 16 KB-aligned native dependencies. ML Kit and MediaPipe ship native libraries, so check their alignment.
- **[OBSERVED] Library minimums:** AndroidX moved to minSdk 23 (CameraX 1.5, Media3 1.9, Navigation3, Room 2.8). WorkManager 2.12 needs 24 [S54][S58][S67]. ML Kit pose needs 23 [S61].
- **[INFERRED] Recommendation:** `minSdk 29`. It gives the thermal status API (29), the scoped-storage baseline and the Photo Picker backport, and avoids old-camera edge cases. `targetSdk 36`, `compileSdk 37`. Re-test, then move to 37.

### B2. Capture with CameraX

**Versions [S54] [OBSERVED]:** CameraX **1.6.2** stable (library updated 2026-08-26). 1.7.0-alpha03.

**What changed:**
- **1.6.0 (2026-03-25):**
  - Moved to the CameraPipe stack used by the Pixel camera.
  - **Media3 Muxer by default in VideoCapture**, with crash resilience that preserves data if the app crashes while recording.
  - `SessionConfig` and `HighSpeedVideoSessionConfig` are now stable. New `isSessionConfigSupported`.
  - Feature groups gained `VIDEO_STABILIZATION` and `UHD_RECORDING`.
  - Fixed a bind crash on Android 17 devices that expose new dynamic-range profiles, so stay on 1.5.2 or later.
- **1.5.0 (2025-09-10):**
  - High-speed and slow-motion recording at 120 and 240 fps.
  - `SessionConfig` with feature groups (HLG, Ultra HDR, **60 fps**, preview stabilization).
  - Deterministic frame-rate query with `CameraInfo.getSupportedFrameRateRanges(sessionConfig)`.
  - `ERROR_INSUFFICIENT_STORAGE`.
  - `withAudioEnabled(initialMuted)`.

**60 fps recipe (OBSERVED APIs; INFERRED composition):**
```kotlin
val recorder = Recorder.Builder()
    .setQualitySelector(QualitySelector.fromOrderedList(
        listOf(Quality.FHD, Quality.HD), FallbackStrategy.lowerQualityOrHigherThan(Quality.HD)))
    .setVideoMimeType(MediaFormat.MIMETYPE_VIDEO_HEVC)   // smaller files; check support
    .setTargetVideoEncodingBitRate(12_000_000)          // planning value, tune per device
    .build()
val videoCapture = VideoCapture.withOutput(recorder)
val probe = SessionConfig(useCases = listOf(preview, videoCapture))
val fps60 = cameraInfo.getSupportedFrameRateRanges(probe).firstOrNull { it.lower == 60 && it.upper == 60 }
val config = SessionConfig.Builder(listOf(preview, videoCapture))
    .apply { if (fps60 != null) setFrameRateRange(fps60) }   // else fall back to 30 and tell the user
    .build()
check(cameraInfo.isSessionConfigSupported(config))
cameraProvider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, config)
```
Alternatives:
- `SessionConfig.Builder.setPreferredFeatureGroup(GroupableFeature.FPS_60, GroupableFeature.PREVIEW_STABILIZATION)` lets CameraX choose the best supported combination.
- `setRequiredFeatureGroup` throws on bind if the combination isn't supported [S56].
- Trade-off: a fixed range such as [60,60] gives steady video but can be darker and noisier in low light [S56]. That matters for evening club tennis.
- Camera2 interop isn't needed for this. 1.7.0-alpha03 adds new `Camera2Interop` configurators for anything still missing [S54].

**120/240 fps [S56]:**
- `HighSpeedVideoSessionConfig`, with capabilities from `Recorder.getHighSpeedVideoCapabilities(cameraInfo)`. Rates are 120 or more, in multiples of 30.
- Constraints: no explicit target frame rate, no mirror mode, preview at about 30 fps with the same resolution, no `ViewPort` or `CameraEffect`.
- Optional slow-motion processing.
- Use it for the Serve Lab burst mode, not for whole matches. **[INFERRED]**

**Output:**
- `FileOutputOptions` writes app-specific storage: no permission, private, **deleted on uninstall**.
- `MediaStoreOutputOptions` writes a shared collection that survives uninstall and shows in the gallery [S55][S66].
- All output types accept `setFileSizeLimit()`.
- **[INFERRED]** Record into app-specific storage, which is fast and private. Offer "Also save to Movies/JOVRA" (MediaStore) in Settings, and say plainly on screen 19 that uninstalling deletes local-only originals.

**Audio (optional) [S55][S56]:**
- `withAudioEnabled()` needs `RECORD_AUDIO`.
- `AudioStats` states: `ACTIVE`, `DISABLED`, `MUTED`, `SOURCE_SILENCED` (the system silenced the mic, for example the dialer took it), `SOURCE_ERROR`, `ENCODER_ERROR`.
- `Recording.mute(boolean)`.
- With the mic off, the audio hit-detection feature (B6) must degrade visibly.

**Interruptions and errors (OBSERVED [S56]):**
- `VideoRecordEvent.Finalize` errors:

  | Code | Error |
  |---|---|
  | 0 | `ERROR_NONE` |
  | 1 | `UNKNOWN` |
  | 2 | `FILE_SIZE_LIMIT_REACHED` |
  | 3 | `INSUFFICIENT_STORAGE` |
  | 4 | `SOURCE_INACTIVE` |
  | 5 | `INVALID_OUTPUT_OPTIONS` |
  | 6 | `ENCODING_FAILED` |
  | 7 | `RECORDER_ERROR` |
  | 8 | `NO_VALID_DATA` |
  | 9 | `DURATION_LIMIT_REACHED` |
  | 10 | `RECORDING_GARBAGE_COLLECTED` |

  A file **is still produced** for `FILE_SIZE_LIMIT_REACHED`. It may also be produced for `DURATION_LIMIT_REACHED` and `SOURCE_INACTIVE`. It may or may not exist after `INSUFFICIENT_STORAGE`. So always check the output URI before declaring failure.
- `CameraState` errors: `CAMERA_IN_USE`, `MAX_CAMERAS_IN_USE`, `CAMERA_DISABLED`, `DO_NOT_DISTURB_MODE_ENABLED`, `OTHER_RECOVERABLE_ERROR`, `CAMERA_FATAL_ERROR`, `CAMERA_DEVICE`, `CAMERA_SERVICE`, `CAMERA_REMOVED`, `STREAM_CONFIG`.
- `PendingRecording.asPersistentRecording()` keeps a recording going while VideoCapture is re-bound to another camera [S55].
- **[INFERRED]** CameraX is tied to the lifecycle. Leaving the activity stops frames, which produces `SOURCE_INACTIVE`. During recording, keep the screen on (`FLAG_KEEP_SCREEN_ON`), dim the UI, and treat any `Finalize` as "save what exists, then tell the user". Keep the Room "recording in progress" row so a crash can be recovered at next launch. The 1.6 muxer's crash resilience helps here.
- **[INFERRED] Planning file sizes:** size in GB is about Mbps × minutes × 0.0075. At 12 Mbps, 60 minutes is about 5.4 GB. Surface this on screen 4 ("Estimated space").

**Thermal (OBSERVED [S57]):**
- `PowerManager.getCurrentThermalStatus()` and `addThermalStatusListener()` (API 29). Levels: 0 NONE, 1 LIGHT, 2 MODERATE, 3 SEVERE, 4 CRITICAL, 5 EMERGENCY, 6 SHUTDOWN.
- `getThermalHeadroom(forecastSeconds)` (API 30). Calling it more than about once a second can return NaN.
- `getThermalHeadroomThresholds()` (API 35). `addThermalHeadroomListener()` (API 36).
- **[INFERRED] Policy matching screen 6's "Phone warming · Analysis paused":** at MODERATE, pause on-device analysis. At SEVERE, warn and offer to drop to 30 fps at the next re-bind. At CRITICAL or above, stop and finalize cleanly.

### B3. Replay with Media3 ExoPlayer

- **Versions [S58] [OBSERVED]:** Media3 **1.11.1** (2026-09-10).
- **Seeking [S59] [OBSERVED]:**
  - `setSeekParameters(SeekParameters)`. In the source, **`DEFAULT = EXACT`** (`EXACT = SeekParameters(0, 0)`).
  - `CLOSEST_SYNC`, `PREVIOUS_SYNC` and `NEXT_SYNC` trade accuracy for speed.
  - `setScrubbingModeEnabled(true)`, added in the 1.8.0 cycle, tunes the player for many rapid seeks while the user drags. Tune it with `setScrubbingModeParameters`. Playback is suppressed with `PLAYBACK_SUPPRESSION_REASON_SCRUBBING`.
- **Frame stepping [INFERRED]:**
  - ExoPlayer has no frame-step method. The only frame-related APIs are `setVideoFrameMetadataListener` and the frame-rate change strategy [S59].
  - Implement it as pause, then `seekTo(position ± 1_000_000/fps µs)` with `EXACT`. Read fps from `videoFormat.frameRate`.
  - Use `VideoFrameMetadataListener` to sync drawn overlays to the presentation time of the frame actually rendered.
  - Each step back decodes from the previous keyframe, so its cost depends on the GOP length. For Stroke Lab and comparison, generate a short-GOP proxy (Transformer) if step latency is poor. Measure it.
- **Speed:** `setPlaybackSpeed(0.25f | 0.5f)` or `setPlaybackParameters` [S59].
- **Thumbnails, timeline and ML frames:**
  - `androidx.media3.inspector.frame.FrameExtractor` (module `media3-inspector-frame` since 1.10.0): `getFrame(positionMs)` and `getThumbnail()` return `ListenableFuture<Frame>`. The builder has `setSeekParameters`, `setEffects` and `setExtractHdrFrames`.
  - Google warns that colours may be inaccurate outside BT.601 limited range on devices from before API 33 [S59].
  - `androidx.media3.inspector.MetadataRetriever` replaces the old ExoPlayer one [S58].

### B4. Clip export and overlays with Media3 Transformer

**[OBSERVED] [S60][S59]:**
- **Trimming:** `MediaItem.ClippingConfiguration.Builder().setStartPositionMs(…).setEndPositionMs(…)`.
- **Trim optimization:** `Transformer.Builder(ctx).experimentalSetTrimOptimizationEnabled(true)` re-encodes only the part near the cut. It works only when the encoder's output format matches the input. Files recorded on another device often won't qualify.
- **MP4 edit lists:** `experimentalSetMp4EditListTrimEnabled(true)` gives near-instant trim-only edits using a pre-roll. Some players ignore the pre-roll and show the "hidden" opening. **[INFERRED]** Don't use it for privacy-sensitive trims or for clips shared outside the app.
- **Effects:**
  - `Presentation.createForHeight(720)` for scaling.
  - `OverlayEffect(List<TextureOverlay>)`, where the last overlay draws on top.
  - `TextOverlay`, whose `getText(presentationTimeUs)` can change per frame, so a **burned-in live scoreboard** is possible.
  - `BitmapOverlay.getBitmap(presentationTimeUs)` for drawings and telestration.
  - `EditedMediaItem.Builder.setRemoveAudio(true)`. `setSpeed(SpeedParameters)` keeps pitch. `setFrameRate()` caps the output fps.
- **Progress and helpers:** `Transformer.getProgress(ProgressHolder)` reports progress. `CompositionPlayer` (experimental) previews edits.
- **[INFERRED]** Run long exports as a `mediaProcessing` foreground service (API 35+, 6 h per 24 h) [S47][S48]. Clip exports of a few seconds can run in the foreground.

### B5. Pose estimation on device

- **ML Kit Pose Detection [S61] [OBSERVED]:**
  - `com.google.mlkit:pose-detection:18.0.0-beta5` and `pose-detection-accurate`. **Beta, no SLA or deprecation policy.**
  - 33 landmarks with `InFrameLikelihood`. The Z coordinate is experimental and not true 3D.
  - Size and speed: base about 10.1 MB and about 30 fps on a Pixel 3 XL; accurate about 13.3 MB.
  - API 23+. `STREAM_MODE` (tracks the most prominent person) or `SINGLE_IMAGE_MODE`. Hardware configs `CPU` and `CPU_GPU`.
  - **Detects one person. The face must be present. The subject should fill much of the frame.** Input at least 480×360.
- **MediaPipe Pose Landmarker [S62] [OBSERVED]:**
  - Lite, full and heavy bundles: a 224×224 detector and a 256×256 landmarker, float16.
  - 33 landmarks plus world coordinates.
  - `RunningMode` `IMAGE`, `VIDEO` (`detectForVideo`) or `LIVE_STREAM`. `setNumPoses(n)`, default 1.
- **[INFERRED] Fit for JOVRA:**
  - Behind-baseline match footage shows small figures facing away. ML Kit's face requirement and single-person limit rule it out there.
  - For Stroke Lab, which uses side-on close clips, either works. MediaPipe `VIDEO` mode with `numPoses = 1`, run offline on decoded frames from `FrameExtractor`, is the more controllable choice. For doubles, `numPoses = 2..4`.
  - iOS will likely use Apple Vision body pose, so the two platforms will disagree slightly. Keep the prior research's per-platform benchmark gate and show only labelled "2D pose estimate" views (screen 13).

### B6. Audio decoding for hit detection

- **[OBSERVED] [S63]:**
  - `MediaExtractor.setDataSource` → find the track with `KEY_MIME` starting `audio/` → `selectTrack` → `readSampleData` / `getSampleTime` / `advance`.
  - Decode with `MediaCodec`. Asynchronous callback mode is preferred since API 21.
  - Output is 16-bit PCM by default, or float if `KEY_PCM_ENCODING = ENCODING_PCM_FLOAT` was set and confirmed in `getOutputFormat()`.
  - De-interleave channels from `getOutputBuffer(id)` as a `ShortBuffer`.
  - Media3's `inspector` module offers `MediaExtractorCompat` [S58].
- **[INFERRED] Algorithm sketch (to benchmark, not a claim):** mono mixdown → high-pass filter around 1–2 kHz → short-time energy or spectral flux at a 5–10 ms hop → adaptive threshold → peak picking with a minimum gap of about 150–250 ms between onsets. Then fuse with pose and court motion so a nearby court's hits are rejected. Timestamps come from `presentationTimeUs`, so they line up with ExoPlayer positions.

### B7. Import (Photos, Files, Drive)

- **Photo Picker [S64] [OBSERVED]:**
  - `androidx.activity` 1.7.0+. Use `PickVisualMedia()` or `PickMultipleVisualMedia()` with `PickVisualMedia.VideoOnly`.
  - Available on Android 11+ through system updates. Backported to API 19–29 through Google Play services. Otherwise it falls back to `ACTION_OPEN_DOCUMENT`.
  - `takePersistableUriPermission` for long-running work such as background upload. Limit of 5,000 media grants, oldest dropped first.
  - **HDR → SDR transcoding:** declare `setMediaCapabilitiesForTranscoding(MediaCapabilities)`. Pass the HDR types JOVRA supports, or `null` to turn transcoding off, so analysis sees the original.
- **Play policy [S65] [OBSERVED]:** apps targeting 33+ may request `READ_MEDIA_VIDEO` or `READ_MEDIA_IMAGES` only if system pickers can't serve core functionality. Enforcement has been in place since 2025-05-28. **Don't request them.**
- **Files and Drive:** use `ACTION_OPEN_DOCUMENT` through the Storage Access Framework. Google Drive is a document provider [S36]. The Picker path is in A5.

### B8. UI and navigation

- **[OBSERVED] [S67]:**
  - Compose BOM **2026.09.00**.
  - **Navigation 3 1.2.0** stable (2026-09-23). 1.0.0 went stable on 2025-11-19 as the Compose-first navigation library, built around `NavDisplay` and a back stack the app owns.
  - Navigation (Compose) 2.10.2 (2026-09-23).
- **[INFERRED]** A new all-Compose app should use Navigation 3. The app owns the back stack, which makes the Record → Calibrate → Live flows and deep links from notifications ("Backup needs reconnect") easier to reason about. Predictive back is required at target 36 [S50].

### B9. Persistence

- **[OBSERVED] [S67]:** Room **2.8.5** (2026-09-09). minSdk 23. Kotlin Multiplatform targets include iOS, plus watchOS and tvOS since 2.8. WorkManager **2.12.0**, minSdk 24, adds `work-analytics`.
- **[INFERRED]**
  - Room holds sessions, score events, shots, calibration, annotations, equipment and strings, plus `UploadItem` and `ExportJob` state machines.
  - DataStore holds preferences such as units and "Wi-Fi only".
  - Video files live in app-specific storage.
  - The domain schema and sidecar JSON are identical to iOS. If a later Kotlin Multiplatform module shares domain logic, Room's KMP support allows a shared database layer. The iOS SwiftData app can still stay native.

### B10. Testing

- **[OBSERVED]**
  - JVM unit tests with JUnit.
  - Compose UI tests with `androidx.compose.ui:ui-test-junit4` and `createComposeRule()` / `createAndroidComposeRule<Activity>()`. `ui-test-manifest` goes in `debugImplementation` for `createComposeRule`. The docs now include a "Test configuration and execution (v2)" page [S68].
  - **Maestro cli-2.11.0** (2026-09-29): YAML flows run on Android emulators, iOS simulators and physical Android devices. **Physical iOS isn't supported.** Needs Java 17+. Includes a Maestro MCP server for coding agents [S69].
- **[OBSERVED] Emulator camera [S70]:** `emulator @AVD -camera-back <mode>`, where the mode is one of:
  - `emulated`
  - `environment` (virtual scene, where you can import PNG or JPEG posters)
  - `webcamN` (list with `-webcam-list`)
  - `imagefile:<file>`
  - **`videofile:<file>`**
  - `image360:<file>` (emulator 36.6.4+)
  - `none`

  On Android 11+ system images the emulator supports RAW, Level 3, logical and concurrent cameras.
- **[INFERRED] Test pyramid for the port:**
  1. JVM: scoring rules, the upload state machine (with OkHttp MockWebServer scripting 308 with and without `Range`, 404, 5xx, 403 `storageQuotaExceeded`, 429), the sidecar schema, hashing.
  2. Instrumented: Room migrations, WorkManager with `work-testing`, Transformer trim and overlay on fixture MP4s, ExoPlayer exact-seek frame accuracy against a frame-counter fixture video.
  3. Emulator: CameraX record of 60 s from `-camera-back videofile:court.mp4` through import and replay. Maestro flows mirroring the iOS ones.
  4. Pixel hardware only: real 60 fps and high-speed capability, 60+ minute thermal soak, interruptions (incoming call, `SOURCE_SILENCED`), low storage, airplane mode during upload.
  - The emulator can't prove frame rates, heat or encoder throughput.
  - Google sign-in on the emulator needs a Google Play system image and a debug-SHA-1 OAuth client (A4).
- **[OBSERVED] Distribution context [S71]:** Android developer verification protections start 2026-09-30 for stores in Brazil, Indonesia, Singapore and Thailand, then roll out globally in 2027. Whether `adb install` of a debug build to Jon's Pixel is exempt was not confirmed on the page I read. **[UNVERIFIED]**

---

## C. Contrary checks and open risks

- **The custom-scheme wording conflict (A3).** Today's evidence favours the iOS reversed-client-ID scheme (Google's 2026 iOS SDK guide). Watch Google's OAuth changelog. App Check and the SDK reduce exposure.
- **Per-project versus per-client `drive.file` grants (A1).** The Picker guide's "project number" wording and a forum report disagree. Settle it with the cross-platform test in A15.
- **iOS 308 handling in background sessions (A7).** Undocumented. Prefer `GTMSessionUploadFetcher`. Its `X-Goog-Upload` dialect is used by Google's client but isn't on the Drive upload guide. If Google changed it, its own Drive SDK would break too. The risk is low but not zero.
- **Quota billing (A11).** Charges are announced but not yet priced. Restores are the exposure.
- **The assignment assumed "WorkManager + dataSync".** Current Google guidance and the Android 15/16 limits favour UIDT for user-started transfers (A8).
- **The assignment assumed "Camera2 interop for 60 fps".** CameraX 1.5+ covers it natively (B2).
- **The assignment assumed "target 35/36".** API 36 is now required (B1).
- **Pose on match footage.** ML Kit's documented limits (single person, face visible) conflict with the behind-baseline camera (B5). Benchmark before shipping any automatic stroke metric.

---

## Sources

All accessed 2026-10-07. Where a page showed a "Last updated" stamp, it is given in parentheses.

- [S1] https://developers.google.com/workspace/drive/api/guides/api-specific-auth: Drive scope list, classifications (non-sensitive, sensitive, restricted) and what `drive.file` grants.
- [S2] https://developers.google.com/workspace/drive/api/guides/manage-uploads (2026-09-03): resumable initiation, session lifetime of one week, single PUT preferred, 256 KiB chunk multiples, status query and 308/`Range`, 404 restart, error handling, pre-generated IDs and 409, sample PUTs without an Authorization header.
- [S3] https://developers.google.com/identity/protocols/oauth2/native-app (2026-09-14): iOS client type, PKCE S256 and verifier length, no client secret, redirect options, custom scheme unsupported on Android and Chrome, loopback deprecated, `disallowed_useragent`, incremental auth not supported, granular consent, revoke endpoint and project-wide effect, refresh tokens always returned, DPoP, App Check (App Attest, Team ID).
- [S4] https://developers.google.com/identity/protocols/oauth2 (2026-05-26): reasons a refresh token expires, 7-day expiry in Testing status, 100 refresh tokens per account per client.
- [S5] https://support.google.com/cloud/answer/15549945 (Manage App Audience): 100 test users, 7-day expiry for test users, user cap, publishing status.
- [S6] https://support.google.com/cloud/answer/7454865 (Unverified apps): unverified means sensitive or restricted scopes; 100 new-user cap.
- [S7] https://support.google.com/cloud/answer/13464323 (When is verification not needed): User Data Policy applies regardless; separate dev, test and prod projects.
- [S8] https://support.google.com/cloud/answer/13464321 (Verification requirements): brand verification requirements, Limited Use, demo video and justification, annual security assessment for restricted scopes.
- [S9] https://support.google.com/cloud/answer/15549049 (Manage OAuth App Branding): name and logo shown only after verification, logo specs, support email options, Verify Branding timing.
- [S10] https://developers.google.com/workspace/drive/picker/guides/overview (2026-09-14): web versus desktop and mobile Picker; mobile uses the system browser and `drive.file` only.
- [S11] https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker: `trigger_onepick`, `prompt=consent`, `allow_multiple`, `mimetypes`, `file_ids`, `allow_folder_selection`, `picked_file_ids`, Android `PICKER_OAUTH_TRIGGER` flow.
- [S12] https://developers.google.com/android/reference/com/google/android/gms/auth/api/identity/AuthorizationRequest.ResourceParameter (2026-05-27) and https://developers.google.com/android/reference/com/google/android/gms/auth/api/identity/AuthorizationRequest.Builder (2026-01-07): `PICKER_*` constants, `addResourceParameter`, `setOptOutIncludingGrantedScopes`, `setPrompt`.
- [S13] https://developer.android.com/identity/authorization: `AuthorizationClient` flow, Credential Manager versus authorization, `revokeAccess` revokes all scopes, `clearToken`, offline access only through a server, Android client SHA-1 setup, `play-services-auth:22.0.0`. Also https://dl.google.com/android/maven2/com/google/android/gms/play-services-auth/maven-metadata.xml: latest version 22.0.0.
- [S14] https://github.com/google/GoogleSignIn-iOS/releases and `GoogleSignIn/Sources/Public/GoogleSignIn/GIDSignIn.h`, `GIDGoogleUser.h`, `Package.swift`: 10.0.0 (2026-09-04, iOS 15, AppAuth 3, GTMAppAuth 6), 9.2.0 notes, public API surface with no arbitrary authorization parameters.
- [S15] https://developers.google.com/identity/sign-in/ios/start-integrating (2026-03-22): `GIDClientID` and reversed-client-ID URL scheme.
- [S16] https://developers.google.com/identity/sign-in/ios/api-access: `grantedScopes`, `addScopes`, `refreshTokensIfNeeded`, `fetcherAuthorizer`.
- [S17] https://developers.google.com/identity/sign-in/ios/disconnect: `disconnect` revokes tokens; delete Google-derived data when the account is deleted.
- [S18] https://developers.google.com/identity/sign-in/ios/appcheck, https://developers.google.com/identity/sign-in/ios/appcheck/get-started and https://developers.google.com/identity/sign-in/ios/appcheck/debug-provider: App Check through App Attest, `configure`, debug provider for Simulator and CI, monitor before enforcing.
- [S19] https://github.com/openid/AppAuth-iOS/releases: 3.0.0 (2026-08-24, iOS 15 minimum, Xcode 27) and 2.1.0 (2026-06-12, `ASWebAuthenticationSession` with no Safari fallback).
- [S20] https://developers.google.com/workspace/drive/api/guides/limits (2026-09-11): May 2026 quota units, 1 TB per day egress, 400M daily threshold, per-method units, 750 GB per day upload, 5 TB maximum file, backoff guidance.
- [S21] https://developers.google.com/workspace/tools-safety (2026-09-03): standardized quota tiers, billing later in 2026 with 90 days' notice.
- [S22] https://developers.google.com/workspace/drive/api/guides/handle-errors (2026-09-03): `storageQuotaExceeded`, `userRateLimitExceeded`, 429, `authError` (401), `appNotAuthorizedToFile`, 5xx backoff.
- [S23] https://developers.google.com/workspace/drive/api/reference/rest/v3/files: `md5Checksum`, `sha1Checksum`, `sha256Checksum`, `size`, `appProperties`, `videoMediaMetadata`, `isAppAuthorized`, `spaces`.
- [S24] https://developers.google.com/workspace/drive/api/guides/appdata (2026-09-03): hidden app data folder, deletion on uninstall, cannot share, move or trash.
- [S25] https://developers.google.com/workspace/drive/api/guides/folder (2026-09-03): folder MIME type, 500,000 items, 100 levels.
- [S26] https://developers.google.com/workspace/drive/api/guides/manage-downloads (2026-09-03): `alt=media`, `Range` partial download, `acknowledgeAbuse`, `files.download` scope of use.
- [S27] https://developers.google.com/workspace/drive/api/guides/properties (2026-09-03): property limits of 30 private per app, 100 total and 124 bytes.
- [S28] https://developers.google.com/workspace/drive/api/reference/rest/v3/files/generateIds: parameters; `drive.file` allowed.
- [S29] https://developers.google.com/workspace/drive/api/reference/rest/v3/about and https://developers.google.com/workspace/drive/api/reference/rest/v3/about/get: `storageQuota` fields, `maxUploadSize`, `drive.file` allowed.
- [S30] https://developers.google.com/workspace/drive/api/reference/rest/v3/files/create (2026-03-20): 5,120 GB maximum upload size.
- [S31] https://developers.google.com/workspace/drive/api/guides/search-files (2026-09-09): `appProperties has {key=… and value=…}` and `trashed = false` query syntax.
- [S32] https://developers.google.com/workspace/drive/picker/guides/web-picker (2026-09-03): `setAppId` uses the Cloud project number to give the app file access.
- [S33] https://developers.google.com/workspace/drive/api/guides/branding (2026-09-03): Google Drive naming, logo and tooltip rules.
- [S34] https://support.google.com/drive/answer/9312312: 15 GB shared across Gmail, Drive and Photos.
- [S35] https://workspaceupdates.googleblog.com/2017/09/use-google-drive-and-files-app-to.html: Google Drive integrated with the iOS Files app (page title confirmed; details from search summary).
- [S36] https://developer.android.com/guide/topics/providers/document-provider: SAF document providers, with Google Drive named as an example. Also https://developer.android.com/training/data-storage/shared/documents-files: `takePersistableUriPermission`.
- [S37] https://developer.apple.com/documentation/foundation/downloading-files-in-the-background: background session lifecycle, relaunch, only file-based uploads, redirects always followed, rate limiter, `isDiscretionary`, `countOfBytesClientExpectsToSend`.
- [S38] https://developer.apple.com/documentation/foundation/pausing-and-resuming-uploads: iOS 17 resumable uploads need a server implementing `draft-ietf-httpbis-resumable-upload-01`.
- [S39] https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask and https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados: iOS 26 continued processing, Live Activity progress, user cancel, network allowed.
- [S40] https://developer.apple.com/documentation/foundation/urlsessionconfiguration/allowsexpensivenetworkaccess and https://developer.apple.com/documentation/foundation/urlsessionconfiguration/allowsconstrainednetworkaccess: expensive and Low Data Mode controls with `waitsForConnectivity`.
- [S41] https://github.com/google/gtm-session-fetcher (v5.3.1, 2026-08-04; `GTMSessionUploadFetcher.h/.m`): `X-Goog-Upload` protocol commands and status, background session support, temporary chunk files, "chunk upload URL requires no authentication header" comment.
- [S42] https://github.com/google/google-api-objectivec-client-for-rest (v5.4.0, 2026-08-04; `Sources/Core/GTLRService.m`): `uploadType=resumable` through `GTMSessionUploadFetcher`, `useBackgroundSession` passthrough.
- [S43] https://github.com/googleapis/google-api-java-client (`MediaHttpUploader.java`): `MINIMUM_CHUNK_SIZE = 256 KB`, `DEFAULT_CHUNK_SIZE = 10 MB`, chunk-size check, `setDirectUploadEnabled`.
- [S44] https://developer.android.com/develop/background-work/background-tasks/data-transfer-options (2026-02-26): WorkManager versus UIDT versus FGS decision table.
- [S45] https://developer.android.com/develop/background-work/background-tasks/uidt (2026-10-01): UIDT API 34, permission, `setUserInitiated`, `setEstimatedNetworkBytes`, visibility and notification requirements.
- [S46] https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/long-running (2026-10-01): `setForeground`, FGS type declaration, Android 16 job-quota note, UIDT suggestion.
- [S47] https://developer.android.com/develop/background-work/services/fgs/service-types (2026-10-01): `dataSync` and `mediaProcessing` details; no `dataSync` from `BOOT_COMPLETED` at target 15+.
- [S48] https://developer.android.com/develop/background-work/services/fgs/timeout (2026-10-01): 6 h per 24 h limit, `onTimeout`, reset on foreground.
- [S49] https://developer.android.com/about/versions/16/behavior-changes-all (2026-10-01): JobScheduler quota changes affecting WorkManager; 16 KB compatibility mode.
- [S50] https://developer.android.com/about/versions/16/behavior-changes-16 (2026-10-01): orientation and resizability ignored at sw ≥ 600 dp, edge-to-edge opt-out removed, predictive back.
- [S51] https://developer.android.com/about/versions/17, https://developer.android.com/about/versions/17/behavior-changes-17 and https://developer.android.com/about/versions/17/behavior-changes-all (2026-10-01): Android 17 released, opt-out removed at API 37, app memory limits, background audio hardening.
- [S52] https://developer.android.com/google/play/requirements/target-sdk (2026-10-01) and https://support.google.com/googleplay/android-developer/answer/11926878: API 36 required from 2026-08-31, extension to 2026-11-01.
- [S53] https://developer.android.com/guide/practices/page-sizes (2026-09-16): 16 KB support required; updates blocked from 2027-02-01; AGP 8.5.1 and NDK r28.
- [S54] https://developer.android.com/jetpack/androidx/releases/camera (2026-08-27): versions 1.6.2 and 1.7.0-alpha03; 1.5.0 and 1.6.0 feature summaries; Media3 muxer crash resilience; minSdk 23.
- [S55] https://developer.android.com/media/camera/camerax/video-capture (2026-09-01): `QualitySelector`, `FallbackStrategy`, output options, `setFileSizeLimit`, `asPersistentRecording`, `VideoRecordEvent`, mirroring.
- [S56] CameraX reference: https://developer.android.com/reference/androidx/camera/video/VideoRecordEvent.Finalize (error codes and when a file is still produced), https://developer.android.com/reference/androidx/camera/core/CameraState (error list), https://developer.android.com/reference/androidx/camera/video/AudioStats (audio states), https://developer.android.com/reference/androidx/camera/core/SessionConfig and https://developer.android.com/reference/androidx/camera/core/SessionConfig.Builder (`setFrameRateRange`, preferred and required feature groups, low-light trade-off), https://developer.android.com/reference/androidx/camera/core/CameraInfo (`getSupportedFrameRateRanges(SessionConfig)`, `isSessionConfigSupported`), https://developer.android.com/reference/androidx/camera/core/featuregroup/GroupableFeature (`FPS_60` and others), https://developer.android.com/reference/androidx/camera/video/HighSpeedVideoSessionConfig (constraints), https://developer.android.com/reference/androidx/camera/video/Recorder and https://developer.android.com/reference/androidx/camera/video/Recorder.Builder (`setTargetVideoEncodingBitRate`, `setVideoMimeType`, `getHighSpeedVideoCapabilities`).
- [S57] https://developer.android.com/reference/android/os/PowerManager (2026-08-03): thermal status levels and API levels, headroom and thresholds, listener APIs.
- [S58] https://developer.android.com/jetpack/androidx/releases/media3 (2026-09-11): 1.11.1 latest, scrubbing mode added in 1.8.0, inspector `FrameExtractor` and `MetadataRetriever`, `media3-inspector-frame` from 1.10.0, minSdk 23 from 1.9.0.
- [S59] Media3 reference and source: https://developer.android.com/reference/androidx/media3/exoplayer/SeekParameters, https://github.com/androidx/media (`SeekParameters.java`: `DEFAULT = EXACT`), https://developer.android.com/reference/androidx/media3/exoplayer/ExoPlayer (`setScrubbingModeEnabled`, `setVideoFrameMetadataListener`, no frame-step API), https://developer.android.com/reference/androidx/media3/inspector/frame/FrameExtractor and https://developer.android.com/reference/androidx/media3/inspector/frame/FrameExtractor.Builder, https://developer.android.com/reference/androidx/media3/effect/OverlayEffect, https://developer.android.com/reference/androidx/media3/effect/TextOverlay.
- [S60] https://developer.android.com/media/media3/transformer/transformations (2026-09-08) and https://developer.android.com/media/media3/transformer/getting-started (2026-10-01): clipping, trim optimization, MP4 edit lists and pre-roll caveat, `Presentation`, `setRemoveAudio`, `getProgress`.
- [S61] https://developers.google.com/ml-kit/vision/pose-detection (2024-07-10) and https://developers.google.com/ml-kit/vision/pose-detection/android (2026-10-07): beta status, 33 landmarks, single person, face required, SDK sizes and fps, API 23, modes, hardware configs, 480×360 guidance, 18.0.0-beta5.
- [S62] https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker (2026-10-01) and https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker/android (2026-08-17): model bundles, `num_poses`, running modes, `detectForVideo`.
- [S63] https://developer.android.com/reference/android/media/MediaExtractor and https://developer.android.com/reference/android/media/MediaCodec (2026-08-03): extraction loop, async codec, PCM 16-bit and float, channel de-interleave.
- [S64] https://developer.android.com/training/data-storage/shared/photo-picker (2026-10-01): contracts, availability and backport, fallback, persistable URIs, 5,000-grant limit, HDR transcoding control.
- [S65] https://support.google.com/googleplay/android-developer/answer/14115180: Photo and Video Permissions policy, enforcement 2025-05-28.
- [S66] https://developer.android.com/training/data-storage (2026-10-01): app-specific files removed on uninstall versus MediaStore.
- [S67] Jetpack release pages: https://developer.android.com/jetpack/androidx/releases/navigation3 (1.2.0, 1.0.0 stable 2025-11-19), https://developer.android.com/jetpack/androidx/releases/navigation (2.10.2), https://developer.android.com/jetpack/androidx/releases/room (2.8.5, KMP, minSdk 23), https://developer.android.com/jetpack/androidx/releases/work (2.12.0, minSdk 24, no UIDT API), https://developer.android.com/develop/ui/compose/bom/bom-mapping (BOM 2026.09.00).
- [S68] https://developer.android.com/develop/ui/compose/testing (2026-10-01): `ui-test-junit4`, `createComposeRule`, `createAndroidComposeRule`, `ui-test-manifest`.
- [S69] https://github.com/mobile-dev-inc/maestro (README and releases; cli-2.11.0 on 2026-09-29): platforms, no physical iOS, Java 17, Maestro MCP.
- [S70] https://developer.android.com/studio/run/emulator-commandline (2026-10-05) and https://developer.android.com/studio/run/emulator-use-camera (2026-03-06): `-camera-back` modes including `videofile:` and `image360:`, virtual scene images, Android 11+ camera features.
- [S71] https://developer.android.com/developer-verification: verification timeline (2026-09-30 in four countries, global in 2027).
- [S72] https://developer.apple.com/app-store/review/guidelines/ (4.8 Login Services): scope of the equivalent-login requirement.
- [S73] https://forum.rclone.org/t/google-drive-changing-client-id-and-scope-drive-file-write-access/6693: a forum report, seen only as a search-result summary and not fetched, claiming a different OAuth client couldn't see earlier `drive.file` files. Contrary data, low authority.
- [S74] https://github.com/openid/AppAuth-Android (README, tags 0.11.1, last commit 2026-03-22): recommends custom-scheme redirects.
- [S75] Local inputs: `/Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md` (founder intent: record, upload to Google Drive, iOS then Android, emulator then device tests), `/Users/IDC2.5/jv/design-reference/brief/research.md` (prior research verified and extended in section 1), `/Users/IDC2.5/jv/design-reference/brief/product-brief.md` and `/Users/IDC2.5/jv/design-reference/brief/screens.json` (screens 4, 6, 7, 8, 13, 19, 20), `/Users/IDC2.5/jv/docs/handoff/CLAUDE-BUILD-PROMPT.md` (provider-independent manifests, Keychain, no raw video to AI by default), and the IDC domain doctrine rules file `~/.claude/rules/idc-domain-doctrine.md` (lane model, `sc-domain:islanddevcrew.com`, the `hello@` rule).
