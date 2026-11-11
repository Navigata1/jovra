import Foundation
import JovraCore

/// How the hand-picked side of a comparison was selected (spec ProgressStoryBuilder; story 136).
public enum ProgressSelectionRule: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case seededRandom = "seeded-random"
    case userChosen = "user-chosen"
}

/// The method that produced a scope's events. A different method id, method version or capability version is a
/// method change, and a method change drops the comparison.
public struct ProgressMethod: Codable, Hashable, Sendable {
    public var methodId: String
    public var methodVersion: String
    public var capabilityVersion: String?

    public init(methodId: String, methodVersion: String, capabilityVersion: String?) {
        self.methodId = methodId
        self.methodVersion = methodVersion
        self.capabilityVersion = capabilityVersion
    }
}

/// One dated side of a comparison: one stat over one or more sessions, with how it was measured and selected.
public struct ProgressScope: Hashable, Sendable {
    /// YYYY-MM-DD.
    public var date: String
    public var sessionIds: [String]
    /// An opaque key for comparable sessions ("practice", "match"); only equal kinds compare.
    public var sessionKind: String
    public var statDefinitionId: String
    public var method: ProgressMethod
    public var selectionRule: ProgressSelectionRule
    public var numerator: Int
    public var denominator: Int
    /// The weakest provenance of the events counted.
    public var provenance: Provenance

    public init(date: String, sessionIds: [String], sessionKind: String, statDefinitionId: String, method: ProgressMethod,
                selectionRule: ProgressSelectionRule, numerator: Int, denominator: Int, provenance: Provenance) {
        self.date = date
        self.sessionIds = sessionIds
        self.sessionKind = sessionKind
        self.statDefinitionId = statDefinitionId
        self.method = method
        self.selectionRule = selectionRule
        self.numerator = numerator
        self.denominator = denominator
        self.provenance = provenance
    }
}

/// Why a comparison is dropped, in the order they are reported (`spec/reference/studio/progress.py` REASONS).
public enum ProgressReason: String, CaseIterable, Hashable, Sendable {
    case statDefinitionChange, methodChange, sessionKindChange, differingSelection, notReviewed, emptySample
}

/// What the film may say: a change (or no change) between comparable scopes, or only a chronology (story 137).
public enum ProgressClaim: String, Hashable, Sendable {
    case change
    case noChange = "no-change"
    case chronology
}

/// One side of a result: the core Fraction (`RateRatio`, with the integer `pct`) and its display "12 / 30 · 40%".
public struct ProgressSide: Equatable, Sendable {
    public let date: String
    public let sessionIds: [String]
    public let fraction: RateRatio
    /// "12 / 30 · 40%"; an empty sample shows "0 / 0 · —".
    public let display: String
    /// "Examples you chose" on a user-chosen side (story 136), otherwise nil.
    public let selectionLabel: String?
}

/// The result of `ProgressStoryBuilder.compare`. A percentage "improvement" of a proportion is never produced: a
/// change is stated only in percentage points, taken from the two displayed integers.
public struct ProgressComparison: Equatable, Sendable {
    public let statDefinitionId: String
    public let earlier: ProgressSide
    public let later: ProgressSide
    public let comparable: Bool
    public let reasons: [ProgressReason]
    /// Later displayed integer minus earlier displayed integer; nil unless comparable.
    public let deltaPercentagePoints: Int?
    /// "+20 percentage points", "+1 percentage point", "0 percentage points"; nil unless comparable.
    public let deltaDisplay: String?
    /// "12 / 30 · 40% → 18 / 30 · 60%, +20 percentage points" (story 134); nil unless comparable.
    public let summary: String?
    public let claim: ProgressClaim
}

/// A refused comparison (the reference's `Reject` codes).
public struct ProgressRejection: Error, Equatable, CustomStringConvertible, Sendable {
    public enum Code: String, Sendable {
        /// The later date is not after the earlier one.
        case notChronological
        /// A numerator outside `0...denominator`.
        case badFraction
        /// A malformed scope.
        case badScope
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }
}

/// ProgressStoryBuilder (Studio spec, Domain modules; stories 134–137). Pure and offline.
public enum ProgressStoryBuilder {
    public static let chosenLabel = "Examples you chose"

    /// Compares two dated scopes of `statDefinitionId`. Comparable only when the stat definition is the requested one
    /// on both sides and the method, session kind and selection rule match, both sides are at least Reviewed and
    /// neither sample is empty; otherwise every reason is listed and the result is a chronology with no delta.
    public static func compare(_ statDefinitionId: String, earlier: ProgressScope,
                               later: ProgressScope) throws(ProgressRejection) -> ProgressComparison {
        let earlierDay = try validate(earlier, "earlier")
        let laterDay = try validate(later, "later")
        guard earlierDay < laterDay else {
            throw ProgressRejection(.notChronological, "earlier \(earlier.date) is not before later \(later.date)")
        }
        var found: Set<ProgressReason> = []
        if earlier.statDefinitionId != statDefinitionId || later.statDefinitionId != statDefinitionId {
            found.insert(.statDefinitionChange)
        }
        if earlier.method != later.method { found.insert(.methodChange) }
        if earlier.sessionKind != later.sessionKind { found.insert(.sessionKindChange) }
        if earlier.selectionRule != later.selectionRule { found.insert(.differingSelection) }
        if !earlier.provenance.isAtLeastReviewed || !later.provenance.isAtLeastReviewed { found.insert(.notReviewed) }
        if earlier.denominator == 0 || later.denominator == 0 { found.insert(.emptySample) }
        let reasons = ProgressReason.allCases.filter(found.contains)
        let before = try side(earlier), after = try side(later)
        guard reasons.isEmpty, let from = before.fraction.pct.value, let to = after.fraction.pct.value else {
            return ProgressComparison(statDefinitionId: statDefinitionId, earlier: before, later: after, comparable: false,
                                      reasons: reasons, deltaPercentagePoints: nil, deltaDisplay: nil, summary: nil,
                                      claim: .chronology)
        }
        // from the displayed integers, never the exact difference (1 / 8 = 13% and 5 / 16 = 31% give 18, not 19)
        let delta = to - from
        let wording = Percent.delta(current: after.fraction, prior: before.fraction)
        return ProgressComparison(statDefinitionId: statDefinitionId, earlier: before, later: after, comparable: true,
                                  reasons: [], deltaPercentagePoints: delta, deltaDisplay: wording,
                                  summary: "\(before.display) → \(after.display), \(wording)",
                                  claim: delta == 0 ? .noChange : .change)
    }

    /// The day a valid scope stands for, or `badScope` / `badFraction`.
    static func validate(_ scope: ProgressScope, _ side: String) throws(ProgressRejection) -> ProgressDay {
        guard let day = ProgressDay(scope.date) else {
            throw ProgressRejection(.badScope, "\(side) date \(scope.date) is not YYYY-MM-DD")
        }
        guard !scope.sessionIds.isEmpty else { throw ProgressRejection(.badScope, "\(side) needs a session") }
        guard scope.numerator >= 0, scope.denominator >= 0, scope.numerator <= scope.denominator else {
            throw ProgressRejection(.badFraction, "\(side) fraction \(scope.numerator) / \(scope.denominator)")
        }
        return day
    }

    private static func side(_ scope: ProgressScope) throws(ProgressRejection) -> ProgressSide {
        let fraction: RateRatio
        do { fraction = try Percent.ratio(n: scope.numerator, d: scope.denominator) }
        catch { throw ProgressRejection(.badFraction, "\(scope.numerator) / \(scope.denominator)") }
        return ProgressSide(date: scope.date, sessionIds: scope.sessionIds, fraction: fraction,
                            display: "\(fraction.n) / \(fraction.d) · \(fraction.display)",
                            selectionLabel: scope.selectionRule == .userChosen ? chosenLabel : nil)
    }
}

extension Provenance {
    /// Reviewed or Validated: the only evidence a stated change may rest on.
    var isAtLeastReviewed: Bool { self == .reviewed || self == .validated }
}

/// A proleptic Gregorian calendar day read strictly from YYYY-MM-DD (no time zone, no lenient rollover).
struct ProgressDay: Comparable, Hashable, Sendable {
    let year: Int, month: Int, day: Int

    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              y >= 1, (1...12).contains(m), d >= 1, d <= Self.days(in: m, of: y) else { return nil }
        year = y; month = m; day = d
    }

    static func days(in month: Int, of year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func < (a: Self, b: Self) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}
