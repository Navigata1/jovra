import Foundation
import JovraCore

/// The quote and usage-reservation ledger (STU-04), a port of `spec/reference/studio/ledger.py`'s `Ledger`:
/// quote -> consent -> cap -> idempotent reservation -> per-stage consumption -> release.
///
/// - A reservation is keyed by `(projectId, planRevision, outputSpecSha256)`. Replaying a request returns the same
///   reservation and charges nothing; the same key with other terms is `idempotencyConflict`; a new plan revision is a
///   new key. An accepted quote funds exactly one reservation, and only the one its `outputSpecSha256` names.
/// - After `budget_exceeded` the key is never re-reserved: an accepted re-quote tops the held reservation up
///   (`topup`), keyed by the top-up quote and never by the initial quote; the old quote is superseded.
/// - Consumption is written when a stage attempt succeeds and is keyed by `(jobId, stage)`: a redelivered message or a
///   later attempt of a charged stage replays; it never exceeds the reservation (`budgetExceeded`), and only the one
///   job the reservation names may consume it, under a charged stage spelled exactly as the job contract spells it.
/// - A reservation remembers every `(quoteId, credits)` request it applied, so a redelivered original reserve or a
///   redelivered top-up replays instead of returning `idempotencyConflict` (finding 9).
/// - The demo never reserves, test reservations are Sample, live charging is refused (`liveChargingNotActivated`)
///   until a new pricing ADR exists (ADR-0013).
///
/// Every timestamp is parsed (`StudioTimestamp`) before it is compared.
public struct Ledger: Sendable {
    /// The quote fields the ledger reads (a stored `jovra.quote/1` carries more).
    public struct QuoteTerms: Equatable, Sendable {
        public var quoteId: String
        public var projectId: String
        public var planRevision: Int
        public var outputSpecSha256: String
        public var filmClassId: String
        public var estimatedMaxCostMicroUsd: Int
        public var estimateMinCredits: Int
        public var estimateMaxCredits: Int
        public var capCredits: Int
        public var expiresAt: String
        public var status: QuoteStatus
        public var illustrative: Bool

        public init(quoteId: String, projectId: String, planRevision: Int, outputSpecSha256: String, filmClassId: String,
                    estimatedMaxCostMicroUsd: Int, estimateMinCredits: Int, estimateMaxCredits: Int, capCredits: Int,
                    expiresAt: String, status: QuoteStatus = .open, illustrative: Bool = false) {
            self.quoteId = quoteId
            self.projectId = projectId
            self.planRevision = planRevision
            self.outputSpecSha256 = outputSpecSha256
            self.filmClassId = filmClassId
            self.estimatedMaxCostMicroUsd = estimatedMaxCostMicroUsd
            self.estimateMinCredits = estimateMinCredits
            self.estimateMaxCredits = estimateMaxCredits
            self.capCredits = capCredits
            self.expiresAt = expiresAt
            self.status = status
            self.illustrative = illustrative
        }

        public init(_ quote: Quote) {
            self.init(quoteId: quote.quoteId, projectId: quote.projectId, planRevision: quote.planRevision,
                      outputSpecSha256: quote.outputSpecSha256, filmClassId: quote.filmClass.rawValue,
                      estimatedMaxCostMicroUsd: quote.estimatedMaxCostMicroUsd, estimateMinCredits: quote.estimate.minCredits,
                      estimateMaxCredits: quote.estimate.maxCredits, capCredits: quote.capCredits, expiresAt: quote.expiresAt,
                      status: quote.status, illustrative: quote.illustrative)
        }
    }

    /// The idempotency key of a reservation.
    public struct Key: Hashable, Sendable {
        public let projectId: String
        public let planRevision: Int
        public let outputSpecSha256: String

        public init(projectId: String, planRevision: Int, outputSpecSha256: String) {
            self.projectId = projectId
            self.planRevision = planRevision
            self.outputSpecSha256 = outputSpecSha256
        }
    }

    /// A reserve or top-up request that was applied: a redelivery of the same pair replays.
    public struct AppliedRequest: Hashable, Sendable {
        public let quoteId: String
        public let credits: Int
    }

    public struct Reservation: Equatable, Sendable {
        public let reservationId: String
        public internal(set) var quoteId: String
        public let initialQuoteId: String
        public internal(set) var jobId: String?
        public let key: Key
        public internal(set) var capCredits: Int
        public internal(set) var reservedCredits: Int
        public internal(set) var consumedCredits: Int = 0
        public internal(set) var releasedCredits: Int = 0
        public internal(set) var status: UsageReservationStatus = .held
        public internal(set) var reserveRequests: Set<AppliedRequest>
        public internal(set) var topupRequests: Set<AppliedRequest> = []
    }

    public enum Outcome: String, Sendable, CaseIterable {
        case ready, failed, canceled

        var closedStatus: UsageReservationStatus {
            switch self {
            case .ready: .settled
            case .failed: .released
            case .canceled: .canceled
            }
        }
    }

    public struct ReserveResult: Equatable, Sendable {
        public let reservationId: String
        public let replayed: Bool
        public let balance: Int

        public init(reservationId: String, replayed: Bool, balance: Int) {
            self.reservationId = reservationId
            self.replayed = replayed
            self.balance = balance
        }
    }

    public struct AttachResult: Equatable, Sendable {
        public let reservationId: String
        public let jobId: String
        public let replayed: Bool

        public init(reservationId: String, jobId: String, replayed: Bool) {
            self.reservationId = reservationId
            self.jobId = jobId
            self.replayed = replayed
        }
    }

    public struct TopupResult: Equatable, Sendable {
        public let reservationId: String
        public let reservedCredits: Int
        public let replayed: Bool
        public let balance: Int

        public init(reservationId: String, reservedCredits: Int, replayed: Bool, balance: Int) {
            self.reservationId = reservationId
            self.reservedCredits = reservedCredits
            self.replayed = replayed
            self.balance = balance
        }
    }

    public struct ConsumeResult: Equatable, Sendable {
        public let consumedCredits: Int
        public let replayed: Bool

        public init(consumedCredits: Int, replayed: Bool) {
            self.consumedCredits = consumedCredits
            self.replayed = replayed
        }
    }

    public struct ReleaseResult: Equatable, Sendable {
        public let releasedCredits: Int
        public let replayed: Bool
        public let balance: Int

        public init(releasedCredits: Int, replayed: Bool, balance: Int) {
            self.releasedCredits = releasedCredits
            self.replayed = replayed
            self.balance = balance
        }
    }

    private struct StageKey: Hashable {
        let reservationId: String
        let jobId: String
        let stage: String
    }

    public let environment: StudioEnvironment
    public private(set) var balance: Int
    public private(set) var quotes: [String: QuoteTerms] = [:]
    public private(set) var reservations: [String: Reservation] = [:]
    /// The charged stages of the job contract (`budgetCheckedBefore`), spelled exactly.
    public let chargedStages: Set<String>
    private var quoteReservation: [String: String] = [:]
    private var byKey: [Key: String] = [:]
    private var consumed: [StageKey: Int] = [:]
    private var counter = 0
    private let book: CreditBook

    public init(environment: StudioEnvironment, balance: Int, classes: CreditClasses,
                jobContract: RenderJobTransitions) throws(LedgerRejection) {
        try LedgerRejection.require(balance >= 0, .badAmount, "balance must be an integer >= 0")
        self.environment = environment
        self.balance = balance
        self.book = CreditBook(classes: classes)
        self.chargedStages = Set(jobContract.budgetCheckedBefore.map(\.rawValue))
    }

    /// Credits from a received JSON value: a plain integer token >= `minimum`. A boolean is not a credit (`true` would
    /// otherwise count as 1) and neither is an integral float (`badAmount`).
    public static func credits(_ value: StudioJSONValue?, label: String = "credits", minimum: Int = 0) throws(LedgerRejection) -> Int {
        guard case .number(let number)? = value, let int = number.int64, int >= minimum, int <= Int64(Int.max) else {
            throw LedgerRejection(.badAmount, "\(label) must be an integer >= \(minimum)")
        }
        return Int(int)
    }

    // MARK: quotes

    public mutating func addQuote(_ quote: QuoteTerms) throws(LedgerRejection) {
        typealias R = LedgerRejection
        let expected = try book.quoteCredits(filmClassId: quote.filmClassId, estimatedMaxCostMicroUsd: quote.estimatedMaxCostMicroUsd)
        try R.require(quote.capCredits == expected, .quoteCapMismatch,
                      "cap must be \(expected) credits from the class minimum and cost estimate")
        try R.require(quote.estimateMinCredits <= quote.estimateMaxCredits && quote.estimateMaxCredits <= quote.capCredits,
                      .badQuote, "estimate must satisfy min <= max <= cap")
        try R.require(Self.isHex64(quote.outputSpecSha256), .badQuote, "a quote is bound to one output spec (outputSpecSha256)")
        quotes[quote.quoteId] = quote
        quoteReservation[quote.quoteId] = nil
    }

    public mutating func accept(quoteId: String, at: String, consent: Bool) throws(LedgerRejection) {
        typealias R = LedgerRejection
        var quote = try self.quote(quoteId)
        try R.require(!quote.illustrative, .illustrativeQuote, "an illustrative Sample quote can never be accepted")
        try R.require(consent, .consentMissing, "the owner must consent to uploading the selected sources")
        try R.require(try StudioTimestamp(at) < StudioTimestamp(quote.expiresAt), .quoteExpired,
                      "quote expired; re-quote, never auto-accept")
        try R.require(quote.status == .open, .badQuoteState, "quote is \(quote.status.rawValue)")
        quote.status = .accepted
        quotes[quoteId] = quote
    }

    // MARK: reservations

    public mutating func reserve(quoteId: String, projectId: String, planRevision: Int, outputSpecSha256: String,
                                 credits: Int, at: String, jobId: String? = nil) throws(LedgerRejection) -> ReserveResult {
        typealias R = LedgerRejection
        try R.require(environment != .demo, .demoNeverReserves, "demo identities never write reservations")
        try R.require(environment != .live, .liveChargingNotActivated,
                      "live charging needs its own ADR, benchmarks and a margin model (ADR-0013)")
        try R.require(credits >= 0, .badAmount, "credits must be an integer >= 0")
        let key = Key(projectId: projectId, planRevision: planRevision, outputSpecSha256: outputSpecSha256)
        if let existing = byKey[key], let r = reservations[existing] {
            try R.require(r.reserveRequests.contains(AppliedRequest(quoteId: quoteId, credits: credits))
                          && (jobId == nil || jobId == r.jobId), .idempotencyConflict,
                          "same idempotency key with different terms or another job (after budget_exceeded, top up instead)")
            return ReserveResult(reservationId: r.reservationId, replayed: true, balance: balance)
        }
        let quote = try self.quote(quoteId)
        try fundable(quote, key: key, at: at)
        try R.require(credits > 0 && credits <= quote.capCredits, .overCap, "reservation must be positive and within the cap")
        try R.require(credits <= balance, .insufficientCredits, "not enough credits")
        counter += 1
        let rid = "res-" + String(repeating: "0", count: max(0, 4 - String(counter).count)) + String(counter)
        balance -= credits
        reservations[rid] = Reservation(reservationId: rid, quoteId: quoteId, initialQuoteId: quoteId, jobId: jobId, key: key,
                                        capCredits: quote.capCredits, reservedCredits: credits,
                                        reserveRequests: [AppliedRequest(quoteId: quoteId, credits: credits)])
        byKey[key] = rid
        quoteReservation[quoteId] = rid
        return ReserveResult(reservationId: rid, replayed: false, balance: balance)
    }

    /// Names the one job a reservation funds (at job creation). The same job replays; another job is `jobMismatch`.
    public mutating func attachJob(reservationId: String, jobId: String) throws(LedgerRejection) -> AttachResult {
        var r = try reservation(reservationId)
        try LedgerRejection.require(!jobId.isEmpty, .badIdentifier, "jobId must be a non-empty id")
        if r.jobId == jobId { return AttachResult(reservationId: reservationId, jobId: jobId, replayed: true) }
        try LedgerRejection.require(r.jobId == nil, .jobMismatch, "reservation \(reservationId) already funds \(r.jobId ?? "")")
        r.jobId = jobId
        reservations[reservationId] = r
        return AttachResult(reservationId: reservationId, jobId: jobId, replayed: false)
    }

    /// Raises a held reservation to `credits` under a newly accepted quote for the same key (the `budget_exceeded`
    /// resume path). Recorded consumption stays, so no stage is charged twice.
    public mutating func topup(reservationId: String, quoteId: String, credits: Int, at: String) throws(LedgerRejection) -> TopupResult {
        typealias R = LedgerRejection
        var r = try reservation(reservationId)
        try R.require(credits >= 0, .badAmount, "credits must be an integer >= 0")
        if r.topupRequests.contains(AppliedRequest(quoteId: quoteId, credits: credits)) {
            // a redelivered top-up that was already applied: replay the current state, charge nothing (finding 9)
            return TopupResult(reservationId: reservationId, reservedCredits: r.reservedCredits, replayed: true, balance: balance)
        }
        try R.require(r.status == .held, .reservationClosed, "reservation is \(r.status.rawValue)")
        let quote = try self.quote(quoteId)
        try R.require(quoteId != r.quoteId && quoteId != r.initialQuoteId, .idempotencyConflict, "a top-up needs a new accepted quote")
        try fundable(quote, key: r.key, at: at)
        try R.require(r.reservedCredits < credits && credits <= quote.capCredits, .overCap,
                      "a top-up raises the reservation and stays within the new cap")
        let extra = credits - r.reservedCredits
        try R.require(extra <= balance, .insufficientCredits, "not enough credits")
        balance -= extra
        quotes[r.quoteId]?.status = .superseded
        quoteReservation[quoteId] = reservationId
        r.quoteId = quoteId
        r.capCredits = quote.capCredits
        r.reservedCredits = credits
        r.topupRequests.insert(AppliedRequest(quoteId: quoteId, credits: credits))
        reservations[reservationId] = r
        return TopupResult(reservationId: reservationId, reservedCredits: credits, replayed: false, balance: balance)
    }

    /// Records a succeeded stage attempt. Keyed by `(jobId, stage)`: a later attempt or a redelivery replays.
    public mutating func consume(reservationId: String, jobId: String, stage: String, attempt: Int,
                                 credits: Int) throws(LedgerRejection) -> ConsumeResult {
        typealias R = LedgerRejection
        var r = try reservation(reservationId)
        try R.require(r.status == .held, .reservationClosed, "reservation is \(r.status.rawValue)")
        try R.require(credits >= 0, .badAmount, "credits must be an integer >= 0")
        try R.require(attempt >= 1, .badAmount, "attempt must be an integer >= 1")
        try R.require(r.jobId != nil && jobId == r.jobId, .jobMismatch,
                      "reservation \(reservationId) funds job \(r.jobId ?? "null"), not \(jobId.debugDescription)")
        try R.require(chargedStages.contains(stage), .unknownStage,
                      "\(stage.debugDescription) is not a charged stage of the job contract (exact spelling)")
        let key = StageKey(reservationId: reservationId, jobId: jobId, stage: stage)
        if let charged = consumed[key] {
            try R.require(charged == credits, .idempotencyConflict, "this stage was already charged a different amount")
            return ConsumeResult(consumedCredits: r.consumedCredits, replayed: true)
        }
        try R.require(r.consumedCredits + credits <= r.reservedCredits, .budgetExceeded,
                      "stage would exceed the reservation; stop at budget_exceeded, never raise the cap")
        r.consumedCredits += credits
        consumed[key] = credits
        reservations[reservationId] = r
        return ConsumeResult(consumedCredits: r.consumedCredits, replayed: false)
    }

    /// Closes a reservation: `ready` settles consumption; `failed` and `canceled` return every unconsumed credit (a
    /// film that failed verification is never charged as delivered). A second release replays.
    public mutating func release(reservationId: String, outcome: Outcome) throws(LedgerRejection) -> ReleaseResult {
        var r = try reservation(reservationId)
        guard r.status == .held else {
            return ReleaseResult(releasedCredits: r.releasedCredits, replayed: true, balance: balance)
        }
        let unused = r.reservedCredits - r.consumedCredits
        r.releasedCredits = unused
        r.status = outcome.closedStatus
        balance += unused
        reservations[reservationId] = r
        return ReleaseResult(releasedCredits: unused, replayed: false, balance: balance)
    }

    // MARK: helpers

    private func quote(_ quoteId: String) throws(LedgerRejection) -> QuoteTerms {
        guard let quote = quotes[quoteId] else { throw LedgerRejection(.unknownQuote, "unknown quote \(quoteId)") }
        return quote
    }

    private func reservation(_ reservationId: String) throws(LedgerRejection) -> Reservation {
        guard let r = reservations[reservationId] else {
            throw LedgerRejection(.unknownReservation, "unknown reservation \(reservationId)")
        }
        return r
    }

    private func fundable(_ quote: QuoteTerms, key: Key, at: String) throws(LedgerRejection) {
        typealias R = LedgerRejection
        try R.require(quote.status == .accepted, .quoteNotAccepted, "reserve only after the quote is accepted")
        try R.require(try StudioTimestamp(at) < StudioTimestamp(quote.expiresAt), .quoteExpired, "quote expired before the reservation")
        try R.require(quote.projectId == key.projectId && quote.planRevision == key.planRevision
                      && quote.outputSpecSha256 == key.outputSpecSha256, .quoteMismatch,
                      "the quote is for another project, plan revision or output spec")
        try R.require(quoteReservation[quote.quoteId] == nil, .quoteAlreadyUsed, "an accepted quote funds exactly one reservation")
    }

    static func isHex64(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.count == 64 && bytes.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
