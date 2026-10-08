import Foundation
import Testing
@testable import Jovra

/// Locale-aware formatting (story 383). Expected strings are hand-checked CLDR forms for US English
/// and Spanish (Spain); `\u{202F}` is the narrow no-break space CLDR puts before "PM".
@Suite("Locale formatting")
struct JovraFormatTests {
    private let english = Locale(identifier: "en_US")
    private let spanish = Locale(identifier: "es_ES")
    private let utc = TimeZone(identifier: "UTC")!
    /// 7 October 2026, 14:05:00 UTC.
    private let match = Date(timeIntervalSince1970: 1_791_381_900)

    @Test("dates read naturally in each locale")
    func dates() {
        #expect(JovraFormat.date(match, locale: english, timeZone: utc) == "Oct 7, 2026")
        #expect(JovraFormat.date(match, locale: spanish, timeZone: utc) == "7 oct 2026")
    }

    @Test("times follow the locale's 12- or 24-hour clock")
    func times() {
        #expect(JovraFormat.time(match, locale: english, timeZone: utc) == "2:05\u{202F}PM")
        #expect(JovraFormat.time(match, locale: spanish, timeZone: utc) == "14:05")
    }

    @Test("time on court is hours and minutes, truncated so a total is never overstated")
    func durations() {
        #expect(JovraFormat.duration(seconds: 24_120, locale: english) == "6h 42m")
        #expect(JovraFormat.duration(seconds: 24_179, locale: english) == "6h 42m")
        #expect(JovraFormat.duration(seconds: 3_240, locale: english) == "54m")
        #expect(JovraFormat.duration(seconds: 24_120, locale: spanish) == "6 h 42 min")
        #expect(JovraFormat.duration(seconds: -5, locale: english) == "0m")
    }

    @Test("timecodes are minutes:seconds, with hours once a recording passes an hour")
    func clock() {
        #expect(JovraFormat.clock(seconds: 766, locale: english) == "12:46")
        #expect(JovraFormat.clock(seconds: 3_723, locale: english) == "1:02:03")
        #expect(JovraFormat.clock(seconds: 3_723, locale: spanish) == "1:02:03")
    }

    @Test("counts use the locale's grouping")
    func counts() {
        #expect(JovraFormat.count(386, locale: english) == "386")
        #expect(JovraFormat.count(12_345, locale: english) == "12,345")
        #expect(JovraFormat.count(12_345, locale: spanish) == "12.345")
    }

    @Test("whole percentages use the locale's percent sign placement")
    func percents() {
        #expect(JovraFormat.percent(67, locale: english) == "67%")
        #expect(JovraFormat.percent(67, locale: spanish) == "67\u{00A0}%")
    }

    @Test("speeds keep the unit the player chose, in the locale's abbreviation")
    func speeds() {
        #expect(JovraFormat.speed(104, unit: .milesPerHour, locale: english) == "104 mph")
        #expect(JovraFormat.speed(167.4, unit: .kilometersPerHour, locale: english) == "167 km/h")
        #expect(JovraFormat.speed(167.4, unit: .kilometersPerHour, locale: spanish) == "167 km/h")
    }
}
