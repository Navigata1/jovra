import Foundation
import XCTest
@testable import JovraCore

final class SessionStoreTests: XCTestCase {
    private func sample() throws -> SessionDocument {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    }

    func testAppendBatchSurvivesInterruptionAsNoneOrAllAndConcurrentFacetsDoNotLoseEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var document = try sample()
        document.match?.log = []
        let store = try SessionStore(root: root)
        try await store.create(document)
        let batch = (0..<5).map { SessionLogEvent.point(.init(id: "batch-\($0)", seq: $0 + 1)) }
        let crashing = try SessionStore(root: root, writeFault: { _ in throw InjectedCrash.beforeRename })
        do { try await crashing.append(batch, to: document.id); XCTFail("interrupted batch must fail") }
        catch InjectedCrash.beforeRename { }
        let unchanged = try await store.load(document.id)
        XCTAssertEqual(unchanged.match?.log.count, 0)
        try await store.append(batch, to: document.id)
        let complete = try await store.load(document.id)
        XCTAssertEqual(complete.match?.log.count, 5)
        let id = document.id
        for index in 0..<1000 {
            async let append: Void = store.append([.point(.init(id: "point-\(index)", seq: index + 6))], to: id)
            async let update: Void = store.update(id, facet: .review(.init(state: index == 999 ? .complete : .inProgress)))
            _ = try await (append, update)
        }
        let final = try await store.load(id)
        XCTAssertEqual(final.match?.log.count, 1005)
        XCTAssertEqual(final.review?.state, .complete)
        XCTAssertEqual(final.analysis, document.analysis)
        XCTAssertEqual(final.archive, document.archive)
    }

    func testZeroNegativeAndDuplicateSequenceRefusalLeavesLogUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var document = try sample(); document.match?.log = []
        let store = try SessionStore(root: root)
        try await store.create(document)
        for sequence in [0, -1] {
            do { try await store.append([.point(.init(id: "invalid", seq: sequence))], to: document.id); XCTFail("invalid sequence accepted") }
            catch SessionStoreError.invalidEvents { }
        }
        let loaded = try await store.load(document.id)
        XCTAssertEqual(loaded.match?.log.count, 0)
    }

    func testFailureAfterRenameDoesNotAcknowledgeDurabilityButNewDocumentRemainsReadable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try sample()
        let store = try SessionStore(root: root)
        try await store.create(document)
        let failing = try SessionStore(root: root, writeFault: { checkpoint in
            if case .documentRenamed = checkpoint { throw SessionStoreError.durabilityUnconfirmed(5) }
        })
        do { try await failing.update(document.id, facet: .review(.init(state: .complete))); XCTFail("unconfirmed durability must not succeed") }
        catch SessionStoreError.durabilityUnconfirmed(5) { }
        let relaunched = try SessionStore(root: root)
        let actual = try await relaunched.load(document.id)
        XCTAssertEqual(actual.review?.state, .complete)
        XCTAssertEqual(actual.match, document.match)
    }

    func testCreateSurvivesStoreRelaunchAndInterruptedWriteKeepsPreviousDocument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try sample()
        let store = try SessionStore(root: root)
        try await store.create(document)
        let relaunched = try SessionStore(root: root)
        let loaded = try await relaunched.load(document.id)
        XCTAssertEqual(loaded, document)
        let crashing = try SessionStore(root: root, writeFault: { _ in throw InjectedCrash.beforeRename })
        do {
            try await crashing.update(document.id, facet: .review(.init(state: .complete)))
            XCTFail("injected interrupted write must fail")
        } catch InjectedCrash.beforeRename { }
        let recovered = try SessionStore(root: root)
        let afterCrash = try await recovered.load(document.id)
        XCTAssertEqual(afterCrash, document)
    }
}

private enum InjectedCrash: Error { case beforeRename }
