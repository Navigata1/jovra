# Independent final CoreFlow validation

**Bounded native CoreFlow and independent actual package checks PASS** at `73ce5c2f3627e3a599118d8b44ba66f2928bbd3f`. This final report validates a new real simulator session/package after the Export audit repair. `REPORT-FIRST-PACKAGE.md` and its failed-before-relaunch status remain unchanged; this final pass does not erase that earlier receipt.

Actual session: `FF2B8D99-74E2-405D-A991-A09762FE12FD`. Package: `exports/B5704F52-F6FA-4CA5-A06B-1E8F3D8AEC7A`. Custody/copies are retained in `../p4-coreflow-actual/final/`. The checker required the reference checkout HEAD equal the full native-tested SHA before importing the independent reference engine and schemas. No app/product edits or Swift builds were performed by this validator.

## Native receipt inspected

Root's `33-pan-core-flow-summary.txt` was independently read and copied to `07-final-native-summary.txt`: **CoreFlowUITests 1 plus ScrollViewportAuditTests 3 = 4 passed, 0 failed, 0 skipped, 0 expected failures**, in two recognized classes, result Passed. Device: JOVRA-Codex-T07 / iPhone 17 Pro / iOS Simulator 26.5, dedicated UDID `4265ADFD-39A3-4E71-8482-1945DDB5F899`; result bundle `.derivedData-replay/17-pan-core-flow.xcresult`. The native complete replay/export audit and relaunch behavior remain bound to this root-produced receipt, distinct from the independently executed artifact commands below.

## Independent actual results

- Persisted and exported session JSON are canonical and schema-valid, with zero cross-reference/time errors. Mandatory `Sample`, synthetic identity and `JOVRAFixtureCamera` generator are retained.
- Five history events retain original winners `A,A,A,B` and a fifth reviewed user correction to `B`, superseding the first point. Independent Python scoring fold yields four active slots `B,A,A,B`; the second server-first score-before is `0-15`. Side A points won is exactly `2/4` = `50%`.
- `points.csv` and `stats.csv` match the independently regenerated fold/stats CSV bytes exactly, using the published handwritten contracts: column order, null/booleans, minimal quoting, UTF-8 without BOM and LF endings. Exported immutable JSON differs from persisted JSON only by the two export records added afterward.
- Exactly four regular files exist. Both persisted records are local `done`, eventLogVersion 5, audio off; registered kind/path/MIME/size and clip range `0..1000ms` match the real package.
- Raw original before/after SHA256 matches: `5061fe1c91bbc6ff7b7e3d6c23eb3aea5e9ef538bf38fe1bdbb646ab169eadaf`. Custody observed exports empty at `2026-10-09T19:32:26.552804+00:00`, before both done records at `2026-10-09T19:34:56+00:00`. The original's actual file size matches its document reference.
- FFprobe counted **30 frames**, **30 fps**, **1 second**, **zero audio tracks**. FFmpeg completely decoded original and clip using `-xerror` without reported decode errors. All thirty binary frame counters decoded as **0 through 29**, proving the intended fixture prefix rather than container duration alone.
- In-memory negative controls based on this actual session refused an unknown schema field and dangling correction target. No source fixture or exported output was fabricated.

| File | Bytes | SHA256 |
| --- | ---: | --- |
| clip.mp4 | 29091 | d4be94c3369338f29aa68797ead90afa519239acd66b66bff82ff0491e33a138 |
| points.csv | 866 | dc014e95e55d1b7d85fa81c53f8649238dcff3c4b11c68607798a0f0d2210f2e |
| session.json | 2590 | 0b96ae44cf97db2adbca6f772424c08c29d542118fc4612d6f4aae52d8fc1987 |
| stats.csv | 1650 | 311c4197b76a5c2a853546705fb44b0c1b66c00bc27e3c09ab11213a2f121388 |

## Exact executed commands

Both commands exited 0; stdout JSON and empty stderr receipts are retained as `04-final-package-artifacts.*` and `05-final-package-video.*`. The video stdout includes its exact underlying FFprobe/full-decode/raw-counter commands.

```sh
python3 /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/evidence/p4-independent-coreflow/check_artifacts.py --repo /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/implementation/reviewed-replay --session-dir /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/evidence/p4-coreflow-actual/final/FF2B8D99-74E2-405D-A991-A09762FE12FD --package-dir /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/evidence/p4-coreflow-actual/final/FF2B8D99-74E2-405D-A991-A09762FE12FD/exports/B5704F52-F6FA-4CA5-A06B-1E8F3D8AEC7A --tested-sha 73ce5c2f3627e3a599118d8b44ba66f2928bbd3f --original-before-sha256 5061fe1c91bbc6ff7b7e3d6c23eb3aea5e9ef538bf38fe1bdbb646ab169eadaf
```

```sh
python3 /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/evidence/p4-independent-coreflow/check_video.py --repo /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/implementation/reviewed-replay --original /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/evidence/p4-coreflow-actual/final/FF2B8D99-74E2-405D-A991-A09762FE12FD/originals/segment-0.mp4 --clip /Users/IDC2.5/.codex/worktrees/jovra-core-continuation/evidence/p4-coreflow-actual/final/FF2B8D99-74E2-405D-A991-A09762FE12FD/exports/B5704F52-F6FA-4CA5-A06B-1E8F3D8AEC7A/clip.mp4 --decoder-lease-released
```

Additional custody timing: `06-final-package-custody-timing.json`. Native summary: `07-final-native-summary.txt`. Decoder/compiler/simulator lease was explicitly released immediately after command completion; no background decoder remains.

## Limits and remaining gates

This acceptance covers the bounded local native record/save/library/replay/review/correction/export/relaunch flow using synthetic simulator footage. It is not full-ticket closure, real-tennis model accuracy, physical camera/hardware testing, iOS 18 runtime, or production/store readiness. Independent full native receipt custody, Standards/Spec review of any later changed head, and successful remote CI remain separate gates. GitHub billing has prevented CI jobs from starting. Studio/cloud, Android/foldables/watch expansion and step 5 remain held. No CI or accessibility failure was waived.
