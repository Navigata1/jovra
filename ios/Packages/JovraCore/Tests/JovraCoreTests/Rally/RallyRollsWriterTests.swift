import Foundation
import Testing
import JovraCore

/// Story 195: per-session and per-clip pre/post-roll, written by JovraCore. The expected bytes are the session the
/// Python reference wrote with the same edits (spec/fixtures/rally/session.rolls.json); CI's native-data-export job
/// re-validates the Swift-written document with scripts/spec/validate.py --encoded-dir.
@Suite("Rally rolls are written into the session document")
struct RallyRollsWriterTests {
    static let relativePath = "spec/fixtures/rally/session.rolls.json"

    static func committed() throws -> (data: Data, document: SessionDocument) {
        let url = try FixtureManifest.repository().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return (data, try ContractCodec.decode(SessionDocument.self, from: data))
    }

    /// The committed session with its rolls removed: what the player had before opening Playback settings.
    static func base() throws -> SessionDocument {
        var document = try committed().document
        document.rallyPlayback = nil
        return document
    }

    @Test("Playback settings and the Rallies list produce the reference document byte for byte")
    func writerMatchesReference() throws {
        let written = try Self.base()
            .settingRallyRolls(preRollMs: 2_000, postRollMs: 3_000)
            .settingClipRolls(targetId: "rp-point-2", preRollMs: 500)
            .settingClipRolls(targetId: "rp-mark-1", postRollMs: 4_000)
            .settingClipExcluded(targetId: "rp-point-3", true)
        let bytes = try CanonicalJSON.encode(written)
        #expect(bytes == (try CanonicalJSON.canonicalize(Self.committed().data)))
        if let directory = ProcessInfo.processInfo.environment["JOVRA_DATA_EXPORT_OUTPUT_DIR"] {
            let target = URL(fileURLWithPath: directory).appendingPathComponent(Self.relativePath)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: target, options: .atomic)
        }
    }

    @Test("the plan built from the written rolls honours the per-session and per-clip values")
    func planUsesWrittenRolls() throws {
        let rolls = try Self.committed().document.rallyPlayback
        let targets = [RallyTarget(targetId: "rp-point-1", startMs: 30_000, endMs: 38_000),
                       RallyTarget(targetId: "rp-point-2", startMs: 52_000, endMs: 61_000),
                       RallyTarget(targetId: "rp-point-3", startMs: 80_000, endMs: 95_000),
                       RallyTarget(targetId: "rp-mark-1", startMs: 100_000, endMs: 100_000)]
        let plan = try RallyOnlyPlan.build(targets: targets, rolls: rolls, durationMs: 120_000)
        // Worked by hand: 2 s / 3 s around point 1, 0.5 s / 3 s around point 2, point 3 deselected, 2 s / 4 s around the mark.
        #expect(plan.ranges.map(\.range) == [MediaRange(fromMs: 28_000, toMs: 41_000), MediaRange(fromMs: 51_500, toMs: 64_000),
                                             MediaRange(fromMs: 98_000, toMs: 104_000)])
        #expect(plan.excludedTargetIds == ["rp-point-3"])
        #expect(plan.gaps.map(\.label) == ["+0:28", "+0:10", "+0:34", "+0:16"])
    }

    @Test("session rolls are 0-5 s in 0.5 s steps", arguments: [(5_500, 0), (1_250, 2_500), (-500, 2_500), (0, 5_001)])
    func sessionRollSteps(pre: Int, post: Int) throws {
        #expect(throws: RallyError.rollOutOfRange) { try Self.base().settingRallyRolls(preRollMs: pre, postRollMs: post) }
    }

    @Test("a clip override must name a point or mark of this session")
    func unknownTarget() throws {
        #expect(throws: RallyError.unknownTarget) { try Self.base().settingClipRolls(targetId: "nope", preRollMs: 500) }
        #expect(throws: RallyError.rollOutOfRange) { try Self.base().settingClipRolls(targetId: "rp-point-1", postRollMs: 10_001) }
    }

    @Test("the first clip edit starts from the default rolls; reselecting keeps the entry without the flag")
    func firstClipEdit() throws {
        let edited = try Self.base().settingClipExcluded(targetId: "rp-mark-1", true)
        #expect(edited.rallyPlayback == SessionRallyPlayback(preRollMs: 1_500, postRollMs: 2_500,
                                                             clips: [.init(targetId: "rp-mark-1", excluded: true)]))
        let restored = try edited.settingClipExcluded(targetId: "rp-mark-1", false)
        #expect(restored.rallyPlayback?.clips == [.init(targetId: "rp-mark-1")])
    }

    @Test("a 1.0 document is stamped 1.1.0 when it gains rolls; a later version is kept")
    func versionStamp() throws {
        var old = try Self.base()
        old.schemaVersion = try SchemaVersion("1.0.0")
        #expect(try old.settingRallyRolls(preRollMs: 0, postRollMs: 0).schemaVersion == .v1_1)
        var later = try Self.base()
        later.schemaVersion = .v1_2
        #expect(try later.settingRallyRolls(preRollMs: 0, postRollMs: 0).schemaVersion == .v1_2)
    }
}
