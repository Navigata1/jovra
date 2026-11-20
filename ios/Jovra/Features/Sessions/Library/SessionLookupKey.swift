import JovraCore
import SwiftUI

/// The library index deep links resolve against ("Show last match"): the same local library the Sessions tab
/// lists, so a launch with `-library` or `-demo` resolves against that launch's library.
struct SessionLookupKey: ServiceKey {
    static let defaultValue: any SessionLookup = resolve(.current)

    static func live() -> any SessionLookup { LibrarySessionLookup(library: LocalCaptureLibraryKey.defaultValue) }

    static func fake(for configuration: LaunchConfiguration) -> any SessionLookup {
        LibrarySessionLookup(library: LocalCaptureLibraryKey.defaultValue)
    }
}

/// Reads the stored library. Trashed sessions are not offered; an unavailable library offers nothing.
struct LibrarySessionLookup: SessionLookup {
    var library: LocalCaptureAvailability

    func summaries() async -> [SessionSummary] {
        guard case .ready(let library) = library,
              let entries = try? await library.libraryEntries().entries else { return [] }
        return entries.compactMap { entry in
            guard let startedAt = entry.createdAt else { return nil }
            return SessionSummary(id: SessionID(rawValue: entry.id), kind: Self.kind(entry), startedAt: startedAt,
                                  isSample: entry.isSample)
        }
    }

    private static func kind(_ entry: LibraryEntry) -> SessionKind {
        if entry.isMatch { return entry.isDoubles ? .doublesMatch : .singlesMatch }
        return entry.kind == .servePractice ? .servePractice : .strokePractice
    }
}

extension EnvironmentValues {
    /// The library index deep links resolve against.
    var sessionLookup: any SessionLookup {
        get { self[SessionLookupKey.self] }
        set { self[SessionLookupKey.self] = newValue }
    }
}
