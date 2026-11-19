import CryptoKit
import Foundation

/// The hash-fixed tuning / held-out split of one recording (`jovra.hashWindows.v1`; reference and rule in
/// `spec/reference/jovra_ref/labels.py`).
///
/// The timeline is cut into windows of `windowMs`. Window i has the key
/// SHA-256("jovra.hashWindows.v1\n" + recording hash + "\n" + i + "\n"); the held-out windows are the k
/// windows with the smallest keys, k = n * heldOutPermille / 1000 rounded half-up, at least 1 and at most
/// n - 1. Nobody chooses them: they follow from the recording's bytes, so the split exists before the first
/// label, and a window is either tuning or held out, never both.
public struct LabelSplit: Codable, Hashable, Sendable {
    public static let method = "jovra.hashWindows.v1"
    public static let defaultWindowMs = 30_000
    public static let defaultHeldOutPermille = 300

    public let method: String
    public let windowMs: Int
    public let heldOutPermille: Int
    public let durationMs: Int
    public let heldOutWindows: [Int]

    public init(recordingSha256: String, duration: RationalTime, windowMs: Int = LabelSplit.defaultWindowMs,
                heldOutPermille: Int = LabelSplit.defaultHeldOutPermille) throws {
        precondition(windowMs > 0 && (1...999).contains(heldOutPermille), "LabelSplit needs a window and a share below 1")
        let durationMs = try Self.wholeMilliseconds(duration)
        self.method = Self.method
        self.windowMs = windowMs
        self.heldOutPermille = heldOutPermille
        self.durationMs = durationMs
        self.heldOutWindows = Self.heldOutWindows(recordingSha256: recordingSha256, durationMs: durationMs,
                                                  windowMs: windowMs, heldOutPermille: heldOutPermille)
    }

    /// Whole milliseconds of a media time (floor).
    public static func wholeMilliseconds(_ time: RationalTime) throws -> Int {
        let (scaled, overflow) = time.value.multipliedReportingOverflow(by: 1000)
        guard !overflow else { throw RationalOverflow(context: "the recording duration in milliseconds") }
        return Int(scaled / time.timescale)
    }

    public static func windowCount(durationMs: Int, windowMs: Int) -> Int {
        durationMs > 0 ? (durationMs + windowMs - 1) / windowMs : 0
    }

    static func windowKey(recordingSha256: String, index: Int) -> String {
        SHA256.hash(data: Data("\(method)\n\(recordingSha256)\n\(index)\n".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func heldOutWindows(recordingSha256: String, durationMs: Int, windowMs: Int, heldOutPermille: Int) -> [Int] {
        let count = windowCount(durationMs: durationMs, windowMs: windowMs)
        guard count >= 2 else { return [] }
        let held = min(max((count * heldOutPermille + 500) / 1000, 1), count - 1)
        let ranked = (0..<count).map { (key: windowKey(recordingSha256: recordingSha256, index: $0), index: $0) }
            .sorted { ($0.key, $0.index) < ($1.key, $1.index) }
        return ranked.prefix(held).map(\.index).sorted()
    }

    public var windowCount: Int { Self.windowCount(durationMs: durationMs, windowMs: windowMs) }

    /// The window a time falls in: floor(t / windowMs), and the last window for the recording's final instant.
    public func window(of time: RationalTime) -> Int {
        let (numerator, overflowA) = time.value.multipliedReportingOverflow(by: 1000)
        let (denominator, overflowB) = time.timescale.multipliedReportingOverflow(by: Int64(windowMs))
        // Exact integer division for every real media time; a value too large for 64 bits is far past any
        // recording and lands in the last window either way.
        let index = overflowA || overflowB ? Int.max : Int(numerator / denominator)
        return max(min(index, windowCount - 1), 0)
    }

    public func split(of time: RationalTime) -> GroundTruth.Split {
        heldOutWindows.contains(window(of: time)) ? .heldOut : .tuning
    }

    public func windows(in split: GroundTruth.Split) -> [Int] {
        (0..<windowCount).filter { heldOutWindows.contains($0) == (split == .heldOut) }
    }

    /// [start, end) of a window in seconds; the last window ends with the recording.
    public func range(ofWindow index: Int) -> (start: Rational, end: Rational) {
        let start = index * windowMs
        return (Rational(Int64(start), 1000), Rational(Int64(min(start + windowMs, durationMs)), 1000))
    }

    /// One line for reports: "30 s windows, 300 per mille held out: 1 of 4 windows (1)".
    public var summary: String {
        let seconds = windowMs % 1000 == 0 ? "\(windowMs / 1000) s" : "\(windowMs) ms"
        let list = heldOutWindows.map(String.init).joined(separator: ", ")
        return "\(method), \(seconds) windows, \(heldOutPermille) per mille held out: "
            + "\(heldOutWindows.count) of \(windowCount) windows" + (heldOutWindows.isEmpty ? "" : " (\(list))")
    }
}
