import Foundation
import JovraStudioCore

/// STU-04 (S12): the Swift job machine, quote credits and reservation ledger replay the shared `job-transitions`,
/// `quote-credits` and `ledger` vectors with the reference's outputs (`spec/reference/studio/jobstate.py`,
/// `ledger.py`). The record kinds on the jobstate and ledger pages are decoded by ContractsConsumer (S10).
struct LedgerConsumer: StudioFixtureConsumer {
    var vectorCheckers: [String: @Sendable (StudioJSONValue) throws -> Void] {
        [
            "job-transitions": { try LedgerVectors.checkJobTransition($0) },
            "quote-credits": { try LedgerVectors.checkQuoteCredits($0) },
            "ledger": { try LedgerVectors.checkLedgerSequence($0) },
        ]
    }
}
