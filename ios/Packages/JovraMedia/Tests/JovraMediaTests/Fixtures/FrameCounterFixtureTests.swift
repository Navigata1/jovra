import AVFoundation
import CoreMedia
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

/// The frame-counter fixtures (scripts/media, set `frameCounter`) burn their own frame index into every
/// frame. Expected values come from the ground truth the Python renderer wrote, never from this package.
@Suite("Frame-counter fixtures decode to their own frame index")
struct FrameCounterFixtureTests {
    static let catalog = MediaFixtureCatalog.repository()

    static var frameCounterIDs: [String] {
        (try? catalog.truths(inSet: "frameCounter").map(\.id)) ?? []
    }

    @Test("the frame-counter set covers 24, 30, 60, 120 and 240 fps")
    func coversEveryRate() throws {
        let rates = try Self.catalog.truths(inSet: "frameCounter").map { $0.video.frameRate.frameRate }
        #expect(Set(rates) == [FrameRate(frames: 24), .fps30, .fps60, .fps120, .fps240])
    }

    @Test("every decoded frame N shows counter N at presentation time N / fps", arguments: frameCounterIDs)
    func sequentialDecode(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let frames = try await DecodedFrameReader.frames(of: try Self.catalog.mediaURL(for: truth), truth: truth)
        #expect(frames.count == truth.video.frameCount)
        let rate = truth.video.frameRate.frameRate
        for (index, frame) in frames.enumerated() {
            #expect(frame.code == index, "frame \(index) shows \(frame.code)")
            #expect(frame.presentationTime == CMTime(frame: index, at: rate), "frame \(index) at \(frame.presentationTime.seconds)")
        }
    }

    @Test("seeking with zero tolerance to frame N shows counter N (sampled frames)", arguments: frameCounterIDs)
    func sampledSeek(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let rate = truth.video.frameRate.frameRate
        let last = truth.video.frameCount - 1
        let samples = [0, 1, rate.frames / 2, rate.frames - 1, rate.frames, rate.frames + 1, last - 1, last]
        let asset = AVURLAsset(url: try Self.catalog.mediaURL(for: truth))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for frame in samples {
            let (image, actual) = try await generator.image(at: CMTime(frame: frame, at: rate))
            let code = try FrameCode.read(from: LumaPlane(image: image), truth: truth)
            #expect(code == frame, "seek to frame \(frame) showed \(code)")
            #expect(actual.frameIndex(at: rate) == frame)
        }
    }
}
