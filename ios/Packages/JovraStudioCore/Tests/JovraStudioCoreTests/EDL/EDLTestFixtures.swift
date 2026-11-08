import Foundation
import JovraStudioCore

/// The shared Sample project as the EDL tests see it: the story-profile catalog, the trusted context built from the
/// stored records (never from a plan), the edit-plan records and the edit-plan invalid cases.
enum EDLTestFixtures {
    struct InvalidCase {
        let file: String
        let id: String
        /// "schema" or "reference" (spec/studio/fixtures/invalid).
        let layer: String
        /// The reference's code for a reference-layer case.
        let code: String?
        let plan: StudioJSONValue
    }

    static func json(_ relativePath: String) throws -> StudioJSONValue {
        try StudioJSONParser.parse(StudioFixtures.data(relativePath))
    }

    static func record<T: StudioContract>(_ type: T.Type, _ name: String) throws -> T {
        try StudioContractCodec.decode(type, from: StudioFixtures.data("records/\(name).json"))
    }

    static func profiles() throws -> StoryProfileCatalog {
        let url = StudioFixtures.repositoryRoot().appendingPathComponent("spec/studio/contracts/story-profiles.v1.json")
        return try StudioContractCodec.decode(StoryProfileCatalog.self, from: Data(contentsOf: url))
    }

    static func validator() throws -> EDLValidator { EDLValidator(profiles: try profiles()) }

    /// `bundle.edl_context` of the Sample project, built from its stored records.
    static func context() throws -> EDLTrustedContext {
        EDLTrustedContext.build(manifest: try record(SourceManifest.self, "source-manifest"),
                                syncMap: try record(SyncMap.self, "sync-map"),
                                keepers: try record(KeeperCatalog.self, "keeper-catalog"),
                                brolls: try record(BrollCatalog.self, "broll-catalog"),
                                references: try record(ReferenceCatalog.self, "reference-catalog"))
    }

    /// Every `edit-plan.*.json` record, by name without the extension.
    static func plans() throws -> [(name: String, plan: StudioJSONValue)] {
        let folder = try StudioFixtures.url("records")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("edit-plan.") && $0.hasSuffix(".json") }.sorted()
            .map { (String($0.dropLast(5)), try json("records/\($0)")) }
    }

    static func invalidCases() throws -> [InvalidCase] {
        let folder = try StudioFixtures.url("invalid")
        var out: [InvalidCase] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter({ $0.hasPrefix("edit-plan.") && $0.hasSuffix(".json") }).sorted() {
            let file = try json("invalid/\(name)")
            guard case .string(let base)? = file["base"], case .array(let cases)? = file["cases"] else { continue }
            let record = try json(base)
            for item in cases {
                guard case .string(let id)? = item["id"], case .string(let layer)? = item["expect"]?["layer"],
                      let patch = item["patch"] else { continue }
                var code: String?
                if case .string(let c)? = item["expect"]?["code"] { code = c }
                out.append(InvalidCase(file: name, id: id, layer: layer, code: code,
                                       plan: try StudioJSONPatch.apply(patch, to: record)))
            }
        }
        return out
    }

    static func invalidCase(_ file: String, _ id: String) throws -> InvalidCase {
        guard let found = try invalidCases().first(where: { $0.file == "edit-plan.\(file).invalid.json" && $0.id == id }) else {
            throw StudioJSONPatch.PatchError(description: "no invalid case \(file)#\(id)")
        }
        return found
    }

    /// Python's `json.dumps(value, indent=2, ensure_ascii=False) + "\n"`, the writer of the shared fixture files, so a
    /// derived document can be compared with a fixture byte for byte.
    static func pythonIndented(_ value: StudioJSONValue) -> Data {
        var out = ""
        write(value, level: 0, into: &out)
        return Data((out + "\n").utf8)
    }

    private static func write(_ value: StudioJSONValue, level: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: level + 1), close = String(repeating: "  ", count: level)
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n.text
        case .string(let s): quote(s, into: &out)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                write(item, level: level + 1, into: &out)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += close + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, member) in members.enumerated() {
                out += pad
                quote(member.key, into: &out)
                out += ": "
                write(member.value, level: level + 1, into: &out)
                out += i == members.count - 1 ? "\n" : ",\n"
            }
            out += close + "}"
        }
    }

    private static func quote(_ text: String, into out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0..<0x20:
                let hex = String(scalar.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}
