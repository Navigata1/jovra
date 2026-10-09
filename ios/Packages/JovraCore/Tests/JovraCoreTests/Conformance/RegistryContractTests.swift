import Foundation
import Testing
@testable import JovraCore

@Test func capabilityRegistryKeepsRequiredNullAndStatus() throws {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: url.appendingPathComponent("spec").path) { url.deleteLastPathComponent() }
    let input = try Data(contentsOf: url.appendingPathComponent("spec/contracts/capability-registry.v1.json"))
    let registry = try CapabilityRegistry.load(from: input)
    #expect(registry.capability(id: "lineSnap")?.status.rawValue == "disabled")
    #expect(registry.capabilities.contains { $0.gate.value == nil })
    #expect(try CanonicalJSON.encode(registry) == CanonicalJSON.canonicalize(input))
}

@Test func otherPersistedRecordsRoundTripThroughRealTypes() throws {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: url.appendingPathComponent("spec").path) { url.deleteLastPathComponent() }
    func check<T: Codable>(_ type: T.Type, _ path: String) throws {
        let input = try Data(contentsOf: url.appendingPathComponent(path))
        let value = try ContractCodec.decode(type, from: input)
        #expect(try CanonicalJSON.encode(value) == CanonicalJSON.canonicalize(input), "Record \(path) loses data")
    }
    try check(EquipmentDocument.self, "spec/fixtures/records/equipment.sample.json")
    try check(PracticePlanDocument.self, "spec/fixtures/records/practice-plan.all-fields.json")
    try check(ArchiveManifest.self, "spec/fixtures/records/archive.all-fields.json")
    try check(ExportManifest.self, "spec/fixtures/records/export.all-fields.json")
    try check(SampleMediaManifest.self, "spec/fixtures/sample/media-manifest.json")
}
