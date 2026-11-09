import Foundation
import JovraCore
import JovraStudioCore

/// Loads the job and credit contracts from the repository and runs one case of the `job-transitions`, `quote-credits`
/// and `ledger` vectors the way `jobstate.run_vector`, `ledger_cases.check_quote_credit_vector` and
/// `ledger.run_sequence` do. The expected values come from the shared vector files, never from the Swift code.
enum LedgerVectors {
    struct Mismatch: Error, CustomStringConvertible { let description: String }

    static func contract<T: StudioContract>(_ type: T.Type, _ name: String) throws -> T {
        let url = StudioFixtures.repositoryRoot().appendingPathComponent("spec/studio/contracts/\(name)")
        return try StudioContractCodec.decode(type, from: Data(contentsOf: url))
    }

    static let transitions: RenderJobTransitions = try! contract(RenderJobTransitions.self, "render-job-transitions.v1.json")
    static let classes: CreditClasses = try! contract(CreditClasses.self, "credit-classes.v1.json")
    static let machine: RenderJobMachine = try! RenderJobMachine(contract: transitions)

    static func record<T: StudioContract>(_ type: T.Type, _ name: String) throws -> T {
        try StudioContractCodec.decode(type, from: StudioFixtures.data("records/\(name)"))
    }

    // MARK: job-transitions

    static func checkJobTransition(_ item: StudioJSONValue) throws {
        let id = try string(item["id"], "id")
        let from = try require(item["from"], "\(id): from")
        let expect = try require(item["expect"], "\(id): expect")
        do {
            // the target is read first, as jobstate.check_transition checks `to` before the current state
            let to = try RenderJobMachine.state(named: string(item["to"], "to"))
            let state = try RenderJobMachine.state(named: string(from["state"], "state"))
            var resume: RenderJobState?
            if case .string(let name)? = from["resumeStage"] { resume = try RenderJobMachine.state(named: name) }
            let job = RenderJobMachine.Fields(state: state, resumeStage: resume, attempt: int(from["attempt"]) ?? 1,
                                              maxAttempts: int(from["maxAttempts"]) ?? 3)
            let got = try machine.checkTransition(job, to: to, hasReservation: bool(item["hasReservation"]) ?? true,
                                                  verifiedArtifact: bool(item["verifiedArtifact"]) ?? false)
            guard expect["rejectCode"] == nil else {
                throw Mismatch(description: "\(id): transition accepted, expected \(expect["rejectCode"]!)")
            }
            guard case .object(let members) = expect else { throw Mismatch(description: "\(id): expect is not an object") }
            for member in members {
                let actual: StudioJSONValue = switch member.key {
                case "state": .string(got.state.rawValue)
                case "resumeStage": got.resumeStage.map { .string($0.rawValue) } ?? .null
                case "attempt": number(got.attempt)
                default: throw Mismatch(description: "\(id): unknown expectation \(member.key)")
                }
                guard actual == member.value else { throw Mismatch(description: "\(id): \(member.key) \(actual) != \(member.value)") }
            }
        } catch let rejection as LedgerRejection {
            guard case .string(let code)? = expect["rejectCode"], code == rejection.code.rawValue else {
                throw Mismatch(description: "\(id): rejected with \(rejection), expected \(expect)")
            }
        }
    }

    // MARK: quote-credits

    static func checkQuoteCredits(_ item: StudioJSONValue) throws {
        let id = try string(item["id"], "id")
        let got = try CreditBook(classes: classes).quoteCredits(filmClassId: string(item["filmClass"], "filmClass"),
                                                                estimatedMaxCostMicroUsd: Ledger.credits(item["estimatedMaxCostMicroUsd"]))
        guard number(got) == item["expectCredits"] else {
            throw Mismatch(description: "\(id): \(got) credits, expected \(item["expectCredits"].map { "\($0)" } ?? "nil")")
        }
    }

    // MARK: ledger sequences

    /// Runs a ledger vector; returns the final snapshot (balance and every reservation's totals and status).
    @discardableResult
    static func checkLedgerSequence(_ item: StudioJSONValue) throws -> StudioJSONValue {
        let id = try string(item["id"], "id")
        guard let environment = StudioEnvironment(rawValue: try string(item["environment"], "environment")) else {
            throw Mismatch(description: "\(id): unknown environment")
        }
        var ledger = try Ledger(environment: environment, balance: Ledger.credits(item["startBalance"], label: "startBalance"),
                                classes: classes, jobContract: transitions)
        if case .array(let quotes)? = item["quotes"] {
            for quote in quotes { try ledger.addQuote(quoteTerms(quote)) }
        }
        guard case .array(let steps)? = item["steps"] else { throw Mismatch(description: "\(id): no steps") }
        for step in steps {
            let where_ = "\(id) step \(step["step"].map { "\($0)" } ?? "?")"
            let expect = try require(step["expect"], "\(where_): expect")
            let got: [String: StudioJSONValue]
            do {
                got = try apply(step, to: &ledger)
            } catch let rejection as LedgerRejection {
                guard case .string(let code)? = expect["rejectCode"], code == rejection.code.rawValue else {
                    throw Mismatch(description: "\(where_): rejected with \(rejection), expected \(expect)")
                }
                continue
            }
            guard expect["rejectCode"] == nil else { throw Mismatch(description: "\(where_): accepted, expected \(expect)") }
            guard case .object(let members) = expect else { throw Mismatch(description: "\(where_): expect is not an object") }
            for member in members where got[member.key] != member.value {
                throw Mismatch(description: "\(where_): \(member.key) \(got[member.key].map { "\($0)" } ?? "nil") != \(member.value)")
            }
        }
        let snapshot = snapshotJSON(ledger)
        let final = try require(item["final"], "\(id): final")
        guard canonical(snapshot) == canonical(final) else {
            throw Mismatch(description: "\(id): final ledger \(String(decoding: snapshot.serialized(), as: UTF8.self)) != \(String(decoding: final.serialized(), as: UTF8.self))")
        }
        return snapshot
    }

    static func apply(_ step: StudioJSONValue, to ledger: inout Ledger) throws -> [String: StudioJSONValue] {
        let op = try string(step["op"], "op")
        let a = try require(step["args"], "args")
        switch op {
        case "accept":
            try ledger.accept(quoteId: string(a["quoteId"], "quoteId"), at: string(a["at"], "at"), consent: bool(a["consent"]) == true)
            return [:]
        case "reserve":
            let r = try ledger.reserve(quoteId: string(a["quoteId"], "quoteId"), projectId: string(a["projectId"], "projectId"),
                                       planRevision: Ledger.credits(a["planRevision"], label: "planRevision"),
                                       outputSpecSha256: string(a["outputSpecSha256"], "outputSpecSha256"),
                                       credits: Ledger.credits(a["credits"]), at: string(a["at"], "at"),
                                       jobId: a["jobId"].flatMap { if case .string(let s) = $0 { s } else { nil } })
            return ["reservationId": .string(r.reservationId), "replayed": .bool(r.replayed), "balance": number(r.balance)]
        case "attachJob":
            let r = try ledger.attachJob(reservationId: string(a["reservationId"], "reservationId"), jobId: string(a["jobId"], "jobId"))
            return ["reservationId": .string(r.reservationId), "jobId": .string(r.jobId), "replayed": .bool(r.replayed)]
        case "topup":
            let r = try ledger.topup(reservationId: string(a["reservationId"], "reservationId"), quoteId: string(a["quoteId"], "quoteId"),
                                     credits: Ledger.credits(a["credits"]), at: string(a["at"], "at"))
            return ["reservationId": .string(r.reservationId), "reservedCredits": number(r.reservedCredits),
                    "replayed": .bool(r.replayed), "balance": number(r.balance)]
        case "consume":
            let r = try ledger.consume(reservationId: string(a["reservationId"], "reservationId"), jobId: string(a["jobId"], "jobId"),
                                       stage: string(a["stage"], "stage"), attempt: Ledger.credits(a["attempt"], label: "attempt", minimum: 1),
                                       credits: Ledger.credits(a["credits"]))
            return ["consumedCredits": number(r.consumedCredits), "replayed": .bool(r.replayed)]
        case "release":
            guard let outcome = Ledger.Outcome(rawValue: try string(a["outcome"], "outcome")) else {
                throw Mismatch(description: "unknown release outcome")
            }
            let r = try ledger.release(reservationId: string(a["reservationId"], "reservationId"), outcome: outcome)
            return ["releasedCredits": number(r.releasedCredits), "replayed": .bool(r.replayed), "balance": number(r.balance)]
        default:
            throw Mismatch(description: "unknown op \(op)")
        }
    }

    static func quoteTerms(_ q: StudioJSONValue) throws -> Ledger.QuoteTerms {
        let estimate = try require(q["estimate"], "estimate")
        guard let status = QuoteStatus(rawValue: try string(q["status"], "status")) else { throw Mismatch(description: "quote status") }
        return Ledger.QuoteTerms(
            quoteId: try string(q["quoteId"], "quoteId"), projectId: try string(q["projectId"], "projectId"),
            planRevision: try Ledger.credits(q["planRevision"], label: "planRevision"),
            outputSpecSha256: try string(q["outputSpecSha256"], "outputSpecSha256"), filmClassId: try string(q["filmClass"], "filmClass"),
            estimatedMaxCostMicroUsd: try Ledger.credits(q["estimatedMaxCostMicroUsd"]),
            estimateMinCredits: try Ledger.credits(estimate["minCredits"]), estimateMaxCredits: try Ledger.credits(estimate["maxCredits"]),
            capCredits: try Ledger.credits(q["capCredits"]), expiresAt: try string(q["expiresAt"], "expiresAt"), status: status,
            illustrative: bool(q["illustrative"]) == true)
    }

    static func snapshotJSON(_ ledger: Ledger) -> StudioJSONValue {
        let reservations = ledger.reservations.keys.sorted().map { rid -> StudioJSONMember in
            let r = ledger.reservations[rid]!
            return StudioJSONMember(key: rid, value: .object([
                StudioJSONMember(key: "reservedCredits", value: number(r.reservedCredits)),
                StudioJSONMember(key: "consumedCredits", value: number(r.consumedCredits)),
                StudioJSONMember(key: "releasedCredits", value: number(r.releasedCredits)),
                StudioJSONMember(key: "status", value: .string(r.status.rawValue)),
            ]))
        }
        return .object([StudioJSONMember(key: "balance", value: number(ledger.balance)),
                        StudioJSONMember(key: "reservations", value: .object(reservations))])
    }

    // MARK: JSON helpers

    static func number(_ value: Int) -> StudioJSONValue {
        // a number token through the strict parser, so it compares equal to one read from a vector file
        try! StudioJSONParser.parse(Data(String(value).utf8))
    }

    static func canonical(_ value: StudioJSONValue) -> Data {
        (try? CanonicalJSON.canonicalize(value.serialized())) ?? value.serialized()
    }

    static func string(_ value: StudioJSONValue?, _ label: String) throws -> String {
        guard case .string(let s)? = value else { throw Mismatch(description: "\(label) is not a string") }
        return s
    }

    static func int(_ value: StudioJSONValue?) -> Int? {
        if case .number(let n)? = value, let v = n.int64 { Int(v) } else { nil }
    }

    static func bool(_ value: StudioJSONValue?) -> Bool? {
        if case .bool(let b)? = value { b } else { nil }
    }

    static func require(_ value: StudioJSONValue?, _ label: String) throws -> StudioJSONValue {
        guard let value else { throw Mismatch(description: "\(label) missing") }
        return value
    }
}
