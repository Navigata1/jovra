# T08 capture custody independent review

Pinned final source: `0826232fc033fee7408859f723354ec2aabb4ac5` (fresh detached checkout).

## Standards
No blocking documented-standard or actionable baseline-smell finding in the bounded custody API and recursive backup follow-up. Local source stays within SessionStore and MediaLibrary. No native app, simulator, or physical-device validation is claimed.

## Spec / public boundary controls
- Recursive backup opt-in clears explicitly excluded original files and nested directories, retaining metadata in device backup.
- Injected metadata failures before and after atomic rename keep effective flags aligned with whichever document actually committed.
- Nested symbolic links are refused before touching external media bytes or backup flags; file lookup refuses them too.
- A prewrite out-of-space capture handoff leaves session metadata byte-identical. Retry commits recording, durable marks, storage/original facets, and Sample together; an existing user-edited mark wins over its stale journal duplicate. Confirmed media becomes `onDevice` and preserves backup opt-in.

The original `3a92267` implementation failed two recursive backup assertions (`01-backup-control.txt`). Root fixed this at `cfb2738`. Three independent Media controls passed at both fixed and final heads (`03` and `06`). Two final Core controls are recorded in `07-final-confirmed-media-controls.txt`.

`05-final-atomic-controls.txt` preserves a reviewer construction error: it expected on-device media from the old imported fixture's recording, which has no confirmed camera segment. The corrected control constructs an explicit finalized 2-second camera segment with `mediaAvailable=true`; this does not establish file decodability and is solely the atomic document handoff test. Real capture decoding remains independently covered by T15.

Tests and probes were added only in this isolated reviewer checkout; their exact patch is retained as `independent-controls-final.patch`, then source is restored. Full root suites and CI are separate evidence; I reran only meaningful focused public controls after the four-line follow-up. No hosted integration or backup-service restoration was performed.

Verdict: ACCEPT the bounded source and custody seam, subject to green exact-head CI. This does not close all of T08 or establish physical-device backup behavior.
