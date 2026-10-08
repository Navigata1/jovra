import Foundation

public enum HarnessError: Error, Equatable, CustomStringConvertible {
    case noClips
    case tuningSeedCannotGate(clipIDs: [String])
    case heldOutSeedInTuning(clipIDs: [String])
    case clipHasNoSplit(clipIDs: [String])
    case gateNeedsFloor
    case mixedBands([String])
    case duplicateClips([String])
    case selfTestEstimatorCannotBackCapability(role: EstimatorRole, capabilityId: String)
    case unknownCapability(String)
    case capabilityHasNoGate(String)
    case floorIsNotCapabilityGate(capabilityId: String)
    case capabilityHasNoBinding(String)
    case taskIsNotCapabilityBinding(capabilityId: String, expected: TaskDescriptor)
    case bindingMissesMetric(capabilityId: String, metric: String)
    case mediaDoesNotMatchTruth(clipID: String, expected: String, decoded: String)

    public var description: String {
        switch self {
        case .noClips: "A benchmark run needs at least one clip"
        case .tuningSeedCannotGate(let ids): "Refusing to gate on tuning seeds: \(ids.joined(separator: ", ")). Gate on held-out seeds only."
        case .heldOutSeedInTuning(let ids): "Refusing to tune on held-out seeds: \(ids.joined(separator: ", ")). They are kept for gating."
        case .clipHasNoSplit(let ids): "Clips without a tuning/held-out split cannot be benchmarked: \(ids.joined(separator: ", "))"
        case .gateNeedsFloor: "A gating run needs a floor"
        case .mixedBands(let bands): "One record covers one band, got \(bands.joined(separator: ", "))"
        case .duplicateClips(let ids): "Each clip counts once; listed more than once: \(ids.joined(separator: ", "))"
        case .selfTestEstimatorCannotBackCapability(let role, let id): "The \(role.rawValue) estimator is a harness self-test and cannot back capability \(id); only a candidate can"
        case .unknownCapability(let id): "No capability \(id) in \(CapabilityRegistryGates.path)"
        case .capabilityHasNoGate(let id): "Capability \(id) has no research gate in \(CapabilityRegistryGates.path)"
        case .floorIsNotCapabilityGate(let id): "A run that names \(id) must use its registry gate as the floor (omit --floor to use it)"
        case .capabilityHasNoBinding(let id): "Capability \(id) has no benchmark binding in \(BenchmarkBindings.path); add one with its task"
        case .taskIsNotCapabilityBinding(let id, let expected):
            "A run that names \(id) must use task \(expected.id) \(expected.version)"
                + (expected.tolerance.map { " with tolerance \($0) (omit --tolerance to use it)" } ?? "") + " (\(BenchmarkBindings.path))"
        case .bindingMissesMetric(let id, let metric): "The benchmark binding of \(id) does not map task metric \(metric) to a gate metric"
        case .mediaDoesNotMatchTruth(let clip, let expected, let decoded):
            "Rendered media for \(clip) decodes to \(decoded), not the committed \(expected). Run: python3 scripts/media/render.py --check"
        }
    }
}

/// Loads ground truth, runs an estimator on every clip, scores the outputs and writes a benchmark record with
/// the estimator's method version. Tuning seeds and held-out seeds never mix: a gating run accepts held-out
/// clips only (it refuses before the estimator runs), and a tuning run accepts tuning clips only and has no
/// verdict. Each clip counts once. A run that names a capability must come from a `candidate` estimator, use
/// that capability's registry gate as its floor (ADR-0004) and the task its benchmark binding names, and its
/// metrics carry the gate's names. A candidate analyses media: each clip must be rendered and decode to the
/// committed decoded-frame hash. Every refusal happens before estimation, and every record clip carries the
/// renderer source hash and decoded-frame hash of its ground truth.
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
        let repeated = Dictionary(grouping: clipIDs, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        guard repeated.isEmpty else { throw HarnessError.duplicateClips(repeated) }
        let role = estimator.identity.role
        var binding: BenchmarkBinding?
        if let capabilityId {
            guard role == .candidate else {
                throw HarnessError.selfTestEstimatorCannotBackCapability(role: role, capabilityId: capabilityId)
            }
            let gate = try Floor.capabilityGate(capabilityId, catalog: catalog)
            if let floor, floor.metrics != gate.metrics {
                throw HarnessError.floorIsNotCapabilityGate(capabilityId: capabilityId)
            }
            let bound = try BenchmarkBindings.binding(for: capabilityId, catalog: catalog)
            guard task.descriptor == bound.task else {
                throw HarnessError.taskIsNotCapabilityBinding(capabilityId: capabilityId, expected: bound.task)
            }
            binding = bound
        }
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

        var mediaURLs: [URL?] = []
        for truth in truths {
            mediaURLs.append(role == .candidate ? try await verifiedMedia(for: truth) : try? catalog.mediaURL(for: truth))
        }
        var outputs: [Task.Output] = []
        for (truth, mediaURL) in zip(truths, mediaURLs) {
            outputs.append(try await estimator.estimate(BenchmarkClip(truth: truth, mediaURL: mediaURL)))
        }
        let scored = try task.score(truths: truths, outputs: outputs)
        let metrics = try binding?.gateMetrics(scored) ?? scored
        let clips = try zip(truths, outputs).map { truth, output in
            BenchmarkRecord.Clip(truthId: truth.id, seed: truth.seed!, split: truth.split!,
                                 rendererSourceHash: truth.renderer.sourceHash,
                                 decodedFramesSha256: truth.signature.decodedFramesSha256,
                                 truthEventsSha256: task.truthDigest(of: truth), outputs: try JSONValue(encoding: output))
        }
        return BenchmarkRecord(
            runId: runId, at: Self.timestamp(at), harness: .init(version: Self.version), task: task.descriptor,
            estimator: estimator.identity, capabilityId: capabilityId, mode: mode, band: bands[0], clips: clips,
            metrics: metrics, floor: floor, verdict: mode == .gate ? floor?.verdict(for: metrics) : nil
        )
    }

    /// The clip's rendered file, after checking it decodes to the committed decoded-frame hash: a candidate's
    /// record then states exactly which media it analysed. Throws `notRendered` when the cache lacks it.
    func verifiedMedia(for truth: GroundTruth) async throws -> URL {
        let url = try catalog.mediaURL(for: truth)
        let decoded = try await DecodedFrameReader.signatureHash(of: url, truth: truth).sha256
        guard decoded == truth.signature.decodedFramesSha256 else {
            throw HarnessError.mediaDoesNotMatchTruth(clipID: truth.id, expected: truth.signature.decodedFramesSha256, decoded: decoded)
        }
        return url
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
