import Foundation
import JovraBenchmark

extension RationalTime {
    /// Seconds as a double: for the screen and for "is this near that" decisions, never for stored values.
    var seconds: Double { Double(value) / Double(timescale) }

    /// `m:ss.mmm`, the way the tool shows a media time.
    var clock: String {
        // Whole milliseconds by integer division: 65.020 s must not print as 1:05.019.
        let (scaled, overflow) = value.multipliedReportingOverflow(by: 1000)
        let milliseconds = overflow ? Int((seconds * 1000).rounded(.down)) : Int(scaled / timescale)
        return String(format: "%d:%02d.%03d", milliseconds / 60_000, (milliseconds / 1000) % 60, milliseconds % 1000)
    }
}

/// What the labeller has selected, by the label's own identity so it survives edits around it.
public enum LabelSelection: Hashable, Sendable {
    case hit(time: RationalTime, player: BenchmarkLabels.Player)
    case bounce(time: RationalTime)
    case rally(start: RationalTime)
    case cameraPosition(from: RationalTime)

    public var time: RationalTime {
        switch self {
        case .hit(let time, _), .bounce(let time), .rally(let time), .cameraPosition(let time): time
        }
    }

    /// Where the label sits among others on its frame: hits (in the order the document keeps them), then the
    /// bounce, the rally and the camera position.
    private var rank: String {
        switch self {
        case .hit(_, let player): "0 \(player.rawValue)"
        case .bounce: "1"
        case .rally: "2"
        case .cameraPosition: "3"
        }
    }

    /// The order `.` and `,` walk the labels in: by time, and on one frame by kind, so every label is reached.
    func precedes(_ other: LabelSelection) -> Bool {
        time != other.time ? time < other.time : rank < other.rank
    }
}

/// The undoable state of a labelling session: the label document plus the two things in progress that are
/// not labels yet. Every edit makes a new value; undo and redo swap whole values.
public struct LabelDocument: Hashable, Sendable {
    public var labels: BenchmarkLabels
    /// A rally the labeller opened with `[` and has not closed yet.
    public var openRallyStart: RationalTime?
    /// Which corner `C` places next (0 far left, 1 far right, 2 near right, 3 near left).
    public var nextCorner: Int

    /// How close a candidate must be to a frame to belong to it.
    static let candidateReach = 0.25

    public init(labels: BenchmarkLabels) {
        // A stored open rally is the labeller's unfinished `[`: lift it back out of the document.
        if let last = labels.rallies.last, last.end == nil {
            self.labels = labels.replacing(rallies: Array(labels.rallies.dropLast()))
            self.openRallyStart = last.start
        } else {
            self.labels = labels
            self.openRallyStart = nil
        }
        let corners = self.labels.cameraPositions.last?.corners.points ?? []
        self.nextCorner = corners.firstIndex(where: { $0 == nil }) ?? 0
    }

    /// The document as it is written to disk: an open rally is stored as the last rally with no end, when
    /// no later rally exists (the schema allows exactly that); otherwise it stays in the session only.
    public var stored: BenchmarkLabels {
        guard let start = openRallyStart, labels.rallies.allSatisfy({ ($0.end ?? $0.start) <= start }) else { return labels }
        return labels.replacing(rallies: labels.rallies + [.init(start: start, end: nil)])
    }

    // MARK: Edits (each returns the new document, or a reason it cannot be done)

    public enum Refusal: Error, Equatable {
        case because(String)
    }

    public func markingHit(at time: RationalTime, player: BenchmarkLabels.Player) throws -> LabelDocument {
        guard !labels.hits.contains(where: { $0.time == time && $0.player == player }) else {
            throw Refusal.because("This frame already has a hit by the \(player.rawValue) player.")
        }
        var copy = self
        let hits = (labels.hits + [.init(time: time, player: player)]).sorted { ($0.time, $0.player.rawValue) < ($1.time, $1.player.rawValue) }
        copy.labels = labels.replacing(hits: hits, hitCandidates: .some(deciding(.confirmed, near: time, from: .pending)))
        return copy
    }

    public func settingStroke(_ stroke: BenchmarkLabels.Stroke?, at time: RationalTime, player: BenchmarkLabels.Player) -> LabelDocument {
        var copy = self
        copy.labels = labels.replacing(hits: labels.hits.map {
            $0.time == time && $0.player == player ? .init(time: $0.time, player: $0.player, stroke: stroke) : $0
        })
        return copy
    }

    public func markingBounce(at time: RationalTime, point: ImagePoint) -> LabelDocument {
        var copy = self
        let existing = labels.bounces.first { $0.time == time }
        let bounces = (labels.bounces.filter { $0.time != time } + [.init(time: time, imagePoint: point.normalized, inPlay: existing?.inPlay ?? true)])
            .sorted { $0.time < $1.time }
        copy.labels = labels.replacing(bounces: bounces)
        return copy
    }

    public func togglingInPlay(at time: RationalTime) -> LabelDocument {
        var copy = self
        copy.labels = labels.replacing(bounces: labels.bounces.map {
            $0.time == time ? .init(time: $0.time, imagePoint: $0.imagePoint, inPlay: !$0.inPlay) : $0
        })
        return copy
    }

    /// The camera position in force at `time`: the last one that starts at or before it.
    public func cameraPosition(at time: RationalTime) -> BenchmarkLabels.CameraPosition? {
        labels.cameraPositions.last { $0.from <= time }
    }

    /// Places (or, with a nil point, marks as not visible) the next corner of the camera position in force at
    /// `time`. The first position always starts with the recording.
    public func placingCorner(_ point: ImagePoint?, at time: RationalTime) -> LabelDocument {
        var copy = self
        let current = cameraPosition(at: time) ?? .init(from: RationalTime(value: 0, timescale: 1), corners: .init(points: [nil, nil, nil, nil]))
        var points = current.corners.points
        points[nextCorner] = point?.normalized
        let updated = BenchmarkLabels.CameraPosition(from: current.from, corners: .init(points: points))
        copy.labels = labels.replacing(cameraPositions: (labels.cameraPositions.filter { $0.from != current.from } + [updated]).sorted { $0.from < $1.from })
        copy.nextCorner = (nextCorner + 1) % 4
        return copy
    }

    public func startingCameraPosition(at time: RationalTime) throws -> LabelDocument {
        guard !labels.cameraPositions.contains(where: { $0.from == time }) else {
            throw Refusal.because("A camera position already starts on this frame.")
        }
        var copy = self
        let added = BenchmarkLabels.CameraPosition(from: time, corners: .init(points: [nil, nil, nil, nil]))
        copy.labels = labels.replacing(cameraPositions: (labels.cameraPositions + [added]).sorted { $0.from < $1.from })
        copy.nextCorner = 0
        return copy
    }

    public func openingRally(at time: RationalTime) throws -> LabelDocument {
        if let openRallyStart {
            throw Refusal.because("A rally is already open since \(openRallyStart.clock). Press ] where it ends.")
        }
        guard !labels.rallies.contains(where: { $0.start <= time && time < ($0.end ?? $0.start) }) else {
            throw Refusal.because("This frame is inside a rally that is already labelled.")
        }
        var copy = self
        copy.openRallyStart = time
        return copy
    }

    public func closingRally(at time: RationalTime) throws -> LabelDocument {
        guard let start = openRallyStart else {
            throw Refusal.because("No rally is open. Press [ on the frame where the rally starts.")
        }
        guard time > start else {
            throw Refusal.because("A rally ends after it starts (it started at \(start.clock)).")
        }
        guard !labels.rallies.contains(where: { $0.start < time && start < ($0.end ?? $0.start) }) else {
            throw Refusal.because("This would overlap a rally that is already labelled.")
        }
        var copy = self
        copy.labels = labels.replacing(rallies: (labels.rallies + [.init(start: start, end: time)]).sorted { $0.start < $1.start })
        copy.openRallyStart = nil
        return copy
    }

    public func deleting(_ selection: LabelSelection) -> LabelDocument {
        var copy = self
        switch selection {
        case .hit(let time, let player):
            copy.labels = labels.replacing(hits: labels.hits.filter { !($0.time == time && $0.player == player) },
                                           hitCandidates: .some(deciding(.pending, near: time, from: .confirmed)))
        case .bounce(let time):
            copy.labels = labels.replacing(bounces: labels.bounces.filter { $0.time != time })
        case .rally(let start):
            copy.labels = labels.replacing(rallies: labels.rallies.filter { $0.start != start })
        case .cameraPosition(let from):
            copy.labels = labels.replacing(cameraPositions: labels.cameraPositions.filter { $0.from != from })
            copy.nextCorner = 0
        }
        return copy
    }

    public func contains(_ selection: LabelSelection) -> Bool {
        switch selection {
        case .hit(let time, let player): labels.hits.contains { $0.time == time && $0.player == player }
        case .bounce(let time): labels.bounces.contains { $0.time == time }
        case .rally(let start): labels.rallies.contains { $0.start == start }
        case .cameraPosition(let from): labels.cameraPositions.contains { $0.from == from }
        }
    }

    // MARK: Hit candidates

    /// The pending candidate closest to `time`, if one is within reach.
    public func pendingCandidate(near time: RationalTime) -> BenchmarkLabels.HitCandidates.Candidate? {
        candidate(near: time, decision: .pending)
    }

    private func candidate(near time: RationalTime, decision: BenchmarkLabels.HitCandidates.Decision) -> BenchmarkLabels.HitCandidates.Candidate? {
        labels.hitCandidates?.items
            .filter { $0.decision == decision && abs($0.time.seconds - time.seconds) <= Self.candidateReach }
            .min { abs($0.time.seconds - time.seconds) < abs($1.time.seconds - time.seconds) }
    }

    /// The candidates with the one nearest `time` (currently `from`) changed to `decision`.
    private func deciding(_ decision: BenchmarkLabels.HitCandidates.Decision, near time: RationalTime,
                          from: BenchmarkLabels.HitCandidates.Decision) -> BenchmarkLabels.HitCandidates? {
        guard let candidates = labels.hitCandidates, let target = candidate(near: time, decision: from) else { return labels.hitCandidates }
        return .init(method: candidates.method, items: candidates.items.map { $0.time == target.time ? .init(time: $0.time, decision: decision) : $0 })
    }

    public func rejectingCandidate(near time: RationalTime) throws -> LabelDocument {
        guard pendingCandidate(near: time) != nil else {
            throw Refusal.because("There is no pending candidate on this frame. Press N for the next one.")
        }
        var copy = self
        copy.labels = labels.replacing(hitCandidates: .some(deciding(.rejected, near: time, from: .pending)))
        return copy
    }

    /// Adds freshly found candidates. One that sits on a hit already labelled counts as confirmed.
    public func offering(candidates times: [RationalTime], method: String) -> LabelDocument {
        var copy = self
        var seen = Set<RationalTime>()
        let items = times.sorted().filter { seen.insert($0).inserted }.map { time in
            let labelled = labels.hits.contains { abs($0.time.seconds - time.seconds) <= Self.candidateReach }
            return BenchmarkLabels.HitCandidates.Candidate(time: time, decision: labelled ? .confirmed : .pending)
        }
        copy.labels = labels.replacing(hitCandidates: .some(.init(method: method, items: items)))
        return copy
    }

    public func candidateCounts() -> (pending: Int, confirmed: Int, rejected: Int) {
        let items = labels.hitCandidates?.items ?? []
        return (items.filter { $0.decision == .pending }.count, items.filter { $0.decision == .confirmed }.count,
                items.filter { $0.decision == .rejected }.count)
    }

    /// Every labelled time, in order, with what it selects: for the next / previous label keys.
    public var landmarks: [LabelSelection] {
        let all: [LabelSelection] = labels.hits.map { .hit(time: $0.time, player: $0.player) }
            + labels.bounces.map { .bounce(time: $0.time) }
            + labels.rallies.map { .rally(start: $0.start) }
            + labels.cameraPositions.map { .cameraPosition(from: $0.from) }
        return all.sorted { $0.precedes($1) }
    }

    /// The label after `label` in walking order. `label` need not exist any more (it may just have been deleted).
    public func landmark(after label: LabelSelection) -> LabelSelection? {
        landmarks.first { label.precedes($0) }
    }

    public func landmark(before label: LabelSelection) -> LabelSelection? {
        landmarks.last { $0.precedes(label) }
    }
}
