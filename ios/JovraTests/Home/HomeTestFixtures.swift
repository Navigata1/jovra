import Foundation
import JovraCore
@testable import Jovra

/// The sample library straight from spec/fixtures/sample (the source the app's bundled copy must equal), and
/// "real" sessions made from it: a sample document with its Sample block removed and a new id is exactly what a
/// recorded or imported session looks like to Home.
enum HomeTestFixtures {
    static func repositoryRoot(filePath: String = #filePath) -> URL {
        var root = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while root.path != "/", !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/sample").path) {
            root.deleteLastPathComponent()
        }
        return root
    }

    static var sampleFolder: URL { repositoryRoot().appendingPathComponent("spec/fixtures/sample") }

    static func sampleLibrary() throws -> SampleLibrary {
        try SampleLibrary.load(from: sampleFolder.appendingPathComponent("library"),
                               mediaManifest: sampleFolder.appendingPathComponent("media-manifest.json"),
                               analysis: sampleFolder.appendingPathComponent("analysis"))
    }

    static func sampleSessions() throws -> [SessionDocument] { try sampleLibrary().sessions }

    static func sample(titled title: String, on day: String) throws -> SessionDocument {
        let sessions = try sampleSessions()
        guard let match = sessions.first(where: { $0.title == title && ($0.recording.startedAt ?? "").hasPrefix(day) }) else {
            throw FixtureError.missing("\(title) on \(day)")
        }
        return match
    }

    /// The sample "Jon vs Alex" match of Oct 6 (6–4 6–3, 54 min, first serves in 40 of 60).
    static func jonVsAlex() throws -> SessionDocument { try sample(titled: "Jon vs Alex", on: "2026-10-06") }

    /// A player's own session: `template` without its Sample block, under a new id, played at `startedAt`, with
    /// none of its points flagged (the sample match has eight points needing review).
    static func real(_ template: SessionDocument, id: String, startedAt: String,
                     original: SessionOriginalStateState = .saved,
                     archive: SessionArchiveStateState = .backedUp,
                     review: SessionReviewState = .complete) -> SessionDocument {
        var document = template
        document.sample = nil
        document.id = id
        document.createdAt = startedAt
        document.recording.startedAt = startedAt
        document.original = SessionOriginalState(state: original)
        document.archive = SessionArchiveState(state: archive)
        document.review = SessionReview(state: review)
        if var match = document.match {
            match.log = match.log.map { event in
                guard case .point(var point) = event, point.reviewState == .needsReview else { return event }
                point.reviewState = .reviewed
                return .point(point)
            }
            document.match = match
        }
        return document
    }

    /// `document` with its last `count` point events marked as needing review.
    static func flagging(_ count: Int, of document: SessionDocument) -> SessionDocument {
        var document = document
        guard var match = document.match else { return document }
        var remaining = count
        match.log = match.log.reversed().map { event in
            guard remaining > 0, case .point(var point) = event else { return event }
            remaining -= 1
            point.reviewState = .needsReview
            return .point(point)
        }.reversed()
        document.match = match
        return document
    }

    /// 2026-10-06 at `hour`:00 on the sample's own wall clock (America/Chicago).
    static func october6(hour: Int) -> Date {
        var components = DateComponents(year: 2026, month: 10, day: 6, hour: hour)
        components.timeZone = chicago
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    static let chicago = TimeZone(identifier: "America/Chicago")!

    enum FixtureError: Error { case missing(String) }
}
