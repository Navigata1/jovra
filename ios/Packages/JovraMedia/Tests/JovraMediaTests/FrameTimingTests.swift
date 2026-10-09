import CoreMedia
import JovraCore
import JovraMedia
import Testing

/// `FrameTiming` reads a track's frame rate from its presentation timestamps: the median frame duration gives
/// the rate, and frame durations that wander from it mark the clip variable-frame-rate. The shortest frame
/// must never set the rate (phone originals have the odd short frame).
@Suite("Frame rate from presentation timestamps")
struct FrameTimingTests {
    /// Cumulative presentation times from per-frame durations, in decode order as given.
    static func times(_ durations: [Int64]) -> [Int64] {
        durations.reduce(into: [Int64(0)]) { $0.append($0.last! + $1) }
    }

    @Test("constant 30 fps at timescale 30000")
    func constant30() throws {
        let timing = try #require(FrameTiming(presentationTimes: Self.times(Array(repeating: 1000, count: 59)), timescale: 30000))
        #expect(timing.frameRate == .fps30)
        #expect(!timing.isVariableFrameRate)
    }

    @Test("29.97 fps stays exact: 1001/30000 s per frame is 30000/1001")
    func ntsc() throws {
        let timing = try #require(FrameTiming(presentationTimes: Self.times(Array(repeating: 1001, count: 59)), timescale: 30000))
        #expect(timing.frameRate == FrameRate(frames: 30000, perSeconds: 1001))
        #expect(!timing.isVariableFrameRate)
    }

    @Test("one-tick rounding (29.97 fps at timescale 600: 20 ticks and every 50th 21) is 30000/1001, constant")
    func timescaleRounding() throws {
        let durations: [Int64] = (0..<100).map { $0 % 50 == 49 ? 21 : 20 }
        let timing = try #require(FrameTiming(presentationTimes: Self.times(durations), timescale: 600))
        #expect(timing.frameRate == FrameRate(frames: 30000, perSeconds: 1001))
        #expect(!timing.isVariableFrameRate)
    }

    @Test("an Android 13 original (timescale 90000: mostly 2999 ticks, some 3000, 2998 and dropped 5998) is 30 fps, variable")
    func androidHistogram() throws {
        // The duration mix of docs/fixtures/real-footage.md's 20261004 original, scaled down.
        var durations = Array(repeating: Int64(2999), count: 790) + Array(repeating: 3000, count: 103)
        durations += Array(repeating: 2998, count: 10) + [5998, 5999, 4615, 1864]
        let shuffled = durations.enumerated().sorted { ($0.offset * 7919) % 907 < ($1.offset * 7919) % 907 }.map(\.element)
        let timing = try #require(FrameTiming(presentationTimes: Self.times(shuffled), timescale: 90000))
        #expect(timing.frameRate == .fps30)
        #expect(timing.isVariableFrameRate)
    }

    @Test("a constant rate that is no standard rate is reported exactly")
    func nonStandard() throws {
        let timing = try #require(FrameTiming(presentationTimes: Self.times(Array(repeating: 1000, count: 30)), timescale: 29589))
        #expect(timing.frameRate == FrameRate(frames: 29589, perSeconds: 1000))
        #expect(!timing.isVariableFrameRate)
    }

    @Test("a phone VFR clip with a 749/30000 s frame reports 30 fps, variable, not 40 fps")
    func phoneVariableRate() throws {
        var durations = Array(repeating: Int64(1000), count: 300)
        durations[17] = 749
        durations[18] = 1251
        durations[140] = 1847 / 3
        let timing = try #require(FrameTiming(presentationTimes: Self.times(durations), timescale: 30000))
        #expect(timing.frameRate == .fps30)
        #expect(timing.isVariableFrameRate)
    }

    @Test("decode order with B-frames: timestamps are sorted before differencing")
    func reordered() throws {
        let presentation = Self.times(Array(repeating: 512, count: 11))   // 30 fps at 15360
        let decodeOrder = [presentation[0], presentation[3], presentation[1], presentation[2]] + presentation[4...]
        let timing = try #require(FrameTiming(presentationTimes: Array(decodeOrder), timescale: 15360))
        #expect(timing.frameRate == .fps30)
        #expect(!timing.isVariableFrameRate)
    }

    @Test("fallback without sample timestamps: nominal 29.97 snaps to 30000/1001, 30 with a 749/30000 s frame is VFR")
    func nominalFallback() throws {
        let ntsc = try #require(FrameTiming(nominal: 29.97003, minFrameDuration: CMTime(value: 1001, timescale: 30000)))
        #expect(ntsc == FrameTiming(frameRate: FrameRate(frames: 30000, perSeconds: 1001), isVariableFrameRate: false))
        let phone = try #require(FrameTiming(nominal: 29.98, minFrameDuration: CMTime(value: 749, timescale: 30000)))
        #expect(phone == FrameTiming(frameRate: .fps30, isVariableFrameRate: true))
        #expect(FrameTiming(nominal: 0.3, minFrameDuration: .invalid) == nil)
        #expect(FrameTiming(nominal: .nan, minFrameDuration: .invalid) == nil)
    }

    @Test("fewer than two frames or a bad timescale states no rate")
    func undefined() {
        #expect(FrameTiming(presentationTimes: [0], timescale: 30000) == nil)
        #expect(FrameTiming(presentationTimes: [0, 0, 0], timescale: 30000) == nil)
        #expect(FrameTiming(presentationTimes: [0, 1000], timescale: 0) == nil)
    }
}
