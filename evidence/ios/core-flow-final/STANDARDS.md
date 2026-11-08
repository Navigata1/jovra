# Native visible Replay — independent Standards review

Candidate: `d407fd5e77e28ee07c61016d0df62d7a2dabb8ac`.
Fixed point resolved: `8d2fe9fed5f9e623306e0a86650102dce204d821`.
Scope: ReplayScreen, owned Replay catalog and five-line navigation placeholder adaptation. Interleaved Capture/Library changes are separately owned prerequisites. ReplayFlowUITests was introduced before this fixed point (78e315c), and is tracked in the candidate tree. Reviewer initially misclassified absence from the feature diff as untracked; independently corrected with git cat-file -e, git ls-files and empty candidate-to-working-test diff. No reviewer compiler/runtime.

## Findings

**P2 documented honesty rule — local Sample labels.** `ReplayScreen.swift:32` is the only Sample badge. It scrolls out before lower selected-score and derived-stat blocks (`120–132`, `168–177`) remain onscreen; those blocks display only provenance. CLAUDE.md hard rule 1 requires visibly labelled Sample/demo data and separates Sample from provenance. Render a Sample badge beside the selected score when the document is synthetic, and beside each derived-stat readout when its evidence.sample is true. A badge only at the start of this long decisions card can itself disappear above the metric viewport. Preserve Manual/Reviewed provenance rather than replacing it with Sample.

No other documented breaches or Fowler heuristic findings in the bounded hunks. Named Replay catalog keys and JovraFormat keep words/counts locale-aware; unknown serve/shot values remain dashes. Same actor-backed models refold stored decisions instead of patching score/stat truth. Minimum-size button styles, native accessible inputs, adaptive transport layout and readonly video stepping are sensible source choices; they do not establish runtime accessibility success. Route metadata/test adaptation faithfully replaces the placeholder without changing the route/initializer.

**Standards HOLD d407 for this one narrow Sample finding.** Current native UI run13466 is author-owned and pending at review; no green, rendered-screen or full T28/T29/CoreFlow/device/step5 acceptance is inferred. Final acceptance must rebind corrected source and actual runtime/test custody.


Custody correction: the original message incorrectly described ReplayFlowUITests as untracked. Candidate-tree existence and unchanged working bytes were independently verified; the actual d407 author receipt can bind that public test. This correction does not remove the local Sample finding. Root reports native08 actual1/0/0 on d407; corrected Sample source still needs its own final gate.


## Corrective Standards review cd3783d

Exact source: `cd3783d4bdb31bdb1299b1df61a13cd852420fe1`; narrow diff from its parent inspected independently. No reviewer build or simulator operation.

The prior P2 Sample finding is closed in source: selected-score receives a SampleBadge when the stored document is synthetic, points-won uses its own evidence.sample, and the shared stat readout labels each derived stat from its own evidence.sample. Each badge sits directly beside its number and preserves the existing Manual/Reviewed provenance badge. Unknown readouts remain dashes rather than fabricated metrics. Native owned SampleBadge supplies established localized accessible copy; the three bounded insertions add no new persistence, scoring or navigation behavior.

Zero remaining documented-standard breaches; zero Fowler heuristic findings in this corrective delta. **Standards source ACCEPT cd3783d**, qualified to the bounded visible Replay source. Root reports genuine nearby-badge public RED (missing score Sample badge); final corrected native/CoreFlow/runtime receipt and source rebind remain pending. Historical d407 finding and test-custody correction are preserved above; no whole T28/T29/device/step5 acceptance is inferred.


## Composed foreground audit source 2817596

Independently reviewed `28175960dc329904410e68728c929caf7c1dd876`. The actual first CoreFlow failure clips Point 1 at the bottom safe area despite its larger reported scroll frame; composed replay viewport alignment then passes the Replay audit. The second failure reaches real four-file export/two done records but samples Clip export title under its fixed header, while the harness globally chooses the underlying Replay scroll. Those failed receipts remain failed.

The corrective source uses explicit replay.scroll/export.scroll surfaces and passes one selected scroll element through scoped title/settling marker, swipes, ancestry membership and repeat. Existing audit exclusions/types/thresholds are unchanged. Container-bottom rendering matches reported viewport while 32pt trailing content padding is preserved. This is a precise measurement-target fix rather than an accessibility waiver; actual final UI receipt remains pending.

One narrow evidence guard recommended: explicit requested-surface mode should also fail if its scoped screen.title is absent, instead of stopping after the initial viewport audit. Current fallback behavior for unnamed screens need not change. Native/compiler/decoder remain author-owned; no independent runtime claim or wholeflow/device acceptance yet.


## Final foreground source Standards ec720e8

Exact corrective source `ec720e8972d7aa34e35166febe297078e2019b76`, independently read against 2817596. Explicit foreground-mode missing scroll and missing scoped title now fail before an incomplete surface audit can be mistaken for success. One identified scroll/title is retained throughout settling, swipes, membership and repeat. Both current identified consumers are modal Replay/Export surfaces: hidden background tab geometry no longer defines their visible bounds or Dynamic Type exception frame. Existing unnamed-tab behavior remains unchanged.

All audit issue types, exclusion rules and numeric thresholds remain intact; no generic issue suppression or feature-label waiver was introduced. The preceding component changes preserve adjacent Sample/provenance labels and 32pt trailing content padding; component diff 281→ec is empty. Zero remaining documented-standard breaches and zero Fowler heuristic findings in this bounded corrective source. **Standards source ACCEPT ec720e8**; source acceptance does not establish current-head runtime success. Fresh final ec native screen/audit/relaunch/CoreFlow and actual artifact validation receipts remain pending; prior failed CoreFlow attempts remain failed. No reviewer compiler/decoder/simulator use, hosted merge/CI waiver, device/store/full-feature/step5 acceptance.


## Measured modal gestures — source ACCEPT6a / helper slice e318

Independently inspected `6a04542740f8856be581b976694a555e07b7a9fb` and helper-only `e3183344bbd68fd529f291783fbc370b9ab54052` against approved main444bf717. Only AccessibilityAuditing.swift changes in the helper slice; its complete bytes equal6a (SHA256 de464eb37f269c1151d74d9e356e65df55d5c582a16dd54278827ddf83174047).

Named foreground scrolling now measures remaining title offset before each downward gesture, stops at the top, caps a slow drag at 45% of the actual viewport, settles afterward and explicitly fails after 12 unsuccessful attempts. This directly fixes the retained failed run where three blind fast downs dismissed the idle system Export sheet after its first audit had passed. Default unnamed scrolling remains unchanged. The full 0..6 upward audit coverage, issue types, exclusion policy, thresholds, foreground membership and title guards remain unchanged; no app dismissal lock or failure waiver.

Zero documented-standard breaches; zero Fowler heuristic findings. **Standards source ACCEPT 6a and explicit helper-slice source ACCEPT e318**. Current fresh native CoreFlow and existing three viewport-unit tests remain pending; prior ec receipt remains failed and is not relabelled as a pass. Source identity does not transfer a passing runtime SHA. No reviewer compiler/decoder/simulator, hosted merge/CI waiver, physical-device/store/full-feature/step5 acceptance.


## Final bounded native receipt and helper source ACCEPT73 /296

Reviewed exact UI/runtime source `73ce5c2f3627e3a599118d8b44ba66f2928bbd3f` and helper-only source `296ec4bff2f5989430ce5828d058d62d3ff5735e`. Complete helper bytes are equal (SHA256 161ca055480d34b0832f0a61566766bbf6ac4cf6e3217f45b714b5ff0ac26d60). The two-line correction adds 16pt for actual observed pan initiation, retaining the measured remaining offset, 45% viewport cap, top<=1 stop, settling and 12-attempt explicit failure. Default behavior and all audit types/exclusions/thresholds are unchanged. Zero documented-standard breaches; zero Fowler heuristic findings.

Independently queried raw `.derivedData-replay/17-pan-core-flow.xcresult`: Passed 4, Failed 0, Skipped 0, ExpectedFailures 0 on iPhone 17 Pro/iOS Simulator 26.5; recognized CoreFlow testcase 207.771s plus the three viewport controls. Raw owner log reports 219.751s total. The tracked public test records through FixtureCamera, opens actual saved Library row, decodes frame 1, appends four decisions, corrects the first winner, asserts later 0–15 / A 2 of 4 and local Sample/unknown labels, types 0..1000 export, asserts Done and enabled Share, audits both named surfaces, closes/relaunches and reopens persisted corrected score. Negative viewport controls still reject visible/fixed/text-clipping/semantic findings. Prior 13/15/16 failures remain failed.

Both extracted screenshots were visually inspected: Sample/range controls and four corrected point labels are legible. The export-finished attachment remains scrolled at inputs/Create; Done/Share lie below its captured viewport. Acceptance relies on actual testcase+full audit, not a claim that this PNG visually displays the Done card.

**Standards ACCEPT bounded UI 73 and explicit helper-source 296**, with native proof bound 73, not transferred to later publication heads. Independent actual four-file/schema/video checker is T07-owned and pending at this review. No share-target delivery, device/store/full T28/T29/T36/step5 or hosted-green/merge waiver.
