import Foundation

/// The storage a planned recording needs, as a range, against the space that is free (S04, N8).
public struct StorageEstimate: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// The planned length fits even at the high end of the range.
        case ready
        /// Less than the planned length fits; `fitsSeconds` says how much.
        case lessThanPlanned
        /// Under five minutes of room.
        case almostFull
    }

    /// Low to high estimate of the recording's size in bytes.
    public var bytes: ClosedRange<Int64>
    public var plannedSeconds: Int
    public var freeBytes: Int64
    /// How long a recording fits in the free space at the high end of the range.
    public var fitsSeconds: Int
    public var verdict: Verdict
}

/// Integer arithmetic only, so both platforms and every run give the same bytes. The nominal size is
/// bitrate × length; a real recording varies with the scene, so the estimate runs from 85 % to 120 % of
/// it (screens.md S04), and "does it fit" is always judged at the 120 % end.
public enum StorageEstimator {
    public static let lowPercent: Int64 = 85
    public static let highPercent: Int64 = 120
    /// Below this much room the storage check fails (N8: "Less than 5 min of space").
    public static let almostFullSeconds = 5 * 60

    public static func range(bitRate: Int, plannedSeconds: Int) -> ClosedRange<Int64> {
        let bits = Int64(max(bitRate, 0)) * Int64(max(plannedSeconds, 0))
        return bits * lowPercent / 800 ... bits * highPercent / 800
    }

    /// Whole seconds of recording that fit in `freeBytes` at the high end of the range.
    public static func fitsSeconds(bitRate: Int, freeBytes: Int64) -> Int {
        guard bitRate > 0, freeBytes > 0 else { return 0 }
        let seconds = freeBytes.multipliedReportingOverflow(by: 800)
        guard !seconds.overflow else { return Int.max }
        return Int(seconds.partialValue / (Int64(bitRate) * highPercent))
    }

    public static func estimate(bitRate: Int, plannedSeconds: Int, freeBytes: Int64) -> StorageEstimate {
        let fits = fitsSeconds(bitRate: bitRate, freeBytes: freeBytes)
        let verdict: StorageEstimate.Verdict
        if fits >= max(plannedSeconds, 0) { verdict = .ready }
        else if fits < almostFullSeconds { verdict = .almostFull }
        else { verdict = .lessThanPlanned }
        return StorageEstimate(bytes: range(bitRate: bitRate, plannedSeconds: plannedSeconds), plannedSeconds: max(plannedSeconds, 0),
                               freeBytes: freeBytes, fitsSeconds: fits, verdict: verdict)
    }
}
