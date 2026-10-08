import Foundation

/// Locale-aware formatting for every displayed date, time, duration, count, percentage and speed
/// (story 383; screen spec §0.2 rule 11). Views call these instead of building strings from numbers,
/// so values follow the player's locale and translations never concatenate fragments.
///
/// Percentages are computed by `pct(n, d)` (Rules §7) and only formatted here. Unit conversion
/// belongs to the Units module; `speed` formats a value in the unit it is given.
enum JovraFormat {
    /// "Oct 7, 2026" / "7 oct 2026".
    static func date(_ date: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "2:05 PM" / "14:05".
    static func time(_ date: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Time on court: "6h 42m", "54m" / "6 h 42 min". Truncated to whole minutes, never rounded up,
    /// so a total is never overstated.
    static func duration(seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let minutes = seconds.isFinite && seconds > 0 ? Int(seconds) / 60 : 0
        let style = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .narrow)
            .locale(locale)
        return Duration.seconds(minutes * 60).formatted(style)
    }

    /// Timecodes: "12:46", and "1:02:03" past an hour.
    static func clock(seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let whole = seconds.isFinite && seconds > 0 ? Int(seconds) : 0
        let pattern: Duration.TimeFormatStyle.Pattern = whole >= 3_600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(whole).formatted(Duration.TimeFormatStyle(pattern: pattern).locale(locale))
    }

    /// "12,345" / "12.345".
    static func count(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(IntegerFormatStyle<Int>(locale: locale))
    }

    /// A whole percentage already computed by `pct`: "67%" / "67 %".
    static func percent(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        (Double(value) / 100).formatted(FloatingPointFormatStyle<Double>.Percent(locale: locale).precision(.fractionLength(0)))
    }

    /// "104 mph", "167 km/h": whole units, in the unit given.
    static func speed(_ value: Double, unit: UnitSpeed, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: value, unit: unit).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }
}
