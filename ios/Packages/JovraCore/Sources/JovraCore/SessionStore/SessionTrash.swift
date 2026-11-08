import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The retention editor's Trash rule (user story 131). Off by default: Trash is never emptied
/// automatically, so an original only disappears through an explicit, confirmed purge.
public struct TrashRetention: Equatable, Sendable {
    public let autoEmpty: Bool
    public let afterDays: Int
    public init(autoEmpty: Bool = false, afterDays: Int = 30) {
        self.autoEmpty = autoEmpty
        self.afterDays = max(1, afterDays)
    }
    public static let `default` = TrashRetention()
}

/// Issued by `SessionStore.purgeConfirmation(for:)` once the player confirms. It cannot be built
/// outside the store, is bound to one trashed session, and is spent by a purge or voided by a restore.
public struct PurgeConfirmation: Equatable, Sendable {
    public let sessionID: String
    let nonce: UUID
}

/// Store-private note written beside `session.json` so Undo restores the exact original facet.
struct TrashRecord: Codable, Equatable {
    let previous: SessionOriginalState?
    let trashedAt: String
}

extension SessionStore {
    static let trashRecordName = ".trash.json"

    /// Moves a session to Trash: the original facet becomes `trashed`; media and every other facet stay.
    public func trash(_ id: String, at date: Date = Date()) throws {
        var document = try load(id)
        guard document.original?.state != .trashed else { return }
        let folder = try folder(id)
        let stamp = Self.timestamp(date)
        // The note lands first; a crash before the document rename leaves the session untrashed.
        try writeAtomically(CanonicalJSON.encode(TrashRecord(previous: document.original, trashedAt: stamp)),
                            named: Self.trashRecordName, in: folder, temporaryPrefix: ".trash-")
        document.original = SessionOriginalState(state: .trashed, updatedAt: stamp)
        try write(document, to: folder)
    }

    public func restoreFromTrash(_ id: String) throws {
        var document = try load(id)
        guard let trashed = document.original, trashed.state == .trashed else { throw SessionStoreError.notInTrash }
        let folder = try folder(id)
        let note = folder.appendingPathComponent(Self.trashRecordName)
        try Self.refuseSymbolicLink(note)
        let record = (try? Data(contentsOf: note)).flatMap { try? JSONDecoder().decode(TrashRecord.self, from: $0) }
        if let record, record.trashedAt == trashed.updatedAt {
            document.original = record.previous
        } else {
            document.original = Self.derivedOriginal(document)
        }
        purgeTokens[id] = nil
        try write(document, to: folder)
        try? FileManager.default.removeItem(at: note)
    }

    public func purgeConfirmation(for id: String) throws -> PurgeConfirmation {
        guard try load(id).original?.state == .trashed else { throw SessionStoreError.notInTrash }
        let confirmation = PurgeConfirmation(sessionID: id, nonce: UUID())
        purgeTokens[id] = confirmation.nonce
        return confirmation
    }

    /// Permanently deletes a trashed session folder, originals included. Refused without the token.
    public func purge(_ id: String, confirmation: PurgeConfirmation?) throws {
        guard let confirmation, confirmation.sessionID == id, purgeTokens[id] == confirmation.nonce else {
            throw SessionStoreError.confirmationRequired
        }
        guard try load(id).original?.state == .trashed else { throw SessionStoreError.notInTrash }
        purgeTokens[id] = nil
        try removeSessionFolder(id)
    }

    /// Applies the retention rule. With `autoEmpty` off this deletes nothing, whatever the age.
    /// A trashed session whose date cannot be read is kept: nothing is deleted on assumption.
    @discardableResult
    public func emptyTrash(retention: TrashRetention, now: Date = Date()) throws -> [String] {
        guard retention.autoEmpty else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retention.afterDays) * 86_400)
        var purged: [String] = []
        for summary in try list(SessionQuery(original: .trashed)) {
            guard let stamp = summary.original?.updatedAt,
                  let trashedAt = ISO8601DateFormatter().date(from: stamp), trashedAt <= cutoff else { continue }
            purgeTokens[summary.id] = nil
            try removeSessionFolder(summary.id)
            purged.append(summary.id)
        }
        return purged.sorted()
    }

    /// One rename takes the whole folder out of `sessions/`, so a crash never leaves a half-deleted
    /// session to be quarantined. Leftovers in `purging/` were already confirmed for deletion.
    func removeSessionFolder(_ id: String) throws {
        let source = try folder(id)
        let purging = try auxiliaryFolder("purging")
        for leftover in try FileManager.default.contentsOfDirectory(at: purging, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: leftover)
        }
        let parentIdentity = try DurableDirectory.identity(of: sessions)
        let destination = purging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard rename(source.path, destination.path) == 0 else { throw SessionStoreError.renameFailed(errno) }
        do { try DurableDirectory.synchronize(sessions, matching: parentIdentity) }
        catch DirectoryDurabilityError.filesystem(let failure) { throw SessionStoreError.durabilityUnconfirmed(failure) }
        try FileManager.default.removeItem(at: destination)
    }

    /// Fallback when the Trash note is missing or stale: the same rule `saveCapture` applies.
    static func derivedOriginal(_ document: SessionDocument) -> SessionOriginalState? {
        let recording = document.recording
        if recording.mediaAvailable && !recording.segments.isEmpty {
            guard recording.segments.allSatisfy(\.finalized) else {
                return SessionOriginalState(state: .partial, reason: "Recording contains unconfirmed media")
            }
            return SessionOriginalState(state: recording.gaps.isEmpty ? .saved : .savedWithGaps)
        }
        return document.storage.originals == .archivedOnly ? SessionOriginalState(state: .archiveOnly) : nil
    }

    static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
