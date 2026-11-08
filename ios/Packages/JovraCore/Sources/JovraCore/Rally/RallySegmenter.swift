import Foundation

/// Why rally segmentation, the rally-only plan or a roll edit refused its input. The raw values are the shared
/// error codes of spec/schemas/fixture-rally.schema.json, so both platforms refuse the same inputs the same way.
public enum RallyError: String, Error, Equatable, Sendable {
    case rallyGapNotPositive
    case pointGapBelowRallyGap
    case rollOutOfRange
    case duplicateId
    case rangeBackwards
    case timeOutsideRecording
    /// A per-clip roll names neither a point event nor a mark of the session.
    case unknownTarget

    public var code: String { rawValue }
}

/// A half of the camera frame. The excluded side (`analysis.excludedSide`) is the half whose neighbouring court is
/// noisy (story 200).
public typealias FrameHalf = SessionAnalysisExcludedSide

/// What HitDetector heard. Only `hit` takes part in segmentation.
public enum HitKind: String, Codable, Hashable, Sendable {
    case hit, bounce, other
}

/// One HitDetector candidate on the session timeline. `side` is the frame half the sound is attributed to, nil when
/// unattributed (an unattributed hit is never masked).
public struct HitCandidate: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let tMs: Int
    public let kind: HitKind
    public let side: FrameHalf?

    public init(id: String, tMs: Int, kind: HitKind = .hit, side: FrameHalf? = nil) {
        self.id = id
        self.tMs = tMs
        self.kind = kind
        self.side = side
    }
}

/// A mark as segmentation sees it. Only `point` marks ("Mark point") seed candidates.
public struct RallyBookmark: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let tMs: Int
    public let kind: SessionMarkKind

    public init(id: String, tMs: Int, kind: SessionMarkKind = .point) {
        self.id = id
        self.tMs = tMs
        self.kind = kind
    }

    public init(_ mark: SessionMark) {
        self.init(id: mark.id, tMs: mark.tMs, kind: mark.kind)
    }
}

/// Tuning for `RallySegmenter`. The defaults are the research starting values (technical-feasibility §6, N7).
public struct RallySegmentParameters: Equatable, Sendable {
    public static let defaultRallyGapMs = 3_000
    public static let defaultPointGapMs = 5_000

    /// The recording's length; every clip is clamped to it.
    public var durationMs: Int
    /// Hits closer than this are one rally.
    public var rallyGapMs: Int
    /// A gap longer than this starts a new point.
    public var pointGapMs: Int
    public var preRollMs: Int
    public var postRollMs: Int
    public var excludedSide: FrameHalf?

    public init(durationMs: Int, rallyGapMs: Int = defaultRallyGapMs, pointGapMs: Int = defaultPointGapMs,
                preRollMs: Int = RallyRolls.defaultPreRollMs, postRollMs: Int = RallyRolls.defaultPostRollMs,
                excludedSide: FrameHalf? = nil) {
        self.durationMs = durationMs
        self.rallyGapMs = rallyGapMs
        self.pointGapMs = pointGapMs
        self.preRollMs = preRollMs
        self.postRollMs = postRollMs
        self.excludedSide = excludedSide
    }
}

/// One rally inside a point candidate: consecutive hits less than the rally gap apart.
public struct RallySpan: Codable, Equatable, Hashable, Sendable {
    public let startMs: Int
    public let endMs: Int
    public let hitCount: Int

    public init(startMs: Int, endMs: Int, hitCount: Int) {
        self.startMs = startMs
        self.endMs = endMs
        self.hitCount = hitCount
    }
}

/// A suggested point. From hits it is `estimated` and needs review (D10: nothing automatic is shown as a fact); from
/// the player's own mark it is `manual`.
public struct PointCandidate: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable { case hits, mark }

    public let source: Source
    /// The first hit, or the mark.
    public let startMs: Int
    /// The last hit, or the mark.
    public let endMs: Int
    /// `[startMs - preRoll, endMs + postRoll)` clamped to the recording.
    public let clip: MediaRange
    public let hitIds: [String]
    public let markIds: [String]
    public let rallies: [RallySpan]
    public let provenance: Provenance
    public let needsReview: Bool

    public init(source: Source, startMs: Int, endMs: Int, clip: MediaRange, hitIds: [String], markIds: [String],
                rallies: [RallySpan], provenance: Provenance, needsReview: Bool) {
        self.source = source
        self.startMs = startMs
        self.endMs = endMs
        self.clip = clip
        self.hitIds = hitIds
        self.markIds = markIds
        self.rallies = rallies
        self.provenance = provenance
        self.needsReview = needsReview
    }
}

/// The candidates plus what was left out, each list ordered by time then id.
public struct RallySegmentation: Codable, Equatable, Sendable {
    public struct Dropped: Codable, Equatable, Sendable {
        public let excludedSide: [String]
        public let notHit: [String]
        public let notPointMark: [String]

        public init(excludedSide: [String], notHit: [String], notPointMark: [String]) {
            self.excludedSide = excludedSide
            self.notHit = notHit
            self.notPointMark = notPointMark
        }
    }

    public let candidates: [PointCandidate]
    public let dropped: Dropped

    public init(candidates: [PointCandidate], dropped: Dropped) {
        self.candidates = candidates
        self.dropped = dropped
    }
}

/// Turns HitDetector hits and the player's marks into point candidates (ios-v1-spec RallySegmenter). Pure and
/// conformance-tested against spec/fixtures/rally, whose reference is spec/reference/jovra_ref/rally.py:
///
/// - Only `hit` sounds count; hits attributed to the excluded frame half are dropped. Unattributed hits are kept.
/// - Kept hits, ordered by time then id, less than `rallyGapMs` apart are one rally; a gap longer than `pointGapMs`
///   starts a new point. A gap in between ends the rally but not the point.
/// - With no audio (`hits == nil`) every point mark is a candidate on its own (story 192). With audio a point mark
///   joins the first hit candidate whose clip holds it, or stands alone. Marks are never masked.
public enum RallySegmenter {
    public static func segment(hits: [HitCandidate]?, bookmarks: [RallyBookmark],
                               parameters p: RallySegmentParameters) throws(RallyError) -> RallySegmentation {
        guard p.rallyGapMs > 0 else { throw .rallyGapNotPositive }
        guard p.pointGapMs >= p.rallyGapMs else { throw .pointGapBelowRallyGap }
        try RallyRolls.check(p.preRollMs)
        try RallyRolls.check(p.postRollMs)
        var seen = Set<String>()
        for (id, time) in (hits ?? []).map({ ($0.id, $0.tMs) }) + bookmarks.map({ ($0.id, $0.tMs) }) {
            guard seen.insert(id).inserted else { throw .duplicateId }
            try RallyRolls.checkTime(time, durationMs: p.durationMs)
        }

        var excluded: [String] = [], notHit: [String] = [], notPointMark: [String] = []
        var kept: [HitCandidate] = []
        for hit in (hits ?? []).sorted(by: { ($0.tMs, $0.id) < ($1.tMs, $1.id) }) {
            if hit.kind != .hit {
                notHit.append(hit.id)
            } else if let side = p.excludedSide, hit.side == side {
                excluded.append(hit.id)
            } else {
                kept.append(hit)
            }
        }

        var groups: [Group] = []
        for hit in kept {
            guard let last = groups.last, hit.tMs - last.endMs <= p.pointGapMs else {
                groups.append(Group(hit: hit))
                continue
            }
            groups[groups.count - 1].add(hit, newRally: hit.tMs - last.endMs >= p.rallyGapMs)
        }
        let clip = { (start: Int, end: Int) in
            RallyRolls.clip(startMs: start, endMs: end, preRollMs: p.preRollMs, postRollMs: p.postRollMs, durationMs: p.durationMs)
        }
        var standalone: [PointCandidate] = []
        for mark in bookmarks.sorted(by: { ($0.tMs, $0.id) < ($1.tMs, $1.id) }) {
            guard mark.kind == .point else { notPointMark.append(mark.id); continue }
            let range = clip(mark.tMs, mark.tMs)
            if hits != nil, let home = groups.firstIndex(where: { clip($0.startMs, $0.endMs).contains(mark.tMs) }) {
                groups[home].markIds.append(mark.id)
            } else {
                standalone.append(PointCandidate(source: .mark, startMs: mark.tMs, endMs: mark.tMs, clip: range, hitIds: [],
                                                 markIds: [mark.id], rallies: [], provenance: .manual, needsReview: false))
            }
        }
        let fromHits = groups.map {
            PointCandidate(source: .hits, startMs: $0.startMs, endMs: $0.endMs, clip: clip($0.startMs, $0.endMs),
                           hitIds: $0.hitIds, markIds: $0.markIds, rallies: $0.rallies, provenance: .estimated, needsReview: true)
        }
        let ordered = (fromHits + standalone).sorted {
            ($0.startMs, $0.endMs, $0.firstId) < ($1.startMs, $1.endMs, $1.firstId)
        }
        return RallySegmentation(candidates: ordered,
                                 dropped: .init(excludedSide: excluded, notHit: notHit, notPointMark: notPointMark))
    }

    private struct Group {
        var startMs: Int
        var endMs: Int
        var hitIds: [String]
        var markIds: [String] = []
        var rallies: [RallySpan]

        init(hit: HitCandidate) {
            startMs = hit.tMs
            endMs = hit.tMs
            hitIds = [hit.id]
            rallies = [RallySpan(startMs: hit.tMs, endMs: hit.tMs, hitCount: 1)]
        }

        mutating func add(_ hit: HitCandidate, newRally: Bool) {
            endMs = hit.tMs
            hitIds.append(hit.id)
            if newRally {
                rallies.append(RallySpan(startMs: hit.tMs, endMs: hit.tMs, hitCount: 1))
            } else if let last = rallies.last {
                rallies[rallies.count - 1] = RallySpan(startMs: last.startMs, endMs: hit.tMs, hitCount: last.hitCount + 1)
            }
        }
    }
}

private extension PointCandidate {
    var firstId: String { hitIds.first ?? markIds.first ?? "" }
}

extension MediaRange {
    /// Half-open: `fromMs` is inside, `toMs` is not.
    func contains(_ tMs: Int) -> Bool { fromMs <= tMs && tMs < toMs }
}
