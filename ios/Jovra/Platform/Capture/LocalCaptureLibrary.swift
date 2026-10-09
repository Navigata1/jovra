import Foundation
import JovraCore
import JovraMedia

/// The first core flow records a singles match. Players remain caller-supplied, with unknown
/// handedness/backhand available rather than inferred profile facts.
struct CaptureSessionSeed: Sendable {
    var title: String
    var players: [SessionPlayer]
    var format: SessionMatchFormat
    var toss: SessionToss
}

enum LocalCaptureLibraryError: Error { case invalidSinglesSetup, unsupportedSource }

/// One app-local service owns one SessionStore actor. Reopening with a root is a system-boundary
/// injection for tests; production consumers will share the environment key's single instance.
actor LocalCaptureLibrary: RecordingSink {
    private let store: SessionStore
    private let media: MediaLibrary

    init(root: URL) throws {
        let store = try SessionStore(root: root)
        self.store = store
        media = MediaLibrary(store: store)
    }

    func createCapture(_ seed: CaptureSessionSeed, mode: SessionRecordingMode) async throws -> SessionID {
        guard mode == .camera || mode == .simulatorFixture else { throw LocalCaptureLibraryError.unsupportedSource }
        guard seed.players.count == 2, Set(seed.players.map(\.id)).count == 2,
              seed.players.allSatisfy({ !$0.id.isEmpty && !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              seed.players.contains(where: { $0.id == seed.toss.firstServer }),
              seed.toss.startingEnds.A.rawValue != seed.toss.startingEnds.B.rawValue,
              !seed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalCaptureLibraryError.invalidSinglesSetup
        }
        let id = SessionID(rawValue: UUID().uuidString)
        let now = Date.now.ISO8601Format()
        let document = SessionDocument(
            schemaVersion: .current, id: id.rawValue, sport: .value, createdAt: now, updatedAt: now,
            title: seed.title, sample: mode == .simulatorFixture ? .init(synthetic: true, generator: "JOVRAFixtureCamera") : nil,
            sessionKind: .match, capturePurpose: .match, players: seed.players,
            sides: .init(A: [seed.players[0].id], B: [seed.players[1].id]),
            match: .init(format: seed.format, toss: seed.toss, log: []),
            recording: .init(mode: mode, segments: [], gaps: [], microphone: .notRequested, mediaAvailable: false),
            marks: [], annotations: [], analysis: .init(state: .notRequested, runs: []), review: .init(state: .notStarted),
            archive: .init(state: .localOnly), storage: .init(originals: .onDevice, includeInDeviceBackup: false),
            exports: [], original: .init(state: .recording)
        )
        try await store.create(document)
        return id
    }

    func load(_ id: SessionID) async throws -> SessionDocument { try await store.load(id.rawValue) }

    func recordingFolder(_ id: SessionID) async throws -> URL {
        try await media.recordingFolder(sessionID: id.rawValue)
    }

    func fileURL(_ id: SessionID, relativePath: String) async throws -> URL {
        try await media.fileURL(sessionID: id.rawValue, relativePath: relativePath)
    }

    func sessions(_ query: SessionQuery = .init()) async throws -> [JovraCore.SessionSummary] {
        try await store.list(query)
    }

    func appendReviewedPoint(winner: Side, startMs: Int, endMs: Int, for id: SessionID) async throws -> SessionPointEvent {
        try await store.appendReviewedPoint(winner: winner, startMs: startMs, endMs: endMs, for: id.rawValue)
    }

    func correctReviewedWinner(pointID: String, winner: Side, for id: SessionID) async throws -> SessionPointEvent {
        try await store.correctReviewedWinner(pointID: pointID, winner: winner, for: id.rawValue)
    }

    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        try await store.saveCapture(recording, marks: marks, for: sessionID)
    }
}
