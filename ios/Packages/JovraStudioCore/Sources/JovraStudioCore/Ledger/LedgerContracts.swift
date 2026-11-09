import Foundation

// The two contract data files the job machine and the ledger run on, byte for byte (spec/studio/contracts), so the app
// never reads spec/ at runtime. LedgerContractsTests fails when either differs from the repository's copy.
public enum LedgerContractSource {
    static let renderJobTransitions = #"""
{
  "schemaVersion": "jovra.render-job-transitions/1",
  "status": "proposed contract; no live job service exists (backend brief 'Job state and money', backend-architecture research section 8)",
  "states": [
    "draft", "quoted", "consented", "upload_pending", "uploading", "queued", "normalizing", "syncing", "analyzing",
    "planning", "preview_rendering", "awaiting_review", "final_rendering", "verifying", "ready",
    "paused", "canceled", "failed_retryable", "failed_terminal", "quote_expired", "budget_exceeded", "deleted"
  ],
  "initial": "draft",
  "terminal": ["ready", "canceled", "failed_terminal", "deleted"],
  "resumable": ["paused", "failed_retryable", "quote_expired", "budget_exceeded"],
  "reservationRequiredFrom": ["upload_pending", "uploading", "queued", "normalizing", "syncing", "analyzing", "planning",
                              "preview_rendering", "awaiting_review", "final_rendering", "verifying", "ready"],
  "budgetCheckedBefore": ["normalizing", "syncing", "analyzing", "planning", "preview_rendering", "final_rendering", "verifying"],
  "forward": {
    "draft": ["quoted"],
    "quoted": ["consented", "quote_expired"],
    "consented": ["upload_pending"],
    "upload_pending": ["uploading", "queued"],
    "uploading": ["queued"],
    "queued": ["normalizing"],
    "normalizing": ["syncing", "analyzing", "planning"],
    "syncing": ["analyzing", "planning"],
    "analyzing": ["planning"],
    "planning": ["preview_rendering"],
    "preview_rendering": ["awaiting_review", "final_rendering"],
    "awaiting_review": ["final_rendering"],
    "final_rendering": ["verifying"],
    "verifying": ["ready"],
    "quote_expired": ["quoted"],
    "budget_exceeded": ["quoted"],
    "failed_retryable": ["failed_terminal"]
  },
  "pausableFrom": ["upload_pending", "uploading", "queued", "normalizing", "syncing", "analyzing", "planning",
                   "preview_rendering", "awaiting_review", "final_rendering", "verifying"],
  "retryableFrom": ["uploading", "queued", "normalizing", "syncing", "analyzing", "planning", "preview_rendering",
                    "final_rendering", "verifying"],
  "terminalFailureFrom": ["uploading", "queued", "normalizing", "syncing", "analyzing", "planning", "preview_rendering",
                          "final_rendering", "verifying", "failed_retryable"],
  "budgetExceededFrom": ["normalizing", "syncing", "analyzing", "planning", "preview_rendering", "final_rendering", "verifying"],
  "resumeTo": "the stage recorded when the job entered paused or failed_retryable (resumeStage); a retry also needs attempt < maxAttempts. A stored resumeStage must be in pausableFrom (paused), retryableFrom (failed_retryable) or budgetExceededFrom (budget_exceeded, informational only: it resumes through a new quote), and is null in every other state; it is never ready, deleted or a terminal state, so a resume can never skip verifying",
  "cancelFrom": "every state that is not terminal",
  "deleteFrom": "every state except deleted",
  "readyRequires": "at least one delivered artifact whose verification passed (full decode, frame count, audio, provenance)"
}
"""#

    static let creditClasses = #"""
{
  "schemaVersion": "jovra.credit-classes/1",
  "status": "proposal, not a price. Source: docs/research/studio/pricing-and-premium.md section 5.1 (INFERRED margins). No charge exists: ADR-0013 holds until a new pricing ADR, measured benchmarks (research section 8) and a margin model.",
  "creditCostBudgetMicroUsd": 800000,
  "quoteRule": "capCredits = max(classMinimum, ceil(estimatedMaxCostMicroUsd / creditCostBudgetMicroUsd))",
  "quoteMaxLifetimeSeconds": 1800,
  "classes": [
    {"id": "story-1", "label": "Story film, 1 angle", "minimumCredits": 2},
    {"id": "story-2-3", "label": "Story film, 2-3 angles", "minimumCredits": 4},
    {"id": "story-4-6", "label": "Story film, 4-6 angles", "minimumCredits": 6},
    {"id": "broadcast-1", "label": "Match Broadcast, 1 angle", "minimumCredits": 3},
    {"id": "broadcast-2-3", "label": "Match Broadcast, 2-3 angles", "minimumCredits": 5},
    {"id": "broadcast-4-6", "label": "Match Broadcast, 4-6 angles", "minimumCredits": 8},
    {"id": "revision", "label": "New revision of a delivered film", "minimumCredits": 1}
  ]
}
"""#
}

extension RenderJobTransitions {
    /// The bundled `render-job-transitions.v1.json`, strictly decoded.
    public static func bundled() throws -> RenderJobTransitions {
        try StudioContractCodec.decode(RenderJobTransitions.self, from: Data(LedgerContractSource.renderJobTransitions.utf8))
    }
}

extension CreditClasses {
    /// The bundled `credit-classes.v1.json`, strictly decoded.
    public static func bundled() throws -> CreditClasses {
        try StudioContractCodec.decode(CreditClasses.self, from: Data(LedgerContractSource.creditClasses.utf8))
    }
}

extension LedgerContractSource {
    /// The bundled texts, for the drift test.
    public static var texts: [String: String] {
        ["render-job-transitions.v1.json": renderJobTransitions, "credit-classes.v1.json": creditClasses]
    }
}
