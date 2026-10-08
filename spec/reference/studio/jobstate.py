"""Reference RenderJob state machine (contract: spec/studio/contracts/render-job-transitions.v1.json).

check_transition() decides one step; replay() re-runs a job's whole history and checks the stored record against it.
Resumable states remember the stage to return to (resumeStage); a retry also consumes an attempt. Terminal states
accept nothing but deletion (and deleted accepts nothing). Paid stages need a reservation, and ready needs a
verified delivered artifact, so a partial failure can never surface as a download-ready film.
"""

from __future__ import annotations

import json
from pathlib import Path

from .core import Reject, require, when

CONTRACT = Path(__file__).resolve().parents[2] / "studio" / "contracts" / "render-job-transitions.v1.json"


def load_contract(path: Path = CONTRACT) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class Machine:
    def __init__(self, contract: dict):
        self.c = contract
        self.states = set(contract["states"])
        self.terminal = set(contract["terminal"])

    def resume_stages(self, state: str) -> set:
        """The stages a job in `state` may remember as resumeStage (empty: it must remember none)."""
        return set({"paused": self.c["pausableFrom"], "failed_retryable": self.c["retryableFrom"],
                    "budget_exceeded": self.c["budgetExceededFrom"]}.get(state, []))

    def check_transition(self, job: dict, to: str, *, has_reservation: bool, verified_artifact: bool) -> dict:
        """job: {"state", "resumeStage", "attempt", "maxAttempts"}. Returns the updated fields or raises Reject.

        A stored resumeStage is never trusted: it must be a stage the current state can return to (pausableFrom,
        retryableFrom or budgetExceededFrom), so ready, deleted or any terminal state can never be "resumed" into,
        and every other state stores none. A service calling this on a stored row gets the same answer as replay()."""
        state = job["state"]
        require(to in self.states, "unknownState", f"unknown state {to!r}")
        require(state in self.states, "unknownState", f"unknown state {state!r}")
        allowed = self.resume_stages(state)
        if allowed:
            require(job["resumeStage"] in allowed, "badResumeStage",
                    f"{state} cannot resume to {job['resumeStage']!r}")
        else:
            require(job["resumeStage"] is None, "badResumeStage", f"{state} remembers no resume stage")
        nxt = {"state": to, "resumeStage": job["resumeStage"], "attempt": job["attempt"]}
        if to == "deleted":
            require(state != "deleted", "terminalState", "a deleted job accepts no transition")
            nxt["resumeStage"] = None
            return nxt
        require(state not in self.terminal, "terminalState", f"{state} is terminal")
        if to == "canceled":
            nxt["resumeStage"] = None
            return nxt
        if to == "paused":
            require(state in self.c["pausableFrom"], "illegalTransition", f"cannot pause from {state}")
            nxt["resumeStage"] = state
            return nxt
        if to == "failed_retryable":
            require(state in self.c["retryableFrom"], "illegalTransition", f"cannot fail-retryably from {state}")
            nxt["resumeStage"] = state
            return nxt
        if to == "failed_terminal":
            require(state in self.c["terminalFailureFrom"], "illegalTransition", f"cannot fail from {state}")
            nxt["resumeStage"] = None
            return nxt
        if to == "budget_exceeded":
            require(state in self.c["budgetExceededFrom"], "illegalTransition", f"no budget check at {state}")
            nxt["resumeStage"] = state
            return nxt
        if state in ("paused", "failed_retryable") and to == job["resumeStage"]:
            if state == "failed_retryable":
                require(job["attempt"] < job["maxAttempts"], "retriesExhausted", "no attempts left; fail terminally")
                nxt["attempt"] = job["attempt"] + 1
            nxt["resumeStage"] = None
            self._guards(to, has_reservation, verified_artifact)
            return nxt
        require(to in self.c["forward"].get(state, []), "illegalTransition", f"{state} -> {to} is not allowed")
        if state in ("quote_expired", "budget_exceeded"):
            nxt["resumeStage"] = None   # a re-quote starts a new consent; nothing is resumed automatically
        self._guards(to, has_reservation, verified_artifact)
        return nxt

    def _guards(self, to: str, has_reservation: bool, verified_artifact: bool) -> None:
        if to in self.c["reservationRequiredFrom"]:
            require(has_reservation, "reservationRequired", f"{to} spends and needs an accepted reservation")
        if to == "ready":
            require(verified_artifact, "unverifiedReady", "ready needs a verified delivered artifact")

    def replay(self, job: dict, *, verified_artifact: bool) -> dict:
        """Re-run a RenderJob record's history; the stored state, resumeStage and attempt must equal the result."""
        history = job["history"]
        require(history and history[0]["from"] is None and history[0]["to"] == self.c["initial"], "badHistory",
                "history starts with null -> draft")
        cur = {"state": self.c["initial"], "resumeStage": None, "attempt": 1, "maxAttempts": job["maxAttempts"]}
        has_reservation = job["reservationId"] is not None
        for i, step in enumerate(history[1:], start=1):
            require(step["seq"] == i and step["from"] == cur["state"], "badHistory",
                    f"history step {i} does not continue from {cur['state']}")
            require(when(step["at"]) >= when(history[i - 1]["at"]), "badHistory", "history timestamps go backwards")
            cur = dict(cur, **self.check_transition(cur, step["to"], has_reservation=has_reservation,
                                                    verified_artifact=verified_artifact))
        for key in ("state", "resumeStage", "attempt"):
            require(job[key] == cur[key], "stateMismatch", f"stored {key} {job[key]!r} but history gives {cur[key]!r}")
        if job.get("stageProgress"):
            require(job["stageProgress"]["stage"] == job["state"], "stateMismatch",
                    "stage progress is reported for the active stage only")
        return cur


def run_vector(machine: Machine, case: dict) -> None:
    """A transition vector: start state fields + target + flags -> expected new fields or rejection code."""
    job = dict({"resumeStage": None, "attempt": 1, "maxAttempts": 3}, **case["from"])
    try:
        got = machine.check_transition(job, case["to"], has_reservation=case.get("hasReservation", True),
                                       verified_artifact=case.get("verifiedArtifact", False))
    except Reject as exc:
        if "rejectCode" not in case["expect"]:
            raise
        require(exc.code == case["expect"]["rejectCode"], "vectorMismatch",
                f"{case['id']}: expected {case['expect']['rejectCode']}, got {exc.code}")
        return
    require("rejectCode" not in case["expect"], "vectorMismatch", f"{case['id']}: transition accepted, expected "
            f"{case['expect'].get('rejectCode')}")
    for key, value in case["expect"].items():
        require(got[key] == value, "vectorMismatch", f"{case['id']}: {key} {got[key]!r} != {value!r}")
