import Foundation
import JovraCore

/// A story profile KeeperSelector ranks for (spec "Ranking is deterministic per profile").
public enum KeeperProfile: String, Sendable, CaseIterable {
    case rallyPulse = "rally-pulse"
    case coachCut = "coach-cut"
    case matchBroadcast = "match-broadcast"
    case progressStory = "progress-story"
    case courtMemories = "court-memories"
}

/// Options a ranking reads. An `excluded` keeper (or B-roll item) is never offered by any profile (story 108).
public struct KeeperRankOptions: Equatable, Sendable {
    public struct Cue: Equatable, Sendable {
        public var cueId: String
        public var keeperId: String
        public var provenance: Provenance

        public init(cueId: String, keeperId: String, provenance: Provenance) {
            self.cueId = cueId
            self.keeperId = keeperId
            self.provenance = provenance
        }
    }

    public struct Broll: Equatable, Sendable {
        public var brollId: String
        /// The chapter the player marked it for: `arrival`, `preparation` or `after`.
        public var chapter: String

        public init(brollId: String, chapter: String) {
            self.brollId = brollId
            self.chapter = chapter
        }
    }

    public enum SelectionRule: String, Sendable {
        case all
        case seededRandom = "seeded-random"
        case userChosen = "user-chosen"
    }

    public var excluded: [String]
    public var limit: Int?
    /// Coach's Cut: cues and the keeper each belongs to.
    public var cues: [Cue]
    /// Progress Story: keeper id -> the session date of a dated example (ISO `YYYY-MM-DD`).
    public var dates: [String: String]
    /// Progress Story: false when there is no comparable evidence (the film becomes a lesson chronology, story 137).
    public var comparable: Bool
    /// Progress Story's selection rule as stored; nil or an unknown rule is refused when the examples are comparable.
    public var selectionRule: String?
    public var count: Int?
    public var seed: Int?
    public var chosen: [String]
    /// Court Memories: B-roll the player marked for a chapter.
    public var brolls: [Broll]

    public init(excluded: [String] = [], limit: Int? = nil, cues: [Cue] = [], dates: [String: String] = [:],
                comparable: Bool = true, selectionRule: String? = nil, count: Int? = nil, seed: Int? = nil,
                chosen: [String] = [], brolls: [Broll] = []) {
        self.excluded = excluded
        self.limit = limit
        self.cues = cues
        self.dates = dates
        self.comparable = comparable
        self.selectionRule = selectionRule
        self.count = count
        self.seed = seed
        self.chosen = chosen
        self.brolls = brolls
    }
}

/// One item of a ranked order: a keeper or a B-roll item, with its Court Memories chapter.
public struct KeeperRankItem: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case keeper, broll
    }

    public var kind: Kind
    public var id: String
    public var chapter: String?

    public init(kind: Kind, id: String, chapter: String? = nil) {
        self.kind = kind
        self.id = id
        self.chapter = chapter
    }
}

/// A profile's ranked order, with Progress Story's label and fallback and Court Memories' missing parts.
public struct KeeperRanking: Equatable, Sendable {
    public var profile: KeeperProfile
    public var order: [KeeperRankItem]
    public var label: String?
    public var fallback: String?
    public var missing: [String]

    public init(profile: KeeperProfile, order: [KeeperRankItem], label: String? = nil, fallback: String? = nil,
                missing: [String] = []) {
        self.profile = profile
        self.order = order
        self.label = label
        self.fallback = fallback
        self.missing = missing
    }
}

/// The core sample generator's PRNG (`jovra_ref.sample_match.SplitMix64`), so a seeded random selection is the same on
/// every platform.
public struct KeeperSplitMix64: Sendable {
    private var state: UInt64

    public init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Fisher-Yates from the end, `j = next() % (i + 1)`.
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var out = items
        var i = out.count - 1
        while i > 0 {
            let j = Int(next() % UInt64(i + 1))
            out.swapAt(i, j)
            i -= 1
        }
        return out
    }
}

extension KeeperSelector {
    public static let chosenLabel = "Examples you chose"

    /// The ranking for a profile id as stored; an unknown id is `unknownProfile`.
    public static func rank(profileId: String, _ keepers: [Keeper], options: KeeperRankOptions) throws -> KeeperRanking {
        guard let profile = KeeperProfile(rawValue: profileId) else {
            throw KeeperRejection(.unknownProfile, "profile \(profileId)")
        }
        return try rank(profile, keepers, options: options)
    }

    /// Deterministic per profile (spec/studio/modules/keepers.md, "Ranking"). An excluded keeper is never offered and
    /// `limit` keeps the head of the order.
    public static func rank(_ profile: KeeperProfile, _ keepers: [Keeper], options: KeeperRankOptions) throws -> KeeperRanking {
        let excluded = Set(options.excluded)
        let kept = keepers.filter { !excluded.contains($0.keeperId) }
        var got: KeeperRanking
        switch profile {
        case .rallyPulse: got = rallyPulse(kept)
        case .coachCut: got = coachCut(kept, options)
        case .matchBroadcast: got = matchBroadcast(kept)
        case .progressStory: got = try progressStory(kept, options)
        case .courtMemories: got = courtMemories(kept, options)
        }
        if let limit = options.limit {
            got.order = limit >= 0 ? Array(got.order.prefix(limit)) : Array(got.order.dropLast(-limit))
        }
        return got
    }

    private static func items(_ keepers: [Keeper], chapter: String? = nil) -> [KeeperRankItem] {
        keepers.map { KeeperRankItem(kind: .keeper, id: $0.keeperId, chapter: chapter) }
    }

    /// Break, set and match points first, then the longest real rallies; ties by point order.
    private static func rallyPulse(_ keepers: [Keeper]) -> KeeperRanking {
        let eligible = keepers.filter { $0.origin == .point && ($0.facts.isPressure || $0.facts.rallyReal) }
        func key(_ k: Keeper) -> (Int, Int, Int) {
            (k.facts.isPressure ? 0 : 1, -(k.facts.rallyReal ? k.facts.rallyLength ?? 0 : 0), k.facts.index ?? 0)
        }
        return KeeperRanking(profile: .rallyPulse, order: items(stableSorted(eligible) { key($0) < key($1) }))
    }

    /// Keepers linked to a reviewed or validated cue first, then keepers linked to a lesson clip; by time.
    private static func coachCut(_ keepers: [Keeper], _ options: KeeperRankOptions) -> KeeperRanking {
        let reviewed = Set(options.cues.filter { $0.provenance == .reviewed || $0.provenance == .validated }.map(\.keeperId))
        let eligible = keepers.filter { reviewed.contains($0.keeperId) || !$0.lessonClipIds.isEmpty }
        let sorted = eligible.sorted { a, b in
            let ra = reviewed.contains(a.keeperId) ? 0 : 1, rb = reviewed.contains(b.keeperId) ? 0 : 1
            if ra != rb { return ra < rb }
            if a.session.startUs != b.session.startUs { return a.session.startUs < b.session.startUs }
            return codePointPrecedes(a.keeperId, b.keeperId)
        }
        return KeeperRanking(profile: .coachCut, order: items(sorted))
    }

    /// Every point keeper, in point order.
    private static func matchBroadcast(_ keepers: [Keeper]) -> KeeperRanking {
        let points = stableSorted(keepers.filter { $0.origin == .point }) { ($0.facts.index ?? 0) < ($1.facts.index ?? 0) }
        return KeeperRanking(profile: .matchBroadcast, order: items(points))
    }

    /// Dated examples by date under the selection rule; without comparable evidence, the lesson chronology.
    private static func progressStory(_ keepers: [Keeper], _ options: KeeperRankOptions) throws -> KeeperRanking {
        let dates = options.dates
        let dated = keepers.filter { dates[$0.keeperId] != nil }.sorted { a, b in
            let da = dates[a.keeperId]!, db = dates[b.keeperId]!
            if da != db { return codePointPrecedes(da, db) }
            if a.session.startUs != b.session.startUs { return a.session.startUs < b.session.startUs }
            return codePointPrecedes(a.keeperId, b.keeperId)
        }
        guard options.comparable else {
            return KeeperRanking(profile: .progressStory, order: items(dated.filter { !$0.lessonClipIds.isEmpty }),
                                 fallback: "lesson-chronology")
        }
        guard let raw = options.selectionRule, let rule = KeeperRankOptions.SelectionRule(rawValue: raw) else {
            throw KeeperRejection(.badOptions, "selection rule \(options.selectionRule ?? "null")")
        }
        let picked: [Keeper]
        switch rule {
        case .all:
            picked = dated
        case .seededRandom:
            guard let count = options.count else { throw KeeperRejection(.badInput, "count must be an integer") }
            guard count > 0, count <= dated.count else {
                throw KeeperRejection(.badOptions, "count \(count) of \(dated.count) dated examples")
            }
            guard let seed = options.seed else { throw KeeperRejection(.badInput, "seed must be an integer") }
            var rng = KeeperSplitMix64(seed: seed)
            let chosen = Set(rng.shuffled(dated).prefix(count).map(\.keeperId))
            picked = dated.filter { chosen.contains($0.keeperId) }
        case .userChosen:
            let ids = Set(dated.map(\.keeperId))
            guard !options.chosen.isEmpty, options.chosen.allSatisfy(ids.contains) else {
                throw KeeperRejection(.unknownKeeper, "a chosen example is not a dated keeper")
            }
            let chosen = Set(options.chosen)
            picked = dated.filter { chosen.contains($0.keeperId) }
        }
        return KeeperRanking(profile: .progressStory, order: items(picked), label: rule == .userChosen ? chosenLabel : nil)
    }

    /// Arrival B-roll, then match moments (a Mark, a lesson link, or a break, set or match point) by time, then after
    /// B-roll; `missing` names any empty part (story 120).
    private static func courtMemories(_ keepers: [Keeper], _ options: KeeperRankOptions) -> KeeperRanking {
        let excluded = Set(options.excluded)
        let brolls = options.brolls.filter { !excluded.contains($0.brollId) }
        let moments = keepers.filter { !$0.markIds.isEmpty || !$0.lessonClipIds.isEmpty || $0.facts.isPressure }.sorted { a, b in
            a.session.startUs != b.session.startUs ? a.session.startUs < b.session.startUs : codePointPrecedes(a.keeperId, b.keeperId)
        }
        let arrival = brolls.filter { $0.chapter == "arrival" }, after = brolls.filter { $0.chapter == "after" }
        let order = arrival.map { KeeperRankItem(kind: .broll, id: $0.brollId, chapter: "arrival") }
            + items(moments, chapter: "match")
            + after.map { KeeperRankItem(kind: .broll, id: $0.brollId, chapter: "after") }
        var missing: [String] = []
        if arrival.isEmpty { missing.append("arrival-broll") }
        if moments.isEmpty { missing.append("match-moments") }
        if after.isEmpty { missing.append("after-broll") }
        return KeeperRanking(profile: .courtMemories, order: order, missing: missing)
    }
}
