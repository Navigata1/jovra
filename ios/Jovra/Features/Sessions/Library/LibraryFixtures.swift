// l10n-lint: ignore-file (synthetic Sample fixtures for the -library facets harness launch; their titles are data, not UI copy)
import Foundation
import JovraCore

/// What a harness launch puts into its library before anything reads it (`-demo sample`, `-library facets`).
enum LibraryLaunchSeed: Sendable {
    /// The shipped Sample library (spec/fixtures/sample), installed through SampleContent.
    case sample(SampleLibrary)
    /// Every facet state, one session in Trash and one unreadable document (`LibraryFixtures`).
    case facets

    /// The seed `configuration` asks for; nil leaves the library as it is.
    static func forLaunch(_ configuration: LaunchConfiguration, bundle: Bundle = .main) -> LibraryLaunchSeed? {
        if configuration.library == .facets { return .facets }
        guard configuration.demo == .sample, let library = bundledSampleLibrary(bundle) else { return nil }
        return .sample(library)
    }

    /// The demo library the app bundles as the folder `sample` (ios/project.yml).
    static func bundledSampleLibrary(_ bundle: Bundle = .main) -> SampleLibrary? {
        guard let folder = bundle.url(forResource: "sample", withExtension: nil) else { return nil }
        return try? SampleLibrary.load(from: folder.appendingPathComponent("library", isDirectory: true),
                                       mediaManifest: folder.appendingPathComponent("media-manifest.json"),
                                       analysis: folder.appendingPathComponent("analysis", isDirectory: true))
    }
}

/// Synthetic, visibly labelled Sample sessions for the library's facet screenshots and UI tests. Every value
/// of every facet (original, analysis, review, archive) appears on at least one card, so the four labels can be
/// seen varying independently. No real footage, no media: the cards show the court placeholder.
enum LibraryFixtures {
    static let generator = "JOVRALibraryFixtures"
    static let trashedID = "fixture-trashed"
    static let quarantinedID = "fixture-unreadable"

    private static let titles = ["Jon vs Alex", "Serve practice", "Forehand session", "Jon vs Sam", "Backhand rally",
                                 "Jon vs Chris", "Return practice", "Club ladder", "Volley drill", "Jon vs Priya",
                                 "Lesson with coach"]
    private static let kinds: [SessionDocumentSessionKind] = [.match, .servePractice, .strokePractice, .match, .rally,
                                                              .match, .drill, .tiebreakOnly, .drill, .practiceSet, .lesson]

    /// One session per archive state (eleven), cycling the other three facets so each of their values appears.
    static func facetSessions(now: Date = .now) -> [SessionDocument] {
        let originals = SessionOriginalStateState.allCases.filter { $0 != .trashed }
        let analyses = SessionAnalysisState.allCases
        let reviews = SessionReviewState.allCases
        let sessions = SessionArchiveStateState.allCases.enumerated().map { index, archive in
            let kind = kinds[index]
            let isMatch = LibraryFilter.matches.includes(kind)
            return document(id: "fixture-\(index + 1)", title: titles[index], kind: kind,
                            players: isMatch ? ["Jon", titles[index].components(separatedBy: " vs ").last ?? "Alex"] : ["Jon"],
                            notes: index == 2 ? "Hit with Alex on court 3" : nil,
                            createdAt: now.addingTimeInterval(-Double(index) * 86_400 - 3_600),
                            durationMs: (22 + index * 4) * 60_000,
                            original: originals[index % originals.count], analysis: analyses[index % analyses.count],
                            review: reviews[index % reviews.count], archive: archive,
                            archiveCopy: archive == .backedUp ? .original : nil, exports: index == 1 ? 2 : 0)
        }
        let trashed = document(id: trashedID, title: "Old warm-up", kind: .strokePractice, players: ["Jon"], notes: nil,
                               createdAt: now.addingTimeInterval(-20 * 86_400), durationMs: 18 * 60_000,
                               original: .saved, analysis: .notRequested, review: .notStarted, archive: .localOnly,
                               archiveCopy: nil, exports: 0)
        return sessions + [trashed]
    }

    /// A Sample session document with the given facets and no media.
    static func document(id: String, title: String, kind: SessionDocumentSessionKind, players: [String], notes: String?,
                         createdAt: Date, durationMs: Int, original: SessionOriginalStateState?,
                         analysis: SessionAnalysisState, review: SessionReviewState, archive: SessionArchiveStateState,
                         archiveCopy: SessionArchiveStateCopy?, exports: Int) -> SessionDocument {
        let stamp = createdAt.ISO8601Format()
        let people = players.enumerated().map { index, name in
            SessionPlayer(id: "p\(index + 1)", displayName: name, handedness: .unknown, backhand: .unknown, isSelf: index == 0)
        }
        let sides = people.count == 2 ? SessionSides(A: [people[0].id], B: [people[1].id]) : nil
        let records = (0..<exports).map { index in
            SessionExportRecord(id: "export-\(index + 1)", kind: .clip, createdAt: stamp, eventLogVersion: 1, includesAudio: false)
        }
        return SessionDocument(
            schemaVersion: .current, id: id, sport: .value, createdAt: stamp, updatedAt: stamp, title: title,
            sample: .init(synthetic: true, generator: generator), sessionKind: kind,
            capturePurpose: LibraryFilter.matches.includes(kind) ? .match : nil, players: people, sides: sides, match: nil,
            recording: .init(mode: .none, durationMs: durationMs, segments: [], gaps: [], microphone: .notRequested, mediaAvailable: false),
            marks: [], annotations: [], analysis: .init(state: analysis, runs: []), review: .init(state: review),
            archive: .init(state: archive, copy: archiveCopy, provider: archive == .localOnly ? nil : .value),
            storage: .init(originals: original == .archiveOnly ? .archivedOnly : .onDevice, includeInDeviceBackup: false),
            notes: notes, exports: records, original: original.map { .init(state: $0, updatedAt: stamp) })
    }

    /// Bytes that are not a session document: the folder the library must set aside and report.
    static let unreadableDocument = Data(#"{"kind":"jovra.session","note":"unreadable fixture"}"#.utf8)
}
