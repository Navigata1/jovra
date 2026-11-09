#!/usr/bin/env python3
"""Replay the Studio ledger vectors through the SQL commands of the local stack (S80 / B-06 adapter test).

spec/studio/fixtures/vectors/ledger.json holds hand-written credit-ledger sequences checked against the reference
ledger (spec/reference/studio/ledger.py). This script runs every sequence against the real database: each vector
operation becomes calls of the app_gateway commands, as jovra_gateway (create_quote, accept_quote) or
jovra_orchestrator (set_job_state, reserve_stage, claim_attempt, finish_attempt, mark_artifact_verified), and every
balance it compares is read back from the rows those commands wrote. It also checks the SQL job-state transition table
against spec/studio/contracts/render-job-transitions.v1.json for every pair of job states.

How the ledger maps onto the database (1 credit = creditCostBudgetMicroUsd = 800,000 micro-USD):
  * a reservation of R credits is the hold that accept_quote opens: the vector quote is a real create_quote quote
    whose cap the adapter writes at R credits (SQL holds exactly the quoted cap; a reservation below the quote's cap
    is replayed as a quote at R);
  * accept is a dry run of accept_quote rolled back (expiry and consent are decided there); reserve is the real
    accept_quote, with the HTTP idempotency key reserve:<quote>:<credits>; topup is accept_quote of a re-quote that
    supersedes the hold's quote after the job stopped at budget_exceeded (story 186);
  * consume of k credits for a stage is reserve_stage + claim_attempt + finish_attempt('succeeded') with measurements
    whose SQL-computed cost is k x 800,000 (rate card rates-ledger-vectors: 1,000 micro-USD per container second and a
    stage floor of 2 credits, so a stage's reservation covers what it consumes); the job is first moved to that stage's
    state through set_job_state along the contract's forward edges;
  * release ready is the verify stage (mark_artifact_verified on the film) and set_job_state(verifying -> ready);
    release failed is set_job_state(-> failed_terminal) where the contract allows it, else -> canceled;
  * balance = startBalance - sum(cap of held holds) - sum(consumed of closed holds), the owner's open cap is
    startBalance x 800,000; reservedCredits = cap, consumedCredits = consumed, releasedCredits = cap - consumed once
    closed, all read from usage_reservations.
Some vector rules have no separate database request; the adapter enforces them itself and labels the step:
  * adapter: overCap (a reservation above the quote's cap), badAmount (a non-integer amount; the gateway's JSON Schema),
    quoteNotAccepted (an acceptance that was refused), a second quote on a held key outside a top-up, and job naming
    (attachJob: SQL creates the job together with the hold);
  * gateway / app: demo identities never reach the database (T-GW-03) and illustrative quotes are never stored.
Every other step's outcome, accepted or refused, is the database's.

Usage (from backend/): supabase status -o env > "$TMP/status.env"
                       python3 supabase/scripts/ledger_vector_replay.py "$TMP/status.env"
Python standard library and psql only. Rows are committed per case under fresh users and removed at the end (the
append-only spend ledger and audit log keep theirs, as in production). Exit status is non-zero when any check fails.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import uuid
from collections import deque
from datetime import datetime
from pathlib import Path

from otp_smoke import Checks, read_env  # same folder; shared helpers

ROOT = Path(__file__).resolve().parents[3]
VECTORS = ROOT / "spec" / "studio" / "fixtures" / "vectors" / "ledger.json"
CONTRACT = ROOT / "spec" / "studio" / "contracts" / "render-job-transitions.v1.json"
CREDIT = 800_000
RATES = "rates-ledger-vectors"
STAGE_OF_STATE = {"normalizing": "normalize", "syncing": "sync", "analyzing": "analyze", "planning": "plan",
                  "preview_rendering": "preview_render", "final_rendering": "final_render",
                  "verifying": "verify_output"}
OUTPUTS = {"a": 120, "b": 60}   # the vector's outputSpecSha256 letter -> durationTargetSec of a real output spec
CONSENT = {"at": "2026-10-07T22:50:00Z", "consentRecordId": "consent-ledger", "consentTextVersion":
           "studio-cloud-consent@1.0.0", "modelProvider": False, "retentionDays": 7, "textClasses": [],
           "uploadSelectedSources": True}
# SQL refusal (message, else SQLSTATE) -> the ledger reject codes it stands for
SQL_CODES = {
    "quote_expired": {"quoteExpired"}, "invalid_value:consent": {"consentMissing"},
    "inputs_changed": {"quoteMismatch"}, "already_accepted": {"idempotencyConflict", "quoteMismatch"},
    "duplicate_work": {"idempotencyConflict"}, "budget_exceeded": {"insufficientCredits", "budgetExceeded"},
    "reservation_closed": {"reservationClosed"}, "not_found": {"jobMismatch"}, "22P02": {"unknownStage"},
    "already_finished": {"idempotencyConflict"}, "stage_already_charged": {"idempotencyConflict"},
    "live_charging_not_activated": {"liveChargingNotActivated"}, "topup_not_larger": {"overCap"},
}


class Refused(Exception):
    def __init__(self, codes: set[str], layer: str, detail: str):
        super().__init__(detail)
        self.codes, self.layer, self.detail = codes, layer, detail


def lit(value) -> str:
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def when(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


class Db:
    def __init__(self, url: str):
        self.url = url

    def run(self, script: str) -> tuple[list[str], tuple[str, str] | None]:
        result = subprocess.run(["psql", self.url, "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-f", "-"],
                                input="\\set VERBOSITY verbose\n" + script, capture_output=True, text=True, timeout=120)
        lines = [line for line in result.stdout.splitlines() if line.strip()]
        if result.returncode == 0:
            return lines, None
        match = re.search(r"ERROR:\s+([0-9A-Z]{5}):\s+(.*)", result.stderr)
        if not match:
            raise RuntimeError(result.stderr.strip()[-400:])
        return lines, (match.group(1), match.group(2).strip())

    def value(self, sql: str) -> str | None:
        lines, error = self.run(f"select ({sql})::text;")
        if error:
            raise RuntimeError(f"{sql}: {error}")
        return lines[-1] if lines else None

    def call(self, role: str, expr: str, prelude: str = "", commit: bool = True) -> dict:
        """One command as `role` inside one transaction; its jsonb (or scalar) result, else a SQL refusal."""
        lines, error = self.run(f"begin;\n{prelude}\nset local role {role};\nselect ({expr})::text;\n"
                                + ("commit;" if commit else "rollback;"))
        if error:
            raise Refused(SQL_CODES.get(error[1], SQL_CODES.get(error[0], set())), "sql", f"{error[0]} {error[1]}")
        text = lines[-1] if lines else ""
        try:
            out = json.loads(text)
        except json.JSONDecodeError:
            out = text
        return out if isinstance(out, dict) else {"value": out}


class Transitions:
    """The contract's job-state machine (render-job-transitions.v1.json), restricted to job states."""

    def __init__(self, contract: dict, states: list[str]):
        self.c, self.states = contract, states
        self.forward = {(f, t) for f, ts in contract["forward"].items() for t in ts if f in states and t in states}

    def allowed(self, f: str, t: str, resume: str | None) -> bool:
        c = self.c
        return f != t and ((f, t) in self.forward
                           or (t == "paused" and f in c["pausableFrom"]) or (f == "paused" and t == resume)
                           or (t == "failed_retryable" and f in c["retryableFrom"])
                           or (f == "failed_retryable" and t == resume)
                           or (t == "failed_terminal" and f in c["terminalFailureFrom"])
                           or (t == "budget_exceeded" and f in c["budgetExceededFrom"])
                           or (t == "canceled" and f not in c["terminal"]) or t == "deleted")

    def path(self, start: str, goal: str) -> list[str] | None:
        """The shortest forward walk from start to goal (the Workflow's own order of stages)."""
        seen, queue = {start: []}, deque([start])
        while queue:
            node = queue.popleft()
            if node == goal:
                return seen[node]
            for f, t in sorted(self.forward):
                if f == node and t not in seen:
                    seen[t] = seen[node] + [t]
                    queue.append(t)
        return None


class Case:
    def __init__(self, db: Db, vector: dict, run: str, index: int, transitions: Transitions):
        self.db, self.v, self.tr = db, vector, transitions
        self.env = vector["environment"]
        self.owner_name = f"ledger_{run}_{index}"
        self.project = str(uuid.uuid4())
        self.plan = str(uuid.uuid4())
        self.sources = [str(uuid.uuid4()), str(uuid.uuid4())]
        self.versions: dict[int, str] = {}
        self.quotes = {q["quoteId"]: dict(q, sql=None, accepted=False) for q in vector.get("quotes", [])}
        self.holds: dict[str, dict] = {}
        self.by_key: dict[tuple, str] = {}
        self.tokens: dict[str, str] = {}
        self.owner = ""

    # setup ---------------------------------------------------------------------------------------------------
    def setup(self) -> None:
        if self.env == "demo":
            return   # demo identities never reach the database (gateway T-GW-03): nothing to create
        s1, s2 = self.sources
        script = [
            "begin;",
            f"select tests.create_supabase_user({lit(self.owner_name)});",
            f"update public.profiles set is_tester = true where id = tests.get_supabase_uid({lit(self.owner_name)});",
            f"insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd) "
            f"values ('owner', tests.get_supabase_uid({lit(self.owner_name)}), {self.v['startBalance'] * CREDIT}, "
            f"1000000000000);",
            f"insert into public.projects (id, owner_id, local_project_id, title) values ({lit(self.project)}, "
            f"tests.get_supabase_uid({lit(self.owner_name)}), gen_random_uuid(), 'Ledger vector Sample');",
        ]
        for slot, source in (("primary_baseline", s1), ("opposite_baseline", s2)):
            script.append(f"insert into public.camera_sources (id, project_id, slot, local_source_id, state, "
                          f"declared_bytes, declared_sha256) values ({lit(source)}, {lit(self.project)}, '{slot}', "
                          f"gen_random_uuid(), 'verified', 100000000, sha256({lit(source)}::bytea));")
        script += [
            f"insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values "
            f"({lit(self.project)}, {lit(json.dumps({'sources': [{'sourceId': s1}, {'sourceId': s2}]}))}::jsonb, "
            f"sha256('ledger'::bytea), 'render');",
            f"insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values "
            f"({lit(self.plan)}, {lit(self.project)}, 'coach-cut', 1, 'Ledger plan');",
        ]
        for revision in (1, 2):
            self.versions[revision] = str(uuid.uuid4())
            script.append(f"insert into public.story_plan_versions (id, story_plan_id, planner_kind, "
                          f"planner_adapter_version, story_plan) values ({lit(self.versions[revision])}, "
                          f"{lit(self.plan)}, 'heuristic', 'h1', '{{}}');")
        script.append("commit;")
        _, error = self.db.run("\n".join(script))
        if error:
            raise RuntimeError(f"setup {self.v['id']}: {error}")
        self.owner = self.db.value(f"tests.get_supabase_uid({lit(self.owner_name)})")
        if int(self.db.value(f"(select version from public.story_plan_versions where id = {lit(self.versions[2])})")) != 2:
            raise RuntimeError("plan versions were not numbered 1 and 2")

    def env_prelude(self) -> str:
        return (f"insert into app_ops.settings (env) values ({lit(self.env)}) "
                "on conflict (id) do update set env = excluded.env;")

    # quotes --------------------------------------------------------------------------------------------------
    def create_sql_quote(self, vq: str) -> dict:
        q = self.quotes[vq]
        output = {"fps": {"num": 30, "den": 1}, "width": 1920, "height": 1080, "aspect": "16:9", "container": "mp4",
                  "videoCodec": "h264", "audioCodec": "aac", "audioSampleRate": 48000,
                  "durationTargetSec": OUTPUTS[q["outputSpecSha256"][0]]}
        out = self.db.call("jovra_gateway", f"app_gateway.create_quote({lit(self.owner)}, {lit(self.project)}, "
                           f"{lit(self.plan)}, {lit(self.versions[q['planRevision']])}, 'heuristic', "
                           f"{lit(json.dumps(output))}::jsonb, array[{lit(self.sources[0])}, {lit(self.sources[1])}]"
                           f"::uuid[], 7, gen_random_uuid())", prelude=self.env_prelude())
        q["sql"] = {"id": out["quoteId"], "inputs": out["inputsSha256"], "supersedes": out["supersedesQuoteId"]}
        self.price(vq, q["capCredits"])
        return q["sql"]

    def price(self, vq: str, credits: int) -> None:
        """The quote's terms in credits (cap and estimate) on the ledger's rate card; server write, as postgres."""
        q = self.quotes[vq]
        high = min(q["estimate"]["maxCredits"], credits)
        low = min(q["estimate"]["minCredits"], high)
        _, error = self.db.run(
            f"update public.quotes set rates_version = '{RATES}', cap_credits = {credits}, "
            f"cap_cost_micro_usd = {credits * CREDIT}, estimate_high_credits = {high}, estimate_low_credits = {low}, "
            f"estimate_high_cost_micro_usd = {min(q['estimatedMaxCostMicroUsd'], credits * CREDIT)} "
            f"where id = {lit(q['sql']['id'])} and state = 'open';")
        if error:
            raise RuntimeError(f"price {vq}: {error}")
        q["credits"] = credits

    def accept_sql(self, vq: str, at: str, key: str, credits: int, consent: bool = True,
                   inputs: str | None = None, commit: bool = True) -> dict:
        q = self.quotes[vq]
        offset = (when(q["expiresAt"]) - when(at)).total_seconds()
        prelude = (self.env_prelude() + f"\nupdate public.quotes set created_at = now() + interval '{offset} seconds' "
                   f"- interval '30 minutes', expires_at = now() + interval '{offset} seconds' "
                   f"where id = {lit(q['sql']['id'])} and state = 'open';")
        body = dict(CONSENT, uploadSelectedSources=bool(consent))
        return self.db.call("jovra_gateway", f"app_gateway.accept_quote({lit(self.owner)}, {lit(q['sql']['id'])}, "
                            f"decode({lit(inputs or q['sql']['inputs'])}, 'hex'), {lit(json.dumps(body))}::jsonb, "
                            f"{credits}, {lit(key)}, gen_random_uuid())", prelude=prelude, commit=commit)

    # reads -----------------------------------------------------------------------------------------------------
    def hold_row(self, rid: str) -> dict:
        return json.loads(self.db.value(
            f"(select to_jsonb(r) from public.usage_reservations r where r.id = {lit(self.holds[rid]['reservation'])})"))

    def balance(self) -> int:
        if self.env == "demo":
            return self.v["startBalance"]
        spent = self.db.value(f"(select coalesce(sum(case when state = 'held' then cap_cost_micro_usd "
                              f"else consumed_cost_micro_usd end), 0) from public.usage_reservations "
                              f"where owner_id = {lit(self.owner)})")
        return self.v["startBalance"] - int(spent) // CREDIT

    def credits(self, rid: str) -> dict:
        row = self.hold_row(rid)
        consumed = row["consumed_cost_micro_usd"] // CREDIT
        closed = row["state"] != "held"
        return {"reservedCredits": row["cap_credits"], "consumedCredits": consumed,
                "releasedCredits": row["cap_credits"] - consumed if closed else 0, "status": row["state"]}

    def job_state(self, job: str) -> str:
        return self.db.value(f"(select state from public.render_jobs where id = {lit(job)})")

    # orchestration ----------------------------------------------------------------------------------------------
    def set_state(self, job: str, target: str) -> dict:
        return self.db.call("jovra_orchestrator", f"app_gateway.set_job_state({lit(job)}, {lit(self.job_state(job))}, "
                            f"{lit(target)}, null, gen_random_uuid())")

    def walk(self, job: str, goal: str) -> None:
        for state in self.tr.path(self.job_state(job), goal) or []:
            self.set_state(job, state)

    def run_stage(self, job: str, stage: str, attempt: int, cost: int, outputs: list | None = None) -> dict:
        """reserve_stage, claim_attempt (when the attempt is new) and finish_attempt('succeeded')."""
        reserved = self.db.call("jovra_orchestrator", f"app_gateway.reserve_stage({lit(job)}, {lit(stage)}, {attempt}, "
                                "gen_random_uuid())")
        attempt_id = reserved["attemptId"]
        if reserved["state"] == "reserved":
            claim = self.db.call("jovra_orchestrator", f"app_gateway.claim_attempt({lit(attempt_id)}, 'ledger-host', "
                                 "'cf-container', gen_random_uuid())")
            self.tokens[attempt_id] = claim["leaseToken"]
        measurements = {"wallMs": cost, "cpuMs": 0, "bytesIn": 0, "bytesOut": 0}   # 1,000 micro-USD per second
        token_hash = hashlib.sha256(self.tokens.get(attempt_id, "jvl_unknown").encode()).hexdigest()
        finished = self.db.call("jovra_orchestrator", f"app_gateway.finish_attempt({lit(attempt_id)}, "
                                f"decode({lit(token_hash)}, 'hex'), 'succeeded', {lit(json.dumps(outputs or []))}::jsonb, "
                                f"{lit(json.dumps(measurements))}::jsonb, null, null, null, gen_random_uuid())")
        return dict(finished, attemptId=attempt_id, replayed=bool(finished.get("replayed") or reserved.get("alreadyCharged")))

    # vector operations ---------------------------------------------------------------------------------------
    def op_accept(self, a: dict) -> dict:
        q = self.quotes[a["quoteId"]]
        if q.get("illustrative"):
            raise Refused({"illustrativeQuote"}, "app", "an illustrative Sample quote is never stored")
        if self.env == "demo":
            q["accepted"] = True
            return {}
        if q["sql"] is None:
            self.create_sql_quote(a["quoteId"])
        try:
            self.accept_sql(a["quoteId"], a["at"], f"dry-run:{a['quoteId']}", q["credits"], consent=a["consent"],
                            commit=False)
        except Refused as refused:
            if refused.codes & {"quoteExpired", "consentMissing"}:
                raise
            # spend, duplicate-work and environment refusals belong to the reservation step, as in the vector
        q["accepted"] = True
        return {}

    def op_reserve(self, a: dict) -> dict:
        if self.env == "demo":
            raise Refused({"demoNeverReserves"}, "gateway", "demo identities never reach the database (T-GW-03)")
        if type(a["credits"]) is not int:
            raise Refused({"badAmount"}, "adapter", "credits are integers (the gateway's JSON Schema)")
        vq, credits, key = a["quoteId"], a["credits"], (a["planRevision"], a["outputSpecSha256"])
        q = self.quotes[vq]
        if key in self.by_key:
            rid = self.by_key[key]
            hold = self.holds[rid]
            if vq != hold["initial"]:
                raise Refused({"idempotencyConflict"}, "adapter", "a second quote on a held key is a top-up request")
            if a.get("jobId") is not None and a["jobId"] != hold["job_name"]:
                raise Refused({"idempotencyConflict"}, "adapter", "the hold funds another job")
            out = self.accept_sql(vq, a["at"], f"reserve:{vq}:{credits}", credits)
            return {"reservationId": rid, "replayed": out.get("replayed"), "balance": self.balance()}
        if not q["accepted"]:
            raise Refused({"quoteNotAccepted"}, "adapter", "the acceptance was refused, so there is nothing to reserve")
        if not 0 < credits <= q["capCredits"]:
            raise Refused({"overCap"}, "adapter", "a reservation above the quote's cap (SQL holds exactly the cap)")
        own_key = (q["planRevision"], q["outputSpecSha256"])
        if q["sql"] is not None and not self.is_accepted(vq):
            self.price(vq, credits)
        presented = None if key == own_key else hashlib.sha256(f"{key}".encode()).hexdigest()
        out = self.accept_sql(vq, a["at"], f"reserve:{vq}:{credits}", credits, inputs=presented)
        rid = f"res-{len(self.holds) + 1:04d}"
        self.holds[rid] = {"reservation": out["reservationId"], "job": out["jobId"], "job_name": a.get("jobId"),
                           "initial": vq, "current": vq, "topups": set()}
        self.by_key[key] = rid
        return {"reservationId": rid, "replayed": out["replayed"], "balance": self.balance()}

    def is_accepted(self, vq: str) -> bool:
        return self.db.value(f"(select state from public.quotes where id = {lit(self.quotes[vq]['sql']['id'])})") != "open"

    def op_attach(self, a: dict) -> dict:
        hold = self.holds[a["reservationId"]]
        if hold["job_name"] == a["jobId"]:
            return {"jobId": a["jobId"], "replayed": True}
        if hold["job_name"] is not None:
            raise Refused({"jobMismatch"}, "adapter", "the hold already funds another job")
        if self.hold_row(a["reservationId"])["job_id"] != hold["job"]:
            raise RuntimeError("the hold has no job")
        hold["job_name"] = a["jobId"]
        return {"jobId": a["jobId"], "replayed": False}

    def op_topup(self, a: dict) -> dict:
        rid, vq, credits = a["reservationId"], a["quoteId"], a["credits"]
        hold, q = self.holds[rid], self.quotes[vq]
        if type(credits) is not int:
            raise Refused({"badAmount"}, "adapter", "credits are integers")
        key = f"topup:{vq}:{credits}"
        if (vq, credits) in hold["topups"] or vq == hold["initial"]:
            out = self.accept_sql(vq, a["at"], key, credits)   # a replay, or already_accepted for the initial quote
            return {"reservationId": rid, "reservedCredits": self.credits(rid)["reservedCredits"],
                    "replayed": out.get("replayed"), "balance": self.balance()}
        if vq == hold["current"]:
            raise Refused({"idempotencyConflict"}, "adapter", "the hold's current quote cannot top it up again")
        if self.hold_row(rid)["state"] != "held":
            raise Refused({"reservationClosed"}, "sql", "the hold is closed (read from usage_reservations)")
        if not credits <= q["capCredits"]:
            raise Refused({"overCap"}, "adapter", "a top-up above the new quote's cap")
        if self.job_state(hold["job"]) != "budget_exceeded":
            self.set_state(hold["job"], "budget_exceeded")   # the Workflow stops the job before the owner re-quotes
        if q["sql"] is None or q["sql"]["supersedes"] is None or self.is_accepted(vq):
            self.create_sql_quote(vq)   # a re-quote after budget_exceeded supersedes the hold's quote (story 186)
        self.price(vq, credits)
        out = self.accept_sql(vq, a["at"], key, credits)
        hold["topups"].add((vq, credits))
        hold["current"] = vq
        return {"reservationId": rid, "reservedCredits": self.credits(rid)["reservedCredits"],
                "replayed": out.get("replayed"), "balance": self.balance()}

    def op_consume(self, a: dict) -> dict:
        hold = self.holds[a["reservationId"]]
        for field in ("credits", "attempt"):
            if type(a[field]) is not int:
                raise Refused({"badAmount"}, "adapter", f"{field} is an integer")
        if hold["job_name"] is None:
            raise Refused({"jobMismatch"}, "adapter", "the vector has not named the hold's job yet")
        job = hold["job"] if a["jobId"] == hold["job_name"] else str(uuid.uuid4())   # another job: unknown to SQL
        stage = STAGE_OF_STATE.get(a["stage"], a["stage"])   # a misspelled stage reaches the enum as written
        if a["stage"] in STAGE_OF_STATE and job == hold["job"]:
            self.walk(job, a["stage"])
        outputs = ([{"outputRef": "film", "bytes": 1000, "sha256": hashlib.sha256(b"film").hexdigest()}]
                   if stage == "final_render" else [])
        try:
            finished = self.run_stage(job, stage, a["attempt"], a["credits"] * CREDIT, outputs)
        except Refused as refused:
            if "budgetExceeded" in refused.codes and self.job_state(job) != "budget_exceeded":
                self.set_state(job, "budget_exceeded")   # the Workflow stops the job when a stage does not fit
            raise
        return {"consumedCredits": self.credits(a["reservationId"])["consumedCredits"], "replayed": finished["replayed"]}

    def op_release(self, a: dict) -> dict:
        rid = a["reservationId"]
        hold = self.holds[rid]
        if self.hold_row(rid)["state"] != "held":
            return {"releasedCredits": self.credits(rid)["releasedCredits"], "replayed": True, "balance": self.balance()}
        job = hold["job"]
        if a["outcome"] == "ready":
            film = self.db.value(f"(select id from public.artifacts where job_id = {lit(job)} and kind = 'film' "
                                 "order by created_at limit 1)")
            if film is None:
                self.walk(job, "final_rendering")
                done = self.db.value(f"(select count(*) from public.render_attempts where job_id = {lit(job)} "
                                     "and stage = 'final_render')")
                self.run_stage(job, "final_render", int(done) + 1, 0, [
                    {"outputRef": "film", "bytes": 1000, "sha256": hashlib.sha256(b"film").hexdigest()}])
                film = self.db.value(f"(select id from public.artifacts where job_id = {lit(job)} and kind = 'film' "
                                     "order by created_at limit 1)")
            self.walk(job, "verifying")
            verify = self.db.call("jovra_orchestrator", f"app_gateway.reserve_stage({lit(job)}, 'verify_output', 1, "
                                  "gen_random_uuid())")
            claim = self.db.call("jovra_orchestrator", f"app_gateway.claim_attempt({lit(verify['attemptId'])}, "
                                 "'ledger-host', 'cf-container', gen_random_uuid())")
            lease = hashlib.sha256(claim["leaseToken"].encode()).hexdigest()
            self.db.call("jovra_orchestrator", f"app_gateway.mark_artifact_verified({lit(verify['attemptId'])}, "
                         f"decode({lit(lease)}, 'hex'), {lit(film)}, '{{\"decoded\": true}}'::jsonb, gen_random_uuid())")
            self.db.call("jovra_orchestrator", f"app_gateway.finish_attempt({lit(verify['attemptId'])}, "
                         f"decode({lit(lease)}, 'hex'), 'succeeded', '[]'::jsonb, "
                         "'{\"wallMs\": 0, \"cpuMs\": 0, \"bytesIn\": 0, \"bytesOut\": 0}'::jsonb, null, null, null, "
                         "gen_random_uuid())")
            self.set_state(job, "ready")
        else:
            state = self.job_state(job)
            target = "failed_terminal" if (a["outcome"] == "failed"
                                           and self.tr.allowed(state, "failed_terminal", None)) else "canceled"
            self.set_state(job, target)
        return {"releasedCredits": self.credits(rid)["releasedCredits"], "replayed": False, "balance": self.balance()}

    # run ---------------------------------------------------------------------------------------------------------
    def replay(self, checks: Checks, tally: dict) -> None:
        ops = {"accept": self.op_accept, "reserve": self.op_reserve, "attachJob": self.op_attach,
               "topup": self.op_topup, "consume": self.op_consume, "release": self.op_release}
        self.setup()
        for step in self.v["steps"]:
            label = f"{self.v['id']} step {step['step']} {step['op']}"
            expect = step["expect"]
            try:
                got = ops[step["op"]](step["args"])
            except Refused as refused:
                tally[refused.layer] = tally.get(refused.layer, 0) + 1
                checks.check(expect.get("rejectCode") in refused.codes,
                             f"{label}: refused by {refused.layer} as {expect.get('rejectCode', 'nothing expected')}",
                             refused.detail)
                continue
            tally["sql"] = tally.get("sql", 0) + 1
            wrong = {k: (got.get(k), v) for k, v in expect.items() if got.get(k) != v}
            checks.check("rejectCode" not in expect and not wrong, f"{label}: {json.dumps(expect, sort_keys=True)}",
                         f"got/expected {wrong}" if wrong else ("accepted, expected " + str(expect.get("rejectCode"))
                                                                if "rejectCode" in expect else ""))
        final = {"balance": self.balance(), "reservations": {rid: self.credits(rid) for rid in sorted(self.holds)}}
        checks.check(final == self.v["final"], f"{self.v['id']}: final balances from usage_reservations",
                     "" if final == self.v["final"] else f"{final} != {self.v['final']}")


def check_transitions(db: Db, checks: Checks, tr: Transitions) -> None:
    rows = json.loads(db.value(
        "(select json_agg(json_build_array(f, t, app_private.job_transition_allowed(f, t, null), "
        "app_private.job_transition_allowed(f, t, t))) from unnest(enum_range(null::public.job_state)) f "
        "cross join unnest(enum_range(null::public.job_state)) t)"))
    drift = [(f, t, a, b) for f, t, a, b in rows
             if a != tr.allowed(f, t, None) or b != tr.allowed(f, t, t)]
    checks.check(not drift and len(rows) == len(tr.states) ** 2,
                 f"job_transition_allowed equals the contract for all {len(rows)} pairs of job states "
                 "(with and without a stored resume state)", f"drift {drift[:6]}" if drift else "")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    env = read_env(sys.argv[1])
    db_url = env.get("DB_URL", "")
    if "127.0.0.1" not in db_url and "localhost" not in db_url:
        print("FAIL  the env file must name the local stack (DB_URL on 127.0.0.1)")
        return 2
    db, checks, run = Db(db_url), Checks(), uuid.uuid4().hex[:8]
    vectors = json.loads(VECTORS.read_text(encoding="utf-8"))
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    states = json.loads(db.value("(select json_agg(s) from unnest(enum_range(null::public.job_state)) s)"))
    tr = Transitions(contract, states)
    check_transitions(db, checks, tr)

    floors = {stage: 2 * CREDIT for stage in ("normalize", "sync", "analyze", "plan", "validate", "preview_render",
                                               "final_render")}
    env_row = db.value("(select count(*) from app_ops.spend_limits where scope = 'environment')") == "0"
    setup = ["begin;", "grant jovra_gateway to postgres;", "grant jovra_orchestrator to postgres;",
             f"insert into app_ops.rate_cards (rates_version, wall_second_micro_usd, input_mtok_micro_usd, "
             f"cache_mtok_micro_usd, output_mtok_micro_usd, image_tokens, planner_max_images, planner_max_input_tokens, "
             f"planner_max_output_tokens, planner_effort) values ('{RATES}', 1000, 0, 0, 0, 0, 0, 0, 0, 'none');",
             "insert into app_ops.stage_rates (rates_version, stage, floor_micro_usd) "
             f"select '{RATES}', s, case s::text {' '.join(f'when {lit(k)} then {v}' for k, v in floors.items())} "
             "else 1 end from unnest(enum_range(null::public.job_stage)) s;"]
    if env_row:
        setup.append("insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd) "
                     "values ('environment', null, 1000000000000, 1000000000000);")
    setup.append("commit;")
    _, error = db.run("\n".join(setup))
    if not checks.check(error is None, "setup: the ledger rate card (2-credit stage floors, 1,000 micro-USD per "
                                       "container second) and the command-role grants", str(error or "")):
        return 1

    tally: dict[str, int] = {}
    owners: list[str] = []
    try:
        for index, vector in enumerate(vectors["cases"]):
            case = Case(db, vector, run, index, tr)
            owners.append(case.owner_name)
            try:
                case.replay(checks, tally)
            except (RuntimeError, KeyError) as exc:
                checks.check(False, f"{vector['id']}: replay error", str(exc)[-400:])
    finally:
        names = ", ".join(lit(o) for o in owners) or "''"
        cleanup = ["begin;", f"delete from auth.users where raw_user_meta_data ->> 'test_identifier' in ({names});",
                   f"delete from app_ops.rate_cards where rates_version = '{RATES}';",
                   "insert into app_ops.settings (env) values ('local') on conflict (id) do update set env = excluded.env;"]
        if env_row:
            cleanup.append("delete from app_ops.spend_limits where scope = 'environment';")
        cleanup += ["revoke jovra_gateway from postgres;", "revoke jovra_orchestrator from postgres;", "commit;"]
        _, error = db.run("\n".join(cleanup))
        checks.check(error is None, "cleanup: users (cascading projects, quotes, holds, jobs), rate card, environment",
                     str(error or ""))
    print(f"ledger vectors: {len(vectors['cases'])} cases; step outcomes decided by "
          + ", ".join(f"{layer} {n}" for layer, n in sorted(tally.items())))
    print("ledger vectors: all checks passed" if checks.failed == 0 else f"ledger vectors: {checks.failed} check(s) failed")
    return 1 if checks.failed else 0


if __name__ == "__main__":
    sys.exit(main())
