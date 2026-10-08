"""JOVRA Room v1 (jovra.room/1): framing, the QR join payload, comparison codes, grants, receiver-owned freshness,
receipts, and a host-side transcript checker.

Sources: SD10 (docs/spec/studio-v1-spec.md), docs/research/studio/multicam-sync.md sections 2.4-2.7, and ADR-0027 as
amended 2026-10-07. Where spec/room (the jovra.room.<record>/1 family) already fixes a rule, this module uses the same
bytes: the QR payload (jovra.room.invitation-payload/1, strict decoding, the LAN allow-list), the guest commitment, the
join proof and the commit-then-reveal comparison code. The self-test room-spec-room-drift checks that both references
agree on the same inputs. The typed-code comparison code (from the TLS channel binding) is new here.

A transcript is one host's ordered view of a room. check_transcript() replays it and raises core.Reject with a stable
code at the first step where the host's declared behaviour differs from the rules: a frame the host must refuse but
accepted (or the reverse), an outbound message the host was not allowed to send, a receipt that is not what the
commands and acknowledgements give, or a screen state that is not what the room state gives.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import ipaddress
import json
import re

from .core import Reject, canonical_bytes, require, when

TRANSCRIPT = "jovra.room-transcript/1"
PAYLOAD_VERSION = "jovra.room.invitation-payload/1"
QR_PREFIX = "jovra-room:1:"
DNSSD_SERVICE = "_jovra-room._tcp"
MAX_FRAME_BYTES = 65_536
MAX_INVITE_LIFETIME_S = 600
SECRET_BYTES = 32
NONCE_BYTES = 16
MAX_JOIN_ATTEMPTS = 3
MAX_CAMERAS = 6
CAPTURE_TTL_MAX_MS = 30_000
FRESH_MS = 5_000
DELAYED_MS = 15_000
STILL_GAP_FRAMING_MS = 2_000
STILL_GAP_MS = 5_000
NS_PER_MS = 1_000_000
BASE64URL = re.compile(r"\A[A-Za-z0-9_-]*\Z")
LAN_NETWORKS = tuple(ipaddress.ip_network(n) for n in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "fc00::/7", "fe80::/10"))
PAYLOAD_KEYS = {"schemaVersion", "sample", "inviteId", "sessionId", "hostEpoch", "hostKeySha256", "joinToken", "nonce",
                "issuedAt", "expiresAt", "captureRole", "commandRole", "endpoints", "displayCode"}

GRANT_PERMITS = {
    "viewer": set(),
    "marker": {"bookmark"},
    "scorer": {"bookmark"},
    "capture-controller": {"recordingIntent", "stopOne", "stopAll", "bookmark"},
}
CAPTURE_COMMANDS = ("recordingIntent", "stopOne", "stopAll")
COMMANDS = CAPTURE_COMMANDS + ("bookmark",)
CAMERA_START_GRANTS = ["viewer"]
CAMERA_START_CAPABILITIES = ["record-local", "view-own-preview"]
GUEST_TYPES = {"hello", "join", "joinReveal", "readiness", "recordingStarted", "heartbeat", "still", "segmentEvent",
               "recordingStopped", "commandResult"} | set(COMMANDS)
HOST_TYPES = {"hello", "approvalRequest", "approve", "decline", "revoke", "roleAssigned", "grantChanged", "receipt"} \
    | set(COMMANDS)
PRE_APPROVAL_TYPES = {"hello", "join", "joinReveal"}
STILL_RECORDING = ("Starting", "Recording", "Paused", "Finalizing")


# ----- framing ------------------------------------------------------------------------------------

def frame_length(message: dict) -> int:
    return len(canonical_bytes(message))


def encode_frame(message: dict) -> bytes:
    """One frame: 4-byte big-endian length, then the canonical UTF-8 JSON (sorted keys, no whitespace)."""
    body = canonical_bytes(message)
    require(len(body) <= MAX_FRAME_BYTES, "frameTooLong", f"{len(body)} bytes")
    return len(body).to_bytes(4, "big") + body


def _no_duplicate_keys(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise Reject("duplicateKey", key)
        out[key] = value
    return out


def _refuse_float(text: str):
    raise Reject("malformedFrame", f"floating-point number {text}: the protocol uses integers")


def decode_frames(data: bytes) -> list:
    """Split a byte stream into messages. The receiver refuses a declared length over MAX_FRAME_BYTES before reading
    the body, a stream that ends inside a frame, and a body that is not one JSON object (duplicate keys and
    floating-point numbers included)."""
    out, i = [], 0
    while i < len(data):
        require(len(data) - i >= 4, "truncatedFrame", "the stream ends inside a length prefix")
        n = int.from_bytes(data[i:i + 4], "big")
        require(n <= MAX_FRAME_BYTES, "frameTooLong", f"declared {n} bytes")
        require(len(data) - i - 4 >= n, "truncatedFrame", "the stream ends inside a frame")
        raw = data[i + 4:i + 4 + n]
        try:
            value = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_keys, parse_float=_refuse_float)
        except Reject:
            raise
        except (ValueError, UnicodeDecodeError) as exc:
            raise Reject("malformedFrame", str(exc)) from None
        require(isinstance(value, dict), "malformedFrame", "a frame holds one JSON object")
        out.append(value)
        i += 4 + n
    return out


# ----- the QR join payload (spec/room jovra.room.invitation-payload/1, unchanged) -------------------------------------

def encode_qr(payload: dict) -> str:
    return QR_PREFIX + base64.urlsafe_b64encode(canonical_bytes(payload)).decode("ascii").rstrip("=")


def _b64url_bytes(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def decode_qr(text: str) -> dict:
    """Strict, so every port reads the same bytes: the prefix, the unpadded base64url alphabet, no duplicate keys, and
    JSON byte-identical to its canonical re-encoding."""
    require(isinstance(text, str) and text.startswith(QR_PREFIX), "notJovraRoomCode",
            "a JOVRA room QR is never a web URL or another scheme")
    body = text[len(QR_PREFIX):]
    require(bool(BASE64URL.match(body)) and len(body) % 4 != 1, "malformedPayload", "not unpadded base64url")
    try:
        raw = _b64url_bytes(body)
        payload = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except Reject:
        raise
    except (ValueError, UnicodeDecodeError, binascii.Error) as exc:
        raise Reject("malformedPayload", str(exc)) from None
    require(isinstance(payload, dict), "malformedPayload", "not an object")
    require(canonical_bytes(payload) == raw, "nonCanonicalPayload", "the QR JSON must be the canonical encoding")
    require(set(payload) - {"network"} == PAYLOAD_KEYS and payload.get("schemaVersion") == PAYLOAD_VERSION,
            "malformedPayload", "not a jovra.room.invitation-payload/1 object")
    return payload


def check_address(address: str, port) -> None:
    try:
        addr = ipaddress.ip_address(address)
    except ValueError:
        raise Reject("endpointNotAllowed", f"{address!r} is not an IP literal") from None
    require(any(addr.version == net.version and addr in net for net in LAN_NETWORKS), "endpointNotAllowed",
            f"{addr} is not a private or link-local LAN address")
    require(type(port) is int and 1024 <= port <= 65535, "endpointNotAllowed", f"port {port!r}")


def check_payload(payload: dict) -> None:
    """Joiner-side checks on a decoded payload, before anything is sent: a camera invitation never carries
    capture-controller, the secret is 32 bytes and the nonce 16, the host's own issuedAt..expiresAt is at most 10
    minutes, and every endpoint is the room's DNS-SD service or a LAN address."""
    require(payload["captureRole"] == "camera" and payload["commandRole"] != "capture-controller",
            "cameraCannotControl", "a camera invitation never carries capture control")
    for key, size, code in (("joinToken", SECRET_BYTES, "secretLength"), ("nonce", NONCE_BYTES, "malformedPayload")):
        value = payload[key]
        require(isinstance(value, str) and bool(BASE64URL.match(value)), code, f"{key} is not base64url")
        try:
            require(len(_b64url_bytes(value)) == size, code, f"{key} must be {size} bytes")
        except (ValueError, binascii.Error):
            raise Reject(code, f"{key} does not decode") from None
    life = (when(payload["expiresAt"]) - when(payload["issuedAt"])).total_seconds()
    require(0 < life <= MAX_INVITE_LIFETIME_S, "inviteLifetime", f"{life:.0f} s")
    require(isinstance(payload["endpoints"], list) and payload["endpoints"], "endpointNotAllowed", "no endpoint")
    for ep in payload["endpoints"]:
        if ep.get("kind") == "dnssd":
            require(ep.get("serviceType") == DNSSD_SERVICE, "endpointNotAllowed", "unexpected DNS-SD service type")
        else:
            require(ep.get("kind") == "lan", "endpointNotAllowed", f"endpoint kind {ep.get('kind')!r}")
            check_address(ep.get("address"), ep.get("port"))


def joiner_check(qr: str, observed_host_key: str) -> dict:
    """What a joining phone does with a scanned code before it sends a byte. Returns the payload or raises."""
    payload = decode_qr(qr)
    check_payload(payload)
    require(hmac.compare_digest(observed_host_key, payload["hostKeySha256"]), "hostKeyMismatch",
            "the TLS key differs from the key pinned by the QR")
    return payload


# ----- comparison codes ----------------------------------------------------------------------------

def six_digits(digest_hex: str) -> str:
    """The first 32 bits of a SHA-256 digest, mod 10^6, as six digits (spec/room's rule)."""
    return f"{int(digest_hex[:8], 16) % 1_000_000:06d}"


def guest_commitment(guest_key: str, guest_nonce: str) -> str:
    return hashlib.sha256(f"jovra-room-commit|{guest_key}|{guest_nonce}".encode("ascii")).hexdigest()


def join_proof(token: str, room_id: str, invite_id: str, nonce: str, guest_key: str, commitment: str) -> str:
    msg = f"{room_id}|{invite_id}|{nonce}|{guest_key}|{commitment}".encode("utf-8")
    return hmac.new(token.encode("ascii"), msg, hashlib.sha256).hexdigest()


def comparison_code(host_key: str, guest_key: str, qr_nonce: str, host_nonce: str, guest_nonce: str) -> str:
    """QR path, commit-then-reveal (ADR-0027 section 3 as amended): both keys, the QR nonce and both fresh nonces."""
    msg = f"jovra-room-sas|{host_key}|{guest_key}|{qr_nonce}|{host_nonce}|{guest_nonce}"
    return six_digits(hashlib.sha256(msg.encode("ascii")).hexdigest())


def channel_binding_code(exporter: str, host_key: str, guest_key: str) -> str:
    """Typed-code path: from the TLS exporter value both ends of one channel share, plus both keys. A man in the
    middle terminates two channels with two exporter values, so the two screens disagree."""
    msg = f"jovra-room-sas-tls|{exporter}|{host_key}|{guest_key}"
    return six_digits(hashlib.sha256(msg.encode("ascii")).hexdigest())


# ----- grants ------------------------------------------------------------------------------------

def grants_from_permissions(permissions: list) -> list:
    """jovra.camera-invite/1 roster permissions -> command grants: everyone is a viewer; host-controls is
    capture-controller (ADR-0027 section 6)."""
    return sorted({"viewer"} | ({"capture-controller"} if "host-controls" in permissions else set()))


def grant_permits(grant: str, command_type: str) -> bool:
    return command_type in GRANT_PERMITS.get(grant, set())


# ----- freshness (owned by the receiver) -------------------------------------------------------------

def freshness(age_ms) -> str:
    """age_ms on the receiver's own monotonic clock since it last accepted a frame from that device; None when it has
    heard nothing since its own process started. Fresh <= 5 s < Delayed <= 15 s < Unknown."""
    if age_ms is None:
        return "Unknown"
    require(type(age_ms) is int and age_ms >= 0, "negativeAge", f"{age_ms!r}")
    if age_ms <= FRESH_MS:
        return "Fresh"
    return "Delayed" if age_ms <= DELAYED_MS else "Unknown"


def contact_label(band: str, age_ms, state):
    """What a stale row says. Silence is never a stop: a row whose last report was a recording state says so."""
    if band in ("Local", "Fresh"):
        return None
    if age_ms is None:
        text = "No contact"
    else:
        s = age_ms // 1000
        text = f"No contact for {s // 60}:{s % 60:02d}"
    return text + (" · may still be recording" if state in STILL_RECORDING else "")


def is_ready(readiness: dict, planned_minutes: int) -> bool:
    return (readiness["cameraPermission"] == "granted" and readiness["presetSupported"]
            and readiness["minutesLeft"] >= planned_minutes
            and (readiness["batteryPct"] >= 20 or readiness["charging"])
            and readiness["thermal"] in ("nominal", "fair"))


def per_device_results(targets: list, outcomes: dict, now_ms: int, deadline_ms: int) -> list:
    """outcomes: deviceId -> ("Accepted"|"Failed"|"Denied", reason). A target with no outcome is Pending until the
    command's deadline on the host's clock, then Unknown (noAcknowledgement). Never a blanket result."""
    out = []
    for device in targets:
        if device in outcomes:
            result, reason = outcomes[device]
        elif now_ms > deadline_ms:
            result, reason = "Unknown", "noAcknowledgement"
        else:
            result, reason = "Pending", None
        out.append({"deviceId": device, "result": result, "reason": reason})
    return out


def idempotency_fingerprint(message: dict) -> str:
    """The command as the host hashes it: the body without expiry.ageAtSendMs (recomputed on every send)."""
    body = json.loads(json.dumps(message["body"]))
    body["expiry"].pop("ageAtSendMs", None)
    return hashlib.sha256(canonical_bytes({"type": message["type"], "body": body})).hexdigest()


# ----- the host state machine -----------------------------------------------------------------------

class Host:
    """The host's view, replayed step by step. Every inbound frame gets a verdict; outbound frames must be ones the
    host may send; observe steps must equal what the state gives."""

    def __init__(self, room: dict):
        self.room = room
        self.room_id = room["roomId"]
        self.epoch = room["hostEpoch"]
        self.host_device = room["hostDeviceId"]
        self.host_key = room["hostKeySha256"]
        self.hint = room["roomHint"]
        self.planned = room["plannedMinutes"]
        self.revision = room["eventRevision"]
        require(room["members"][0]["deviceId"] == self.host_device and room["members"][0]["keySha256"] == self.host_key
                and room["members"][0]["slotRole"] == "primary", "badRoom", "members[0] is the host, holding primary")
        self.members = {}        # deviceId -> member dict (slot, slotRole, grants, capabilities, key)
        self.key_device = {}     # bound peer key -> deviceId
        for m in room["members"]:
            require(m["deviceId"] not in self.members and m["keySha256"] not in self.key_device, "badRoom",
                    f"duplicate member {m['deviceId']}")
            require(m is room["members"][0] or m["slotRole"] == "camera", "badRoom", "only the host holds primary")
            require("viewer" in m["commandGrants"], "badRoom", "every member is a viewer")
            self.members[m["deviceId"]] = dict(m)
            self.key_device[m["keySha256"]] = m["deviceId"]
        self._check_slots()
        self.revoked_keys = set()
        self.invites = {}        # inviteId -> invite state
        self.pending = {}        # inviteId -> pending join
        self.seqs = {}           # (epoch, peer key or host) -> last seq
        self.rehello = set()     # bound keys that still owe a hello in this epoch
        self.heard = {}          # deviceId -> host ms of the last accepted frame (this host process)
        self.state = {}          # deviceId -> last reported capture state
        self.stopped_by_ack = set()
        self.ready = {}          # deviceId -> last readiness body
        self.thermal = {}
        self.stills = {}         # deviceId -> (frame atMs, sentMonoNs, captureMonoNs)
        self.acks = {}           # deviceId -> intentId of its last recordingStarted (None after a stop)
        self.intent = None       # current accepted recordingIntent id
        self.commands = {}       # (issuer, commandId) -> stored command
        self.receipted = set()
        self.reuse = {}          # (issuer, commandId) -> queued commandIdReuse receipts the host must send
        self.declined = {}       # inviteId -> the reason a decline must give
        self.now = 0

    # --- helpers ---
    def _check_slots(self) -> None:
        slots = [m["slot"] for m in self.members.values() if m.get("slot")]
        require(len(slots) == len(set(slots)), "badRoom", "two members hold one slot")

    def slot_members(self) -> list:
        return [d for d, m in self.members.items() if m.get("slot")]

    def _seq(self, peer: str, seq: int) -> None:
        key = (self.epoch, peer)
        require(seq > self.seqs.get(key, 0), "seqNotIncreasing", f"seq {seq} after {self.seqs.get(key, 0)}")
        self.seqs[key] = seq

    def _envelope(self, msg: dict) -> None:
        require(msg["roomId"] == self.room_id, "wrongRoom", f"room {msg['roomId']}")
        require(msg["hostEpoch"] >= self.epoch, "staleEpoch", f"epoch {msg['hostEpoch']} < {self.epoch}")
        require(msg["hostEpoch"] == self.epoch, "unknownEpoch", f"epoch {msg['hostEpoch']} > {self.epoch}")

    def _length(self, step: dict) -> None:
        require(step["length"] <= MAX_FRAME_BYTES, "frameTooLong", f"declared {step['length']} bytes")
        require(step["length"] == frame_length(step["message"]), "frameLengthMismatch",
                f"declared {step['length']}, body {frame_length(step['message'])}")

    def _invite_open(self, invite: dict) -> None:
        require(not invite["void"], "inviteRevoked", f"invitation {invite['inviteId']} is void ({invite['void']})")
        require(not invite["used"], "inviteUsed", f"invitation {invite['inviteId']} was already used")
        require(self.now <= invite["deadline"], "inviteExpired", f"invitation {invite['inviteId']} expired")

    # --- steps ---
    def step(self, step: dict) -> None:
        require(step["atMs"] >= self.now, "stepsOutOfOrder", f"atMs {step['atMs']} before {self.now}")
        self.now = step["atMs"]
        getattr(self, "_" + step["step"])(step)

    def _invite(self, step: dict) -> None:
        payload = decode_qr(step["qr"])
        check_payload(payload)
        require(payload["sessionId"] == self.room_id, "payloadMismatch", "the QR names another room")
        require(payload["hostEpoch"] == self.epoch, "payloadMismatch", "the QR names another host epoch")
        require(payload["hostKeySha256"] == self.host_key, "payloadMismatch", "the QR pins another host key")
        require(payload["inviteId"] == step["inviteId"] and payload["displayCode"] == step["displayCode"],
                "payloadMismatch", "the QR names another invitation")
        require(payload["commandRole"] == "viewer", "payloadMismatch", "a camera code grants viewer only")
        life = (when(payload["expiresAt"]) - when(payload["issuedAt"])).total_seconds()
        require(life == step["lifetimeS"], "inviteLifetime", "lifetimeS differs from the QR's issuedAt..expiresAt")
        for ep in payload["endpoints"]:
            if ep["kind"] == "dnssd":
                require(ep.get("instanceName") == self.hint, "roomHintMismatch",
                        "the DNS-SD instance is the room's opaque hint")
        require(step["inviteId"] not in self.invites, "duplicateInvite", step["inviteId"])
        require(step["slot"] not in [self.members[d]["slot"] for d in self.slot_members()], "slotOccupied",
                f"{step['slot']} already has a phone")
        for other in self.invites.values():
            if not other["void"] and not other["used"] and self.now <= other["deadline"]:
                require(other["displayCode"] != step["displayCode"], "displayCodeInUse", step["displayCode"])
                if other["slot"] == step["slot"]:
                    other["void"] = "superseded"   # a new code for a slot voids the old one
        self.invites[step["inviteId"]] = {
            "inviteId": step["inviteId"], "slot": step["slot"], "displayCode": step["displayCode"],
            "deadline": self.now + 1000 * step["lifetimeS"], "token": payload["joinToken"], "nonce": payload["nonce"],
            "void": None, "used": False, "attempts": 0, "device": None}

    def _in(self, step: dict) -> None:
        try:
            self._receive(step)
            verdict = {"accepted": True}
        except Reject as exc:
            verdict = {"accepted": False, "code": exc.code}
            got = exc
        declared = step["verdict"]
        if declared["accepted"] and not verdict["accepted"]:
            raise got
        require(declared["accepted"] or not verdict["accepted"], "unexpectedAccept",
                f"the host accepted a frame it declared refused ({declared.get('code')})")
        require(declared == verdict, "verdictMismatch",
                f"refused with {verdict.get('code')}, declared {declared.get('code')}")

    def _receive(self, step: dict) -> None:
        msg, peer = step["message"], step["peerKeySha256"]
        self._length(step)
        require(peer not in self.revoked_keys, "revokedPeer", "a revoked phone's connection is closed")
        require(peer != self.host_key, "senderNotChannelPeer", "the host's own key on an inbound channel")
        self._envelope(msg)
        bound = self.key_device.get(peer)
        if bound is None:
            require(msg["deviceId"] not in self.members, "senderNotChannelPeer",
                    f"an unapproved channel claims member {msg['deviceId']}")
            require(msg["type"] in PRE_APPROVAL_TYPES, "notApproved", f"{msg['type']} before approval")
        else:
            require(msg["deviceId"] == bound, "senderNotChannelPeer", f"channel of {bound} claims {msg['deviceId']}")
            require(peer not in self.rehello or msg["type"] == "hello", "reauthRequired",
                    "after a new host epoch a member says hello first")
        require(msg["type"] in GUEST_TYPES, "hostOnlyMessage", f"{msg['type']} comes only from the host")
        self._seq(peer, msg["seq"])
        if msg["type"] in COMMANDS:
            self._command(msg, step["transitMs"], step)
        else:
            getattr(self, "_in_" + msg["type"])(msg, step)
        if bound is not None:
            self.heard[bound] = self.now

    def _in_hello(self, msg, step) -> None:
        require(msg["body"]["role"] == "guest" and msg["body"]["roomHint"] is None, "helloRoleMismatch",
                "a guest hello")
        self.rehello.discard(step["peerKeySha256"])

    def _in_join(self, msg, step) -> None:
        body, peer = msg["body"], step["peerKeySha256"]
        if body["path"] == "qr":
            invite = self.invites.get(body["inviteId"])
        else:   # a typed code finds the latest invitation shown with it; the code itself authenticates nothing
            matches = [i for i in self.invites.values() if i["displayCode"] == body["displayCode"]]
            invite = matches[-1] if matches else None
        require(invite is not None, "unknownInvite", "no such invitation")
        self._invite_open(invite)
        require(invite["slot"] not in [self.members[d]["slot"] for d in self.slot_members()], "slotFull",
                f"{invite['slot']} already has a phone")
        require(len(self.slot_members()) < MAX_CAMERAS, "roomFull", "six phones already")
        current = self.pending.get(invite["inviteId"])
        require(current is None or current["peer"] == peer, "joinInProgress", "another phone is waiting on this code")
        require(peer not in self.key_device and msg["deviceId"] not in self.members, "alreadyMember",
                "no second membership")
        require(body["guestKeySha256"] == peer, "guestKeyNotChannelKey",
                "the join names a key other than the channel's")
        if body["path"] == "qr":
            require(body["observedHostKeySha256"] == self.host_key, "hostKeyMismatch", "the guest saw another host key")
            want = join_proof(invite["token"], self.room_id, invite["inviteId"], invite["nonce"], peer,
                              body["guestCommitment"])
            require(hmac.compare_digest(want, body["proof"]), "badProof", "the join proof does not match the QR secret")
        else:
            require(body["channelBinding"] == "tls-exporter" and step["exporter"] is not None,
                    "typedCodeNeedsChannelBinding", "a typed code without a channel-bound comparison code is refused")
        self.pending[invite["inviteId"]] = {
            "peer": peer, "device": msg["deviceId"], "path": body["path"], "commitment": body["guestCommitment"],
            "exporter": step["exporter"], "hostNonce": None, "guestNonce": None, "allowed": False}

    def _in_joinReveal(self, msg, step) -> None:
        pend = self.pending.get(msg["body"]["inviteId"])
        require(pend is not None and pend["peer"] == step["peerKeySha256"], "noPendingJoin", "no join to reveal for")
        require(pend["path"] == "qr" and pend["hostNonce"] is not None, "revealBeforeChallenge",
                "the guest reveals only after the host's nonce")
        require(pend["guestNonce"] is None, "duplicateReveal", "one reveal per join")
        if guest_commitment(pend["peer"], msg["body"]["guestNonce"]) != pend["commitment"]:
            self._failed_attempt(msg["body"]["inviteId"])
            raise Reject("commitmentMismatch", "the revealed nonce does not open the commitment")
        pend["guestNonce"] = msg["body"]["guestNonce"]

    def _failed_attempt(self, invite_id: str) -> None:
        invite = self.invites[invite_id]
        invite["attempts"] += 1
        self.pending.pop(invite_id, None)
        if invite["attempts"] >= MAX_JOIN_ATTEMPTS:
            invite["void"] = "attemptsExhausted"

    def _in_readiness(self, msg, step) -> None:
        self.ready[msg["deviceId"]] = msg["body"]
        self.thermal[msg["deviceId"]] = msg["body"]["thermal"]

    def _in_heartbeat(self, msg, step) -> None:
        self.state[msg["deviceId"]] = msg["body"]["captureState"]
        self.thermal[msg["deviceId"]] = msg["body"]["thermal"]
        if msg["body"]["captureState"] != "Stopped":
            self.stopped_by_ack.discard(msg["deviceId"])
        else:
            self.stopped_by_ack.add(msg["deviceId"])

    def _in_still(self, msg, step) -> None:
        body, device = msg["body"], msg["deviceId"]
        require(self.thermal.get(device) in ("nominal", "fair"), "stillWhileHot",
                "stills only at thermal nominal or fair")
        require(body["captureMonoNs"] <= msg["sentMonoNs"], "stillFromFuture", "captured after it was sent")
        prev = self.stills.get(device)
        if prev is not None:
            gap = STILL_GAP_FRAMING_MS if body["framing"] else STILL_GAP_MS
            require(body["captureMonoNs"] - prev[2] >= gap * NS_PER_MS, "stillCadence",
                    f"stills at least {gap} ms apart")
        self.stills[device] = (self.now, msg["sentMonoNs"], body["captureMonoNs"])

    def _in_recordingStarted(self, msg, step) -> None:
        self._started(msg)

    def _started(self, msg) -> None:
        intent = msg["body"]["intentId"]
        if intent is not None:
            require(any(c["accepted"] and c["message"]["type"] == "recordingIntent"
                        and c["message"]["body"]["intentId"] == intent for c in self.commands.values()),
                    "unknownIntent", f"no accepted intent {intent}")
        device = msg["deviceId"]
        self.state[device] = "Recording"
        self.stopped_by_ack.discard(device)
        self.acks[device] = intent
        for c in self.commands.values():
            if (c["accepted"] and c["message"]["type"] == "recordingIntent" and intent is not None
                    and c["message"]["body"]["intentId"] == intent and device in c["targets"]):
                c["outcomes"].setdefault(device, ("Accepted", None))

    def _in_segmentEvent(self, msg, step) -> None:
        require(self.state.get(msg["deviceId"]) in STILL_RECORDING, "segmentWithoutRecording",
                "segment events come from a recording camera")

    def _in_recordingStopped(self, msg, step) -> None:
        self._stopped(msg)

    def _stopped(self, msg) -> None:
        device = msg["deviceId"]
        require(self.state.get(device) in STILL_RECORDING, "stopWithoutRecording", "only a recording camera stops")
        self.state[device] = "Stopped"
        self.stopped_by_ack.add(device)
        self.acks[device] = None
        cid = msg["body"]["commandId"]
        if cid is not None:
            cmd = self._relayed(cid, device)
            cmd["outcomes"].setdefault(device, ("Accepted", None))

    def _relayed(self, command_id: str, device: str) -> dict:
        for c in self.commands.values():
            if c["message"]["body"]["commandId"] == command_id and c["accepted"] and device in c["targets"]:
                return c
        raise Reject("unknownCommand", f"{command_id} was never sent to {device}")

    def _in_commandResult(self, msg, step) -> None:
        cmd = self._relayed(msg["body"]["commandId"], msg["deviceId"])
        cmd["outcomes"].setdefault(msg["deviceId"], (msg["body"]["result"], msg["body"]["reason"]))

    # --- commands ---
    def _command(self, msg: dict, transit_ms, step) -> None:
        """Order: issuer binding, idempotency (scoped to the issuer), grant held, grant permits, expiry, targets,
        revision. Every outcome is answered by a receipt the transcript must show."""
        body = msg["body"]
        issuer = msg["deviceId"]
        require(body["issuer"]["deviceId"] == issuer, "issuerNotSender", "the issuer is the authenticated sender")
        key = (issuer, body["commandId"])
        fp = idempotency_fingerprint(msg)
        stored = self.commands.get(key)
        if stored is not None:
            if stored["fingerprint"] == fp:
                stored["retries"] += 1
                return
            # the stored receipt stands; this attempt is refused and logged as a security event
            self.reuse.setdefault(key, []).append({
                "commandId": key[1], "issuerDeviceId": issuer, "status": "Rejected", "reason": "commandIdReuse",
                "securityEvent": True, "eventRevision": self.revision, "perDevice": []})
            return
        rec = {"message": msg, "fingerprint": fp, "accepted": False, "targets": [], "outcomes": {}, "at": self.now,
               "deadline": self.now, "status": None, "reason": None, "security": False, "retries": 0,
               "revision": self.revision, "rejectOnly": None}
        self.commands[key] = rec
        grants = self.members[issuer]["commandGrants"]
        typ = msg["type"]

        def finish(status, reason, security=False):
            rec.update(status=status, reason=reason, security=security, revision=self.revision)

        if body["claimedGrant"] not in grants:
            return finish("Rejected", "grantNotHeld", True)
        if not grant_permits(body["claimedGrant"], typ):
            return finish("Rejected", "grantNotPermitted")
        ttl, age = body["expiry"]["ttlMs"], body["expiry"]["ageAtSendMs"]
        if typ in CAPTURE_COMMANDS:
            if ttl > CAPTURE_TTL_MAX_MS:
                return finish("Rejected", "ttlTooLong")
            if transit_ms is None:
                return finish("Expired", "unboundedTransit")
        if transit_ms is not None and age + transit_ms > ttl:
            return finish("Expired", "commandExpired")
        targets = body["target"]["deviceIds"]
        enrolled = self.slot_members()
        if typ == "bookmark":
            if body["target"]["scope"] != "room" or targets:
                return finish("Rejected", "targetScope")
        else:
            if not targets:
                return finish("Rejected", "noTargets")
            if any(t not in enrolled for t in targets):
                return finish("Rejected", "unknownTarget")
            if typ == "stopOne" and (body["target"]["scope"] != "one" or len(targets) != 1):
                return finish("Rejected", "targetScope")
            if typ == "stopAll":
                if body["target"]["scope"] != "all" or set(targets) != set(enrolled):
                    return finish("Rejected", "stopAllTargetsIncomplete")
                if body["targetLabel"] != f"Stop all cameras ({len(targets)})":
                    return finish("Rejected", "targetLabelMismatch")
            if body["baseEventRevision"] != self.revision:
                return finish("Conflicted", "baseRevisionStale")
            self.revision += 1
        rec.update(accepted=True, targets=list(targets), deadline=self.now + ttl - age - (transit_ms or 0))
        if typ == "recordingIntent":
            self.intent = body["intentId"]
        finish("Accepted", None)

    def receipt_for(self, key) -> dict:
        rec = self.commands[key]
        per = per_device_results(rec["targets"], rec["outcomes"], self.now, rec["deadline"]) if rec["accepted"] else []
        for item in per:
            if item["result"] != "Pending":
                rec["outcomes"].setdefault(item["deviceId"], (item["result"], item["reason"]))   # final never changes
        return {"commandId": key[1], "issuerDeviceId": key[0], "status": rec["status"], "reason": rec["reason"],
                "securityEvent": rec["security"], "eventRevision": rec["revision"], "perDevice": per}

    # --- local (the host's own phone) ---
    def _local(self, step: dict) -> None:
        msg = step["message"]
        require(msg["deviceId"] == self.host_device, "localNotHost", "a local step is the host's own")
        self._envelope(msg)
        self._seq("host", msg["seq"])
        typ = msg["type"]
        if typ in COMMANDS:
            return self._command(msg, 0, step)
        handler = {"recordingStarted": self._started, "recordingStopped": self._stopped}.get(typ)
        if handler is not None:
            return handler(msg)
        if typ == "heartbeat":
            return self._in_heartbeat(msg, step)
        if typ == "readiness":
            return self._in_readiness(msg, step)
        if typ == "receipt" and msg["body"]["issuerDeviceId"] == self.host_device:
            return self._check_receipt(msg, None)
        raise Reject("localNotAllowed", f"{typ} is not a host-local step")

    # --- out ---
    def _out(self, step: dict) -> None:
        msg = step["message"]
        self._length(step)
        require(msg["deviceId"] == self.host_device, "outNotHost", "outbound frames come from the host")
        self._envelope(msg)
        require(msg["type"] in HOST_TYPES, "guestOnlyMessage", f"the host never sends {msg['type']}")
        self._seq("host", msg["seq"])
        getattr(self, "_out_" + (msg["type"] if msg["type"] not in COMMANDS else "relay"))(msg, step)

    def _out_hello(self, msg, step) -> None:
        require(msg["body"]["role"] == "host" and msg["body"]["roomHint"] == self.hint, "helloRoleMismatch",
                "the host's hello carries the room hint")

    def _out_approvalRequest(self, msg, step) -> None:
        pend = self.pending.get(msg["body"]["inviteId"])
        require(pend is not None and step["toPeerKeys"] == [pend["peer"]], "noPendingJoin", "no join waits here")
        if pend["path"] == "qr":
            require(msg["body"]["hostNonce"] is not None, "hostNonceMissing", "the QR path needs the host nonce")
            pend["hostNonce"] = msg["body"]["hostNonce"]
        else:
            require(msg["body"]["hostNonce"] is None, "hostNonceMissing", "the typed path uses the channel binding")
            pend["hostNonce"] = ""

    def _comparison(self, step: dict) -> None:
        invite_id = step["inviteId"]
        pend = self.pending.get(invite_id)
        require(pend is not None and pend["hostNonce"] is not None, "noPendingJoin", "nothing to compare")
        invite = self.invites[invite_id]
        view = step["guestView"] or {"hostKeySha256": self.host_key, "guestKeySha256": pend["peer"],
                                     "exporter": pend["exporter"]}
        if pend["path"] == "qr":
            require(pend["guestNonce"] is not None, "comparisonBeforeReveal", "both nonces come first")
            host_code = comparison_code(self.host_key, pend["peer"], invite["nonce"], pend["hostNonce"],
                                        pend["guestNonce"])
            guest_code = comparison_code(view["hostKeySha256"], view["guestKeySha256"], invite["nonce"],
                                         pend["hostNonce"], pend["guestNonce"])
        else:
            host_code = channel_binding_code(pend["exporter"], self.host_key, pend["peer"])
            require(view["exporter"] is not None, "typedCodeNeedsChannelBinding",
                    "the guest's channel offers no binding")
            guest_code = channel_binding_code(view["exporter"], view["hostKeySha256"], view["guestKeySha256"])
        require(step["hostScreenCode"] == host_code, "comparisonCodeWrong", "the host's screen shows another code")
        require(step["guestScreenCode"] == guest_code, "comparisonCodeWrong", "the guest's screen shows another code")
        if step["decision"] == "allow":
            require(host_code == guest_code, "comparisonCodeMismatch", "the host allowed codes that differ")
            pend["allowed"] = True
        else:
            self._failed_attempt(invite_id)
            if invite["void"] == "attemptsExhausted":
                self.declined[invite_id] = "attemptsExhausted"
            else:
                self.declined[invite_id] = "codesDidNotMatch" if host_code != guest_code else "hostDeclined"

    def _out_approve(self, msg, step) -> None:
        body = msg["body"]
        pend = self.pending.get(body["inviteId"])
        require(pend is not None and pend["allowed"], "approvalWithoutComparison",
                "approval needs both screens' codes compared and Allow tapped")
        require(body["guestKeySha256"] == pend["peer"] and body["deviceId"] == pend["device"]
                and step["toPeerKeys"] == [pend["peer"]], "approvalKeyMismatch", "the approval names another phone")
        require(body["basis"] == ("comparisonCode" if pend["path"] == "qr" else "channelBindingCode"),
                "approvalBasisMismatch", "the basis is the path's comparison code")
        invite = self.invites[body["inviteId"]]
        self._invite_open(invite)
        invite["used"], invite["device"] = True, pend["device"]
        del self.pending[body["inviteId"]]
        self.key_device[pend["peer"]] = pend["device"]
        self.members[pend["device"]] = {"deviceId": pend["device"], "keySha256": pend["peer"], "slot": None,
                                        "slotRole": None, "commandGrants": ["viewer"], "capabilities": [],
                                        "invite": invite["inviteId"]}
        self.heard[pend["device"]] = self.now

    def _out_decline(self, msg, step) -> None:
        reason = self.declined.pop(msg["body"]["inviteId"], None)
        require(reason is not None, "declineWithoutComparison", "a decline follows a declined comparison")
        require(msg["body"]["reason"] == reason, "declineReasonMismatch", f"expected {reason}")

    def _out_roleAssigned(self, msg, step) -> None:
        body = msg["body"]
        member = self.members.get(body["deviceId"])
        require(member is not None, "roleBeforeApproval", f"{body['deviceId']} is not an approved member")
        require(step["toPeerKeys"] == [member["keySha256"]], "roleToOtherPhone", "sent to the member it names")
        others = [self.members[d]["slot"] for d in self.slot_members() if d != body["deviceId"]]
        require(body["slot"] not in others, "slotOccupied", f"{body['slot']} already has a phone")
        require(body["slotRole"] == ("primary" if body["deviceId"] == self.host_device else "camera"),
                "primaryNotHost", "only the host records the primary slot")
        if member["slot"] is None:
            require(body["slot"] == self.invites[member["invite"]]["slot"], "slotMismatch",
                    "the first slot is the invitation's slot")
            require(body["commandGrants"] == CAMERA_START_GRANTS and body["capabilities"] == CAMERA_START_CAPABILITIES,
                    "cameraGrantExceeded", "a camera guest starts with record-local and view-own-preview only")
        else:
            require(sorted(body["commandGrants"]) == sorted(member["commandGrants"])
                    and sorted(body["capabilities"]) == sorted(member["capabilities"]), "grantMismatch",
                    "grants change only through grantChanged")
        member.update(slot=body["slot"], slotRole=body["slotRole"], commandGrants=list(body["commandGrants"]),
                      capabilities=list(body["capabilities"]))

    def _out_grantChanged(self, msg, step) -> None:
        body = msg["body"]
        member = self.members.get(body["deviceId"])
        require(member is not None and member["slot"] is not None, "roleBeforeApproval", "not a member with a slot")
        require("viewer" in body["commandGrants"], "viewerRequired", "everyone keeps viewer")
        member["commandGrants"] = list(body["commandGrants"])

    def _out_revoke(self, msg, step) -> None:
        body = msg["body"]
        if body["deviceId"] is not None:
            member = self.members.get(body["deviceId"])
            require(member is not None and body["deviceId"] != self.host_device and body["reason"] == "hostRemoved",
                    "revokeTarget", "only a guest member is removed")
            self.revoked_keys.add(member["keySha256"])
            self.key_device.pop(member["keySha256"], None)
            if member.get("invite"):
                self.invites[member["invite"]]["void"] = "revoked"
            del self.members[body["deviceId"]]
            for d in (self.heard, self.state, self.ready, self.stills, self.acks, self.thermal):
                d.pop(body["deviceId"], None)
            self.stopped_by_ack.discard(body["deviceId"])
        else:
            invite = self.invites.get(body["inviteId"])
            require(invite is not None and body["reason"] == "codeWithdrawn", "revokeTarget", "no such code")
            invite["void"] = "revoked"
            pend = self.pending.pop(body["inviteId"], None)
            if pend is not None:
                self.revoked_keys.add(pend["peer"])

    def _out_receipt(self, msg, step) -> None:
        issuer = msg["body"]["issuerDeviceId"]
        require(issuer != self.host_device and issuer in self.members, "receiptMismatch",
                "a receipt goes over the network only to a guest issuer (the host's own are local)")
        require(step["toPeerKeys"] == [self.members[issuer]["keySha256"]], "receiptMismatch",
                "a receipt goes to its issuer")
        self._check_receipt(msg, step)

    def _check_receipt(self, msg, step) -> None:
        body = msg["body"]
        key = (body["issuerDeviceId"], body["commandId"])
        require(key in self.commands, "receiptMismatch", "a receipt for a command the host never processed")
        queued = self.reuse.get(key)
        want = queued.pop(0) if queued else self.receipt_for(key)
        require(body == want, "receiptMismatch", f"host sent {canonical_bytes(body).decode()}, rules give "
                                                 f"{canonical_bytes(want).decode()}")
        self.receipted.add(key)

    def _out_relay(self, msg, step) -> None:
        key = (msg["body"]["issuer"]["deviceId"], msg["body"]["commandId"])
        rec = self.commands.get(key)
        require(rec is not None and rec["accepted"] and rec["message"]["body"] == msg["body"], "relayNotAccepted",
                "only an accepted command is relayed, unchanged")
        keys = sorted(self.members[t]["keySha256"] for t in rec["targets"]
                      if t != self.host_device and t in self.members)
        require(sorted(step["toPeerKeys"]) == keys, "relayNotTarget", "relayed to exactly its targets")

    # --- restart ---
    def _restart(self, step: dict) -> None:
        require(step["newHostEpoch"] > self.epoch, "epochNotIncreasing", "a new host epoch is higher")
        for invite in self.invites.values():
            if not invite["used"] and not invite["void"]:
                invite["void"] = "hostEpochChanged"
        self.pending.clear()
        for key, rec in self.commands.items():
            if rec["accepted"]:
                for t in rec["targets"]:
                    rec["outcomes"].setdefault(t, ("Unknown", "hostEpochChanged"))   # never replayed
        self.epoch = step["newHostEpoch"]
        self.heard.clear()   # the receiver restarted: everything is Unknown until heard again
        if step["kind"] == "hostRestart":
            require(step["newHostKeySha256"] == self.host_key and step["newHostDeviceId"] == self.host_device,
                    "hostChangedOnRestart", "a restart keeps the host phone and key")
            self.rehello = {m["keySha256"] for d, m in self.members.items() if d != self.host_device}
        else:
            require(step["newHostKeySha256"] != self.host_key, "transferKeepsKey", "a transfer is another phone")
            self.host_key, self.host_device = step["newHostKeySha256"], step["newHostDeviceId"]
            new = self.members.get(self.host_device, {"slot": "near-baseline"})
            self.members = {self.host_device: {"deviceId": self.host_device, "keySha256": self.host_key,
                                               "slot": new["slot"], "slotRole": "primary",
                                               "commandGrants": ["capture-controller", "scorer", "viewer"],
                                               "capabilities": ["record-local", "upload-own-source", "view-own-preview"]}}
            self.key_device = {self.host_key: self.host_device}
            self.rehello = set()

    # --- observe ---
    def display(self) -> dict:
        devices = []
        for d in self.slot_members():
            m = self.members[d]
            state = self.state.get(d)
            if d == self.host_device:
                band, age = "Local", None
            else:
                age = self.now - self.heard[d] if d in self.heard else None
                band = freshness(age)
            ready = is_ready(self.ready[d], self.planned) if d in self.ready else None
            still = self.stills.get(d)
            still_age = (self.now - still[0]) + (still[1] - still[2]) // NS_PER_MS if still else None
            devices.append({"deviceId": d, "slot": m["slot"], "freshness": band,
                            "contactAgeMs": age if band in ("Delayed", "Unknown") else None, "state": state,
                            "label": contact_label(band, age, state), "ready": ready, "stillAgeMs": still_age})
        on = None
        if self.intent is not None:
            n = sum(1 for row in devices if row["freshness"] in ("Local", "Fresh") and row["state"] == "Recording"
                    and self.acks.get(row["deviceId"]) == self.intent)
            on = {"n": n, "m": len(devices)}
        return {"recordingOn": on, "devices": devices}

    def _observe(self, step: dict) -> None:
        want, shown = self.display(), step["display"]
        rows = {r["deviceId"]: r for r in shown["devices"]}
        require(sorted(rows) == sorted(r["deviceId"] for r in want["devices"]) and len(rows) == len(shown["devices"]),
                "displayRosterMismatch", "the screen lists other cameras than the roster")
        for row in want["devices"]:
            got = rows[row["deviceId"]]
            if got["state"] == "Stopped" and row["state"] != "Stopped":
                raise Reject("stopInferredFromSilence", f"{row['deviceId']} never reported a stop")
            for field, code in (("slot", "displayRosterMismatch"), ("freshness", "freshnessMismatch"),
                                ("contactAgeMs", "contactAgeMismatch"), ("state", "stateMismatch"),
                                ("label", "labelMismatch"), ("ready", "readyMismatch"),
                                ("stillAgeMs", "stillAgeMismatch")):
                require(got[field] == row[field], code, f"{row['deviceId']} {field}: shown {got[field]!r}, "
                                                        f"rules give {row[field]!r}")
        require(shown["recordingOn"] == want["recordingOn"], "recordingCountMismatch",
                f"shown {shown['recordingOn']}, acknowledgements give {want['recordingOn']}")

    def finish(self) -> None:
        for key in self.commands:
            require(key in self.receipted, "missingReceipt", f"command {key[1]} was never answered")


def check_transcript(doc: dict) -> dict:
    """Replay one jovra.room-transcript/1 record. Returns a summary (frames, refusals, roster, receipts)."""
    require(doc["schemaVersion"] == TRANSCRIPT, "notATranscript", doc["schemaVersion"])
    host = Host(doc["room"])
    refused = []
    for i, step in enumerate(doc["steps"]):
        try:
            host.step(step)
        except Reject as exc:
            raise Reject(exc.code, f"step {i}: {exc.message}") from None
        if step["step"] == "in" and not step["verdict"]["accepted"]:
            refused.append(step["verdict"]["code"])
    host.finish()
    return {"steps": len(doc["steps"]), "refused": refused, "members": sorted(host.slot_members()),
            "epoch": host.epoch, "display": host.display(), "host": host}


def step_outcome(doc: dict, index: int) -> dict:
    """Replay up to and including step `index` and report what the host concluded there: the verdict of an inbound
    frame, the receipt for a command, or the display at an observe step."""
    host = Host(doc["room"])
    for i, step in enumerate(doc["steps"][: index + 1]):
        host.step(step)
    step = doc["steps"][index]
    if step["step"] == "in":
        return {"verdict": step["verdict"]}
    if step["step"] in ("out", "local") and step["message"]["type"] == "receipt":
        return {"receipt": step["message"]["body"]}
    if step["step"] == "observe":
        return {"display": host.display()}
    return {}
