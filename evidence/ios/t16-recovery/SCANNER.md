# Finished-stale capture recovery slice

This bounded scanner recovers a finished AVAssetWriter recording whose final store handoff failed. It decodes every video frame, reconciles actual media metadata/hashes, refuses corrupt timestamps/overlapping gaps and isolates broken session peers. The raw journal and originals remain byte-identical; a separate canonical receipt fingerprints those inputs. Repeated scanning and atomic adoption preserve receipt timestamp and session bytes.

## Evidence

14: genuine public missing-API red. 15: first green attempt failed because this isolated worktree had no fixture cache (setup failure, not a behavioral red). 16: copied authorized fixture cache and all19 rendered hashes independently checked. 17: unchanged-source actual60-frame finished-stale public test passed. 18: activated corruption red12issues (negative/future marks and overlapping gaps improperly accepted; broken media peer isolation passed). 19: minimal production time guards, three public tests including six corruption parameters passed; authentic2s recording decoded independently to60frames. 20: retained adopted session passed independent Python schema and exact canonical byte checks; separate receipt canonical bytes passed. 21: ffprobe independently read h2641280x720,30fps,2seconds,60decodedframes. Actual raw journal/movie, receipt and adopted document are retained in actual-finished-stale/.

Commands: `swift test --package-path ios/Packages/JovraMedia --scratch-path ../media-stack/.build/stack-media -j 2 --filter 'finishedJournalWithFailedFinalHandoff|corruptLedgerTimesCannotBeAdoptedAsVerifiedCapture|brokenMediaPeersAreExplicitlyRefusedWithoutHidingHealthyCapture'`; artifact retention used JOVRA_RECOVERY_EVIDENCE_DIR. Python used scripts/spec/jsonschema_subset.SchemaSet and canonical_json.canonicalize, independently of Swift. ffprobe used -count_frames.

## Scope remaining

Not fullT16: unfinished/torn media explicitly refused. Actual process kill/loss bound, salvage of partially written fragments, mixed segment recovery, media-service reset, native startup wiring, and physical power-loss/device evidence remain pending. Internal receipt format1 is not advertised as a shared JSON-schema contract. Raw invalid peer sentinel is explicitly not captured/playable footage.

The generated structural Codable boundary is not full JSON Schema runtime validation. This slice checks actual writer-produced snapshots, media reconciliation and the specifically activated mark/gap/event guards. Arbitrary corrupt mark IDs/note/provenance and copied file metadata constraints remain unresolved for full untrusted-WAL acceptance; no universal corruption-validation claim is made. A general validation engine is not introduced here.

## Independent review corrections

T07 Spec found captureEvents were copied without semantic guards. Activated five additional corruption parameters: negative/future event times, absent frame-rate/thermal payload and zero frame-rate numerator. Evidence22 actual16-issue RED comprises these15issues and the real captured-mark producer assertion. Added eight guard lines; evidence24 GREEN4public tests with11corruption parameters.

Reading the shared provenance schema exposed a published T15 mark producer mismatch. A real FixtureCamera/AVAssetWriter captured point, recovered and atomically adopted, independently failed Python schema at marks[0].provenance.source=captureMark (23). The one-line writer correction to source=user preserved manual status, timestamp/note and Sample=true. Authentic before/after session/movie/WAL/receipt retained in actual-marked-schema-{red,green}/. After fix, both unmarked/marked actual adopted sessions passed independent schema and exact canonical bytes (25). Broader arbitrary copied-WAL field schema constraints remain explicitly unresolved above.
