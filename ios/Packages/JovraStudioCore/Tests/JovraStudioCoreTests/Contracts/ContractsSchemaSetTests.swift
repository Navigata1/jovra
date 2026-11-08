import Foundation
import Testing
import JovraStudioCore

/// The embedded schema set is the shared one, unchanged, and uses only what this checker implements.
@Suite("Studio contracts: schema set")
struct ContractsSchemaSetTests {
    @Test("the embedded schemas equal spec/schemas/studio byte for byte, and the models were generated from them")
    func embeddedSchemasMatchTheSpec() throws {
        let folder = StudioFixtures.repositoryRoot().appendingPathComponent("spec/schemas/studio")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".schema.json") }.sorted()
        let regenerate = "run python3 ios/Packages/JovraStudioCore/Tools/generate_contract_models.py"
        #expect(names == StudioSchemaSource.files.keys.sorted(), "schema files added or removed; \(regenerate)")
        for name in names {
            var text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            if text.hasSuffix("\n") { text.removeLast() }
            #expect(StudioSchemaSource.files[name] == text, "\(name) changed since generation; \(regenerate)")
        }
        #expect(StudioSchemaSource.embeddedDigest == StudioContractModels.schemaDigest, "models are stale; \(regenerate)")
    }

    @Test("every keyword the Studio schemas use is implemented, every $ref resolves, every pattern is portable")
    func schemasUseOnlySupportedKeywords() {
        #expect(StudioSchemaSet.studio.problems.isEmpty, "\(StudioSchemaSet.studio.problems)")
    }

    @Test("the loader reports an unsupported keyword, a dangling $ref and a non-portable escape")
    func loaderReportsProblems() throws {
        let set = try StudioSchemaSet(files: [
            "a.schema.json": #"{"type": "object", "unevaluatedProperties": false, "properties": {"x": {"$ref": "b.schema.json#/$defs/y"}, "z": {"type": "string", "pattern": "^\\d+$"}}}"#,
        ])
        #expect(set.problems.contains { $0.contains("unsupported keyword \"unevaluatedProperties\"") })
        #expect(set.problems.contains { $0.contains("unresolvable $ref b.schema.json#/$defs/y") })
        #expect(set.problems.contains { $0.contains("uses \\d") })
    }

    @Test("ECMA-262 anchors: $ is rewritten outside character classes only", arguments: [
        ("^[a-z]+$", #"^[a-z]+\z"#), ("^[$]$", #"^[$]\z"#), (#"^a\$$"#, #"^a\$\z"#), ("^(a|b)$", #"^(a|b)\z"#),
    ])
    func ecmaRewrite(_ pattern: String, _ expected: String) {
        #expect(StudioSchemaSet.ecmaPattern(pattern) == expected)
    }

    @Test("an id pattern refuses a trailing newline and accepts the id")
    func idPattern() throws {
        let set = try StudioSchemaSet(files: ["s.schema.json": #"{"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"}"#])
        let at = StudioSchemaLocation(file: "s.schema.json")
        #expect(set.validate(.string("lesson-01"), against: at).isEmpty)
        #expect(!set.validate(.string("lesson-01\n"), against: at).isEmpty)
    }

    @Test("oneOf needs exactly one match, if/then applies only when the condition holds")
    func applicators() throws {
        let set = try StudioSchemaSet(files: ["s.schema.json": #"""
            {"type": "object", "additionalProperties": false,
             "properties": {"kind": {"enum": ["a", "b"]}, "n": {"oneOf": [{"type": "integer"}, {"type": "integer", "minimum": 5}]}},
             "if": {"properties": {"kind": {"const": "a"}}}, "then": {"required": ["n"]}}
            """#])
        let at = StudioSchemaLocation(file: "s.schema.json")
        func check(_ text: String) throws -> [String] { set.validate(try StudioJSONParser.parse(Data(text.utf8)), against: at) }
        #expect(try check(#"{"kind": "b"}"#).isEmpty)
        #expect(try check(#"{"kind": "a"}"#) == [#"$: missing required property "n""#])
        #expect(try check(#"{"kind": "b", "n": 1}"#).isEmpty)
        #expect(try check(#"{"kind": "b", "n": 7}"#).contains { $0.contains("matches 2 of oneOf") })
    }
}
