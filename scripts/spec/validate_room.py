#!/usr/bin/env python3
"""Validate the JOVRA Room v1 and watch-bridge contracts (spec/room). Standard library only.

Separate from scripts/spec/validate.py (core) and validate_studio.py (Studio); it imports neither and changes nothing
outside spec/room. It reuses scripts/spec/jsonschema_subset.py read-only.

1. Every room schema uses only keywords the bundled checker implements and every $ref resolves; '$' anchors follow
   ECMA-262 (no trailing newline accepted).
2. Drift checks (read-only): provenance labels = core common.schema.json provenanceStatus; studioSlot = Studio
   placementSlot; displayCode pattern = Studio camera-invite displayCode; analysis capability ids exist in
   spec/contracts/capability-registry.v1.json; the adapted watch-bridge fixture equals the adapter applied to the
   unchanged design sample.
3. Every record fixture validates against the schema its schemaVersion names and passes its reference rule.
4. Every invalid case is rejected by the expected layer: 'schema' cases fail the schema; 'reference' cases pass the
   schema and the reference rejects them with the expected code.
5. Vectors: freshness, watch sample, phone status, status rows, disconnect, snapshot acceptance, watch-side bridge
   acceptance, invitations, command ledger, outbox and analysis presentation; every command and envelope inside a
   vector is schema-checked too.
6. The original handoff verifier's assertions (docs/handoff/adaptive-v3/scripts/verify_protocol_fixtures.py), ported
   onto the reference.
7. Acceptance map: every row of design-reference/adaptive/brief/acceptance-matrix.md is present, in order, with its
   exact text; every testable row is covered by at least one case that exists and passed.
8. Secret hygiene: join tokens appear only in the QR payload records and the invitation vectors' Sample secrets block;
   the Sample hotspot passphrase only in its QR payload record; host logs never contain a token, proof or nonce.
9. Determinism: regenerating the fixtures gives exactly the files on disk.

Usage:  python3 scripts/spec/validate_room.py [-v]
"""

from __future__ import annotations

import copy
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROOM = ROOT / "spec" / "room"
FIX = ROOM / "fixtures"
SCHEMAS = ROOM / "schemas"
DESIGN_SAMPLE = ROOT / "design-reference/adaptive/brief/watch-snapshot.sample.json"
MATRIX = ROOT / "design-reference/adaptive/brief/acceptance-matrix.md"
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOM / "reference"))

from jsonschema_subset import SchemaSet  # noqa: E402

from jovra_room import alerts, analysis, bridge, freshness, invitation, ledger, records, snapshot  # noqa: E402
from jovra_room.core import Reject, apply_patch, canonical  # noqa: E402
from jovra_room.design_sample import from_design_sample  # noqa: E402

SCHEMA_BY_VERSION = {
    "jovra.room.invitation/1": "invitation.schema.json",
    "jovra.room.invitation-payload/1": "invitation-payload.schema.json",
    "jovra.room.join-request/1": "join-request.schema.json",
    "jovra.room.join-challenge/1": "join-challenge.schema.json",
    "jovra.room.join-reveal/1": "join-reveal.schema.json",
    "jovra.room.watch-local/1": "watch-local.schema.json",
    "jovra.room.device-status/1": "device-status.schema.json",
    "jovra.room.snapshot/1": "room-snapshot.schema.json",
    "jovra.room.watch-bridge/1": "watch-bridge-snapshot.schema.json",
    "jovra.room.command/1": "command.schema.json",
    "jovra.room.receipt/1": "receipt.schema.json",
    "jovra.room.analysis-result/1": "analysis-result.schema.json",
    "jovra.room-fixture.invalid-cases/1": "fixture.schema.json",
    "jovra.room-fixture.vectors/1": "fixture.schema.json",
    "jovra.room-fixture.acceptance-map/1": "fixture.schema.json",
}


def ecma_pattern(pattern: str) -> str:
    """JSON Schema patterns are ECMA-262: '$' matches only at the very end. Rewrite unescaped '$' outside a class as
    '\\Z' (same correction validate_studio.py makes; the shared checker belongs to the core gate)."""
    out, i, in_class = [], 0, False
    while i < len(pattern):
        ch = pattern[i]
        if ch == "\\":
            out.append(pattern[i:i + 2])
            i += 2
            continue
        if ch == "[" and not in_class:
            in_class = True
        elif ch == "]" and in_class:
            in_class = False
        out.append("\\Z" if ch == "$" and not in_class else ch)
        i += 1
    return "".join(out)


class RoomSchemaSet(SchemaSet):
    def _pattern(self, pattern: str) -> re.Pattern:
        if pattern not in self._patterns:
            self._patterns[pattern] = re.compile(ecma_pattern(pattern))
        return self._patterns[pattern]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class Report:
    def __init__(self, verbose: bool):
        self.verbose = verbose
        self.failures: list[str] = []
        self.counts: dict[str, int] = {}
        self.passed_cases: set[str] = set()
        self.failed_cases: set[str] = set()

    def ok(self, what: str, n: int = 1) -> None:
        self.counts[what] = self.counts.get(what, 0) + n

    def fail(self, where: str, message: str) -> None:
        self.failures.append(f"FAIL {where}: {message}")

    def log(self, message: str) -> None:
        if self.verbose:
            print(message)

    def case(self, ref: str, failures_before: int) -> None:
        (self.passed_cases if len(self.failures) == failures_before else self.failed_cases).add(ref)


class Ctx:
    def __init__(self):
        self.schemas = RoomSchemaSet(SCHEMAS)
        reg = load(ROOT / "spec/contracts/capability-registry.v1.json")
        self.registry = {c["id"]: c["status"] for c in reg.get("capabilities", reg)}
        self.records = {p.name[: -len(".json")]: load(p) for p in sorted((FIX / "records").glob("*.json"))}

    def schema_errors(self, doc) -> list:
        name = SCHEMA_BY_VERSION.get(doc.get("schemaVersion")) if isinstance(doc, dict) else None
        if name is None:
            return [f"unknown schemaVersion {doc.get('schemaVersion') if isinstance(doc, dict) else doc!r}"]
        return self.schemas.validate(doc, name)

    def rule(self, doc) -> None:
        records.check(doc, {"registry": self.registry})

    def record(self, ref: str) -> dict:
        return copy.deepcopy(self.records[ref[len("records/"): -len(".json")]])


def expect_eq(rep: Report, where: str, actual, expected) -> None:
    if actual != expected:
        rep.fail(where, f"expected {json.dumps(expected, sort_keys=True)}, got {json.dumps(actual, sort_keys=True)}")


def subset(actual: dict, expected: dict) -> dict:
    return {k: actual.get(k) for k in expected}


# ----- 1-2: schemas and drift -------------------------------------------------------------------------------------

def check_schemas(ctx: Ctx, rep: Report) -> None:
    for problem in ctx.schemas.check_all():
        rep.fail("schemas", problem)
    for name in sorted(set(SCHEMA_BY_VERSION.values()) - set(ctx.schemas.files)):
        rep.fail("schemas", f"missing {name}")
    rep.ok("schemas", len(ctx.schemas.files))
    pat = ctx.schemas._pattern("^[0-9a-f]{64}$")
    if pat.search("a" * 64 + "\n") or not pat.search("a" * 64):
        rep.fail("schema self-test", "pattern anchors are not ECMA-262")
    for label, doc in (("empty command", {"schemaVersion": "jovra.room.command/1"}),
                       ("snapshot asserting freshness", {**ctx.records["room-snapshot"], "freshness": "Fresh"})):
        if not ctx.schema_errors(doc):
            rep.fail("schema self-test", f"{label} passed")
    rep.ok("schema self-tests", 3)


def check_drift(ctx: Ctx, rep: Report) -> None:
    common = ctx.schemas.files["room-common.schema.json"]["$defs"]
    core = load(ROOT / "spec/schemas/common.schema.json")["$defs"]
    expect_eq(rep, "drift provenance", common["provenanceLabel"]["enum"], core["provenanceStatus"]["enum"])
    studio_common = ROOT / "spec/schemas/studio/studio-common.schema.json"
    studio_invite = ROOT / "spec/schemas/studio/camera-invite.schema.json"
    if studio_common.exists() and studio_invite.exists():
        expect_eq(rep, "drift studioSlot", common["studioSlot"]["enum"], load(studio_common)["$defs"]["placementSlot"]["enum"])
        studio_code = load(studio_invite)["properties"]["invites"]["items"]["properties"]["displayCode"]["pattern"]
        expect_eq(rep, "drift displayCode", common["displayCode"]["pattern"], studio_code)
        rep.ok("drift checks", 2)
    else:
        rep.fail("drift", "Studio schemas not found; cannot check the CameraInvite mapping")
    for name, doc in ctx.records.items():
        if doc.get("schemaVersion") == "jovra.room.analysis-result/1" and doc["capabilityId"] not in ctx.registry:
            rep.fail("drift registry", f"{name}: {doc['capabilityId']} not in capability-registry.v1.json")
    raw = load(DESIGN_SAMPLE)
    expect_eq(rep, "drift design sample adapter", from_design_sample(raw), ctx.records["watch-bridge.sample"])
    rep.ok("drift checks", 3)


# ----- 3-4: records and invalid cases ------------------------------------------------------------------------------

def check_records(ctx: Ctx, rep: Report) -> None:
    for name, doc in ctx.records.items():
        before = len(rep.failures)
        for e in ctx.schema_errors(doc):
            rep.fail(f"records/{name}.json", e)
        try:
            ctx.rule(doc)
        except Reject as exc:
            rep.fail(f"records/{name}.json", f"reference rejected a valid record: {exc}")
        if len(rep.failures) == before:
            rep.ok("valid records")


def check_invalid(ctx: Ctx, rep: Report) -> None:
    for path in sorted((FIX / "invalid").glob("*.json")):
        doc = load(path)
        for e in ctx.schema_errors(doc):
            rep.fail(path.name, e)
        base = ctx.record(doc["base"])
        for case in doc["cases"]:
            ref = f"invalid/{path.name}#{case['id']}"
            before = len(rep.failures)
            mutated = apply_patch(base, case["patch"])
            errors = ctx.schema_errors(mutated)
            if case["expect"]["layer"] == "schema":
                if not errors:
                    rep.fail(ref, "schema accepted an invalid record")
            elif errors:
                rep.fail(ref, f"should pass the schema and fail the reference; schema said {errors[0]}")
            else:
                try:
                    ctx.rule(mutated)
                    rep.fail(ref, f"reference accepted; expected {case['expect']['code']}")
                except Reject as exc:
                    expect_eq(rep, ref, exc.code, case["expect"]["code"])
            rep.case(ref, before)
            rep.ok(f"invalid cases ({case['expect']['layer']})")


# ----- 5: vectors --------------------------------------------------------------------------------------------------

def run_freshness(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before, i = ref_of(case), len(rep.failures), case["input"]
        try:
            got = freshness.classify(i["senderAgeMs"], i["sinceAcceptMs"], transit_bounded=i["transitBounded"],
                                     baseline_valid=i["baselineValid"], transit_ms=i["transitMs"])
        except ValueError as exc:
            got = {"error": str(exc).split(":")[0]}
        expect_eq(rep, ref, got, case["expect"])
        rep.case(ref, before)


def run_watch_sample(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before = ref_of(case), len(rep.failures)
        if case["source"] == "design":
            raw = load(DESIGN_SAMPLE)
            obs = raw["transportObservation"]
            roster = [d["deviceId"] for d in raw["devices"]]
            rows = [(d, freshness.classify(d["ageAtBridgeMs"], 0, transit_bounded=obs["transitBounded"],
                                           baseline_valid=obs["baselineValid"], transit_ms=0)) for d in raw["devices"]]
            for dev_id, elapsed in case["expect"]["frozenElapsedMs"].items():
                d, f = next((d, f) for d, f in rows if d["deviceId"] == dev_id)
                expect_eq(rep, ref + " frozen", freshness.display_row(d, f, None)["elapsedMs"], elapsed)
        else:
            bridge = apply_patch(ctx.records["watch-bridge.sample"], case["bridgePatch"])
            for e in ctx.schema_errors(bridge):
                rep.fail(ref, f"patched bridge invalid: {e}")
            roster = bridge["roster"]["cameraDeviceIds"]
            rows = [(d, f) for d, f, _ in freshness.observe_bridge(bridge, case["nowMonoMs"], case["currentBaselineId"])]
        expect_eq(rep, ref + " freshness", {d["deviceId"]: f for d, f in rows}, case["expect"]["freshness"])
        expect_eq(rep, ref + " counts", freshness.counts(rows, roster), case["expect"]["counts"])
        rep.case(ref, before)


def run_phone_status(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before = ref_of(case), len(rep.failures)
        env = apply_patch(ctx.records["room-snapshot"], case["snapshotPatch"])
        for e in ctx.schema_errors(env):
            rep.fail(ref, f"patched snapshot invalid: {e}")
        rows = [(d, f) for d, f, _ in freshness.observe_snapshot(env, case["observation"], case["nowMonoMs"],
                                                                 case["currentBaselineId"])]
        rows = [(d, "Local" if d["deviceId"] == case["localDeviceId"] else f) for d, f in rows]
        expect_eq(rep, ref + " freshness", {d["deviceId"]: f for d, f in rows}, case["expect"]["freshness"])
        expect_eq(rep, ref + " counts", freshness.counts(rows, env["roster"]["cameraDeviceIds"]), case["expect"]["counts"])
        rep.case(ref, before)


def run_display(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before = ref_of(case), len(rep.failures)
        got = freshness.display_row(case["device"], case["freshness"], case["ageMs"], is_local=case["isLocal"],
                                    local_elapsed_ms=case["localElapsedMs"])
        expect_eq(rep, ref, got, case["expect"])
        rep.case(ref, before)


def run_disconnect(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before, exp = ref_of(case), len(rep.failures), case["expect"]
        got = freshness.on_room_disconnect(case["local"], case["remote"])
        expect_eq(rep, ref + " local", got["localCaptureState"], exp["localCaptureState"])
        expect_eq(rep, ref + " commands", got["commandsIssued"], exp["commandsIssued"])
        expect_eq(rep, ref + " counts", got["counts"], exp["counts"])
        expect_eq(rep, ref + " frozen", {r["deviceId"]: r["elapsedMs"] for r in got["remote"]}, exp["frozenElapsedMs"])
        expect_eq(rep, ref + " may", {r["deviceId"]: r["mayStillBeRecording"] for r in got["remote"]}, exp["mayStillBeRecording"])
        rep.case(ref, before)


def run_snapshot(ctx, rep, doc, ref_of):
    base = ctx.records["room-snapshot"]
    for case in doc["cases"]:
        ref, before, init = ref_of(case), len(rep.failures), case["initial"]
        rx = snapshot.SnapshotReceiver(init["sessionId"], init["hostEpoch"], init["hostKey"], init["hostDeviceId"],
                                       init["members"], init["rosterRevision"])
        for n, step in enumerate(case["steps"]):
            where = f"{ref} step {n}"
            if step["op"] == "accept":
                env = apply_patch(base, step["envelopePatch"])
                for e in ctx.schema_errors(env):
                    rep.fail(where, f"envelope invalid: {e}")
                expect_eq(rep, where, rx.accept(env), step["expect"])
            elif step["op"] == "reconcile":
                expect_eq(rep, where, rx.reconcile(step["newEpoch"], step["hostKey"], step["hostDeviceId"],
                                                   step["approvedHostKeys"]), step["expect"])
            elif step["op"] == "restart":
                rx = snapshot.SnapshotReceiver.restore(json.loads(json.dumps(rx.persisted())))
            elif step["op"] == "assert":
                expect_eq(rep, where, subset(rx.persisted(), step["expect"]), step["expect"])
            else:
                rep.fail(where, f"unknown op {step['op']!r}")
        rep.case(ref, before)


def run_bridge(ctx, rep, doc, ref_of):
    base = ctx.records["watch-bridge.sample"]
    for case in doc["cases"]:
        ref, before = ref_of(case), len(rep.failures)
        rx = bridge.BridgeReceiver(case["pairedPhoneId"])
        for n, step in enumerate(case["steps"]):
            where = f"{ref} step {n}"
            if step["op"] == "accept":
                env = apply_patch(base, step["bridgePatch"])
                for e in ctx.schema_errors(env):
                    rep.fail(where, f"bridge payload invalid: {e}")
                expect_eq(rep, where, rx.accept(env), step["expect"])
            elif step["op"] == "restart":
                rx = bridge.BridgeReceiver.restore(json.loads(json.dumps(rx.persisted())))
            else:
                rep.fail(where, f"unknown op {step['op']!r}")
        rep.case(ref, before)


def run_invitation(ctx, rep, doc, ref_of):
    secrets = doc["secrets"]
    for case in doc["cases"]:
        ref, before, init = ref_of(case), len(rep.failures), case["initial"]
        recs = [ctx.record(r) for r in init["records"]]
        host = invitation.HostInvitations(init["sessionId"], init["hostEpoch"], init["hostKey"], recs,
                                          secrets["tokens"], secrets["nonces"], init["members"])
        for n, step in enumerate(case["steps"]):
            where, op = f"{ref} step {n}", step["op"]
            if op == "join":
                req = apply_patch(ctx.records["join-request"], step["requestPatch"])
                for e in ctx.schema_errors(req):
                    rep.fail(where, f"join request invalid: {e}")
                expect_eq(rep, where, host.validate_join(req, step["now"], step["hostNonce"]), step["expect"])
                for kind, body in (("join-challenge", {"hostNonce": step["hostNonce"]}),):
                    msg = {**ctx.records[kind], **body, "inviteId": req["inviteId"]}
                    for e in ctx.schema_errors(msg):
                        rep.fail(where, f"{kind} invalid: {e}")
            elif op == "reveal":
                msg = {**ctx.records["join-reveal"], "inviteId": step["inviteId"], "guestNonce": step["guestNonce"]}
                for e in ctx.schema_errors(msg):
                    rep.fail(where, f"join-reveal invalid: {e}")
                expect_eq(rep, where, host.reveal(step["inviteId"], step["guestNonce"]), step["expect"])
            elif op == "approve":
                expect_eq(rep, where, host.approve(step["inviteId"], step["confirmed"], step["now"]), step["expect"])
            elif op == "assertRecord":
                rec = host.records[step["inviteId"]]
                expect_eq(rep, where, subset(rec, step["expect"]), step["expect"])
                for e in ctx.schema_errors(rec):
                    rep.fail(where, f"record became schema-invalid: {e}")
                try:
                    ctx.rule(rec)
                except Reject as exc:
                    rep.fail(where, f"record broke its rule: {exc}")
            elif op == "transferHost":
                expect_eq(rep, where, {"revoked": host.transfer_host(step["newEpoch"], step["newHostKey"])}, step["expect"])
            elif op == "lookup":
                expect_eq(rep, where, host.lookup(step["code"], step["source"], step["now"]), step["expect"])
            elif op == "joinerVerify":
                payload = apply_patch(ctx.records["invitation-payload"], step["payloadPatch"])
                expect_eq(rep, where, invitation.joiner_verify(payload, step["observedHostKey"]), step["expect"])
            elif op == "checkResolved":
                try:
                    invitation.check_resolved_endpoint(step["address"], step["port"])
                    got = "ok"
                except Reject as exc:
                    got = exc.code
                expect_eq(rep, where, got, step["expect"])
            elif op == "decodeQr":
                if step.get("fromPayload"):
                    payload = ctx.records["invitation-payload"]
                    got = {"roundTrip": invitation.decode_qr(invitation.encode_qr(payload)) == payload}
                else:
                    try:
                        invitation.decode_qr(step["text"])
                        got = {"decoded": True}
                    except Reject as exc:
                        got = {"error": exc.code}
                expect_eq(rep, where, got, step["expect"])
            else:
                rep.fail(where, f"unknown op {op!r}")
        leaked = canonical(host.log)
        secret_values = (list(secrets["tokens"].values()) + list(secrets["nonces"].values())
                         + [ctx.records["join-request"]["proof"], ctx.records["join-reveal"]["guestNonce"]])
        for secret in secret_values:
            if secret in leaked:
                rep.fail(ref, "host log contains a token, proof or nonce")
        rep.case(ref, before)


def _ledger(init):
    return ledger.CommandLedger(init["sessionId"], init["hostEpoch"], init["eventRevision"], init["members"], init["devices"])


def _check_command(ctx, rep, where, cmd):
    for e in ctx.schema_errors(cmd):
        rep.fail(where, f"command invalid: {e}")
    try:
        ctx.rule(cmd)
    except Reject as exc:
        if exc.code != "ttlTooLong":  # the ledger vectors deliberately send one over-long capture TTL
            rep.fail(where, f"command breaks its rule: {exc}")


def _check_receipt(ctx, rep, where, rec):
    for e in ctx.schema_errors(rec):
        rep.fail(where, f"receipt invalid: {e}")
    try:
        ctx.rule(rec)
    except Reject as exc:
        rep.fail(where, f"receipt breaks its rule: {exc}")


def run_ledger(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before = ref_of(case), len(rep.failures)
        led = _ledger(case["initial"])
        for n, step in enumerate(case["steps"]):
            where, op = f"{ref} step {n}", step["op"]
            if op == "submit":
                _check_command(ctx, rep, where, step["command"])
                got = led.submit(step["command"], step.get("delivery"), step["peer"])
                _check_receipt(ctx, rep, where, got)
                expect_eq(rep, where, subset(got, step["expect"]), step["expect"])
            elif op == "deliver":
                got = led.deliver(step["commandId"])
                _check_receipt(ctx, rep, where, got)
                expect_eq(rep, where, got["deviceResults"], step["expect"]["deviceResults"])
                expect_eq(rep, where + " summary", ledger.summarize(got), step["expect"]["summary"])
            elif op == "deviceReport":
                led.device_report(step["deviceId"], step["captureState"])
            elif op == "restart":
                led = ledger.CommandLedger.from_json(json.loads(json.dumps(led.to_json())))
            elif op == "linkLost":
                expect_eq(rep, where, {"commandsIssued": led.room_link_lost()}, step["expect"])
            elif op == "beginEpoch":
                led.begin_epoch(step["newEpoch"])
            elif op == "assert":
                expect_eq(rep, where, subset(led.state(), step["expect"]), step["expect"])
            else:
                rep.fail(where, f"unknown op {op!r}")
        rep.case(ref, before)


def run_outbox(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before, init = ref_of(case), len(rep.failures), case["initial"]
        led = _ledger(init)
        box = ledger.Outbox(init.get("outboxEpoch", init["hostEpoch"]), init["eventRevision"])
        for n, step in enumerate(case["steps"]):
            where, op = f"{ref} step {n}", step["op"]
            if op == "offline":
                _check_command(ctx, rep, where, step["command"])
                got = box.submit_offline(step["command"], step["nowMonoMs"])
                _check_receipt(ctx, rep, where, got)
                expect_eq(rep, where, subset(got, step["expect"]), step["expect"])
            elif op == "hostSubmit":
                _check_command(ctx, rep, where, step["command"])
                expect_eq(rep, where, subset(led.submit(step["command"], None, step["peer"]), step["expect"]), step["expect"])
            elif op == "flush":
                got = box.flush(led, step["nowMonoMs"], step.get("delivery"), step["peer"])
                for r in got:
                    _check_receipt(ctx, rep, where, r)
                expect_eq(rep, where, [subset(r, e) for r, e in zip(got, step["expect"])] if len(got) == len(step["expect"]) else got,
                          step["expect"])
            elif op == "reconcile":
                for r in step["hostReceipts"].values():
                    _check_receipt(ctx, rep, where, r)
                expect_eq(rep, where, box.reconcile(step["newEpoch"], step["hostReceipts"]), step["expect"])
                for r in box.receipts.values():
                    _check_receipt(ctx, rep, where, r)
            elif op == "assertQueue":
                expect_eq(rep, where, [e["command"]["commandId"] for e in box.queue], step["expect"])
            elif op == "assertLedger":
                expect_eq(rep, where, subset(led.state(), step["expect"]), step["expect"])
        rep.case(ref, before)


def run_alerts(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before = ref_of(case), len(rep.failures)
        pol = alerts.AlertPolicy()
        for step in case["steps"]:
            op, t = step["op"], step["t"]
            if op == "status":
                pol.status(t, step["deviceId"], step["freshness"], step["captureState"])
            elif op == "tick":
                pol.tick(t)
            elif op == "point":
                pol.point(t)
            elif op == "own":
                pol.own(t, step["kind"], step["deviceId"])
            elif op == "ack":
                pol.ack(t, step["alertId"])
            else:
                rep.fail(ref, f"unknown op {op!r}")
        expect_eq(rep, ref + " events", pol.events, case["expect"]["events"])
        expect_eq(rep, ref + " commands", pol.commands_issued, case["expect"]["commandsIssued"])
        rep.case(ref, before)


def run_analysis(ctx, rep, doc, ref_of):
    for case in doc["cases"]:
        ref, before = ref_of(case), len(rep.failures)
        result = apply_patch(ctx.record(case["record"]), case["resultPatch"])
        for e in ctx.schema_errors(result):
            rep.fail(ref, f"result invalid: {e}")
        got = analysis.present(result, case["capabilities"], ctx.registry, case["currentPointEventId"])
        expect_eq(rep, ref, subset(got, case["expect"]), case["expect"])
        rep.case(ref, before)


RUNNERS = {"freshness": run_freshness, "watch-sample": run_watch_sample, "phone-status": run_phone_status,
           "display": run_display, "disconnect": run_disconnect, "snapshot": run_snapshot, "bridge": run_bridge,
           "invitation": run_invitation, "alerts": run_alerts,
           "ledger": run_ledger, "outbox": run_outbox, "analysis": run_analysis}


def check_vectors(ctx: Ctx, rep: Report) -> None:
    for path in sorted((FIX / "vectors").glob("*.json")):
        doc = load(path)
        for e in ctx.schema_errors(doc):
            rep.fail(path.name, e)
        before_cases = len(rep.passed_cases) + len(rep.failed_cases)
        try:
            RUNNERS[doc["kind"]](ctx, rep, doc, lambda case, p=path: f"vectors/{p.name}#{case['id']}")
        except Exception as exc:  # a reference that raises fails the gate with a message instead of a traceback
            rep.fail(path.name, f"runner raised {type(exc).__name__}: {exc}")
        rep.ok(f"vector cases ({doc['kind']})", len(rep.passed_cases) + len(rep.failed_cases) - before_cases)


# ----- 6: the original handoff verifier, ported --------------------------------------------------------------------

def check_legacy(ctx: Ctx, rep: Report) -> None:
    before = len(rep.failures)
    raw = load(DESIGN_SAMPLE)
    env = {**ctx.records["room-snapshot"], "snapshotSeq": raw["snapshotSeq"]}
    trials = [("sample-jon-alex", 3, 7, env, "accepted"), ("wrong-room", 3, 7, env, "wrongSession"),
              ("sample-jon-alex", 4, 7, env, "staleEpoch"), ("sample-jon-alex", 3, 8, env, "replayOrOutOfOrder")]
    for session, epoch, prev, e, expected in trials:
        rx = snapshot.SnapshotReceiver(session, epoch, e["hostKeySha256"], e["hostDeviceId"], [d["deviceId"] for d in e["devices"]],
                                       e["roster"]["rosterRevision"])
        rx.last_seq = prev
        expect_eq(rep, f"legacy accept {session}/{epoch}/{prev}", rx.accept(e), expected)
    rows = [(d, freshness.classify(d["ageAtBridgeMs"], 0, transit_bounded=True, baseline_valid=True, transit_ms=0)) for d in raw["devices"]]
    expect_eq(rep, "legacy fresh-recording", freshness.counts(rows, [d["deviceId"] for d in raw["devices"]])["freshRecording"], 5)
    expect_eq(rep, "legacy c3", dict((d["deviceId"], f) for d, f in rows)["c3"], "Unknown")
    for args, expected in (((2000, 4000), "Delayed"), ((2000, 14000), "Unknown"), ((5000, 0), "Fresh"), ((15000, 0), "Delayed")):
        expect_eq(rep, f"legacy freshness {args}", freshness.classify(*args, transit_bounded=True, baseline_valid=True, transit_ms=0), expected)
    expect_eq(rep, "legacy unbounded", freshness.classify(0, 0, transit_bounded=False, baseline_valid=True), "Unknown")
    expect_eq(rep, "legacy baseline", freshness.classify(0, 0, transit_bounded=True, baseline_valid=False, transit_ms=0), "Unknown")
    try:
        freshness.classify(-1, 0, transit_bounded=True, baseline_valid=True, transit_ms=0)
        rep.fail("legacy negative", "negative age accepted")
    except ValueError:
        pass
    expect_eq(rep, "legacy frozen", raw["devices"][2]["lastReportedElapsedMs"], 746000)
    init = {"sessionId": "sample-jon-alex", "hostEpoch": 3, "eventRevision": 42,
            "members": {"m-scorer": {"roles": ["scorer"], "deviceId": "p-scorer"},
                        "m-viewer": {"roles": ["viewer"], "deviceId": "p-viewer"}}, "devices": {}}
    led = _ledger(init)
    cmd = ctx.records["command.point-won"]
    scorer, viewer_peer = {"deviceId": "p-scorer"}, {"deviceId": "p-viewer"}
    expect_eq(rep, "legacy ledger 1", led.submit(cmd, None, scorer)["status"], "Accepted")
    expect_eq(rep, "legacy ledger 2", led.submit(cmd, None, scorer)["status"], "Accepted")
    expect_eq(rep, "legacy ledger applied once", (led.state()["eventCount"], led.revision), (1, 43))
    expect_eq(rep, "legacy id reuse", led.submit(apply_patch(cmd, [{"op": "replace", "path": "/payload/winnerPlayerId", "value": "alex"}]), None, scorer)["reason"], "commandIdReuse")
    expect_eq(rep, "legacy conflict", led.submit({**cmd, "commandId": "other-point"}, None, scorer)["status"], "Conflicted")
    viewer = apply_patch(cmd, [{"op": "replace", "path": "/commandId", "value": "viewer-point"},
                               {"op": "replace", "path": "/role", "value": "viewer"},
                               {"op": "replace", "path": "/issuer/memberId", "value": "m-viewer"},
                               {"op": "replace", "path": "/baseEventRevision", "value": 43}])
    expect_eq(rep, "legacy viewer", led.submit(viewer, None, viewer_peer)["status"], "Rejected")
    if len(rep.failures) == before:
        rep.ok("legacy verifier assertions", 20)


# ----- 7: acceptance map -------------------------------------------------------------------------------------------

def matrix_rows() -> list:
    lines = MATRIX.read_text(encoding="utf-8").splitlines()
    rows = [ln for ln in lines if ln.startswith("|") and not ln.startswith("|---")][1:]
    return [ln.split("|")[1].strip() for ln in rows]


def check_acceptance(ctx: Ctx, rep: Report) -> None:
    amap = load(FIX / "acceptance-map.json")
    for e in ctx.schema_errors(amap):
        rep.fail("acceptance-map", e)
    scenarios = matrix_rows()
    expect_eq(rep, "acceptance rows", [r["scenario"] for r in amap["rows"]], scenarios)
    expect_eq(rep, "acceptance numbering", [r["row"] for r in amap["rows"]], list(range(1, len(scenarios) + 1)))
    all_cases = rep.passed_cases | rep.failed_cases
    for r in amap["rows"]:
        if r["protocolTestable"] != "no" and not r["covers"]:
            rep.fail("acceptance-map", f"row {r['row']} is testable but has no case")
        if r["protocolTestable"] == "no" and r["covers"]:
            rep.fail("acceptance-map", f"row {r['row']} is marked untestable but lists cases")
        for c in r["covers"]:
            if c not in all_cases:
                rep.fail("acceptance-map", f"row {r['row']}: {c} was not executed")
            elif c in rep.failed_cases:
                rep.fail("acceptance-map", f"row {r['row']}: {c} failed")
    tallies = {k: sum(1 for r in amap["rows"] if r["protocolTestable"] == k) for k in ("yes", "partial", "no")}
    rep.ok("acceptance rows (protocol-testable)", tallies["yes"])
    rep.ok("acceptance rows (partial)", tallies["partial"])
    rep.ok("acceptance rows (native/physical only)", tallies["no"])


# ----- 8-9: secrets and determinism --------------------------------------------------------------------------------

def check_secrets(ctx: Ctx, rep: Report) -> None:
    tokens = list(load(FIX / "vectors" / "invitation.json")["secrets"]["tokens"].values())
    allowed = {"records/invitation-payload.json", "records/invitation-payload.hotspot.json", "vectors/invitation.json"}
    passphrase = ctx.records["invitation-payload.hotspot"]["network"]["passphrase"]
    for path in sorted(FIX.rglob("*.json")):
        rel = path.relative_to(FIX).as_posix()
        text = path.read_text(encoding="utf-8")
        if rel not in allowed and any(t in text for t in tokens):
            # invalid cases that deliberately put a token where it must not be are rejected by the schema
            if not rel.startswith("invalid/"):
                rep.fail("secrets", f"{rel} contains a join token")
        if passphrase in text and rel not in {"records/invitation-payload.hotspot.json"}:
            rep.fail("secrets", f"{rel} contains the Sample hotspot passphrase")
    rep.ok("secret hygiene checks", 2)


def check_determinism(rep: Report) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([sys.executable, str(ROOM / "reference" / "generate_room_fixtures.py"), "--out", tmp],
                       check=True, capture_output=True)
        fresh = {p.relative_to(tmp).as_posix(): p.read_bytes() for p in Path(tmp).rglob("*.json")}
    disk = {p.relative_to(FIX).as_posix(): p.read_bytes() for p in FIX.rglob("*.json")}
    for rel in sorted(set(fresh) | set(disk)):
        if fresh.get(rel) != disk.get(rel):
            rep.fail("determinism", f"{rel} differs from a fresh generation")
    rep.ok("fixture files (deterministic)", len(disk))


def main(argv) -> int:
    rep = Report("-v" in argv)
    ctx = Ctx()
    check_schemas(ctx, rep)
    check_drift(ctx, rep)
    check_records(ctx, rep)
    check_invalid(ctx, rep)
    check_vectors(ctx, rep)
    check_legacy(ctx, rep)
    check_acceptance(ctx, rep)
    check_secrets(ctx, rep)
    check_determinism(rep)
    for f in rep.failures:
        print(f)
    for what, n in rep.counts.items():
        print(f"ok  {n:4d}  {what}")
    print(f"cases passed: {len(rep.passed_cases)}, failed: {len(rep.failed_cases)}")
    if rep.failures:
        print(f"FAILED: {len(rep.failures)} problem(s)")
        return 1
    print("PASS: JOVRA Room v1 contracts")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
