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

struct StartupRecoverySummary: Equatable, Sendable {
    var recovered = 0
    var refused = 0
    var scanFailed = false
}

/// One app-local service owns one SessionStore actor. Reopening with a root is a system-boundary
/// injection for tests; production consumers will share the environment key's single instance.
actor LocalCaptureLibrary: RecordingSink {
    private let root: URL
    private var startupRecovery: Task<StartupRecoverySummary, Never>?
    // Never scan a journal opened by this process, including one created while scanning awaits I/O.
    private var capturesStartedHere: Set<String> = []
    private let store: SessionStore
    private let media: MediaLibrary

    init(root: URL) throws {
        self.root = root
        let store = try SessionStore(root: root)
        self.store = store
        media = MediaLibrary(store: store)
    }

    func createCapture(_ seed: CaptureSessionSeed, mode: SessionRecordingMode) async throws -> SessionID {
        guard mode == .camera || mode == .simulatorFixture else { throw LocalCaptureLibraryError.unsupportedSource }
        guard seed.players.count == 2, Set(seed.players.map(\.id)).count == 2,
              seed.players.allSatisfy({ !$0.id.isEmpty && !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.displayName.unicodeScalars.count <= 60 }),
              seed.players.contains(where: { $0.id == seed.toss.firstServer }),
              seed.toss.startingEnds.A.rawValue != seed.toss.startingEnds.B.rawValue,
              !seed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seed.title.unicodeScalars.count <= 120 else {
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
        capturesStartedHere.insert(id.rawValue)
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
        _ = await reconcileAtStartup()
        return try await store.list(query)
    }

    func reconcileAtStartup() async -> StartupRecoverySummary {
        if let startupRecovery { return await startupRecovery.value }
        let task = Task { await runStartupRecovery() }
        startupRecovery = task
        return await task.value
    }

    private func runStartupRecovery() async -> StartupRecoverySummary {
        let scanner = RecoveryScanner(root: root)
        var summary = StartupRecoverySummary()
        do {
            let candidates = try await scanner.scan { id in try await self.isStartupRecoveryCandidate(id) }
            summary.refused = await scanner.refusals.count
            for candidate in candidates {
                do {
                    guard let witness = await scanner.adoptionWitness(for: candidate.sessionID) else {
                        summary.refused += 1
                        continue
                    }
                    if try await store.reconcileFinishedCapture(candidate.recording, marks: candidate.marks,
                                                                original: candidate.original, for: candidate.sessionID,
                                                                verifyOriginals: witness.verify) {
                        summary.recovered += 1
                    }
                } catch {
                    summary.refused += 1
                }
            }
        } catch {
            summary.scanFailed = true
        }
        return summary
    }

    private func isStartupRecoveryCandidate(_ id: String) async throws -> Bool {
        guard !capturesStartedHere.contains(id) else { return false }
        return try await store.needsFinishedCaptureRecovery(id)
    }

    func appendReviewedPoint(winner: Side, startMs: Int, endMs: Int, for id: SessionID) async throws -> SessionPointEvent {
        try await store.appendReviewedPoint(winner: winner, startMs: startMs, endMs: endMs, for: id.rawValue)
    }

    func correctReviewedWinner(pointID: String, winner: Side, for id: SessionID) async throws -> SessionPointEvent {
        try await store.correctReviewedWinner(pointID: pointID, winner: winner, for: id.rawValue)
    }

    func exportClip(_ id: SessionID, range: MediaRange, includeAudio: Bool) async throws -> LocalExportPackage {
        try await LocalExportService(store: store).export(sessionID: id.rawValue, range: range, includeAudio: includeAudio)
    }

    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        try await store.saveCapture(recording, marks: marks, for: sessionID)
    }
}
