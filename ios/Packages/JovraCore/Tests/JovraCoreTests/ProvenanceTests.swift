import Foundation
import Testing
import JovraCore

@Suite("Provenance")
struct ProvenanceTests {
    @Test("decodes the four persisted provenance values")
    func decodesContractValues() throws {
        let json = Data(#"["manual","estimated","reviewed","validated"]"#.utf8)
        let decoded = try JSONDecoder().decode([Provenance].self, from: json)
        #expect(decoded == [.manual, .estimated, .reviewed, .validated])
    }

    @Test("encodes to the same lowercase strings")
    func encodesContractValues() throws {
        let data = try JSONEncoder().encode([Provenance.reviewed])
        #expect(String(decoding: data, as: UTF8.self) == #"["reviewed"]"#)
    }

    @Test("rejects values outside the contract")
    func rejectsUnknown() {
        let json = Data(#"["measured"]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([Provenance].self, from: json)
        }
    }

}
