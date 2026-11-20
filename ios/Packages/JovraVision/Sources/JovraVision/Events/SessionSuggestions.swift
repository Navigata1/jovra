import CryptoKit
import Foundation
import JovraCore

/// A capability and its method version, as recorded on every value it produces (GLOSSARY: Capability).
public struct AnalysisCapability: Equatable, Sendable {
    /// The capability registry id, e.g. `pointOutcome.auto`.
    public var id: String
    public var version: String
    public init(id: String, version: String) { self.id = id; self.version = version }

    /// The contract source: `model:<capability>@<version>`.
    public var source: String { "model:\(id)@\(version)" }
}

/// A played point an analysis stage found, by its time in the session. Who won and how it ended are known
/// only when the stage can tell; otherwise they stay unknown and the player decides in review.
public struct PointCandidate: Codable, Equatable, Sendable {
    public var startMs: Int
    public var endMs: Int
    public var winner: SessionOutcomeWinner
    public var endType: SessionOutcomeEndType
    /// The capability's own certainty (GLOSSARY: Confidence), never shown as accuracy.
    public var confidence: Decimal?

    public init(startMs: Int, endMs: Int, winner: SessionOutcomeWinner = .unknown, endType: SessionOutcomeEndType = .unknown,
                confidence: Decimal? = nil) {
        self.startMs = startMs; self.endMs = endMs; self.winner = winner; self.endType = endType; self.confidence = confidence
    }
}

public enum SessionSuggestionsError: Error, Equatable, Sendable {
    /// The capability id or version cannot form a contract source (`model:<id>@<version>`).
    case invalidCapability
    /// A candidate ends before it starts or starts before the recording.
    case invalidCandidate(startMs: Int, endMs: Int)
}

/// The events one conversion appends, and what it left alone.
public struct SuggestionBatch: Equatable, Sendable {
    /// Point events to append to the event log, in order.
    public var events: [SessionLogEvent]
    /// Reviewed points a candidate fell on. They are the player's decision and are not superseded.
    public var keptReviewed: [String]
    /// Candidates this method version already suggested (re-running a method adds nothing).
    public var alreadySuggested: Int
}

/// Turns analysis observations into session events (V00). Every event is a suggestion: a point event with a
/// detected outcome only, `estimated`, sourced `model:<capability>@<version>`, in needs review. Suggestions are
/// appended, never edited in place (ADR-0003), and corrections win (ADR-0004, spec decision 24):
///
/// - a candidate on an unreviewed point supersedes it (re-analysis replaces an earlier estimate);
/// - a candidate on a reviewed point is not written at all (the event log would refuse it anyway);
/// - a candidate on no logged point is inserted in time order.
///
/// Event ids derive from the method version and the candidate's times, so a run repeated after an app kill
/// adds nothing twice.
public enum SessionSuggestions {
    public static func pointEvents(for candidates: [PointCandidate], by capability: AnalysisCapability,
                                   in input: ScoringInput) throws -> SuggestionBatch {
        guard capability.source.range(of: #"^model:[A-Za-z0-9._-]+@[A-Za-z0-9._+-]+$"#, options: .regularExpression) != nil else {
            throw SessionSuggestionsError.invalidCapability
        }
        for candidate in candidates where candidate.startMs < 0 || candidate.endMs <= candidate.startMs {
            throw SessionSuggestionsError.invalidCandidate(startMs: candidate.startMs, endMs: candidate.endMs)
        }
        var logged: [String: SessionPointEvent] = [:]
        for case .point(let point) in input.log { logged[point.id] = point }
        let ids = Set(input.log.map(\.id))
        // The points the score uses now, in match order, with their times.
        let placed = try ScoringEngine.fold(input).points.filter { $0.kind == .point }
        var seq = input.log.map(\.seq).max() ?? 0
        var events: [SessionLogEvent] = []
        var kept: [String] = []
        var already = 0
        var superseded = Set<String>()

        for candidate in candidates.sorted(by: { ($0.startMs, $0.endMs) < ($1.startMs, $1.endMs) }) {
            let id = eventID(candidate, capability)
            if ids.contains(id) { already += 1; continue }
            let overlapping = placed.first { point in
                guard let start = point.tStartMs, let end = point.tEndMs else { return false }
                return candidate.startMs < end && start < candidate.endMs
            }
            var supersedes: String?
            var insertBefore: String?
            if let point = overlapping {
                if logged[point.id]?.reviewed != nil {
                    if !kept.contains(point.id) { kept.append(point.id) }
                    continue
                }
                // One suggestion per point and run: a second candidate on the same point is not a new point.
                guard superseded.insert(point.id).inserted else { continue }
                supersedes = point.id
            } else {
                insertBefore = placed.first { ($0.tStartMs ?? .min) > candidate.startMs }?.id
            }
            seq += 1
            let detected = SessionOutcome(winner: candidate.winner, endType: candidate.endType, provenance: .estimated,
                                          source: capability.source, capabilityId: capability.id,
                                          capabilityVersion: capability.version, confidence: candidate.confidence)
            events.append(.point(SessionPointEvent(id: id, seq: seq, supersedes: supersedes, insertBefore: insertBefore,
                                                   tStartMs: candidate.startMs, tEndMs: candidate.endMs,
                                                   detected: detected, reviewState: .needsReview)))
        }
        return SuggestionBatch(events: events, keptReviewed: kept, alreadySuggested: already)
    }

    /// `sg-` and 24 hex digits of SHA-256 over the method and the candidate's times (contract id grammar).
    static func eventID(_ candidate: PointCandidate, _ capability: AnalysisCapability) -> String {
        let key = "\(capability.source)|point|\(candidate.startMs)|\(candidate.endMs)"
        return "sg-" + SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
