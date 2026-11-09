import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// SD11 acceptance 3 (money): every demo quote is flagged Sample with charging disabled, and accept() in demo returns
/// demoDisabled with no reservation (stories 17, 189).
@Suite("Cloud: demo quotes are Sample and never reserve")
struct CloudDemoMoneyTests {
    static let request = CloudQuoteRequest(projectId: "sample-court-day", planRevision: 1)

    @Test("the demo quote is the illustrative Sample quote: Sample quote $4 – $8, spending limit $12, charging off")
    func sampleQuote() async throws {
        let quote = try await DemoCloudClient().quote(Self.request)
        #expect(quote.quote == (try CloudFixtures.sampleQuote()))
        #expect(quote.isSample && quote.quote.sample && quote.quote.illustrative && quote.quote.environment == .demo)
        #expect(!quote.chargingEnabled)
        #expect(quote.title == "Sample quote")
        #expect(quote.rangeText == "$4 – $8")
        #expect(quote.limitText == "$12")
        #expect(quote.accessibilityLabel == "Sample quote. Estimated processing 4 to 8 dollars. Spending limit 12 dollars.")
        #expect(CloudCopy.demoDoesNotUploadOrCharge == "Demo mode does not upload or charge.")
    }

    @Test("in every scenario a quote, when there is one, is Sample with charging disabled",
          arguments: DemoCloudScenario.allCases)
    func everyQuoteIsSample(scenario: DemoCloudScenario) async throws {
        let client = try DemoCloudClient(scenario: scenario)
        do {
            let quote = try await client.quote(Self.request)
            #expect(quote.isSample && quote.title == "Sample quote" && !quote.chargingEnabled)
        } catch {
            #expect(scenario == .notSignedIn && error == .notSignedIn)
        }
    }

    @Test("accept() in demo returns demoDisabled with no reservation, whatever the scenario, key or cap",
          arguments: DemoCloudScenario.allCases)
    func acceptIsDemoDisabled(scenario: DemoCloudScenario) async throws {
        let client = try DemoCloudClient(scenario: scenario)
        let quote = try CloudFixtures.sampleQuote()
        for cap in [0, 4, 1_000] {
            let result = try await client.accept(quote, consent: CloudFixtures.consent, capCredits: cap,
                                                 idempotencyKey: Ledger.Key(projectId: quote.projectId, planRevision: 1,
                                                                            outputSpecSha256: quote.outputSpecSha256))
            #expect(result == .demoDisabled(sampleJob: client.sampleJobId))
            #expect(result.reservationId == nil)
        }
        // nothing the demo shows carries a reservation it made: its Sample jobs are the committed records
        for snapshot in await CloudDemoTranscriptTests.all(client) {
            #expect(snapshot.job.reservationId.value == nil || ["res-0001", "res-0002"].contains(snapshot.job.reservationId.value!))
        }
    }

    @Test("the quote state machine that accept() runs keeps a demo quote in demoDisabled and refuses consent")
    func quoteMachineRefusesDemo() throws {
        var state = try QuoteReservation(environment: .demo, spendingLimitCredits: 4)
        try state.request()
        let quote = try CloudFixtures.sampleQuote()
        try state.present(quote, at: StudioTimestamp(quote.createdAt))
        #expect(state.state == .demoDisabled(quote) && state.reservationId == nil && state.acceptRequest == nil)
        #expect(throws: LedgerRejection.self) {
            try state.consent(.init(uploadSelectedSources: true, consentRecordId: "c", consentTextVersion: "v"),
                              at: StudioTimestamp(quote.createdAt))
        }
    }

    @Test("upload, share and account actions are refused in demo with the demo message")
    func demoRefusesSideEffects() async throws {
        let client = try DemoCloudClient()
        let session = UploadSession(uploadId: "u", sourceId: "camera-1", byteCount: 1, confirmedParts: [], completed: false, sample: true)
        await #expect(throws: CloudError.demoDisabled) { _ = try await client.openUpload(sourceId: "camera-1") }
        await #expect(throws: CloudError.demoDisabled) { _ = try await client.uploadPart(session, partNumber: 1) }
        await #expect(throws: CloudError.demoDisabled) { _ = try await client.completeUpload(session) }
        for action in ShareLinkAction.allCases {
            await #expect(throws: CloudError.demoDisabled) { _ = try await client.shareLink(action, artifactId: "film-court-memories") }
        }
        await #expect(throws: CloudError.demoDisabled) { _ = try await client.deleteAccount() }
        #expect(try await client.exportMyData().status == .nothingInCloud)
        #expect(CloudError.demoDisabled.message == "Demo mode does not upload or charge.")
    }

    @Test("the demo identity is the demo profile: no account reference and no credential")
    func noToken() async throws {
        #expect(try await DemoCloudClient().identity() == .demoProfile)
        let client = try DemoCloudClient()
        #expect(await client.mode() == .demo)
    }
}
