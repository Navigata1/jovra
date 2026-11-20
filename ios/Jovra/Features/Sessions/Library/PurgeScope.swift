import Foundation
import JovraCore

/// What permanently deleting a session from Trash removes, said exactly (story 130): the original video and
/// its size, the analysis, points and review, the local copies, and whether a verified Google Drive copy of
/// the original survives. Nothing is purged without this text being confirmed.
struct PurgeScope: Equatable, Sendable {
    enum DriveCopy: Equatable, Sendable {
        /// A verified backup of the original exists and is kept.
        case verifiedOriginal
        /// Only a rally-only copy is in Google Drive.
        case rallyOnly
        /// No verified copy.
        case none
    }

    let title: String
    let message: String
    let drive: DriveCopy

    init(_ entry: LibraryEntry, locale: Locale = .autoupdatingCurrent) {
        let format = { (count: Int64) in SessionCardPresentation.bytes(count, locale: locale) }
        title = String(localized: "Delete “\(entry.title)” permanently?", table: "Sessions.Library",
                       comment: "Permanent deletion from Recently deleted")
        if entry.archive == .backedUp {
            drive = entry.archiveCopy == .rallyOnlyCopy ? .rallyOnly : .verifiedOriginal
        } else {
            drive = .none
        }
        let originalsHere = entry.bytes?.originals ?? 0
        var lines = [String(localized: "This removes from this iPhone:", table: "Sessions.Library")]
        if originalsHere > 0 {
            lines.append("• " + String(localized: "The original video (\(format(originalsHere)))", table: "Sessions.Library"))
        } else {
            lines.append("• " + String(localized: "No original video is on this iPhone", table: "Sessions.Library"))
        }
        lines.append("• " + String(localized: "Its analysis, points and review", table: "Sessions.Library"))
        let copies = (entry.bytes?.exports ?? 0) + (entry.bytes?.cache ?? 0)
        if entry.exportCount > 0 {
            lines.append("• " + String(localized: "\(entry.exportCount) local copies and cached files (\(format(copies)))", table: "Sessions.Library",
                                      comment: "Exports and cache removed with a session"))
        } else if copies > 0 {
            lines.append("• " + String(localized: "Cached files (\(format(copies)))", table: "Sessions.Library"))
        } else {
            lines.append("• " + String(localized: "No local copies", table: "Sessions.Library"))
        }
        lines.append("")
        switch drive {
        case .verifiedOriginal:
            lines.append(String(localized: "Google Drive: a verified copy of the original is kept.", table: "Sessions.Library"))
        case .rallyOnly:
            lines.append(String(localized: "Google Drive: only a rallies-only copy is kept. The full original video is not.", table: "Sessions.Library"))
        case .none where originalsHere > 0:
            lines.append(String(localized: "Google Drive: no verified copy. This is the only copy of the original video.", table: "Sessions.Library"))
        case .none:
            // Nothing to call "the only copy": no original is stored here and none is backed up (a missing video,
            // or a Sample session without media).
            lines.append(String(localized: "Google Drive: no verified copy. No copy of the original video exists on this iPhone or in Google Drive.", table: "Sessions.Library"))
        }
        lines.append(String(localized: "This can't be undone.", table: "Sessions.Library"))
        message = lines.joined(separator: "\n")
    }
}
