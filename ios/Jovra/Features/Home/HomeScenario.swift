#if DEBUG
import Foundation
import JovraCore

/// UI-test seam (DEBUG builds only, like the component galleries): `JOVRA_HOME_SCENARIO=<name>` in the launch
/// environment gives Home a fixed set of session documents instead of the store, and `JOVRA_HOME_NOW=<ISO 8601>`
/// fixes the clock the greeting and captions read. "Real" sessions here are the bundled sample "Jon vs Alex"
/// with its Sample block removed: exactly what a recorded session looks like to Home.
enum HomeScenario: String, CaseIterable {
    /// A fresh install: no sessions.
    case empty
    /// One session of the player's own beside the eight samples.
    case realPlusSample
    /// The player's own practice only: no match yet.
    case practiceOnly
    /// A match whose review is in progress with eight points needing review.
    case needsReview
    /// A recording kept only on this iPhone.
    case localOnly
    /// A recording saved with gaps after an interruption.
    case savedWithGaps
    /// A recording partially saved after an interruption.
    case interrupted

    static let environmentKey = "JOVRA_HOME_SCENARIO"
    static let clockKey = "JOVRA_HOME_NOW"

    static var current: HomeScenario? {
        ProcessInfo.processInfo.environment[environmentKey].flatMap(HomeScenario.init(rawValue:))
    }

    /// The fixed clock, when the launch asked for one.
    static var now: Date? {
        ProcessInfo.processInfo.environment[clockKey].flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    func documents() throws -> [SessionDocument] {
        let samples = try HomeSampleLibrary.sessions()
        guard let match = samples.first(where: { $0.id == Self.jonVsAlexID }),
              let practice = samples.first(where: { $0.sessionKind == .servePractice }) else { return [] }
        switch self {
        case .empty: return []
        case .realPlusSample: return samples + [Self.own(match, id: "home-real-1")]
        case .practiceOnly: return [Self.own(practice, id: "home-practice-1")]
        case .needsReview: return [Self.flagging(8, of: Self.own(match, id: "home-review-1", review: .inProgress))]
        case .localOnly: return [Self.own(match, id: "home-local-1", archive: .localOnly)]
        case .savedWithGaps: return [Self.own(match, id: "home-gaps-1", original: .savedWithGaps, review: .notStarted)]
        case .interrupted: return [Self.own(match, id: "home-partial-1", original: .partial, review: .notStarted)]
        }
    }

    /// The sample "Jon vs Alex" of Oct 6.
    static let jonVsAlexID = "b75c57d3-04df-5b4d-b969-32ed5cbfd97a"

    private static func own(_ template: SessionDocument, id: String, original: SessionOriginalStateState = .saved,
                            archive: SessionArchiveStateState = .backedUp,
                            review: SessionReviewState = .complete) -> SessionDocument {
        var document = template
        document.sample = nil
        document.id = id
        document.original = SessionOriginalState(state: original)
        document.archive = SessionArchiveState(state: archive)
        document.review = SessionReview(state: review)
        // A session of the player's own starts with nothing flagged; scenarios flag what they need.
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

    private static func flagging(_ count: Int, of document: SessionDocument) -> SessionDocument {
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
}
#endif
