import Foundation
import Testing
import JovraStudioCore

/// The Swift fixture manifest (STU-01). On the repository it must pass; on a temporary copy it fails for a new kind
/// with no module page and for a page that says `swift: consumed` with no Swift consumer, and passes once the new
/// kind's page says `swift: pending`.
@Suite("Studio contracts: fixture manifest")
struct ContractsFixtureManifestTests {
    static var root: URL { StudioFixtures.repositoryRoot() }

    static func check(_ base: URL, consumed: Set<String> = StudioConsumption.discovered.kinds) throws -> StudioFixtureManifest.Report {
        try StudioFixtureManifest.check(fixtures: base.appendingPathComponent("spec/studio/fixtures"),
                                        contracts: base.appendingPathComponent("spec/studio/contracts"),
                                        modules: base.appendingPathComponent("spec/studio/modules"), consumed: consumed)
    }

    /// A temporary copy of spec/studio (fixtures, contracts and module pages), removed by the caller.
    static func copy() throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("studio-manifest-\(UUID().uuidString)")
        let target = temp.appendingPathComponent("spec/studio")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for folder in ["fixtures", "contracts", "modules"] {
            try FileManager.default.copyItem(at: root.appendingPathComponent("spec/studio/\(folder)"), to: target.appendingPathComponent(folder))
        }
        return temp
    }

    static let newVector = #"{"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "brand-new-kind", "cases": []}"#

    @Test("the repository's fixtures, module pages and Swift consumers agree")
    func repositoryPasses() throws {
        let consumption = StudioConsumption.discovered
        #expect(consumption.conflicts.isEmpty, "\(consumption.conflicts)")
        let report = try Self.check(Self.root)
        print("Studio fixture manifest: \(report.rows.count) kinds; consumers: \(generatedStudioConsumers.map { String(describing: type(of: $0)) })")
        for row in report.rows {
            print("  \(row.kind) page=\(row.page ?? "-") swift=\(row.swift ?? "-") consumed=\(row.consumed) files=\(row.files)")
        }
        for failure in report.failures { print("  FAIL \(failure)") }
        #expect(report.failures.isEmpty, "\(report.failures)")
    }

    @Test("a new fixture kind with no module page fails")
    func newKindWithoutPageFails() throws {
        let temp = try Self.copy()
        defer { try? FileManager.default.removeItem(at: temp) }
        try Data(Self.newVector.utf8).write(to: temp.appendingPathComponent("spec/studio/fixtures/vectors/brand-new.json"))
        let report = try Self.check(temp)
        #expect(report.failures.contains("kind brand-new-kind has no module page (1 fixture file(s) state it)"), "\(report.failures)")
    }

    @Test("a new kind whose page says swift: pending passes unconsumed")
    func newKindPendingPasses() throws {
        let temp = try Self.copy()
        defer { try? FileManager.default.removeItem(at: temp) }
        try Data(Self.newVector.utf8).write(to: temp.appendingPathComponent("spec/studio/fixtures/vectors/brand-new.json"))
        let page = "---\nmodule: brandnew\nreference: []\ncases: []\nkinds: [brand-new-kind]\ncoverage: covered\nswift: pending\nkotlin: pending\n---\n"
        try Data(page.utf8).write(to: temp.appendingPathComponent("spec/studio/modules/brandnew.md"))
        let report = try Self.check(temp)
        #expect(report.failures.isEmpty, "\(report.failures)")
        #expect(report.rows.contains(.init(kind: "brand-new-kind", page: "brandnew", swift: "pending", consumed: false, files: 1)))
    }

    @Test("a page that says swift: consumed with no Swift consumer fails")
    func consumedWithoutConsumerFails() throws {
        let temp = try Self.copy()
        defer { try? FileManager.default.removeItem(at: temp) }
        let page = temp.appendingPathComponent("spec/studio/modules/sync.md")
        let text = try String(contentsOf: page, encoding: .utf8)
        try Data(text.replacingOccurrences(of: "\nswift: pending\n", with: "\nswift: consumed\n").utf8).write(to: page)
        let report = try Self.check(temp)
        #expect(report.failures.contains("page sync says swift: consumed, but kind sync-fit has no registered Swift consumer"), "\(report.failures)")
        // jovra.sync-map/1 is decoded by ContractsConsumer, so only the page's vector kinds are reported.
        #expect(!report.failures.contains { $0.contains("kind jovra.sync-map/1 has no") })
    }

    @Test("the records page is consumed only while its decoders stay registered")
    func recordsPageNeedsItsDecoders() throws {
        var consumed = StudioConsumption.discovered.kinds
        consumed.remove("jovra.lesson/1")
        let report = try Self.check(Self.root, consumed: consumed)
        #expect(report.failures == ["page records says swift: consumed, but kind jovra.lesson/1 has no registered Swift consumer"])
    }
}
