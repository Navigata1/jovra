import Foundation
import JovraCore
import Testing
@testable import Jovra

/// The library card, list and Trash copy (S08, stories 120–131) computed from stored documents. Expected
/// strings are the screen spec's own copy, written out by hand.
@Suite("Session library presentation")
struct SessionLibraryPresentationTests {
    private static let day = Date(timeIntervalSince1970: 1_791_331_200) // 2026-10-07T00:00:00Z

    private func entry(_ id: String = "s1", title: String = "Jon vs Alex", kind: SessionDocumentSessionKind = .match,
                       players: [String] = ["Jon", "Alex"], notes: String? = nil, daysAgo: Double = 0,
                       original: SessionOriginalStateState? = .saved, analysis: SessionAnalysisState = .notRequested,
                       review: SessionReviewState = .notStarted, archive: SessionArchiveStateState = .localOnly,
                       copy: SessionArchiveStateCopy? = nil, bytes: SessionBytes? = nil, exports: Int = 0) -> LibraryEntry {
        let document = LibraryFixtures.document(
            id: id, title: title, kind: kind, players: players, notes: notes,
            createdAt: Self.day.addingTimeInterval(-daysAgo * 86_400), durationMs: 54 * 60_000,
            original: original, analysis: analysis, review: review, archive: archive, archiveCopy: copy,
            exports: exports)
        return LibraryEntry(document: document, bytes: bytes)
    }

    // MARK: Facets

    @Test("each facet keeps its own label: a stuck stage never hides the others")
    func independentFacets() {
        let labels = SessionFacetLabels(entry(original: .missing, analysis: .failed, review: .inProgress, archive: .needsReconnect))
        #expect(labels.original.text == "Video missing")
        #expect(labels.analysis.text == "Analysis failed")
        #expect(labels.review.text == "Needs review")
        #expect(labels.archive.text == "Needs reconnect")
        #expect([labels.original, labels.analysis, labels.review, labels.archive].map(\.tone) ==
                [.attention, .attention, .attention, .attention])
        #expect(Set([labels.original, labels.analysis, labels.review, labels.archive].map(\.axis)).count == 4)
    }

    @Test("a saved original says On device; the archive axis says what backup is doing", arguments: [
        (SessionArchiveStateState.localOnly, "Not backed up"),
        (.awaitingSetup, "Backup not set up"),
        (.queued, "Queued for backup"),
        (.waitingForWiFi, "Waiting for Wi-Fi"),
        (.hashing, "Preparing backup"),
        (.uploading, "Backing up"),
        (.verifying, "Checking backup"),
        (.backedUp, "Backed up"),
        (.failed, "Retry backup"),
        (.needsReconnect, "Needs reconnect"),
        (.quotaBlocked, "Google Drive is full"),
    ])
    func archiveLabels(state: SessionArchiveStateState, text: String) {
        let labels = SessionFacetLabels(entry(archive: state))
        #expect(labels.original.text == "On device")
        #expect(labels.archive.text == text)
    }

    @Test("Only on this iPhone until a verified backup of the original exists")
    func onlyOnThisIPhone() {
        #expect(SessionFacetLabels(entry(archive: .localOnly)).isOnlyOnThisIPhone)
        #expect(SessionFacetLabels(entry(archive: .uploading)).isOnlyOnThisIPhone)
        #expect(SessionFacetLabels(entry(archive: .backedUp, copy: .rallyOnlyCopy)).isOnlyOnThisIPhone,
                "a rally-only copy is not the original")
        #expect(!SessionFacetLabels(entry(archive: .backedUp, copy: .original)).isOnlyOnThisIPhone)
        #expect(!SessionFacetLabels(entry(original: .archiveOnly, archive: .backedUp)).isOnlyOnThisIPhone)
        #expect(!SessionFacetLabels(entry(original: .missing, archive: .localOnly)).isOnlyOnThisIPhone,
                "no video on this iPhone either")
    }

    @Test("analysis and review states read as the spec's words", arguments: [
        (SessionAnalysisState.notRequested, "Not analyzed"), (.queued, "Analysis queued"), (.running, "Analyzing"),
        (.paused, "Analysis paused"), (.done, "Analysis ready"), (.partial, "Partly analyzed"),
        (.failed, "Analysis failed"), (.unavailable, "Analysis unavailable"),
    ])
    func analysisLabels(state: SessionAnalysisState, text: String) {
        #expect(SessionFacetLabels(entry(analysis: state)).analysis.text == text)
    }

    @Test("review: not started, needs review, reviewed")
    func reviewLabels() {
        #expect(SessionFacetLabels(entry(review: .notStarted)).review.text == "Not reviewed")
        #expect(SessionFacetLabels(entry(review: .inProgress)).review.text == "Needs review")
        #expect(SessionFacetLabels(entry(review: .complete)).review.text == "Reviewed")
        #expect(SessionFacetLabels(entry(review: .complete)).review.tone == .positive)
    }

    @Test("the card reads as one sentence with every facet named")
    func accessibilitySummary() {
        let card = SessionCardPresentation(entry(archive: .queued, bytes: .init(originals: 1_200_000_000, cache: 0, exports: 0)),
                                           calendar: .gregorianUTC, now: Self.day, locale: Locale(identifier: "en_US"))
        #expect(card.metadata == "Oct 7 · 54 min · Singles")
        #expect(card.storage == "1.2 GB on this iPhone")
        #expect(card.accessibilityLabel ==
                "Jon vs Alex, Sample, Oct 7 · 54 min · Singles. Video: On device. Analysis: Not analyzed. Review: Not reviewed. Backup: Queued for backup. Only on this iPhone. 1.2 GB on this iPhone")
    }

    @Test("a recording under a minute states its seconds, never “0 min”")
    func shortDuration() {
        var short = entry()
        short.durationMs = 10_400
        let card = SessionCardPresentation(short, calendar: .gregorianUTC, now: Self.day, locale: Locale(identifier: "en_US"))
        #expect(card.metadata == "Oct 7 · 10 sec · Singles")
    }

    // MARK: Listing

    @Test("search finds players, titles and notes; filters split matches from practice; newest first")
    func listing() {
        let entries = [
            entry("a", title: "Serve practice", kind: .servePractice, players: ["Jon"], daysAgo: 2),
            entry("b", title: "Jon vs Alex", players: ["Jon", "Alex"], daysAgo: 0),
            entry("c", title: "Forehand session", kind: .strokePractice, players: ["Jon"], notes: "Hit with alex", daysAgo: 4),
            entry("d", title: "Jon vs Sam", players: ["Jon", "Sam"], daysAgo: 9),
        ]
        #expect(LibraryListing.visible(entries, search: "", filter: .all).map(\.id) == ["b", "a", "c", "d"])
        #expect(LibraryListing.visible(entries, search: "Alex", filter: .all).map(\.id) == ["b", "c"])
        #expect(LibraryListing.visible(entries, search: "  ALEX ", filter: .matches).map(\.id) == ["b"])
        #expect(LibraryListing.visible(entries, search: "", filter: .practice).map(\.id) == ["a", "c"])
        #expect(LibraryListing.visible(entries, search: "zzz", filter: .all).isEmpty)
    }

    // MARK: Permanent deletion

    @Test("the purge dialog names the original, the analysis, local copies and a verified Drive copy")
    func purgeWithVerifiedDriveCopy() {
        let scope = PurgeScope(entry(analysis: .done, review: .complete, archive: .backedUp, copy: .original,
                                     bytes: .init(originals: 1_200_000_000, cache: 30_000_000, exports: 10_000_000), exports: 2),
                               locale: Locale(identifier: "en_US"))
        #expect(scope.title == "Delete “Jon vs Alex” permanently?")
        #expect(scope.message == """
            This removes from this iPhone:
            • The original video (1.2 GB)
            • Its analysis, points and review
            • 2 local copies and cached files (40 MB)

            Google Drive: a verified copy of the original is kept.
            This can't be undone.
            """)
    }

    @Test("without a verified Drive copy the dialog says this is the only copy")
    func purgeWithoutDriveCopy() {
        let scope = PurgeScope(entry(archive: .uploading, bytes: .init(originals: 500_000_000, cache: 0, exports: 0)),
                               locale: Locale(identifier: "en_US"))
        #expect(scope.message == """
            This removes from this iPhone:
            • The original video (500 MB)
            • Its analysis, points and review
            • No local copies

            Google Drive: no verified copy. This is the only copy of the original video.
            This can't be undone.
            """)
    }

    @Test("with no original here and no Drive copy, the dialog says no copy of the original exists", arguments: [
        SessionBytes?.none,
        SessionBytes(originals: 0, cache: 0, exports: 0),
    ])
    func purgeWithoutAnyOriginal(bytes: SessionBytes?) {
        let scope = PurgeScope(entry(archive: .localOnly, bytes: bytes), locale: Locale(identifier: "en_US"))
        #expect(scope.message == """
            This removes from this iPhone:
            • No original video is on this iPhone
            • Its analysis, points and review
            • No local copies

            Google Drive: no verified copy. No copy of the original video exists on this iPhone or in Google Drive.
            This can't be undone.
            """)
        #expect(!scope.message.contains("This is the only copy"), "never claims an original that is not stored")
    }

    @Test("with no original here, a Drive copy is still named exactly", arguments: [
        (SessionArchiveStateCopy.original, "Google Drive: a verified copy of the original is kept."),
        (.rallyOnlyCopy, "Google Drive: only a rallies-only copy is kept. The full original video is not."),
    ])
    func purgeWithoutLocalOriginalButBackedUp(copy: SessionArchiveStateCopy, line: String) {
        let scope = PurgeScope(entry(original: .archiveOnly, archive: .backedUp, copy: copy,
                                     bytes: .init(originals: 0, cache: 0, exports: 0)),
                               locale: Locale(identifier: "en_US"))
        #expect(scope.message.contains("• No original video is on this iPhone"))
        #expect(scope.message.contains(line))
    }

    // MARK: Move to Trash

    @Test("moving to Trash states the video's size only when this iPhone holds some bytes", arguments: [
        (SessionBytes?.none, "The session and its points move to Trash. Nothing is deleted until you delete it there."),
        (SessionBytes(originals: 0, cache: 0, exports: 0),
         "The session and its points move to Trash. Nothing is deleted until you delete it there."),
        (SessionBytes(originals: 500_000_000, cache: 0, exports: 0),
         "The video (500 MB) and its points move to Trash. Nothing is deleted until you delete it there."),
    ])
    func moveToTrashMessage(bytes: SessionBytes?, expected: String) {
        #expect(SessionsView.deleteMessage(entry(bytes: bytes), locale: Locale(identifier: "en_US")) == expected)
    }

    @Test("a Sample session with nothing on this iPhone never says “Zero kB”; a Drive copy is named as untouched")
    func moveToTrashBackedUpWithoutBytes() {
        let message = SessionsView.deleteMessage(entry(archive: .backedUp, copy: .original,
                                                       bytes: .init(originals: 0, cache: 0, exports: 0)),
                                                 locale: Locale(identifier: "en_US"))
        #expect(message == "The session and its points move to Trash. Nothing is deleted until you delete it there. "
                + "Your Google Drive copy is not affected.")
        #expect(!message.localizedCaseInsensitiveContains("zero"))
    }
}

extension Calendar {
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
