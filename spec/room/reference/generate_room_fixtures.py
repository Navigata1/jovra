#!/usr/bin/env python3
"""Write spec/room/fixtures deterministically (same bytes every run). Standard library only.

Every expectation below is a hand-written literal derived from design-reference/adaptive/brief/session-connectivity.md,
acceptance-matrix.md and the JOVRA Room v1 proposal (docs/research/studio/multicam-sync.md section 2). This script
never calls the reference engine to produce an expectation: scripts/spec/validate_room.py runs the reference against
these literals. Hashes (key fingerprints, token hashes, HMAC proofs, verification codes) are computed here with
hashlib/hmac directly, independently of spec/room/reference/jovra_room.

All secrets below are fictional Sample values derived from public strings. They are not credentials.

Usage:  python3 spec/room/reference/generate_room_fixtures.py [--out DIR]
"""

from __future__ import annotations

import base64
import copy
import hashlib
import hmac
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DESIGN_SAMPLE = ROOT / "design-reference/adaptive/brief/watch-snapshot.sample.json"

SESSION = "sample-jon-alex"
EPOCH = 3


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def b64token(seed: str) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(seed.encode("utf-8")).digest()[:16]).decode("ascii").rstrip("=")


HOST_KEY = sha("sample-host-key-epoch-3")
NEW_HOST_KEY = sha("sample-host-key-epoch-4")
ROGUE_KEY = sha("sample-rogue-key")
GUEST_KEY = sha("sample-guest-key-c2")
TOKEN_C2 = b64token("sample-join-token-inv-c2")
NONCE_C2 = b64token("sample-nonce-inv-c2")
TOKEN_SCORER = b64token("sample-join-token-inv-scorer")
NONCE_SCORER = b64token("sample-nonce-inv-scorer")
GUEST_NONCE = b64token("sample-guest-nonce-c2")      # the guest's committed nonce (revealed after the challenge)
HOST_NONCE_1 = b64token("sample-host-nonce-attempt-1")  # the host's fresh challenge nonces, one per attempt
HOST_NONCE_2 = b64token("sample-host-nonce-attempt-2")
HOST_NONCE_3 = b64token("sample-host-nonce-attempt-3")
HOTSPOT_PASSPHRASE = "sample-court-wifi-482"           # Sample value, not a credential


def commitment(guest_key, guest_nonce):
    return sha(f"jovra-room-commit|{guest_key}|{guest_nonce}")


def proof(token, invite, nonce, guest_key, commit, session=SESSION):
    msg = f"{session}|{invite}|{nonce}|{guest_key}|{commit}"
    return hmac.new(token.encode("ascii"), msg.encode("utf-8"), hashlib.sha256).hexdigest()


def sas(host_key, guest_key, qr_nonce, host_nonce, guest_nonce):
    digest = sha(f"jovra-room-sas|{host_key}|{guest_key}|{qr_nonce}|{host_nonce}|{guest_nonce}")
    return f"{int(digest[:8], 16) % 1_000_000:06d}"


GUEST_COMMIT = commitment(GUEST_KEY, GUEST_NONCE)


OBS = {"storageFreeBytes": 41000000000, "estimatedMinutesLeft": 182, "batteryPercent": 71, "charging": False,
       "lowPowerMode": False, "thermal": "fair"}
CAPS_V1 = {"recordingHealth": True, "manualScore": True, "markForReview": True, "liveServeSpeed": False, "automatedLineCalls": False}
POLICY = {"freshMaxMs": 5000, "delayedMaxMs": 15000, "proposalOnly": True}
SAMPLE_DEVICES = [  # (deviceId, deviceSeq, ageAtHostMs, lastReportedElapsedMs) from the design sample, host side
    ("c1", 12, 500, 754000), ("c2", 11, 1500, 753000), ("c3", 7, 17500, 746000),
    ("c4", 12, 500, 752000), ("c5", 12, 500, 754000), ("c6", 11, 1500, 751000)]


# ----- records -----------------------------------------------------------------------------------------------------

def rec_invitation(invite="inv-c2", token=TOKEN_C2, capture="camera", command="viewer", slot="far-baseline", code="JVR-482"):
    return {
        "schemaVersion": "jovra.room.invitation/1", "sample": True, "inviteId": invite, "sessionId": SESSION,
        "hostDeviceId": "c1", "hostEpoch": EPOCH, "hostKeySha256": HOST_KEY, "displayCode": code,
        "joinTokenSha256": sha(token), "secretBits": 128, "issuedAt": "2026-10-07T21:10:00Z",
        "expiresAt": "2026-10-07T21:20:00Z", "singleUse": True, "hostApprovalRequired": True,
        "captureRole": capture, "commandRole": command, "studioSlot": slot, "status": "issued",
        "usedByDeviceId": None, "usedAt": None, "revokedReason": None,
    }


def rec_payload():
    return {
        "schemaVersion": "jovra.room.invitation-payload/1", "sample": True, "inviteId": "inv-c2", "sessionId": SESSION,
        "hostEpoch": EPOCH, "hostKeySha256": HOST_KEY, "joinToken": TOKEN_C2, "nonce": NONCE_C2,
        "issuedAt": "2026-10-07T21:10:00Z", "expiresAt": "2026-10-07T21:20:00Z", "captureRole": "camera",
        "commandRole": "viewer", "displayCode": "JVR-482",
        "endpoints": [{"kind": "dnssd", "serviceType": "_jovra-room._tcp", "instanceName": "JOVRA Court 3"},
                      {"kind": "lan", "address": "192.168.1.20", "port": 47100}],
    }


def rec_payload_hotspot():
    """An Android host on a LocalOnlyHotspot puts the court Wi-Fi in the QR (Sample SSID and passphrase)."""
    p = rec_payload()
    p["network"] = {"kind": "wifi", "ssid": "JOVRA Court 3", "passphrase": HOTSPOT_PASSPHRASE, "security": "wpa2-psk"}
    p["endpoints"] = [{"kind": "lan", "address": "192.168.49.1", "port": 47100}]
    return p


def rec_join(**over):
    r = {"schemaVersion": "jovra.room.join-request/1", "inviteId": "inv-c2", "sessionId": SESSION, "hostEpoch": EPOCH,
         "guestDeviceId": "c2", "guestKeySha256": GUEST_KEY, "guestCommitment": GUEST_COMMIT,
         "observedHostKeySha256": HOST_KEY,
         "proof": proof(TOKEN_C2, "inv-c2", NONCE_C2, GUEST_KEY, GUEST_COMMIT), "requestedCaptureRole": "camera",
         "requestedCommandRole": "viewer", "displayName": "Alex's phone", "consent": {"shareCaptureMetadata": True}}
    r.update(over)
    return r


def rec_join_challenge():
    return {"schemaVersion": "jovra.room.join-challenge/1", "inviteId": "inv-c2", "sessionId": SESSION, "hostEpoch": EPOCH,
            "hostNonce": HOST_NONCE_1}


def rec_join_reveal():
    return {"schemaVersion": "jovra.room.join-reveal/1", "inviteId": "inv-c2", "sessionId": SESSION, "hostEpoch": EPOCH,
            "guestNonce": GUEST_NONCE}


ROSTER = {"rosterRevision": 1, "cameraDeviceIds": ["c1", "c2", "c3", "c4", "c5", "c6"]}


def device(dev_id, seq, elapsed, state="Recording", role="camera", age=None):
    d = {"deviceId": dev_id, "captureInstanceId": f"sample-{dev_id}-take1", "segmentId": "s1", "deviceSeq": seq,
         "captureState": state, "captureRole": role, "lastReportedElapsedMs": elapsed, "observations": dict(OBS)}
    if age is not None:
        d["ageAtHostMs"] = age
    return d


def rec_device_status():
    d = device("c2", 11, 753000)
    return {"schemaVersion": "jovra.room.device-status/1", "sessionId": SESSION, "hostEpoch": EPOCH, **d}


def receipt(cid, kind, status, reason=None, rev=42, applied=None, conflict=None, results=None):
    return {"schemaVersion": "jovra.room.receipt/1", "commandId": cid, "sessionId": SESSION, "hostEpoch": EPOCH,
            "type": kind, "status": status, "reason": reason, "canonicalEventRevision": rev, "appliedRecordId": applied,
            "conflict": conflict, "deviceResults": results or []}


def rec_snapshot():
    devices = [device(i, s, e, role="primary" if i == "c1" else "camera", age=a) for i, s, a, e in SAMPLE_DEVICES]
    return {
        "schemaVersion": "jovra.room.snapshot/1", "sample": True, "sessionId": SESSION, "hostDeviceId": "c1",
        "hostEpoch": EPOCH, "hostKeySha256": HOST_KEY, "snapshotSeq": 8, "eventRevision": 42,
        "freshnessPolicy": dict(POLICY), "capabilities": dict(CAPS_V1),
        "score": {"eventRevision": 42, "label": "manual", "players": [{"playerId": "jon", "games": 5, "point": "30"},
                                                                       {"playerId": "alex", "games": 4, "point": "15"}]},
        "roster": copy.deepcopy(ROSTER),
        "devices": devices,
        "receipts": [receipt("sample-marker-42", "MarkForReview", "Accepted", applied="sample-mark-42")],
    }


def command(cid, payload, role="scorer", member="m-scorer", dev="p-scorer", base=42, scope="session", targets=(),
            ttl=60000, age=200, surface="phone", bridge=None, session=SESSION, epoch=EPOCH):
    return {
        "schemaVersion": "jovra.room.command/1", "commandId": cid, "sessionId": session, "hostEpoch": epoch,
        "issuer": {"memberId": member, "deviceId": dev, "surface": surface, "bridgeDeviceId": bridge},
        "role": role, "issuedAt": "2026-10-07T21:30:00Z",
        "issuedFreshness": {"basedOnSnapshotSeq": 8, "basedOnFreshness": "Fresh"},
        "expiry": {"ttlMs": ttl, "ageAtSendMs": age}, "target": {"scope": scope, "deviceIds": list(targets)},
        "baseEventRevision": base, "payload": payload,
    }


def point(cid, winner="jon", base=42, **kw):
    return command(cid, {"type": "PointWon", "winnerPlayerId": winner}, base=base, **kw)


def undo(cid, target, base, **kw):
    return command(cid, {"type": "Undo", "targetEventId": target}, base=base, **kw)


def mark(cid, reason="point", point_id="sample-point-42", **kw):
    kw.setdefault("role", "marker")
    kw.setdefault("member", "m-marker")
    kw.setdefault("dev", "w-marker")
    kw.setdefault("surface", "watch")
    kw.setdefault("bridge", "p-marker")
    kw.setdefault("base", None)
    refs = [{"deviceId": "c1", "captureInstanceId": "sample-c1-take1", "segmentId": "s1",
             "frameRange": {"startFrame": 45210, "endFrame": 45390}}]
    return command(cid, {"type": "MarkForReview", "reason": reason, "pointEventId": point_id, "sourceRefs": refs,
                         "note": None}, **kw)


def capture(cid, kind, targets=(), label=None, **kw):
    kw.setdefault("role", "capture-controller")
    kw.setdefault("member", "m-controller")
    kw.setdefault("dev", "p-controller")
    kw.setdefault("ttl", 15000)
    payload = {"type": kind}
    if kind == "StopOne":
        payload["targetLabel"] = label or "Camera 1 · near baseline"
    if kind == "StopAllRequest":
        payload.update(targetLabel="All 6 cameras", confirmed=True)
    scope = "allCameras" if kind == "StopAllRequest" else "device"
    return command(cid, payload, base=None, scope=scope, targets=targets, **kw)


def rec_analysis(kind="serve-previous"):
    base = {"schemaVersion": "jovra.room.analysis-result/1", "sample": True, "sessionId": SESSION,
            "sourceRefs": [{"deviceId": "c1", "captureInstanceId": "sample-c1-take1", "segmentId": "s1",
                            "frameRange": {"startFrame": 45210, "endFrame": 45330}}],
            "producedAt": "2026-10-07T21:28:40Z", "producedAtEventRevision": 42, "reviewState": "notRequired",
            "scoreEffect": "none"}
    if kind == "serve-previous":
        return {**base, "resultId": "sample-serve-42", "capabilityId": "serveSpeed.manualAssisted", "kind": "serveSpeed",
                "pointEventId": "sample-point-42", "label": "estimated", "modelVersion": "serve-assist/0.1",
                "calibrationId": "sample-cal-1", "value": "74", "units": "mph",
                "uncertainty": {"lower": "70", "upper": "78", "level": "range"}, "unavailableReason": None}
    if kind == "serve-unavailable":
        return {**base, "resultId": "sample-serve-43", "capabilityId": "serveSpeed.manualAssisted", "kind": "serveSpeed",
                "pointEventId": "sample-point-43", "label": "estimated", "modelVersion": None, "calibrationId": None,
                "value": None, "units": None, "uncertainty": None, "unavailableReason": "calibrationMissing"}
    return {**base, "resultId": "sample-bounce-43", "capabilityId": "bouncePlacement.auto", "kind": "bounceHint",
            "pointEventId": "sample-point-43", "label": "estimated", "modelVersion": None, "calibrationId": None,
            "value": None, "units": None, "uncertainty": None, "unavailableReason": "capabilityUnsupported",
            "reviewState": "reviewNeeded"}


def rec_watch_bridge():
    """Literal adaptation of the design sample (see jovra_room/design_sample.py; the validator checks they agree)."""
    raw = json.loads(DESIGN_SAMPLE.read_text(encoding="utf-8"))
    return {
        "schemaVersion": "jovra.room.watch-bridge/1", "sample": True, "sessionId": raw["sessionId"],
        "hostEpoch": raw["hostEpoch"], "snapshotSeq": raw["snapshotSeq"], "eventRevision": raw["eventRevision"],
        "bridge": {"bridgeDeviceId": "sample-bridge-phone", "bridgeInstanceId": "sample-bridge-run-1",
                   "channel": "watchconnectivity", "bridgeSeq": 8, "snapshotAgeAtBridgeMs": 1000},
        "participant": {"memberId": "sample-member-jon", "commandRoles": ["scorer"],
                        "watchCommandTypes": ["MarkForReview", "PointWon", "Undo"]},
        "freshnessPolicy": dict(POLICY), "capabilities": dict(CAPS_V1),
        "score": {"eventRevision": 42, "label": "manual", "players": [{"playerId": "jon", "games": 5, "point": "30"},
                                                                       {"playerId": "alex", "games": 4, "point": "15"}]},
        "roster": copy.deepcopy(ROSTER),
        "latestServe": None,
        "devices": [{k: d[k] for k in ("deviceId", "captureInstanceId", "segmentId", "deviceSeq", "captureState",
                                        "ageAtBridgeMs", "lastReportedElapsedMs")} for d in raw["devices"]],
        "alerts": [],
        "receipts": [receipt("sample-marker-42", "MarkForReview", "Accepted", applied="sample-mark-42")],
        "receiverObservation": {"delivery": "fixture", "transitBounded": True, "transitMs": 0,
                                "processBaselineId": "sample-watch-boot-1", "acceptedAtMonoMs": 0},
    }


def rec_watch_bridge_with_serve():
    """v1 watch with a post-capture serve estimate (ADR-0026 as amended): timestamped, labelled, never live."""
    b = rec_watch_bridge()
    b["capabilities"]["serveSpeedResults"] = True
    b["latestServe"] = rec_analysis("serve-previous")
    b["alerts"] = [{"alertId": "sample-alert-c3", "kind": "cameraUnknown", "deviceId": "c3", "severity": "deferred",
                    "ageAtBridgeMs": 18000}]
    return b


def rec_watch_local(kind):
    base = {"schemaVersion": "jovra.room.watch-local/1", "sessionId": SESSION}
    if kind == "echo-request":
        return {**base, "messageId": "sample-echo-1", "kind": "echoRequest", "echoMonoMs": 120000}
    if kind == "ack-alert":
        return {**base, "messageId": "sample-ack-1", "kind": "ackAlert", "alertId": "sample-alert-c3"}
    return {**base, "messageId": "sample-stop-own-1", "kind": "stopOwnPhone", "confirmed": True}


def records():
    out = {
        "invitation": rec_invitation(),
        "invitation.scorer": rec_invitation("inv-scorer", TOKEN_SCORER, "none", "scorer", None, "JVR-517"),
        "invitation-payload": rec_payload(),
        "invitation-payload.hotspot": rec_payload_hotspot(),
        "join-request": rec_join(),
        "join-challenge": rec_join_challenge(),
        "join-reveal": rec_join_reveal(),
        "device-status": rec_device_status(),
        "room-snapshot": rec_snapshot(),
        "watch-bridge.sample": rec_watch_bridge(),
        "watch-bridge.with-serve": rec_watch_bridge_with_serve(),
        "watch-local.echo-request": rec_watch_local("echo-request"),
        "watch-local.ack-alert": rec_watch_local("ack-alert"),
        "watch-local.stop-own-phone": rec_watch_local("stop-own-phone"),
        "command.point-won": point("cmd-point-43"),
        "command.undo": undo("cmd-undo-44", "evt-43", 43),
        "command.mark-for-review.watch": mark("cmd-mark-43"),
        "command.start-request": capture("cmd-start-c4", "StartRequest", ["c4"]),
        "command.stop-one": capture("cmd-stop-c1", "StopOne", ["c1"]),
        "command.stop-all": capture("cmd-stop-all", "StopAllRequest"),
        "receipt.accepted-point": receipt("cmd-point-43", "PointWon", "Accepted", rev=43, applied="evt-43"),
        "receipt.conflicted": receipt("cmd-point-43b", "PointWon", "Conflicted", "baseRevisionStale", rev=43,
                                      conflict={"baseEventRevision": 42, "currentEventRevision": 43}),
        "receipt.pending-offline": receipt("cmd-point-44", "PointWon", "Pending", "offlineDraft", rev=None),
        "receipt.stop-all-partial": receipt("cmd-stop-all", "StopAllRequest", "Accepted", results=[
            {"deviceId": "c1", "status": "Accepted", "reason": "stopRequested"},
            {"deviceId": "c2", "status": "TimedOut", "reason": "unreachable"},
            {"deviceId": "c3", "status": "Unknown", "reason": "noAcknowledgement"},
            {"deviceId": "c4", "status": "Failed", "reason": "finalizeFailed"},
            {"deviceId": "c5", "status": "Accepted", "reason": "stopRequested"},
            {"deviceId": "c6", "status": "Accepted", "reason": "notRecording"}]),
        "analysis-result.serve-previous": rec_analysis("serve-previous"),
        "analysis-result.serve-unavailable": rec_analysis("serve-unavailable"),
        "analysis-result.bounce-review": rec_analysis("bounce"),
    }
    return out


# ----- invalid cases -----------------------------------------------------------------------------------------------

def S(case_id, why, patch, rows=None):
    c = {"id": case_id, "why": why, "patch": patch, "expect": {"layer": "schema"}}
    if rows:
        c["acceptanceRows"] = rows
    return c


def R(case_id, why, patch, code, rows=None):
    c = {"id": case_id, "why": why, "patch": patch, "expect": {"layer": "reference", "code": code}}
    if rows:
        c["acceptanceRows"] = rows
    return c


def rep(path, value):
    return {"op": "replace", "path": path, "value": value}


def add(path, value):
    return {"op": "add", "path": path, "value": value}


def rem(path):
    return {"op": "remove", "path": path}


def invalid_sets():
    return {
        "invitation": [
            R("long-invite", "Invitations expire within 10 minutes", [rep("/expiresAt", "2026-10-07T21:20:01Z")], "inviteLifetime", [4]),
            R("camera-with-controls", "A camera invitation never carries capture controls (Studio: cameras never get host controls)",
              [rep("/commandRole", "capture-controller")], "cameraCannotControl", [14]),
            S("token-in-record", "The host record stores only a hash of the join token", [add("/joinToken", TOKEN_C2)]),
            S("weak-secret", "At least 128 bits of entropy", [rep("/secretBits", 64)]),
            S("multi-use", "Single use", [rep("/singleUse", False)], [4]),
            S("no-host-approval", "The host approves every join", [rep("/hostApprovalRequired", False)]),
            S("url-display-code", "The display code is lookup data, never a URL", [rep("/displayCode", "https://jovra.example/j/482")]),
            R("used-without-device", "A used invitation names the device and time", [rep("/status", "used")], "usedFields", [4]),
            R("revoked-without-reason", "Revocation states why", [rep("/status", "revoked")], "revokedFields"),
        ],
        "invitation-payload": [
            S("web-url-endpoint", "A QR never makes the client fetch an arbitrary URL",
              [rep("/endpoints/1", {"kind": "url", "url": "https://jovra.example/join"})], [5]),
            S("hostname-endpoint", "Endpoints are IP literals or DNS-SD instances, never hostnames",
              [rep("/endpoints/1/address", "court-relay.example.com")], [5]),
            R("public-ip-endpoint", "Only private or link-local LAN addresses", [rep("/endpoints/1/address", "8.8.8.8")], "endpointNotAllowed", [5]),
            R("loopback-endpoint", "Loopback is not a peer", [rep("/endpoints/1/address", "127.0.0.1")], "endpointNotAllowed", [5]),
            R("cgnat-endpoint", "Carrier-grade NAT space is not the court LAN", [rep("/endpoints/1/address", "100.64.0.9")], "endpointNotAllowed", [5]),
            S("other-service-type", "Only the JOVRA room service", [rep("/endpoints/0/serviceType", "_http._tcp")], [5]),
            S("short-token", "At least 128 bits", [rep("/joinToken", "abc123")], [4]),
            S("callback-url", "No URL fields at all", [add("/callbackUrl", "https://jovra.example/cb")], [5]),
            R("long-lifetime", "At most 10 minutes", [rep("/expiresAt", "2026-10-07T22:10:00Z")], "inviteLifetime", [4]),
        ],
        "invitation-payload.hotspot": [
            S("open-network", "The court Wi-Fi is never an open network", [rep("/network/security", "open")], [5]),
            S("short-passphrase", "WPA passphrases are 8 to 63 characters", [rep("/network/passphrase", "short")], [5]),
            S("network-url", "No URL fields at all, including in the network block", [add("/network/captivePortal", "https://jovra.example/wifi")], [5]),
            R("public-ip-on-hotspot", "The hotspot endpoint still passes the LAN allow-list", [rep("/endpoints/0/address", "8.8.4.4")],
              "endpointNotAllowed", [5]),
        ],
        "join-request": [
            S("no-consent", "Joining records consent to share capture metadata", [rep("/consent/shareCaptureMetadata", False)]),
            S("token-in-clear", "The guest proves possession; it never sends the token", [add("/joinToken", TOKEN_C2)]),
            S("bad-proof-format", "Proof is an HMAC-SHA256", [rep("/proof", "JVR-482")], [4]),
            S("no-commitment", "The guest commits to its key and nonce before the host's challenge (D3)", [rem("/guestCommitment")], [4]),
            R("guest-equals-host", "A guest cannot present the host's key as its own",
              [rep("/guestKeySha256", HOST_KEY)], "guestKeyEqualsHostKey", [5]),
        ],
        "device-status": [
            S("sender-asserted-fresh", "Freshness is receiver-derived; a sender cannot assert it", [add("/freshness", "Fresh")], [6]),
            S("sender-asserted-unknown", "Unknown is not a capture state", [rep("/captureState", "Unknown")], [6]),
            S("sender-asserted-connected", "No 'connected' claim", [add("/connected", True)], [6]),
            S("failed-without-reason", "A failure says why", [rep("/captureState", "Failed")], [15]),
            S("reason-without-failure", "Only a failure has a reason", [add("/failureReason", "storageFull")]),
            R("sender-asserted-age", "Only the host measures a device's age", [add("/ageAtHostMs", 0)], "senderAssertedAge", [6]),
            S("negative-elapsed", "Durations are non-negative", [rep("/lastReportedElapsedMs", -1)]),
        ],
        "room-snapshot": [
            S("seven-cameras", "One to six cameras", [add("/devices/-", device("c7", 1, 1000, age=500))]),
            R("duplicate-device", "A device appears once", [rep("/devices/5/deviceId", "c1")], "duplicateDevice", [5]),
            R("two-primaries", "One primary camera", [rep("/devices/1/captureRole", "primary")], "primaryCount"),
            S("live-serve-speed", "v1 has no live serve speed", [rep("/capabilities/liveServeSpeed", True)], [20]),
            S("automated-line-calls", "v1 makes no line calls", [rep("/capabilities/automatedLineCalls", True)], [22]),
            R("score-revision-mismatch", "The score summary is derived at the envelope's revision",
              [rep("/score/eventRevision", 41)], "scoreRevisionMismatch", [12]),
            S("device-freshness-field", "No sender-asserted freshness inside a snapshot", [add("/devices/0/freshness", "Fresh")], [7]),
            S("missing-host-age", "The host states each device's age", [rem("/devices/0/ageAtHostMs")], [6]),
            R("device-other-session", "Embedded entries cannot name another session",
              [add("/devices/2/sessionId", "other-room")], "sessionMismatch", [5]),
            S("stale-policy", "Thresholds are the proposed product defaults", [rep("/freshnessPolicy/freshMaxMs", 30000)]),
            S("no-roster", "Enrolment comes from the host's roster, never from the rows present (D8)", [rem("/roster")], [5]),
            S("roster-duplicate", "A roster lists a camera once", [rep("/roster/cameraDeviceIds/1", "c1")], [5]),
            R("device-not-in-roster", "Every device row is on the roster (D8)",
              [rep("/roster/cameraDeviceIds", ["c1", "c2", "c3", "c4", "c5"])], "deviceNotInRoster", [5]),
        ],
        "watch-bridge.sample": [
            S("bounded-without-bound", "A bounded transit states its bound",
              [rep("/receiverObservation/transitMs", None)], [8]),
            S("unbounded-with-bound", "An unbounded transit has no bound", [rep("/receiverObservation/transitBounded", False)], [8]),
            S("video-stream", "A watch never receives camera streams", [add("/devices/0/streamUrl", "rtsp://192.168.1.21/live")]),
            R("duplicate-device", "A device appears once", [rep("/devices/1/deviceId", "c1")], "duplicateDevice"),
            S("watch-as-host", "The watch bridge channel is a native companion API", [rep("/bridge/channel", "lan-room")]),
            S("queued-but-bounded", "A queued delivery can never claim a bounded transit (D6)",
              [rep("/receiverObservation/delivery", "queued"), rep("/receiverObservation/transitMs", 0)], [8]),
            S("interactive-unbounded", "An interactive exchange is the bounded one",
              [rep("/receiverObservation/delivery", "interactive"), rep("/receiverObservation/transitBounded", False),
               rep("/receiverObservation/transitMs", None)], [8]),
            S("no-bridge-instance", "Replay marks need the bridge instance (D6)", [rem("/bridge/bridgeInstanceId")], [5]),
            S("no-participant", "The watch UI is driven by the member's roles, so the bridge states them", [rem("/participant")], [14]),
            R("watch-stop-all", "A watch never issues capture requests (ADR-0026 as amended)",
              [add("/participant/watchCommandTypes/-", "StopAllRequest")], "watchCaptureCommand", [14]),
            R("watch-exceeds-grant", "Pairing grants nothing: a viewer's watch cannot score",
              [rep("/participant/commandRoles", ["viewer"])], "watchExceedsGrant", [14]),
            R("camera-unknown-critical", "A camera going Unknown is deferred, never critical (ADR-0026 as amended)",
              [add("/alerts/-", {"alertId": "a1", "kind": "cameraUnknown", "deviceId": "c3", "severity": "critical", "ageAtBridgeMs": 0})],
              "alertSeverity", [19]),
            R("own-failure-deferred", "The owner's own recording failure is critical",
              [add("/alerts/-", {"alertId": "a2", "kind": "ownRecordingFailed", "deviceId": "c1", "severity": "deferred", "ageAtBridgeMs": 0})],
              "alertSeverity", [19]),
            R("serve-without-capability", "A serve result is forwarded only with serveSpeedResults on",
              [rep("/latestServe", rec_analysis("serve-previous"))], "capabilityAbsent", [20]),
            R("bridge-device-not-in-roster", "Every device row is on the roster (D8)",
              [rep("/roster/cameraDeviceIds", ["c1", "c2", "c3", "c4", "c5"])], "deviceNotInRoster", [7]),
        ],
        "watch-bridge.with-serve": [
            R("serve-validated-label", "A forwarded result keeps its true label", [rep("/latestServe/label", "validated")],
              "labelExceedsCapability", [20]),
            R("bounce-as-serve", "Only a serve result fills latestServe",
              [rep("/latestServe", rec_analysis("bounce"))], "notServeResult", [22]),
            S("live-serve", "v1 never claims live serve speed", [rep("/capabilities/liveServeSpeed", True)], [20]),
            R("serve-other-session", "A forwarded result belongs to this session",
              [rep("/latestServe/sessionId", "other-room")], "sessionMismatch", [21]),
        ],
        "watch-local.stop-own-phone": [
            S("stop-other-phone", "A watch can only stop its own phone; there is no target field", [add("/deviceId", "c4")], [16]),
            S("stop-all-from-watch", "No stop-all kind exists on the watch channel", [rep("/kind", "stopAll")], [16]),
            S("unconfirmed-stop", "The own-phone stop needs the watch's confirmation", [rem("/confirmed")], [16]),
        ],
        "watch-local.ack-alert": [
            S("ack-without-alert", "An acknowledgement names its alert", [rem("/alertId")], [19]),
            S("ack-with-stop", "An acknowledgement never carries a stop", [add("/confirmed", True)], [19]),
        ],
        "watch-local.echo-request": [
            S("echo-without-time", "The echo carries the watch's own monotonic time", [rem("/echoMonoMs")], [8]),
        ],
        "command.stop-all": [
            S("unconfirmed-stop-all", "An all-device stop needs explicit confirmation", [rep("/payload/confirmed", False)], [16]),
            S("stop-all-without-label", "Stop-all names its concrete target", [rem("/payload/targetLabel")], [16]),
            R("long-capture-ttl", "Capture requests live at most 30 s", [rep("/expiry/ttlMs", 60000)], "ttlTooLong"),
            S("stop-all-with-revision", "Capture requests do not touch the event log", [rep("/baseEventRevision", 42)]),
        ],
        "command.stop-one": [
            S("stop-one-two-targets", "Stop one targets exactly one device", [add("/target/deviceIds/-", "c2")], [16]),
            S("stop-one-no-target", "Stop one targets exactly one device", [rep("/target/deviceIds", [])], [16]),
        ],
        "command.point-won": [
            S("point-without-base", "Score commands carry the base revision", [rep("/baseEventRevision", None)], [11]),
            S("point-with-device-target", "Score commands target the session", [rep("/target", {"scope": "device", "deviceIds": ["c1"]})]),
            S("force-record", "There is no command that forces remote capture", [rep("/payload", {"type": "ForceRecord"})], [15]),
            S("watch-without-bridge", "A watch command names its paired-phone bridge", [rep("/issuer/surface", "watch")]),
            S("phone-with-bridge", "Only a watch goes through a bridge", [rep("/issuer/bridgeDeviceId", "p-other")]),
            S("no-expiry", "Every command expires", [rem("/expiry")]),
        ],
        "command.mark-for-review.watch": [
            R("mark-without-reference", "A review mark is source-linked", [rep("/payload/pointEventId", None), rep("/payload/sourceRefs", [])],
              "markWithoutReference", [22]),
            R("watch-own-bridge", "The bridge is the paired phone", [rep("/issuer/bridgeDeviceId", "w-marker")], "watchIsItsOwnBridge"),
        ],
        "receipt.conflicted": [
            R("conflict-without-detail", "A conflict states both revisions", [rep("/conflict", None)], "conflictFields", [11]),
            S("succeeded-status", "Receipt states are Pending/Accepted/Rejected/Expired/Conflicted", [rep("/status", "Succeeded")]),
        ],
        "receipt.stop-all-partial": [
            R("blanket-success", "A capture fan-out keeps per-device results", [rep("/deviceResults", [])], "missingDeviceResults", [16]),
            S("stopped-result", "Per-device results do not claim a capture state", [rep("/deviceResults/0/status", "Stopped")], [16]),
            R("duplicate-result", "One result per device", [rep("/deviceResults/1/deviceId", "c1")], "duplicateDeviceResult", [16]),
        ],
        "receipt.pending-offline": [
            R("pending-with-revision", "A pending draft has not advanced the canonical revision", [rep("/canonicalEventRevision", 43)],
              "pendingRevision", [13]),
            R("pending-with-record", "A pending draft created nothing", [rep("/appliedRecordId", "evt-43")], "recordWithoutAcceptance", [13]),
        ],
        "receipt.accepted-point": [
            R("accepted-without-event", "An accepted point names the event it created exactly once", [rep("/appliedRecordId", None)],
              "acceptedWithoutRecord", [9]),
        ],
        "analysis-result.serve-previous": [
            R("no-uncertainty", "An estimated value carries its uncertainty", [rep("/uncertainty", None)], "uncertaintyMissing", [20]),
            R("value-and-reason", "Exactly one of value and unavailable reason", [rep("/unavailableReason", "occluded")], "valueOrReason", [20]),
            R("unknown-capability", "Capabilities come from the registry", [rep("/capabilityId", "serveSpeed.live")], "unknownCapability", [20]),
            R("validated-label", "A label cannot exceed its capability", [rep("/label", "validated")], "labelExceedsCapability"),
            R("spin-value", "Unsupported capabilities never carry a value", [rep("/capabilityId", "spinRpm")], "capabilityUnsupported"),
            S("score-effect", "A result never changes the score", [rep("/scoreEffect", "awardPoint")], [22]),
            S("wrist-speed", "Wrist movement is not ball speed", [rep("/kind", "wristSpeed")], [20]),
            R("value-outside-range", "The value lies inside its stated uncertainty", [rep("/value", "90")], "uncertaintyExcludesValue"),
        ],
        "analysis-result.bounce-review": [
            R("line-call-value", "No automated line call values", [rep("/value", "3"), rep("/units", "cm"), rep("/unavailableReason", None),
                                                                    rep("/uncertainty", {"lower": "0", "upper": "9", "level": "range"})],
              "capabilityUnsupported", [22]),
        ],
    }


# ----- vectors -----------------------------------------------------------------------------------------------------

def v_freshness():
    def c(case_id, why, age, since, bounded=True, baseline=True, transit=0, expect="Fresh", rows=None):
        case = {"id": case_id, "why": why, "input": {"senderAgeMs": age, "sinceAcceptMs": since, "transitBounded": bounded,
                                                     "baselineValid": baseline, "transitMs": transit if bounded else None},
                "expect": expect}
        if rows:
            case["acceptanceRows"] = rows
        return case
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "freshness",
            "status": "Proposal thresholds (fresh <= 5 s, delayed <= 15 s); ported and extended from docs/handoff/adaptive-v3/scripts/verify_protocol_fixtures.py",
            "cases": [
                c("fresh-at-bridge", "1 s at the bridge, accepted now", 1000, 0),
                c("fresh-boundary", "5 000 ms is still fresh", 5000, 0),
                c("delayed-just-over", "5 001 ms is delayed", 5001, 0, expect="Delayed"),
                c("delayed-by-watch-time", "2 s at bridge + 4 s on the watch = 6 s", 2000, 4000, expect="Delayed", rows=[7]),
                c("delayed-boundary", "15 000 ms is still delayed", 15000, 0, expect="Delayed"),
                c("unknown-just-over", "15 001 ms is Unknown", 15001, 0, expect="Unknown", rows=[6]),
                c("unknown-by-watch-time", "2 s at bridge + 14 s on the watch = 16 s", 2000, 14000, expect="Unknown", rows=[7]),
                c("transit-counts", "Known transit is added: 3 000 + 2 500 = 5 500", 3000, 0, transit=2500, expect="Delayed"),
                c("queued-arrives-now", "A queued delivery that arrived this instant is still Unknown", 0, 0, bounded=False, expect="Unknown", rows=[8]),
                c("baseline-lost", "A restarted process has no valid monotonic baseline", 0, 0, baseline=False, expect="Unknown", rows=[3]),
                c("interactive-refresh", "A bounded interactive exchange establishes freshness again", 1000, 200, transit=150, rows=[8]),
                c("negative-sender-age", "Negative ages are invalid input", -1, 0, expect={"error": "negativeAge"}),
                c("negative-since-accept", "Negative ages are invalid input", 0, -5, expect={"error": "negativeAge"}),
                {"id": "bounded-without-bound", "why": "A bounded transit must state its bound",
                 "input": {"senderAgeMs": 0, "sinceAcceptMs": 0, "transitBounded": True, "baselineValid": True, "transitMs": None},
                 "expect": {"error": "transitBoundMissing"}},
            ]}


ALL_FRESH = {"c1": "Fresh", "c2": "Fresh", "c3": "Unknown", "c4": "Fresh", "c5": "Fresh", "c6": "Fresh"}
ALL_UNKNOWN = {f"c{i}": "Unknown" for i in range(1, 7)}


def v_watch_sample():
    def cnt(fresh, delayed, unknown, fresh_rec, reported=6, claim=False):
        return {"enrolled": 6, "fresh": fresh, "delayed": delayed, "unknown": unknown, "reportedRecording": reported,
                "freshRecording": fresh_rec, "canClaimAllRecording": claim}
    five_fresh = {"c1": "Fresh", "c2": "Fresh", "c3": "Fresh", "c4": "Fresh", "c5": "Fresh"}
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "watch-sample",
            "status": "Sample: design-reference/adaptive/brief/watch-snapshot.sample.json and its jovra.room.watch-bridge/1 adaptation; counts are over the roster",
            "cases": [
                {"id": "design-sample-raw", "why": "The unchanged design sample: 5 of 6 fresh, c3 Unknown, c3 elapsed frozen at 12:26",
                 "source": "design", "acceptanceRows": [6],
                 "expect": {"freshness": ALL_FRESH, "counts": cnt(5, 0, 1, 5), "frozenElapsedMs": {"c3": 746000}}},
                {"id": "bridge-at-accept", "why": "The adapted bridge record, read the instant it was accepted", "source": "bridge",
                 "nowMonoMs": 0, "currentBaselineId": "sample-watch-boot-1", "bridgePatch": [],
                 "expect": {"freshness": ALL_FRESH, "counts": cnt(5, 0, 1, 5)}},
                {"id": "watch-holds-3500", "why": "3.5 s later on the watch: 1 s cameras stay fresh, 2 s cameras become delayed",
                 "source": "bridge", "nowMonoMs": 3500, "currentBaselineId": "sample-watch-boot-1", "bridgePatch": [],
                 "expect": {"freshness": {"c1": "Fresh", "c2": "Delayed", "c3": "Unknown", "c4": "Fresh", "c5": "Fresh", "c6": "Delayed"},
                            "counts": cnt(3, 2, 1, 3)}},
                {"id": "bridge-stale", "why": "The phone heard every camera recently, but the watch has not heard the bridge for 20 s",
                 "source": "bridge", "nowMonoMs": 20000, "currentBaselineId": "sample-watch-boot-1", "bridgePatch": [],
                 "acceptanceRows": [7], "expect": {"freshness": ALL_UNKNOWN, "counts": cnt(0, 0, 6, 0)}},
                {"id": "queued-after-suspension", "why": "A queued context delivered on resume has unbounded transit",
                 "source": "bridge", "nowMonoMs": 0, "currentBaselineId": "sample-watch-boot-1", "acceptanceRows": [8],
                 "bridgePatch": [rep("/receiverObservation/delivery", "queued"), rep("/receiverObservation/transitBounded", False),
                                 rep("/receiverObservation/transitMs", None)],
                 "expect": {"freshness": ALL_UNKNOWN, "counts": cnt(0, 0, 6, 0)}},
                {"id": "interactive-refresh", "why": "A reachable request/ack bounds transit at 300 ms; 500 ms later",
                 "source": "bridge", "nowMonoMs": 500, "currentBaselineId": "sample-watch-boot-1", "acceptanceRows": [8],
                 "bridgePatch": [rep("/receiverObservation/delivery", "interactive"), rep("/receiverObservation/transitMs", 300)],
                 "expect": {"freshness": ALL_FRESH, "counts": cnt(5, 0, 1, 5)}},
                {"id": "watch-process-restart", "why": "Cached snapshot after the watch app restarted: every age is Unknown",
                 "source": "bridge", "nowMonoMs": 100, "currentBaselineId": "sample-watch-boot-2", "bridgePatch": [],
                 "acceptanceRows": [3], "expect": {"freshness": ALL_UNKNOWN, "counts": cnt(0, 0, 6, 0)}},
                {"id": "missing-camera-row", "why": "D8: five fresh recording rows and one enrolled camera with no row is not 'all recording'",
                 "source": "bridge", "nowMonoMs": 0, "currentBaselineId": "sample-watch-boot-1", "acceptanceRows": [6, 7],
                 "bridgePatch": [rep("/devices/2/ageAtBridgeMs", 1000), rem("/devices/5")],
                 "expect": {"freshness": five_fresh, "counts": cnt(5, 0, 1, 5, reported=5)}},
                {"id": "reboot-reused-baseline", "why": "D18: a baseline id reused after a reboot with the clock behind is Unknown, never a crash",
                 "source": "bridge", "nowMonoMs": 100, "currentBaselineId": "sample-watch-boot-1", "acceptanceRows": [3],
                 "bridgePatch": [rep("/receiverObservation/acceptedAtMonoMs", 50000)],
                 "expect": {"freshness": ALL_UNKNOWN, "counts": cnt(0, 0, 6, 0)}},
            ]}


def v_phone_status():
    obs = {"transitBounded": True, "transitMs": 40, "processBaselineId": "sample-phone-boot-1", "acceptedAtMonoMs": 1000}

    def case(case_id, why, now, observation=None, patch=(), local=None, baseline="sample-phone-boot-1", expect=None, rows=None):
        c = {"id": case_id, "why": why, "snapshotPatch": list(patch), "observation": observation or dict(obs),
             "nowMonoMs": now, "currentBaselineId": baseline, "localDeviceId": local, "expect": expect}
        if rows:
            c["acceptanceRows"] = rows
        return c

    def cnt(fresh, delayed, unknown, fresh_rec, claim=False):
        return {"enrolled": 6, "fresh": fresh, "delayed": delayed, "unknown": unknown, "reportedRecording": 6,
                "freshRecording": fresh_rec, "canClaimAllRecording": claim}
    all_fresh = {f"c{i}": "Fresh" for i in range(1, 7)}
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "phone-status",
            "status": "D18: the phone participant path, age = ageAtHostMs + host-to-phone transit + time since accept, over records/room-snapshot.json",
            "cases": [
                case("phone-at-accept", "40 ms transit, read at accept: c3 (17.5 s at the host) is Unknown", 1000,
                     expect={"freshness": ALL_FRESH, "counts": cnt(5, 0, 1, 5)}, rows=[6]),
                case("phone-held-4600", "4.6 s later every row has aged past 5 s", 5600,
                     expect={"freshness": {"c1": "Delayed", "c2": "Delayed", "c3": "Unknown", "c4": "Delayed", "c5": "Delayed", "c6": "Delayed"},
                             "counts": cnt(0, 5, 1, 0)}, rows=[6]),
                case("phone-local-camera", "The phone is c1; its own capture is Local and counts as fresh, so six recording cameras can be claimed",
                     1000, patch=[rep("/devices/2/ageAtHostMs", 500)], local="c1",
                     expect={"freshness": dict(all_fresh, c1="Local"), "counts": cnt(6, 0, 0, 6, claim=True)}, rows=[6]),
                case("phone-queued", "A snapshot whose transit cannot be bounded is Unknown", 1000,
                     observation=dict(obs, transitBounded=False, transitMs=None),
                     expect={"freshness": ALL_UNKNOWN, "counts": cnt(0, 0, 6, 0)}, rows=[8]),
                case("phone-restart", "A restarted phone process has no valid baseline", 1000, baseline="sample-phone-boot-2",
                     expect={"freshness": ALL_UNKNOWN, "counts": cnt(0, 0, 6, 0)}, rows=[3]),
            ]}


def v_display():
    c3 = {"deviceId": "c3", "captureState": "Recording", "lastReportedElapsedMs": 746000}

    def row(dev, fresh, age, stale, may, elapsed, source="last-reported", is_local=False, local=None):
        return {"device": dev, "freshness": fresh, "ageMs": age, "isLocal": is_local, "localElapsedMs": local,
                "expect": {"deviceId": dev["deviceId"], "freshness": "Local" if is_local else fresh, "elapsedMs": elapsed,
                           "elapsedSource": source, "extrapolated": False, "stale": stale,
                           "lastHeardAgeMs": 0 if is_local else age, "mayStillBeRecording": may,
                           "captureState": dev["captureState"]}}
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "display",
            "status": "Status-row semantics; remote elapsed durations are never extrapolated",
            "cases": [
                {"id": "c3-silent-recording", "why": "Camera reported Recording, then nothing for 18 s: 12:26 stays frozen, 'May still be recording'",
                 "acceptanceRows": [6], **row(c3, "Unknown", 18000, True, True, 746000)},
                {"id": "delayed-recording", "why": "9 s since the last report: delayed, frozen, may still be recording",
                 "acceptanceRows": [6], **row(dict(c3, deviceId="c2"), "Delayed", 9000, True, True, 746000)},
                {"id": "fresh-not-extrapolated", "why": "Even a fresh remote row shows the reported value, not a running clock",
                 **row(dict(c3, deviceId="c1"), "Fresh", 1000, False, False, 746000)},
                {"id": "unknown-no-age", "why": "After a restart the last-heard age is not known either", "acceptanceRows": [3],
                 **row(c3, "Unknown", None, True, True, 746000)},
                {"id": "saved-stale", "why": "A saved camera that falls silent is not 'may still be recording'",
                 **row(dict(c3, captureState="Saved"), "Unknown", 30000, True, False, 746000)},
                {"id": "local-timer", "why": "Only the device's own UI runs its local capture timer",
                 **row(dict(c3, deviceId="c4"), "Fresh", 0, False, False, 760500, source="local-timer", is_local=True, local=760500)},
            ]}


def v_disconnect():
    snap = rec_snapshot()
    remote = [{k: d[k] for k in ("deviceId", "captureState", "lastReportedElapsedMs")} for d in snap["devices"][1:]]
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "disconnect",
            "status": "The room link is lost on the primary camera; it keeps recording locally",
            "cases": [{
                "id": "host-or-network-lost", "why": "Local originals survive; no stop of any kind; cached remote rows become Unknown and keep their last elapsed value",
                "acceptanceRows": [6, 17],
                "local": {"deviceId": "c1", "captureState": "Recording", "lastReportedElapsedMs": 754000},
                "remote": remote,
                "expect": {"localCaptureState": "Recording", "commandsIssued": [],
                           "counts": {"enrolled": 5, "fresh": 0, "delayed": 0, "unknown": 5, "reportedRecording": 5,
                                      "freshRecording": 0, "canClaimAllRecording": False},
                           "frozenElapsedMs": {d["deviceId"]: d["lastReportedElapsedMs"] for d in remote},
                           "mayStillBeRecording": {d["deviceId"]: True for d in remote}},
            }]}


def v_snapshot():
    members = ["c1", "c2", "c3", "c4", "c5", "c6"]
    init = {"sessionId": SESSION, "hostEpoch": EPOCH, "hostKey": HOST_KEY, "hostDeviceId": "c1", "members": members,
            "rosterRevision": 1}
    new_host = [rep("/hostEpoch", 4), rep("/hostKeySha256", NEW_HOST_KEY), rep("/hostDeviceId", "c2")]

    def acc(patch, expect, seq=None):
        p = list(patch)
        if seq is not None:
            p.append(rep("/snapshotSeq", seq))
        return {"op": "accept", "envelopePatch": p, "expect": expect}

    def reconcile(epoch, key, expect, host="c2"):
        return {"op": "reconcile", "newEpoch": epoch, "hostKey": key, "hostDeviceId": host,
                "approvedHostKeys": [NEW_HOST_KEY], "expect": expect}
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "snapshot",
            "status": "Envelope patches apply to records/room-snapshot.json; every patched envelope is schema-valid. Nothing unauthenticated changes receiver state",
            "cases": [
                {"id": "replay-and-order", "why": "Strictly increasing snapshotSeq; replays and reordering are rejected",
                 "acceptanceRows": [5], "initial": init, "steps": [
                     acc([], "accepted", 12), acc([], "replayOrOutOfOrder", 12), acc([], "replayOrOutOfOrder", 11),
                     acc([], "accepted", 13), {"op": "assert", "expect": {"lastSeq": 13, "hostEpoch": 3}}]},
                {"id": "wrong-session", "why": "Another session's envelope", "acceptanceRows": [5], "initial": init,
                 "steps": [acc([rep("/sessionId", "other-room")], "wrongSession")]},
                {"id": "old-epoch", "why": "A previous host epoch is never fresh authority", "acceptanceRows": [5],
                 "initial": init, "steps": [acc([rep("/hostEpoch", 2)], "staleEpoch")]},
                {"id": "wrong-host-key", "why": "Same epoch, different host key: an impostor host", "acceptanceRows": [5],
                 "initial": init, "steps": [acc([rep("/hostKeySha256", ROGUE_KEY)], "hostKeyMismatch")]},
                {"id": "host-device-changed", "why": "D7: the host device cannot change under the same epoch and key",
                 "acceptanceRows": [5], "initial": init,
                 "steps": [acc([], "accepted", 12), acc([rep("/hostDeviceId", "c4")], "hostDeviceChanged", 13)]},
                {"id": "unauthenticated-device", "why": "Identity is the roster, not a caller-supplied name",
                 "acceptanceRows": [5], "initial": init,
                 "steps": [acc([rep("/devices/5/deviceId", "c7")], "unauthenticatedDevice")]},
                {"id": "device-seq-regression", "why": "A device's sequence cannot go back within one capture instance; a new instance may restart it",
                 "acceptanceRows": [5], "initial": init, "steps": [
                     acc([], "accepted", 12),
                     acc([rep("/devices/0/deviceSeq", 3)], "deviceSeqRegressed", 13),
                     acc([rep("/devices/0/deviceSeq", 1), rep("/devices/0/captureInstanceId", "sample-c1-take2")], "accepted", 13)]},
                {"id": "capture-instance-rollback", "why": "D7: a device never returns to a capture instance it has left",
                 "acceptanceRows": [5], "initial": init, "steps": [
                     acc([], "accepted", 12),
                     acc([rep("/devices/0/deviceSeq", 1), rep("/devices/0/captureInstanceId", "sample-c1-take2")], "accepted", 13),
                     acc([rep("/devices/0/deviceSeq", 7)], "captureInstanceRetired", 14)]},
                {"id": "event-revision-rollback", "why": "D7: a higher snapshotSeq cannot roll the score back",
                 "acceptanceRows": [5, 12], "initial": init, "steps": [
                     acc([], "accepted", 12),
                     acc([rep("/eventRevision", 37), rep("/score/eventRevision", 37)], "eventRevisionRegressed", 13),
                     acc([rep("/eventRevision", 43), rep("/score/eventRevision", 43)], "accepted", 13)]},
                {"id": "device-seq-reused", "why": "D7: one deviceSeq is one report; the host's age measurement may change, the content may not",
                 "acceptanceRows": [5], "initial": init, "steps": [
                     acc([], "accepted", 12),
                     acc([rep("/devices/0/captureState", "Saved")], "deviceSeqReused", 13),
                     acc([rep("/devices/0/ageAtHostMs", 4500)], "accepted", 13)]},
                {"id": "roster-grows", "why": "D8: an approved camera joins with a higher roster revision; the roster never changes without one",
                 "acceptanceRows": [5], "initial": dict(init, members=members[:5]), "steps": [
                     acc([], "rosterChangedWithoutRevision", 12),
                     acc([rep("/roster/rosterRevision", 2)], "accepted", 12),
                     acc([], "rosterRegressed", 13),
                     acc([rep("/roster/rosterRevision", 2), rem("/devices/5")], "accepted", 13),
                     {"op": "assert", "expect": {"rosterRevision": 2, "members": members, "lastSeq": 13}}]},
                {"id": "forged-higher-epoch-ignored", "why": "D2: an unauthenticated higher-epoch envelope changes nothing; the receiver stays live and can still reconcile",
                 "acceptanceRows": [5, 17], "initial": init, "steps": [
                     acc([], "accepted", 12),
                     acc([rep("/hostEpoch", 1003), rep("/hostKeySha256", "0" * 64)], "epochChangeRequiresReconciliation", 1),
                     {"op": "assert", "expect": {"lastSeq": 12, "hostEpoch": 3}},
                     acc([], "accepted", 13),
                     reconcile(4, NEW_HOST_KEY, "reconciled"),
                     acc(new_host, "accepted", 0)]},
                {"id": "epoch-change-reconcile", "why": "A new epoch is adopted only through reconcile() with an approved, authenticated host key",
                 "acceptanceRows": [5, 17], "initial": init, "steps": [
                     acc([], "accepted", 12),
                     acc(new_host, "epochChangeRequiresReconciliation", 0),
                     acc([], "accepted", 13),
                     reconcile(4, ROGUE_KEY, "hostNotAuthenticated"),
                     reconcile(3, NEW_HOST_KEY, "epochNotNewer"),
                     reconcile(4, NEW_HOST_KEY, "reconciled"),
                     acc(new_host, "accepted", 0),
                     acc([], "staleEpoch", 14),
                     {"op": "assert", "expect": {"lastSeq": 0, "hostEpoch": 4, "hostDeviceId": "c2"}}]},
                {"id": "restart-keeps-replay-protection", "why": "Sequence high-water marks and retired capture instances persist across process death",
                 "acceptanceRows": [3], "initial": init, "steps": [
                     acc([], "accepted", 12),
                     acc([rep("/devices/0/deviceSeq", 1), rep("/devices/0/captureInstanceId", "sample-c1-take2")], "accepted", 13),
                     {"op": "restart"}, acc([], "replayOrOutOfOrder", 13), acc([], "captureInstanceRetired", 14),
                     acc([rep("/devices/0/deviceSeq", 2), rep("/devices/0/captureInstanceId", "sample-c1-take2")], "accepted", 14)]},
            ]}


def v_bridge():
    paired = "sample-bridge-phone"

    def acc(patch, expect):
        return {"op": "accept", "bridgePatch": list(patch), "expect": expect}

    def seq(n):
        return rep("/bridge/bridgeSeq", n)
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "bridge",
            "status": "D6: watch-side acceptance of records/watch-bridge.sample.json; the watch is paired to sample-bridge-phone",
            "cases": [
                {"id": "replayed-payload", "why": "The same bridgeSeq re-delivered as 'interactive' is a replay, not a refresh",
                 "acceptanceRows": [5, 8], "pairedPhoneId": paired, "steps": [
                     acc([], "accepted"),
                     acc([rep("/receiverObservation/delivery", "interactive"), rep("/receiverObservation/transitMs", 40)], "replayOrOutOfOrder"),
                     acc([seq(7)], "replayOrOutOfOrder"),
                     acc([seq(9)], "accepted")]},
                {"id": "not-paired-bridge", "why": "Only the watch's own paired phone is a bridge", "acceptanceRows": [5],
                 "pairedPhoneId": paired, "steps": [acc([rep("/bridge/bridgeDeviceId", "p-other")], "notPairedBridge")]},
                {"id": "bridge-restart", "why": "A restarted bridge starts a new instance; the old instance can never come back",
                 "acceptanceRows": [5], "pairedPhoneId": paired, "steps": [
                     acc([], "accepted"),
                     acc([rep("/bridge/bridgeInstanceId", "sample-bridge-run-2"), seq(1)], "accepted"),
                     acc([seq(9)], "bridgeInstanceRetired")]},
                {"id": "session-regression", "why": "Within one session and epoch, snapshotSeq and eventRevision never go back; an older epoch is refused",
                 "acceptanceRows": [5, 12], "pairedPhoneId": paired, "steps": [
                     acc([], "accepted"),
                     acc([seq(9), rep("/snapshotSeq", 7)], "snapshotSeqRegressed"),
                     acc([seq(10), rep("/eventRevision", 41), rep("/score/eventRevision", 41)], "eventRevisionRegressed"),
                     acc([seq(11), rep("/hostEpoch", 2)], "staleEpoch"),
                     acc([seq(12), rep("/snapshotSeq", 8)], "accepted")]},
                {"id": "new-session", "why": "The phone joined the next match; the previous session's payloads stay behind the bridge sequence",
                 "pairedPhoneId": paired, "steps": [
                     acc([], "accepted"),
                     acc([seq(9), rep("/sessionId", "sample-next-match"), rep("/snapshotSeq", 1), rep("/eventRevision", 0),
                          rep("/score/eventRevision", 0)], "accepted"),
                     acc([], "replayOrOutOfOrder")]},
                {"id": "watch-restart-keeps-marks", "why": "Replay marks persist across a watch restart (freshness does not)",
                 "acceptanceRows": [3], "pairedPhoneId": paired, "steps": [
                     acc([], "accepted"), {"op": "restart"}, acc([], "replayOrOutOfOrder"), acc([seq(9)], "accepted")]},
            ]}


def canonical_json(obj) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def qr_text(raw_json: str, pad=False) -> str:
    body = base64.urlsafe_b64encode(raw_json.encode("utf-8")).decode("ascii")
    return "jovra-room:1:" + (body if pad else body.rstrip("="))


def v_invitation():
    secrets = {"note": "Sample secrets derived from public strings; not credentials. A real host keeps tokens in its secure store.",
               "tokens": {"inv-c2": TOKEN_C2, "inv-scorer": TOKEN_SCORER},
               "nonces": {"inv-c2": NONCE_C2, "inv-scorer": NONCE_SCORER}}
    init = {"sessionId": SESSION, "hostEpoch": EPOCH, "hostKey": HOST_KEY, "members": {"c1": HOST_KEY},
            "records": ["records/invitation.json", "records/invitation.scorer.json"]}
    code_1 = sas(HOST_KEY, GUEST_KEY, NONCE_C2, HOST_NONCE_1, GUEST_NONCE)
    code_2 = sas(HOST_KEY, GUEST_KEY, NONCE_C2, HOST_NONCE_2, GUEST_NONCE)
    assert code_1 != code_2, "the host nonce must change the code"
    camera_grants = ["record-local", "upload-own-source", "view-own-preview", "view-room-status"]

    def res(result, code=None, grants=(), verification=None, host_nonce=None, device=None):
        return {"result": result, "code": code, "grants": list(grants), "verificationCode": verification,
                "hostNonce": host_nonce, "deviceId": device}
    rejected = lambda code: res("rejected", code)  # noqa: E731
    ok = res("accepted", grants=camera_grants, device="c2")

    def join(now, patch=(), expect=None, host_nonce=HOST_NONCE_1):
        return {"op": "join", "requestPatch": list(patch), "now": now, "hostNonce": host_nonce,
                "expect": expect if expect is not None else res("challenge", host_nonce=host_nonce)}

    def reveal(expect, guest_nonce=GUEST_NONCE, invite="inv-c2"):
        return {"op": "reveal", "inviteId": invite, "guestNonce": guest_nonce, "expect": expect}

    def approve(now, confirmed=True, expect=None, invite="inv-c2"):
        return {"op": "approve", "inviteId": invite, "confirmed": confirmed, "now": now, "expect": expect}

    def lookup(code, source, now, result, invite=None):
        return {"op": "lookup", "code": code, "source": source, "now": now,
                "expect": {"result": result, "inviteId": invite, "authenticates": False}}

    def declined(host_nonce, code):
        return [join(t1, host_nonce=host_nonce), reveal(res("awaitingHostApproval", verification=code)),
                approve(t1, False, rejected("verificationNotConfirmed"))]
    t1, t_end, t_late = "2026-10-07T21:12:00Z", "2026-10-07T21:20:00Z", "2026-10-07T21:20:01Z"
    waiting_1 = res("awaitingHostApproval", verification=code_1)
    scorer_commit = commitment(GUEST_KEY, GUEST_NONCE)
    scorer_join = [rep("/inviteId", "inv-scorer"), rep("/requestedCaptureRole", "none"), rep("/requestedCommandRole", "scorer"),
                   rep("/proof", proof(TOKEN_SCORER, "inv-scorer", NONCE_SCORER, GUEST_KEY, scorer_commit))]
    payload = rec_payload()
    canon = canonical_json(payload)
    dup_key = canon[:-1] + ',"hostKeySha256":"' + ROGUE_KEY + '"}'
    spaced = json.dumps(payload, sort_keys=True, ensure_ascii=False)
    good = qr_text(canon)
    assert "=" in qr_text(canon, pad=True), "the padded variant must differ from the unpadded one"
    payload_cases = [
        {"op": "joinerVerify", "payloadPatch": [], "observedHostKey": HOST_KEY, "expect": "ok"},
        {"op": "joinerVerify", "payloadPatch": [], "observedHostKey": ROGUE_KEY, "expect": "hostFingerprintMismatch"},
        {"op": "joinerVerify", "payloadPatch": [rep("/endpoints/1/address", "203.0.113.7")], "observedHostKey": HOST_KEY,
         "expect": "endpointNotAllowed"},
        {"op": "joinerVerify", "payloadPatch": [rep("/commandRole", "capture-controller")], "observedHostKey": HOST_KEY,
         "expect": "cameraCannotControl"},
        {"op": "decodeQr", "text": "https://jovra.example/join?code=JVR-482", "expect": {"error": "notJovraRoomCode"}},
        {"op": "decodeQr", "text": "jovra-room:1:%%%", "expect": {"error": "malformedPayload"}},
        {"op": "decodeQr", "fromPayload": True, "expect": {"roundTrip": True}},
    ]
    strict_qr = [
        {"op": "decodeQr", "text": good, "expect": {"decoded": True}},
        {"op": "decodeQr", "text": good[:20] + "!!**" + good[20:], "expect": {"error": "malformedPayload"}},
        {"op": "decodeQr", "text": qr_text(canon, pad=True), "expect": {"error": "malformedPayload"}},
        {"op": "decodeQr", "text": qr_text(dup_key), "expect": {"error": "duplicateKey"}},
        {"op": "decodeQr", "text": qr_text(spaced), "expect": {"error": "nonCanonicalPayload"}},
    ]
    resolved = [
        {"op": "checkResolved", "address": "192.168.1.20", "port": 47100, "expect": "ok"},
        {"op": "checkResolved", "address": "fe80::1c2a:3bff:fe4d:5e6f", "port": 47100, "expect": "ok"},
        {"op": "checkResolved", "address": "93.184.216.34", "port": 47100, "expect": "endpointNotAllowed"},
        {"op": "checkResolved", "address": "127.0.0.1", "port": 47100, "expect": "endpointNotAllowed"},
        {"op": "checkResolved", "address": "192.168.1.20", "port": 443, "expect": "endpointNotAllowed"},
    ]
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "invitation",
            "status": "Sample host (device c1) with records/invitation.json (camera, viewer) and records/invitation.scorer.json; join requests patch records/join-request.json; host nonces are per attempt",
            "secrets": secrets,
            "cases": [
                {"id": "happy-path", "why": "Proof checks, the host challenges, the guest reveals, both screens show the same code, host approves, single use consumed",
                 "initial": init, "steps": [join(t1), reveal(waiting_1), approve(t1, expect=ok),
                                            {"op": "assertRecord", "inviteId": "inv-c2", "expect": {"status": "used", "usedByDeviceId": "c2", "usedAt": t1}}]},
                {"id": "replayed-invite", "why": "The same token presented again after use is refused and exposes nothing",
                 "acceptanceRows": [4], "initial": init,
                 "steps": [join(t1), reveal(waiting_1), approve(t1, expect=ok), join("2026-10-07T21:13:00Z", expect=rejected("alreadyUsed")),
                           join("2026-10-07T21:13:00Z", [rep("/guestDeviceId", "c5")], rejected("alreadyUsed"))]},
                {"id": "join-in-progress", "why": "A second presentation while one is pending is refused", "acceptanceRows": [4],
                 "initial": init, "steps": [join(t1), join(t1, expect=rejected("joinInProgress"))]},
                {"id": "expired-invite", "why": "One second after expiry on the host's own clock", "acceptanceRows": [4],
                 "initial": init, "steps": [join(t_late, expect=rejected("expired")),
                                            {"op": "assertRecord", "inviteId": "inv-c2", "expect": {"status": "expired"}}]},
                {"id": "expiry-boundary", "why": "Exactly at expiresAt is still valid", "initial": init, "steps": [join(t_end)]},
                {"id": "expired-while-waiting", "why": "Approval after expiry is refused", "acceptanceRows": [4], "initial": init,
                 "steps": [join("2026-10-07T21:19:30Z"), reveal(waiting_1), approve(t_late, expect=rejected("expired"))]},
                {"id": "wrong-session", "why": "A request for another session", "acceptanceRows": [5], "initial": init,
                 "steps": [join(t1, [rep("/sessionId", "other-room")], rejected("wrongSession"))]},
                {"id": "wrong-epoch", "why": "A request bound to another host epoch", "acceptanceRows": [5], "initial": init,
                 "steps": [join(t1, [rep("/hostEpoch", 2)], rejected("revoked"))]},
                {"id": "impostor-host", "why": "The guest observed a different TLS key than the QR pinned", "acceptanceRows": [5],
                 "initial": init, "steps": [join(t1, [rep("/observedHostKeySha256", ROGUE_KEY)], rejected("hostFingerprintMismatch"))]},
                {"id": "guessed-token", "why": "Knowing the display code is not knowing the token", "acceptanceRows": [4],
                 "initial": init,
                 "steps": [join(t1, [rep("/proof", proof(b64token("guess"), "inv-c2", NONCE_C2, GUEST_KEY, GUEST_COMMIT))], rejected("badProof"))]},
                {"id": "proof-bound-to-guest-key", "why": "A proof made for one guest key fails for another", "acceptanceRows": [4],
                 "initial": init, "steps": [join(t1, [rep("/guestKeySha256", sha("sample-guest-key-c5"))], rejected("badProof"))]},
                {"id": "proof-bound-to-commitment", "why": "A proof made for one commitment fails for another", "acceptanceRows": [4],
                 "initial": init, "steps": [join(t1, [rep("/guestCommitment", commitment(GUEST_KEY, b64token("other")))], rejected("badProof"))]},
                {"id": "role-escalation", "why": "The invitation's role is the role; a guest cannot ask for more", "acceptanceRows": [14],
                 "initial": init, "steps": [join(t1, [rep("/requestedCommandRole", "scorer")], rejected("roleMismatch"))]},
                {"id": "unknown-invite", "why": "No such invitation", "initial": init,
                 "steps": [join(t1, [rep("/inviteId", "inv-zz")], rejected("unknownInvite"))]},
                {"id": "codes-not-confirmed", "why": "The host did not confirm matching verification codes", "acceptanceRows": [5],
                 "initial": init, "steps": declined(HOST_NONCE_1, code_1) + [
                     {"op": "assertRecord", "inviteId": "inv-c2", "expect": {"status": "issued"}}]},
                {"id": "commitment-mismatch", "why": "D3: a reveal that does not open the commitment fails the attempt; nothing is pending afterwards",
                 "acceptanceRows": [4, 5], "initial": init, "steps": [
                     join(t1), reveal(rejected("commitmentMismatch"), guest_nonce=b64token("sample-ground-nonce")),
                     reveal(rejected("noPendingJoin")), {"op": "assertRecord", "inviteId": "inv-c2", "expect": {"status": "issued"}}]},
                {"id": "reveal-before-challenge", "why": "A reveal without a challenged join is refused", "initial": init,
                 "steps": [reveal(rejected("noPendingJoin")), approve(t1, expect=rejected("noPendingJoin"))]},
                {"id": "host-nonce-binds-code", "why": "D3: the code depends on a host nonce chosen after the guest committed, so it cannot be precomputed from the QR",
                 "acceptanceRows": [5], "initial": init, "steps": declined(HOST_NONCE_1, code_1) + [
                     join(t1, host_nonce=HOST_NONCE_2), reveal(res("awaitingHostApproval", verification=code_2))]},
                {"id": "attempts-exhausted", "why": "D11: three declined attempts by token holders revoke the invitation; no endless approval prompts",
                 "acceptanceRows": [4], "initial": init, "steps":
                     declined(HOST_NONCE_1, code_1) + declined(HOST_NONCE_2, code_2)
                     + declined(HOST_NONCE_3, sas(HOST_KEY, GUEST_KEY, NONCE_C2, HOST_NONCE_3, GUEST_NONCE)) + [
                     {"op": "assertRecord", "inviteId": "inv-c2", "expect": {"status": "revoked", "revokedReason": "attemptsExhausted"}},
                     join(t1, expect=rejected("revoked"))]},
                {"id": "already-member", "why": "D17: a member cannot join again under a second invitation (no implicit role upgrade)",
                 "acceptanceRows": [14], "initial": init, "steps": [
                     join(t1), reveal(waiting_1), approve(t1, expect=ok),
                     join(t1, scorer_join, rejected("alreadyMember")),
                     join(t1, scorer_join + [rep("/guestDeviceId", "c2-again")], rejected("alreadyMember")),
                     {"op": "assertRecord", "inviteId": "inv-scorer", "expect": {"status": "issued"}}]},
                {"id": "host-is-member", "why": "The host's own key cannot be enrolled as a guest", "acceptanceRows": [14],
                 "initial": init, "steps": [join(t1, [rep("/guestDeviceId", "c1")], rejected("alreadyMember"))]},
                {"id": "host-transfer-revokes", "why": "A new host epoch revokes every open invitation", "acceptanceRows": [5, 17],
                 "initial": init, "steps": [
                     {"op": "transferHost", "newEpoch": 4, "newHostKey": NEW_HOST_KEY, "expect": {"revoked": ["inv-c2", "inv-scorer"]}},
                     join(t1, expect=rejected("revoked")),
                     join(t1, [rep("/hostEpoch", 4), rep("/observedHostKeySha256", NEW_HOST_KEY)], rejected("revoked")),
                     {"op": "assertRecord", "inviteId": "inv-scorer", "expect": {"status": "revoked", "revokedReason": "hostTransfer"}}]},
                {"id": "display-code-lookup", "why": "A display code finds an invitation for host approval; it never authenticates",
                 "acceptanceRows": [4], "initial": init, "steps": [
                     lookup("JVR-482", "guest-a", t1, "found", "inv-c2"), lookup("JVR-517", "guest-a", t1, "found", "inv-scorer")]},
                {"id": "display-code-guessing", "why": "D11: five misses throttle that source for a 10-minute window; other sources and the code itself keep working",
                 "acceptanceRows": [4], "initial": init, "steps":
                     [lookup(f"JVR-00{i}", "guest-a", f"2026-10-07T21:10:0{i}Z", "notFound") for i in range(5)] + [
                     lookup("JVR-482", "guest-a", "2026-10-07T21:10:05Z", "lookupThrottled"),
                     lookup("JVR-482", "guest-b", "2026-10-07T21:10:06Z", "found", "inv-c2"),
                     lookup("JVR-482", "guest-a", "2026-10-07T21:20:00Z", "found", "inv-c2")]},
                {"id": "lookup-ignores-expired", "why": "D18: an expired invitation is never found, even before anything else marks it",
                 "acceptanceRows": [4], "initial": init, "steps": [
                     lookup("JVR-482", "guest-a", t_late, "notFound"),
                     {"op": "assertRecord", "inviteId": "inv-c2", "expect": {"status": "expired"}}]},
                {"id": "joiner-side-checks", "why": "Before sending anything the guest checks roles, lifetime, endpoints and the pinned key; a QR is never a URL. The joiner never compares its own clock with the host's (D14): expiry is the host's decision",
                 "acceptanceRows": [4, 5], "initial": init, "steps": payload_cases},
                {"id": "strict-qr", "why": "D15: every port decodes the same bytes the same way: base64url alphabet, no padding, no duplicate keys, canonical JSON only",
                 "acceptanceRows": [5], "initial": init, "steps": strict_qr},
                {"id": "dnssd-resolved-endpoint", "why": "D16: a resolved DNS-SD address passes the same LAN allow-list and port rule before connecting",
                 "acceptanceRows": [5], "initial": init, "steps": resolved},
            ]}


BOUNDED = {"transitBounded": True, "transitMs": 40, "hostHoldMs": 0}
NO_PEER = "no-peer"


def ledger_initial(**over):
    devices = {f"c{i}": {"captureState": "Recording", "reachable": True, "foreground": True, "cameraPermission": "granted"} for i in range(1, 7)}
    init = {"sessionId": SESSION, "hostEpoch": EPOCH, "eventRevision": 42,
            "members": {"m-scorer": {"roles": ["scorer"], "deviceId": "p-scorer", "watchDeviceIds": ["w-scorer"]},
                        "m-scorer2": {"roles": ["scorer"], "deviceId": "p-scorer2", "watchDeviceIds": []},
                        "m-viewer": {"roles": ["viewer"], "deviceId": "p-viewer", "watchDeviceIds": ["w-viewer"]},
                        "m-marker": {"roles": ["marker"], "deviceId": "p-marker", "watchDeviceIds": ["w-marker"]},
                        "m-controller": {"roles": ["capture-controller"], "deviceId": "p-controller", "watchDeviceIds": ["w-controller"]},
                        "m-host": {"roles": ["capture-controller", "scorer"], "deviceId": "c1", "watchDeviceIds": []}},
            "devices": devices}
    for k, v in over.items():
        if k == "deviceOverrides":
            for dev, fields in v.items():
                init["devices"][dev].update(fields)
        else:
            init[k] = v
    return init


def honest_peer(cmd):
    """The authenticated channel a command arrives on: the issuing phone, or the watch's bridge phone."""
    return {"deviceId": cmd["issuer"]["bridgeDeviceId"] or cmd["issuer"]["deviceId"]}


def sub(cmd, status, reason=None, rev=42, applied=None, conflict=None, delivery=None, results=None, peer=None):
    step = {"op": "submit", "command": cmd, "peer": None if peer == NO_PEER else (peer or honest_peer(cmd)),
            "expect": {"status": status, "reason": reason, "canonicalEventRevision": rev, "appliedRecordId": applied,
                       "conflict": conflict, "deviceResults": results or []}}
    if delivery is not None:
        step["delivery"] = delivery
    return step


def pend(*devs):
    return [{"deviceId": d, "status": "Pending", "reason": None} for d in devs]


def v_ledger():
    p43 = point("cmd-p43")
    s_scorer2 = dict(member="m-scorer2", dev="p-scorer2")
    stop_all = capture("cmd-stop-all", "StopAllRequest")
    recording = {f"c{i}": "Recording" for i in range(1, 7)}
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "ledger",
            "status": "Sample host ledger at revision 42 with six members (the host holds scorer and capture-controller) and six recording cameras; each submit names the authenticated channel peer",
            "cases": [
                {"id": "duplicate-identical", "why": "An identical retry returns the original receipt; one event", "acceptanceRows": [9],
                 "initial": ledger_initial(), "steps": [
                     sub(p43, "Accepted", rev=43, applied="evt-43"), sub(p43, "Accepted", rev=43, applied="evt-43"),
                     {"op": "assert", "expect": {"eventRevision": 43, "eventCount": 1, "tally": {"jon": 1}, "securityLog": []}}]},
                {"id": "same-id-different-payload", "why": "Reusing an id with different contents is rejected and security-logged; the original stands",
                 "acceptanceRows": [10], "initial": ledger_initial(), "steps": [
                     sub(p43, "Accepted", rev=43, applied="evt-43"),
                     sub(point("cmd-p43", winner="alex"), "Rejected", "commandIdReuse", rev=43),
                     sub(point("cmd-p43", base=43), "Rejected", "commandIdReuse", rev=43),
                     sub(p43, "Accepted", rev=43, applied="evt-43"),
                     {"op": "assert", "expect": {"eventRevision": 43, "eventCount": 1, "tally": {"jon": 1},
                                                 "securityLog": [{"commandId": "cmd-p43", "code": "commandIdReuse"},
                                                                 {"commandId": "cmd-p43", "code": "commandIdReuse"}]}}]},
                {"id": "honest-retry-refreshes-age", "why": "D4: a retry that recomputes ageAtSendMs is the same command (the fingerprint excludes it), not an attack",
                 "acceptanceRows": [9, 10], "initial": ledger_initial(deviceOverrides={"c4": {"captureState": "Ready"}}), "steps": [
                     sub(capture("cmd-start-c4", "StartRequest", ["c4"], age=200), "Accepted", results=pend("c4"), delivery=BOUNDED),
                     sub(capture("cmd-start-c4", "StartRequest", ["c4"], age=5000), "Accepted", results=pend("c4"), delivery=BOUNDED),
                     {"op": "assert", "expect": {"securityLog": []}}]},
                {"id": "two-scorers-same-revision", "why": "Two writes against revision 42: one update, one visible conflict",
                 "acceptanceRows": [11], "initial": ledger_initial(), "steps": [
                     sub(p43, "Accepted", rev=43, applied="evt-43"),
                     sub(point("cmd-p43-b", winner="alex", **s_scorer2), "Conflicted", "baseRevisionStale", rev=43,
                         conflict={"baseEventRevision": 42, "currentEventRevision": 43}),
                     sub(point("cmd-p43-b2", winner="alex", base=43, **s_scorer2), "Accepted", rev=44, applied="evt-44"),
                     {"op": "assert", "expect": {"eventRevision": 44, "eventCount": 2, "tally": {"alex": 1, "jon": 1}}}]},
                {"id": "undo-recomputes", "why": "Undo is an event naming its target; totals are recomputed from the log",
                 "acceptanceRows": [12], "initial": ledger_initial(), "steps": [
                     sub(p43, "Accepted", rev=43, applied="evt-43"),
                     sub(point("cmd-p44", winner="alex", base=43), "Accepted", rev=44, applied="evt-44"),
                     sub(undo("cmd-u45", "evt-43", 44), "Accepted", rev=45, applied="evt-45"),
                     {"op": "assert", "expect": {"eventRevision": 45, "eventCount": 3, "tally": {"alex": 1}}},
                     sub(undo("cmd-u46", "evt-43", 45), "Rejected", "undoTargetInvalid", rev=45),
                     sub(undo("cmd-u46b", "evt-45", 45), "Rejected", "undoTargetInvalid", rev=45),
                     sub(undo("cmd-u46c", "evt-44", 44), "Conflicted", "baseRevisionStale", rev=45,
                         conflict={"baseEventRevision": 44, "currentEventRevision": 45}),
                     {"op": "assert", "expect": {"eventRevision": 45, "eventCount": 3, "tally": {"alex": 1}}}]},
                {"id": "viewer-denied", "why": "Pairing or claiming does not grant a role", "acceptanceRows": [14], "initial": ledger_initial(),
                 "steps": [
                     sub(capture("cmd-v1", "StopAllRequest", role="viewer", member="m-viewer", dev="p-viewer"), "Rejected", "roleNotPermitted",
                         delivery=BOUNDED),
                     sub(point("cmd-v2", role="viewer", member="m-viewer", dev="p-viewer"), "Rejected", "roleNotPermitted"),
                     sub(capture("cmd-v3", "StopAllRequest", member="m-viewer", dev="w-viewer", surface="watch", bridge="p-viewer"),
                         "Rejected", "roleNotGranted", delivery=BOUNDED),
                     sub(point("cmd-v4", member="m-stranger", dev="p-stranger"), "Rejected", "notMember"),
                     {"op": "assert", "expect": {"eventRevision": 42, "eventCount": 0, "captureStates": recording,
                                                 "securityLog": [{"commandId": "cmd-v3", "code": "roleNotGranted"},
                                                                 {"commandId": "cmd-v4", "code": "notMember"}]}}]},
                {"id": "forged-issuer", "why": "D1: the issuer must be the authenticated channel peer; a body claiming another member, device or watch is refused and logged",
                 "acceptanceRows": [5, 14], "initial": ledger_initial(), "steps": [
                     sub(point("cmd-f1", member="m-scorer", dev="p-viewer"), "Rejected", "issuerNotAuthenticated", peer={"deviceId": "p-viewer"}),
                     sub(capture("cmd-f2", "StopAllRequest"), "Rejected", "issuerNotAuthenticated", delivery=BOUNDED,
                         peer={"deviceId": "p-viewer"}),
                     sub(point("cmd-f3", member="m-scorer", dev="w-unknown", surface="watch", bridge="p-viewer"), "Rejected",
                         "issuerNotAuthenticated"),
                     sub(point("cmd-f4", member="m-scorer", dev="w-unknown", surface="watch", bridge="p-scorer"), "Rejected",
                         "issuerNotAuthenticated"),
                     sub(point("cmd-f5"), "Rejected", "unauthenticatedChannel", peer=NO_PEER),
                     sub(point("cmd-f6", member="m-scorer", dev="w-scorer", surface="watch", bridge="p-scorer"), "Accepted", rev=43,
                         applied="evt-43"),
                     {"op": "assert", "expect": {"eventRevision": 43, "eventCount": 1, "tally": {"jon": 1}, "captureStates": recording,
                                                 "securityLog": [{"commandId": "cmd-f1", "code": "issuerNotAuthenticated"},
                                                                 {"commandId": "cmd-f2", "code": "issuerNotAuthenticated"},
                                                                 {"commandId": "cmd-f3", "code": "issuerNotAuthenticated"},
                                                                 {"commandId": "cmd-f4", "code": "issuerNotAuthenticated"},
                                                                 {"commandId": "cmd-f5", "code": "unauthenticatedChannel"}]}}]},
                {"id": "unauthenticated-not-cached", "why": "D10: a non-member cannot burn a member's commandId; ids are scoped to the authenticated member",
                 "acceptanceRows": [10], "initial": ledger_initial(), "steps": [
                     sub(point("cmd-next", member="m-stranger", dev="p-stranger"), "Rejected", "notMember"),
                     sub(point("cmd-next"), "Accepted", rev=43, applied="evt-43"),
                     sub(point("cmd-next", winner="alex", **s_scorer2), "Conflicted", "baseRevisionStale", rev=43,
                         conflict={"baseEventRevision": 42, "currentEventRevision": 43}),
                     {"op": "assert", "expect": {"eventRevision": 43, "securityLog": [{"commandId": "cmd-next", "code": "notMember"}]}}]},
                {"id": "epoch-rejection-not-cached", "why": "D10: a command for the next epoch is refused but not burned; after host recovery at that epoch the same bytes apply",
                 "acceptanceRows": [5, 17], "initial": ledger_initial(), "steps": [
                     sub(point("cmd-e4", epoch=4), "Rejected", "unknownEpoch"),
                     {"op": "beginEpoch", "newEpoch": 4},
                     sub(point("cmd-e4", epoch=4), "Accepted", rev=43, applied="evt-43"),
                     sub(point("cmd-e3"), "Rejected", "staleEpoch", rev=43),
                     {"op": "assert", "expect": {"hostEpoch": 4, "eventRevision": 43, "securityLog": []}}]},
                {"id": "host-holds-two-roles", "why": "Grants are a set: the host scores and controls capture; a role it does not hold is refused",
                 "acceptanceRows": [14], "initial": ledger_initial(), "steps": [
                     sub(point("cmd-h1", member="m-host", dev="c1"), "Accepted", rev=43, applied="evt-43"),
                     sub(capture("cmd-h2", "StopOne", ["c2"], member="m-host", dev="c1", label="Camera 2 · far baseline"), "Accepted",
                         rev=43, results=pend("c2"), delivery=BOUNDED),
                     sub(mark("cmd-h3", member="m-host", dev="c1", surface="phone", bridge=None), "Rejected", "roleNotGranted", rev=43)]},
                {"id": "watch-cannot-control-capture", "why": "A watch never issues capture requests, even for a capture-controller (ADR-0026 as amended)",
                 "acceptanceRows": [14, 16], "initial": ledger_initial(), "steps": [
                     sub(capture("cmd-w1", "StopAllRequest", dev="w-controller", surface="watch", bridge="p-controller"), "Rejected",
                         "surfaceNotPermitted", delivery=BOUNDED),
                     {"op": "assert", "expect": {"captureStates": recording, "securityLog": []}}]},
                {"id": "marker-and-bounce-marks", "why": "Marks are source-linked notes with receipts; they never move the score revision",
                 "acceptanceRows": [22], "initial": ledger_initial(), "steps": [
                     sub(mark("cmd-m1"), "Accepted", rev=42, applied="mark-1"),
                     sub(mark("cmd-m2", reason="uncertainBounce", point_id=None), "Accepted", rev=42, applied="mark-2"),
                     sub(point("cmd-m3", role="marker", member="m-marker", dev="w-marker", surface="watch", bridge="p-marker"),
                         "Rejected", "roleNotPermitted"),
                     {"op": "assert", "expect": {"eventRevision": 42, "eventCount": 0, "markCount": 2, "tally": {}}}]},
                {"id": "start-denied-or-background", "why": "Start is a request: permission and foreground decide on each phone; no fictitious Recording",
                 "acceptanceRows": [15],
                 "initial": ledger_initial(deviceOverrides={"c2": {"captureState": "Ready", "cameraPermission": "denied"},
                                                             "c3": {"captureState": "Ready", "foreground": False},
                                                             "c4": {"captureState": "Ready"}}),
                 "steps": [
                     sub(capture("cmd-start", "StartRequest", ["c2", "c3", "c4"]), "Accepted", results=pend("c2", "c3", "c4"), delivery=BOUNDED),
                     {"op": "deliver", "commandId": "cmd-start", "expect": {
                         "deviceResults": [{"deviceId": "c2", "status": "Denied", "reason": "cameraPermissionDenied"},
                                           {"deviceId": "c3", "status": "Denied", "reason": "foregroundRequired"},
                                           {"deviceId": "c4", "status": "Accepted", "reason": "startRequested"}],
                         "summary": {"targets": 3, "byStatus": {"Accepted": 1, "Denied": 2}, "banner": "partial"}}},
                     {"op": "assert", "expect": {"captureStates": {"c1": "Recording", "c2": "Ready", "c3": "Ready", "c4": "Starting",
                                                                   "c5": "Recording", "c6": "Recording"}}},
                     {"op": "deviceReport", "deviceId": "c4", "captureState": "Recording"},
                     {"op": "assert", "expect": {"captureStates": {"c1": "Recording", "c2": "Ready", "c3": "Ready", "c4": "Recording",
                                                                   "c5": "Recording", "c6": "Recording"}}}]},
                {"id": "start-while-finalizing", "why": "D13: a device still finalizing its previous take denies a start and never reports Starting",
                 "acceptanceRows": [15], "initial": ledger_initial(deviceOverrides={"c1": {"captureState": "Finalizing"}}), "steps": [
                     sub(capture("cmd-start-c1", "StartRequest", ["c1"]), "Accepted", results=pend("c1"), delivery=BOUNDED),
                     {"op": "deliver", "commandId": "cmd-start-c1", "expect": {
                         "deviceResults": [{"deviceId": "c1", "status": "Denied", "reason": "finalizing"}],
                         "summary": {"targets": 1, "byStatus": {"Denied": 1}, "banner": "partial"}}},
                     {"op": "assert", "expect": {"captureStates": dict(recording, c1="Finalizing")}}]},
                {"id": "stop-all-partial", "why": "A room-wide stop is a fan-out with individual results; no blanket success",
                 "acceptanceRows": [16],
                 "initial": ledger_initial(deviceOverrides={"c2": {"reachable": False}, "c3": {"ackLost": True},
                                                             "c4": {"stopFault": True}, "c6": {"captureState": "Saved"}}),
                 "steps": [
                     sub(stop_all, "Accepted", results=pend("c1", "c2", "c3", "c4", "c5", "c6"), delivery=BOUNDED),
                     {"op": "deliver", "commandId": "cmd-stop-all", "expect": {
                         "deviceResults": [{"deviceId": "c1", "status": "Accepted", "reason": "stopRequested"},
                                           {"deviceId": "c2", "status": "TimedOut", "reason": "unreachable"},
                                           {"deviceId": "c3", "status": "Unknown", "reason": "noAcknowledgement"},
                                           {"deviceId": "c4", "status": "Failed", "reason": "finalizeFailed"},
                                           {"deviceId": "c5", "status": "Accepted", "reason": "stopRequested"},
                                           {"deviceId": "c6", "status": "Accepted", "reason": "notRecording"}],
                         "summary": {"targets": 6, "byStatus": {"Accepted": 3, "Failed": 1, "TimedOut": 1, "Unknown": 1}, "banner": "partial"}}},
                     {"op": "deliver", "commandId": "cmd-stop-all", "expect": {
                         "deviceResults": [{"deviceId": "c1", "status": "Accepted", "reason": "stopRequested"},
                                           {"deviceId": "c2", "status": "TimedOut", "reason": "unreachable"},
                                           {"deviceId": "c3", "status": "Unknown", "reason": "noAcknowledgement"},
                                           {"deviceId": "c4", "status": "Failed", "reason": "finalizeFailed"},
                                           {"deviceId": "c5", "status": "Accepted", "reason": "stopRequested"},
                                           {"deviceId": "c6", "status": "Accepted", "reason": "notRecording"}],
                         "summary": {"targets": 6, "byStatus": {"Accepted": 3, "Failed": 1, "TimedOut": 1, "Unknown": 1}, "banner": "partial"}}},
                     {"op": "assert", "expect": {"captureStates": {"c1": "Finalizing", "c2": "Recording", "c3": "Recording",
                                                                   "c4": "Recording", "c5": "Finalizing", "c6": "Saved"}}}]},
                {"id": "stop-all-no-cameras", "why": "D12: a capture request with nothing to target is refused, never an Accepted receipt with no results",
                 "acceptanceRows": [16], "initial": ledger_initial(devices={}), "steps": [
                     sub(stop_all, "Rejected", "noTargets", delivery=BOUNDED)]},
                {"id": "stop-one", "why": "Stop one names one target and touches only it", "acceptanceRows": [16], "initial": ledger_initial(),
                 "steps": [
                     sub(capture("cmd-stop-c1", "StopOne", ["c1"]), "Accepted", results=pend("c1"), delivery=BOUNDED),
                     {"op": "deliver", "commandId": "cmd-stop-c1", "expect": {
                         "deviceResults": [{"deviceId": "c1", "status": "Accepted", "reason": "stopRequested"}],
                         "summary": {"targets": 1, "byStatus": {"Accepted": 1}, "banner": "allConfirmed"}}},
                     {"op": "assert", "expect": {"captureStates": {"c1": "Finalizing", "c2": "Recording", "c3": "Recording",
                                                                   "c4": "Recording", "c5": "Recording", "c6": "Recording"}}},
                     sub(capture("cmd-stop-c9", "StopOne", ["c9"]), "Rejected", "unknownTarget", delivery=BOUNDED)]},
                {"id": "capture-expiry", "why": "Capture requests expire on unbounded or excessive age; score commands rely on the revision instead",
                 "initial": ledger_initial(), "steps": [
                     sub(stop_all, "Expired", "unboundedTransit", delivery={"transitBounded": False}),
                     sub(capture("cmd-stop-late", "StopAllRequest", age=20000), "Expired", "expired",
                         delivery={"transitBounded": True, "transitMs": 11000, "hostHoldMs": 0}),
                     sub(capture("cmd-stop-long", "StopAllRequest", ttl=60000), "Rejected", "ttlTooLong", delivery=BOUNDED),
                     sub(point("cmd-queued-point"), "Accepted", rev=43, applied="evt-43", delivery={"transitBounded": False}),
                     sub(point("cmd-old-point", base=43, ttl=5000, age=4000), "Expired", "expired", rev=43,
                         delivery={"transitBounded": True, "transitMs": 900, "hostHoldMs": 200}),
                     {"op": "assert", "expect": {"eventRevision": 43, "captureStates": recording}}]},
                {"id": "delivery-fails-closed", "why": "D5: a missing, partial or negative transit observation is unbounded transit; it can never extend a TTL",
                 "acceptanceRows": [8], "initial": ledger_initial(deviceOverrides={"c4": {"captureState": "Ready"}}), "steps": [
                     sub(capture("cmd-d1", "StartRequest", ["c4"]), "Expired", "unboundedTransit"),
                     sub(capture("cmd-d2", "StartRequest", ["c4"]), "Expired", "unboundedTransit", delivery={"transitBounded": True}),
                     sub(capture("cmd-d3", "StartRequest", ["c4"], age=20000), "Expired", "unboundedTransit",
                         delivery={"transitBounded": True, "transitMs": -10000, "hostHoldMs": 0}),
                     sub(capture("cmd-d4", "StartRequest", ["c4"]), "Expired", "unboundedTransit", delivery={"transitMs": 100, "hostHoldMs": 0}),
                     sub(capture("cmd-d5", "StartRequest", ["c4"]), "Accepted", results=pend("c4"), delivery=BOUNDED),
                     {"op": "assert", "expect": {"captureStates": dict(recording, c4="Ready")}}]},
                {"id": "session-and-epoch", "why": "Commands bound to another session or epoch are refused", "acceptanceRows": [5],
                 "initial": ledger_initial(), "steps": [
                     sub(point("cmd-e1", session="other-room"), "Rejected", "wrongSession"),
                     sub(point("cmd-e2", epoch=2), "Rejected", "staleEpoch"),
                     sub(point("cmd-e3", epoch=4), "Rejected", "unknownEpoch")]},
                {"id": "restart-no-duplicate", "why": "After process death (or a fold/rotation recreation) an identical retry still applies once",
                 "acceptanceRows": [1, 3], "initial": ledger_initial(), "steps": [
                     sub(p43, "Accepted", rev=43, applied="evt-43"), {"op": "restart"},
                     sub(p43, "Accepted", rev=43, applied="evt-43"),
                     {"op": "assert", "expect": {"eventRevision": 43, "eventCount": 1, "tally": {"jon": 1}}}]},
                {"id": "link-lost-no-stop", "why": "Disconnect never stops cameras", "acceptanceRows": [17], "initial": ledger_initial(),
                 "steps": [{"op": "linkLost", "expect": {"commandsIssued": []}},
                           {"op": "assert", "expect": {"eventCount": 0, "captureStates": recording}}]},
            ]}


def v_outbox():
    scorer = {"deviceId": "p-scorer"}

    def offline(cmd, now=0):
        return {"op": "offline", "command": cmd, "nowMonoMs": now,
                "expect": {"status": "Pending", "reason": "offlineDraft", "canonicalEventRevision": None}}

    def flush(expect, now=0, delivery=None, peer=None):
        step = {"op": "flush", "nowMonoMs": now, "peer": peer or scorer, "expect": expect}
        if delivery is not None:
            step["delivery"] = delivery
        return step

    def r(cid, status, reason=None, rev=None):
        return {"commandId": cid, "status": status, "reason": reason, "canonicalEventRevision": rev}
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "outbox",
            "status": "Issuer outbox (phone or watch) against the sample host ledger; the issuer recomputes ageAtSendMs on every send",
            "cases": [
                {"id": "offline-point", "why": "An offline point is a visible pending draft; the canonical revision does not move until a receipt",
                 "acceptanceRows": [13], "initial": ledger_initial(), "steps": [
                     offline(point("cmd-off-43")),
                     {"op": "assertLedger", "expect": {"eventRevision": 42, "eventCount": 0}},
                     flush([r("cmd-off-43", "Accepted", rev=43)]),
                     {"op": "assertLedger", "expect": {"eventRevision": 43, "eventCount": 1}}]},
                {"id": "offline-conflict", "why": "Another scorer moved the revision while this one was offline", "acceptanceRows": [11, 13],
                 "initial": ledger_initial(), "steps": [
                     offline(point("cmd-off-a", winner="alex")),
                     {"op": "hostSubmit", "command": point("cmd-live-jon", member="m-scorer2", dev="p-scorer2"), "peer": {"deviceId": "p-scorer2"},
                      "expect": {"status": "Accepted", "canonicalEventRevision": 43}},
                     flush([r("cmd-off-a", "Conflicted", "baseRevisionStale", 43)]),
                     {"op": "assertLedger", "expect": {"eventRevision": 43, "eventCount": 1, "tally": {"jon": 1}}}]},
                {"id": "chained-drafts", "why": "Consecutive offline points are a chain: each is based on the previous draft's revision and both apply",
                 "acceptanceRows": [13], "initial": ledger_initial(), "steps": [
                     offline(point("cmd-c1")), offline(point("cmd-c2", winner="alex", base=43)),
                     flush([r("cmd-c1", "Accepted", rev=43), r("cmd-c2", "Accepted", rev=44)]),
                     {"op": "assertQueue", "expect": []},
                     {"op": "assertLedger", "expect": {"eventRevision": 44, "tally": {"alex": 1, "jon": 1}}}]},
                {"id": "chain-broken-held", "why": "D9: once a draft in the chain conflicts, the later draft is held for resubmission, never sent against a revision its author did not see",
                 "acceptanceRows": [11, 13], "initial": ledger_initial(), "steps": [
                     offline(point("cmd-d1", winner="alex")), offline(point("cmd-d2", base=43)),
                     {"op": "hostSubmit", "command": point("cmd-live", member="m-scorer2", dev="p-scorer2"), "peer": {"deviceId": "p-scorer2"},
                      "expect": {"status": "Accepted", "canonicalEventRevision": 43}},
                     flush([r("cmd-d1", "Conflicted", "baseRevisionStale", 43), r("cmd-d2", "Pending", "requiresResubmit")]),
                     {"op": "assertQueue", "expect": ["cmd-d2"]},
                     {"op": "assertLedger", "expect": {"eventRevision": 43, "eventCount": 1, "tally": {"jon": 1}}}]},
                {"id": "offline-marker", "why": "A watch mark made offline is pending, then acknowledged", "acceptanceRows": [13],
                 "initial": ledger_initial(), "steps": [
                     offline(mark("cmd-off-mark")),
                     flush([r("cmd-off-mark", "Accepted", rev=42)], peer={"deviceId": "p-marker"}),
                     {"op": "assertLedger", "expect": {"eventRevision": 42, "markCount": 1}}]},
                {"id": "queued-capture-expires", "why": "D4: time spent in the outbox counts; a start request flushed 10 minutes later expires, one flushed at once applies",
                 "acceptanceRows": [8, 15], "initial": ledger_initial(deviceOverrides={"c4": {"captureState": "Ready"}}), "steps": [
                     offline(capture("cmd-late-start", "StartRequest", ["c4"])),
                     flush([r("cmd-late-start", "Expired", "expired", 42)], now=600000, delivery=BOUNDED,
                           peer={"deviceId": "p-controller"}),
                     offline(capture("cmd-quick-start", "StartRequest", ["c4"]), now=600000),
                     flush([r("cmd-quick-start", "Accepted", rev=42)], now=601000, delivery=BOUNDED, peer={"deviceId": "p-controller"}),
                     {"op": "assertQueue", "expect": []}]},
                {"id": "epoch-mismatch-keeps-drafts", "why": "D9: a flush to a host at another epoch sends nothing and drops nothing; reconcile decides",
                 "acceptanceRows": [3, 13, 17], "initial": ledger_initial(hostEpoch=4, outboxEpoch=3), "steps": [
                     offline(point("cmd-keep")),
                     flush([]),
                     {"op": "assertQueue", "expect": ["cmd-keep"]},
                     {"op": "reconcile", "newEpoch": 4, "hostReceipts": {}, "expect": {"cmd-keep": {"status": "Pending", "reason": "requiresResubmit"}}},
                     {"op": "assertQueue", "expect": ["cmd-keep"]},
                     {"op": "assertLedger", "expect": {"eventRevision": 42, "eventCount": 0}}]},
                {"id": "epoch-change-reconcile", "why": "After a host change: adopt known receipts, expire unknown capture requests, keep other drafts pending for resubmission",
                 "acceptanceRows": [3, 17], "initial": ledger_initial(), "steps": [
                     offline(point("cmd-q1")), offline(point("cmd-q2", winner="alex")), offline(capture("cmd-q3", "StopAllRequest")),
                     {"op": "reconcile", "newEpoch": 4,
                      "hostReceipts": {"cmd-q1": receipt("cmd-q1", "PointWon", "Accepted", rev=43, applied="evt-43")},
                      "expect": {"cmd-q1": {"status": "Accepted", "reason": None},
                                 "cmd-q2": {"status": "Pending", "reason": "requiresResubmit"},
                                 "cmd-q3": {"status": "Expired", "reason": "hostEpochChanged"}}},
                     {"op": "assertQueue", "expect": ["cmd-q2"]}]},
            ]}


def v_alerts():
    def st(t, dev, fresh, state="Recording"):
        return {"t": t, "op": "status", "deviceId": dev, "freshness": fresh, "captureState": state}

    def tick(t):
        return {"t": t, "op": "tick"}

    def pt(t):
        return {"t": t, "op": "point"}

    def ev(t, event, alert_id, dev, kind="cameraUnknown", severity="deferred"):
        return {"t": t, "event": event, "alertId": alert_id, "kind": kind, "deviceId": dev, "severity": severity}

    def hap(t, ids, pattern="deferred"):
        return {"t": t, "event": "haptic", "alertIds": ids, "pattern": pattern}

    def case(case_id, why, steps, events, rows=(19,)):
        return {"id": case_id, "why": why, "acceptanceRows": list(rows), "steps": steps,
                "expect": {"events": events, "commandsIssued": []}}
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "alerts",
            "status": "AlertPolicy on the phone (watch spec 'Haptics and alerts'; ADR-0026 §8 as amended); times are phone monotonic ms",
            "cases": [
                case("raise-after-3s", "A recording camera Unknown for 3 s raises one deferred alert; the next point delivers its haptic",
                     [st(0, "c3", "Fresh"), st(1000, "c3", "Unknown"), tick(3999), tick(4000), pt(10000)],
                     [ev(4000, "raise", "alert-1", "c3"), hap(10000, ["alert-1"])], rows=(6, 19)),
                case("blip-under-3s", "A shorter silence raises nothing",
                     [st(0, "c3", "Fresh"), st(1000, "c3", "Unknown"), st(3500, "c3", "Fresh"), tick(9000)], []),
                case("never-recording", "A camera that was never freshly Recording raises nothing when it goes quiet",
                     [st(0, "c6", "Fresh", "Saved"), st(1000, "c6", "Unknown", "Saved"), tick(20000)], []),
                case("deferral-45s", "With no point, the deferred haptic fires 45 s after the alert",
                     [st(0, "c3", "Fresh"), st(1000, "c3", "Unknown"), tick(4000), tick(48999), tick(49000)],
                     [ev(4000, "raise", "alert-1", "c3"), hap(49000, ["alert-1"])]),
                case("collapse", "Two pending alerts collapse into one haptic",
                     [st(0, "c2", "Fresh"), st(0, "c3", "Fresh"), st(1000, "c2", "Unknown"), st(2000, "c3", "Unknown"),
                      tick(4000), tick(5000), pt(8000)],
                     [ev(4000, "raise", "alert-1", "c2"), ev(5000, "raise", "alert-2", "c3"), hap(8000, ["alert-1", "alert-2"])]),
                case("clear-after-4s", "Fresh again for 4 s clears the alert; a cleared alert drops out of the pending haptic",
                     [st(0, "c3", "Fresh"), st(1000, "c3", "Unknown"), tick(4000), st(20000, "c3", "Fresh"), tick(23999),
                      tick(24000), pt(30000)],
                     [ev(4000, "raise", "alert-1", "c3"), ev(24000, "clear", "alert-1", "c3")]),
                case("one-per-outage-and-5-min-cap", "One alert per outage; the same camera re-alerts at most once per 5 min",
                     [st(0, "c3", "Fresh"), st(1000, "c3", "Unknown"), tick(4000), pt(5000), st(20000, "c3", "Fresh"),
                      tick(24000), st(30000, "c3", "Unknown"), tick(33000), tick(303999), tick(304000), pt(305000)],
                     [ev(4000, "raise", "alert-1", "c3"), hap(5000, ["alert-1"]), ev(24000, "clear", "alert-1", "c3"),
                      ev(304000, "raise", "alert-2", "c3"), hap(305000, ["alert-2"])]),
                case("ack-closes-outage", "Acknowledging clears it on watch and phone, drops its haptic, and the same outage never re-raises",
                     [st(0, "c3", "Fresh"), st(1000, "c3", "Unknown"), tick(4000),
                      {"t": 6000, "op": "ack", "alertId": "alert-1"}, pt(8000), tick(60000), tick(305000)],
                     [ev(4000, "raise", "alert-1", "c3"), ev(6000, "ack", "alert-1", "c3")]),
                case("own-recording-failed-critical", "The wearer's own phone failing to record is critical: raised and vibrated at once",
                     [{"t": 5000, "op": "own", "kind": "ownRecordingFailed", "deviceId": "c1"}],
                     [ev(5000, "raise", "alert-1", "c1", "ownRecordingFailed", "critical"), hap(5000, ["alert-1"], "critical")]),
            ]}


def v_analysis():
    caps_on = dict(CAPS_V1, serveSpeedResults=True)
    return {"schemaVersion": "jovra.room-fixture.vectors/1", "kind": "analysis",
            "status": "Presentation of records/analysis-result.*.json; the registry is spec/contracts/capability-registry.v1.json (read-only)",
            "cases": [
                {"id": "serve-capability-absent", "why": "No active capability, no value", "acceptanceRows": [20],
                 "record": "records/analysis-result.serve-previous.json", "resultPatch": [], "capabilities": dict(CAPS_V1),
                 "currentPointEventId": "sample-point-42",
                 "expect": {"show": "unavailable", "reason": "capabilityAbsent", "value": None, "scoreEffect": "none"}},
                {"id": "serve-calibration-missing", "why": "The result explains that calibration is missing", "acceptanceRows": [20],
                 "record": "records/analysis-result.serve-unavailable.json", "resultPatch": [], "capabilities": caps_on,
                 "currentPointEventId": "sample-point-43",
                 "expect": {"show": "unavailable", "reason": "calibrationMissing", "value": None, "scoreEffect": "none"}},
                {"id": "serve-uncalibrated-value", "why": "A value without its calibration is not shown", "acceptanceRows": [20],
                 "record": "records/analysis-result.serve-previous.json", "resultPatch": [rep("/calibrationId", None)],
                 "capabilities": caps_on, "currentPointEventId": "sample-point-42",
                 "expect": {"show": "unavailable", "reason": "calibrationMissing", "value": None, "scoreEffect": "none"}},
                {"id": "serve-previous-point", "why": "A result from point 42 shown while point 43 is current stays labelled previous",
                 "acceptanceRows": [21], "record": "records/analysis-result.serve-previous.json", "resultPatch": [],
                 "capabilities": caps_on, "currentPointEventId": "sample-point-43",
                 "expect": {"show": "previous", "reason": None, "value": "74", "units": "mph", "label": "estimated",
                            "pointEventId": "sample-point-42", "producedAt": "2026-10-07T21:28:40Z", "scoreEffect": "none"}},
                {"id": "serve-current-point", "why": "Same result while its own point is current", "acceptanceRows": [21],
                 "record": "records/analysis-result.serve-previous.json", "resultPatch": [], "capabilities": caps_on,
                 "currentPointEventId": "sample-point-42",
                 "expect": {"show": "current", "value": "74", "units": "mph", "scoreEffect": "none"}},
                {"id": "bounce-review-only", "why": "An ambiguous bounce is a review bookmark; no line call and no score change",
                 "acceptanceRows": [22], "record": "records/analysis-result.bounce-review.json", "resultPatch": [],
                 "capabilities": caps_on, "currentPointEventId": "sample-point-43",
                 "expect": {"show": "unavailable", "reason": "capabilityAbsent", "value": None, "scoreEffect": "none"}},
                {"id": "reviewed-serve-needs-review", "why": "A result flagged for review is not shown as a number",
                 "record": "records/analysis-result.serve-previous.json", "resultPatch": [rep("/reviewState", "reviewNeeded")],
                 "capabilities": caps_on, "currentPointEventId": "sample-point-42",
                 "expect": {"show": "reviewNeeded", "value": None, "scoreEffect": "none"}},
            ]}


ACCEPTANCE = [  # (row, protocolTestable, note)
    (1, "partial", "Protocol part only: an identical command retried after recreation applies once. Pane layout, playhead and render/charge continuity are native UI gates."),
    (2, "no", "Layout and window-size behaviour: native UI, emulator and device gates."),
    (3, "partial", "Protocol part: monotonic baseline loss makes cached status Unknown; replay marks persist on phone and watch; outbox drafts reconcile after an epoch change. Restoring the draft and the screen after real process death is a native gate."),
    (4, "yes", "Host-side expiry, single use, proof, commit-then-reveal verification code, attempt limit, per-source display-code throttling; rejected joins grant nothing."),
    (5, "yes", "Session, epoch, host key, host device, roster, issuer-to-channel binding and endpoint rules for snapshots, bridge payloads, invitations and commands; strict QR decoding. The real TLS pin and peer binding are native transport gates."),
    (6, "yes", "Freshness thresholds, frozen last-reported elapsed time and 'may still be recording' row semantics."),
    (7, "yes", "Chained ages: a stale bridge makes every camera Unknown on the watch and blocks the aggregate claim."),
    (8, "yes", "Unbounded (queued) transit is Unknown until an interactive bounded exchange."),
    (9, "yes", "Idempotent identical retry returns the original receipt; one event."),
    (10, "yes", "Same id, different payload: rejected and security-logged; the stored receipt stands."),
    (11, "yes", "Base-revision conflict, including an offline scorer's late flush."),
    (12, "partial", "The ledger records undo as an event and recomputes the tally from the log; full score/stat/export recomputation is pinned by the core spec/fixtures scoring cases."),
    (13, "yes", "Offline drafts stay Pending with no canonical revision until a receipt."),
    (14, "yes", "Role grants come from membership; viewers and claimed roles are refused; invitations cannot escalate."),
    (15, "partial", "Protocol part: start is a request; permission, background or a still-finalizing take yields Denied per device; no fictitious Recording. Real OS camera, permission and background behaviour is a device gate."),
    (16, "yes", "Per-device Accepted/Denied/Failed/TimedOut/Unknown results; no blanket success banner; confirmed, labelled stop-all."),
    (17, "partial", "Protocol part: disconnect issues no commands; a new host epoch needs an authenticated reconciliation and revokes invitations. That local originals survive and capture keeps running is a native/physical gate."),
    (18, "no", "Watch shapes, fonts and accessibility labels: native UI gates."),
    (19, "partial", "Protocol part: the AlertPolicy (3 s raise, 4 s clear, one alert per outage, 5 min re-alert cap, deferral to the next point or 45 s, collapse, critical own-phone alerts, acknowledgement) and alert severity. Real haptics, always-on and low-power behaviour are watchOS/Wear OS runtime gates."),
    (20, "yes", "Absent capability or missing calibration is an explicit unavailable reason; v1 schema forbids live serve speed."),
    (21, "yes", "A result keeps its own point and timestamp and is labelled previous."),
    (22, "yes", "Bounce hints are review marks or unavailable; results have scoreEffect none; v1 forbids automated line calls."),
    (23, "no", "Six-device endurance needs physical devices."),
]


def acceptance_map(scenarios, vector_files, invalid_files):
    covers = {row: [] for row, _, _ in ACCEPTANCE}
    for name, doc in sorted(vector_files.items()):
        for case in doc["cases"]:
            for row in case.get("acceptanceRows", []):
                covers[row].append(f"vectors/{name}.json#{case['id']}")
    for name, doc in sorted(invalid_files.items()):
        for case in doc["cases"]:
            for row in case.get("acceptanceRows", []):
                covers[row].append(f"invalid/{name}.invalid.json#{case['id']}")
    return {"schemaVersion": "jovra.room-fixture.acceptance-map/1",
            "source": "design-reference/adaptive/brief/acceptance-matrix.md",
            "rows": [{"row": row, "scenario": scenarios[row - 1], "protocolTestable": testable,
                      "covers": covers[row] if testable != "no" else [], "note": note} for row, testable, note in ACCEPTANCE]}


def matrix_scenarios() -> list:
    lines = (ROOT / "design-reference/adaptive/brief/acceptance-matrix.md").read_text(encoding="utf-8").splitlines()
    rows = [ln for ln in lines if ln.startswith("|") and not ln.startswith("|---")][1:]
    return [ln.split("|")[1].strip() for ln in rows]


def build() -> dict:
    """Map of relative path -> JSON document."""
    out = {}
    recs = records()
    for name, doc in recs.items():
        out[f"records/{name}.json"] = doc
    invalid = {}
    for base, cases in invalid_sets().items():
        invalid[base] = {"schemaVersion": "jovra.room-fixture.invalid-cases/1", "base": f"records/{base}.json", "cases": cases}
        out[f"invalid/{base}.invalid.json"] = invalid[base]
    vectors = {"freshness": v_freshness(), "watch-sample": v_watch_sample(), "phone-status": v_phone_status(),
               "display": v_display(), "disconnect": v_disconnect(), "snapshot": v_snapshot(), "bridge": v_bridge(),
               "invitation": v_invitation(), "alerts": v_alerts(),
               "ledger": v_ledger(), "outbox": v_outbox(), "analysis": v_analysis()}
    for name, doc in vectors.items():
        out[f"vectors/{name}.json"] = doc
    out["acceptance-map.json"] = acceptance_map(matrix_scenarios(), vectors, invalid)
    return out


def dump(doc) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def main(argv) -> int:
    out_dir = Path(argv[argv.index("--out") + 1]) if "--out" in argv else ROOT / "spec/room/fixtures"
    for rel, doc in sorted(build().items()):
        path = out_dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(dump(doc), encoding="utf-8")
    print(f"wrote {len(build())} fixture files to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
