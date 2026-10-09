import Foundation
import Testing
@testable import JovraCore

@Test func nativeScoringInputsAndOutputsKeepEveryGoldenField() throws {
    let root = try FixtureManifest.repository()
    let paths = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("spec/fixtures/scoring"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
    var outputs = 0
    for path in paths {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        let input = try JSONSerialization.data(withJSONObject: fixture["input"]!)
        #expect(try CanonicalJSON.encode(ScoringInput.decode(input)) == CanonicalJSON.canonicalize(input))
        for checkpoint in fixture["checkpoints"] as? [[String: Any]] ?? [] {
            let fold = (checkpoint["expected"] as! [String: Any])["fold"]!
            let bytes = try JSONSerialization.data(withJSONObject: fold)
            let value = try ContractCodec.decode(MatchTimeline.self, from: bytes)
            #expect(try CanonicalJSON.encode(value) == CanonicalJSON.canonicalize(bytes), "\(path.lastPathComponent)")
            outputs += 1
        }
    }
    #expect(outputs >= 105)
    print("Concrete native scoring contracts: \(paths.count) inputs, \(outputs) complete outputs")
}

@Test func matchSessionBridgeKeepsStoredAuthoritativeValues() throws {
    let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: path))
    let input = try ScoringInput(session: document)
    #expect(input.players == document.players)
    #expect(input.log == document.match?.log)
    #expect(input.format == document.match?.format)
    #expect(input.resolutionMode == document.match?.resolutionMode)
}
