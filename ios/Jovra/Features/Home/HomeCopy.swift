import Foundation
import JovraCore

/// Home's greeting (S03 layout 4): morning 05:00–11:59, afternoon 12:00–17:59, otherwise evening; no name gives
/// "Good morning." on its own.
enum HomeGreeting {
    enum Part: Equatable { case morning, afternoon, evening }

    static func part(at date: Date, timeZone: TimeZone) -> Part {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch calendar.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        default: return .evening
        }
    }

    static func text(name: String?, at date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (part(at: date, timeZone: timeZone), name?.isEmpty == false ? name : nil) {
        case (.morning, let name?): return String(localized: "Good morning, \(name).", table: "Home", comment: "Home greeting with the player's name")
        case (.afternoon, let name?): return String(localized: "Good afternoon, \(name).", table: "Home", comment: "Home greeting with the player's name")
        case (.evening, let name?): return String(localized: "Good evening, \(name).", table: "Home", comment: "Home greeting with the player's name")
        case (.morning, nil): return String(localized: "Good morning.", table: "Home", comment: "Home greeting, no name known")
        case (.afternoon, nil): return String(localized: "Good afternoon.", table: "Home", comment: "Home greeting, no name known")
        case (.evening, nil): return String(localized: "Good evening.", table: "Home", comment: "Home greeting, no name known")
        }
    }
}

/// Home's computed captions.
enum HomeCopy {
    /// "Last 4 weeks" when the window ends today; otherwise the day it ends ("4 weeks to Oct 6"), so an older
    /// window never claims to be recent.
    static func windowCaption(_ window: ClosedRange<CalendarDay>, now: Date, timeZone: TimeZone = .autoupdatingCurrent,
                              locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let end = window.upperBound
        if today.year == end.year, today.month == end.month, today.day == end.day {
            return String(localized: "Last 4 weeks", table: "Home", comment: "Scope caption: the four weeks ending today")
        }
        var components = DateComponents(year: end.year, month: end.month, day: end.day, hour: 12)
        components.timeZone = timeZone
        let date = calendar.date(from: components) ?? now
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale).month(.abbreviated).day()
        style.timeZone = timeZone
        let label = date.formatted(style)
        return String(localized: "4 weeks to \(label)", table: "Home", comment: "Scope caption: the four weeks ending on a past day, e.g. “4 weeks to Oct 6”")
    }

    /// The change between two displayed weekly percentages, in percentage points (never percent of percent), against
    /// the week before; `versusWeek` names the compared week when the one before had too few serves to show.
    static func delta(points: Int, versusWeek: Int? = nil) -> String {
        if let versusWeek {
            let week = weekLabel(versusWeek)
            if points == 0 {
                return String(localized: "No change vs \(week)", table: "Home", comment: "Trend delta of zero against a named week, e.g. “No change vs Week 2”")
            }
            let signed = signedCount(points)
            return abs(points) == 1
                ? String(localized: "\(signed) percentage point vs \(week)", table: "Home", comment: "Trend delta, one point, against a named week")
                : String(localized: "\(signed) percentage points vs \(week)", table: "Home", comment: "Trend delta against a named week, e.g. “+4 percentage points vs Week 2”")
        }
        if points == 0 {
            return String(localized: "No change vs last week", table: "Home", comment: "Trend delta of zero percentage points")
        }
        let signed = signedCount(points)
        return abs(points) == 1
            ? String(localized: "\(signed) percentage point vs last week", table: "Home", comment: "Trend delta, one point, e.g. “+1 percentage point vs last week”")
            : String(localized: "\(signed) percentage points vs last week", table: "Home", comment: "Trend delta, e.g. “+4 percentage points vs last week”")
    }

    /// "+4" / "−3" (a true minus sign).
    private static func signedCount(_ value: Int) -> String {
        (value > 0 ? "+" : "−") + JovraFormat.count(abs(value))
    }

    /// "Week 1" … "Week 4": the chart's x labels and its Audio Graph categories.
    static func weekLabel(_ index: Int) -> String {
        String(localized: "Week \(index + 1)", table: "Home", comment: "Trend chart x-axis label, e.g. “Week 4”")
    }

    /// "Wk 1" … "Wk 4" under the chart where space is short.
    static func shortWeekLabel(_ index: Int) -> String {
        String(localized: "Wk \(index + 1)", table: "Home", comment: "Trend chart x-axis label, abbreviated, e.g. “Wk 4”")
    }
}
