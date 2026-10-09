import CoreMedia
import Foundation
import JovraCore
import JovraBenchmark
import JovraMedia
import Testing

@Suite("Exact replay frame lookup", .serialized)
struct FramePlaybackTests {
    @Test
    func refusesClockValuesThatCannotBeRepresentedWithoutOverflow() throws {
        let catalog = MediaFixtureCatalog.repository()
        let url = try catalog.mediaURL(for: catalog.truth(id: "frameCounter/fc-060"))
        #expect(throws: FramePlaybackError.invalidSource) {
            _ = try FramePlayback(url: url, rate: FrameRate(frames: Int.max), frameCount: 3)
        }
        #expect(throws: FramePlaybackError.invalidSource) {
            _ = try FramePlayback(url: url, rate: FrameRate(frames: 60, perSeconds: Int.max), frameCount: 3)
        }
    }

    @Test(arguments: ["frameCounter/fc-060", "frameCounter/fc-240"])
    func seededForwardAndBackwardTargetsDecodeToTheirOwnFrame(id: String) async throws {
        let catalog = MediaFixtureCatalog.repository()
        let truth = try catalog.truth(id: id)
        let rate = truth.video.frameRate.frameRate
        let playback = try FramePlayback(url: catalog.mediaURL(for: truth), rate: rate, frameCount: truth.video.frameCount)
        var seed: UInt64 = 0x1234
        for _ in 0..<100 {
            seed = seed &* 6364136223846793005 &+ 1
            let index = Int((seed >> 32) % UInt64(truth.video.frameCount))
            let frame = try await playback.frame(at: index)
            let code = try FrameCode.read(from: LumaPlane(image: frame.image), truth: truth)
            #expect(code == index, "Actual decoded counter must match the chosen frame")
            #expect(frame.index == index)
            #expect(frame.time == CMTime(frame: index, at: rate))
        }
        await #expect(throws: (any Error).self) { _ = try await playback.frame(at: -1) }
        await #expect(throws: (any Error).self) { _ = try await playback.frame(at: truth.video.frameCount) }
    }
}
