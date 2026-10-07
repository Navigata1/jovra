# Studio implementation states and exact data rules

These are implementation requirements, not claims that the pictured states are live. All raster references contain fictional people/footage/data. Reference QR patterns are decorative and must be replaced by generated, expiring invitation codes in the app.

## Navigation and visual invariants

Keep the JOVRA Court Arc JV mark, warm ivory #F4F1E8, forest #092A25, panel #123C33, chartreuse #D7F56A and clay #C47752. Native five tabs: Home, Sessions, Record, Insights, Profile. Studio is reached from Home, a session, or Insights. Landscape workspaces may have contextual editing navigation. No sixth mandatory mobile tab and no replacing Profile with Studio.

Reference typography is visual intent; implement native text, Dynamic Type and accessibility labels. Raster images are not production interactive controls. Court geometry and score displays are generated from code and versioned rules, not copied from approximate photographic lines.

## Required state map

| Reference | Normal state | Required alternatives |
|---|---|---|
| 21 Studio Home | Latest film, lesson entry, Build your match | No films; first session; local demo; cloud unavailable; last job failed |
| 22 Court setup | 1 primary, up to 5 optional placements | One angle; occupied role; unsafe placement hint; camera capability unavailable |
| 23 Camera lobby | 2 ready, 1 waiting in sample | Host/guest; QR expired; invite revoked; role full; reconnect; permission denied; storage/thermal warning |
| 24 Director capture | Primary live, secondary aged stills | Missing acknowledgement; device disconnected; no microphone; unavailable preview; low battery/space; interruption; host exits |
| 25 Source import | 3 × 3.6 GB = 10.8 GB sample | One old match; no audio; unsupported/invalid media; duplicate file; partial source; mixed dimensions/FPS; insufficient working space |
| 26 Sync | Estimated offset/drift, review controls | Manual markers; failed alignment; no shared coverage; drift; gap/restart; muted source; normalized proxy; needs review |
| 27 Broadcast/replay | Multi-angle review, corrected event-derived score | One angle; missing angle at this time; buffering; uncertain sync; score unknown; offline; stale film after correction |
| 28 Angle insight | Estimated observation with source | Manual note; Reviewed cue; unsupported capability; occluded body/ball; no calibration; rejected observation |
| 29 Story modes | Five profiles and optional length | No relevant keepers; profile needs notes; quote unavailable; local draft; no music rights |
| 30 Coach’s Cut | Reviewed example and next drill | Unknown stat; manual cue; rejected cue; no drill; labelled replay; original-speed fallback |
| 31 Rally Pulse | Full rallies, optional effects | Reduced Motion; clean alternate; no licensed music; clip too short; contact frames protected |
| 32 Progress Story | Comparable dated 12/30 → 18/30 | No earlier evidence; method change; differing sample selection; no measurable change; manual reflection only |
| 33 Court Memories | Real B-roll, original sound | One source; no B-roll; venue hidden; personal caption omitted; no natural audio |
| 34 Lesson journal | Dated notes, linked clips and practice | Empty; offline; missing/deleted clip; private coach share; export; manual lesson |
| 35 Lesson workspace | Clip-linked notes and checklist | Unreviewed note; unsaved edits; source unavailable; permission revoked; conflicted sync |
| 36 Storyboard | Versioned source-bound edit | Invalid window; gap; unsupported effect; missing audio rights; older point revision; pending plan approval; rebuild |
| 37 Preflight | Sample quote, consent unchecked | Demo disabled charge; real quote expired; not signed in; cost above cap; no cloud consent; retention choice; local replay |
| 38 Job queue | Upload done, alignment done, film active | Paused; resumed; retryable/terminal failure; canceled; budget exhausted; notification unavailable; app suspended |
| 39 Delivery | Private film, download, lesson, YouTube preparation | Still verifying; failed full decode; expired link; access revoked; partial download; old version; archive disconnected |
| 40 Settings | Local demo, optional providers and privacy | Real auth/test/live; disconnect/reconnect; token expired; provider planned/unavailable; deletion running/failed; data export |

## Sample source of truth

The screenshots illustrate several deliberately distinct flows, not one live job. Implementation fixtures must distinguish their identities.

- Match sample: Jon vs Alex; final set rows Jon [6,6], Alex [4,3]. No live point score is implied on a completed match. Store point events that actually produce this score before displaying it in a functioning demo.
- Import sample: three 60-minute sources at assumed 8 Mbps each: 3.6 GB, 10.8 GB total; file-size math excludes audio/container overhead.
- Sync sample: Camera 2 offset +120 ms and drift 18 ms/min. These are estimates for UI layout, not measured field results. Assign them to the selected source, not every angle.
- Lesson fixture: September 9, 2026 First serve foundation (4 clips); September 23 Recovery step (2 clips); October 7 Serve rhythm (3 clips). Current practice: 10 shadow serves done, 20 target serves done, review five clips pending. A drill’s five-clip goal is allowed even while only three lesson clips have been saved.
- Progress fixture: September 9 12/30 = 40%; October 7 18/30 = 60%; +20 percentage points, over two reviewed sessions. Same metric definition and method; explicitly Sample.
- Court Memories sample finished film: 04:18 = 258 seconds; 1080p; 412 MB is an illustrative file size. Chapter durations in screen 33: Arrival 00:42, Match 02:21, Moment after 01:15, summing 04:18. The advanced storyboard illustrates a different draft arrangement of the same target length; do not treat its chapter boundaries as the finished film’s three chapter durations.
- Storyboard selected source window: 00:12.400–00:18.600 = 6.2 seconds. Draft output placement: 00:12.000–00:18.200 at 1×. Exact boundaries live in the EDL; scale the timeline accurately in code.
- Queue fixture: current one-match project, three sources; Upload complete, Align complete/reviewed, Build film active, Verify queued; 42% is a sample stage progress, not a computed total-job percentage.
- Quote fixture: $4–$8 estimate and $12 cap are illustrative UX. Never charge those amounts or label them a real provider quote without a current priced estimate and accepted reservation.
- Provider fixtures: device active; iCloud Drive folder choice; Google Drive not connected; Box/Dropbox planned. Local demo has no live token, billing or uploads. Cloud switch off.

## Auxiliary sheets and alerts beyond the twenty references

Include camera/microphone/Photos/Files/local-network permissions; real recording acknowledgement; one-device stop versus all-device stop; missing-file repair; consent per selected source; source/draft delete versus original delete; quote expiry/reprice; budget limit; partial upload retry; manual sync markers; invite/access expiry; cloud sign-in and sign-out; preview feedback; film revision selection; caption correction; account export/deletion; provider scope explanation; download recovery; YouTube channel/privacy confirmation when wired.

No extra raster was created for each alert. Use the established design components and the state map to implement them; do not invent backend readiness from a screen.

## Production visual gate

Use accurate deterministic tennis court geometry. Re-render scores from events. Use actual video stills and waveform data in the app. Review real footage, cues, overlays and audio. If any generated visual diagram or timestamp is imperfect, the written source/time/event contract wins. Mockup photography is not evidence of synchronized recordings, inference or a completed export.

