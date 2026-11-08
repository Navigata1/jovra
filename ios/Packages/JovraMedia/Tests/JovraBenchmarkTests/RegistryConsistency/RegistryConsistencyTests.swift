import Foundation
import JovraBenchmark
import JovraCore
import Testing

/// JovraCore also generates a `BenchmarkRecord` contract model; the harness's own type is the one records use.
private typealias Record = JovraBenchmark.BenchmarkRecord

/// The registry-consistency gate (T11): what the shipped registry may claim about each capability, given the
/// committed benchmark records. Each rule is exercised by changing one capability of the real registry.
@Suite("Registry consistency: no capability claims more than its benchmark records back")
struct RegistryConsistencyTests {
    static let catalog = MediaFixtureCatalog.repository()

    private func committed() throws -> (CapabilityRegistry, [Record]) {
        try RegistryConsistency.committed(in: Self.catalog)
    }

    private func changing(_ registry: CapabilityRegistry, _ id: String,
                          _ change: (inout CapabilityCapability) -> Void) throws -> CapabilityRegistry {
        var copy = registry
        let index = try #require(copy.capabilities.firstIndex { $0.id == id }, "\(id) is in the registry")
        change(&copy.capabilities[index])
        return copy
    }

    /// A committed self-test record re-labelled as a passing candidate gate run for `capabilityId`.
    private func passingRecord(for capabilityId: String, runId: String, records: [Record]) throws -> Record {
        let base = try #require(records.first { $0.mode == .gate && $0.verdict?.passed == true })
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        json["runId"] = runId
        json["capabilityId"] = capabilityId
        var estimator = try #require(json["estimator"] as? [String: Any])
        estimator["role"] = "candidate"
        json["estimator"] = estimator
        return try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func lastBenchmark(_ runId: String, passed: Bool) -> ContractNullable<CapabilityCapabilityLastBenchmark> {
        .value(CapabilityCapabilityLastBenchmark(runId: runId, at: "2026-11-08T12:00:00Z", dataset: "synthetic corpus",
                                                 passed: passed, results: []))
    }

    @Test("the shipped registry is consistent with the committed records")
    func shippedRegistryIsConsistent() throws {
        let (registry, records) = try committed()
        let report = RegistryConsistency.check(registry, records: records)
        #expect(report.violations == [], "\(report.violations.map(\.description))")
        #expect(report.standings.count == registry.capabilities.count)
    }

    @Test("the floor-gated capabilities are exactly hit detection, rally segmentation, camera-moved and line-snap")
    func floorsAreTheNamedFour() throws {
        let (registry, _) = try committed()
        let floors = Set(registry.capabilities.filter(RegistryConsistency.hasFloor).map(\.id))
        #expect(floors == ["audio.hitDetection", "rally.segmentation", "camera.movedDetection", "lineSnap"])
    }

    @Test("raising a gated capability above disabled without a passing record fails",
          arguments: ["audio.hitDetection", "rally.segmentation", "camera.movedDetection", "lineSnap"])
    func gatedAboveDisabledWithoutRecordFails(id: String) throws {
        let (registry, records) = try committed()
        let raised = try changing(registry, id) { $0.status = .estimated }
        let report = RegistryConsistency.check(raised, records: records)
        #expect(!report.isConsistent)
        #expect(report.violations == [.gatedAboveDisabledWithoutPassingRecord(capabilityId: id, status: "estimated")])
    }

    @Test("a 'validated' status without a record fails")
    func validatedWithoutRecordFails() throws {
        let (registry, records) = try committed()
        let claimed = try changing(registry, "serveSpeed.manualAssisted") { $0.status = .validated }
        let report = RegistryConsistency.check(claimed, records: records)
        #expect(report.violations == [.validatedWithoutPassingRecord(capabilityId: "serveSpeed.manualAssisted")])
    }

    @Test("an ungated 'estimated' capability without a record passes and reads 'Not benchmarked'",
          arguments: ["checkpoint.autofill", "pose.overlay2d", "serveSpeed.manualAssisted"])
    func ungatedEstimatedWithoutRecordIsNotBenchmarked(id: String) throws {
        let (registry, records) = try committed()
        let capability = try #require(registry.capability(id: id))
        #expect(capability.status == .estimated)
        #expect(capability.lastBenchmark.value == nil)
        #expect(!RegistryConsistency.hasFloor(capability))
        let report = RegistryConsistency.check(registry, records: records)
        #expect(report.isConsistent)
        #expect(report.standing(of: id) == .notBenchmarked)
        #expect(report.standing(of: id)?.label == "Not benchmarked")
    }

    @Test("a committed passing gate record lets a floor-gated capability leave disabled")
    func passingRecordAllowsEstimated() throws {
        let (registry, records) = try committed()
        let runId = "candidate.hits-gate-20261108T120000Z"
        let promoted = try changing(registry, "audio.hitDetection") {
            $0.status = .estimated
            $0.lastBenchmark = lastBenchmark(runId, passed: true)
        }
        let withRecord = records + [try passingRecord(for: "audio.hitDetection", runId: runId, records: records)]
        let report = RegistryConsistency.check(promoted, records: withRecord)
        #expect(report.isConsistent, "\(report.violations.map(\.description))")
        #expect(report.standing(of: "audio.hitDetection") == .passing(runId: runId))
    }

    @Test("a lastBenchmark that claims a pass with no committed record behind it fails")
    func unbackedPassingClaimFails() throws {
        let (registry, records) = try committed()
        let claimed = try changing(registry, "audio.hitDetection") {
            $0.status = .estimated
            $0.lastBenchmark = lastBenchmark("candidate.hits-gate-missing", passed: true)
        }
        let report = RegistryConsistency.check(claimed, records: records)
        #expect(report.violations.contains(.unbackedPassingClaim(capabilityId: "audio.hitDetection",
                                                                 runId: "candidate.hits-gate-missing")))
        #expect(report.violations.contains(.gatedAboveDisabledWithoutPassingRecord(capabilityId: "audio.hitDetection",
                                                                                   status: "estimated")))
    }

    @Test("a record for another capability does not back this one")
    func recordForAnotherCapabilityDoesNotCount() throws {
        let (registry, records) = try committed()
        let runId = "candidate.lines-gate-20261108T120000Z"
        let claimed = try changing(registry, "camera.movedDetection") {
            $0.status = .estimated
            $0.lastBenchmark = lastBenchmark(runId, passed: true)
        }
        let other = try passingRecord(for: "lineSnap", runId: runId, records: records)
        let report = RegistryConsistency.check(claimed, records: records + [other])
        #expect(!report.isConsistent)
        #expect(report.standing(of: "camera.movedDetection") == .failing(runId: runId))
    }
}
