import Foundation
import Testing
import JovraStudioCore

/// Smoke test for the package (S04): a Studio record read from the shared fixtures names its contract and whether it
/// is Sample data. Full Codable models for every contract arrive with S10.
@Suite("Studio record header")
struct RecordHeaderTests {
    @Test("the Sample project lock names jovra.project-lock version 1 and is Sample data")
    func projectLockHeader() throws {
        let header = try StudioRecordHeader(json: StudioFixtures.data("records/project-lock.json"))

        #expect(header.schemaVersion == StudioSchemaVersion(kind: "project-lock", version: 1))
        #expect(header.isSample == true)
    }

    @Test("an edit plan names version 2 of its contract")
    func editPlanVersion() throws {
        let header = try StudioRecordHeader(json: StudioFixtures.data("records/edit-plan.rally-pulse-portrait.json"))

        #expect(header.schemaVersion.kind == "edit-plan")
        #expect(header.schemaVersion.version == 2)
        #expect(header.schemaVersion.description == "jovra.edit-plan/2")
    }

    @Test(
        "a schema version is refused unless it is exactly jovra.<kind>/<positive integer>",
        arguments: [
            "jovra.project-lock/1\n", // ECMA-262 `$` semantics: a trailing newline is not the end of the value
            "jovra.project-lock",
            "jovra.project-lock/0",
            "jovra.project-lock/01",
            "jovra.project-lock/1.0",
            "jovra.Project-Lock/1",
            "jovra./1",
            "JOVRA.project-lock/1",
            "other.project-lock/1",
            " jovra.project-lock/1",
        ]
    )
    func refusesMalformedVersion(_ text: String) {
        #expect(StudioSchemaVersion(text) == nil)
    }

    @Test("a record that is not a JSON object with a schemaVersion string is an error")
    func refusesRecordWithoutSchemaVersion() {
        #expect(throws: StudioRecordHeader.ReadError.self) {
            try StudioRecordHeader(json: Data(#"[1, 2]"#.utf8))
        }
        #expect(throws: StudioRecordHeader.ReadError.self) {
            try StudioRecordHeader(json: Data(#"{"sample": true}"#.utf8))
        }
        #expect(throws: StudioRecordHeader.ReadError.self) {
            try StudioRecordHeader(json: Data(#"{"schemaVersion": "jovra.quote"}"#.utf8))
        }
        // A sample flag that is not a JSON boolean is refused on every platform (no NSNumber bridging to true).
        #expect(throws: StudioRecordHeader.ReadError.self) {
            try StudioRecordHeader(json: Data(#"{"schemaVersion": "jovra.quote/1", "sample": 1}"#.utf8))
        }
    }

    @Test("a record without a sample flag is not Sample data")
    func missingSampleFlagIsNotSample() throws {
        let header = try StudioRecordHeader(json: Data(#"{"schemaVersion": "jovra.quote/1"}"#.utf8))

        #expect(header.isSample == false)
    }
}
