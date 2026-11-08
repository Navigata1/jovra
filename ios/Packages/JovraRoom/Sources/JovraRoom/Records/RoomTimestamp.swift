/// An RFC 3339 UTC timestamp with a Z suffix (room-common `dateTime`). Wall-clock time is informational across
/// devices: only the device that wrote two timestamps may compare them (the host checking its own invitation).
public struct RoomTimestamp: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Milliseconds since 1970-01-01T00:00:00Z.
    public let millisecondsSinceEpoch: Int
    public let text: String

    /// `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,3})?Z$`, and a real calendar instant.
    public init?(_ text: String) {
        let s = Array(text.utf8)
        func digits(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= s.count else { return nil }
            var value = 0
            for i in range {
                guard (48...57).contains(s[i]) else { return nil }
                value = value * 10 + Int(s[i] - 48)
            }
            return value
        }
        guard s.count >= 20, s.last == UInt8(ascii: "Z"),
              s[4] == UInt8(ascii: "-"), s[7] == UInt8(ascii: "-"), s[10] == UInt8(ascii: "T"),
              s[13] == UInt8(ascii: ":"), s[16] == UInt8(ascii: ":"),
              let year = digits(0..<4), let month = digits(5..<7), let day = digits(8..<10),
              let hour = digits(11..<13), let minute = digits(14..<16), let second = digits(17..<19) else { return nil }
        var millis = 0
        if s.count > 20 {
            let fraction = 20..<(s.count - 1)
            guard s[19] == UInt8(ascii: "."), (1...3).contains(fraction.count), let value = digits(fraction) else {
                return nil
            }
            millis = value * [1, 100, 10, 1][fraction.count]
        } else if s.count != 20 {
            return nil
        }
        guard (1...12).contains(month), (1...Self.daysIn(month, year)).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }
        let days = Self.daysFromCivil(year, month, day)
        millisecondsSinceEpoch = ((days * 24 + hour) * 60 + minute) * 60_000 + second * 1000 + millis
        self.text = text
    }

    public static func < (lhs: RoomTimestamp, rhs: RoomTimestamp) -> Bool {
        lhs.millisecondsSinceEpoch < rhs.millisecondsSinceEpoch
    }

    public var description: String { text }

    private static func daysIn(_ month: Int, _ year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant's days_from_civil).
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
