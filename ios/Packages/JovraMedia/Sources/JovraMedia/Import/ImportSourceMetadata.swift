@preconcurrency import AVFoundation
import Foundation
import JovraCore

/// The real recording date and camera the original's own metadata states (story 119). Nothing is
/// guessed: a file without a creation date keeps `recordedAt` nil, never the copy time.
struct ImportSourceMetadata: Sendable {
    var recordedAt: Date?
    var device: SessionRecordingDevice?

    static func read(_ url: URL) async -> ImportSourceMetadata {
        let asset = AVURLAsset(url: url)
        var result = ImportSourceMetadata()
        if let item = try? await asset.load(.creationDate) {
            result.recordedAt = try? await item.load(.dateValue)
        }
        let items = ((try? await asset.load(.metadata)) ?? [])
            + ((try? await asset.loadMetadata(for: .quickTimeMetadata)) ?? [])
        let model = await firstString(in: items, identifiers: [.quickTimeMetadataModel, .commonIdentifierModel], limit: 60)
        let software = await firstString(in: items, identifiers: [.quickTimeMetadataSoftware, .commonIdentifierSoftware], limit: 30)
        if model != nil || software != nil { result.device = .init(model: model, osVersion: software) }
        return result
    }

    private static func firstString(in items: [AVMetadataItem], identifiers: [AVMetadataIdentifier], limit: Int) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                guard let value = try? await item.load(.stringValue) else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return String(trimmed.unicodeScalars.prefix(limit)) }
            }
        }
        return nil
    }
}
