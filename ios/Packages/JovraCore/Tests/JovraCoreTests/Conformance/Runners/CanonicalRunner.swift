// fixture-kind: jovra.fixture.canonical
import Foundation
import Testing
@testable import JovraCore
struct CanonicalRunner: FixtureRunner {
    let kind = "jovra.fixture.canonical"
    private struct Fixture: Decodable { var cases: [Case] }
    private struct Case: Decodable { var id: String, input: String, canonical: String }
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        for vector in fixture.cases {
            #expect(try CanonicalJSON.canonicalize(Data(vector.input.utf8)) == Data(vector.canonical.utf8), "Independent vector \(vector.id)")
        }
        print("canonical independent vectors: \(fixture.cases.count)")
    }
}
