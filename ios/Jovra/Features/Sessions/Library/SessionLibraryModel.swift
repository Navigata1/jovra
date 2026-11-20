import Foundation
import JovraCore
import Observation

/// The Sessions tab's state: what the local library holds, Trash and quarantine, and the operations the
/// library offers (move to Trash, Undo, restore, the confirmed purge). Every operation reloads from the
/// session folders, so the list never shows a state the store does not hold.
@MainActor @Observable
final class SessionLibraryModel {
    enum Phase: Equatable {
        case loading
        /// The walking skeleton is recording through the capture engine before the list loads.
        case recordingFixture(seconds: Int)
        case unavailable
        case failed
        case loaded
    }

    private(set) var phase = Phase.loading
    private(set) var snapshot = LibrarySnapshot(entries: [], trashed: [], quarantined: [])
    private(set) var recovery = StartupRecoverySummary()
    /// An operation that did not complete; the screen says so and nothing is assumed to have changed.
    var operationFailed = false
    @ObservationIgnored private var reloadToken = UUID()

    func reload(_ availability: LocalCaptureAvailability, launch: LaunchConfiguration) async {
        let token = UUID()
        reloadToken = token
        guard case .ready(let library) = availability else { phase = .unavailable; return }
        if snapshot.entries.isEmpty && snapshot.trashed.isEmpty { phase = .loading }
        do {
            if let seconds = launch.recordFixtureSessionSeconds {
                if phase == .loading { phase = .recordingFixture(seconds: seconds) }
                _ = try await FixtureSessionRecorder.recordIfRequested(launch, library: library)
            }
            let summary = await library.reconcileAtStartup()
            let loaded = try await library.libraryEntries()
            guard reloadToken == token else { return }
            recovery = summary
            snapshot = loaded
            phase = .loaded
        } catch {
            guard reloadToken == token, !Task.isCancelled else { return }
            phase = .failed
        }
    }

    /// Moves `entry` to Trash. Returns false (and says so) when the store refused.
    func moveToTrash(_ entry: LibraryEntry, in availability: LocalCaptureAvailability, launch: LaunchConfiguration) async -> Bool {
        await perform(availability, launch: launch) { try await $0.trash(SessionID(rawValue: entry.id)) }
    }

    func restore(_ id: String, in availability: LocalCaptureAvailability, launch: LaunchConfiguration) async -> Bool {
        await perform(availability, launch: launch) { try await $0.restore(SessionID(rawValue: id)) }
    }

    func purge(_ id: String, in availability: LocalCaptureAvailability, launch: LaunchConfiguration) async -> Bool {
        await perform(availability, launch: launch) { try await $0.purge(SessionID(rawValue: id)) }
    }

    private func perform(_ availability: LocalCaptureAvailability, launch: LaunchConfiguration,
                         _ action: (LocalCaptureLibrary) async throws -> Void) async -> Bool {
        guard case .ready(let library) = availability else { operationFailed = true; return false }
        var succeeded = true
        do { try await action(library) } catch { succeeded = false; operationFailed = true }
        await reload(availability, launch: launch)
        return succeeded
    }
}
