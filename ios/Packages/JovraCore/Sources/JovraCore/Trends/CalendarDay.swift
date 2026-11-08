import Foundation

/// A local calendar date ("YYYY-MM-DD") with exact day arithmetic and no time zone. Converting a timestamp to the
/// player's day is the caller's job; trends only bucket days, so a Calendar or TimeZone never enters the maths.
public struct CalendarDay: Codable, Comparable, Hashable, Sendable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int

    public init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysIn(month: month, year: year)).contains(day) else { throw CalendarDayError.invalid }
        self.year = year; self.month = month; self.day = day
    }

    public init(_ text: String) throws {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard text.utf8.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { throw CalendarDayError.invalid }
        try self.init(year: y, month: m, day: d)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Days since 1970-01-01 (proleptic Gregorian; H. Hinnant's days_from_civil).
    var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    init(ordinal z: Int) {
        let shifted = z + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let doe = shifted - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (m <= 2 ? 1 : 0); month = m; day = d
    }

    public func adding(days: Int) -> CalendarDay { CalendarDay(ordinal: ordinal + days) }

    /// The first day of the month `back` months before this day's month.
    func monthStart(back: Int) -> CalendarDay {
        let months = year * 12 + (month - 1) - back
        return CalendarDay(validated: months / 12, month: months % 12 + 1, day: 1)
    }

    /// Day 1 of a month is always valid, so no check is needed.
    private init(validated year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool { lhs.ordinal < rhs.ordinal }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum CalendarDayError: Error, Equatable, Sendable { case invalid }
