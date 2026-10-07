import CoreMedia
import JovraCore
import JovraMedia
import Testing

@Suite("Frame-accurate CMTime")
struct FrameTimeTests {
    @Test("frame 30 at 29.97 fps is exactly 1001/1000 s, with no rounding")
    func ntscFrameIsExact() {
        let time = CMTime(frame: 30, at: FrameRate(frames: 30000, perSeconds: 1001))
        #expect(time == CMTime(value: 1001, timescale: 1000))
        #expect(time.flags.contains(.valid))
    }

    @Test("frame 120 at 240 fps is half a second")
    func highFrameRate() {
        #expect(CMTime(frame: 120, at: .fps240) == CMTime(value: 1, timescale: 2))
    }

    @Test("every frame start round-trips to its frame index", arguments: [0, 1, 59, 60, 3599, 216_000])
    func roundTrip(_ frame: Int) {
        let rate = FrameRate(frames: 30000, perSeconds: 1001)
        #expect(CMTime(frame: frame, at: rate).frameIndex(at: rate) == frame)
    }

    @Test("a time between frames maps to the frame on screen")
    func betweenFrames() {
        // 1.0 s at 60 fps is frame 60; 1.0 s + 10 ms is still frame 60.
        let time = CMTime(value: 1010, timescale: 1000)
        #expect(time.frameIndex(at: .fps60) == 60)
    }

    @Test("invalid and negative times map to frame 0")
    func invalid() {
        #expect(CMTime.invalid.frameIndex(at: .fps30) == 0)
        #expect(CMTime(value: -3, timescale: 1).frameIndex(at: .fps30) == 0)
    }
}
