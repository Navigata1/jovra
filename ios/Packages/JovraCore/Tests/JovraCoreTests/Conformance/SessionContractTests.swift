import Foundation
import Testing
@testable import JovraCore

private var repository: URL {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: url.appendingPathComponent("spec/schemas/session.schema.json").path) {
        let parent = url.deletingLastPathComponent()
        precondition(parent != url, "Shared spec directory is required")
        url = parent
    }
    return url
}

@Test func sessionOptionalFieldsRoundTripThroughRealTypes() throws {
    let input = try Data(contentsOf: repository.appendingPathComponent("spec/fixtures/records/session.all-fields.json"))
    let session = try ContractCodec.decode(SessionDocument.self, from: input)
    #expect(session.serveMarks?.first?.contactFrame != nil)
    #expect(session.recording.captureEvents != nil)
    #expect(try CanonicalJSON.encode(session) == CanonicalJSON.canonicalize(input))
    let sample = try Data(contentsOf: repository.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json"))
    let decoded = try ContractCodec.decode(SessionDocument.self, from: sample)
    #expect(decoded.serveMarks == nil)
    #expect(decoded.match?.log.count == 124)
    #expect(try CanonicalJSON.encode(decoded) == CanonicalJSON.canonicalize(sample))
}
