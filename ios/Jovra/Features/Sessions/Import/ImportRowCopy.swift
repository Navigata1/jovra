import Foundation
import JovraCore
import JovraMedia

/// What one import row says. Every unsupported or failed row names the specific problem and what to do
/// (stories 107 and 109); nothing here claims a result the pipeline did not report.
enum ImportRowCopy {
    static func title(for status: ImportModel.Status) -> String {
        switch status {
        case .receiving: String(localized: "Getting the video from Photos…", table: "Sessions.Import")
        case .queued: String(localized: "Waiting to start", table: "Sessions.Import")
        case .waitingForDownload: String(localized: "Waiting for download", table: "Sessions.Import")
        case .copying: String(localized: "Saving a copy on this device…", table: "Sessions.Import")
        case .saved: String(localized: "Saved locally", table: "Sessions.Import")
        case .duplicate: String(localized: "Already in your library", table: "Sessions.Import")
        case .working: String(localized: "Working…", table: "Sessions.Import")
        case .unsupported: String(localized: "Can't import this video", table: "Sessions.Import")
        case .failed: String(localized: "Not imported", table: "Sessions.Import")
        case .cancelled: String(localized: "Cancelled", table: "Sessions.Import")
        case .openedExisting: String(localized: "Opened the saved session", table: "Sessions.Import")
        case .actionFailed: String(localized: "That didn't work", table: "Sessions.Import")
        }
    }

    static func detail(for status: ImportModel.Status) -> String {
        switch status {
        case .receiving:
            String(localized: "Videos stored in iCloud Photos download first.", table: "Sessions.Import")
        case .queued:
            String(localized: "Imports run one at a time.", table: "Sessions.Import")
        case .waitingForDownload:
            String(localized: "This video is stored in the cloud. JOVRA continues as soon as it's on this iPhone.", table: "Sessions.Import")
        case .copying:
            String(localized: "Your original stays unchanged.", table: "Sessions.Import")
        case .saved(let video):
            metadata(video)
        case .duplicate(_, let existing):
            if let existing, !existing.isEmpty {
                String(localized: "This is the same video as “\(existing)”.", table: "Sessions.Import")
            } else {
                String(localized: "This is the same video as one you already imported.", table: "Sessions.Import")
            }
        case .working:
            String(localized: "Checking the saved copy.", table: "Sessions.Import")
        case .unsupported(let reason):
            unsupported(reason)
        case .failed(let failure):
            failed(failure)
        case .cancelled:
            String(localized: "Nothing was saved for this video.", table: "Sessions.Import")
        case .openedExisting:
            String(localized: "No second copy was saved.", table: "Sessions.Import")
        case .actionFailed:
            String(localized: "Nothing was saved or changed. Try again from your library.", table: "Sessions.Import")
        }
    }

    static func unsupported(_ reason: ImportUnsupportedReason) -> String {
        switch reason {
        case .container(let ext) where ext.isEmpty:
            String(localized: "This file has no video format JOVRA can read. Save it as MOV or MP4, then import it again.", table: "Sessions.Import")
        case .container(let ext):
            String(localized: "\(ext.uppercased()) files aren't supported. Save it as MOV or MP4, then import it again.", table: "Sessions.Import")
        case .noVideoTrack:
            String(localized: "This file has no video JOVRA can read. Choose a MOV or MP4 video.", table: "Sessions.Import")
        case .codec(let name):
            String(localized: "It uses the \(name) codec. Convert it to HEVC or H.264, then import it again.", table: "Sessions.Import")
        case .notDecodable(let name):
            String(localized: "This iPhone can't play this \(name) video. Convert it to standard HEVC or H.264.", table: "Sessions.Import")
        case .frameRate(let rate?):
            String(localized: "It's \(frameRateText(rate)) fps. JOVRA imports 24 to 240 fps.", table: "Sessions.Import")
        case .frameRate(nil):
            String(localized: "The video doesn't state a frame rate. Export it again at 24 to 240 fps.", table: "Sessions.Import")
        case .resolution(let width, let height):
            // Pixel sizes are labels, never grouped ("7680 × 4320").
            String(localized: "It's \(String(width)) × \(String(height)). JOVRA imports up to 4K (4096 pixels on the long side) and at least 240p.", table: "Sessions.Import")
        }
    }

    static func failed(_ failure: ImportFailure) -> String {
        switch failure {
        case .unreadable:
            String(localized: "The file couldn't be read, or it changed while copying. Your original was not changed.", table: "Sessions.Import")
        case .duplicateUnverified:
            String(localized: "A saved session has this video, but its copy no longer checks out. Open your library to review it.", table: "Sessions.Import")
        case .invalidSetup:
            String(localized: "Check the player names and match details, then try again.", table: "Sessions.Import")
        case .oneMatchPerImport:
            String(localized: "A singles match imports one video at a time.", table: "Sessions.Import")
        case .couldNotSave:
            String(localized: "The copy couldn't be saved. Check free space, then try again. Your original was not changed.", table: "Sessions.Import")
        }
    }

    /// "12 sec · 720p · Files · Oct 6, 2026", or "Date not in file" when the original states none.
    static func metadata(_ video: ImportModel.SavedVideo) -> String {
        var parts: [String] = []
        if let ms = video.durationMs {
            parts.append(Duration.milliseconds(ms).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
        }
        if video.shortSide > 0 { parts.append(video.shortSide >= 2160 ? "4K" : "\(video.shortSide)p") }
        switch video.source {
        case .photos: parts.append(String(localized: "Photos", table: "Sessions.Import"))
        case .files: parts.append(String(localized: "Files", table: "Sessions.Import"))
        case .googleDrive: parts.append(String(localized: "Google Drive", table: "Sessions.Import"))
        case nil: break
        }
        if let date = video.recordedAt {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        } else {
            parts.append(String(localized: "Date not in file", table: "Sessions.Import"))
        }
        return parts.joined(separator: " · ")
    }

    /// Nil until the player turns the video; the original file is never changed.
    static func rotationText(quarterTurns: Int) -> String? {
        guard quarterTurns % 4 != 0 else { return nil }
        let degrees = (quarterTurns % 4) * 90
        return String(localized: "Shown turned \(degrees)° clockwise. The original file is unchanged.", table: "Sessions.Import")
    }

    private static func frameRateText(_ rate: FrameRate) -> String {
        guard rate.perSeconds > 0 else { return "0" }
        return (Double(rate.frames) / Double(rate.perSeconds)).formatted(.number.precision(.fractionLength(0...2)))
    }
}
