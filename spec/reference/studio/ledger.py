"""Reference quote and usage-reservation ledger: quote -> consent -> cap -> idempotent reservation.

Studio Credits are the single unit of quote, cap, reservation and receipt (pricing research section 5.1, a proposal).
The rules checked here (backend brief 'Job state and money'; pricing research section 7):

* the quote cap is max(class minimum, ceil(estimated max cost / credit budget)); client or model prices are ignored;
* a quote is bound to one output: it carries outputSpecSha256, computed by the server from the stored plan version
  (core.output_spec_sha256), never taken from the client; its consent is part of the quote, so it is bound too;
* a quote expires (at most 30 minutes) and is never auto-accepted; an expired quote cannot reserve; timestamps are
  parsed (core.when), never compared as text;
* a reservation is keyed by (projectId, planRevision, outputSpecSha256): replaying the same request returns the same
  reservation and charges nothing; the same key with different terms is a conflict; a new plan revision is a new key;
  an accepted quote funds at most one reservation, and only the one its outputSpecSha256 names;
* after budget_exceeded the same key is never re-reserved: an accepted re-quote for the same plan revision and output
  tops up the held reservation (topup), so one key always has exactly one reservation and one hold;
* consumption is written when a stage attempt succeeds and is keyed by (jobId, stage): a redelivered queue message or
  a later attempt of a stage that was already charged replays instead of charging again, and a failed attempt writes
  nothing (its cost is bounded by the internal cost cap and maxAttempts, never charged to the owner);
* consumption never exceeds the reservation (budget_exceeded instead), unused credits are released, and a failure
  before ready releases everything not consumed;
* demo identities never reserve; test reservations are Sample; live charging is refused until its own ADR exists;
* a retried request that was already applied replays, also after a top-up: the reservation remembers every
  (quoteId, credits) request it applied, so a redelivered original reserve or a redelivered top-up returns the
  current state with no charge instead of an error;
* a stored UsageReservation's entries are tied to it: reserve keys are reserve:<projectId>:<planRevision>:
  <outputSpecSha256> (the record's own idempotency key; one initial entry, first) or that key plus :topup:<quoteId>;
  consume keys are consume:<jobId>:<stage>:<attempt> with the record's jobId and a charged stage of the job contract
  (exact spelling); release keys are release:<jobId>:<outcome> matching the record's status; every key's prefix is
  its entry kind.
"""

from __future__ import annotations

import json
import re
from fractions import Fraction
from pathlib import Path

from .core import Reject, require, when

CONTRACT = Path(__file__).resolve().parents[2] / "studio" / "contracts" / "credit-classes.v1.json"
JOB_CONTRACT = Path(__file__).resolve().parents[2] / "studio" / "contracts" / "render-job-transitions.v1.json"
HEX64 = re.compile(r"[0-9a-f]{64}")
ATTEMPT = re.compile(r"[1-9][0-9]{0,3}")
RELEASE_OUTCOME = {"settled": "ready", "released": "failed", "canceled": "canceled"}


def charged_stages(path: Path = JOB_CONTRACT) -> frozenset:
    """The stages that may write a consume entry: the job contract's budget-checked stages, spelled exactly."""
    return frozenset(json.loads(path.read_text(encoding="utf-8"))["budgetCheckedBefore"])


def credits_value(value, label: str, minimum: int = 0) -> int:
    """Credits are plain integers; a boolean is not a credit (True would otherwise count as 1)."""
    require(type(value) is int and value >= minimum, "badAmount", f"{label} must be an integer >= {minimum}")
    return value


def load_classes(path: Path = CONTRACT) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def quote_credits(classes: dict, class_id: str, estimated_max_cost_micro_usd: int) -> int:
    by_id = {c["id"]: c for c in classes["classes"]}
    require(class_id in by_id, "unknownFilmClass", f"unknown film class {class_id!r}")
    require(type(estimated_max_cost_micro_usd) is int and estimated_max_cost_micro_usd >= 0, "badEstimate",
            "estimate must be a non-negative integer of micro-USD")
    budget = classes["creditCostBudgetMicroUsd"]
    return max(by_id[class_id]["minimumCredits"], Fraction(estimated_max_cost_micro_usd, budget).__ceil__())


class Ledger:
    """In-memory reference ledger. Timestamps are parsed with core.when before any comparison."""

    def __init__(self, environment: str, balance: int):
        require(environment in ("demo", "test", "live"), "badEnum", "environment")
        self.environment = environment
        self.balance = credits_value(balance, "balance")
        self.quotes: dict[str, dict] = {}
        self.reservations: dict[str, dict] = {}
        self.by_key: dict[tuple, str] = {}
        self.consumed_keys: dict[tuple, dict] = {}
        self.counter = 0

    # quotes ------------------------------------------------------------------------------------
    def add_quote(self, quote: dict, classes: dict) -> None:
        expected = quote_credits(classes, quote["filmClass"], quote["estimatedMaxCostMicroUsd"])
        require(quote["capCredits"] == expected, "quoteCapMismatch",
                f"cap must be {expected} credits from the class minimum and cost estimate")
        require(quote["estimate"]["minCredits"] <= quote["estimate"]["maxCredits"] <= quote["capCredits"],
                "badQuote", "estimate must satisfy min <= max <= cap")
        require(type(quote.get("outputSpecSha256")) is str and HEX64.fullmatch(quote["outputSpecSha256"]) is not None,
                "badQuote", "a quote is bound to one output spec (outputSpecSha256)")
        self.quotes[quote["quoteId"]] = dict(quote, reservationId=None)

    def accept(self, quote_id: str, at: str, consent: bool) -> None:
        q = self._quote(quote_id)
        require(not q.get("illustrative"), "illustrativeQuote", "an illustrative Sample quote can never be accepted")
        require(consent is True, "consentMissing", "the owner must consent to uploading the selected sources")
        require(when(at) < when(q["expiresAt"]), "quoteExpired", "quote expired; re-quote, never auto-accept")
        require(q["status"] == "open", "badQuoteState", f"quote is {q['status']}")
        q["status"] = "accepted"
        q["acceptedAt"] = at

    def _quote(self, quote_id: str) -> dict:
        require(quote_id in self.quotes, "unknownQuote", f"unknown quote {quote_id}")
        return self.quotes[quote_id]

    def _fundable(self, q: dict, project_id: str, plan_revision: int, output_spec_sha256: str, at: str) -> None:
        require(q["status"] == "accepted", "quoteNotAccepted", "reserve only after the quote is accepted")
        require(when(at) < when(q["expiresAt"]), "quoteExpired", "quote expired before the reservation")
        require(q["projectId"] == project_id and q["planRevision"] == plan_revision
                and q["outputSpecSha256"] == output_spec_sha256, "quoteMismatch",
                "the quote is for another project, plan revision or output spec")
        require(q["reservationId"] is None, "quoteAlreadyUsed", "an accepted quote funds exactly one reservation")

    # reservations ------------------------------------------------------------------------------
    def reserve(self, *, quote_id: str, project_id: str, plan_revision: int, output_spec_sha256: str,
                credits: int, at: str) -> dict:
        require(self.environment != "demo", "demoNeverReserves", "demo identities never write reservations")
        require(self.environment != "live", "liveChargingNotActivated",
                "live charging needs its own ADR, benchmarks and a margin model (ADR-0013)")
        credits_value(credits, "credits")
        key = (project_id, plan_revision, output_spec_sha256)
        if key in self.by_key:
            r = self.reservations[self.by_key[key]]
            require((quote_id, credits) in r["reserveRequests"], "idempotencyConflict",
                    "same idempotency key with different terms (after budget_exceeded, top up instead)")
            return {"reservationId": r["reservationId"], "replayed": True, "balance": self.balance}
        q = self._quote(quote_id)
        self._fundable(q, project_id, plan_revision, output_spec_sha256, at)
        require(0 < credits <= q["capCredits"], "overCap", "reservation must be positive and within the cap")
        require(credits <= self.balance, "insufficientCredits", "not enough credits")
        self.counter += 1
        rid = f"res-{self.counter:04d}"
        self.balance -= credits
        self.reservations[rid] = {"reservationId": rid, "quoteId": quote_id, "key": key, "capCredits": q["capCredits"],
                                  "reservedCredits": credits, "consumedCredits": 0, "releasedCredits": 0,
                                  "status": "held", "reserveRequests": {(quote_id, credits)}, "topupRequests": set()}
        self.by_key[key] = rid
        q["reservationId"] = rid
        return {"reservationId": rid, "replayed": False, "balance": self.balance}

    def topup(self, *, reservation_id: str, quote_id: str, credits: int, at: str) -> dict:
        """Raise a held reservation to `credits` under a newly accepted quote for the same key (the budget_exceeded
        resume path). The old quote is superseded; consumption already recorded stays, so no stage is charged twice."""
        r = self._reservation(reservation_id)
        credits_value(credits, "credits")
        if (quote_id, credits) in r["topupRequests"]:
            # a redelivered top-up that was already applied: replay the current state, charge nothing
            return {"reservationId": reservation_id, "reservedCredits": r["reservedCredits"], "replayed": True,
                    "balance": self.balance}
        require(r["status"] == "held", "reservationClosed", f"reservation is {r['status']}")
        q = self._quote(quote_id)
        require(quote_id != r["quoteId"], "idempotencyConflict", "a top-up needs a new accepted quote")
        self._fundable(q, *r["key"], at)
        require(r["reservedCredits"] < credits <= q["capCredits"], "overCap",
                "a top-up raises the reservation and stays within the new cap")
        extra = credits - r["reservedCredits"]
        require(extra <= self.balance, "insufficientCredits", "not enough credits")
        self.balance -= extra
        self.quotes[r["quoteId"]]["status"] = "superseded"
        q["reservationId"] = reservation_id
        r.update(quoteId=quote_id, capCredits=q["capCredits"], reservedCredits=credits)
        r["topupRequests"].add((quote_id, credits))
        return {"reservationId": reservation_id, "reservedCredits": credits, "replayed": False, "balance": self.balance}

    def consume(self, *, reservation_id: str, job_id: str, stage: str, attempt: int, credits: int) -> dict:
        r = self._reservation(reservation_id)
        require(r["status"] == "held", "reservationClosed", f"reservation is {r['status']}")
        credits_value(credits, "credits")
        credits_value(attempt, "attempt", 1)
        key = (reservation_id, job_id, stage)
        if key in self.consumed_keys:
            require(self.consumed_keys[key]["credits"] == credits, "idempotencyConflict",
                    "this stage was already charged a different amount")
            return {"consumedCredits": r["consumedCredits"], "replayed": True}
        require(r["consumedCredits"] + credits <= r["reservedCredits"], "budgetExceeded",
                "stage would exceed the reservation; stop at budget_exceeded, never raise the cap")
        r["consumedCredits"] += credits
        self.consumed_keys[key] = {"credits": credits, "attempt": attempt}
        return {"consumedCredits": r["consumedCredits"], "replayed": False}

    def release(self, *, reservation_id: str, outcome: str) -> dict:
        """Close a reservation. outcome: 'ready' settles consumption; 'failed' or 'canceled' returns every
        unconsumed credit (a film that failed verification is never charged as delivered)."""
        r = self._reservation(reservation_id)
        require(outcome in ("ready", "failed", "canceled"), "badEnum", "release outcome")
        if r["status"] != "held":
            return {"releasedCredits": r["releasedCredits"], "replayed": True, "balance": self.balance}
        unused = r["reservedCredits"] - r["consumedCredits"]
        r["releasedCredits"] = unused
        r["status"] = {"ready": "settled", "failed": "released", "canceled": "canceled"}[outcome]
        self.balance += unused
        return {"releasedCredits": unused, "replayed": False, "balance": self.balance}

    def _reservation(self, rid: str) -> dict:
        require(rid in self.reservations, "unknownReservation", f"unknown reservation {rid}")
        return self.reservations[rid]


def run_sequence(classes: dict, vector: dict) -> dict:
    """Run a ledger vector: steps with expected results or rejection codes; returns the final snapshot."""
    ledger = Ledger(vector["environment"], vector["startBalance"])
    for quote in vector.get("quotes", []):
        ledger.add_quote(quote, classes)
    for step in vector["steps"]:
        op, args = step["op"], step["args"]
        try:
            if op == "accept":
                ledger.accept(args["quoteId"], args["at"], args["consent"])
                got = {}
            elif op == "reserve":
                got = ledger.reserve(quote_id=args["quoteId"], project_id=args["projectId"],
                                     plan_revision=args["planRevision"], output_spec_sha256=args["outputSpecSha256"],
                                     credits=args["credits"], at=args["at"])
            elif op == "topup":
                got = ledger.topup(reservation_id=args["reservationId"], quote_id=args["quoteId"],
                                   credits=args["credits"], at=args["at"])
            elif op == "consume":
                got = ledger.consume(reservation_id=args["reservationId"], job_id=args["jobId"], stage=args["stage"],
                                     attempt=args["attempt"], credits=args["credits"])
            elif op == "release":
                got = ledger.release(reservation_id=args["reservationId"], outcome=args["outcome"])
            else:
                raise Reject("badVector", f"unknown op {op}")
        except Reject as exc:
            require(step["expect"].get("rejectCode") == exc.code, "vectorMismatch",
                    f"{vector['id']} step {step['step']}: rejected with {exc.code}, expected {step['expect']}")
            continue
        require("rejectCode" not in step["expect"], "vectorMismatch",
                f"{vector['id']} step {step['step']}: accepted, expected {step['expect']['rejectCode'] if 'rejectCode' in step['expect'] else ''}")
        for key, value in step["expect"].items():
            require(got.get(key) == value, "vectorMismatch",
                    f"{vector['id']} step {step['step']}: {key} {got.get(key)!r} != {value!r}")
    snapshot = {"balance": ledger.balance,
                "reservations": {k: {f: v[f] for f in ("reservedCredits", "consumedCredits", "releasedCredits", "status")}
                                 for k, v in sorted(ledger.reservations.items())}}
    require(snapshot == vector["final"], "vectorMismatch", f"{vector['id']}: final ledger {snapshot} != {vector['final']}")
    return snapshot


def _check_entry_key(rec: dict, e: dict, stages: frozenset, topups: list, index: int) -> tuple | None:
    """Ties one entry's key to its record. Returns (job, stage) for a consume entry."""
    parts = e["key"].split(":")
    require(parts[0] == e["kind"], "badEntryKey", f"{e['key']}: a {e['kind']} entry is keyed {e['kind']}:...")
    if e["kind"] == "reserve":
        k = rec["idempotencyKey"]
        own = ["reserve", k["projectId"], str(k["planRevision"]), k["outputSpecSha256"]]
        require(k["projectId"] == rec["projectId"], "badEntryKey", "the idempotency key names another project")
        require(parts[:4] == own and (len(parts) == 4 or (len(parts) == 6 and parts[4] == "topup")), "badEntryKey",
                f"{e['key']}: reserve keys are the record's own key {':'.join(own)}, or that key plus :topup:<quoteId>")
        if len(parts) == 4:
            require(index == 0, "badEntryKey", "the one initial reserve entry is the first entry; a retried reserve "
                    "replays, it never writes a second hold under another key")
        else:
            require(index > 0 and parts[5] not in topups, "badEntryKey", f"{e['key']}: one top-up per accepted quote")
            topups.append(parts[5])
        return None
    require(rec["jobId"] is not None and len(parts) >= 3 and parts[1] == rec["jobId"], "badEntryKey",
            f"{e['key']}: {e['kind']} entries name this reservation's job {rec['jobId']}")
    if e["kind"] == "consume":
        require(len(parts) == 4 and parts[2] in stages and ATTEMPT.fullmatch(parts[3]) is not None, "badEntryKey",
                f"{e['key']}: consume keys are consume:<jobId>:<charged stage>:<attempt>")
        return parts[1], parts[2]
    require(len(parts) == 3 and parts[2] == RELEASE_OUTCOME.get(rec["status"]), "badEntryKey",
            f"{e['key']}: release keys are release:<jobId>:<outcome> and match the status {rec['status']}")
    return None


def check_reservation_record(rec: dict, stages: frozenset | None = None) -> None:
    """Totals in a UsageReservation record equal its entries; idempotency keys are unique and tied to this record
    (its own idempotency key, job, charged stages and status); the cap holds."""
    stages = charged_stages() if stages is None else stages
    require(rec["reservedCredits"] <= rec["capCredits"], "overCap", "reserved credits exceed the cap")
    totals = {"reserve": 0, "consume": 0, "release": 0}
    seen = set()
    charged = set()
    topups: list = []
    for index, e in enumerate(rec["entries"]):
        require(e["key"] not in seen, "idempotencyConflict", f"duplicate entry key {e['key']}")
        seen.add(e["key"])
        totals[e["kind"]] += e["credits"]
        job_stage = _check_entry_key(rec, e, stages, topups, index)
        if job_stage is not None:
            require(job_stage not in charged, "idempotencyConflict",
                    f"stage {job_stage[1]} of {job_stage[0]} is charged once, whatever the attempt")
            charged.add(job_stage)
    require(rec["entries"] and rec["entries"][0]["kind"] == "reserve", "badEntryKey",
            "a reservation starts with its reserve entry")
    require(sum(1 for e in rec["entries"] if e["kind"] == "release") <= 1, "badEntryKey", "one release per reservation")
    if topups:
        require(rec["quoteId"] == topups[-1], "badEntryKey", "after a top-up, quoteId names the newest quote")
    require(totals["reserve"] == rec["reservedCredits"] and totals["consume"] == rec["consumedCredits"]
            and totals["release"] == rec["releasedCredits"], "ledgerMismatch", "entry totals differ from the record")
    require(rec["consumedCredits"] + rec["releasedCredits"] <= rec["reservedCredits"], "budgetExceeded",
            "consumed plus released exceeds the reservation")
    if rec["status"] == "held":
        require(rec["releasedCredits"] == 0, "ledgerMismatch", "a held reservation has released nothing")
    else:
        require(rec["consumedCredits"] + rec["releasedCredits"] == rec["reservedCredits"], "ledgerMismatch",
                "a closed reservation accounts for every reserved credit")
    if rec["environment"] == "demo":
        require(rec["reservedCredits"] == 0, "demoNeverReserves", "demo reservations hold zero credits")
    if rec["environment"] in ("demo", "test"):
        require(rec["sample"] is True, "sampleRequired", "demo and test reservations are Sample")
    require(rec["environment"] != "live", "liveChargingNotActivated", "no live reservation before its ADR")
