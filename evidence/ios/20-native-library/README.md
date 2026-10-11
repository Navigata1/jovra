# Bounded native Library handoff

Frozen source 7624e6c990fe97c8ce2124b6371b968f120feac8 replaces the Sessions placeholder with real folder-derived metadata from the same LocalCaptureLibrary actor, loading/error/retry/empty states, and All/Matches/Practice filters. Only a sink-confirmed saved recording shows Open library. Real row IDs open Replay with the same session ID, including an empty log. Stored recording status is explicitly metadata; actual media presence/playability is verified by Replay. Missing optional facets remain unavailable rather than inferred.

Matches intentionally groups match/tiebreakOnly/practiceSet (scored kinds), with a visible scored-practice disclosure; Practice groups the five remaining concrete kinds. No schema case is added. A per-reload UUID plus cancellation check makes the latest request authoritative even for independent refresh/retry tasks. New copy belongs to Sessions.Library; the existing Sessions table is byte-identical to the Capture base.

## Actual proof and retained failures

- Public RED 01: actual unique-title fixture capture reached Saved, then line 23 failed waiting for absent capture.openLibrary. Failed 0/1/0,35.713 seconds. The outer shell footer initially used reserved zsh status; xcodebuild already recorded TEST FAILED and the fail-closed summary was run separately.
- First implementation 03: compile failure, zero executed tests (State shadowing SwiftUI.State and no .practice schema case). No runtime acceptance.
- Corrective 04 on 7e: real capture/save/CTA/relaunch/Sample/filter changes and full hit/audit completed; final generic screen.title query was ambiguous between visible Smart replay and underlying Your sessions. Overall Failed 0/1/0,171.844 seconds remains retained. The repair uses the existing constrained heading helper and does not change app behavior or waive an audit.
- Ownership 08 correctly refused an edit to unowned Sessions. New keys moved into owned Sessions.Library; original table restored. Final 10 localization 32+12 tool tests/literal 0/copy 0/one owned catalog 0 problems passed.
- Final 11 on source 7624: Passed 2/0/0,308.042 seconds on dedicated JOVRA-Codex-T07 4265ADFD-39A3-4E71-8482-1945DDB5F899,iPhone 17 Pro/iOS 26.5. Real retained-session AX5 audit/hit/row tap and fresh actual capture/save/CTA/relaunch/Sample/Practice→Matches→All/full normal audit/constrained Replay heading all executed. This is a new passing receipt rather than a relabelled failure. Tracked iOS diff from tested source was empty.

Final actual capture snapshot title Library 565124FE, SHA-256 b2020c711c1cc27805218161ff39cf1ef49d28128779c0316725652afd631b93, has canonical bytes, zero session-schema errors, one segment, saved original facet and mandatory JOVRAFixtureCamera Sample. No real tennis footage or device camera was used. Named normal/AX5 PNGs were visually inspected. Raw xcresults stay local. Independent Standards and Spec receipts accept the bounded source and actual 2-test runtime separately.

Full T20 search/import/trash/quarantine/overview/verified location and backup facets, the genuine final CoreFlow gate, physical devices and iOS 18 runtime remain pending. Step 5 is held. GitHub billing prevents remote CI from starting; no merge or CI waiver is implied.
