import Foundation
import Testing
import JovraStudioCore

/// STU-04 acceptance 1: every job-transition, ledger and quote-credit vector passes with the reference's outputs.
@Suite("Ledger: vector parity with jobstate.py and ledger.py")
struct LedgerParityTests {
    static func cases(_ file: String) throws -> [StudioJSONValue] {
        let value = try StudioJSONParser.parse(StudioFixtures.data("vectors/\(file)"))
        guard case .array(let cases)? = value["cases"] else { throw LedgerVectors.Mismatch(description: "\(file) has no cases") }
        return cases
    }

    @Test("all 32 job-transition vectors give the reference's state, resume stage, attempt or code")
    func jobTransitions() throws {
        let cases = try Self.cases("job-transitions.json")
        #expect(cases.count == 32)
        for item in cases { try LedgerVectors.checkJobTransition(item) }
    }

    @Test("all 21 ledger sequences give the reference's step results and final ledger")
    func ledgerSequences() throws {
        let cases = try Self.cases("ledger.json")
        #expect(cases.count == 21)
        for item in cases { try LedgerVectors.checkLedgerSequence(item) }
    }

    @Test("all 8 quote-credit vectors give the reference's cap")
    func quoteCredits() throws {
        let cases = try Self.cases("quote-credits.json")
        #expect(cases.count == 8)
        for item in cases { try LedgerVectors.checkQuoteCredits(item) }
    }

    /// The checkers can fail: a vector whose stored expectation is changed is reported, not silently passed.
    @Test("a vector with a wrong expectation is reported as a mismatch")
    func checkersDetectWrongExpectations() throws {
        let job = try Self.cases("job-transitions.json").first { $0["id"] == .string("retry-counts-attempt") }!
        let wrongAttempt = try StudioJSONPatch.apply(StudioJSONParser.parse(Data(#"[{"op":"replace","path":"/expect/attempt","value":1}]"#.utf8)), to: job)
        #expect(throws: LedgerVectors.Mismatch.self) { try LedgerVectors.checkJobTransition(wrongAttempt) }

        let credits = try Self.cases("quote-credits.json").first { $0["id"] == .string("story-4-6-one-over") }!
        let wrongCap = try StudioJSONPatch.apply(StudioJSONParser.parse(Data(#"[{"op":"replace","path":"/expectCredits","value":6}]"#.utf8)), to: credits)
        #expect(throws: LedgerVectors.Mismatch.self) { try LedgerVectors.checkQuoteCredits(wrongCap) }

        let sequence = try Self.cases("ledger.json").first { $0["id"] == .string("happy-path-idempotent") }!
        let wrongBalance = try StudioJSONPatch.apply(StudioJSONParser.parse(Data(#"[{"op":"replace","path":"/final/balance","value":6}]"#.utf8)), to: sequence)
        #expect(throws: LedgerVectors.Mismatch.self) { try LedgerVectors.checkLedgerSequence(wrongBalance) }
    }

    @Test("the jobstate and ledger pages say swift: consumed, and the manifest fails without LedgerConsumer")
    func modulePagesAreConsumed() throws {
        let modules = StudioFixtures.repositoryRoot().appendingPathComponent("spec/studio/modules")
        let pages = try StudioFixtureManifest.pages(in: modules).filter { ["jobstate", "ledger"].contains($0.module) }
        #expect(pages.map(\.swift) == ["consumed", "consumed"])
        #expect(try ContractsFixtureManifestTests.check(ContractsFixtureManifestTests.root).failures.isEmpty)
        var consumed = StudioConsumption.discovered.kinds
        for kind in LedgerConsumer().vectorCheckers.keys { consumed.remove(kind) }
        let report = try ContractsFixtureManifestTests.check(ContractsFixtureManifestTests.root, consumed: consumed)
        #expect(report.failures.sorted() == [
            "page jobstate says swift: consumed, but kind job-transitions has no registered Swift consumer",
            "page ledger says swift: consumed, but kind ledger has no registered Swift consumer",
            "page ledger says swift: consumed, but kind quote-credits has no registered Swift consumer",
        ])
    }

    @Test("the bundled contracts are the repository's render-job-transitions and credit-classes files, byte for byte")
    func bundledContractsMatchTheSpec() throws {
        for (name, text) in LedgerContractSource.texts {
            let url = StudioFixtures.repositoryRoot().appendingPathComponent("spec/studio/contracts/\(name)")
            let file = try String(contentsOf: url, encoding: .utf8)
            #expect(text == file.trimmingCharacters(in: .newlines), "\(name) differs from spec/studio/contracts; regenerate LedgerContracts.swift")
        }
        #expect(try RenderJobTransitions.bundled() == LedgerVectors.transitions)
        #expect(try CreditClasses.bundled() == LedgerVectors.classes)
    }
}
