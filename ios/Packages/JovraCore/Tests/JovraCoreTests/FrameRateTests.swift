import Testing
import JovraCore

@Suite("Frame rate")
struct FrameRateTests {
    @Test("integer rates: frame 60 at 60 fps starts at exactly one second")
    func integerRate() {
        let rate = FrameRate.fps60
        #expect(rate.seconds(atFrame: 60) == 1.0)
        #expect(rate.frame(atSeconds: 1.0) == 60)
    }

    @Test("NTSC 29.97 fps (30000/1001): frame 30 starts at 1.001 s")
    func ntscRate() {
        let rate = FrameRate(frames: 30000, perSeconds: 1001)
        #expect(abs(rate.seconds(atFrame: 30) - 1.001) < 1e-12)
        #expect(abs(rate.framesPerSecond - 29.97002997) < 1e-6)
    }

    @Test("a time inside a frame maps to that frame, and frame starts round-trip despite float error")
    func frameLookup() {
        let rate = FrameRate(frames: 30000, perSeconds: 1001)
        #expect(rate.frame(atSeconds: 1.0) == 29) // 1.000 s falls inside frame 29 (starts 0.9676 s)
        for frame in [0, 1, 29, 30, 1799, 107_892] {
            #expect(rate.frame(atSeconds: rate.seconds(atFrame: frame)) == frame)
        }
    }

    @Test("negative times clamp to frame 0")
    func negative() {
        #expect(FrameRate.fps30.frame(atSeconds: -0.5) == 0)
    }
}
