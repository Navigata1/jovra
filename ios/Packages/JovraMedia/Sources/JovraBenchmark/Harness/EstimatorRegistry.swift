import Foundation

/// What a command-line or test run asks the harness for.
public struct RunRequest: Sendable {
    public var clipIDs: [String]
    public var mode: RunMode
    public var floor: Floor?
    public var capabilityId: String?
    /// Matching tolerance for event-time tasks.
    public var tolerance: RationalTime
    public var runId: String
    public var at: Date

    public static let defaultTolerance = RationalTime(value: 50, timescale: 1000)

    public init(clipIDs: [String], mode: RunMode, floor: Floor?, capabilityId: String? = nil,
                tolerance: RationalTime = RunRequest.defaultTolerance, runId: String, at: Date) {
        self.clipIDs = clipIDs
        self.mode = mode
        self.floor = floor
        self.capabilityId = capabilityId
        self.tolerance = tolerance
        self.runId = runId
        self.at = at
    }
}

/// Every estimator the harness can run by name. An analysis ticket registers its estimator with one entry
/// here (estimator id -> how to run it); the harness, records and validator need no other change.
public enum EstimatorRegistry {
    public typealias Runner = @Sendable (BenchmarkHarness, RunRequest) async throws -> BenchmarkRecord

    public static let all: [String: Runner] = [
        "oracle.eventTimes": eventTimes(OracleEventEstimator()),
        "null.eventTimes": eventTimes(NullEventEstimator()),
    ]

    public static func eventTimes<E: BenchmarkEstimator>(_ estimator: E) -> Runner where E.Output == [RationalTime] {
        { harness, request in
            try await harness.run(estimator, task: EventTimesTask(tolerance: request.tolerance), clipIDs: request.clipIDs,
                                  mode: request.mode, floor: request.floor, capabilityId: request.capabilityId,
                                  runId: request.runId, at: request.at)
        }
    }

    /// Re-runs a committed record's estimator on the same clips with the same mode, floor and task parameters.
    public static func rerun(_ record: BenchmarkRecord, harness: BenchmarkHarness, at: Date = Date()) async throws -> BenchmarkRecord {
        guard let runner = all[record.estimator.id] else { throw RegistryError.unknownEstimator(record.estimator.id) }
        let request = RunRequest(clipIDs: record.clips.map(\.truthId), mode: record.mode, floor: record.floor,
                                 capabilityId: record.capabilityId,
                                 tolerance: record.task.tolerance ?? RunRequest.defaultTolerance,
                                 runId: record.runId, at: at)
        return try await runner(harness, request)
    }
}

public enum RegistryError: Error, Equatable, CustomStringConvertible {
    case unknownEstimator(String)

    public var description: String {
        switch self {
        case .unknownEstimator(let id): "No estimator \(id) in EstimatorRegistry (known: \(EstimatorRegistry.all.keys.sorted().joined(separator: ", ")))"
        }
    }
}
