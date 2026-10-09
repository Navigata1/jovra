import Foundation
import XCTest
@testable import JovraCore

final class SessionStoreTests: XCTestCase {
    private static func point(id: String, seq: Int) -> SessionLogEvent {
        .point(.init(id: id, seq: seq, reviewed: .init(winner: .a, endType: .winner,
             provenance: .manual, source: "user"), reviewState: .reviewed))
    }

    private func sample() throws -> SessionDocument {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    }

    func testIndexRebuildAndCorruptSessionQuarantinePreserveHealthySessions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let first = try sample()
        var second = first
        second.id = "second-session"
        second.sample = nil
        second.notes = "Clay court. Work on return."
        try await store.create(first)
        try await store.create(second)
        let before = try await store.list()
        XCTAssertEqual(before.count, 2)
        try FileManager.default.removeItem(at: root.appendingPathComponent("index.json"))
        let rebuilt = try await store.list()
        XCTAssertEqual(before, rebuilt)
        let searched = try await store.list(.init(search: "clay", sample: false))
        XCTAssertEqual(searched.map(\.id), ["second-session"])
        try Data("{broken".utf8).write(to: root.appendingPathComponent("sessions/second-session/session.json"))
        let healthy = try await store.list()
        XCTAssertEqual(healthy.map(\.id), [first.id])
        let quarantine = try await store.quarantinedSessions()
        XCTAssertEqual(quarantine.map(\.sessionID), ["second-session"])
        let record = try XCTUnwrap(quarantine.first)
        XCTAssertFalse(record.reason.isEmpty)
    }

    func testOlderDocumentMigratesAndOpponentQueriesExcludeSamples() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        var document = try sample()
        try await store.create(document)
        document.id = "real-legacy"
        document.sample = nil
        document.schemaVersion = .v1
        try await store.create(document)
        _ = try await store.rebuildIndex()
        let migrated = try await store.load(document.id)
        XCTAssertEqual(migrated.schemaVersion, .current)
        XCTAssertEqual(migrated.match, document.match)
        if let directory = ProcessInfo.processInfo.environment["JOVRA_QUERY_EVIDENCE_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try CanonicalJSON.encode(migrated).write(to: url.appendingPathComponent("session.json"))
        }
        let migratedAgain = try await store.migrate(migrated)
        XCTAssertEqual(migratedAgain, migrated)
        let selfID = try XCTUnwrap(document.players.first(where: \.isSelf)?.id)
        let opponent = try XCTUnwrap(document.players.first(where: { !$0.isSelf })?.id)
        let history = try await store.opponentHistory(playerID: selfID, opponentID: opponent)
        XCTAssertEqual(history.map(\.id), ["real-legacy"])
        let headToHead = try await store.headToHead(playerID: selfID, opponentID: opponent)
        XCTAssertEqual(headToHead.map(\.id), ["real-legacy"])
        let reopened = try SessionStore(root: root)
        let retained = try await reopened.load(document.id)
        XCTAssertEqual(retained, migrated)
    }

    func testFutureDocumentAndInvalidFolderArePreservedWithoutHidingHealthySession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let healthy = try sample()
        try await store.create(healthy)
        var future = healthy
        future.id = "future"
        future.schemaVersion = try SchemaVersion("1.3.0")
        try await store.create(future)
        let weird = root.appendingPathComponent("sessions/invalid name")
        try FileManager.default.createDirectory(at: weird, withIntermediateDirectories: true)
        try Data("preserve-me".utf8).write(to: weird.appendingPathComponent("original.mp4"))
        let listed = try await store.list()
        XCTAssertEqual(listed.map(\.id), [healthy.id])
        let records = try await store.quarantinedSessions()
        XCTAssertEqual(Set(records.map(\.sessionID)), ["future", "invalid name"])
        let record = try XCTUnwrap(records.first(where: { $0.sessionID == "invalid name" }))
        let kept = root.appendingPathComponent("quarantine/\(record.folderName)/session/original.mp4")
        XCTAssertEqual(try Data(contentsOf: kept), Data("preserve-me".utf8))
    }

    func testFiltersAndOpponentQueriesDistinguishTeamsAndExcludeSamples() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        var document = try sample()
        try await store.create(document)
        document.id = "real-doubles"
        document.sample = nil
        document.schemaVersion = .current
        var teammate = document.players[0]
        teammate.id = "teammate"; teammate.displayName = "Team mate"; teammate.isSelf = false
        var opponentPartner = document.players[1]
        opponentPartner.id = "opponent-partner"; opponentPartner.isSelf = false
        document.players += [teammate, opponentPartner]
        document.sides = .init(A: [document.players[0].id, teammate.id], B: [document.players[1].id, opponentPartner.id])
        document.match?.log = [.doublesOrder(.init(id: "order", seq: 1, setIndex: 0,
            firstServer: document.players[0].id, secondServer: document.players[1].id,
            deuceReceivers: .init(A: document.players[0].id, B: document.players[1].id)))]
        document.marks = nil; document.shots = nil
        document.original = .init(state: .saved)
        document.analysis = .init(state: .notRequested, runs: [])
        document.review = .init(state: .inProgress)
        try await store.create(document)
        let filtered = try await store.list(.init(search: "team MATE", kind: .match, sample: false,
            original: .saved, analysis: .notRequested, review: .inProgress, archive: .localOnly))
        XCTAssertEqual(filtered.map(\.id), [document.id])
        let selfID = document.players[0].id
        let teammateHistory = try await store.opponentHistory(playerID: selfID, opponentID: teammate.id)
        XCTAssertTrue(teammateHistory.isEmpty)
        let history = try await store.headToHead(playerID: selfID, opponentID: document.players[1].id)
        XCTAssertEqual(history.map(\.id), [document.id])
        let samePerson = try await store.headToHead(playerID: selfID, opponentID: selfID)
        XCTAssertTrue(samePerson.isEmpty)
    }

    func testFutureMutationRefusalLeavesDocumentBytesUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        var document = try sample()
        document.schemaVersion = try SchemaVersion("1.3.0")
        try await store.create(document)
        let url = root.appendingPathComponent("sessions/\(document.id)/session.json")
        let before = try Data(contentsOf: url)
        do { try await store.update(document.id, facet: .review(.init(state: .complete))); XCTFail("future version must not be rewritten") }
        catch SessionStoreError.unsupportedMigration { }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testAppendBatchSurvivesInterruptionAsNoneOrAllAndConcurrentFacetsDoNotLoseEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var document = try sample()
        document.match?.log = []
        let store = try SessionStore(root: root)
        try await store.create(document)
        let batch = (0..<5).map { Self.point(id: "batch-\($0)", seq: $0 + 1) }
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
            async let append: Void = store.append([Self.point(id: "point-\(index)", seq: index + 6)], to: id)
            async let update: Void = store.update(id, facet: .review(.init(state: index == 999 ? .complete : .inProgress)))
            _ = try await (append, update)
        }
        let final = try await store.load(id)
        XCTAssertEqual(final.match?.log.count, 1005)
        XCTAssertEqual(final.review?.state, .complete)
        XCTAssertEqual(final.analysis, document.analysis)
        XCTAssertEqual(final.archive, document.archive)
        if let directory = ProcessInfo.processInfo.environment["JOVRA_STORE_EVIDENCE_DIR"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try CanonicalJSON.encode(final).write(to: output.appendingPathComponent("session.json"))
        }
    }

    func testZeroNegativeAndDuplicateSequenceRefusalLeavesLogUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var document = try sample(); document.match?.log = []
        let store = try SessionStore(root: root)
        try await store.create(document)
        for sequence in [0, -1] {
            do { try await store.append([Self.point(id: "invalid", seq: sequence)], to: document.id); XCTFail("invalid sequence accepted") }
            catch SessionStoreError.invalidEvents { }
        }
        let loaded = try await store.load(document.id)
        XCTAssertEqual(loaded.match?.log.count, 0)
        try await store.append([Self.point(id: "first", seq: 1)], to: document.id)
        for event in [Self.point(id: "duplicate-sequence", seq: 1), Self.point(id: "first", seq: 2)] {
            do { try await store.append([event], to: document.id); XCTFail("duplicate log identity accepted") }
            catch SessionStoreError.invalidEvents { }
        }
        let afterDuplicates = try await store.load(document.id)
        XCTAssertEqual(afterDuplicates.match?.log.count, 1)
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

    func testPointWithoutDetectedOrReviewedOutcomeIsRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var document = try sample(); document.match?.log = []
        let store = try SessionStore(root: root)
        try await store.create(document)
        do { try await store.append([.point(.init(id: "missing-outcome", seq: 1))], to: document.id); XCTFail("schema-invalid point accepted") }
        catch SessionStoreError.invalidEvents { }
        let actual = try await store.load(document.id)
        XCTAssertEqual(actual.match?.log.count, 0)
    }

    func testNewOriginalFacetUpgradesLegacyDocumentWithoutChangingMatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = try sample()
        XCTAssertEqual(document.schemaVersion, .v1)
        let store = try SessionStore(root: root)
        try await store.create(document)
        try await store.update(document.id, facet: .original(.init(state: .saved)))
        let actual = try await store.load(document.id)
        XCTAssertEqual(actual.schemaVersion, .current)
        XCTAssertEqual(actual.match, document.match)
        XCTAssertEqual(actual.original?.state, .saved)
    }

    func testSymlinkEscapeIsRefusedWithoutHidingHealthySessionOrTouchingExternalMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let store = try SessionStore(root: root)
        let document = try sample()
        try await store.create(document)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("keep-original".utf8).write(to: outside.appendingPathComponent("video.mp4"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("sessions/escape"), withDestinationURL: outside)
        do { _ = try await store.load("escape"); XCTFail("symlink must be refused") }
        catch SessionStoreError.unsafePath { }
        let listed = try await store.list()
        XCTAssertEqual(listed.map(\.id), [document.id])
        XCTAssertEqual(try Data(contentsOf: outside.appendingPathComponent("video.mp4")), Data("keep-original".utf8))
        let refused = try await store.quarantinedSessions()
        XCTAssertEqual(refused.map(\.sessionID), ["escape"])
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
