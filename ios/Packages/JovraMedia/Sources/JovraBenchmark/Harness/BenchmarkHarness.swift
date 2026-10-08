import Foundation

public enum HarnessError: Error, Equatable, CustomStringConvertible {
    case noClips
    case tuningSeedCannotGate(clipIDs: [String])
    case heldOutSeedInTuning(clipIDs: [String])
    case clipHasNoSplit(clipIDs: [String])
    case gateNeedsFloor
    case mixedBands([String])

    public var description: String {
        switch self {
        case .noClips: "A benchmark run needs at least one clip"
        case .tuningSeedCannotGate(let ids): "Refusing to gate on tuning seeds: \(ids.joined(separator: ", ")). Gate on held-out seeds only."
        case .heldOutSeedInTuning(let ids): "Refusing to tune on held-out seeds: \(ids.joined(separator: ", ")). They are kept for gating."
        case .clipHasNoSplit(let ids): "Clips without a tuning/held-out split cannot be benchmarked: \(ids.joined(separator: ", "))"
        case .gateNeedsFloor: "A gating run needs a floor"
        case .mixedBands(let bands): "One record covers one band, got \(bands.joined(separator: ", "))"
        }
    }
}

/// Loads ground truth, runs an estimator on every clip, scores the outputs and writes a benchmark record with
/// the estimator's method version. Tuning seeds and held-out seeds never mix: a gating run accepts held-out
/// clips only (it refuses before the estimator runs), and a tuning run accepts tuning clips only and has no
/// verdict.
public struct BenchmarkHarness: Sendable {
    public static let version = "1.0.0"

    public let catalog: MediaFixtureCatalog

    public init(catalog: MediaFixtureCatalog) {
        self.catalog = catalog
    }

    public func run<Estimator: BenchmarkEstimator, Task: BenchmarkTask>(
        _ estimator: Estimator, task: Task, clipIDs: [String], mode: RunMode, floor: Floor?,
        capabilityId: String? = nil, runId: String, at: Date
    ) async throws -> BenchmarkRecord where Estimator.Output == Task.Output {
        guard !clipIDs.isEmpty else { throw HarnessError.noClips }
        let truths = try clipIDs.map { try catalog.truth(id: $0) }
        let unsplit = truths.filter { $0.split == nil || $0.seed == nil }.map(\.id)
        guard unsplit.isEmpty else { throw HarnessError.clipHasNoSplit(clipIDs: unsplit) }
        switch mode {
        case .gate:
            let tuning = truths.filter { $0.split == .tuning }.map(\.id)
            guard tuning.isEmpty else { throw HarnessError.tuningSeedCannotGate(clipIDs: tuning) }
            guard floor != nil else { throw HarnessError.gateNeedsFloor }
        case .tuning:
            let heldOut = truths.filter { $0.split == .heldOut }.map(\.id)
            guard heldOut.isEmpty else { throw HarnessError.heldOutSeedInTuning(clipIDs: heldOut) }
        }
        let bands = Array(Set(truths.map(\.band))).sorted()
        guard bands.count == 1 else { throw HarnessError.mixedBands(bands) }

        var outputs: [Task.Output] = []
        for truth in truths {
            outputs.append(try await estimator.estimate(BenchmarkClip(truth: truth, mediaURL: try? catalog.mediaURL(for: truth))))
        }
        let metrics = try task.score(truths: truths, outputs: outputs)
        let clips = try zip(truths, outputs).map { truth, output in
            BenchmarkRecord.Clip(truthId: truth.id, seed: truth.seed!, split: truth.split!,
                                 truthEventsSha256: task.truthDigest(of: truth), outputs: try JSONValue(encoding: output))
        }
        return BenchmarkRecord(
            runId: runId, at: Self.timestamp(at), harness: .init(version: Self.version), task: task.descriptor,
            estimator: estimator.identity, capabilityId: capabilityId, mode: mode, band: bands[0], clips: clips,
            metrics: metrics, floor: floor, verdict: mode == .gate ? floor?.verdict(for: metrics) : nil
        )
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
