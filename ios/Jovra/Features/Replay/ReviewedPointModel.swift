import Foundation
import JovraCore
import Observation

/// Decisions are append-only. Display rows, pre-point calls and observed stats all use one fresh fold.
@MainActor @Observable
final class ReviewedPointModel {
    private(set) var document: SessionDocument?
    private(set) var timeline: MatchTimeline?
    private(set) var selectedID: String?
    private(set) var pointsWonA: DerivedStat?
    private(set) var firstServeInA: DerivedStat?
    private(set) var shots: DerivedStat?
    private(set) var isWorking = false
    var error: String?
    @ObservationIgnored private var library: LocalCaptureLibrary?
    @ObservationIgnored private var session: SessionID?
    @ObservationIgnored private var generation = UUID()

    var points: [TimelinePointRecord] { timeline?.points.filter { $0.kind == .point } ?? [] }
    var selected: TimelinePointRecord? { points.first { $0.id == selectedID } }
    var pointsWonAFraction: String {
        guard case .ratio(let value)? = pointsWonA?.value else { return "—" }
        return "\(value.n)/\(value.d)"
    }
    var scoreBefore: String {
        guard let point = selected, let call = point.call.value else { return "—" }
        switch call {
        case .points(let value): return value.server.rawValue + "–" + value.receiver.rawValue
        case .tiebreak(let value): return "\(value.server)–\(value.receiver)"
        case .deuce(let value): return value.kind == .deuce ? "Deuce · 40–40" : "Deciding point · 40–40"
        case .advantage(let value):
            guard let server = point.serverSide.value else { return "—" }
            return value.side.rawValue == server.rawValue ? "AD–40" : "40–AD"
        }
    }

    func select(_ id: String) { if points.contains(where: { $0.id == id }) { selectedID = id } }

    func open(library: LocalCaptureLibrary, session: SessionID) async {
        generation = UUID(); let token = generation
        self.library = library; self.session = session
        document = nil; timeline = nil; selectedID = nil
        pointsWonA = nil; firstServeInA = nil; shots = nil
        error = nil; isWorking = true
        defer { if generation == token { isWorking = false } }
        do { try await refresh(library: library, session: session, selected: nil, token: token) }
        catch { if generation == token { self.error = "Couldn't load the session's score. Reopen it to try again." } }
    }

    func append(winner: Side, startMs: Int, endMs: Int) async {
        await save { library, session in
            try await library.appendReviewedPoint(winner: winner, startMs: startMs, endMs: endMs, for: session)
        }
    }

    func correct(winner: Side) async {
        guard let point = selected else { return }
        await save { library, session in
            try await library.correctReviewedWinner(pointID: point.id, winner: winner, for: session)
        }
    }

    private func save(_ action: (LocalCaptureLibrary, SessionID) async throws -> SessionPointEvent) async {
        guard !isWorking, let library, let session else { return }
        let token = generation
        isWorking = true; error = nil
        defer { if generation == token { isWorking = false } }
        do {
            let point = try await action(library, session)
            try await refresh(library: library, session: session, selected: point.id, token: token)
        } catch {
            if generation == token {
                self.error = "Couldn't confirm this point was saved. Check the time range and reopen the session before trying again."
            }
        }
    }

    private func refresh(library: LocalCaptureLibrary, session: SessionID, selected: String?, token: UUID) async throws {
        let loaded = try await library.load(session)
        let folded = try ScoringEngine.fold(ScoringInput(session: loaded))
        let won = try StatsEngine.stat(.pointsWon(.a), in: folded, sample: loaded.sample != nil)
        let serves = try StatsEngine.stat(.firstServeIn(.a), in: folded, sample: loaded.sample != nil)
        let shots = try StatsEngine.stat(.shots, in: folded, sample: loaded.sample != nil)
        guard generation == token else { return }
        document = loaded; timeline = folded
        pointsWonA = won; firstServeInA = serves; self.shots = shots
        selectedID = folded.points.first { $0.kind == .point && $0.id == selected }?.id
            ?? folded.points.first { $0.kind == .point }?.id
    }
}
