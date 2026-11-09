import Foundation
import Testing
import JovraStudioCore

/// STU-04 acceptance 1 and 2: the render-job, quote and usage-reservation record rules refuse every reference-layer
/// invalid case with the reference's code, accept the stored records, and keep the finding 5 and finding 9 fixes.
@Suite("Ledger: record rules and the reference's invalid cases")
struct LedgerRecordRuleTests {
    struct InvalidCase {
        let label: String
        let version: String
        let layer: String
        let code: String?
        let document: Data
    }

    static let versions: Set<String> = ["jovra.render-job/1", "jovra.quote/1", "jovra.usage-reservation/1"]
    static var chargedStages: Set<String> { Set(LedgerVectors.transitions.budgetCheckedBefore.map(\.rawValue)) }

    static func invalidCases() throws -> [InvalidCase] {
        let folder = try StudioFixtures.url("invalid")
        var out: [InvalidCase] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ $0.hasSuffix(".json") }).sorted() {
            let file = try StudioJSONParser.parse(Data(contentsOf: folder.appendingPathComponent(name)))
            guard case .string(let base)? = file["base"], case .array(let cases)? = file["cases"] else { continue }
            let record = try StudioJSONParser.parse(StudioFixtures.data(base))
            guard case .string(let version)? = record["schemaVersion"], versions.contains(version) else { continue }
            for item in cases {
                guard case .string(let id)? = item["id"], case .string(let layer)? = item["expect"]?["layer"], let patch = item["patch"] else {
                    throw LedgerVectors.Mismatch(description: "\(name): malformed case")
                }
                let code: String? = if case .string(let c)? = item["expect"]?["code"] { c } else { nil }
                out.append(InvalidCase(label: "\(name)#\(id)", version: version, layer: layer, code: code,
                                       document: try StudioJSONPatch.apply(patch, to: record).serialized()))
            }
        }
        return out
    }

    static func artifacts() throws -> [DeliveredArtifact] {
        let folder = try StudioFixtures.url("records")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("delivered-artifact.") }.sorted()
            .map { try LedgerVectors.record(DeliveredArtifact.self, $0) }
    }

    /// The reference rule of one record (jobstate_cases.check_render_job, ledger_cases.check_quote / check_reservation).
    static func checkRecord(version: String, _ data: Data) throws {
        switch version {
        case "jovra.render-job/1":
            let job = try StudioContractCodec.decode(RenderJob.self, from: data)
            try LedgerVectors.machine.replay(job, verifiedArtifact: RenderJobMachine.verifiedArtifact(for: job, artifacts: artifacts()))
        case "jovra.quote/1":
            try CreditBook(classes: LedgerVectors.classes).checkQuote(StudioContractCodec.decode(Quote.self, from: data))
        case "jovra.usage-reservation/1":
            try ReservationRecordRules.check(StudioContractCodec.decode(UsageReservation.self, from: data), chargedStages: chargedStages)
        default:
            throw LedgerVectors.Mismatch(description: "no rule for \(version)")
        }
    }

    @Test("every stored render-job, quote and usage-reservation record passes its rules")
    func storedRecordsPass() throws {
        let folder = try StudioFixtures.url("records")
        var checked: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ $0.hasSuffix(".json") }).sorted() {
            let data = try StudioFixtures.data("records/\(name)")
            guard case .string(let version)? = try StudioJSONParser.parse(data)["schemaVersion"], Self.versions.contains(version) else { continue }
            try Self.checkRecord(version: version, data)
            checked.append(name)
        }
        print("Ledger record rules accept: \(checked)")
        #expect(checked.count == 7)
    }

    @Test("every reference-layer invalid case fails with the reference's code; schema-layer cases never decode")
    func invalidCasesFailWithTheSameCodes() throws {
        var matched: [String: Int] = [:]
        for item in try Self.invalidCases() {
            if item.layer == "schema" {
                #expect(throws: StudioContractError.self, "\(item.label)") { try Self.checkRecord(version: item.version, item.document) }
                matched["schema", default: 0] += 1
                continue
            }
            let expected = try #require(item.code, "\(item.label) has no code")
            do {
                try Self.checkRecord(version: item.version, item.document)
                Issue.record("\(item.label): accepted, expected \(expected)")
            } catch let rejection as LedgerRejection {
                #expect(rejection.code.rawValue == expected, "\(item.label): \(rejection)")
                matched[item.version, default: 0] += 1
            }
        }
        print("Ledger invalid cases refused with the reference's code: \(matched.sorted { $0.key < $1.key })")
        #expect(matched["jovra.render-job/1"] == 7)
        #expect(matched["jovra.quote/1"] == 11)
        #expect(matched["jovra.usage-reservation/1"] == 15)
    }

    // MARK: finding 5: a retried reserve must replay, never write a second hold under another key

    @Test("finding 5: a second reserve entry 'reserve:<k>:retry' summed into the hold is badEntryKey")
    func finding5SecondReserveKeyIsRejected() throws {
        var record = try LedgerVectors.record(UsageReservation.self, "usage-reservation.settled.json")
        let own = "reserve:\(record.idempotencyKey.projectId):\(record.idempotencyKey.planRevision):\(record.idempotencyKey.outputSpecSha256)"
        record.entries[0].credits = 2
        record.entries.insert(UsageReservationEntry(entryId: "e-1b", kind: .reserve, credits: 2, key: own + ":retry",
                                                    at: "2026-10-07T22:50:06Z"), at: 1)
        // the totals still add up, so only the key rule can catch the doubled hold
        #expect(record.entries.filter { $0.kind == .reserve }.map(\.credits).reduce(0, +) == record.reservedCredits)
        #expect(throws: LedgerRejection(.badEntryKey, "")) {
            try Self.rethrowingCode { try ReservationRecordRules.check(record, chargedStages: Self.chargedStages) }
        }
    }

    // MARK: finding 9: redelivered reserve and top-up after a top-up replay

    @Test("finding 9: a redelivered reserve and a redelivered top-up after a top-up replay with no charge")
    func finding9RedeliveriesAfterTopupReplay() throws {
        var ledger = try Ledger(environment: .test, balance: 10, classes: LedgerVectors.classes, jobContract: LedgerVectors.transitions)
        let hash = String(repeating: "a", count: 64)
        for (id, cap) in [("q-1", 4), ("q-2", 5)] {
            try ledger.addQuote(.init(quoteId: id, projectId: "p1", planRevision: 1, outputSpecSha256: hash, filmClassId: "story-2-3",
                                      estimatedMaxCostMicroUsd: cap == 4 ? 1_290_000 : 3_900_000, estimateMinCredits: 2,
                                      estimateMaxCredits: 4, capCredits: cap, expiresAt: "2026-10-07T23:15:00Z"))
        }
        try ledger.accept(quoteId: "q-1", at: "2026-10-07T22:50:00Z", consent: true)
        _ = try ledger.reserve(quoteId: "q-1", projectId: "p1", planRevision: 1, outputSpecSha256: hash, credits: 2,
                               at: "2026-10-07T22:51:00Z", jobId: "job-1")
        _ = try ledger.consume(reservationId: "res-0001", jobId: "job-1", stage: "normalizing", attempt: 1, credits: 2)
        try ledger.accept(quoteId: "q-2", at: "2026-10-07T22:58:00Z", consent: true)
        let topup = try ledger.topup(reservationId: "res-0001", quoteId: "q-2", credits: 5, at: "2026-10-07T22:58:30Z")
        #expect(topup == .init(reservationId: "res-0001", reservedCredits: 5, replayed: false, balance: 5))

        let reserveAgain = try ledger.reserve(quoteId: "q-1", projectId: "p1", planRevision: 1, outputSpecSha256: hash, credits: 2,
                                              at: "2026-10-07T22:59:00Z", jobId: "job-1")
        #expect(reserveAgain == .init(reservationId: "res-0001", replayed: true, balance: 5))
        let topupAgain = try ledger.topup(reservationId: "res-0001", quoteId: "q-2", credits: 5, at: "2026-10-07T22:59:10Z")
        #expect(topupAgain == .init(reservationId: "res-0001", reservedCredits: 5, replayed: true, balance: 5))
        #expect(ledger.balance == 5 && ledger.reservations["res-0001"]?.reservedCredits == 5)
        // the replay remembers exactly what was applied: the top-up quote under reserve() is still a conflict
        #expect(throws: LedgerRejection(.idempotencyConflict, "")) {
            try Self.rethrowingCode {
                _ = try ledger.reserve(quoteId: "q-2", projectId: "p1", planRevision: 1, outputSpecSha256: hash, credits: 5,
                                       at: "2026-10-07T22:59:20Z", jobId: "job-1")
            }
        }
    }

    @Test("a top-up keyed by the initial quote is refused in the ledger and in a stored record")
    func topupNeverByInitialQuote() throws {
        var record = try LedgerVectors.record(UsageReservation.self, "usage-reservation.settled.json")
        let own = "reserve:\(record.idempotencyKey.projectId):\(record.idempotencyKey.planRevision):\(record.idempotencyKey.outputSpecSha256)"
        record.entries[0].credits = 2
        record.entries.insert(UsageReservationEntry(entryId: "e-1b", kind: .reserve, credits: 2, key: own + ":topup:" + record.initialQuoteId,
                                                    at: "2026-10-07T22:50:06Z"), at: 1)
        #expect(throws: LedgerRejection(.badEntryKey, "")) {
            try Self.rethrowingCode { try ReservationRecordRules.check(record, chargedStages: Self.chargedStages) }
        }
    }

    /// Rethrows a rejection with an empty message, so `#expect(throws:)` compares the code only.
    static func rethrowingCode(_ body: () throws -> Void) throws {
        do { try body() } catch let rejection as LedgerRejection { throw LedgerRejection(rejection.code, "") }
    }
}
