import Foundation
import Testing
import JovraCore

@Test(arguments: [true, false])
func sessionCreationDoesNotAcknowledgeAReplacedSessionsDirectory(symbolicLink: Bool) async throws {
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<7 { repo.deleteLastPathComponent() }
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: repo.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let sessions = root.appendingPathComponent("sessions")
    let retained = root.appendingPathComponent("retained-sessions")
    let store = try SessionStore(root: root, writeFault: { checkpoint in
        if case .documentRenamed = checkpoint {
            try FileManager.default.moveItem(at: sessions, to: retained)
            if symbolicLink { try FileManager.default.createSymbolicLink(at: sessions, withDestinationURL: retained) }
            else { try FileManager.default.createDirectory(at: sessions.appendingPathComponent(document.id), withIntermediateDirectories: true) }
        }
    })
    await #expect(throws: (any Error).self) { try await store.create(document) }
    let retainedDocument = retained.appendingPathComponent(document.id).appendingPathComponent("session.json")
    #expect(try Data(contentsOf: retainedDocument) == CanonicalJSON.encode(document), "A refused acknowledgment must not erase an already renamed document through a replaced parent")
    if !symbolicLink { #expect(FileManager.default.fileExists(atPath: sessions.appendingPathComponent(document.id).path), "Both owned trees remain for inspection") }
}
