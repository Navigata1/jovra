# SPEC review — bounded durable local export package

ACCEPT exact1b3e3b848d46f212d839eacd8343d06c5770b427 against main29eba0f. Read all90 LocalExportService lines,32 SessionStore.recordExports lines,153 public test lines and retained actual proof/limits. No reviewer Swift compiler or simulator run.

The service snapshots the authoritative actor document before rendering and before its own export records. DataExporter derives canonical JSON and both CSVs from that single snapshot; the clip range fits exactly one finalized original segment and subtracts its session start. Audio defaults off and record.includesAudio reports actual ClipExporter result. No originals are rewritten. Four uniquely named artifacts are written/flushed and directory identities synchronized before record publication. Cancellation/metadata failures leave unique unregistered work for inspection/retry, with no automatic overwrite or cleanup claim.

recordExports runs synchronously within the same SessionStore actor, reloads current state and merges only two export records; a correction during rendering therefore remains authoritative and historical eventLogVersion remains source max-seq. The seam checks owned regular path/size, duplicate IDs and version bounds before one durable write. It deliberately trusts the Media service's flush/decode contract; no untrusted-file/media-validation or physical-power-loss claim is made.

Independently reran verify_actual.py: both retained session documents pass shared schema/reference integrity and exact canonical bytes; historical snapshot A=1 vs current corrected B=1 and version1<2 verified; both CSVs equal independent Python goldens. FFprobe30frames/1second/noaudio and FFmpeg full decode pass. Recomputed all three source/test SHA hashes, matching source-custody.json. Read actual focused4tests PASS3.914s and genuine missing-API red evidence. Tests cover source preservation/concurrent reviewed correction, pre-rename metadata failure+nonoverwrite retry, invalid range and redirected exports folder.

Full package integration remains pending; this acceptance is bounded candidate behavior/source, not fullT36/Photos/Files/UI/background/relaunch/sharepack/whole-flow acceptance. These limits are explicit in producer README. No SPEC findings.

## Complete-package acceptance withdrawn pending corrective custody control

A concrete post-artifactsReady gap was identified by T02/root and confirmed by this reviewer: directory identity checks do not verify CSV presence, and the two export records verify only clip/JSON file paths. Deleting points.csv or stats.csv during the awaited callback can register Done while the four-file package is incomplete. Initial1b acceptance above remains historical happy-flow/source/artifact evidence, but complete-package SPEC acceptance is withdrawn pending a public deletion/same-sized-symlink RED→GREEN control and all-four owned regular file/expected-size checks at the synchronous atomic registration boundary. No reviewer source edits.

## Corrective SPEC rebind — 153915451ca60bd671eea7407ffec2b6045defbe

ACCEPT corrective source/actual focused behavior. The prior complete-package custody finding is closed: media supplies four distinct exact artifact references, recordExports checks all four owned regular/no-symlink paths and expected bytes inside the same synchronous actor metadata transaction, and both record references must belong to that set. Existing latest-document merge/version/identity behavior remains. No broad file-schema/media-validation engine introduced.

Read genuine07 RED three parameterized cases/six issues (points.csv deletion, stats.csv deletion, same-sized stats.csv symlink erroneously reachedDone) and08 GREEN5tests/seven cases4.580s. Recomputed all3 corrective source/test hashes matching source-custody.json. Prior1b receipt stays historical and withdrawal is retained; this corrective acceptance replaces it for bounded four-artifact presence custody. Full serial Media integration/fresh actual artifact proof still pending before final committed composition receipt. No reviewer compiler.

## Final committed composition SPEC rebind — 90ad922424760658e83235d23645acdd687bb724

ACCEPT bounded corrected local export package. Independently confirmed ios source/test diff15391545..90ad9224 empty and all three corrective hashes match. Read09 full serial Media90tests/16suites PASS34.717s, explicitly bound tested source15391545, and independently reran verifier against fresh actual-corrective-session rather than old1b artifacts: two shared schema/reference/canonical documents, Python CSV goldens, historical A1/current B1 version1<2, FFprobe30frames/1second/noaudio and FFmpeg full decode PASS. Old1b actual artifacts and withdrawal remain preserved.

Four-artifact custody gap is closed by genuine07 RED/08 GREEN and final integrated proof. No remaining SPEC finding in bounded range/snapshot/record registration. FullT36/UI/Photos/Files/background/relaunch/SharePack/finalCoreFlow and physical power-loss acceptance remain open. Exact final head receives this explicit rebind; no reviewer Swift compiler/native runtime.
