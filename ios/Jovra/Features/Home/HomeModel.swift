import CoreGraphics
import Foundation
import JovraCore
import Observation

/// Loads Home's session documents, computes the dashboard and the latest session's poster frame.
@MainActor @Observable
final class HomeModel {
    enum Phase: Equatable {
        case loading
        case loaded(HomeDashboard)
        /// The local library could not be opened.
        case unavailable
        /// The sessions could not be read.
        case failed
    }

    private(set) var phase = Phase.loading
    private(set) var thumbnail: CGImage?
    private var thumbnailFor: String?

    /// The clock the greeting and captions read (fixed by a UI-test launch in DEBUG builds).
    var now: Date {
        #if DEBUG
        if let fixed = HomeScenario.now { return fixed }
        #endif
        return Date()
    }

    func load(library: LocalCaptureAvailability, launch: LaunchConfiguration) async {
        let documents: [SessionDocument]
        do {
            documents = try await HomeSessionSource.documents(library: library, launch: launch)
        } catch HomeSessionSource.LoadError.libraryUnavailable {
            phase = .unavailable; return
        } catch {
            phase = .failed; return
        }
        let dashboard = HomeDashboard.make(sessions: documents, now: now)
        phase = .loaded(dashboard)
        guard case .populated(let overview) = dashboard.content, thumbnailFor != overview.latest.id,
              let latest = documents.first(where: { $0.id == overview.latest.id }) else { return }
        thumbnailFor = overview.latest.id
        thumbnail = await HomeSessionSource.posterFrame(for: latest, library: library)
    }
}
