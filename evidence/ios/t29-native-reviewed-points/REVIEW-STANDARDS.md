# Native reviewed-point model — independent Standards review

Pinned candidate: `a7e53e8967cb81bb07095c6ece2e11f37f13fc84`.
Fixed point: `240ebd47bc72ff8a19b575acd900bf12a92503e7`.
Scope: ReviewedPointModel.swift, eight LocalCaptureLibrary delegation lines, ReviewedPointModelTests.swift. Read-only reviewer; no native compiler/runtime invoked.

## Findings

1. **Documented localization rule (P2).** `ReviewedPointModel.swift:31,48,74` embeds display English ("Deuce", "Deciding point", and error messages) in ordinary strings. `docs/DEVELOPING.md:170–173` requires explicitly named String Catalog tables. These property names evade the literal lint, so this is not a duplicate tooling finding. Prefer typed call/error state rendered by the upcoming localized view, or explicit localized resources here. Preserve the uncertainty of the unconfirmed-write error.
2. **Documented number-formatting rule (P2).** `ReviewedPointModel.swift:24,30` interpolates numerator/denominator and tie-break counts directly into display strings. `docs/DEVELOPING.md:175–177` requires JovraFormat for numbers. Expose typed values to the view or use the shared locale-aware formatter. Ordinary 0/15/30/40 enum score tokens are domain notation; this finding targets variable integer counts.

No additional documented-standard breaches or Fowler baseline heuristic findings. Shared actor wrappers maintain the existing native service boundary; they are not a new speculative middle-man abstraction. The model uses one fresh scoring/stat fold, separate mutation/history ownership, generation guards and honest nil values.

## Evidence and limits

Independently SHA-256 checked all three source/test blobs against source-custody.json: all MATCH. Read actual 04 native summary: three passed, zero failed/skipped in two classes; this is author simulator evidence, not a reviewer execution. Genuine missing-type RED and failed shadowed-error compile are retained. The source remains a bounded model seam; no reviewed-point UI, whole T29 acceptance, physical-device acceptance or step5 authorization follows.

**Verdict: HOLD Standards acceptance for the two narrow presentation-standard corrections.** Numerical/spec acceptance is owned by the independent Spec reviewer.


## Corrective and publication rebind — ACCEPT

Corrective tested source: `6f4d9b2ef36a1372038d7dcd8b9cfd9833f33027`.
Publication candidate: `f740e2e1a5dfc72c3bdb61df1eb7ab0bf330eb1c`.

Independently inspected the exact corrective model/catalog diff: both P2 findings are closed. Reviewed-point score words and error messages now use `String(localized:table: "Replay")`; the new owned Replay catalog contains each key, including the interpolated frame-status key. Variable fraction/tie-break/frame-count/rational-rate values use shared JovraFormat.count, preserving domain notation and core math. The merged readonly playback model's pre-UI display/error strings receive the same narrow correction. No additional documented breaches or Fowler heuristic findings.

Independently verified an empty `git diff 6f4d9b2..f740e2e -- ios` and all five manifest source/test/catalog hashes MATCH. Read actual 07 owned-catalog receipt: literal/copy/ownership checks pass. Read actual 08 localized native summary: three passed, zero failed/skipped on the dedicated iPhone17Pro/iOS26.5 simulator. This runtime receipt remains bound to 6f4d9b2; it is not relabelled as a reviewer run or publication-head execution.

Final bounded **Standards ACCEPT f740e2e1a5dfc72c3bdb61df1eb7ab0bf330eb1c**. Original a7 HOLD and original native receipts above remain historical. Whole T29/UI, physical-device, finalCoreFlow and step5 remain outside this acceptance.
