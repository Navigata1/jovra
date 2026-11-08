import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// Negative tests of the strict decoder (STU-01): integral floats, unknown properties, duplicate names, the wrong
/// contract, and a writer that refuses to emit a document the reader would refuse.
@Suite("Studio contracts: strict decoding")
struct ContractsStrictDecoderTests {
    static func patched(_ fixture: String, _ patch: String) throws -> Data {
        let base = try StudioJSONParser.parse(StudioFixtures.data(fixture))
        return try StudioJSONPatch.apply(StudioJSONParser.parse(Data(patch.utf8)), to: base).serialized()
    }

    static func schemaErrors(_ body: () throws -> Void) -> [String] {
        do { try body() } catch StudioContractError.schema(let errors) { return errors } catch { return ["other: \(error)"] }
        return []
    }

    @Test("an integral float (744.0) in a frame field is refused; 744 is accepted")
    func integralFloatFrame() throws {
        let fixture = "records/edit-plan.court-memories-storyboard.json"
        let float = try Self.patched(fixture, #"[{"op": "replace", "path": "/segments/1/sourceInFrame", "value": 744.0}]"#)
        let errors = Self.schemaErrors { _ = try StudioContractCodec.decode(EditPlan.self, from: float) }
        // Segment 1 is a oneOf member, so the error names the closest member's failure.
        #expect(errors.contains { $0.contains("$.segments[1].sourceInFrame: expected type [\"integer\"], got number") }, "\(errors)")

        let integer = try Self.patched(fixture, #"[{"op": "replace", "path": "/segments/1/sourceInFrame", "value": 744}]"#)
        let plan = try StudioContractCodec.decode(EditPlan.self, from: integer)
        guard case .live(let segment) = plan.segments[1] else {
            Issue.record("segment 1 of the fixture is not a live segment")
            return
        }
        #expect(segment.sourceInFrame == 744)
    }

    @Test("an exponent integer (7.44e2) is not an integer either")
    func exponentIsNotInteger() throws {
        let data = try Self.patched("records/project-lock.json", #"[{"op": "replace", "path": "/revision", "value": 1e0}]"#)
        let errors = Self.schemaErrors { _ = try StudioContractCodec.decode(ProjectLock.self, from: data) }
        #expect(errors.contains("$.revision: expected type [\"integer\"], got number"), "\(errors)")
    }

    @Test("an unknown property is refused, at the root and nested")
    func unknownProperty() throws {
        let root = try Self.patched("records/observation.estimated-cue.json", #"[{"op": "add", "path": "/spinRpm", "value": 3000}]"#)
        let rootErrors = Self.schemaErrors { _ = try StudioContractCodec.decode(Observation.self, from: root) }
        #expect(rootErrors.contains { $0.hasPrefix("$.spinRpm: unknown property") }, "\(rootErrors)")

        let nested = try Self.patched("records/observation.estimated-cue.json", #"[{"op": "add", "path": "/provenance/certainty", "value": "high"}]"#)
        let nestedErrors = Self.schemaErrors { _ = try StudioContractCodec.decode(Observation.self, from: nested) }
        #expect(nestedErrors.contains { $0.hasPrefix("$.provenance.certainty: unknown property") }, "\(nestedErrors)")
    }

    @Test("a duplicate member name is refused before any schema check")
    func duplicateName() {
        let data = Data(#"{"schemaVersion": "jovra.observation/1", "schemaVersion": "jovra.observation/1"}"#.utf8)
        #expect(throws: StudioContractError.unreadable("duplicate member name \"schemaVersion\"")) {
            try StudioContractCodec.decode(Observation.self, from: data)
        }
    }

    @Test("a document of another contract is refused by name")
    func wrongContract() throws {
        let data = try StudioFixtures.data("records/project-lock.json")
        #expect(throws: StudioContractError.wrongSchemaVersion(expected: "jovra.lesson/1", found: "jovra.project-lock/1")) {
            try StudioContractCodec.decode(Lesson.self, from: data)
        }
    }

    @Test("decimals survive exactly: an observation's confidence 0.62 round-trips as 0.62")
    func decimalConfidence() throws {
        let data = try StudioFixtures.data("records/observation.estimated-cue.json")
        let observation = try StudioContractCodec.decode(Observation.self, from: data)
        #expect(observation.provenance.confidence.value == Decimal(string: "0.62"))
        #expect(String(decoding: try StudioContractCodec.encode(observation), as: UTF8.self).contains(#""confidence":0.62"#))
    }

    @Test("the writer refuses a value that breaks its schema (an id ending in a newline)")
    func writerRefusesInvalidValue() throws {
        var observation = try StudioContractCodec.decode(Observation.self, from: StudioFixtures.data("records/observation.estimated-cue.json"))
        observation.observationId = "obs-01\n"
        let errors = Self.schemaErrors { _ = try StudioContractCodec.encode(observation) }
        #expect(errors.contains { $0.hasPrefix("$.observationId:") }, "\(errors)")
    }

    @Test("explicit null and absence stay distinct: a required nullable field must be present")
    func requiredNullableMustBePresent() throws {
        let data = try Self.patched("records/observation.estimated-cue.json", #"[{"op": "remove", "path": "/textRef"}]"#)
        let errors = Self.schemaErrors { _ = try StudioContractCodec.decode(Observation.self, from: data) }
        #expect(errors.contains("$: missing required property \"textRef\""), "\(errors)")
    }

    @Test("malformed JSON is unreadable, never partially decoded", arguments: [
        #"{"schemaVersion": "jovra.observation/1""#, "[1, 2", #"{"a": 01}"#, #"{"a": "\ud800"}"#, "{} {}",
    ])
    func malformed(_ text: String) {
        #expect(throws: StudioJSONParser.ParseError.self) { try StudioJSONParser.parse(Data(text.utf8)) }
    }
}
