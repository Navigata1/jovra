import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// SD7: exact rationals, integer microseconds and the one half-up rule.
@Suite("Studio contracts: time")
struct ContractsTimeTests {
    @Test("half-up rounds .5 away from minus infinity, for both signs", arguments: [
        (1, 2, 1), (-1, 2, 0), (3, 2, 2), (-3, 2, -1), (5, 3, 2), (4, 3, 1), (-4, 3, -1), (-5, 3, -2), (0, 7, 0), (7, -2, -3),
    ])
    func roundHalfUp(_ num: Int, _ den: Int, _ expected: Int) throws {
        #expect(try StudioTime.roundHalfUp(num, over: den) == expected)
    }

    @Test("it is the same rule as the core percentage (Percent.pct is half-up of 100n/d)")
    func sameRuleAsCorePercent() throws {
        for d in 1...40 {
            for n in 0...d {
                #expect(try Percent.pct(n: n, d: d) == StudioTime.roundHalfUp(100 * n, over: d))
            }
        }
    }

    @Test("NTSC frames: 30000/1001 fps maps microseconds to frames exactly")
    func ntscFrames() throws {
        let fps = StudioFrameRate(num: 30000, den: 1001)
        // Frame 1 starts at 1001000/30 µs = 33366.666…; frame n's start maps back to n for every n.
        #expect(try StudioTime.frameStartMicroseconds(1, fps: fps) == StudioExactRational(100100, 3))
        for frame in [0, 1, 2, 29, 30, 1799, 107892] {
            let start = try StudioTime.frameStartMicroseconds(frame, fps: fps)
            #expect(try StudioTime.frame(atMicroseconds: start, fps: fps) == frame)
        }
        // Half a frame after frame 0 rounds up to frame 1; just before it stays on frame 0.
        #expect(try StudioTime.frame(atMicroseconds: StudioExactRational(50050, 3), fps: fps) == 1)
        #expect(try StudioTime.frame(atMicroseconds: StudioExactRational(50049, 3), fps: fps) == 0)
    }

    @Test("a rational media time converts to exact microseconds")
    func rationalTime() throws {
        #expect(try StudioTime.microseconds(StudioRationalTime(value: 1001, timescale: 30000)) == StudioExactRational(100100, 3))
        #expect(try StudioTime.microseconds(StudioRationalTime(value: 90000, timescale: 600)) == StudioExactRational(150_000_000, 1))
    }

    @Test("zero denominators and overflow are errors, never wrong numbers")
    func errors() {
        #expect(throws: StudioTime.TimeError.zeroDenominator) { try StudioTime.roundHalfUp(1, over: 0) }
        #expect(throws: StudioTime.TimeError.overflow) { try StudioTime.roundHalfUp(.max, over: 3) }
    }
}
