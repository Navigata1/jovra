import Foundation
import JovraCore

/// The registry-consistency gate (ADR-0004, ticket T11), over the shipped registry model (`CapabilityRegistry`,
/// T03) and the committed benchmark records:
///
/// - `validated` always needs a passing record.
/// - A capability whose gate promotes it to `estimated` has a floor (audio hit detection, rally segmentation,
///   camera-moved detection, line-snap): any status other than `disabled` needs a passing record.
/// - An ungated `estimated` capability (no gate, or a gate that only promotes to `validated`) may lack a
///   record; it is reported as "Not benchmarked".
///
/// A passing record is a `lastBenchmark` that passed and names a committed gating record for the same
/// capability whose verdict passed. `scripts/spec/validate.py` applies the same rule in Python.
public enum RegistryConsistency {
    /// What the capability page says about a capability's benchmark.
    public enum Standing: Equatable, Sendable {
        case passing(runId: String)
        case failing(runId: String)
        case notBenchmarked

        /// Exact copy for the capability detail sheet (T12) when there is no record.
        public static let notBenchmarkedLabel = "Not benchmarked"

        public var label: String {
            switch self {
            case .passing: "Benchmark passed"
            case .failing: "Benchmark failed"
            case .notBenchmarked: Self.notBenchmarkedLabel
            }
        }
    }

    public enum Violation: Equatable, Sendable, CustomStringConvertible {
        /// `validated` without a passing record.
        case validatedWithoutPassingRecord(capabilityId: String)
        /// A floor-gated capability above `disabled` without a passing record.
        case gatedAboveDisabledWithoutPassingRecord(capabilityId: String, status: String)
        /// `lastBenchmark` claims a pass that no committed passing gate record for this capability backs.
        case unbackedPassingClaim(capabilityId: String, runId: String)

        public var description: String {
            switch self {
            case .validatedWithoutPassingRecord(let id):
                "\(id) is validated without a passing benchmark record (ADR-0004)"
            case .gatedAboveDisabledWithoutPassingRecord(let id, let status):
                "\(id) is \(status) without a passing record of its floor; it must stay disabled"
            case .unbackedPassingClaim(let id, let runId):
                "\(id): lastBenchmark \(runId) is not a committed passing gate record for it"
            }
        }
    }

    public struct Report: Sendable {
        public let violations: [Violation]
        public let standings: [String: Standing]

        public var isConsistent: Bool { violations.isEmpty }

        public func standing(of capabilityId: String) -> Standing? { standings[capabilityId] }
    }

    /// A gate that promotes to `estimated` is a floor the capability must pass before it is shown at all.
    public static func hasFloor(_ capability: CapabilityCapability) -> Bool {
        capability.gate.value?.promotesTo == .estimated
    }

    public static func check(_ registry: CapabilityRegistry, records: [BenchmarkRecord]) -> Report {
        var violations: [Violation] = []
        var standings: [String: Standing] = [:]
        for capability in registry.capabilities {
            let standing = standing(of: capability, records: records)
            standings[capability.id] = standing
            if let last = capability.lastBenchmark.value, last.passed, standing != .passing(runId: last.runId) {
                violations.append(.unbackedPassingClaim(capabilityId: capability.id, runId: last.runId))
            }
            let passing: Bool = if case .passing = standing { true } else { false }
            if capability.status == .validated, !passing {
                violations.append(.validatedWithoutPassingRecord(capabilityId: capability.id))
            } else if hasFloor(capability), capability.status != .disabled, !passing {
                violations.append(.gatedAboveDisabledWithoutPassingRecord(capabilityId: capability.id,
                                                                         status: capability.status.rawValue))
            }
        }
        return Report(violations: violations, standings: standings)
    }

    static func standing(of capability: CapabilityCapability, records: [BenchmarkRecord]) -> Standing {
        guard let last = capability.lastBenchmark.value else { return .notBenchmarked }
        let backed = records.contains { record in
            record.runId == last.runId && record.capabilityId == capability.id && record.mode == .gate
                && record.verdict?.passed == true
        }
        return last.passed && backed ? .passing(runId: last.runId) : .failing(runId: last.runId)
    }
}

extension RegistryConsistency {
    /// The shipped registry and every committed benchmark record under `spec/`.
    public static func committed(in catalog: MediaFixtureCatalog) throws -> (CapabilityRegistry, [BenchmarkRecord]) {
        let registry = try CapabilityRegistry.load(
            from: Data(contentsOf: catalog.root.appendingPathComponent(CapabilityRegistryGates.path)))
        var records: [BenchmarkRecord] = []
        let spec = catalog.root.appendingPathComponent("spec", isDirectory: true)
        let files = FileManager.default.enumerator(at: spec, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" } ?? []
        struct Header: Decodable { let kind: String? }
        for url in files.sorted(by: { $0.path < $1.path }) {
            let data = try Data(contentsOf: url)
            guard (try? JSONDecoder().decode(Header.self, from: data))?.kind == BenchmarkRecord.kind else { continue }
            records.append(try JSONDecoder().decode(BenchmarkRecord.self, from: data))
        }
        return (registry, records)
    }
}
