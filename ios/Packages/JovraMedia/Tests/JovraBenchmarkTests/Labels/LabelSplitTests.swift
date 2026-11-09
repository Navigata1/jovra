import CryptoKit
import Foundation
import JovraBenchmark
import Testing

/// The tuning / held-out split is fixed by the recording's hash (jovra.hashWindows.v1).
@Suite("Label split: hash-fixed windows")
struct LabelSplitTests {
    /// SHA-256 of the ASCII line "jovra synthetic recording 7" (fixture L01).
    static let recording = "d9db095691ae78dbfbbc8d3bed01cbe609b1c332c9b004658491817690f0b130"

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func ms(_ value: Int64) -> RationalTime { RationalTime(value: value, timescale: 1000) }

    @Test("120 s in 30 s windows holds out one window, and this hash picks window 1")
    func knownSplit() throws {
        let split = try LabelSplit(recordingSha256: Self.recording, duration: RationalTime(value: 120, timescale: 1))
        #expect(split.method == "jovra.hashWindows.v1")
        #expect(split.windowCount == 4)
        #expect(split.heldOutWindows == [1])
        #expect(split.windows(in: .tuning) == [0, 2, 3])
        let other = try LabelSplit(recordingSha256: Self.hash("jovra synthetic recording 1\n"), duration: RationalTime(value: 120, timescale: 1))
        #expect(other.heldOutWindows == [2])
    }

    @Test("held-out and tuning windows are disjoint and together cover the recording",
          arguments: [1, 29_999, 30_000, 30_001, 90_000, 359_960, 4_277_700] as [Int64])
    func disjointAndComplete(durationMs: Int64) throws {
        for seed in 0..<40 {
            let split = try LabelSplit(recordingSha256: Self.hash("recording \(seed)"), duration: Self.ms(durationMs))
            let held = Set(split.windows(in: .heldOut)), tuning = Set(split.windows(in: .tuning))
            #expect(held.isDisjoint(with: tuning))
            #expect(held.union(tuning) == Set(0..<split.windowCount))
            #expect(held == Set(split.heldOutWindows))
            if split.windowCount >= 2 {
                #expect(!held.isEmpty && !tuning.isEmpty)
            } else {
                #expect(held.isEmpty)
            }
            let last = split.range(ofWindow: split.windowCount - 1)
            #expect(last.end == Rational(durationMs, 1000))
        }
    }

    @Test("the held-out share is 300 per mille, rounded half-up, never all and never none",
          arguments: [(2, 1), (3, 1), (4, 1), (5, 2), (10, 3), (142, 43)])
    func share(windows: Int, heldOut: Int) throws {
        let split = try LabelSplit(recordingSha256: Self.recording, duration: Self.ms(Int64(windows) * 30_000))
        #expect(split.heldOutWindows.count == heldOut)
    }

    @Test("a time on a boundary belongs to the later window; the final instant to the last one")
    func boundaries() throws {
        let split = try LabelSplit(recordingSha256: Self.recording, duration: RationalTime(value: 120, timescale: 1))
        #expect(split.split(of: Self.ms(29_999)) == .tuning)
        #expect(split.split(of: Self.ms(30_000)) == .heldOut)
        #expect(split.split(of: RationalTime(value: 1_799_999, timescale: 30_000)) == .heldOut)   // 59.99997 s
        #expect(split.split(of: Self.ms(60_000)) == .tuning)
        #expect(split.window(of: Self.ms(120_000)) == 3)
        #expect(split.window(of: RationalTime(value: Int64.max, timescale: 1)) == 3)
    }

    @Test("the same recording always gets the same split, and another recording a different key order")
    func deterministic() throws {
        let duration = RationalTime(value: 4_277_700, timescale: 1000)
        let one = try LabelSplit(recordingSha256: Self.recording, duration: duration)
        let again = try LabelSplit(recordingSha256: Self.recording, duration: duration)
        let other = try LabelSplit(recordingSha256: Self.hash("another recording"), duration: duration)
        #expect(one == again)
        #expect(one.heldOutWindows != other.heldOutWindows)
        #expect(one.heldOutWindows.count == 43)
    }

    @Test("the summary line states the method, the window, the share and the held-out windows")
    func summary() throws {
        let split = try LabelSplit(recordingSha256: Self.recording, duration: RationalTime(value: 120, timescale: 1))
        #expect(split.summary == "jovra.hashWindows.v1, 30 s windows, 300 per mille held out: 1 of 4 windows (1)")
    }
}
