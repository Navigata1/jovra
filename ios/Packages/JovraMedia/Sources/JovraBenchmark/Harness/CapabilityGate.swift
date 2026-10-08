import Foundation

/// The research gates in `spec/contracts/capability-registry.v1.json`. A benchmark record that names a
/// capability is judged against that capability's gate and nothing else (ADR-0004), so the harness reads the
/// gate from the registry rather than trusting a floor the caller chose.
public enum CapabilityRegistryGates {
    public static let path = "spec/contracts/capability-registry.v1.json"

    struct Registry: Decodable {
        struct Capability: Decodable {
            struct Gate: Decodable { let metrics: [Floor.Metric] }
            let id: String
            let gate: Gate?
        }
        let capabilities: [Capability]
    }

    /// Every capability id with its gate metrics (nil for a capability without a gate).
    public static func load(from catalog: MediaFixtureCatalog) throws -> [String: [Floor.Metric]?] {
        let data = try Data(contentsOf: catalog.root.appendingPathComponent(path))
        let registry = try JSONDecoder().decode(Registry.self, from: data)
        return Dictionary(registry.capabilities.map { ($0.id, $0.gate?.metrics) }, uniquingKeysWith: { first, _ in first })
    }
}

extension Floor {
    /// The floor a record naming `capabilityId` must use: that capability's registry gate.
    public static func capabilityGate(_ capabilityId: String, catalog: MediaFixtureCatalog) throws -> Floor {
        let gates = try CapabilityRegistryGates.load(from: catalog)
        guard let entry = gates[capabilityId] else { throw HarnessError.unknownCapability(capabilityId) }
        guard let metrics = entry, !metrics.isEmpty else { throw HarnessError.capabilityHasNoGate(capabilityId) }
        return Floor(source: "\(CapabilityRegistryGates.path) gate of \(capabilityId)", metrics: metrics)
    }
}

/// How a task is judged against one capability's research gate (`spec/fixtures/media/benchmark-bindings.json`,
/// `spec/schemas/benchmark-bindings.schema.json`): the task id, version and tolerance a record naming the
/// capability must use, and the gate name of each task metric. The caller chooses none of these.
public struct BenchmarkBinding: Decodable, Hashable, Sendable {
    public struct MetricName: Decodable, Hashable, Sendable {
        public let task: String
        public let gate: String
    }

    public let capabilityId: String
    public let task: TaskDescriptor
    public let metrics: [MetricName]

    /// The task's metrics under the gate's names, in the task's order. A task metric the binding does not map
    /// is an error: a record must never carry a metric its gate cannot judge.
    public func gateMetrics(_ results: [MetricResult]) throws -> [MetricResult] {
        try results.map { result in
            guard let mapped = metrics.first(where: { $0.task == result.name }) else {
                throw HarnessError.bindingMissesMetric(capabilityId: capabilityId, metric: result.name)
            }
            return result.named(mapped.gate)
        }
    }
}

public enum BenchmarkBindings {
    public static let path = "spec/fixtures/media/benchmark-bindings.json"

    struct Document: Decodable { let bindings: [BenchmarkBinding] }

    public static func load(from catalog: MediaFixtureCatalog) throws -> [BenchmarkBinding] {
        let data = try Data(contentsOf: catalog.root.appendingPathComponent(path))
        return try JSONDecoder().decode(Document.self, from: data).bindings
    }

    /// The binding of `capabilityId`; a capability without one cannot be named by a run.
    public static func binding(for capabilityId: String, catalog: MediaFixtureCatalog) throws -> BenchmarkBinding {
        guard let binding = try load(from: catalog).first(where: { $0.capabilityId == capabilityId }) else {
            throw HarnessError.capabilityHasNoBinding(capabilityId)
        }
        return binding
    }
}
