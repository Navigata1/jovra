import Foundation

/// The library numbers Home, Progress and the String journal read, after the sample-scope rule: session count,
/// court time, the player's first serves in pooled per week over the four weeks ending at the latest session
/// (matches only; numerators and denominators pooled, never averaged), and logged court time per string job.
/// The reference generator computes the same summary for the sample library oracle (library.expected.json).
public struct LibrarySummary: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public let from: String
        public let to: String
    }
    public struct Week: Codable, Equatable, Sendable {
        public let week: Int
        public let from: String
        public let to: String
        public let sessionIds: [String]
        public let value: RateRatio
    }
    public struct StringJobUse: Codable, Equatable, Sendable {
        public let id: String
        public let strungOn: String
        public let linkedSessionIds: [String]
        public let loggedMinutes: Int
    }
    public struct Row: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let date: String
        public let kind: SessionDocumentSessionKind
        public let minutes: Int
        public let mediaIds: [String]
        public let scoreline: ContractNullable<String>
    }

    public static let windowDays = 28

    public let sample: Bool
    public let sessionCount: Int
    public let totalMinutes: Int
    public let window: Window?
    public let weeklyFirstServeIn: [Week]
    public let firstServeInDelta: String
    public let stringJobs: [StringJobUse]
    public let sessions: [Row]

    public static func compute(sessions documents: [SessionDocument], equipment: [EquipmentDocument]) throws -> LibrarySummary {
        let scope = SampleScope.sessions(documents)
        let sessions = scope.items
        let dated = try sessions.map { (document: $0, date: try localDate($0)) }
            .sorted { ($0.date, $0.document.id) < ($1.date, $1.document.id) }
        var weeks: [Week] = []
        var window: Window?
        if let last = dated.last?.date {
            let end = try day(last)
            let start = end - (windowDays - 1)
            window = Window(from: label(start), to: label(end))
            for index in 0..<(windowDays / 7) {
                let low = start + 7 * index, high = low + 6
                var parts: [(n: Int, d: Int)] = [], ids: [String] = []
                for entry in dated where entry.document.sessionKind == .match {
                    let value = try day(entry.date)
                    guard value >= low, value <= high, let fraction = try firstServeIn(entry.document) else { continue }
                    parts.append((fraction.n, fraction.d))
                    ids.append(entry.document.id)
                }
                weeks.append(Week(week: index + 1, from: label(low), to: label(high), sessionIds: ids,
                                  value: try Percent.pool(parts)))
            }
        }
        let delta = weeks.count >= 2 ? Percent.delta(current: weeks[weeks.count - 1].value, prior: weeks[weeks.count - 2].value) : "—"
        let jobs = SampleScope.equipment(equipment).items.flatMap(\.stringJobs).compactMap { job -> StringJobUse? in
            let linked = sessions.filter { $0.equipmentUse?.contains { $0.stringJobId == job.id } == true }
            guard !linked.isEmpty else { return nil }
            return StringJobUse(id: job.id, strungOn: job.strungOn, linkedSessionIds: linked.map(\.id).sorted(),
                                loggedMinutes: minutes(linked.reduce(0) { $0 + ($1.recording.durationMs ?? 0) }))
        }
        let rows = try dated.reversed().map { entry in
            Row(id: entry.document.id, title: entry.document.title, date: entry.date, kind: entry.document.sessionKind,
                minutes: (entry.document.recording.durationMs ?? 0) / 60_000,
                mediaIds: entry.document.sample?.mediaIds ?? [],
                scoreline: entry.document.match == nil ? .null
                    : try ScoringEngine.fold(ScoringInput(session: entry.document)).match.scoreline)
        }
        return LibrarySummary(sample: scope.isSample, sessionCount: sessions.count,
                              totalMinutes: minutes(sessions.reduce(0) { $0 + ($1.recording.durationMs ?? 0) }),
                              window: window, weeklyFirstServeIn: weeks, firstServeInDelta: delta,
                              stringJobs: jobs, sessions: rows)
    }

    /// Half-up whole minutes.
    private static func minutes(_ ms: Int) -> Int { (ms + 30_000) / 60_000 }

    /// The player's (isSelf) first serves in for one match.
    private static func firstServeIn(_ document: SessionDocument) throws -> RateRatio? {
        guard let me = document.players.first(where: \.isSelf), let sides = document.sides else { return nil }
        let stats = try StatsEngine.compute(ScoringEngine.fold(ScoringInput(session: document)))
        if sides.A.contains(me.id) { return stats.sides.A.firstServeIn }
        if sides.B.contains(me.id) { return stats.sides.B.firstServeIn }
        return nil
    }

    // Calendar days as integers (days since 1970-01-01), so week arithmetic never meets a DST transition.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The session's date on the wall clock where it was played.
    static func localDate(_ document: SessionDocument) throws -> String {
        let stamp = document.recording.startedAt ?? document.createdAt
        guard let instant = ISO8601DateFormatter().date(from: stamp) else {
            throw SampleContentError.invalidLibrary("\(document.id): unreadable start time")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = document.recording.timeZone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func day(_ label: String) throws -> Int {
        let parts = label.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            throw SampleContentError.invalidLibrary("bad date \(label)")
        }
        return Int(date.timeIntervalSince1970 / 86_400)
    }

    private static func label(_ day: Int) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(day) * 86_400))
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
