import Foundation

/// The analysis numbers the Shot map (S11), Serve Lab (S12), Stroke Lab (S13) and Compare (S14) read from installed
/// sessions, computed from their records and never typed into a view: placed shots by depth, first serves in by box and
/// zone, serve-mark completeness, swing key moments and comparisons with the bundled sample media that shows each
/// sync time. The reference generator computes the same summary for the analysis oracle (analysis.expected.json).
///
/// Geometry (ITF, court metres from the net centre): a placement beyond the service line (6.40 m) is Deep, inside it
/// Short, and an Out tap is Out whatever its position. A serve's box is the receiver's deuce box when the bounce's x
/// and y differ in sign; the box splits into equal thirds from the centre service line: T, Body and Wide.
public struct SampleAnalysisSummary: Codable, Equatable, Sendable {
    public struct ShotPlacement: Codable, Equatable, Sendable {
        public let sessionId: String
        public let hitter: String
        public let stroke: String
        public let tagged: Int
        public let placed: Int
        public let deep: RateRatio
        public let short: RateRatio
        public let out: RateRatio
        public let needsReview: Int
        /// The three displayed percentages do not sum to 100, so the screen adds "Percentages are rounded."
        public let percentagesRounded: Bool
    }
    public struct Zones: Codable, Equatable, Sendable {
        public let placed: Int
        public let wide: RateRatio
        public let body: RateRatio
        public let t: RateRatio
    }
    public struct ServePlacement: Codable, Equatable, Sendable {
        public let sessionId: String
        public let server: String
        public let serve: String
        public let deuce: Zones
        public let ad: Zones
    }
    public struct ServeMarks: Codable, Equatable, Sendable {
        public let sessionId: String
        public let marked: Int
        /// Marks with contact, bounce, bounce position and server position: what "Review 12 serves" counts.
        public let complete: Int
        public let deuce: Int
        public let ad: Int
        public let calibrationIds: [String]
    }
    public struct Moment: Codable, Equatable, Sendable {
        public let name: String
        public let time: MediaTime
    }
    public struct Swing: Codable, Equatable, Sendable {
        public let id: String
        public let kind: String
        public let stroke: String
        public let shotId: String?
        public let serveMarkId: String?
        public let markId: String?
        public let moments: [Moment]
    }
    public struct SessionSwings: Codable, Equatable, Sendable {
        public let sessionId: String
        public let swings: [Swing]
    }
    public struct ComparisonSide: Codable, Equatable, Sendable {
        public let sessionId: String
        public let date: String
        public let syncTimeMs: Int
        /// The bundled sample media that shows the sync time (a practice clip before the session video).
        public let mediaId: String?
        public let offsetMs: Int?
    }
    public struct Comparison: Codable, Equatable, Sendable {
        public let id: String
        /// The session folder the project is saved in (clip A's).
        public let sessionId: String
        public let syncedAt: String
        public let note: String?
        public let left: ComparisonSide
        public let right: ComparisonSide
    }

    public let sample: Bool
    public let shotPlacement: [ShotPlacement]
    public let servePlacement: [ServePlacement]
    public let serveMarks: [ServeMarks]
    public let keyMoments: [SessionSwings]
    public let comparisons: [Comparison]

    static let serviceLine = Decimal(string: "6.40")!
    static let singlesHalfWidth = Decimal(string: "4.115")!

    /// Sessions newest first (local date, then id, descending), each contributing what it holds.
    public static func compute(sessions: [SessionDocument], mediaManifest: SampleMediaManifest) throws -> SampleAnalysisSummary {
        let dates = try Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, try LibrarySummary.localDate($0)) })
        let ordered = sessions.sorted { (dates[$0.id]!, $0.id) > (dates[$1.id]!, $1.id) }
        return SampleAnalysisSummary(
            sample: sessions.allSatisfy { $0.sample != nil },
            shotPlacement: try ordered.flatMap(shotPlacement),
            servePlacement: try ordered.flatMap(servePlacement),
            serveMarks: ordered.compactMap(serveMarks),
            keyMoments: ordered.compactMap(keyMoments),
            comparisons: try ordered.flatMap { try comparisons($0, dates: dates, manifest: mediaManifest) })
    }

    static func isDeep(_ court: CourtPoint2D) -> Bool { abs(court.y) > serviceLine }

    /// "deuce" or "ad": the receiver's box the bounce is in.
    static func box(_ court: CourtPoint2D) -> String { court.x * court.y < 0 ? "deuce" : "ad" }

    /// "t", "body" or "wide": equal thirds of the box from the centre service line.
    static func zone(_ court: CourtPoint2D) -> String {
        let thirds = abs(court.x) * 3
        return thirds < singlesHalfWidth ? "t" : (thirds < singlesHalfWidth * 2 ? "body" : "wide")
    }

    private static func shotPlacement(_ document: SessionDocument) throws -> [ShotPlacement] {
        var order: [String] = [], groups: [String: (hitter: String, stroke: String, tagged: Int, placed: [SessionShotPlacement])] = [:]
        for shot in document.shots ?? [] where shot.stroke != .serve {
            let key = "\(shot.hitter)|\(shot.stroke.rawValue)"
            if groups[key] == nil { order.append(key); groups[key] = (shot.hitter, shot.stroke.rawValue, 0, []) }
            groups[key]!.tagged += 1
            if let placement = shot.placement { groups[key]!.placed.append(placement) }
        }
        return try order.compactMap { key in
            let group = groups[key]!, placed = group.placed
            guard !placed.isEmpty else { return nil }
            let outs = placed.filter { $0.inOut == .out }.count
            let deep = placed.filter { $0.inOut != .out && isDeep($0.court) }.count
            let short = placed.count - outs - deep
            let ratios = try [deep, short, outs].map { try Percent.ratio(n: $0, d: placed.count) }
            return ShotPlacement(sessionId: document.id, hitter: group.hitter, stroke: group.stroke, tagged: group.tagged,
                                 placed: placed.count, deep: ratios[0], short: ratios[1], out: ratios[2],
                                 needsReview: placed.filter { $0.inOut == .needsReview }.count,
                                 percentagesRounded: ratios.compactMap(\.pct.value).reduce(0, +) != 100)
        }
    }

    private static func servePlacement(_ document: SessionDocument) throws -> [ServePlacement] {
        guard document.match != nil else { return [] }
        let firsts = Set(try ScoringEngine.fold(ScoringInput(session: document)).points
            .filter { $0.serveNumber.value == .value1 && ($0.strokeCount.value ?? 0) > 0 }.map(\.id))
        var order: [String] = [], boxes: [String: [String: [String]]] = [:]
        for shot in document.shots ?? [] where shot.stroke == .serve {
            guard let placement = shot.placement, let point = shot.pointId, firsts.contains(point) else { continue }
            if boxes[shot.hitter] == nil { order.append(shot.hitter); boxes[shot.hitter] = ["deuce": [], "ad": []] }
            boxes[shot.hitter]![box(placement.court)]!.append(zone(placement.court))
        }
        func zones(_ placed: [String]) throws -> Zones {
            let count = { (zone: String) in placed.filter { $0 == zone }.count }
            return Zones(placed: placed.count, wide: try Percent.ratio(n: count("wide"), d: placed.count),
                         body: try Percent.ratio(n: count("body"), d: placed.count),
                         t: try Percent.ratio(n: count("t"), d: placed.count))
        }
        return try order.map { server in
            ServePlacement(sessionId: document.id, server: server, serve: "first",
                           deuce: try zones(boxes[server]!["deuce"]!), ad: try zones(boxes[server]!["ad"]!))
        }
    }

    private static func serveMarks(_ document: SessionDocument) -> ServeMarks? {
        guard let marks = document.serveMarks, !marks.isEmpty else { return nil }
        return ServeMarks(
            sessionId: document.id, marked: marks.count,
            complete: marks.filter { $0.contactFrame != nil && $0.bounceFrame != nil && $0.bounceCourt != nil && $0.serverPosition != nil }.count,
            deuce: marks.filter { $0.servedTo == .deuce }.count, ad: marks.filter { $0.servedTo == .ad }.count,
            calibrationIds: Set(marks.compactMap(\.calibrationId)).sorted())
    }

    private static func keyMoments(_ document: SessionDocument) -> SessionSwings? {
        guard let swings = document.swings, !swings.isEmpty else { return nil }
        return SessionSwings(sessionId: document.id, swings: swings.map { swing in
            Swing(id: swing.id, kind: swing.kind.rawValue, stroke: swing.stroke?.rawValue ?? "unknown",
                  shotId: swing.shotId, serveMarkId: swing.serveMarkId, markId: swing.markId,
                  moments: swing.keyMoments.map { Moment(name: $0.name.rawValue, time: $0.time) })
        })
    }

    private static func comparisons(_ document: SessionDocument, dates: [String: String],
                                    manifest: SampleMediaManifest) throws -> [Comparison] {
        try (document.comparisons ?? []).map { comparison in
            func side(_ value: SessionComparisonSide) throws -> ComparisonSide {
                guard let date = dates[value.sessionId] else {
                    throw SampleContentError.invalidLibrary("comparison names no session in scope: \(value.sessionId)")
                }
                let media = covering(manifest, sessionID: value.sessionId, timeMs: value.syncTimeMs)
                return ComparisonSide(sessionId: value.sessionId, date: date, syncTimeMs: value.syncTimeMs,
                                      mediaId: media?.mediaId, offsetMs: media.map { value.syncTimeMs - $0.coversSessionMs.fromMs })
            }
            return Comparison(id: comparison.id, sessionId: document.id, syncedAt: comparison.syncedAt.rawValue,
                              note: comparison.note, left: try side(comparison.left), right: try side(comparison.right))
        }
    }

    /// The sample media of a session that shows a session time, a purpose-made practice clip before the session video.
    static func covering(_ manifest: SampleMediaManifest, sessionID: String, timeMs: Int) -> SampleMediaMedia? {
        manifest.media
            .filter { $0.sessionId == sessionID && $0.coversSessionMs.fromMs <= timeMs && timeMs < $0.coversSessionMs.toMs }
            .min { ($0.role != .practiceClip ? 1 : 0, $0.mediaId) < ($1.role != .practiceClip ? 1 : 0, $1.mediaId) }
    }
}
