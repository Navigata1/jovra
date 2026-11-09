import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// STU-10 (S35): every `keepers` and `staleness` vector passes in Swift, with zero mismatches against the reference's
/// stored output and the hand-derived assertions. The counts and a parity table are printed as evidence.
@Suite("Keepers: parity with keepers.py and staleness.py")
struct KeepersParityTests {
    static func cases(_ file: String) throws -> [StudioJSONValue] {
        let doc = try StudioJSONParser.parse(StudioFixtures.data("vectors/\(file).json"))
        guard case .array(let cases)? = doc["cases"] else { return [] }
        return cases
    }

    static func table(_ kind: String, _ cases: [StudioJSONValue], _ check: (StudioJSONValue) throws -> String) -> [String] {
        var mismatches: [String] = []
        print("\(kind) parity:")
        for item in cases {
            let id = (try? KeepersVectors.string(item["id"], "id")) ?? "?"
            do {
                _ = try check(item)
                print("  match     \(id)")
            } catch {
                print("  MISMATCH  \(id): \(error)")
                mismatches.append("\(id): \(error)")
            }
        }
        print("\(kind) vectors: \(cases.count) cases, \(cases.count - mismatches.count) match, \(mismatches.count) mismatch(es)")
        return mismatches
    }

    @Test("every keepers vector matches the reference and its hand assertions (zero mismatches)")
    func keepersVectors() throws {
        let cases = try Self.cases("keepers")
        let mismatches = Self.table("keepers", cases, KeepersVectors.checkKeepers)
        #expect(cases.count == 26)
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("every staleness vector matches the reference and its hand assertions (zero mismatches)")
    func stalenessVectors() throws {
        let cases = try Self.cases("staleness")
        let mismatches = Self.table("staleness", cases, KeepersVectors.checkStaleness)
        #expect(cases.count == 9)
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("the Sample film binds the canonical hash Swift computes for the final plan (the key staleness uses)")
    func sampleFilmBindsTheFinalPlan() throws {
        let plan = try StudioStaleness.planDependencies(record: StudioFixtures.data("records/edit-plan.court-memories-final.json"))
        let film = try StudioContractCodec.decode(DeliveredArtifact.self, from: StudioFixtures.data("records/delivered-artifact.film.json"))
        // the literal stored in the Sample film record, not recomputed the way the code computes it
        #expect(film.bindings.editPlanSha256 == "4d768ced3b6181944a086e7a79cfab5d7e95f86730d5262a58fca57b290a50b3")
        #expect(plan.editPlanSha256 == film.bindings.editPlanSha256)
        #expect(plan.keeperIds.contains("k-01") && !plan.keeperIds.contains("k-04"))
    }
}
