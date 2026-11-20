import Foundation
import JovraCore
import JovraMedia
import Observation
import OSLog
import SwiftUI

/// The session setup draft (S04) shared by the Record tab and its sheets, and remembered on disk so the
/// last setup is the next session's default (story 55). The file is tiny and written whole, atomically,
/// on every change; a file that cannot be read starts a fresh setup rather than blocking recording.
@MainActor @Observable
final class SessionSetupStore {
    var setup: SessionSetup {
        didSet { if setup != oldValue { save() } }
    }

    /// Opponents and partners from sessions saved on this iPhone, newest first (story 39). The players
    /// sheet offers the first few not already in the setup (`RecentPlayers.offered`).
    private(set) var recentPlayers: [SessionSetup.Player] = []

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let logger = Logger(subsystem: "com.islanddevcrew.jovra", category: "SessionSetup")

    /// `file` nil keeps the draft in memory only (previews and tests).
    init(file: URL?) {
        self.file = file
        setup = Self.load(file) ?? SessionSetup()
    }

    /// The camera presets this device can record; nil until the camera has been asked (story 49).
    private(set) var cameraFormats: [CaptureFormatOption]?
    /// Free space, battery and heat; nil until read.
    private(set) var budget: DeviceBudgetSnapshot?

    /// The chosen preset, or the first supported one when the remembered id is not offered here.
    var selectedFormat: CaptureFormatOption? {
        cameraFormats.flatMap { CaptureFormatCatalog.option(id: setup.cameraFormatID, in: $0) }
    }

    var isFixtureCamera: Bool { selectedFormat?.lens == .fixture }

    /// Bitrate × planned length × 0.85…1.2 against free space (S04 "Estimated space").
    var storageEstimate: StorageEstimate? {
        guard let format = selectedFormat, let budget else { return nil }
        return StorageEstimator.estimate(bitRate: format.bitRate, plannedSeconds: setup.plannedMinutes * 60, freeBytes: budget.freeBytes)
    }

    var preflight: [PreflightCheck] { PreflightCheck.checks(budget: budget, estimate: storageEstimate) }

    func refreshDevice(budget source: any DeviceBudget, formats: () async -> [CaptureFormatOption]) async {
        if cameraFormats == nil { cameraFormats = await formats() }
        budget = try? await source.snapshot()
    }

    func refreshRecentPlayers(from library: LocalCaptureAvailability) async {
        guard case .ready(let library) = library,
              let sessions = try? await library.sessions(.init(sample: false)) else { return }
        recentPlayers = RecentPlayers.from(sessions)
    }

    /// Chooses a mode. A match is filmed from behind the baseline; stroke practice starts side-on and serve
    /// practice from behind the baseline, and the player can change either (story 51).
    func select(_ mode: SessionSetup.Mode) {
        guard setup.mode != mode else { return }
        var next = setup
        next.mode = mode
        switch mode {
        case .singlesMatch, .doublesMatch, .servePractice: next.purpose = .match
        case .strokePractice: next.purpose = .sideOnTechnique
        }
        next.alignFirstOrderWithFirstServer()
        setup = next
    }

    /// "Check camera position" (story 54): presents capture with exactly this setup. A setup that still
    /// has a problem is never presented; the screen lists the problem instead.
    func checkCameraPosition(_ router: AppRouter) {
        guard setup.isReady else { return }
        router.present(.capture(SessionSetupDraft(setup)))
    }

    // MARK: Disk

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(setup).write(to: file, options: [.atomic])
        } catch {
            // The draft is a convenience: recording never depends on it (CLAUDE.md rule 3).
            logger.error("Could not remember the session setup: \(String(describing: error), privacy: .public)")
        }
    }

    private static func load(_ file: URL?) -> SessionSetup? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SessionSetup.self, from: data)
    }

    nonisolated static var defaultFile: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("JOVRA", isDirectory: true)
            .appendingPathComponent("setup", isDirectory: true)
            .appendingPathComponent("last-session-setup.json")
    }

    /// This store's part of "Delete all JOVRA data".
    nonisolated static func eraser(file: URL?) -> DataEraser {
        DataEraser(id: "sessionSetup") {
            guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
            try FileManager.default.removeItem(at: file)
        }
    }
}

/// Registers the setup store (the ServiceKey seam). The demo uses the same store: setup holds only the
/// player's own choices. A DEBUG launch with `JOVRA_SETUP_RESET=1` forgets the remembered setup first, so
/// each UI test starts from the same defaults.
struct SessionSetupStoreKey: ServiceKey {
    static let defaultValue: SessionSetupStore = MainActor.assumeIsolated { resolve(.current) }

    static func usesFake(_ configuration: LaunchConfiguration) -> Bool { false }
    static func fake(for configuration: LaunchConfiguration) -> SessionSetupStore { live() }

    static func live() -> SessionSetupStore {
        MainActor.assumeIsolated {
            let file = SessionSetupStore.defaultFile
            DataEraserRegistry.shared.register(SessionSetupStore.eraser(file: file))
            #if DEBUG
            if ProcessInfo.processInfo.environment["JOVRA_SETUP_RESET"] == "1", let file {
                try? FileManager.default.removeItem(at: file)
            }
            #endif
            return SessionSetupStore(file: file)
        }
    }
}

extension EnvironmentValues {
    var sessionSetupStore: SessionSetupStore {
        get { self[SessionSetupStoreKey.self] }
        set { self[SessionSetupStoreKey.self] = newValue }
    }
}
