import Foundation
import JovraCore

/// The client's quote and consent state (STU-04, ST37 preflight): a pure state machine with no I/O.
///
/// `none -> requested -> presented(expiresAt) -> consented -> accepted(reservationId)`, with the side states
/// `expired` (a fresh quote is required: an expired quote is never auto-accepted, story 185), `aboveCap` (the quote's
/// cap is over the player's spending limit; only the player raises the limit, story 186), `unavailable(reason)` and
/// `demoDisabled` (demo mode never uploads, reserves or charges).
///
/// Times are parsed (`StudioTimestamp`), never compared as text, so a consent at `23:15:00.500Z` on a quote that
/// expires at `23:15:00Z` is refused. The client never computes a price the server trusts: the quote's credits come
/// from the server, and `acceptRequest` carries the quote id, its idempotency key and the consent, never an amount.
public struct QuoteReservation: Equatable, Sendable {
    public enum UnavailableReason: String, Equatable, Sendable, CaseIterable {
        /// No account: ST37 "Sign in to make films in the cloud."
        case notSignedIn
        /// The quote service did not answer: ST37 "Cloud production isn't available right now."
        case cloudUnavailable
        /// A live quote: live charging waits for its own pricing ADR (ADR-0013).
        case liveChargingNotActivated
    }

    /// The owner's ticked boxes on ST37 (both unchecked by default).
    public struct ConsentChoice: Equatable, Sendable {
        public var uploadSelectedSources: Bool
        public var modelProvider: Bool
        public var textClasses: [QuoteConsentTextClass]
        public var consentRecordId: String
        public var consentTextVersion: String

        public init(uploadSelectedSources: Bool, modelProvider: Bool = false, textClasses: [QuoteConsentTextClass] = [],
                    consentRecordId: String, consentTextVersion: String) {
            self.uploadSelectedSources = uploadSelectedSources
            self.modelProvider = modelProvider
            self.textClasses = textClasses
            self.consentRecordId = consentRecordId
            self.consentTextVersion = consentTextVersion
        }
    }

    /// What the client sends to accept: no credits, cap or cost, so nothing the client computed can become a price.
    /// A second tap or a retry sends the same request (one job, one reservation).
    public struct AcceptRequest: Equatable, Sendable {
        public let quoteId: String
        public let idempotencyKey: Ledger.Key
        public let consent: QuoteConsent
    }

    public enum State: Equatable, Sendable {
        case none
        case requested
        case presented(Quote)
        case consented(Quote, QuoteConsent)
        case accepted(Quote, reservationId: String)
        case expired(Quote)
        case aboveCap(Quote)
        case unavailable(UnavailableReason)
        /// Demo mode: the Sample quote is shown, and nothing is reserved.
        case demoDisabled(Quote?)
    }

    public let environment: StudioEnvironment
    public private(set) var spendingLimitCredits: Int
    public private(set) var state: State = .none

    public init(environment: StudioEnvironment, spendingLimitCredits: Int) throws(LedgerRejection) {
        try LedgerRejection.require(spendingLimitCredits >= 0, .badAmount, "the spending limit is an integer >= 0")
        self.environment = environment
        self.spendingLimitCredits = spendingLimitCredits
    }

    /// The quote shown now, in any state that shows one.
    public var quote: Quote? {
        switch state {
        case .presented(let q), .consented(let q, _), .accepted(let q, _), .expired(let q), .aboveCap(let q): q
        case .demoDisabled(let q): q
        case .none, .requested, .unavailable: nil
        }
    }

    /// The reservation the server accepted; only in `accepted`.
    public var reservationId: String? {
        if case .accepted(_, let id) = state { id } else { nil }
    }

    /// The request to send in `consented`; nil otherwise.
    public var acceptRequest: AcceptRequest? {
        guard case .consented(let q, let consent) = state else { return nil }
        return AcceptRequest(quoteId: q.quoteId, idempotencyKey: Self.key(q), consent: consent)
    }

    /// Ask for a (fresh) quote. Allowed when no quote is live: at the start, after expiry, above the limit, when the
    /// service was unavailable, and in demo. A changed retention or angle count re-quotes the same way.
    public mutating func request() throws(LedgerRejection) {
        switch state {
        case .none, .expired, .aboveCap, .unavailable, .presented, .demoDisabled:
            state = .requested
        case .requested, .consented, .accepted:
            throw LedgerRejection(.badQuoteState, "a quote is already requested, consented or accepted")
        }
    }

    /// The quote service answered with `quote` at `now`.
    public mutating func present(_ quote: Quote, at now: StudioTimestamp) throws(LedgerRejection) {
        guard state == .requested else { throw LedgerRejection(.badQuoteState, "no quote was requested") }
        try LedgerRejection.require(quote.environment == environment, .quoteMismatch,
                                    "a \(quote.environment.rawValue) quote in a \(environment.rawValue) session")
        if environment == .demo {
            state = .demoDisabled(quote)
            return
        }
        if environment == .live {
            state = .unavailable(.liveChargingNotActivated)
            return
        }
        try LedgerRejection.require(!quote.illustrative, .illustrativeQuote, "an illustrative Sample quote is never accepted")
        try LedgerRejection.require(quote.status == .open, .badQuoteState, "the quote is \(quote.status.rawValue)")
        state = try now < StudioTimestamp(quote.expiresAt) ? .presented(quote) : .expired(quote)
        if quote.capCredits > spendingLimitCredits, case .presented = state { state = .aboveCap(quote) }
    }

    /// The quote service could not quote.
    public mutating func fail(_ reason: UnavailableReason) throws(LedgerRejection) {
        guard state == .requested else { throw LedgerRejection(.badQuoteState, "no quote was requested") }
        state = .unavailable(reason)
    }

    /// Re-checks expiry at `now`: a presented or consented quote past `expiresAt` becomes `expired` and its consent
    /// is cleared.
    public mutating func refresh(at now: StudioTimestamp) throws(LedgerRejection) {
        switch state {
        case .presented(let q), .consented(let q, _), .aboveCap(let q):
            if try now >= StudioTimestamp(q.expiresAt) { state = .expired(q) }
        default:
            break
        }
    }

    /// The player sets a new spending limit. Nothing else ever changes it. Above the cap a presented quote waits in
    /// `aboveCap` (consent cleared); at or over the cap an `aboveCap` quote is presented again.
    public mutating func changeLimit(to credits: Int, at now: StudioTimestamp) throws(LedgerRejection) {
        try LedgerRejection.require(credits >= 0, .badAmount, "the spending limit is an integer >= 0")
        spendingLimitCredits = credits
        try refresh(at: now)
        switch state {
        case .presented(let q), .consented(let q, _):
            if q.capCredits > credits { state = .aboveCap(q) }
        case .aboveCap(let q):
            if q.capCredits <= credits { state = .presented(q) }
        default:
            break
        }
    }

    /// The owner ticks the consent boxes at `now`. Refused after expiry (the state becomes `expired`, consent
    /// cleared), without the upload consent, or when the model-provider consent does not match the planner choice.
    public mutating func consent(_ choice: ConsentChoice, at now: StudioTimestamp) throws(LedgerRejection) {
        if case .demoDisabled = state { throw LedgerRejection(.demoNeverReserves, "demo mode does not upload or charge") }
        try refresh(at: now)
        switch state {
        case .presented(let q), .consented(let q, _):
            try LedgerRejection.require(choice.uploadSelectedSources, .consentMissing, "tick the box to upload these videos")
            let consent = QuoteConsent(consentRecordId: choice.consentRecordId, uploadSelectedSources: true,
                                       modelProvider: choice.modelProvider, textClasses: choice.textClasses,
                                       retentionDays: q.retentionDays, consentTextVersion: choice.consentTextVersion, at: now.text)
            try CreditBook.checkConsent(consent, retentionDays: q.retentionDays, plannerChoice: q.plannerChoice)
            state = .consented(q, consent)
        case .expired:
            throw LedgerRejection(.quoteExpired, "this quote expired; get a new quote")
        case .aboveCap:
            throw LedgerRejection(.overCap, "the estimate is above your limit")
        default:
            throw LedgerRejection(.badQuoteState, "no quote to consent to")
        }
    }

    /// The server accepted the request and holds `reservationId`. Refused unless consented and before expiry.
    public mutating func accepted(reservationId: String, at now: StudioTimestamp) throws(LedgerRejection) {
        if case .demoDisabled = state { throw LedgerRejection(.demoNeverReserves, "demo mode never reserves") }
        try refresh(at: now)
        switch state {
        case .consented(let q, _):
            try LedgerRejection.require(!reservationId.isEmpty, .badIdentifier, "the reservation id is empty")
            state = .accepted(q, reservationId: reservationId)
        case .expired:
            throw LedgerRejection(.quoteExpired, "this quote expired; get a new quote")
        default:
            throw LedgerRejection(.consentMissing, "acceptance needs the owner's consent first")
        }
    }

    static func key(_ quote: Quote) -> Ledger.Key {
        Ledger.Key(projectId: quote.projectId, planRevision: quote.planRevision, outputSpecSha256: quote.outputSpecSha256)
    }
}
