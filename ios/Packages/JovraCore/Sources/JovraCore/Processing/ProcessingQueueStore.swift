import Foundation

/// The processing queue, persisted. Every transition is written to disk before it is acknowledged and
/// then mirrored into the session's analysis facet through the shared `SessionStore` (never the
/// original facet). Opening the store after an app kill re-queues interrupted work at its saved progress.
public actor ProcessingQueueStore {
    public static let fileName = "processing-queue.json"

    private let root: URL
    private let sessions: SessionStore
    public private(set) var queue: ProcessingQueue

    public init(root: URL, sessions: SessionStore) throws {
        self.root = root
        self.sessions = sessions
        let url = root.appendingPathComponent(Self.fileName)
        var loaded = ProcessingQueue()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                loaded = try JSONDecoder().decode(ProcessingQueue.self, from: Data(contentsOf: url))
            } catch {
                // Keep the unreadable file for diagnostics and start empty: sessions are untouched and
                // can be queued again.
                let aside = root.appendingPathComponent("processing-queue.unreadable-\(UUID().uuidString).json")
                try FileManager.default.moveItem(at: url, to: aside)
            }
        }
        let interrupted = loaded.jobs.values.contains { job in ProcessingStage.allCases.contains { job[$0].status == .running } }
        loaded.recoverAfterRelaunch()
        queue = loaded
        if interrupted { try Self.write(loaded, to: root) }
    }

    /// Opens the queue at launch: interrupted work is re-queued and the analysis facets are brought in line.
    public static func open(root: URL, sessions: SessionStore) async throws -> ProcessingQueueStore {
        let store = try ProcessingQueueStore(root: root, sessions: sessions)
        await store.synchronizeFacets()
        return store
    }

    public func job(_ sessionID: String) -> ProcessingJob? { queue.job(sessionID) }

    public func next(under conditions: ProcessingConditions,
                     stages: Set<ProcessingStage> = Set(ProcessingStage.allCases)) -> ProcessingDecision {
        queue.next(under: conditions, stages: stages)
    }

    /// Brings the analysis facets in line with the queue (after a relaunch, a running facet becomes queued).
    public func synchronizeFacets() async {
        for job in queue.jobs.values { try? await mirror(job.sessionID) }
    }

    public func enqueue(_ sessionID: String, originalSaved: Bool) async throws {
        try await apply(sessionID) { $0.enqueue(sessionID, originalSaved: originalSaved) }
    }

    public func start(_ stage: ProcessingStage, for sessionID: String, under conditions: ProcessingConditions) async throws {
        try await apply(sessionID) { try $0.start(stage, for: sessionID, under: conditions) }
    }

    public func report(_ stage: ProcessingStage, for sessionID: String, progress: Double) async throws {
        // Progress reports do not change the facet's state, so only the queue file is written.
        var next = queue
        try next.report(stage, for: sessionID, progress: progress)
        try commit(next)
    }

    public func complete(_ stage: ProcessingStage, for sessionID: String) async throws {
        try await apply(sessionID) { try $0.complete(stage, for: sessionID) }
    }

    public func fail(_ stage: ProcessingStage, for sessionID: String, reason: ProcessingReason) async throws {
        try await apply(sessionID) { try $0.fail(stage, for: sessionID, reason: reason) }
    }

    public func markUnavailable(_ stage: ProcessingStage, for sessionID: String, reason: ProcessingReason) async throws {
        try await apply(sessionID) { try $0.markUnavailable(stage, for: sessionID, reason: reason) }
    }

    /// Marks every queued `stage` unavailable (nothing in this build can run it), whatever holds are in
    /// force, and mirrors each changed session's analysis facet.
    public func markQueuedUnavailable(_ stage: ProcessingStage, reason: ProcessingReason) async throws {
        var next = queue
        let changed = next.markQueuedUnavailable(stage, reason: reason)
        guard !changed.isEmpty else { return }
        try commit(next)
        for sessionID in changed { try await mirror(sessionID) }
    }

    public func pauseAnalysis(for sessionID: String) async throws {
        try await apply(sessionID) { try $0.pauseAnalysis(for: sessionID) }
    }

    public func resumeAnalysis(for sessionID: String) async throws {
        try await apply(sessionID) { try $0.resumeAnalysis(for: sessionID) }
    }

    public func retry(_ stage: ProcessingStage, for sessionID: String) async throws {
        try await apply(sessionID) { try $0.retry(stage, for: sessionID) }
    }

    /// Puts a running stage back in the queue at its saved progress (the app is leaving the foreground
    /// on a path that cannot continue in the background).
    public func interrupt(_ stage: ProcessingStage, for sessionID: String) async throws {
        guard queue.job(sessionID)?[stage].status == .running else { return }
        var next = queue
        next.recoverAfterRelaunch()
        try commit(next)
        try await mirror(sessionID)
    }

    public func updateBackup(_ readiness: ProcessingConditions.BackupReadiness) throws {
        var next = queue
        next.updateBackup(readiness)
        if next != queue { try commit(next) }
    }

    private func apply(_ sessionID: String, _ change: (inout ProcessingQueue) throws -> Void) async throws {
        var next = queue
        try change(&next)
        try commit(next)
        try await mirror(sessionID)
    }

    private func commit(_ next: ProcessingQueue) throws {
        try Self.write(next, to: root)
        queue = next
    }

    private func mirror(_ sessionID: String) async throws {
        guard let job = queue.job(sessionID) else { return }
        do {
            try await sessions.update(sessionID, facet: .analysis(job.analysisFacet))
        } catch SessionStoreError.notFound {
            // The session was deleted; the queue entry goes with it.
            var next = queue
            next.remove(sessionID)
            try commit(next)
        }
    }

    private static func write(_ queue: ProcessingQueue, to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(queue).write(to: root.appendingPathComponent(fileName), options: .atomic)
        try DurableDirectory.synchronize(root)
    }
}
