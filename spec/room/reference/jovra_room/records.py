"""Record-level rules that JSON Schema (as used here) cannot express. Each raises Reject(code)."""

from __future__ import annotations

from .core import Reject, parse_time
from .invitation import check_endpoint, check_lifetime, check_roles
from .ledger import CAPTURE_TTL_MAX_MS, CAPTURE_TYPES, ROLE_COMMANDS, SCORE_TYPES

OWN_ALERTS = frozenset({"ownRecordingFailed", "ownStorageCritical"})


def _unique(values, code: str) -> None:
    values = list(values)
    if len(values) != len(set(values)):
        raise Reject(code)


def check_invitation(r: dict, ctx=None) -> None:
    check_lifetime(r["issuedAt"], r["expiresAt"])
    check_roles(r["captureRole"], r["commandRole"])
    used = r["status"] == "used"
    if used != (r["usedByDeviceId"] is not None) or used != (r["usedAt"] is not None):
        raise Reject("usedFields")
    if (r["status"] == "revoked") != (r["revokedReason"] is not None):
        raise Reject("revokedFields")
    if used and parse_time(r["usedAt"]) > parse_time(r["expiresAt"]):
        raise Reject("usedAfterExpiry")
    if r["captureRole"] == "none" and r["studioSlot"] is not None:
        raise Reject("slotWithoutCamera")


def check_invitation_payload(p: dict, ctx=None) -> None:
    check_lifetime(p["issuedAt"], p["expiresAt"])
    check_roles(p["captureRole"], p["commandRole"])
    for ep in p["endpoints"]:
        check_endpoint(ep)


def check_join_request(r: dict, ctx=None) -> None:
    if r["guestKeySha256"] == r["observedHostKeySha256"]:
        raise Reject("guestKeyEqualsHostKey")


def check_join_challenge(r: dict, ctx=None) -> None:
    return None


def check_join_reveal(r: dict, ctx=None) -> None:
    return None


def check_device_status(d: dict, ctx=None) -> None:
    if "ageAtHostMs" in d:
        raise Reject("senderAssertedAge", "only the host measures a device's age")


def _check_score(env: dict) -> None:
    if "score" in env and env["score"]["eventRevision"] != env["eventRevision"]:
        raise Reject("scoreRevisionMismatch")


def _check_receipts(receipts: list) -> None:
    _unique((r["commandId"] for r in receipts), "duplicateReceipt")
    for r in receipts:
        check_receipt(r)


def _check_roster(env: dict) -> None:
    roster = set(env["roster"]["cameraDeviceIds"])
    if any(d["deviceId"] not in roster for d in env["devices"]):
        raise Reject("deviceNotInRoster")


def check_snapshot(env: dict, ctx=None) -> None:
    _unique((d["deviceId"] for d in env["devices"]), "duplicateDevice")
    _check_roster(env)
    if sum(1 for d in env["devices"] if d.get("captureRole") == "primary") > 1:
        raise Reject("primaryCount")
    for d in env["devices"]:
        for key in ("sessionId", "hostEpoch"):
            if key in d and d[key] != env[key]:
                raise Reject("sessionMismatch")
    _check_score(env)
    _check_receipts(env["receipts"])


def check_watch_bridge(env: dict, ctx=None) -> None:
    _unique((d["deviceId"] for d in env["devices"]), "duplicateDevice")
    _check_roster(env)
    _check_score(env)
    _check_receipts(env["receipts"])
    part = env["participant"]
    allowed = set().union(*(ROLE_COMMANDS[r] for r in part["commandRoles"]))
    if any(t in CAPTURE_TYPES for t in part["watchCommandTypes"]):
        raise Reject("watchCaptureCommand", "a watch never issues capture requests in v1")
    if not set(part["watchCommandTypes"]) <= allowed:
        raise Reject("watchExceedsGrant", "watch abilities can only narrow the member's grants")
    _unique((a["alertId"] for a in env["alerts"]), "duplicateAlert")
    for a in env["alerts"]:
        if (a["severity"] == "critical") != (a["kind"] in OWN_ALERTS):
            raise Reject("alertSeverity", "critical only for the watch owner's own recording failure or storage")
    serve = env.get("latestServe")
    if serve is not None:
        if not env["capabilities"].get("serveSpeedResults", False):
            raise Reject("capabilityAbsent", "latestServe needs capabilities.serveSpeedResults")
        if serve["kind"] != "serveSpeed":
            raise Reject("notServeResult")
        if serve["sessionId"] != env["sessionId"]:
            raise Reject("sessionMismatch")
        check_analysis_result(serve, ctx)


def check_command(c: dict, ctx=None) -> None:
    kind = c["payload"]["type"]
    if kind in CAPTURE_TYPES and c["expiry"]["ttlMs"] > CAPTURE_TTL_MAX_MS:
        raise Reject("ttlTooLong")
    if c["issuer"]["surface"] == "watch" and c["issuer"]["bridgeDeviceId"] == c["issuer"]["deviceId"]:
        raise Reject("watchIsItsOwnBridge")
    if kind == "MarkForReview" and not c["payload"]["sourceRefs"] and c["payload"]["pointEventId"] is None:
        raise Reject("markWithoutReference", "a review mark needs a point or a source reference")


def check_receipt(r: dict, ctx=None) -> None:
    if (r["status"] == "Conflicted") != (r["conflict"] is not None):
        raise Reject("conflictFields")
    if (r["status"] == "Pending") != (r["canonicalEventRevision"] is None) and r["reason"] != "hostEpochChanged":
        raise Reject("pendingRevision")
    _unique((x["deviceId"] for x in r["deviceResults"]), "duplicateDeviceResult")
    if r["type"] in CAPTURE_TYPES and r["status"] == "Accepted" and not r["deviceResults"]:
        raise Reject("missingDeviceResults")
    if r["type"] not in CAPTURE_TYPES and r["deviceResults"]:
        raise Reject("unexpectedDeviceResults")
    if r["status"] == "Accepted" and r["type"] not in CAPTURE_TYPES and r["appliedRecordId"] is None:
        raise Reject("acceptedWithoutRecord")
    if r["status"] != "Accepted" and r["appliedRecordId"] is not None:
        raise Reject("recordWithoutAcceptance")
    if r["type"] in SCORE_TYPES and r["status"] == "Accepted" and r["canonicalEventRevision"] is None:
        raise Reject("pendingRevision")


def check_analysis_result(r: dict, ctx=None) -> None:
    registry = (ctx or {}).get("registry", {})
    if (r["value"] is None) == (r["unavailableReason"] is None):
        raise Reject("valueOrReason", "exactly one of value and unavailableReason")
    if (r["value"] is None) != (r["units"] is None):
        raise Reject("unitsWithoutValue")
    if r["value"] is not None and r["label"] == "estimated" and r["uncertainty"] is None:
        raise Reject("uncertaintyMissing")
    status = registry.get(r["capabilityId"])
    if status is None:
        raise Reject("unknownCapability", r["capabilityId"])
    if status in ("unsupported", "disabled") and r["value"] is not None:
        raise Reject("capabilityUnsupported", f"{r['capabilityId']} is {status}")
    if r["label"] == "validated" and status != "validated":
        raise Reject("labelExceedsCapability")
    for ref in r["sourceRefs"]:
        fr = ref["frameRange"]
        if fr is not None and fr["endFrame"] < fr["startFrame"]:
            raise Reject("frameRange")
    if r["uncertainty"] is not None and r["value"] is not None:
        lo, hi, v = (float(r["uncertainty"]["lower"]), float(r["uncertainty"]["upper"]), float(r["value"]))
        if not lo <= v <= hi:
            raise Reject("uncertaintyExcludesValue")


RULES = {
    "jovra.room.invitation/1": check_invitation,
    "jovra.room.invitation-payload/1": check_invitation_payload,
    "jovra.room.join-request/1": check_join_request,
    "jovra.room.join-challenge/1": check_join_challenge,
    "jovra.room.watch-local/1": check_join_challenge,
    "jovra.room.join-reveal/1": check_join_reveal,
    "jovra.room.device-status/1": check_device_status,
    "jovra.room.snapshot/1": check_snapshot,
    "jovra.room.watch-bridge/1": check_watch_bridge,
    "jovra.room.command/1": check_command,
    "jovra.room.receipt/1": check_receipt,
    "jovra.room.analysis-result/1": check_analysis_result,
}


def check(record: dict, ctx=None) -> None:
    RULES[record["schemaVersion"]](record, ctx)
