import Foundation
import Testing
import JovraStudioCore

/// Runs every registered vector checker over every case of the vector files of its kind. STU-01 registers none (its
/// pages hold only schema kinds); module tickets register theirs in their own `<Name>Consumer.swift`.
@Suite("Studio contracts: vector consumers")
struct ContractsVectorTests {
    @Test("every registered vector checker runs on at least one case of its kind")
    func registeredCheckersRun() throws {
        let checkers = StudioConsumption.discovered.vectorCheckers
        let folder = try StudioFixtures.url("vectors")
        var ran: [String: Int] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ $0.hasSuffix(".json") }).sorted() {
            let file = try StudioJSONParser.parse(Data(contentsOf: folder.appendingPathComponent(name)))
            guard case .string(let kind)? = file["kind"], let checker = checkers[kind], case .array(let cases)? = file["cases"] else { continue }
            for item in cases {
                try checker(item)
                ran[kind, default: 0] += 1
            }
        }
        print("Studio vector cases run by Swift checkers: \(ran.sorted(by: { $0.key < $1.key }))")
        for kind in checkers.keys { #expect(ran[kind, default: 0] > 0, "checker for \(kind) found no cases") }
    }
}
