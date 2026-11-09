@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

enum DisplayedFrameError: Error { case noPixelBuffer(CMTime) }

/// Reads the frame the player itself would display: the decoded pixel buffer at the player's current item
/// time, with the fixture's burned-in frame code read back from its luma. Nothing is inferred from a readout.
@MainActor
struct DisplayedFrame {
    let output: AVPlayerItemVideoOutput
    let truth: GroundTruth

    init(_ controller: PlaybackController, truth: GroundTruth) {
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        controller.player.currentItem?.add(output)
        self.truth = truth
    }

    func code(_ controller: PlaybackController) async throws -> Int {
        let time = controller.player.currentTime()
        for _ in 0..<200 {
            if let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                return try FrameCode.read(from: LumaPlane(pixelBuffer: buffer), truth: truth)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw DisplayedFrameError.noPixelBuffer(time)
    }
}

@MainActor
@Suite("PlaybackController on the frame-counter fixtures", .serialized)
struct PlaybackControllerTests {
    let catalog = MediaFixtureCatalog.repository()

    private func open(_ id: String) async throws -> (PlaybackController, GroundTruth) {
        let truth = try catalog.truth(id: id)
        let controller = try await PlaybackController.open(url: try catalog.mediaURL(for: truth))
        return (controller, truth)
    }

    @Test
    func openReadsTheClipsRateAndFrameCount() async throws {
        let (controller, truth) = try await open("frameCounter/fc-240")
        #expect(controller.frameRate == truth.video.frameRate.frameRate)
        #expect(controller.frameCount == truth.video.frameCount)
        #expect(controller.currentFrame == 0)
        #expect(controller.readout == PlaybackReadout(frame: 0, frameRate: .fps240, rate: .normal))
        controller.close()
    }

    @Test
    func aMissingFileIsAnErrorNotACrash() async throws {
        let gone = FileManager.default.temporaryDirectory.appendingPathComponent("jovra-missing-\(UUID()).mp4")
        await #expect(throws: PlaybackOpenError.missingFile) { _ = try await PlaybackController.open(url: gone) }
    }

    /// 100 seeded random targets per fixture. Each target is reached by an exact seek and then left by one
    /// frame forward and one frame backward; every landing is checked on the decoded displayed frame.
    @Test(arguments: ["frameCounter/fc-060", "frameCounter/fc-240"])
    func seekAndStepLandOnTheExactDisplayedFrame(id: String) async throws {
        let (controller, truth) = try await open(id)
        defer { controller.close() }
        let displayed = DisplayedFrame(controller, truth: truth)
        let count = truth.video.frameCount
        var seed: UInt64 = 0x5EED_0014
        var checked = 0
        for _ in 0..<100 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let target = Int((seed >> 33) % UInt64(count - 2)) + 1
            await controller.seek(toFrame: target, precision: .exact)
            #expect(controller.currentFrame == target)
            #expect(try await displayed.code(controller) == target, "seek to \(target)")
            await controller.step(byCount: 1)
            #expect(controller.currentFrame == target + 1)
            #expect(try await displayed.code(controller) == target + 1, "step forward from \(target)")
            await controller.step(byCount: -1)
            await controller.settle()
            #expect(controller.currentFrame == target)
            #expect(try await displayed.code(controller) == target, "step backward to \(target)")
            checked += 3
        }
        #expect(checked == 300)
    }

    @Test
    func stepsClampAtTheEndsAndTenSecondSkipStaysInsideTheClip() async throws {
        let (controller, truth) = try await open("frameCounter/fc-060")
        defer { controller.close() }
        let displayed = DisplayedFrame(controller, truth: truth)
        await controller.step(byCount: -1)
        #expect(controller.currentFrame == 0)
        await controller.skip(seconds: 10)
        #expect(controller.currentFrame == truth.video.frameCount - 1, "a 2 s clip ends before +10 s")
        #expect(try await displayed.code(controller) == truth.video.frameCount - 1)
        await controller.step(byCount: 1)
        #expect(controller.currentFrame == truth.video.frameCount - 1)
        await controller.skip(seconds: -10)
        #expect(controller.currentFrame == 0)
        #expect(try await displayed.code(controller) == 0)
    }

    @Test
    func draggingChasesCoarselyAndReleaseLandsExactly() async throws {
        let (controller, truth) = try await open("frameCounter/fc-240")
        defer { controller.close() }
        let displayed = DisplayedFrame(controller, truth: truth)
        for frame in stride(from: 0, through: 400, by: 7) { controller.scrub(toFrame: frame) }
        #expect(controller.currentFrame == 399, "the readout follows the finger immediately")
        await controller.endScrub(atFrame: 401)
        #expect(controller.currentFrame == 401)
        #expect(try await displayed.code(controller) == 401)
        #expect(controller.seeksIssued < 60, "a fast drag never queues one seek per position (issued \(controller.seeksIssued))")
    }

    @Test
    func rateChangesReachThePlayerAndTheReadout() async throws {
        let (controller, _) = try await open("frameCounter/fc-060")
        defer { controller.close() }
        #expect(controller.canPlaySlowForward)
        for rate in PlaybackRate.allCases {
            controller.setRate(rate)
            #expect(controller.readout.rate == rate)
            #expect(controller.player.defaultRate == rate.value)
        }
        controller.setRate(.half)
        controller.play()
        try await Task.sleep(for: .milliseconds(150))
        #expect(controller.player.rate == 0.5)
        #expect(controller.isPlaying)
        controller.pause()
        #expect(!controller.isPlaying)
        #expect(controller.player.rate == 0)
    }

    /// The loop is enforced by the item's forward end time, so playback stops at B before seeking to A.
    @Test
    func anABLoopRepeatsWithinOneFrameOfAAndB() async throws {
        let (controller, truth) = try await open("frameCounter/fc-060")
        defer { controller.close() }
        let displayed = DisplayedFrame(controller, truth: truth)
        let loop = try #require(FrameLoop(start: 30, end: 50, frameCount: truth.video.frameCount))
        controller.setLoop(loop)
        await controller.settle()
        #expect(controller.currentFrame == 30, "setting a loop outside the playhead moves it to A")
        controller.setRate(.double)
        var observed: [Int] = []
        controller.play()
        let deadline = ContinuousClock.now + .seconds(3)
        while controller.loopWraps.count < 3, ContinuousClock.now < deadline {
            observed.append(controller.player.currentTime().frameIndex(at: controller.frameRate))
            try await Task.sleep(for: .milliseconds(4))
        }
        controller.pause()
        #expect(controller.loopWraps.count >= 3, "the loop repeated (wraps: \(controller.loopWraps.count))")
        for wrap in controller.loopWraps {
            #expect(abs(wrap.endedAt - loop.end) <= 1, "playback stopped within one frame of B (\(wrap.endedAt))")
            #expect(wrap.restartedAt == loop.start, "playback restarted exactly at A")
        }
        #expect(observed.allSatisfy { (loop.start - 1)...(loop.end + 1) ~= $0 }, "never outside A–B ± 1: \(observed.filter { !((29)...(51) ~= $0) })")
        controller.setLoop(nil)
        await controller.seek(toFrame: 30, precision: .exact)
        #expect(try await displayed.code(controller) == 30)
    }
}
