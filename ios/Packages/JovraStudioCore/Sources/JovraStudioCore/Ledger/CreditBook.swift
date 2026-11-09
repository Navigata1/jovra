import Foundation
import JovraCore

/// Studio Credits as `spec/studio/contracts/credit-classes.v1.json` defines them: the one unit of quote, cap,
/// reservation and receipt. The amounts are a labelled proposal, not a price (ADR-0013).
///
/// The cap rule is `capCredits = max(classMinimum, ceil(estimatedMaxCostMicroUsd / creditCostBudgetMicroUsd))`
/// (`ledger.quote_credits`). The client uses it only to check a stored or received quote against the contract; the
/// server computes the quote and a client-computed price is never trusted.
public struct CreditBook: Sendable {
    public let classes: CreditClasses

    public init(classes: CreditClasses) {
        self.classes = classes
    }

    /// The cap of a quote of `filmClassId` whose worst case costs `estimatedMaxCostMicroUsd`, in exact integers.
    public func quoteCredits(filmClassId: String, estimatedMaxCostMicroUsd: Int) throws(LedgerRejection) -> Int {
        guard let filmClass = classes.classes.first(where: { $0.id.rawValue == filmClassId }) else {
            throw LedgerRejection(.unknownFilmClass, "unknown film class \(filmClassId.debugDescription)")
        }
        try LedgerRejection.require(estimatedMaxCostMicroUsd >= 0, .badEstimate,
                                    "estimate must be a non-negative integer of micro-USD")
        let budget = classes.creditCostBudgetMicroUsd
        let ceiling = estimatedMaxCostMicroUsd / budget + (estimatedMaxCostMicroUsd % budget == 0 ? 0 : 1)
        return max(filmClass.minimumCredits, ceiling)
    }

    /// The record rules of a stored `jovra.quote/1` beyond its schema (`records.check_quote`): a lifetime of at most
    /// `quoteMaxLifetimeSeconds`, the contract cap, `min <= max <= cap`, illustrative quotes Sample and never accepted
    /// or consented, money shown only on an illustrative quote, acceptance after consent and before expiry (parsed
    /// times), demo and test quotes Sample, storage priced for the chosen retention, and consent that matches the
    /// planner choice and retention.
    public func checkQuote(_ quote: Quote) throws(LedgerRejection) {
        typealias R = LedgerRejection
        let created = try StudioTimestamp(quote.createdAt), expires = try StudioTimestamp(quote.expiresAt)
        try R.require(created.milliseconds(until: expires) <= classes.quoteMaxLifetimeSeconds * 1000, .quoteLifetime,
                      "a quote expires within \(classes.quoteMaxLifetimeSeconds / 60) minutes")
        try R.require(created < expires, .quoteLifetime, "expiry after creation")
        let cap = try quoteCredits(filmClassId: quote.filmClass.rawValue, estimatedMaxCostMicroUsd: quote.estimatedMaxCostMicroUsd)
        try R.require(quote.capCredits == cap, .quoteCapMismatch, "cap must be \(cap): the class minimum and the cost estimate")
        try R.require(quote.estimate.minCredits <= quote.estimate.maxCredits && quote.estimate.maxCredits <= quote.capCredits,
                      .badQuote, "estimate min <= max <= cap")
        if quote.illustrative {
            try R.require(quote.sample && quote.status != .accepted && quote.consent.value == nil, .illustrativeQuote,
                          "an illustrative quote is Sample, never accepted and never consented")
        }
        if let amounts = quote.displayAmounts.value {
            try R.require(quote.illustrative, .illustrativeQuote, "money amounts are shown only as illustrative Sample UX")
            try R.require(amounts.minMinor <= amounts.maxMinor && amounts.maxMinor <= amounts.capMinor, .badQuote,
                          "display min <= max <= cap")
        }
        if quote.status == .accepted {
            guard let acceptedText = quote.acceptedAt.value, let consent = quote.consent.value else {
                throw R(.consentMissing, "an accepted quote records the owner's upload consent")
            }
            let accepted = try StudioTimestamp(acceptedText), consented = try StudioTimestamp(consent.at)
            try R.require(accepted < expires && consented <= accepted, .quoteExpired,
                          "a quote is accepted, after consent, before it expires; never auto-accepted later")
        } else {
            try R.require(quote.acceptedAt.value == nil, .badQuote, "only accepted quotes have acceptedAt")
        }
        if quote.environment != .live {
            try R.require(quote.sample, .sampleRequired, "demo and test quotes are Sample")
        }
        try R.require(quote.lineItems.storageDays == quote.retentionDays, .badQuote,
                      "the storage line item is priced for the chosen retention")
        if quote.plannerChoice == .heuristic {
            try R.require(quote.lineItems.plannerTokensEstimate == 0, .plannerMismatch,
                          "a rules-planned quote estimates no model tokens")
        }
        if let consent = quote.consent.value {
            try Self.checkConsent(consent, retentionDays: quote.retentionDays, plannerChoice: quote.plannerChoice)
        }
    }

    /// A consent matches its quote: the same retention, the model-provider consent exactly when planning uses a model,
    /// and note text classes only together with model planning.
    static func checkConsent(_ consent: QuoteConsent, retentionDays: Int,
                             plannerChoice: QuotePlannerChoice) throws(LedgerRejection) {
        try LedgerRejection.require(consent.retentionDays == retentionDays, .badQuote,
                                    "the consent confirms the quote's retention")
        try LedgerRejection.require(consent.modelProvider == (plannerChoice == .model), .consentMissing,
                                    "model planning needs the explicit model-provider consent, and a rules-planned quote records none")
        try LedgerRejection.require(consent.modelProvider || consent.textClasses.isEmpty, .badQuote,
                                    "note text classes are consented only together with model planning")
    }
}
