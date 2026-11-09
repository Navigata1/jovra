import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// STU-04 acceptance 4 and stories 185, 186, 199: the client's quote and consent state machine.
@Suite("Ledger: QuoteReservation (client quote and consent state)")
struct LedgerQuoteReservationTests {
    /// The stored accepted quote, reopened: expires 2026-10-07T23:15:00Z, cap 4 credits, rules-planned, 7 days.
    static func openQuote() throws -> Quote {
        var quote = try LedgerVectors.record(Quote.self, "quote.accepted.json")
        quote.status = .open
        quote.acceptedAt = .null
        quote.consent = .null
        return quote
    }

    static func at(_ text: String) throws -> StudioTimestamp { try StudioTimestamp(text) }

    static let choice = QuoteReservation.ConsentChoice(uploadSelectedSources: true, consentRecordId: "consent-1",
                                                       consentTextVersion: "studio-cloud-consent@1.0.0")

    static func presented(limit: Int = 12) throws -> QuoteReservation {
        var flow = try QuoteReservation(environment: .test, spendingLimitCredits: limit)
        try flow.request()
        try flow.present(openQuote(), at: at("2026-10-07T22:46:00Z"))
        return flow
    }

    static func code(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let r as LedgerRejection { return r.code.rawValue } catch { return "\(error)" }
    }

    @Test("the happy path: none -> requested -> presented -> consented -> accepted(reservationId)")
    func happyPath() throws {
        var flow = try QuoteReservation(environment: .test, spendingLimitCredits: 12)
        #expect(flow.state == .none)
        try flow.request()
        #expect(flow.state == .requested)
        let quote = try Self.openQuote()
        try flow.present(quote, at: Self.at("2026-10-07T22:46:00Z"))
        #expect(flow.state == .presented(quote))
        #expect(flow.acceptRequest == nil, "nothing is sent before consent")
        try flow.consent(Self.choice, at: Self.at("2026-10-07T22:49:00Z"))
        let request = try #require(flow.acceptRequest)
        #expect(request.quoteId == quote.quoteId)
        #expect(request.idempotencyKey == Ledger.Key(projectId: quote.projectId, planRevision: quote.planRevision,
                                                      outputSpecSha256: quote.outputSpecSha256))
        #expect(request.consent.uploadSelectedSources && !request.consent.modelProvider && request.consent.retentionDays == 7)
        try flow.accepted(reservationId: "res-0002", at: Self.at("2026-10-07T22:50:00Z"))
        #expect(flow.reservationId == "res-0002")
        #expect(Self.code { try flow.request() } == "badQuoteState", "an accepted quote is not re-requested")
    }

    @Test("consent at 23:15:00.500Z on a quote that expires at 23:15:00Z is refused and the quote expires")
    func consentAfterFractionalExpiryIsRefused() throws {
        var flow = try Self.presented()
        // as text, "2026-10-07T23:15:00.500Z" < "2026-10-07T23:15:00Z" ('.' sorts before 'Z'); as an instant it is later
        #expect("2026-10-07T23:15:00.500Z" < "2026-10-07T23:15:00Z")
        #expect(Self.code { try flow.consent(Self.choice, at: Self.at("2026-10-07T23:15:00.500Z")) } == "quoteExpired")
        guard case .expired = flow.state else { Issue.record("state \(flow.state)"); return }
        #expect(flow.acceptRequest == nil)
        #expect(Self.code { try flow.accepted(reservationId: "res-1", at: Self.at("2026-10-07T23:15:01Z")) } == "quoteExpired")
        try flow.request()   // a fresh quote is the only way on (story 185)
        #expect(flow.state == .requested)
    }

    @Test("a consent half a second before expiry is accepted; acceptance after expiry is not")
    func consentBeforeExpiryThenLateAcceptance() throws {
        var flow = try Self.presented()
        try flow.consent(Self.choice, at: Self.at("2026-10-07T23:14:59.500Z"))
        #expect(flow.acceptRequest != nil)
        #expect(Self.code { try flow.accepted(reservationId: "res-1", at: Self.at("2026-10-07T23:15:00Z")) } == "quoteExpired")
        guard case .expired = flow.state else { Issue.record("state \(flow.state)"); return }
        #expect(flow.reservationId == nil)
    }

    @Test("demo mode ends in demoDisabled with the Sample quote and no reservation")
    func demoEndsDisabled() throws {
        let sample = try LedgerVectors.record(Quote.self, "quote.sample-illustrative.json")
        #expect(sample.environment == .demo && sample.sample && sample.illustrative)
        var flow = try QuoteReservation(environment: .demo, spendingLimitCredits: 12)
        try flow.request()
        try flow.present(sample, at: Self.at("2026-10-07T22:46:00Z"))
        #expect(flow.state == .demoDisabled(sample))
        #expect(Self.code { try flow.consent(Self.choice, at: Self.at("2026-10-07T22:47:00Z")) } == "demoNeverReserves")
        #expect(Self.code { try flow.accepted(reservationId: "res-1", at: Self.at("2026-10-07T22:47:00Z")) } == "demoNeverReserves")
        #expect(flow.state == .demoDisabled(sample))
        #expect(flow.reservationId == nil && flow.acceptRequest == nil)
    }

    @Test("a cap above the spending limit waits in aboveCap until the player raises the limit")
    func aboveCapNeverAutoRaised() throws {
        var flow = try Self.presented(limit: 3)
        guard case .aboveCap = flow.state else { Issue.record("state \(flow.state)"); return }
        #expect(flow.spendingLimitCredits == 3, "the limit is never raised by the flow")
        #expect(Self.code { try flow.consent(Self.choice, at: Self.at("2026-10-07T22:47:00Z")) } == "overCap")
        try flow.changeLimit(to: 4, at: Self.at("2026-10-07T22:47:00Z"))
        guard case .presented = flow.state else { Issue.record("state \(flow.state)"); return }
        try flow.consent(Self.choice, at: Self.at("2026-10-07T22:48:00Z"))
        try flow.changeLimit(to: 2, at: Self.at("2026-10-07T22:48:30Z"))
        guard case .aboveCap = flow.state else { Issue.record("lowering the limit must clear consent: \(flow.state)"); return }
        #expect(flow.acceptRequest == nil)
    }

    @Test("consent needs the upload box, and the model-provider box exactly when the cloud plans the story")
    func consentRules() throws {
        var flow = try Self.presented()
        var noUpload = Self.choice
        noUpload.uploadSelectedSources = false
        #expect(Self.code { try flow.consent(noUpload, at: Self.at("2026-10-07T22:47:00Z")) } == "consentMissing")
        var model = Self.choice
        model.modelProvider = true
        #expect(Self.code { try flow.consent(model, at: Self.at("2026-10-07T22:47:00Z")) } == "consentMissing",
                "a rules-planned quote records no model-provider consent")
        var notes = Self.choice
        notes.textClasses = [.ownerNotes]
        #expect(Self.code { try flow.consent(notes, at: Self.at("2026-10-07T22:47:00Z")) } == "badQuote")
        guard case .presented = flow.state else { Issue.record("refused consent must leave the quote presented: \(flow.state)"); return }
    }

    @Test("unavailable, expired-on-arrival, illustrative and live quotes never reach consent")
    func sideStates() throws {
        var offline = try QuoteReservation(environment: .test, spendingLimitCredits: 12)
        try offline.request()
        try offline.fail(.notSignedIn)
        #expect(offline.state == .unavailable(.notSignedIn))
        try offline.request()
        #expect(offline.state == .requested)

        var late = try QuoteReservation(environment: .test, spendingLimitCredits: 12)
        try late.request()
        try late.present(Self.openQuote(), at: Self.at("2026-10-07T23:15:00Z"))
        guard case .expired = late.state else { Issue.record("state \(late.state)"); return }

        var illustrative = try QuoteReservation(environment: .test, spendingLimitCredits: 12)
        try illustrative.request()
        var sample = try Self.openQuote()
        sample.illustrative = true
        #expect(Self.code { try illustrative.present(sample, at: Self.at("2026-10-07T22:46:00Z")) } == "illustrativeQuote")

        var live = try QuoteReservation(environment: .live, spendingLimitCredits: 12)
        try live.request()
        var liveQuote = try Self.openQuote()
        liveQuote.environment = .live
        try live.present(liveQuote, at: Self.at("2026-10-07T22:46:00Z"))
        #expect(live.state == .unavailable(.liveChargingNotActivated))
    }

    @Test("the accept request carries no amount: the client never computes a price the server trusts")
    func acceptRequestCarriesNoPrice() throws {
        var flow = try Self.presented()
        try flow.consent(Self.choice, at: Self.at("2026-10-07T22:49:00Z"))
        let request = try #require(flow.acceptRequest)
        let labels = Mirror(reflecting: request).children.compactMap(\.label)
        #expect(labels.sorted() == ["consent", "idempotencyKey", "quoteId"])
        // a double tap sends the same request (one job, one reservation, story 199)
        #expect(flow.acceptRequest == request)
    }
}
