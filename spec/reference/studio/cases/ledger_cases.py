"""Ledger and quote-credit vectors, quote and usage-reservation invalid cases and checkers. Module page:
spec/studio/modules/ledger.md.
"""

from __future__ import annotations

from studio import ledger, records
from studio.core import output_spec_sha256
from studio.cases.patches import add, bad, invalid_docs, rep, rm


# ----- ledger and quote credits -------------------------------------------------------------------

H = "a" * 64
H2 = "b" * 64


def _quote(qid, rev=1, expires="2026-10-07T23:15:00Z", illustrative=False, est=1_290_000, cap=4, key=H):
    return {"quoteId": qid, "projectId": "p1", "planRevision": rev, "outputSpecSha256": key, "filmClass": "story-2-3",
            "estimatedMaxCostMicroUsd": est, "estimate": {"minCredits": 2, "maxCredits": 4}, "capCredits": cap,
            "expiresAt": expires, "status": "open", "illustrative": illustrative}


def _step(n, op, args, expect):
    return {"step": n, "op": op, "args": args, "expect": expect}


def _accept(n, q="q-1", at="2026-10-07T22:50:00Z", consent=True, expect=None):
    return _step(n, "accept", {"quoteId": q, "at": at, "consent": consent}, expect or {})


def _reserve(n, credits, expect, q="q-1", rev=1, key=H, at="2026-10-07T22:51:00Z", job="job-1"):
    return _step(n, "reserve", {"quoteId": q, "projectId": "p1", "planRevision": rev, "outputSpecSha256": key,
                                "credits": credits, "at": at, "jobId": job}, expect)


def _consume(n, stage, credits, expect, attempt=1, rid="res-0001", job="job-1"):
    return _step(n, "consume", {"reservationId": rid, "jobId": job, "stage": stage, "attempt": attempt,
                                "credits": credits}, expect)


def _release(n, outcome, expect, rid="res-0001"):
    return _step(n, "release", {"reservationId": rid, "outcome": outcome}, expect)


def _res(reserved, consumed, released, status):
    return {"reservedCredits": reserved, "consumedCredits": consumed, "releasedCredits": released, "status": status}


def ledger_vectors():
    ok4 = {"reservationId": "res-0001", "replayed": False, "balance": 6}
    cases = [
        {"id": "happy-path-idempotent", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, ok4), _reserve(3, 4, dict(ok4, replayed=True)),
            _consume(4, "normalizing", 1, {"consumedCredits": 1, "replayed": False}),
            _consume(5, "normalizing", 1, {"consumedCredits": 1, "replayed": True}),
            _consume(6, "final_rendering", 2, {"consumedCredits": 3, "replayed": False}),
            _release(7, "ready", {"releasedCredits": 1, "replayed": False, "balance": 7}),
            _release(8, "ready", {"releasedCredits": 1, "replayed": True, "balance": 7})],
         "final": {"balance": 7, "reservations": {"res-0001": _res(4, 3, 1, "settled")}}},
        {"id": "same-key-different-terms", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, ok4), _reserve(3, 3, {"rejectCode": "idempotencyConflict"}),
            _consume(4, "normalizing", 1, {"consumedCredits": 1}),
            _consume(5, "normalizing", 2, {"rejectCode": "idempotencyConflict"})],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 1, 0, "held")}}},
        {"id": "budget-exceeded-then-failed", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 2, {"reservationId": "res-0001", "balance": 8}),
            _consume(3, "normalizing", 2, {"consumedCredits": 2}),
            _consume(4, "planning", 1, {"rejectCode": "budgetExceeded"}),
            _release(5, "failed", {"releasedCredits": 0, "balance": 8})],
         "final": {"balance": 8, "reservations": {"res-0001": _res(2, 2, 0, "released")}}},
        {"id": "failure-returns-unconsumed", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, ok4), _consume(3, "normalizing", 1, {"consumedCredits": 1}),
            _release(4, "failed", {"releasedCredits": 3, "balance": 9}),
            _consume(5, "planning", 1, {"rejectCode": "reservationClosed"})],
         "final": {"balance": 9, "reservations": {"res-0001": _res(4, 1, 3, "released")}}},
        {"id": "expired-quote", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1, at="2026-10-07T23:20:00Z", expect={"rejectCode": "quoteExpired"}),
            _reserve(2, 4, {"rejectCode": "quoteNotAccepted"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "no-consent", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1, consent=False, expect={"rejectCode": "consentMissing"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "illustrative-never-accepted", "environment": "demo", "startBalance": 10,
         "quotes": [_quote("q-1", illustrative=True)], "steps": [
             _accept(1, expect={"rejectCode": "illustrativeQuote"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "demo-never-reserves", "environment": "demo", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, {"rejectCode": "demoNeverReserves"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "live-not-activated", "environment": "live", "startBalance": 10, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 4, {"rejectCode": "liveChargingNotActivated"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "new-revision-new-reservation", "environment": "test", "startBalance": 10,
         "quotes": [_quote("q-1"), _quote("q-2", rev=2)], "steps": [
             _accept(1), _accept(2, q="q-2"), _reserve(3, 4, ok4),
             _reserve(4, 4, {"reservationId": "res-0002", "replayed": False, "balance": 2}, q="q-2", rev=2, key=H,
                      job="job-2")],
         "final": {"balance": 2, "reservations": {"res-0001": _res(4, 0, 0, "held"), "res-0002": _res(4, 0, 0, "held")}}},
        {"id": "cap-and-balance", "environment": "test", "startBalance": 3, "quotes": [_quote("q-1")], "steps": [
            _accept(1), _reserve(2, 5, {"rejectCode": "overCap"}), _reserve(3, 4, {"rejectCode": "insufficientCredits"}),
            _reserve(4, 3, {"reservationId": "res-0001", "balance": 0})],
         "final": {"balance": 0, "reservations": {"res-0001": _res(3, 0, 0, "held")}}},
        {"id": "quote-for-another-revision", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, {"rejectCode": "quoteMismatch"}, rev=2)],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "one-accepted-quote-one-hold", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, ok4),
                   _reserve(3, 4, {"rejectCode": "quoteMismatch"}, key=H2)],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 0, 0, "held")}}},
        {"id": "budget-exceeded-topup-resumes", "environment": "test", "startBalance": 10,
         "quotes": [_quote("q-1"), _quote("q-2", est=4_000_000, cap=5)], "steps": [
             _accept(1), _reserve(2, 2, {"reservationId": "res-0001", "balance": 8}),
             _consume(3, "normalizing", 2, {"consumedCredits": 2}),
             _consume(4, "planning", 1, {"rejectCode": "budgetExceeded"}),
             _accept(5, q="q-2", at="2026-10-07T22:58:00Z"),
             _reserve(6, 5, {"rejectCode": "idempotencyConflict"}, q="q-2", at="2026-10-07T22:58:30Z"),
             _step(7, "topup", {"reservationId": "res-0001", "quoteId": "q-2", "credits": 5,
                                "at": "2026-10-07T22:58:30Z"}, {"reservationId": "res-0001", "reservedCredits": 5,
                                                                "balance": 5}),
             _consume(8, "planning", 1, {"consumedCredits": 3, "replayed": False}),
             _consume(9, "normalizing", 2, {"consumedCredits": 3, "replayed": True}, attempt=2),
             _release(10, "ready", {"releasedCredits": 2, "balance": 7})],
         "final": {"balance": 7, "reservations": {"res-0001": _res(5, 3, 2, "settled")}}},
        {"id": "retries-after-topup-replay", "environment": "test", "startBalance": 10,
         "quotes": [_quote("q-1"), _quote("q-2", est=4_000_000, cap=5)], "steps": [
             _accept(1), _reserve(2, 2, {"reservationId": "res-0001", "balance": 8}),
             _consume(3, "normalizing", 2, {"consumedCredits": 2}),
             _accept(4, q="q-2", at="2026-10-07T22:58:00Z"),
             _step(5, "topup", {"reservationId": "res-0001", "quoteId": "q-2", "credits": 5,
                                "at": "2026-10-07T22:58:30Z"}, {"reservedCredits": 5, "replayed": False, "balance": 5}),
             _reserve(6, 2, {"reservationId": "res-0001", "replayed": True, "balance": 5}, at="2026-10-07T22:59:00Z"),
             _step(7, "topup", {"reservationId": "res-0001", "quoteId": "q-2", "credits": 5,
                                "at": "2026-10-07T22:59:10Z"}, {"reservedCredits": 5, "replayed": True, "balance": 5}),
             _reserve(8, 5, {"rejectCode": "idempotencyConflict"}, q="q-2", at="2026-10-07T22:59:20Z")],
         "final": {"balance": 5, "reservations": {"res-0001": _res(5, 2, 0, "held")}}},
        {"id": "retry-not-charged-twice", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, ok4),
                   _consume(3, "final_rendering", 1, {"consumedCredits": 1, "replayed": False}),
                   _consume(4, "final_rendering", 1, {"consumedCredits": 1, "replayed": True}, attempt=2),
                   _consume(5, "final_rendering", 2, {"rejectCode": "idempotencyConflict"}, attempt=3)],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 1, 0, "held")}}},
        {"id": "fractional-second-expiry", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1, at="2026-10-07T23:15:00.500Z", expect={"rejectCode": "quoteExpired"}),
                   _reserve(2, 4, {"rejectCode": "quoteNotAccepted"})],
         "final": {"balance": 10, "reservations": {}}},
        {"id": "consume-bound-to-job-and-stage", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, ok4),
                   _consume(3, "final_rendering", 1, {"consumedCredits": 1, "replayed": False}),
                   _consume(4, "Final_Rendering", 1, {"rejectCode": "unknownStage"}, attempt=2),
                   _consume(5, "final_rendering", 1, {"rejectCode": "jobMismatch"}, job="job-2"),
                   _consume(6, "not_a_stage", 1, {"rejectCode": "unknownStage"}),
                   _step(7, "attachJob", {"reservationId": "res-0001", "jobId": "job-2"}, {"rejectCode": "jobMismatch"}),
                   _step(8, "attachJob", {"reservationId": "res-0001", "jobId": "job-1"},
                         {"jobId": "job-1", "replayed": True})],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 1, 0, "held")}}},
        {"id": "job-attached-after-reserve", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 4, ok4, job=None),
                   _consume(3, "normalizing", 1, {"rejectCode": "jobMismatch"}),
                   _step(4, "attachJob", {"reservationId": "res-0001", "jobId": "job-1"},
                         {"jobId": "job-1", "replayed": False}),
                   _consume(5, "normalizing", 1, {"consumedCredits": 1, "replayed": False})],
         "final": {"balance": 6, "reservations": {"res-0001": _res(4, 1, 0, "held")}}},
        {"id": "topup-from-initial-quote-refused", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, 2, {"reservationId": "res-0001", "balance": 8}),
                   _step(3, "topup", {"reservationId": "res-0001", "quoteId": "q-1", "credits": 4,
                                      "at": "2026-10-07T22:52:00Z"}, {"rejectCode": "idempotencyConflict"})],
         "final": {"balance": 8, "reservations": {"res-0001": _res(2, 0, 0, "held")}}},
        {"id": "boolean-credits-refused", "environment": "test", "startBalance": 10, "quotes": [_quote("q-1")],
         "steps": [_accept(1), _reserve(2, True, {"rejectCode": "badAmount"})],
         "final": {"balance": 10, "reservations": {}}},
    ]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "ledger",
            "status": "hand-written ledger sequences in Studio Credits (Sample; no money moves). Quotes are bound "
                      "to one outputSpecSha256; consumption is keyed by (job, stage)", "cases": cases}


def quote_credit_vectors():
    rows = [("story-1-design-target", "story-1", 1_120_000, 2), ("story-1-zero", "story-1", 0, 2),
            ("story-1-worst-case", "story-1", 9_400_000, 12), ("broadcast-4-6-design", "broadcast-4-6", 2_320_000, 8),
            ("story-4-6-exact-boundary", "story-4-6", 4_800_000, 6), ("story-4-6-one-over", "story-4-6", 4_800_001, 7),
            ("revision", "revision", 400_000, 1), ("screen-37-class", "story-2-3", 1_290_000, 4)]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "quote-credits",
            "status": "capCredits = max(class minimum, ceil(cost / 800000 micro-USD)); proposal, not a price",
            "cases": [{"id": i, "filmClass": c, "estimatedMaxCostMicroUsd": e, "expectCredits": x} for i, c, e, x in rows]}



# ----- invalid cases ------------------------------------------------------------------------------

def invalid_sets(P, plans):
    sets = {}
    _settled_hash = output_spec_sha256(plans["final"])
    sets["usage-reservation.settled"] = [
        bad("double-consume", "One consumption per stage attempt",
            [rep("/entries/3/key", "consume:job-film-01:normalizing:1")], "idempotencyConflict"),
        bad("totals-disagree", "Totals equal the entries", [rep("/releasedCredits", 2)], "ledgerMismatch"),
        bad("live-charge", "No live charging before its ADR", [rep("/environment", "live"), rep("/sample", False)],
            "liveChargingNotActivated"),
        bad("reserved-above-cap", "A reservation never exceeds the cap", [rep("/capCredits", 3)], "overCap"),
        bad("stage-charged-twice", "A retried stage is charged once, whatever the attempt",
            [rep("/entries/3/key", "consume:job-film-01:normalizing:2")], "idempotencyConflict"),
        bad("retried-reserve-second-key", "A retried reserve written under a second key is a double hold within the "
            "cap; a retry replays instead",
            [rep("/entries/0/credits", 2),
             add("/entries/1", {"entryId": "e-1b", "kind": "reserve", "credits": 2, "key": "reserve:sample-court-day:2:retry",
                                "at": "2026-10-07T22:50:06Z"})], "badEntryKey"),
        bad("reserve-key-of-another-output", "The reserve entry is keyed by this record's own output spec",
            [rep("/entries/0/key", "reserve:sample-court-day:2:" + "c" * 64)], "badEntryKey"),
        bad("consume-for-another-job", "Consumption is charged to this reservation's job only",
            [rep("/entries/3/key", "consume:other-job:final_rendering:2")], "badEntryKey"),
        bad("consume-unknown-stage", "Only the job contract's charged stages consume credits",
            [rep("/entries/3/key", "consume:job-film-01:not_a_stage:2")], "badEntryKey"),
        bad("consume-stage-case", "Stages are spelled exactly; Final_Rendering is not final_rendering",
            [rep("/entries/3/key", "consume:job-film-01:Final_Rendering:2")], "badEntryKey"),
        bad("reserve-keyed-as-consume", "An entry's key prefix is its kind",
            [rep("/entries/1/kind", "reserve"), rep("/reservedCredits", 5), rep("/capCredits", 5),
             rep("/consumedCredits", 2), rep("/releasedCredits", 3), rep("/entries/4/credits", 3)], "badEntryKey"),
        bad("release-outcome-mismatch", "A settled reservation was released as ready, not failed",
            [rep("/entries/4/key", "release:job-film-01:failed")], "badEntryKey"),
        bad("topup-from-initial-quote", "One accepted quote funds one hold: a top-up keyed by the quote that funded the "
            "initial hold is a second hold from the same quote",
            [rep("/entries/0/credits", 2),
             add("/entries/1", {"entryId": "e-1b", "kind": "reserve", "credits": 2,
                                "key": "reserve:sample-court-day:2:" + _settled_hash + ":topup:quote-test-01",
                                "at": "2026-10-07T22:50:06Z"})], "badEntryKey"),
        bad("quote-is-not-initial", "Without a top-up the funding quote is the initial quote",
            [rep("/initialQuoteId", "quote-test-00")], "badEntryKey"),
    ]
    sets["usage-reservation.held"] = [
        bad("demo-credits", "Demo identities never reserve", [rep("/environment", "demo")], "demoNeverReserves"),
    ]
    sets["quote.sample-illustrative"] = [
        bad("illustrative-accepted", "The screen-37 sample quote can never be accepted",
            [rep("/status", "accepted"), rep("/acceptedAt", "2026-10-07T22:50:00Z"),
             rep("/consent", {"consentRecordId": "consent-x", "uploadSelectedSources": True, "modelProvider": True,
                              "textClasses": ["ownerNotes"], "retentionDays": 7,
                              "consentTextVersion": "studio-cloud-consent@1.0.0", "at": "2026-10-07T22:49:00Z"})],
            "illustrativeQuote"),
        bad("long-lived-quote", "Quotes expire within 30 minutes", [rep("/expiresAt", "2026-10-08T00:45:00Z")], "quoteLifetime"),
        bad("client-set-cap", "The cap follows the class minimum and estimate", [rep("/capCredits", 3)], "quoteCapMismatch"),
    ]
    sets["quote.accepted"] = [
        bad("money-on-a-real-quote", "Dollar amounts appear only as illustrative Sample UX",
            [rep("/displayAmounts", {"currency": "USD", "minMinor": 400, "maxMinor": 800, "capMinor": 1200,
                                     "illustrative": True})], "illustrativeQuote"),
        bad("accepted-after-expiry", "Never auto-accepted after expiry", [rep("/acceptedAt", "2026-10-07T23:20:00Z")],
            "quoteExpired"),
        bad("accepted-without-consent", "Acceptance records upload consent", [rep("/consent", None)], "consentMissing"),
        bad("accepted-half-second-late", "23:15:00.500Z is after 23:15:00Z (timestamps are parsed, not compared as text)",
            [rep("/acceptedAt", "2026-10-07T23:15:00.500Z")], "quoteExpired"),
        bad("unbound-quote", "A quote is bound to one output spec", [rm("/outputSpecSha256")]),
        bad("heuristic-quote-with-planner-tokens", "A rules-planned quote estimates no model tokens",
            [rep("/lineItems/plannerTokensEstimate", 120000)], "plannerMismatch"),
        bad("model-planning-without-provider-consent", "Model planning needs the explicit model-provider consent",
            [rep("/plannerChoice", "model"), rep("/lineItems/plannerTokensEstimate", 120000)], "consentMissing"),
        bad("note-text-without-model-consent", "Note text classes go to a model only with model planning",
            [rep("/consent/textClasses", ["ownerNotes"])], "badQuote"),
        bad("consent-retention-differs", "The consent confirms the quote's retention",
            [rep("/consent/retentionDays", 30)], "badQuote"),
        bad("retention-not-offered", "Retention is 1, 7 or 30 days (D-3)", [rep("/retentionDays", 14),
                                                                         rep("/lineItems/storageDays", 14)]),
        bad("consent-without-model-field", "The consent records the model-provider choice", [rm("/consent/modelProvider")]),
        bad("hash-trailing-newline", "A sha256 with a trailing newline is not a sha256 (ECMA-262 anchors)",
            [rep("/outputSpecSha256", "8" * 64 + "\n")]),
    ]
    return invalid_docs(sets)


# ----- what this module declares and registers ----------------------------------------------------

def fixtures(sample):
    docs = {"vectors/ledger.json": ledger_vectors(), "vectors/quote-credits.json": quote_credit_vectors()}
    for name, doc in invalid_sets(sample.P, sample.plans).items():
        docs[f"invalid/{name}.invalid.json"] = doc
    return docs


def check_ledger_vector(ctx, case, report, where) -> None:
    ledger.run_sequence(ctx.classes, case)
    report.ok("ledger vectors")


def check_quote_credit_vector(ctx, case, report, where) -> None:
    got = ledger.quote_credits(ctx.classes, case["filmClass"], case["estimatedMaxCostMicroUsd"])
    if got != case["expectCredits"]:
        report.fail(where, f"{got} credits, expected {case['expectCredits']}")
    else:
        report.ok("quote-credit vectors")


def check_reservation(ctx, doc):
    return ledger.check_reservation_record(doc)


def check_quote(ctx, doc):
    return records.check_quote(doc, ctx.classes)


VECTOR_CHECKERS = {"ledger": check_ledger_vector, "quote-credits": check_quote_credit_vector}
SCHEMAS = {"jovra.quote/1": "quote.schema.json",
           "jovra.usage-reservation/1": "usage-reservation.schema.json",
           "jovra.credit-classes/1": "contracts.schema.json"}
RECORD_RULES = {"jovra.quote/1": check_quote, "jovra.usage-reservation/1": check_reservation}


# ----- self-tests: the quote schema against the credit-classes contract --------------------------------------

def check_class_drift(ctx, report) -> None:
    """quote.schema.json's film classes are exactly the classes of credit-classes.v1.json, in order."""
    film = ctx.schemas.files["quote.schema.json"]["properties"]["filmClass"]["enum"]
    if film != [c["id"] for c in ctx.classes["classes"]]:
        report.fail("drift", "quote film classes differ from credit-classes.v1.json")
    else:
        report.ok("drift checks")


SELF_TESTS = {"ledger-contract-drift": check_class_drift}
