import Foundation
import Testing
import JovraStudioCore

/// STU-01: every schema-layer invalid case under spec/studio/fixtures/invalid whose base record has a registered
/// decoder is refused by the Swift decoder. Reference-layer cases pass the schema by construction; they are decoded
/// here only to show the decoder is not stricter than the contract, except where this port is deliberately stricter
/// (an integral float in an integer field). Their codes belong to the module tickets that port each reference rule.
@Suite("Studio contracts: invalid cases")
struct ContractsInvalidCaseTests {
    struct Case {
        let file: String
        let id: String
        let layer: String
        let version: String
        let document: Data
        let patch: StudioJSONValue
    }

    static func cases() throws -> [Case] {
        let folder = try StudioFixtures.url("invalid")
        var out: [Case] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ $0.hasSuffix(".json") }).sorted() {
            let file = try StudioJSONParser.parse(Data(contentsOf: folder.appendingPathComponent(name)))
            guard case .string(let base)? = file["base"], case .array(let cases)? = file["cases"] else {
                Issue.record("invalid/\(name) has no base or cases")
                continue
            }
            let record = try StudioJSONParser.parse(StudioFixtures.data(base))
            guard case .string(let version)? = record["schemaVersion"] else { continue }
            for item in cases {
                guard case .string(let id)? = item["id"], case .string(let layer)? = item["expect"]?["layer"], let patch = item["patch"]
                else {
                    Issue.record("invalid/\(name) has a malformed case")
                    continue
                }
                let bad = try StudioJSONPatch.apply(patch, to: record)
                out.append(Case(file: name, id: id, layer: layer, version: version, document: bad.serialized(), patch: patch))
            }
        }
        return out
    }

    @Test("every schema-layer invalid case of a registered schema is refused")
    func schemaLayerCasesAreRefused() throws {
        let decoders = StudioConsumption.discovered.decoders
        var refused = 0, skipped: [String: Int] = [:]
        for item in try Self.cases() where item.layer == "schema" {
            guard let decoder = decoders[item.version] else {
                skipped[item.version, default: 0] += 1
                continue
            }
            do {
                _ = try decoder.roundTrip(item.document)
                Issue.record("\(item.file)#\(item.id): the Swift decoder accepted a schema-layer invalid case")
            } catch {
                refused += 1
                print("  refused \(item.file)#\(item.id): \(String(describing: error).prefix(160))")
            }
        }
        print("Studio invalid cases (schema layer): \(refused) refused; unregistered schemas skipped: \(skipped.sorted(by: { $0.key < $1.key }))")
        #expect(refused > 0)
    }

    @Test("the trailing-newline id and hash cases are refused, although Python's re.search accepts them (finding 6)")
    func trailingNewlineCasesAreRefused() throws {
        let decoders = StudioConsumption.discovered.decoders
        let newline = try Self.cases().filter { item in
            guard case .array(let ops) = item.patch else { return false }
            return ops.contains { if case .string(let s)? = $0["value"] { s.hasSuffix("\n") } else { false } }
        }
        #expect(newline.count >= 2, "expected the lesson-id and plan-hash cases")
        for item in newline {
            let decoder = try #require(decoders[item.version], "\(item.version) has no registered decoder")
            #expect(throws: StudioContractError.self, "\(item.file)#\(item.id)") { try decoder.roundTrip(item.document) }
            print("  refused trailing newline: \(item.file)#\(item.id)")
        }
        // The same value passes a `$` that also matches before a final newline (Python re, ICU, java.util.regex).
        let python = try NSRegularExpression(pattern: "^[0-9a-f]{64}$")
        let ecma = try NSRegularExpression(pattern: StudioSchemaSet.ecmaPattern("^[0-9a-f]{64}$"))
        let hash = String(repeating: "a", count: 64) + "\n"
        let range = NSRange(hash.startIndex..<hash.endIndex, in: hash)
        #expect(python.firstMatch(in: hash, range: range) != nil)
        #expect(ecma.firstMatch(in: hash, range: range) == nil)
    }

    @Test("reference-layer cases pass the Swift decoder unless they carry an integral float")
    func referenceLayerCasesDecode() throws {
        let decoders = StudioConsumption.discovered.decoders
        var decoded = 0
        var stricter: [String] = []
        for item in try Self.cases() where item.layer == "reference" {
            guard let decoder = decoders[item.version] else { continue }
            do {
                _ = try decoder.roundTrip(item.document)
                decoded += 1
            } catch StudioContractError.schema(let errors) where errors.contains(where: { $0.contains("expected type [\"integer\"], got number") }) {
                stricter.append("\(item.file)#\(item.id)")
            } catch {
                Issue.record("\(item.file)#\(item.id): reference-layer case refused by the decoder: \(error)")
            }
        }
        print("Studio invalid cases (reference layer): \(decoded) decode (their rules belong to the module tickets); refused as integral floats: \(stricter)")
        #expect(stricter.contains("edit-plan.court-memories-storyboard.invalid.json#integral-float-frame"))
    }
}
