"""JOVRA Room v1 (jovra.room/1): the ST23/ST24 transcripts, invalid transcript cases, room vectors and drift
self-tests. Module page: spec/studio/modules/room.md.

Expectations here are written by hand, never computed by spec/reference/studio/room.py: receipts, screen states,
verdicts and codes are literals; the six-digit comparison codes in the transcripts come from spec/room's own
reference (an independent implementation, read only) and the vector codes were computed with shasum and bc
(the derivation is stored beside each vector). Frame lengths are the canonical byte counts of the messages.
"""

from __future__ import annotations

import base64
import copy
import hashlib
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from studio import room
from studio.core import Reject, apply_patch, canonical_bytes
from studio.cases.patches import bad, rep

ROOT = Path(__file__).resolve().parents[4]
SPEC_ROOM_REFERENCE = ROOT / "spec" / "room" / "reference"
SPEC_ROOM_SCHEMAS = ROOT / "spec" / "room" / "schemas"

ROOM_ID = "room-court-day"
PROJECT = "sample-court-day"
HINT = "jovra-k7m2q9x4d1"
# Fixed public keys: SPKI DER of two P-256 points, both checked on-curve with `openssl pkey -pubcheck` (2026-10-08).
# Host: the curve's generator G (the public key of private key 1). Alex: RFC 6979 appendix A.2.5's public key.
SPKI_PREFIX = "3059301306072a8648ce3d020106082a8648ce3d030107034200"
HOST_SPKI = (SPKI_PREFIX + "04" "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
             "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
ALEX_SPKI = (SPKI_PREFIX + "04" "60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6"
             "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299")
HOST_KEY = "5cd252fb0ce8932436faf8ccd1040981b89ee4ad6b9fe9e2a2b7e71aacb27cd3"   # shasum -a 256 of HOST_SPKI bytes
ALEX_KEY = "5a7a78cca4a0f420d9bc62bb669c3c2759e39f723d3ae10dcbe0f0815a07ecd4"   # shasum -a 256 of ALEX_SPKI bytes
# Sample stand-ins: sha256("jovra-sample-key:<name>")
SAM_KEY = "bce1f60efddb88a865d063a609df2ef580196cc05a92c541afcb2bf9e0804942"
KAI_KEY = "d230269de07abf4dc72d2a5581eeab3cd44f2fb5e40368db7d449ddd5a3dd5e2"
STRANGER_KEY = "bbc29565cd64a9627f2992ebf7ed4941a8be5aa7b11abde7e2150b12b65b0a50"
MALLORY_KEY = "b6457b21efacef1eaa0d1adb4bca3cc185ef757aa1e865ae324721b99b96f791"
MALLORY_HOST_KEY = "99249c4e7115b5402c60286a0cc21f9b8fb8c4bdbc04fff2cd9500420f37d5a2"
EXPORTER_X = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
EXPORTER_Y = "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
EXPORTER_SAM = hashlib.sha256(b"jovra-sample-exporter:sam").hexdigest()

JON = "device-jon"
ALEX = "device-alex"
SAM = "device-sam"
KAI = "device-kai"
STRANGER = "device-stranger"
MALLORY = "device-mallory"
CLOCK_OFFSET_MS = {JON: 0, ALEX: 7_331_000, SAM: 52_004_000, KAI: 918_000, STRANGER: 33_000, MALLORY: 4_000}
WALL_BASE = datetime(2026, 10, 7, 20, 0, 0, tzinfo=timezone.utc)

HOST_MEMBER = {"deviceId": JON, "keySha256": HOST_KEY, "label": "Jon's iPhone", "slot": "near-baseline",
               "slotRole": "primary", "commandGrants": ["capture-controller", "scorer", "viewer"],
               "capabilities": ["record-local", "upload-own-source", "view-own-preview"]}
CAMERA_GRANTS = ["viewer"]
CAMERA_CAPS = ["record-local", "view-own-preview"]


def member(device, key, label, slot):
    return {"deviceId": device, "keySha256": key, "label": label, "slot": slot, "slotRole": "camera",
            "commandGrants": list(CAMERA_GRANTS), "capabilities": list(CAMERA_CAPS)}


def spec_room_invitation():
    """spec/room's reference (read only): an independent implementation of the shared formulas."""
    if str(SPEC_ROOM_REFERENCE) not in sys.path:
        sys.path.insert(0, str(SPEC_ROOM_REFERENCE))
    import jovra_room.invitation as invitation
    return invitation


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def sample_token(label: str) -> str:
    return b64url(hashlib.sha256(f"jovra-sample-token:{label}".encode()).digest())


def sample_nonce(label: str) -> str:
    return b64url(hashlib.sha256(f"jovra-sample-nonce:{label}".encode()).digest()[:16])


def wall(at_ms: int) -> str:
    return (WALL_BASE + timedelta(milliseconds=at_ms)).strftime("%Y-%m-%dT%H:%M:%SZ")


def tls_code(exporter: str, host_key: str, guest_key: str) -> str:
    """The typed-code formula, written out independently of the reference (pinned by the hand vector)."""
    digest = hashlib.sha256(f"jovra-room-sas-tls|{exporter}|{host_key}|{guest_key}".encode()).hexdigest()
    return f"{int(digest[:8], 16) % 1_000_000:06d}"


def endpoints(address="192.168.1.20", port=47100, hint=HINT):
    return [{"kind": "dnssd", "serviceType": "_jovra-room._tcp", "instanceName": hint},
            {"kind": "lan", "address": address, "port": port}]


def payload(invite_id, display, at_ms, lifetime_s=600, epoch=1, host_key=HOST_KEY, eps=None, token=None,
            command_role="viewer"):
    return {"schemaVersion": "jovra.room.invitation-payload/1", "sample": True, "inviteId": invite_id,
            "sessionId": ROOM_ID, "hostEpoch": epoch, "hostKeySha256": host_key,
            "joinToken": token or sample_token(invite_id), "nonce": sample_nonce(invite_id),
            "issuedAt": wall(at_ms), "expiresAt": wall(at_ms + 1000 * lifetime_s), "captureRole": "camera",
            "commandRole": command_role, "displayCode": display, "endpoints": eps or endpoints()}


def qr_text(p: dict) -> str:
    return "jovra-room:1:" + b64url(canonical_bytes(p))


# ----- transcript builder -------------------------------------------------------------------------

class Script:
    def __init__(self, room_doc: dict):
        self.room = room_doc
        self.epoch = room_doc["hostEpoch"]
        self.steps: list = []
        self.seq: dict = {}
        self.qr: dict = {}

    def msg(self, device, typ, body, at, epoch=None, seq=None, room_id=ROOM_ID):
        epoch = epoch or self.epoch
        key = (epoch, device)
        seq = seq if seq is not None else self.seq.get(key, 0) + 1
        self.seq[key] = max(self.seq.get(key, 0), seq)
        return {"schemaVersion": "jovra.room/1", "roomId": room_id, "hostEpoch": epoch, "deviceId": device, "seq": seq,
                "sentMonoNs": (at + CLOCK_OFFSET_MS[device]) * 1_000_000, "type": typ, "body": body}

    def add(self, step, note):
        if note:
            step = dict({"note": note}, **step)
        self.steps.append(step)
        return step

    def invite(self, at, invite_id, slot, display, lifetime_s=600, note=None, **kw):
        p = payload(invite_id, display, at, lifetime_s, epoch=self.epoch, **kw)
        self.qr[invite_id] = p
        return self.add({"step": "invite", "atMs": at, "inviteId": invite_id, "slot": slot, "displayCode": display,
                         "lifetimeS": lifetime_s, "qr": qr_text(p)}, note)

    def inn(self, at, peer, device, typ, body, code=None, transit=40, exporter=None, note=None, **kw):
        m = self.msg(device, typ, body, at, **kw)
        verdict = {"accepted": True} if code is None else {"accepted": False, "code": code}
        return self.add({"step": "in", "atMs": at, "peerKeySha256": peer, "length": len(canonical_bytes(m)),
                         "transitMs": transit, "exporter": exporter, "verdict": verdict, "message": m}, note)

    def out(self, at, to, typ, body, note=None):
        m = self.msg(self.room["hostDeviceId"], typ, body, at)
        return self.add({"step": "out", "atMs": at, "toPeerKeys": to, "length": len(canonical_bytes(m)), "message": m},
                        note)

    def local(self, at, typ, body, note=None, device=JON):
        return self.add({"step": "local", "atMs": at, "message": self.msg(device, typ, body, at)}, note)

    def comparison(self, at, invite_id, host_code, guest_code, decision="allow", guest_view=None, note=None):
        return self.add({"step": "comparison", "atMs": at, "inviteId": invite_id, "hostScreenCode": host_code,
                         "guestScreenCode": guest_code, "decision": decision, "guestView": guest_view}, note)

    def restart(self, at, kind, epoch, device=JON, key=HOST_KEY, note=None):
        self.epoch = epoch
        return self.add({"step": "restart", "atMs": at, "kind": kind, "newHostEpoch": epoch, "newHostDeviceId": device,
                         "newHostKeySha256": key}, note)

    def observe(self, at, recording_on, devices, note=None):
        return self.add({"step": "observe", "atMs": at, "display": {"recordingOn": recording_on, "devices": devices}},
                        note)

    def doc(self, transcript_id, screen, title):
        return {"schemaVersion": "jovra.room-transcript/1", "transcriptId": transcript_id, "sample": True,
                "screen": screen, "title": title, "room": self.room, "steps": self.steps}


def room_header(members, epoch=1, revision=0):
    return {"roomId": ROOM_ID, "projectId": PROJECT, "hostDeviceId": JON, "hostKeySha256": HOST_KEY,
            "hostEpoch": epoch, "roomHint": HINT, "maxCameras": 6, "plannedMinutes": 90, "eventRevision": revision,
            "members": members}


# message bodies

def hello_guest(platform="android"):
    return {"role": "guest", "appVersion": "1.0.0", "platform": platform, "protocols": [1], "roomHint": None}


def hello_host():
    return {"role": "host", "appVersion": "1.0.0", "platform": "ios", "protocols": [1], "roomHint": HINT}


def guest_nonce(label):
    return sample_nonce("guest-" + label)


def host_nonce(label):
    return sample_nonce("host-" + label)


def join_qr(s: Script, invite_id, guest_key, name, model, nonce_label, observed=HOST_KEY):
    inv = spec_room_invitation()
    p = s.qr[invite_id]
    commitment = inv.guest_commitment(guest_key, guest_nonce(nonce_label))
    proof = inv.join_proof(p["joinToken"], ROOM_ID, invite_id, p["nonce"], guest_key, commitment)
    return {"path": "qr", "inviteId": invite_id, "displayCode": None, "guestKeySha256": guest_key,
            "guestCommitment": commitment, "observedHostKeySha256": observed, "proof": proof, "channelBinding": None,
            "displayName": name, "deviceModel": model, "consent": {"shareCaptureMetadata": True}}


def join_typed(display, guest_key, name, model, binding="tls-exporter"):
    return {"path": "typedCode", "inviteId": None, "displayCode": display, "guestKeySha256": guest_key,
            "guestCommitment": None, "observedHostKeySha256": None, "proof": None, "channelBinding": binding,
            "displayName": name, "deviceModel": model, "consent": {"shareCaptureMetadata": True}}


def sas(s: Script, invite_id, guest_key, nonce_label, host_key=HOST_KEY):
    inv = spec_room_invitation()
    return inv.verification_code(host_key, guest_key, s.qr[invite_id]["nonce"], host_nonce(nonce_label),
                                 guest_nonce(nonce_label))


def readiness(battery, minutes, thermal="nominal", camera="granted", mic="granted", charging=False):
    return {"cameraPermission": camera, "microphonePermission": mic, "presetSupported": True, "batteryPct": battery,
            "charging": charging, "lowPowerMode": False, "freeBytes": minutes * 1_150_000_000, "minutesLeft": minutes,
            "thermal": thermal}


def heartbeat(state, segment=None, saved_ms=0, battery=80, thermal="nominal", free=150_000_000_000):
    return {"captureState": state, "segmentId": segment, "savedThroughMs": saved_ms, "segmentIndex": 0,
            "freeBytes": free, "batteryPct": battery, "thermal": thermal, "droppedFrames": 0}


def still(s: Script, device, still_id, at, framing, lag_ms=100):
    return {"stillId": still_id, "captureMonoNs": (at + CLOCK_OFFSET_MS[device] - lag_ms) * 1_000_000,
            "framing": framing, "format": "jpeg", "width": 640, "height": 360, "bytes": 41_000,
            "sha256": hashlib.sha256(f"jovra-sample-still:{still_id}".encode()).hexdigest()}


def started(device, intent, segment, at):
    return {"intentId": intent, "segmentId": segment, "fileZeroHostNs": (at + CLOCK_OFFSET_MS[device] + 35) * 1_000_000,
            "wallClockAtStart": wall(at), "preset": {"width": 1920, "height": 1080}, "fps": {"num": 60, "den": 1},
            "timescale": 600, "orientationLock": "landscapeLeft"}


def command(command_id, issuer, grant, scope, targets, base, ttl=10_000, age=0, **extra):
    body = {"commandId": command_id, "issuer": {"deviceId": issuer}, "claimedGrant": grant,
            "expiry": {"ttlMs": ttl, "ageAtSendMs": age}, "target": {"scope": scope, "deviceIds": targets},
            "baseEventRevision": base}
    body.update(extra)
    return body


def receipt(command_id, issuer, status, reason, security, revision, per_device):
    return {"commandId": command_id, "issuerDeviceId": issuer, "status": status, "reason": reason,
            "securityEvent": security, "eventRevision": revision,
            "perDevice": [{"deviceId": d, "result": r, "reason": why} for d, r, why in per_device]}


def row(device, slot, band, age, state, label, ready, still_age):
    return {"deviceId": device, "slot": slot, "freshness": band, "contactAgeMs": age, "state": state, "label": label,
            "ready": ready, "stillAgeMs": still_age}


# ----- ST23: the lobby (screen 23 demo state) -----------------------------------------------------------------

T23 = 1_000_000


def st23_lobby() -> dict:
    s = Script(room_header([dict(HOST_MEMBER)]))
    t = T23
    s.invite(t, "inv-2", "far-baseline", "JVR-417", note="invite-camera-2")
    s.local(t, "readiness", readiness(78, 130))
    s.local(t, "heartbeat", heartbeat("Ready", battery=78))
    s.inn(t + 40_000, ALEX_KEY, ALEX, "hello", hello_guest())
    s.out(t + 40_010, [ALEX_KEY], "hello", hello_host())
    s.inn(t + 41_000, ALEX_KEY, ALEX, "join", join_qr(s, "inv-2", ALEX_KEY, "Alex's phone", "Pixel 9", "alex"),
          note="alex-join")
    s.out(t + 41_010, [ALEX_KEY], "approvalRequest", {"inviteId": "inv-2", "hostNonce": host_nonce("alex")})
    s.inn(t + 41_200, ALEX_KEY, ALEX, "joinReveal", {"inviteId": "inv-2", "guestNonce": guest_nonce("alex")},
          note="alex-reveal")
    code = sas(s, "inv-2", ALEX_KEY, "alex")
    s.comparison(t + 52_000, "inv-2", code, code, note="alex-codes-match")
    s.out(t + 52_010, [ALEX_KEY], "approve", {"inviteId": "inv-2", "deviceId": ALEX, "guestKeySha256": ALEX_KEY,
                                              "basis": "comparisonCode"}, note="alex-approved")
    s.out(t + 52_020, [ALEX_KEY], "roleAssigned", {"deviceId": ALEX, "slot": "far-baseline", "slotRole": "camera",
                                                   "commandGrants": ["viewer"], "capabilities": list(CAMERA_CAPS)},
          note="alex-role")
    s.inn(t + 53_000, ALEX_KEY, ALEX, "readiness", readiness(82, 140), note="alex-readiness")
    s.inn(t + 54_000, ALEX_KEY, ALEX, "heartbeat", heartbeat("Ready", battery=82), note="alex-heartbeat")
    s.inn(t + 55_000, ALEX_KEY, ALEX, "still", still(s, ALEX, "st-c2-001", t + 55_000, True), note="alex-still-1")
    s.invite(t + 300_000, "inv-3", "near-left-corner", "JVR-482", note="invite-camera-3")
    s.inn(t + 300_500, ALEX_KEY, ALEX, "heartbeat", heartbeat("Ready", battery=82))
    s.inn(t + 301_000, ALEX_KEY, ALEX, "still", still(s, ALEX, "st-c2-002", t + 301_000, True), note="alex-still-2")
    s.observe(t + 302_000, None, [
        row(JON, "near-baseline", "Local", None, "Ready", None, True, None),
        row(ALEX, "far-baseline", "Fresh", None, "Ready", None, True, 1100),
    ], note="lobby-screen")
    return s.doc("st23-lobby", "23-camera-lobby",
                 "Camera lobby demo: Camera 1 Jon's iPhone ready, Camera 2 approved by matching codes and ready, "
                 "Camera 3 Corner left waiting on JVR-482 (10 min)")


# ----- ST23: trust in the lobby (codes, typed codes, revoke, restart, transfer) ---------------------------------

def st23_trust() -> dict:
    s = Script(room_header([dict(HOST_MEMBER)]))
    t = T23
    s.invite(t, "inv-a", "far-baseline", "JVR-417")
    s.local(t, "readiness", readiness(78, 130))
    s.local(t, "heartbeat", heartbeat("Ready", battery=78))
    s.inn(t + 10_000, ALEX_KEY, ALEX, "hello", hello_guest())
    s.out(t + 10_010, [ALEX_KEY], "hello", hello_host())
    s.inn(t + 11_000, ALEX_KEY, ALEX, "join", join_qr(s, "inv-a", ALEX_KEY, "Alex's phone", "Pixel 9", "alex-a"))
    s.out(t + 11_010, [ALEX_KEY], "approvalRequest", {"inviteId": "inv-a", "hostNonce": host_nonce("alex-a")})
    s.inn(t + 11_200, ALEX_KEY, ALEX, "joinReveal", {"inviteId": "inv-a", "guestNonce": guest_nonce("alex-a")})
    code = sas(s, "inv-a", ALEX_KEY, "alex-a")
    s.comparison(t + 15_000, "inv-a", code, code)
    s.out(t + 15_010, [ALEX_KEY], "approve", {"inviteId": "inv-a", "deviceId": ALEX, "guestKeySha256": ALEX_KEY,
                                              "basis": "comparisonCode"})
    s.out(t + 15_020, [ALEX_KEY], "roleAssigned", {"deviceId": ALEX, "slot": "far-baseline", "slotRole": "camera",
                                                   "commandGrants": ["viewer"], "capabilities": list(CAMERA_CAPS)})
    # a forwarded QR, scanned again by another phone (same display name as Alex's: the name never matters)
    s.inn(t + 20_000, STRANGER_KEY, STRANGER, "hello", hello_guest("ios"))
    s.inn(t + 20_500, STRANGER_KEY, STRANGER, "join",
          join_qr(s, "inv-a", STRANGER_KEY, "Alex's phone", "iPhone 16", "stranger-a"), code="inviteUsed",
          note="reused-code")
    s.invite(t + 30_000, "inv-b", "near-left-corner", "JVR-482")
    s.inn(t + 31_000, MALLORY_KEY, MALLORY, "hello", hello_guest("ios"))
    s.inn(t + 31_500, MALLORY_KEY, MALLORY, "join", join_typed("JVR-482", MALLORY_KEY, "Sam's phone", "iPhone 15",
                                                               binding=None),
          code="typedCodeNeedsChannelBinding", note="typed-code-unbound")
    # a man in the middle relays Sam's typed-code join: two TLS channels, two exporter values
    s.inn(t + 32_000, MALLORY_KEY, MALLORY, "join", join_typed("JVR-482", MALLORY_KEY, "Sam's phone", "iPhone 15"),
          exporter=EXPORTER_X, note="mitm-join")
    s.out(t + 32_010, [MALLORY_KEY], "approvalRequest", {"inviteId": "inv-b", "hostNonce": None})
    s.comparison(t + 40_000, "inv-b", "654318", "032799", decision="decline",
                 guest_view={"hostKeySha256": MALLORY_HOST_KEY, "guestKeySha256": SAM_KEY, "exporter": EXPORTER_Y},
                 note="mitm-codes-differ")
    s.out(t + 40_010, [MALLORY_KEY], "decline", {"inviteId": "inv-b", "reason": "codesDidNotMatch"}, note="mitm-declined")
    s.inn(t + 50_000, SAM_KEY, SAM, "hello", hello_guest("ios"))
    s.inn(t + 50_500, SAM_KEY, SAM, "join", join_typed("JVR-482", SAM_KEY, "Sam's phone", "iPhone 15"),
          exporter=EXPORTER_SAM, note="sam-typed-join")
    s.out(t + 50_510, [SAM_KEY], "approvalRequest", {"inviteId": "inv-b", "hostNonce": None})
    sam_code = tls_code(EXPORTER_SAM, HOST_KEY, SAM_KEY)
    s.comparison(t + 60_000, "inv-b", sam_code, sam_code, note="sam-codes-match")
    s.out(t + 60_010, [SAM_KEY], "approve", {"inviteId": "inv-b", "deviceId": SAM, "guestKeySha256": SAM_KEY,
                                             "basis": "channelBindingCode"}, note="sam-approved")
    s.out(t + 60_020, [SAM_KEY], "roleAssigned", {"deviceId": SAM, "slot": "near-left-corner", "slotRole": "camera",
                                                  "commandGrants": ["viewer"], "capabilities": list(CAMERA_CAPS)})
    s.invite(t + 70_000, "inv-c", "far-right-corner", "JVR-555")
    s.inn(t + 670_001, STRANGER_KEY, STRANGER, "join",
          join_qr(s, "inv-c", STRANGER_KEY, "Riley's phone", "iPhone 16", "stranger-c"), code="inviteExpired",
          note="expired-code")
    s.invite(t + 680_000, "inv-d", "near-right-corner", "JVR-640")
    s.out(t + 680_100, [ALEX_KEY], "roleAssigned", {"deviceId": ALEX, "slot": "near-right-corner", "slotRole": "camera",
                                                    "commandGrants": ["viewer"], "capabilities": list(CAMERA_CAPS)},
          note="alex-moved")
    s.inn(t + 681_000, STRANGER_KEY, STRANGER, "join",
          join_qr(s, "inv-d", STRANGER_KEY, "Riley's phone", "iPhone 16", "stranger-d"), code="slotFull",
          note="slot-full")
    s.out(t + 690_000, [ALEX_KEY], "revoke", {"deviceId": ALEX, "inviteId": None, "reason": "hostRemoved"},
          note="alex-revoked")
    s.inn(t + 690_500, ALEX_KEY, ALEX, "heartbeat", heartbeat("Ready"), code="revokedPeer", note="revoked-closes")
    s.inn(t + 691_000, STRANGER_KEY, STRANGER, "join",
          join_qr(s, "inv-a", STRANGER_KEY, "Riley's phone", "iPhone 16", "stranger-a2"), code="inviteRevoked",
          note="revoked-code-void")
    s.invite(t + 700_000, "inv-e", "far-baseline", "JVR-733")
    s.restart(t + 710_000, "hostRestart", 2, note="host-restart")
    s.inn(t + 711_000, SAM_KEY, SAM, "heartbeat", heartbeat("Ready"), code="staleEpoch", epoch=1, note="old-epoch")
    s.inn(t + 711_500, SAM_KEY, SAM, "heartbeat", heartbeat("Ready"), code="reauthRequired", note="reauth-first")
    s.inn(t + 712_000, SAM_KEY, SAM, "hello", hello_guest("ios"), note="reauth-hello")
    s.out(t + 712_010, [SAM_KEY], "hello", hello_host())
    s.inn(t + 712_500, SAM_KEY, SAM, "heartbeat", heartbeat("Ready"))
    s.inn(t + 713_000, STRANGER_KEY, STRANGER, "join",
          join_qr(s, "inv-e", STRANGER_KEY, "Riley's phone", "iPhone 16", "stranger-e"), code="inviteRevoked",
          note="restart-voids-code")
    s.invite(t + 720_000, "inv-f", "far-baseline", "JVR-808")
    s.observe(t + 721_000, None, [
        row(JON, "near-baseline", "Local", None, "Ready", None, True, None),
        row(SAM, "near-left-corner", "Delayed", 8500, "Ready", "No contact for 0:08", None, None),
    ], note="after-restart-screen")
    s.restart(t + 730_000, "hostTransfer", 3, device=SAM, key=SAM_KEY, note="host-transfer")
    s.inn(t + 731_000, STRANGER_KEY, STRANGER, "join",
          join_qr(s, "inv-f", STRANGER_KEY, "Riley's phone", "iPhone 16", "stranger-f"), code="inviteRevoked",
          note="transfer-voids-code")
    return s.doc("st23-trust", "23-camera-lobby",
                 "Camera lobby trust: a reused code, a typed code without channel binding, a man in the middle "
                 "declined, an expired code, a full slot, revoke, a host restart and a host transfer")


# ----- ST24: director capture (screen 24 demo state) -------------------------------------------------------------

T24 = 2_000_000


def st24_director() -> dict:
    alex = member(ALEX, ALEX_KEY, "Alex's phone", "far-baseline")
    sam = member(SAM, SAM_KEY, "Sam's phone", "near-left-corner")
    s = Script(room_header([dict(HOST_MEMBER), alex, sam]))
    t = T24
    s.local(t, "readiness", readiness(78, 130))
    s.local(t, "heartbeat", heartbeat("Ready", battery=78))
    s.inn(t + 100, ALEX_KEY, ALEX, "readiness", readiness(82, 140))
    s.inn(t + 200, ALEX_KEY, ALEX, "heartbeat", heartbeat("Ready", battery=82))
    s.inn(t + 300, SAM_KEY, SAM, "readiness", readiness(76, 130, thermal="fair"))
    s.inn(t + 400, SAM_KEY, SAM, "heartbeat", heartbeat("Ready", battery=76, thermal="fair"))
    start = command("cmd-start-1", JON, "capture-controller", "all", [JON, ALEX, SAM], 0, intentId="intent-1")
    s.local(t + 1000, "recordingIntent", start, note="start-intent")
    s.local(t + 1001, "receipt", receipt("cmd-start-1", JON, "Accepted", None, False, 1,
                                         [(JON, "Pending", None), (ALEX, "Pending", None), (SAM, "Pending", None)]),
            note="start-pending")
    s.out(t + 1002, [ALEX_KEY, SAM_KEY], "recordingIntent", start)
    s.local(t + 1100, "recordingStarted", started(JON, "intent-1", "seg-c1-001", t + 1100))
    s.inn(t + 1400, ALEX_KEY, ALEX, "recordingStarted", started(ALEX, "intent-1", "seg-c2-001", t + 1400))
    s.inn(t + 1600, SAM_KEY, SAM, "recordingStarted", started(SAM, "intent-1", "seg-c3-001", t + 1600),
          note="sam-ack")
    s.local(t + 1700, "receipt", receipt("cmd-start-1", JON, "Accepted", None, False, 1,
                                         [(JON, "Accepted", None), (ALEX, "Accepted", None), (SAM, "Accepted", None)]),
            note="start-confirmed")
    obs = t + 1100 + 754_000   # REC 12:34
    s.inn(obs - 11_900, SAM_KEY, SAM, "still", still(s, SAM, "st-c3-201", obs - 11_900, False))
    s.inn(obs - 11_000, SAM_KEY, SAM, "heartbeat",
          heartbeat("Recording", "seg-c3-001", 742_000, 74, thermal="serious"))   # warming: stills pause
    s.inn(obs - 7_900, ALEX_KEY, ALEX, "still", still(s, ALEX, "st-c2-301", obs - 7_900, False), note="alex-still")
    s.inn(obs - 1_500, ALEX_KEY, ALEX, "heartbeat", heartbeat("Recording", "seg-c2-001", 752_000, 80))
    s.inn(obs - 900, SAM_KEY, SAM, "heartbeat", heartbeat("Recording", "seg-c3-001", 753_000, 74, thermal="serious"))
    s.local(obs - 500, "heartbeat", heartbeat("Recording", "seg-c1-001", 754_000, 78))
    s.observe(obs, {"n": 3, "m": 3}, [
        row(JON, "near-baseline", "Local", None, "Recording", None, True, None),
        row(ALEX, "far-baseline", "Fresh", None, "Recording", None, True, 8000),
        row(SAM, "near-left-corner", "Fresh", None, "Recording", None, True, 12000),
    ], note="director-screen")
    mark = command("cmd-mark-1", JON, "scorer", "room", [], None, ttl=30_000, matchClockHintMs=754_000, note=None)
    s.local(obs + 200, "bookmark", mark, note="mark-point")
    s.local(obs + 201, "receipt", receipt("cmd-mark-1", JON, "Accepted", None, False, 1, []))
    return s.doc("st24-director", "24-director-capture",
                 "Director capture demo: REC 12:34, Recording on 3 of 3 phones from three acknowledgements, "
                 "stills aged 8 s and 12 s, Mark point")


# ----- ST24: contact lost, commands and receipts ---------------------------------------------------------------

T24B = 3_000_000


def st24_contact_lost() -> dict:
    members = [dict(HOST_MEMBER), member(ALEX, ALEX_KEY, "Alex's phone", "far-baseline"),
               member(SAM, SAM_KEY, "Sam's phone", "near-left-corner"),
               member(KAI, KAI_KEY, "Kai's phone", "far-left-corner")]
    s = Script(room_header(members, epoch=2))
    t = T24B
    s.local(t, "readiness", readiness(78, 130))
    s.local(t, "heartbeat", heartbeat("Ready", battery=78))
    for i, (key, dev) in enumerate(((ALEX_KEY, ALEX), (SAM_KEY, SAM), (KAI_KEY, KAI))):
        s.inn(t + 100 * (i + 1), key, dev, "heartbeat", heartbeat("Ready"))
    everyone = [JON, ALEX, SAM, KAI]
    start = command("cmd-start-1", JON, "capture-controller", "all", everyone, 0, intentId="intent-1")
    s.local(t + 1000, "recordingIntent", start)
    s.local(t + 1001, "receipt", receipt("cmd-start-1", JON, "Accepted", None, False, 1,
                                         [(d, "Pending", None) for d in everyone]))
    s.out(t + 1002, [ALEX_KEY, SAM_KEY, KAI_KEY], "recordingIntent", start)
    s.local(t + 1100, "recordingStarted", started(JON, "intent-1", "seg-c1-001", t + 1100))
    for i, (key, dev, seg) in enumerate(((ALEX_KEY, ALEX, "seg-c2-001"), (SAM_KEY, SAM, "seg-c3-001"),
                                         (KAI_KEY, KAI, "seg-c4-001"))):
        s.inn(t + 1300 + 100 * i, key, dev, "recordingStarted", started(dev, "intent-1", seg, t + 1300 + 100 * i))
    s.local(t + 1600, "receipt", receipt("cmd-start-1", JON, "Accepted", None, False, 1,
                                         [(d, "Accepted", None) for d in everyone]))
    s.inn(t + 60_000, KAI_KEY, KAI, "heartbeat", heartbeat("Recording", "seg-c4-001", 58_000), note="kai-last-heard")
    s.inn(t + 100_000, ALEX_KEY, ALEX, "heartbeat", heartbeat("Recording", "seg-c2-001", 98_000), note="alex-beat")
    s.inn(t + 100_500, SAM_KEY, SAM, "heartbeat", heartbeat("Recording", "seg-c3-001", 98_500))
    s.inn(t + 100_700, SAM_KEY, SAM, "segmentEvent", {"segmentId": "seg-c3-001", "event": "interruption",
                                                      "reason": "call", "mediaMs": 98_700, "nextSegmentId": None})
    s.local(t + 101_000, "heartbeat", heartbeat("Recording", "seg-c1-001", 99_900, 78))
    s.observe(t + 102_000, {"n": 3, "m": 4}, [
        row(JON, "near-baseline", "Local", None, "Recording", None, True, None),
        row(ALEX, "far-baseline", "Fresh", None, "Recording", None, None, None),
        row(SAM, "near-left-corner", "Fresh", None, "Recording", None, None, None),
        row(KAI, "far-left-corner", "Unknown", 42000, "Recording", "No contact for 0:42 · may still be recording",
            None, None),
    ], note="silent-42s")
    s.inn(t + 103_000, ALEX_KEY, ALEX, "heartbeat", heartbeat("Recording", "seg-c2-001", 101_000), code="staleEpoch",
          epoch=1, note="old-epoch")
    alex_seq = next(st["message"]["seq"] for st in s.steps if st.get("note") == "alex-beat")
    s.inn(t + 103_500, ALEX_KEY, ALEX, "heartbeat", heartbeat("Recording", "seg-c2-001", 101_500),
          code="seqNotIncreasing", seq=alex_seq, note="replayed-seq")
    viewer_stop = command("cmd-x1", ALEX, "viewer", "all", everyone, 1, age=50, confirmed=True,
                          targetLabel="Stop all cameras (4)")
    s.inn(t + 104_000, ALEX_KEY, ALEX, "stopAll", viewer_stop, note="viewer-stop-all")
    s.out(t + 104_010, [ALEX_KEY], "receipt", receipt("cmd-x1", ALEX, "Rejected", "grantNotPermitted", False, 1, []),
          note="viewer-stop-all-receipt")
    claimed = command("cmd-x2", ALEX, "capture-controller", "all", everyone, 1, age=50, confirmed=True,
                      targetLabel="Stop all cameras (4)")
    s.inn(t + 104_500, ALEX_KEY, ALEX, "stopAll", claimed, note="claims-control")
    s.out(t + 104_510, [ALEX_KEY], "receipt", receipt("cmd-x2", ALEX, "Rejected", "grantNotHeld", True, 1, []),
          note="claims-control-receipt")
    s.out(t + 105_000, [ALEX_KEY], "grantChanged", {"deviceId": ALEX, "commandGrants": ["capture-controller", "viewer"]},
          note="alex-granted-control")
    mark = command("cmd-a1", ALEX, "capture-controller", "room", [], None, ttl=30_000, age=10,
                   matchClockHintMs=105_000, note="Great rally")
    s.inn(t + 106_000, ALEX_KEY, ALEX, "bookmark", mark, note="bookmark")
    original = receipt("cmd-a1", ALEX, "Accepted", None, False, 1, [])
    s.out(t + 106_010, [ALEX_KEY], "receipt", original, note="bookmark-receipt")
    retry = copy.deepcopy(mark)
    retry["expiry"]["ageAtSendMs"] = 900
    s.inn(t + 107_000, ALEX_KEY, ALEX, "bookmark", retry, note="retry-same-payload")
    s.out(t + 107_010, [ALEX_KEY], "receipt", original, note="retry-receipt")
    other = copy.deepcopy(mark)
    other["note"] = "Changed note"
    s.inn(t + 108_000, ALEX_KEY, ALEX, "bookmark", other, note="reuse-other-payload")
    s.out(t + 108_010, [ALEX_KEY], "receipt", receipt("cmd-a1", ALEX, "Rejected", "commandIdReuse", True, 1, []),
          note="reuse-receipt")
    s.inn(t + 109_000, ALEX_KEY, ALEX, "stopOne", command("cmd-a2", ALEX, "capture-controller", "one", [KAI], 0, age=20),
          note="stale-revision")
    s.out(t + 109_010, [ALEX_KEY], "receipt", receipt("cmd-a2", ALEX, "Conflicted", "baseRevisionStale", False, 1, []),
          note="stale-revision-receipt")
    s.inn(t + 110_000, ALEX_KEY, ALEX, "stopOne", command("cmd-a3", ALEX, "capture-controller", "one", [KAI], 1, age=20),
          transit=None, note="unbounded-transit")
    s.out(t + 110_010, [ALEX_KEY], "receipt", receipt("cmd-a3", ALEX, "Expired", "unboundedTransit", False, 1, []),
          note="unbounded-transit-receipt")
    s.inn(t + 110_500, SAM_KEY, SAM, "heartbeat", heartbeat("Recording", "seg-c3-001", 108_500))
    s.inn(t + 110_600, ALEX_KEY, ALEX, "heartbeat", heartbeat("Recording", "seg-c2-001", 108_600))
    stop_all = command("cmd-stop-all", JON, "capture-controller", "all", everyone, 1, confirmed=True,
                       targetLabel="Stop all cameras (4)")
    s.local(t + 111_000, "stopAll", stop_all, note="stop-all")
    s.local(t + 111_001, "receipt", receipt("cmd-stop-all", JON, "Accepted", None, False, 2,
                                            [(d, "Pending", None) for d in everyone]))
    s.out(t + 111_002, [ALEX_KEY, SAM_KEY, KAI_KEY], "stopAll", stop_all)
    s.local(t + 111_200, "recordingStopped", {"commandId": "cmd-stop-all", "segments": [
        {"segmentId": "seg-c1-001", "durationMs": 109_900, "bytes": 2_350_000_000}]})
    s.inn(t + 111_500, ALEX_KEY, ALEX, "recordingStopped", {"commandId": "cmd-stop-all", "segments": [
        {"segmentId": "seg-c2-001", "durationMs": 109_800, "bytes": 2_340_000_000}]})
    s.inn(t + 112_000, SAM_KEY, SAM, "commandResult", {"commandId": "cmd-stop-all", "result": "Failed",
                                                       "reason": "finalizeFailed"})
    s.local(t + 121_001, "receipt", receipt("cmd-stop-all", JON, "Accepted", None, False, 2, [
        (JON, "Accepted", None), (ALEX, "Accepted", None), (SAM, "Failed", "finalizeFailed"),
        (KAI, "Unknown", "noAcknowledgement")]), note="stop-all-partial")
    s.observe(t + 121_500, {"n": 0, "m": 4}, [
        row(JON, "near-baseline", "Local", None, "Stopped", None, True, None),
        row(ALEX, "far-baseline", "Delayed", 10_000, "Stopped", "No contact for 0:10", None, None),
        row(SAM, "near-left-corner", "Delayed", 9_500, "Recording", "No contact for 0:09 · may still be recording",
            None, None),
        row(KAI, "far-left-corner", "Unknown", 61_500, "Recording", "No contact for 1:01 · may still be recording",
            None, None),
    ], note="after-stop-all")
    return s.doc("st24-contact-lost", "24-director-capture",
                 "Director capture trust: a camera silent for 42 s, old epoch and replayed seq refused, viewer stop-all "
                 "refused, retries, a reused command id, and a partial stop-all")


TRANSCRIPTS = {
    "room-transcript.st23-lobby": st23_lobby,
    "room-transcript.st23-trust": st23_trust,
    "room-transcript.st24-director": st24_director,
    "room-transcript.st24-contact-lost": st24_contact_lost,
}


# ----- invalid transcript cases ----------------------------------------------------------------------------------

def find(doc, note):
    for i, step in enumerate(doc["steps"]):
        if step.get("note") == note:
            return i
    raise KeyError(note)


def msg_patch(doc, i, path, value):
    """Replace a field inside step i's message and keep its frame length honest (so the case tests the field, not
    the length)."""
    step = copy.deepcopy(doc["steps"][i])
    probe = apply_patch({"m": step["message"]}, [rep("/m" + path, value)])["m"]
    ops = [rep(f"/steps/{i}/message" + path, value)]
    if "length" in step:
        ops.append(rep(f"/steps/{i}/length", len(canonical_bytes(probe))))
    return ops


def accept(doc, note):
    return [rep(f"/steps/{find(doc, note)}/verdict", {"accepted": True})]


def invalid_sets(docs):
    lobby, trust, director, lost = (docs[k] for k in TRANSCRIPTS)
    join = find(lobby, "alex-join")
    reveal = find(lobby, "alex-reveal")
    approve = find(lobby, "alex-approved")
    role = find(lobby, "alex-role")
    still2 = find(lobby, "alex-still-2")
    still1 = find(lobby, "alex-still-1")
    public_qr = qr_text(payload("inv-2", "JVR-417", T23, eps=endpoints(address="8.8.8.8")))
    long_qr = qr_text(payload("inv-2", "JVR-417", T23, lifetime_s=660))
    named_qr = qr_text(payload("inv-2", "JVR-417", T23, eps=endpoints(hint="Jons iPhone")))
    short_qr = qr_text(payload("inv-2", "JVR-417", T23, token=b64url(b"\x07" * 16)))
    sets = {}
    sets["room-transcript.st23-lobby"] = [
        bad("expired-code", "A join after the invitation's 10 minutes on the host's clock is refused, not accepted",
            [rep("/steps/0/atMs", 400_000)], "inviteExpired"),
        bad("role-bound-before-approval", "A slot role is never bound before the host approves the phone",
            [{"op": "remove", "path": f"/steps/{approve}"}],
            "roleBeforeApproval"),
        bad("approval-by-display-name", "Approval names a key and a comparison code, never a display name",
            msg_patch(lobby, approve, "/body/basis", "displayName")),
        bad("approval-names-other-key", "Approving a key other than the one that joined is refused, even with the same "
            "display name", msg_patch(lobby, approve, "/body/guestKeySha256", STRANGER_KEY), "approvalKeyMismatch"),
        bad("approval-without-comparison", "Approve needs both screens compared and Allow tapped",
            [{"op": "remove", "path": f"/steps/{find(lobby, 'alex-codes-match')}"}], "approvalWithoutComparison"),
        bad("comparison-code-wrong", "The host's screen shows the code the keys and nonces give",
            [rep(f"/steps/{find(lobby, 'alex-codes-match')}/hostScreenCode", "000000")], "comparisonCodeWrong"),
        bad("frame-over-max-length", "A declared frame length over 65,536 bytes is refused before the body is read",
            [rep(f"/steps/{join}/length", 70_000)], "frameTooLong"),
        bad("frame-length-mismatch", "The 4-byte prefix is the body's exact byte length",
            [rep(f"/steps/{join}/length", lobby["steps"][join]["length"] + 1)], "frameLengthMismatch"),
        bad("bad-proof", "The join proof must be the HMAC of the QR secret",
            msg_patch(lobby, join, "/body/proof", "0" * 64), "badProof"),
        bad("host-key-mismatch", "The guest must have seen the host key the QR pins",
            msg_patch(lobby, join, "/body/observedHostKeySha256", MALLORY_HOST_KEY), "hostKeyMismatch"),
        bad("guest-key-not-channel", "The join's key is the TLS channel's key",
            msg_patch(lobby, join, "/body/guestKeySha256", STRANGER_KEY), "guestKeyNotChannelKey"),
        bad("commitment-mismatch", "The revealed nonce must open the commitment made before the host's nonce",
            msg_patch(lobby, reveal, "/body/guestNonce", sample_nonce("other")), "commitmentMismatch"),
        bad("camera-grant-exceeded", "A camera guest starts with record-local and view-own-preview only",
            msg_patch(lobby, role, "/body/commandGrants", ["capture-controller", "viewer"]), "cameraGrantExceeded"),
        bad("camera-capability-exceeded", "upload-own-source is not part of a camera guest's start",
            msg_patch(lobby, role, "/body/capabilities", ["record-local", "upload-own-source", "view-own-preview"]),
            "cameraGrantExceeded"),
        bad("wrong-room", "A frame for another room is refused",
            msg_patch(lobby, find(lobby, "alex-heartbeat"), "/roomId", "room-other"), "wrongRoom"),
        bad("sender-not-channel-peer", "A message is attributed by its TLS peer, never by its deviceId",
            msg_patch(lobby, find(lobby, "alex-heartbeat"), "/deviceId", JON), "senderNotChannelPeer"),
        bad("seq-not-increasing", "A replayed or non-increasing seq is refused",
            msg_patch(lobby, find(lobby, "alex-heartbeat"), "/seq", 1), "seqNotIncreasing"),
        bad("still-while-hot", "Stills only at thermal nominal or fair",
            msg_patch(lobby, find(lobby, "alex-readiness"), "/body/thermal", "serious")
            + msg_patch(lobby, find(lobby, "alex-heartbeat"), "/body/thermal", "serious"), "stillWhileHot"),
        bad("still-cadence", "Stills while framing are at least 2 s apart",
            msg_patch(lobby, still2, "/body/captureMonoNs",
                      lobby["steps"][still1]["message"]["body"]["captureMonoNs"] + 1_000_000_000), "stillCadence"),
        bad("qr-public-endpoint", "A QR whose endpoint is a public address is refused",
            [rep("/steps/0/qr", public_qr)], "endpointNotAllowed"),
        bad("qr-lifetime-over-10-min", "An invitation lives at most 10 minutes",
            [rep("/steps/0/qr", long_qr), rep("/steps/0/lifetimeS", 660)], "inviteLifetime"),
        bad("qr-names-the-room", "The advertised instance is the opaque room hint, never a name",
            [rep("/steps/0/qr", named_qr)], "roomHintMismatch"),
        bad("qr-secret-16-bytes", "The QR secret is 32 random bytes",
            [rep("/steps/0/qr", short_qr)], "secretLength"),
        bad("room-hint-with-a-name", "The room hint is opaque random characters", [rep("/room/roomHint", "Jons-court")]),
        bad("frame-refusal-hidden", "A frame the host must accept is not declared refused",
            [rep(f"/steps/{find(lobby, 'alex-heartbeat')}/verdict", {"accepted": False, "code": "staleEpoch"})],
            "unexpectedAccept"),
        bad("lobby-ready-shown-wrongly", "Ready follows the camera's own readiness report",
            [rep(f"/steps/{find(lobby, 'lobby-screen')}/display/devices/1/ready", False)], "readyMismatch"),
    ]
    sets["room-transcript.st23-trust"] = [
        bad("reused-code", "A used code is refused for every later phone", accept(trust, "reused-code"), "inviteUsed"),
        bad("typed-code-without-binding", "A typed code without a channel-bound comparison code is refused",
            accept(trust, "typed-code-unbound"), "typedCodeNeedsChannelBinding"),
        bad("mitm-allowed", "Allow on codes that differ is refused",
            [rep(f"/steps/{find(trust, 'mitm-codes-differ')}/decision", "allow")], "comparisonCodeMismatch"),
        bad("expired-code-accepted", "An expired code is refused", accept(trust, "expired-code"), "inviteExpired"),
        bad("slot-full-accepted", "A code for a slot that has a phone is refused", accept(trust, "slot-full"), "slotFull"),
        bad("revoked-phone-heard", "Revoke closes the connection", accept(trust, "revoked-closes"), "revokedPeer"),
        bad("revoked-code-accepted", "Revoke voids the code the phone used", accept(trust, "revoked-code-void"),
            "inviteRevoked"),
        bad("old-epoch-accepted", "An older host epoch is refused", accept(trust, "old-epoch"), "staleEpoch"),
        bad("no-reauth-after-restart", "After a new epoch a member re-authenticates first", accept(trust, "reauth-first"),
            "reauthRequired"),
        bad("restart-keeps-code", "A host restart voids open codes", accept(trust, "restart-voids-code"), "inviteRevoked"),
        bad("transfer-keeps-code", "A host transfer voids every open code", accept(trust, "transfer-voids-code"),
            "inviteRevoked"),
        bad("decline-reason-hidden", "A decline after codes differ says so",
            msg_patch(trust, find(trust, "mitm-declined"), "/body/reason", "hostDeclined"), "declineReasonMismatch"),
    ]
    start_ack = find(director, "sam-ack")
    sets["room-transcript.st24-director"] = [
        bad("ack-counted-without-recording-started", "Recording on n of m counts recordingStarted acknowledgements for "
            "this intent, not a local start",
            msg_patch(director, start_ack, "/body/intentId", None)
            + msg_patch(director, find(director, "start-confirmed"), "/body/perDevice/2/result", "Pending"),
            "recordingCountMismatch"),
        bad("blanket-start-receipt", "A start is an intent: per-device results stay Pending until acknowledged",
            msg_patch(director, find(director, "start-pending"), "/body/perDevice/2/result", "Accepted"),
            "receiptMismatch"),
        bad("still-age-not-chained", "A still's age chains the sender's capture lag and the host's own clock",
            [rep(f"/steps/{find(director, 'director-screen')}/display/devices/1/stillAgeMs", 7900)], "stillAgeMismatch"),
        bad("still-is-a-video-frame", "A preview still is small (at most 256 KiB)",
            msg_patch(director, find(director, "alex-still"), "/body/bytes", 5_000_000)),
    ]
    silent = find(lost, "silent-42s")
    sets["room-transcript.st24-contact-lost"] = [
        bad("stop-inferred-from-silence", "Silence is never shown as Stopped",
            [rep(f"/steps/{silent}/display/devices/3/state", "Stopped")], "stopInferredFromSilence"),
        bad("silent-shown-fresh", "A camera silent for 42 s is Unknown",
            [rep(f"/steps/{silent}/display/devices/3/freshness", "Fresh")], "freshnessMismatch"),
        bad("silent-counted", "An Unknown camera is not counted in Recording on n of m",
            [rep(f"/steps/{silent}/display/recordingOn", {"n": 4, "m": 4})], "recordingCountMismatch"),
        bad("silent-label", "A silent recording camera reads No contact for 0:42 · may still be recording",
            [rep(f"/steps/{silent}/display/devices/3/label", "Stopped")], "labelMismatch"),
        bad("old-epoch-accepted", "An older host epoch is refused", accept(lost, "old-epoch"), "staleEpoch"),
        bad("replayed-seq-accepted", "A replayed seq is refused", accept(lost, "replayed-seq"), "seqNotIncreasing"),
        bad("viewer-stop-all-accepted", "A viewer cannot stop all",
            msg_patch(lost, find(lost, "viewer-stop-all-receipt"), "/body/status", "Accepted"), "receiptMismatch"),
        bad("claimed-grant-not-security-event", "Claiming a grant the member does not hold is a security event",
            msg_patch(lost, find(lost, "claims-control-receipt"), "/body/securityEvent", False), "receiptMismatch"),
        bad("reuse-not-flagged", "The same commandId with another payload is refused as a security event",
            msg_patch(lost, find(lost, "reuse-receipt"), "/body/status", "Accepted"), "receiptMismatch"),
        bad("retry-new-receipt", "A retry with the same payload returns the original receipt",
            msg_patch(lost, find(lost, "retry-receipt"), "/body/eventRevision", 2), "receiptMismatch"),
        bad("stop-all-blanket-success", "A silent camera's stop result is Unknown, never Accepted",
            msg_patch(lost, find(lost, "stop-all-partial"), "/body/perDevice/3/result", "Accepted"), "receiptMismatch"),
        bad("stop-all-missing-target", "Stop all names every enrolled camera",
            msg_patch(lost, find(lost, "stop-all"), "/body/target/deviceIds", [JON, ALEX, SAM])
            + msg_patch(lost, find(lost, "stop-all"), "/body/targetLabel", "Stop all cameras (3)"), "receiptMismatch"),
        bad("stop-all-unconfirmed", "Stop all is a confirmed action",
            msg_patch(lost, find(lost, "stop-all"), "/body/confirmed", False)),
        bad("missing-receipt", "Every command is answered by a receipt",
            [{"op": "remove", "path": f"/steps/{find(lost, 'stale-revision-receipt')}"}], "missingReceipt"),
        bad("unbounded-transit-accepted", "A capture command whose transit cannot be bounded expires",
            msg_patch(lost, find(lost, "unbounded-transit-receipt"), "/body/status", "Accepted"), "receiptMismatch"),
    ]
    out = {}
    for name, cases in sets.items():
        out[name] = {"schemaVersion": "jovra.studio-fixture.invalid-cases/1", "base": f"records/{name}.json",
                     "cases": cases}
    return out


# ----- vectors (hand-derived expectations) ---------------------------------------------------------------------------

FRAME_JSON = ('{"body":{"batteryPct":78,"captureState":"Recording","droppedFrames":0,"freeBytes":40000000000,'
              '"savedThroughMs":754000,"segmentId":"seg-c2-001","segmentIndex":0,"thermal":"nominal"},'
              '"deviceId":"device-alex","hostEpoch":1,"roomId":"room-court-day","schemaVersion":"jovra.room/1",'
              '"sentMonoNs":9000000000,"seq":7,"type":"heartbeat"}')


def qr_cases():
    good = payload("inv-v1", "JVR-417", 0)
    def case(cid, text, expect, observed=HOST_KEY):
        return {"id": cid, "op": "joinerQr", "qr": text, "observedHostKeySha256": observed, "expect": expect}
    noncanonical = "jovra-room:1:" + b64url(json.dumps(good, indent=1).encode())
    padded = qr_text(good) + "=="
    return [
        case("qr-valid", qr_text(good), {"result": "ok"}),
        case("qr-public-endpoint", qr_text(payload("inv-v1", "JVR-417", 0, eps=endpoints(address="8.8.8.8"))),
             {"code": "endpointNotAllowed"}),
        case("qr-cgnat-endpoint", qr_text(payload("inv-v1", "JVR-417", 0, eps=endpoints(address="100.64.0.7"))),
             {"code": "endpointNotAllowed"}),
        case("qr-loopback-endpoint", qr_text(payload("inv-v1", "JVR-417", 0, eps=endpoints(address="127.0.0.1"))),
             {"code": "endpointNotAllowed"}),
        case("qr-low-port", qr_text(payload("inv-v1", "JVR-417", 0, eps=endpoints(port=80))), {"code": "endpointNotAllowed"}),
        case("qr-link-local-v6", qr_text(payload("inv-v1", "JVR-417", 0, eps=endpoints(address="fe80::1"))),
             {"result": "ok"}),
        case("qr-web-url", "https://example.com/join?code=JVR-417", {"code": "notJovraRoomCode"}),
        case("qr-padded", padded, {"code": "malformedPayload"}),
        case("qr-not-canonical", noncanonical, {"code": "nonCanonicalPayload"}),
        case("qr-11-minutes", qr_text(payload("inv-v1", "JVR-417", 0, lifetime_s=660)), {"code": "inviteLifetime"}),
        case("qr-16-byte-secret", qr_text(payload("inv-v1", "JVR-417", 0, token=b64url(b"\x01" * 16))),
             {"code": "secretLength"}),
        case("qr-camera-with-control", qr_text(payload("inv-v1", "JVR-417", 0, command_role="capture-controller")),
             {"code": "cameraCannotControl"}),
        case("qr-wrong-host-key", qr_text(good), {"code": "hostKeyMismatch"}, observed=MALLORY_HOST_KEY),
    ]


def vectors():
    cases = [
        {"id": "approval-code-fixed-keys", "op": "approvalCode",
         "hostSpkiHex": HOST_SPKI, "guestSpkiHex": ALEX_SPKI, "qrNonce": "qrNonceFixedVector0001",
         "hostNonce": "hostNonceFixedVector01", "guestNonce": "guestNonceFixedVector1",
         "expect": {"hostKeySha256": HOST_KEY, "guestKeySha256": ALEX_KEY,
                    "commitment": "e6cd773220cd095eff498ce6d6e53204cc6ea212fc3517e101cc26d4f1df4ebe",
                    "digest": "23a8dc1370fec6d3d6f002c3adf49f7b0bdfc4e7805a2435a508be6032a75066", "code": "268947"},
         "hand": "printf 'jovra-room-sas|<hostKey>|<guestKey>|<qrNonce>|<hostNonce>|<guestNonce>' | shasum -a 256 -> "
                 "23a8dc13...; 0x23a8dc13 = 598268947; 598268947 mod 1000000 = 268947 (bc, 2026-10-08)"},
        {"id": "typed-code-channel-binding", "op": "channelCode", "exporter": EXPORTER_X, "hostKeySha256": HOST_KEY,
         "guestKeySha256": MALLORY_KEY, "expect": {"code": "654318"},
         "hand": "0xfbeda06e = 4226654318; mod 1000000 = 654318"},
        {"id": "typed-code-mitm-differs", "op": "channelCode", "exporter": EXPORTER_Y, "hostKeySha256": MALLORY_HOST_KEY,
         "guestKeySha256": SAM_KEY, "expect": {"code": "032799"},
         "hand": "0xf78a405f = 4153032799; mod 1000000 = 032799: the guest's screen differs from the host's 654318"},
        {"id": "frame-encode", "op": "frameEncode", "canonicalJson": FRAME_JSON,
         "expect": {"prefixHex": "00000148", "length": 328}, "hand": "printf '%s' <json> | wc -c -> 328 = 0x148"},
        {"id": "frame-two-in-a-row", "op": "frameDecode",
         "streamHex": ("00000002" + b"{}".hex()) * 2, "expect": {"messages": 2}},
        {"id": "frame-over-max", "op": "frameDecode", "streamHex": "00010001" + "7b7d", "expect": {"code": "frameTooLong"}},
        {"id": "frame-at-max-declared-truncated", "op": "frameDecode", "streamHex": "00010000" + "7b7d",
         "expect": {"code": "truncatedFrame"}},
        {"id": "frame-short-prefix", "op": "frameDecode", "streamHex": "0000", "expect": {"code": "truncatedFrame"}},
        {"id": "frame-not-object", "op": "frameDecode", "streamHex": "00000003" + b"[1]".hex(),
         "expect": {"code": "malformedFrame"}},
        {"id": "frame-float", "op": "frameDecode", "streamHex": "00000009" + b'{"a":1.5}'.hex(),
         "expect": {"code": "malformedFrame"}},
        {"id": "frame-duplicate-key", "op": "frameDecode", "streamHex": "0000000d" + b'{"a":1,"a":2}'.hex(),
         "expect": {"code": "duplicateKey"}},
    ]
    for ms, band in ((0, "Fresh"), (5000, "Fresh"), (5001, "Delayed"), (15000, "Delayed"), (15001, "Unknown")):
        cases.append({"id": f"freshness-{ms}ms", "op": "freshness", "ageMs": ms, "state": "Recording",
                      "expect": {"band": band}})
    cases += [
        {"id": "silent-42s", "op": "freshness", "ageMs": 42000, "state": "Recording",
         "expect": {"band": "Unknown", "label": "No contact for 0:42 · may still be recording"}},
        {"id": "unheard-since-restart", "op": "freshness", "ageMs": None, "state": "Recording",
         "expect": {"band": "Unknown", "label": "No contact · may still be recording"}},
        {"id": "delayed-ready", "op": "freshness", "ageMs": 8000, "state": "Ready",
         "expect": {"band": "Delayed", "label": "No contact for 0:08"}},
        {"id": "stop-all-partial-results", "op": "perDevice", "targets": [JON, ALEX, SAM, KAI],
         "outcomes": {JON: ["Accepted", None], ALEX: ["Accepted", None], SAM: ["Failed", "finalizeFailed"]},
         "nowMs": 10_001, "deadlineMs": 10_000,
         "expect": [{"deviceId": JON, "result": "Accepted", "reason": None},
                    {"deviceId": ALEX, "result": "Accepted", "reason": None},
                    {"deviceId": SAM, "result": "Failed", "reason": "finalizeFailed"},
                    {"deviceId": KAI, "result": "Unknown", "reason": "noAcknowledgement"}]},
        {"id": "stop-all-before-deadline", "op": "perDevice", "targets": [JON, KAI],
         "outcomes": {JON: ["Accepted", None]}, "nowMs": 10_000, "deadlineMs": 10_000,
         "expect": [{"deviceId": JON, "result": "Accepted", "reason": None},
                    {"deviceId": KAI, "result": "Pending", "reason": None}]},
        {"id": "host-controls-is-capture-controller", "op": "grantsFromPermissions",
         "permissions": ["record-local", "upload-own-source", "view-own-preview", "host-controls"],
         "expect": ["capture-controller", "viewer"]},
        {"id": "camera-permissions-are-viewer", "op": "grantsFromPermissions",
         "permissions": ["record-local", "upload-own-source", "view-own-preview"], "expect": ["viewer"]},
    ]
    for grant, typ, allowed in (("viewer", "stopAll", False), ("viewer", "bookmark", False),
                                ("marker", "bookmark", True), ("scorer", "stopAll", False),
                                ("capture-controller", "stopAll", True), ("capture-controller", "recordingIntent", True)):
        cases.append({"id": f"permit-{grant}-{typ}", "op": "grantPermits", "grant": grant, "type": typ,
                      "expect": {"allowed": allowed}})
    cases += qr_cases()
    def step(cid, transcript, note, expect):
        return {"id": cid, "op": "transcriptStep", "transcript": transcript, "note": note, "expect": expect}
    lost, trust = "room-transcript.st24-contact-lost", "room-transcript.st23-trust"
    cases += [
        step("adr27-older-epoch", lost, "old-epoch", {"verdict": {"accepted": False, "code": "staleEpoch"}}),
        step("adr27-replayed-seq", lost, "replayed-seq", {"verdict": {"accepted": False, "code": "seqNotIncreasing"}}),
        step("adr27-same-id-same-payload", lost, "retry-receipt",
             {"receipt": receipt("cmd-a1", ALEX, "Accepted", None, False, 1, [])}),
        step("adr27-same-id-other-payload", lost, "reuse-receipt",
             {"receipt": receipt("cmd-a1", ALEX, "Rejected", "commandIdReuse", True, 1, [])}),
        step("adr27-viewer-stop-all", lost, "viewer-stop-all-receipt",
             {"receipt": receipt("cmd-x1", ALEX, "Rejected", "grantNotPermitted", False, 1, [])}),
        step("adr27-partial-stop-all", lost, "stop-all-partial",
             {"receipt": receipt("cmd-stop-all", JON, "Accepted", None, False, 2, [
                 (JON, "Accepted", None), (ALEX, "Accepted", None), (SAM, "Failed", "finalizeFailed"),
                 (KAI, "Unknown", "noAcknowledgement")])}),
        step("adr27-stale-revision-conflicted", lost, "stale-revision-receipt",
             {"receipt": receipt("cmd-a2", ALEX, "Conflicted", "baseRevisionStale", False, 1, [])}),
        step("freshness-silent-camera-42s", lost, "silent-42s",
             {"recordingOn": {"n": 3, "m": 4},
              "row": row(KAI, "far-left-corner", "Unknown", 42000, "Recording",
                         "No contact for 0:42 · may still be recording", None, None)}),
        step("adr27-typed-code-unbound", trust, "typed-code-unbound",
             {"verdict": {"accepted": False, "code": "typedCodeNeedsChannelBinding"}}),
        step("adr27-reused-code", trust, "reused-code", {"verdict": {"accepted": False, "code": "inviteUsed"}}),
        step("adr27-expired-code", trust, "expired-code", {"verdict": {"accepted": False, "code": "inviteExpired"}}),
        step("story40-slot-full", trust, "slot-full", {"verdict": {"accepted": False, "code": "slotFull"}}),
        step("adr27-revoke-closes", trust, "revoked-closes", {"verdict": {"accepted": False, "code": "revokedPeer"}}),
        step("adr27-revoke-voids-code", trust, "revoked-code-void",
             {"verdict": {"accepted": False, "code": "inviteRevoked"}}),
        step("adr27-transfer-voids-codes", trust, "transfer-voids-code",
             {"verdict": {"accepted": False, "code": "inviteRevoked"}}),
    ]
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": "room",
            "status": "hand-written expectations (ADR-0027 vectors, freshness, framing, QR, grants, the approval code "
                      "from fixed public keys); transcriptStep cases name a step of a room transcript by its note",
            "cases": cases}


# ----- what this module declares and registers ----------------------------------------------------------------------

def build_transcripts() -> dict:
    return {name: make() for name, make in TRANSCRIPTS.items()}


def fixtures(sample):
    docs = build_transcripts()
    out = {f"records/{name}.json": doc for name, doc in docs.items()}
    for name, doc in invalid_sets(docs).items():
        out[f"invalid/{name}.invalid.json"] = doc
    out["vectors/room.json"] = vectors()
    return out


def check_transcript_record(ctx, doc):
    summary = room.check_transcript(doc)
    summary.pop("host")
    return summary


def check_room_vector(ctx, case, report, where) -> None:
    op = case["op"]
    exp = case["expect"]

    def same(got, label):
        if got == exp:
            report.ok(label)
        else:
            report.fail(where, f"got {got!r}, expected {exp!r}")

    if op == "approvalCode":
        host = hashlib.sha256(bytes.fromhex(case["hostSpkiHex"])).hexdigest()
        guest = hashlib.sha256(bytes.fromhex(case["guestSpkiHex"])).hexdigest()
        commit = room.guest_commitment(guest, case["guestNonce"])
        code = room.comparison_code(host, guest, case["qrNonce"], case["hostNonce"], case["guestNonce"])
        digest = hashlib.sha256(f"jovra-room-sas|{host}|{guest}|{case['qrNonce']}|{case['hostNonce']}|"
                                f"{case['guestNonce']}".encode()).hexdigest()
        same({"hostKeySha256": host, "guestKeySha256": guest, "commitment": commit, "digest": digest, "code": code},
             "room vectors (approval code)")
    elif op == "channelCode":
        same({"code": room.channel_binding_code(case["exporter"], case["hostKeySha256"], case["guestKeySha256"])},
             "room vectors (channel-binding code)")
    elif op == "frameEncode":
        frame = room.encode_frame(json.loads(case["canonicalJson"]))
        ok = frame[4:] == case["canonicalJson"].encode()
        same({"prefixHex": frame[:4].hex(), "length": len(frame) - 4} if ok else {"body": "differs"},
             "room vectors (framing)")
    elif op == "frameDecode":
        try:
            got = {"messages": len(room.decode_frames(bytes.fromhex(case["streamHex"])))}
        except Reject as exc:
            got = {"code": exc.code}
        same(got, "room vectors (framing)")
    elif op == "freshness":
        band = room.freshness(case["ageMs"])
        got = {"band": band}
        if "label" in exp:
            got["label"] = room.contact_label(band, case["ageMs"], case["state"])
        same(got, "room vectors (freshness)")
    elif op == "perDevice":
        outcomes = {d: tuple(v) for d, v in case["outcomes"].items()}
        same(room.per_device_results(case["targets"], outcomes, case["nowMs"], case["deadlineMs"]),
             "room vectors (receipts)")
    elif op == "grantsFromPermissions":
        same(room.grants_from_permissions(case["permissions"]), "room vectors (grants)")
    elif op == "grantPermits":
        same({"allowed": room.grant_permits(case["grant"], case["type"])}, "room vectors (grants)")
    elif op == "joinerQr":
        try:
            room.joiner_check(case["qr"], case["observedHostKeySha256"])
            got = {"result": "ok"}
        except Reject as exc:
            got = {"code": exc.code}
        same(got, "room vectors (QR join payload)")
    elif op == "transcriptStep":
        doc = ctx.fixture(f"records/{case['transcript']}.json")
        out = room.step_outcome(doc, find(doc, case["note"]))
        if "row" in exp:
            rows = {r["deviceId"]: r for r in out["display"]["devices"]}
            got = {"recordingOn": out["display"]["recordingOn"], "row": rows.get(exp["row"]["deviceId"])}
        else:
            got = out
        same(got, "room vectors (ADR-0027 transcript steps)")
    else:
        report.fail(where, f"unknown room vector op {op!r}")


VECTOR_CHECKERS = {"room": check_room_vector}
SCHEMAS = {"jovra.room/1": "room.schema.json", "jovra.room-transcript/1": "room.schema.json"}
RECORD_RULES = {"jovra.room-transcript/1": check_transcript_record}


# ----- self-tests ---------------------------------------------------------------------------------------------------

def _transcript_qrs(ctx) -> list:
    out = []
    for name in TRANSCRIPTS:
        doc = ctx.fixture(f"records/{name}.json")
        out += [s["qr"] for s in doc["steps"] if s["step"] == "invite"]
    return out


def check_spec_room_drift(ctx, report) -> None:
    """The QR payload, the strict decoder, the LAN allow-list and the commitment, proof and comparison-code formulas
    agree with spec/room's reference and schema (read only); the grant names equal spec/room's commandRole enum and the
    freshness thresholds equal its default policy."""
    sys.path.insert(0, str(ROOT / "scripts" / "spec"))
    from jsonschema_subset import SchemaSet
    inv = spec_room_invitation()
    import jovra_room.freshness as fresh
    problems = []
    spec_schemas = SchemaSet(SPEC_ROOM_SCHEMAS)
    for qr in _transcript_qrs(ctx):
        payload_doc = room.decode_qr(qr)
        errors = spec_schemas.validate(payload_doc, "invitation-payload.schema.json")
        if errors:
            problems.append(f"a transcript QR fails spec/room's payload schema: {errors[:2]}")
        if inv.decode_qr(qr) != payload_doc:
            problems.append("spec/room decodes a transcript QR differently")
    for addr in ("192.168.1.20", "10.0.0.5", "172.16.4.4", "169.254.1.1", "fe80::1", "fd00::1", "8.8.8.8",
                 "100.64.0.7", "127.0.0.1", "224.0.0.251", "::1", "2001:db8::1", "192.0.2.1"):
        def ours():
            try:
                room.check_address(addr, 47100)
                return "ok"
            except Reject as exc:
                return exc.code
        def theirs():
            try:
                inv.check_resolved_endpoint(addr, 47100)
                return "ok"
            except Exception as exc:   # spec/room raises its own Reject type
                return getattr(exc, "code", "error")
        if ours() != theirs():
            problems.append(f"LAN allow-list differs for {addr}: {ours()} vs {theirs()}")
    keys = (HOST_KEY, ALEX_KEY, "qrNonceFixedVector0001", "hostNonceFixedVector01", "guestNonceFixedVector1")
    if room.comparison_code(*keys) != inv.verification_code(*keys):
        problems.append("comparison code differs from spec/room's verification_code")
    if room.guest_commitment(ALEX_KEY, keys[4]) != inv.guest_commitment(ALEX_KEY, keys[4]):
        problems.append("guest commitment differs")
    proof_args = (sample_token("x"), ROOM_ID, "inv-x", sample_nonce("x"), ALEX_KEY, "c" * 64)
    if room.join_proof(*proof_args) != inv.join_proof(*proof_args):
        problems.append("join proof differs")
    common = json.loads((SPEC_ROOM_SCHEMAS / "room-common.schema.json").read_text(encoding="utf-8"))["$defs"]
    ours_schema = ctx.schemas.files["room.schema.json"]["$defs"]
    if common["commandRole"]["enum"] != ours_schema["commandGrant"]["enum"]:
        problems.append("grant names differ from spec/room's commandRole enum")
    if common["displayCode"]["pattern"] != ours_schema["displayCode"]["pattern"] or common["nonce"]["pattern"] != \
            ours_schema["nonce"]["pattern"]:
        problems.append("display code or nonce pattern differs from spec/room")
    if (fresh.DEFAULT_POLICY["freshMaxMs"], fresh.DEFAULT_POLICY["delayedMaxMs"]) != (room.FRESH_MS, room.DELAYED_MS):
        problems.append("freshness thresholds differ from spec/room's default policy")
    if inv.QR_PREFIX != room.QR_PREFIX or inv.MAX_LIFETIME_S != room.MAX_INVITE_LIFETIME_S:
        problems.append("QR prefix or lifetime differs from spec/room")
    for problem in problems:
        report.fail("room-spec-room-drift", problem)
    if not problems:
        report.ok("drift checks")


def check_camera_invite_drift(ctx, report) -> None:
    """The roster permission host-controls is capture-controller: the Sample camera-invite record's host role maps to
    capture-controller and its cameras to viewer, and the transcripts' starting members agree; the display code
    pattern equals camera-invite's."""
    problems = []
    invite = ctx.records["camera-invite"]
    mapped = {r["deviceId"]: room.grants_from_permissions(r["permissions"]) for r in invite["roles"] if r["deviceId"]}
    if mapped.get(JON) != ["capture-controller", "viewer"] or mapped.get(ALEX) != ["viewer"]:
        problems.append(f"camera-invite permissions map to {mapped}")
    for name in TRANSCRIPTS:
        for m in ctx.fixture(f"records/{name}.json")["room"]["members"]:
            if m["deviceId"] in mapped and ("capture-controller" in m["commandGrants"]) != \
                    ("capture-controller" in mapped[m["deviceId"]]):
                problems.append(f"{name}: {m['deviceId']} grants disagree with its camera-invite permissions")
    ci = ctx.schemas.files["camera-invite.schema.json"]["properties"]["invites"]["items"]["properties"]
    if ci["displayCode"]["pattern"] != ctx.schemas.files["room.schema.json"]["$defs"]["displayCode"]["pattern"]:
        problems.append("display code pattern differs from jovra.camera-invite/1")
    for problem in problems:
        report.fail("room-camera-invite-drift", problem)
    if not problems:
        report.ok("drift checks")


def check_messages_schema(ctx, report) -> None:
    """Every message inside every transcript (and the framing vector's message) is a valid jovra.room/1 message on its
    own, and a message with an unknown type or a body of another type is refused by the schema."""
    problems = []
    count = 0
    for name in TRANSCRIPTS:
        for i, s in enumerate(ctx.fixture(f"records/{name}.json")["steps"]):
            if "message" in s:
                errors = ctx.schemas.validate(s["message"], "room.schema.json")
                count += 1
                if errors:
                    problems.append(f"{name} step {i}: {errors[:2]}")
    sample = json.loads(FRAME_JSON)
    for label, mutated in (("unknown type", dict(sample, type="still-live")),
                           ("body of another type", dict(sample, type="readiness")),
                           ("negative seq", dict(sample, seq=0))):
        if not ctx.schemas.validate(mutated, "room.schema.json"):
            problems.append(f"the schema accepts a message with {label}")
    if ctx.schemas.validate(sample, "room.schema.json"):
        problems.append("the framing vector's message is not a valid jovra.room/1 message")
    for problem in problems:
        report.fail("room-message-schema", problem)
    if not problems:
        report.ok("room messages schema-valid", count)


def check_secret_hygiene(ctx, report) -> None:
    """A QR secret appears only inside the QR text of its invite step: never in a message, a display or a header."""
    problems = []
    for name in TRANSCRIPTS:
        doc = ctx.fixture(f"records/{name}.json")
        tokens = [room.decode_qr(s["qr"])["joinToken"] for s in doc["steps"] if s["step"] == "invite"]
        rest = json.dumps([s for s in doc["steps"] if s["step"] != "invite"] + [doc["room"]])
        problems += [f"{name}: a join token appears outside its QR" for t in tokens if t in rest]
    for problem in problems:
        report.fail("room-secret-hygiene", problem)
    if not problems:
        report.ok("secret hygiene")


SELF_TESTS = {"room-spec-room-drift": check_spec_room_drift, "room-camera-invite-drift": check_camera_invite_drift,
              "room-message-schema": check_messages_schema, "room-secret-hygiene": check_secret_hygiene}
