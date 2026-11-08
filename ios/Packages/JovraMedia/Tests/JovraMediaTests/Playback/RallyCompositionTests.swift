@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

/// T32: the rally-only composition plays exactly the plan's ranges. The frame-counter fixtures burn their own frame
/// index into every frame, so which source frame the composition shows is read back from the pixels, never assumed.
@Suite("Rally-only composition from a RallyOnlyPlan", .serialized)
struct RallyCompositionTests {
    static let catalog = MediaFixtureCatalog.repository()

    /// Three points in a 2 s recording, widened by 0.1 s each side: [200, 600), [900, 1300), [1700, 2000).
    static func plan() throws -> RallyOnlyPlan {
        try RallyOnlyPlan.build(
            targets: [RallyTarget(targetId: "a", startMs: 300, endMs: 500), RallyTarget(targetId: "b", startMs: 1_000, endMs: 1_200),
                      RallyTarget(targetId: "c", startMs: 1_800, endMs: 2_000)],
            rolls: SessionRallyPlayback(preRollMs: 100, postRollMs: 100), durationMs: 2_000)
    }

    static func codeShown(at time: CMTime, in asset: AVAsset, truth: GroundTruth) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: time)
        return try FrameCode.read(from: LumaPlane(image: image), truth: truth)
    }

    @Test("duration equals the sum of the plan's ranges within one frame", arguments: ["frameCounter/fc-060", "frameCounter/fc-240"])
    func durationMatchesPlan(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let rate = truth.video.frameRate.frameRate
        let plan = try Self.plan()
        #expect(plan.keptMs == 1_100) // 400 + 400 + 300, worked by hand
        let rally = try await RallyComposition.build(plan: plan, sources: [RallySource(url: Self.catalog.mediaURL(for: truth), sessionStartMs: 0)])
        let difference = CMTimeAbsoluteValue(CMTimeSubtract(rally.composition.duration, CMTime(value: 1_100, timescale: 1_000)))
        #expect(CMTimeCompare(difference, CMTime(frame: 1, at: rate)) <= 0, "\(id): composition \(rally.composition.duration.seconds) s")
        print("\(id): composition \(rally.composition.duration.value)/\(rally.composition.duration.timescale) s, plan 1100 ms, one frame \(CMTime(frame: 1, at: rate).seconds) s")
        #expect(rally.pieces.map(\.sessionRange) == plan.ranges.map(\.range))
    }

    @Test("each range starts on its own source frame and the skipped time never plays", arguments: ["frameCounter/fc-060", "frameCounter/fc-240"])
    func framesComeFromThePlannedRanges(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let rate = truth.video.frameRate.frameRate
        let rally = try await RallyComposition.build(plan: Self.plan(), sources: [RallySource(url: Self.catalog.mediaURL(for: truth), sessionStartMs: 0)])
        let fps = rate.frames
        // Composition 0 / 0.4 / 0.8 s are session 0.2 / 0.9 / 1.7 s; one frame before 0.4 s is the frame before 0.6 s.
        let expectations: [(compositionMs: Int, sourceFrame: Int)] = [
            (0, fps / 5), (400, fps * 9 / 10), (800, fps * 17 / 10),
        ]
        for (compositionMs, sourceFrame) in expectations {
            let shown = try await Self.codeShown(at: CMTime(value: Int64(compositionMs), timescale: 1_000), in: rally.composition, truth: truth)
            #expect(shown == sourceFrame, "\(id): composition \(compositionMs) ms shows frame \(shown)")
        }
        let beforeCut = CMTimeSubtract(CMTime(value: 400, timescale: 1_000), CMTime(frame: 1, at: rate))
        #expect(try await Self.codeShown(at: beforeCut, in: rally.composition, truth: truth) == fps * 6 / 10 - 1)
        #expect(rally.sessionTimeMs(atCompositionTime: CMTime(value: 450, timescale: 1_000)) == 950)
        #expect(rally.sessionTimeMs(atCompositionTime: CMTime(value: 1_100, timescale: 1_000)) == nil)
    }

    @Test("a range that runs over a recording gap plays only the media on each side of it")
    func spansSegments() async throws {
        let truth = try Self.catalog.truth(id: "frameCounter/fc-060")
        let url = try Self.catalog.mediaURL(for: truth)
        // Two 2 s segments with a 0.5 s recording gap: segment 1 starts at session 2.5 s.
        let plan = try RallyOnlyPlan.build(targets: [RallyTarget(targetId: "p", startMs: 1_800, endMs: 2_700)],
                                           rolls: SessionRallyPlayback(preRollMs: 0, postRollMs: 0), durationMs: 4_500)
        let rally = try await RallyComposition.build(plan: plan, sources: [RallySource(url: url, sessionStartMs: 2_500),
                                                                          RallySource(url: url, sessionStartMs: 0)])
        #expect(rally.pieces.map(\.sessionRange) == [MediaRange(fromMs: 1_800, toMs: 2_000), MediaRange(fromMs: 2_500, toMs: 2_700)])
        let difference = CMTimeAbsoluteValue(CMTimeSubtract(rally.composition.duration, CMTime(value: 400, timescale: 1_000)))
        #expect(CMTimeCompare(difference, CMTime(frame: 1, at: .fps60)) <= 0)
        #expect(try await Self.codeShown(at: .zero, in: rally.composition, truth: truth) == 108)
        #expect(try await Self.codeShown(at: CMTime(value: 200, timescale: 1_000), in: rally.composition, truth: truth) == 0)
    }

    @Test("audio follows the video and a rotated original keeps its orientation")
    func audioAndOrientation() async throws {
        let truth = try Self.catalog.truth(id: "import/hevc-1080p30-portrait-rotated")
        let url = try Self.catalog.mediaURL(for: truth)
        let plan = try RallyOnlyPlan.build(targets: [RallyTarget(targetId: "a", startMs: 500, endMs: 700),
                                                     RallyTarget(targetId: "b", startMs: 1_200, endMs: 1_400)],
                                           rolls: SessionRallyPlayback(preRollMs: 100, postRollMs: 100), durationMs: 2_000)
        let rally = try await RallyComposition.build(plan: plan, sources: [RallySource(url: url, sessionStartMs: 0)])
        let source = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let video = try #require(try await rally.composition.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await rally.composition.loadTracks(withMediaType: .audio).first)
        #expect(try await video.load(.preferredTransform) == source.load(.preferredTransform))
        let oneFrame = CMTime(frame: 1, at: .fps30)
        for track in [video, audio] {
            let duration = try await track.load(.timeRange).duration
            let difference = CMTimeAbsoluteValue(CMTimeSubtract(duration, CMTime(value: 800, timescale: 1_000)))
            #expect(CMTimeCompare(difference, oneFrame) <= 0, "\(track.mediaType.rawValue) \(duration.seconds) s")
        }
    }

    @Test("nothing to play and a missing file are refused")
    func refusals() async throws {
        let empty = try RallyOnlyPlan.build(targets: [], rolls: nil, durationMs: 2_000)
        let url = try Self.catalog.mediaURL(for: Self.catalog.truth(id: "frameCounter/fc-060"))
        await #expect(throws: RallyCompositionError.nothingToPlay) {
            _ = try await RallyComposition.build(plan: empty, sources: [RallySource(url: url, sessionStartMs: 0)])
        }
        await #expect(throws: RallyCompositionError.invalidSource) {
            _ = try await RallyComposition.build(plan: Self.plan(), sources: [RallySource(url: URL(fileURLWithPath: "/nonexistent.mp4"), sessionStartMs: 0)])
        }
    }
}
