import CryptoKit
import Foundation

/// Task `eventTimes` 1.0.0: an estimator returns event times per clip (hit onsets, camera nudges, ...),
/// matched to the clip's ground-truth events within a tolerance and pooled over all clips.
///
/// Matching, per clip: predictions sorted ascending. For each truth event in time order, the unmatched
/// prediction with the smallest |p - t| <= tolerance is taken (on equal distance, the earlier one) and
/// consumed. Metrics: precision = matched / predictions, recall = matched / truth events, onset MAE = mean
/// |p - t| over matched pairs in ms. Exact rationals throughout; same rule as
/// `spec/reference/jovra_ref/benchmark.py`.
public struct EventTimesTask: BenchmarkTask {
    public typealias Output = [RationalTime]

    public static let id = "eventTimes"
    public static let version = "1.0.0"

    public struct ClipResult: Sendable {
        public let truth: [RationalTime]
        public let predictions: [RationalTime]

        public init(truth: [RationalTime], predictions: [RationalTime]) {
            self.truth = truth
            self.predictions = predictions
        }
    }

    public let tolerance: RationalTime

    public init(tolerance: RationalTime) {
        self.tolerance = tolerance
    }

    public var descriptor: TaskDescriptor {
        TaskDescriptor(id: Self.id, version: Self.version, tolerance: tolerance)
    }

    /// SHA-256 of the truth event times, one `value/timescale` line each (ASCII).
    public static func truthEventsSha256(_ truth: GroundTruth) -> String {
        let text = (truth.events ?? []).map { "\($0.time.value)/\($0.time.timescale)\n" }.joined()
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func truthDigest(of truth: GroundTruth) -> String {
        Self.truthEventsSha256(truth)
    }

    public func score(truths: [GroundTruth], outputs: [[RationalTime]]) throws -> [MetricResult] {
        try score(zip(truths, outputs).map { ClipResult(truth: ($0.events ?? []).map(\.time), predictions: $1) })
    }

    public func score(_ clips: [ClipResult]) throws -> [MetricResult] {
        var matched: Int64 = 0, predicted: Int64 = 0, expected: Int64 = 0
        var total = Rational.zero
        for clip in clips {
            let deltas = try Self.match(truth: clip.truth, predictions: clip.predictions, tolerance: Rational(tolerance))
            matched += Int64(deltas.count)
            predicted += Int64(clip.predictions.count)
            expected += Int64(clip.truth.count)
            for delta in deltas { total = try total.adding(delta) }
        }
        let precision = predicted > 0 ? Rational(matched, predicted) : nil
        let recall = expected > 0 ? Rational(matched, expected) : nil
        let mae = matched > 0 ? try total.multiplied(by: Rational(1000)).divided(by: Rational(matched)) : nil
        return [
            try MetricResult(name: "precision", exact: precision, places: 4),
            try MetricResult(name: "recall", exact: recall, places: 4),
            try MetricResult(name: "onset MAE", unit: "ms", exact: mae, places: 3),
        ]
    }

    /// |p - t| of every matched pair, in truth order.
    static func match(truth: [RationalTime], predictions: [RationalTime], tolerance: Rational) throws -> [Rational] {
        let sorted = predictions.map(Rational.init).enumerated().sorted { ($0.element, $0.offset) < ($1.element, $1.offset) }.map(\.element)
        var used = [Bool](repeating: false, count: sorted.count)
        var deltas: [Rational] = []
        for t in truth.map(Rational.init) {
            let low = try t.subtracting(tolerance), high = try t.adding(tolerance)
            var index = lowerBound(sorted, low)
            var best: (index: Int, delta: Rational)?
            while index < sorted.count, sorted[index] <= high {
                if !used[index] {
                    let delta = try sorted[index].subtracting(t).magnitude
                    if best == nil || delta < best!.delta { best = (index, delta) }
                }
                index += 1
            }
            if let best {
                used[best.index] = true
                deltas.append(best.delta)
            }
        }
        return deltas
    }

    private static func lowerBound(_ values: [Rational], _ target: Rational) -> Int {
        var (low, high) = (0, values.count)
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < target { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

/// Returns the ground-truth event times: the best any estimator could do. A harness self-test only.
public struct OracleEventEstimator: BenchmarkEstimator {
    public init() {}
    public var identity: EstimatorIdentity { EstimatorIdentity(id: "oracle.eventTimes", methodVersion: "1.0.0", role: .oracle) }
    public func estimate(_ clip: BenchmarkClip) async throws -> [RationalTime] {
        (clip.truth.events ?? []).map(\.time)
    }
}

/// Finds nothing: the floor must reject it. A harness self-test only.
public struct NullEventEstimator: BenchmarkEstimator {
    public init() {}
    public var identity: EstimatorIdentity { EstimatorIdentity(id: "null.eventTimes", methodVersion: "1.0.0", role: .null) }
    public func estimate(_ clip: BenchmarkClip) async throws -> [RationalTime] { [] }
}
