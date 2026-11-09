import Foundation

/// The stable machine codes of the job machine, the quote rules and the reservation ledger (STU-04). They are the
/// codes of `spec/reference/studio/jobstate.py`, `ledger.py` and `records.py`, spelled exactly, so a shared vector or
/// invalid case names the same code on every platform. Fixtures assert the code, never the message.
public enum LedgerRejectCode: String, CaseIterable, Hashable, Sendable {
    // RenderJob machine (jobstate.py)
    case unknownState, badResumeStage, terminalState, illegalTransition, retriesExhausted, reservationRequired
    case unverifiedReady, badHistory, stateMismatch
    /// Swift only: a local job never enters a cloud-only state (quote, consent, upload, budget).
    case cloudOnlyState
    // Quotes (ledger.py, records.check_quote)
    case unknownFilmClass, badEstimate, quoteCapMismatch, badQuote, illustrativeQuote, consentMissing, quoteExpired
    case badQuoteState, unknownQuote, quoteNotAccepted, quoteMismatch, quoteAlreadyUsed, quoteLifetime, plannerMismatch
    case sampleRequired
    // Reservations (ledger.py)
    case badAmount, demoNeverReserves, liveChargingNotActivated, idempotencyConflict, overCap, insufficientCredits
    case badIdentifier, jobMismatch, reservationClosed, unknownStage, budgetExceeded, unknownReservation, badEntryKey
    case ledgerMismatch
    // Shared
    case badTimestamp
}

/// A rule violation with a stable code (`core.Reject` in the Python reference).
public struct LedgerRejection: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: LedgerRejectCode
    public let message: String

    public init(_ code: LedgerRejectCode, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }

    /// `core.require`: throws `code` unless `condition` holds.
    static func require(_ condition: Bool, _ code: LedgerRejectCode, _ message: @autoclosure () -> String) throws(LedgerRejection) {
        if !condition { throw LedgerRejection(code, message()) }
    }
}

/// A Studio wall-clock instant (studio-common `dateTime`: `YYYY-MM-DDTHH:MM:SS(.fff)?Z`), parsed before any
/// comparison. Timestamps are never compared as text: `...:00.500Z` sorts before `...:00Z` as a string but is half a
/// second later (`core.when`).
public struct StudioTimestamp: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Milliseconds since 1970-01-01T00:00:00Z.
    public let millisecondsSinceEpoch: Int
    /// The text as written.
    public let text: String

    /// Parses the studio-common `dateTime` shape and a real calendar instant; anything else is `badTimestamp`.
    public init(_ text: String) throws(LedgerRejection) {
        guard let millis = Self.parse(Array(text.utf8)) else {
            throw LedgerRejection(.badTimestamp, "\(text.debugDescription) is not an RFC 3339 UTC timestamp")
        }
        self.millisecondsSinceEpoch = millis
        self.text = text
    }

    public static func < (lhs: StudioTimestamp, rhs: StudioTimestamp) -> Bool {
        lhs.millisecondsSinceEpoch < rhs.millisecondsSinceEpoch
    }

    /// Equality is the instant, not the spelling (`...:00Z` equals `...:00.000Z`).
    public static func == (lhs: StudioTimestamp, rhs: StudioTimestamp) -> Bool {
        lhs.millisecondsSinceEpoch == rhs.millisecondsSinceEpoch
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(millisecondsSinceEpoch) }

    public var description: String { text }

    /// Whole milliseconds from `self` to `later` (negative when `later` is earlier).
    public func milliseconds(until later: StudioTimestamp) -> Int {
        later.millisecondsSinceEpoch - millisecondsSinceEpoch
    }

    private static func parse(_ s: [UInt8]) -> Int? {
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
        }
        guard (1...12).contains(month), (1...daysIn(month, year)).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }
        let days = daysFromCivil(year, month, day)
        return ((days * 24 + hour) * 60 + minute) * 60_000 + second * 1000 + millis
    }

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
