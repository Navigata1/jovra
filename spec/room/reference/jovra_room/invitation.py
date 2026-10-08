"""Invitations: QR payload encoding, joiner-side checks, host-side single-use validation with a commit-then-reveal
verification code and host approval.

The QR carries a 128-bit (or larger) join token and a nonce; the guest proves possession with an HMAC over
sessionId|inviteId|nonce|guestKeySha256|guestCommitment instead of sending the token. The host stores only the token's
SHA-256 in its record and keeps the token in its secure store (here: a dict passed in).

Verification code (a short authentication string, as in Bluetooth numeric comparison / ZRTP): the guest commits to
H(guestKey, guestNonce) in its join request; only then does the host send a fresh random hostNonce; only then does the
guest reveal guestNonce. The six digits mix both keys and both nonces, so a holder of a forwarded QR can no longer
grind guest keys offline for a matching code: every try costs one online join attempt with a one-in-a-million chance,
and an invitation is revoked after MAX_JOIN_ATTEMPTS declined or failed attempts by token holders.

A six-character display code is lookup data: it finds an invitation for host approval and never authenticates anyone.
Lookups are throttled per requesting source in a sliding window. Host transfer revokes every open invitation. A device
that is already a member cannot join again under a second invitation (no implicit role upgrade in v1).
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import ipaddress
import json
import re

from .core import Reject, canonical, parse_time

QR_PREFIX = "jovra-room:1:"
MAX_LIFETIME_S = 600
LOOKUP_MAX_MISSES = 5
LOOKUP_WINDOW_S = 600
MAX_JOIN_ATTEMPTS = 3
DNSSD_SERVICE = "_jovra-room._tcp"
BASE64URL = re.compile(r"\A[A-Za-z0-9_-]*\Z")
# Explicit allow-list (not ipaddress.is_private, whose meaning varies by Python version and includes documentation
# ranges): RFC 1918, IPv4 link-local, IPv6 unique-local and IPv6 link-local.
LAN_NETWORKS = tuple(ipaddress.ip_network(n) for n in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16", "fc00::/7", "fe80::/10"))

CAPTURE_GRANTS = {"camera": ["record-local", "upload-own-source", "view-own-preview"], "none": []}
COMMAND_GRANTS = {
    "viewer": [],
    "marker": ["command:MarkForReview"],
    "scorer": ["command:MarkForReview", "command:PointWon", "command:Undo"],
    "capture-controller": ["command:MarkForReview", "command:StartRequest", "command:StopAllRequest", "command:StopOne"],
}


def grants_for(capture_role: str, command_role: str) -> list:
    return sorted(set(["view-room-status"] + CAPTURE_GRANTS[capture_role] + COMMAND_GRANTS[command_role]))


def encode_qr(payload: dict) -> str:
    raw = base64.urlsafe_b64encode(canonical(payload).encode("utf-8")).decode("ascii").rstrip("=")
    return QR_PREFIX + raw


def _no_duplicate_keys(pairs):
    out = {}
    for k, v in pairs:
        if k in out:
            raise Reject("duplicateKey", k)
        out[k] = v
    return out


def decode_qr(text: str) -> dict:
    """Strict decoding every port must reproduce: unpadded base64url alphabet only, no duplicate JSON keys, and the
    payload must be byte-identical to its canonical re-encoding (so two parsers can never disagree on a field)."""
    if not text.startswith(QR_PREFIX):
        raise Reject("notJovraRoomCode", "a JOVRA room QR is never a web URL or another scheme")
    body = text[len(QR_PREFIX):]
    if not BASE64URL.match(body) or len(body) % 4 == 1:
        raise Reject("malformedPayload", "not unpadded base64url")
    try:
        raw = base64.urlsafe_b64decode(body + "=" * (-len(body) % 4))
        payload = json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except (ValueError, UnicodeDecodeError, binascii.Error) as exc:
        raise Reject("malformedPayload", str(exc)) from None
    if not isinstance(payload, dict):
        raise Reject("malformedPayload", "not an object")
    if canonical(payload).encode("utf-8") != raw:
        raise Reject("nonCanonicalPayload", "the QR JSON must be the canonical encoding")
    return payload


def _check_address(address: str, port: int) -> None:
    try:
        addr = ipaddress.ip_address(address)
    except ValueError:
        raise Reject("endpointNotAllowed", "not an IP literal") from None
    if not any(addr.version == net.version and addr in net for net in LAN_NETWORKS):
        raise Reject("endpointNotAllowed", f"{addr} is not a private or link-local LAN address")
    if not isinstance(port, int) or isinstance(port, bool) or not 1024 <= port <= 65535:
        raise Reject("endpointNotAllowed", "port")


def check_endpoint(ep: dict) -> None:
    if ep.get("kind") == "dnssd":
        if ep.get("serviceType") != DNSSD_SERVICE:
            raise Reject("endpointNotAllowed", "unexpected DNS-SD service type")
        return  # the address is checked after resolution: check_resolved_endpoint
    if ep.get("kind") != "lan":
        raise Reject("endpointNotAllowed", f"kind {ep.get('kind')!r}")
    _check_address(ep["address"], ep["port"])


def check_resolved_endpoint(address: str, port: int) -> None:
    """A DNS-SD instance resolves to an address and port; the same LAN allow-list and port rule apply before
    connecting. The TLS pin (hostKeySha256) still authenticates the host; the allow-list limits where a client connects."""
    _check_address(address, port)


def check_lifetime(issued_at: str, expires_at: str) -> None:
    life = (parse_time(expires_at) - parse_time(issued_at)).total_seconds()
    if life <= 0 or life > MAX_LIFETIME_S:
        raise Reject("inviteLifetime", f"{life:.0f} s")


def check_roles(capture_role: str, command_role: str) -> None:
    if capture_role == "camera" and command_role == "capture-controller":
        raise Reject("cameraCannotControl", "a camera invitation never carries host/capture controls (Studio rule)")


def joiner_verify(payload: dict, observed_host_key: str) -> str:
    """Joiner-side checks before sending anything: roles, lifetime (issuedAt..expiresAt, both from the host's clock),
    endpoints, and the pinned host key observed on the TLS channel. The joiner never compares its own wall clock with
    the host's timestamps: expiry is decided by the host alone (wall clocks are never compared across devices)."""
    try:
        check_roles(payload["captureRole"], payload["commandRole"])
        check_lifetime(payload["issuedAt"], payload["expiresAt"])
        for ep in payload["endpoints"]:
            check_endpoint(ep)
    except Reject as exc:
        return exc.code
    if not hmac.compare_digest(observed_host_key, payload["hostKeySha256"]):
        return "hostFingerprintMismatch"
    return "ok"


def guest_commitment(guest_key: str, guest_nonce: str) -> str:
    return hashlib.sha256(f"jovra-room-commit|{guest_key}|{guest_nonce}".encode("ascii")).hexdigest()


def join_proof(token: str, session_id: str, invite_id: str, nonce: str, guest_key: str, commitment: str) -> str:
    msg = f"{session_id}|{invite_id}|{nonce}|{guest_key}|{commitment}".encode("utf-8")
    return hmac.new(token.encode("ascii"), msg, hashlib.sha256).hexdigest()


def verification_code(host_key: str, guest_key: str, qr_nonce: str, host_nonce: str, guest_nonce: str) -> str:
    """Six digits both screens show before the host approves. Never typed in as a secret."""
    msg = f"jovra-room-sas|{host_key}|{guest_key}|{qr_nonce}|{host_nonce}|{guest_nonce}"
    digest = hashlib.sha256(msg.encode("ascii")).hexdigest()
    return f"{int(digest[:8], 16) % 1_000_000:06d}"


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def _result(result: str, code=None, grants=(), verification=None, host_nonce=None, device=None) -> dict:
    return {"result": result, "code": code, "grants": list(grants), "verificationCode": verification,
            "hostNonce": host_nonce, "deviceId": device}


class HostInvitations:
    """Host-side invitation state. ``tokens`` and ``nonces`` stand in for the host's secure store; ``members`` maps
    already-admitted device ids to their key fingerprints (the host's own device included)."""

    def __init__(self, session_id: str, host_epoch: int, host_key: str, records: list, tokens: dict, nonces: dict,
                 members: dict | None = None):
        self.session_id = session_id
        self.host_epoch = host_epoch
        self.host_key = host_key
        self.records = {r["inviteId"]: dict(r) for r in records}
        self.tokens = dict(tokens)
        self.nonces = dict(nonces)
        self.members = dict(members or {})
        self.pending = {}      # inviteId -> {"req", "hostNonce", "stage", "code"}
        self.attempts = {}     # inviteId -> failed attempts by token holders
        self.lookup_misses = {}  # source -> [miss times, epoch seconds]
        self.log = []  # never contains tokens, proofs, nonces or QR text

    def _reject(self, code: str) -> dict:
        self.log.append({"event": "joinRejected", "code": code})
        return _result("rejected", code)

    def _is_member(self, req: dict) -> bool:
        return req["guestDeviceId"] in self.members or req["guestKeySha256"] in self.members.values()

    def _fail_attempt(self, invite_id: str) -> None:
        self.attempts[invite_id] = self.attempts.get(invite_id, 0) + 1
        rec = self.records[invite_id]
        if self.attempts[invite_id] >= MAX_JOIN_ATTEMPTS and rec["status"] == "issued":
            rec.update(status="revoked", revokedReason="attemptsExhausted")
            self.log.append({"event": "inviteRevoked", "inviteId": invite_id, "reason": "attemptsExhausted"})

    def validate_join(self, req: dict, now: str, host_nonce: str) -> dict:
        """Checks the join request; on success the host answers with a fresh random hostNonce (the challenge)."""
        rec = self.records.get(req["inviteId"])
        if rec is None:
            return self._reject("unknownInvite")
        if req["sessionId"] != self.session_id or rec["sessionId"] != self.session_id:
            return self._reject("wrongSession")
        if rec["status"] == "revoked" or rec["hostEpoch"] != self.host_epoch or req["hostEpoch"] != self.host_epoch:
            return self._reject("revoked")
        if rec["status"] == "used":
            return self._reject("alreadyUsed")
        if req["inviteId"] in self.pending:
            return self._reject("joinInProgress")
        if rec["status"] == "expired" or parse_time(now) > parse_time(rec["expiresAt"]):
            rec["status"] = "expired"
            return self._reject("expired")
        if not hmac.compare_digest(req["observedHostKeySha256"], self.host_key) or rec["hostKeySha256"] != self.host_key:
            return self._reject("hostFingerprintMismatch")
        if req["requestedCaptureRole"] != rec["captureRole"] or req["requestedCommandRole"] != rec["commandRole"]:
            return self._reject("roleMismatch")
        token = self.tokens.get(rec["inviteId"])
        if token is None or token_hash(token) != rec["joinTokenSha256"]:
            return self._reject("unknownInvite")
        expected = join_proof(token, self.session_id, rec["inviteId"], self.nonces[rec["inviteId"]],
                              req["guestKeySha256"], req["guestCommitment"])
        if not hmac.compare_digest(expected, req["proof"]):
            return self._reject("badProof")
        if self._is_member(req):
            return self._reject("alreadyMember")
        self.pending[rec["inviteId"]] = {"req": req, "hostNonce": host_nonce, "stage": "challenged", "code": None}
        self.log.append({"event": "joinChallenged", "inviteId": rec["inviteId"]})
        return _result("challenge", host_nonce=host_nonce)

    def reveal(self, invite_id: str, guest_nonce: str) -> dict:
        """The guest opens its commitment after seeing hostNonce; both screens then show the same six digits."""
        p = self.pending.get(invite_id)
        if p is None or p["stage"] != "challenged":
            return self._reject("noPendingJoin")
        req = p["req"]
        if not hmac.compare_digest(guest_commitment(req["guestKeySha256"], guest_nonce), req["guestCommitment"]):
            del self.pending[invite_id]
            self._fail_attempt(invite_id)
            return self._reject("commitmentMismatch")
        p["stage"] = "awaitingApproval"
        p["code"] = verification_code(self.host_key, req["guestKeySha256"], self.nonces[invite_id], p["hostNonce"],
                                      guest_nonce)
        self.log.append({"event": "awaitingHostApproval", "inviteId": invite_id})
        return _result("awaitingHostApproval", verification=p["code"])

    def approve(self, invite_id: str, codes_match_confirmed: bool, now: str) -> dict:
        p = self.pending.get(invite_id)
        if p is None or p["stage"] != "awaitingApproval":
            return self._reject("noPendingJoin")
        del self.pending[invite_id]
        req, rec = p["req"], self.records[invite_id]
        if not codes_match_confirmed:
            self._fail_attempt(invite_id)
            return self._reject("verificationNotConfirmed")
        if rec["hostEpoch"] != self.host_epoch or rec["status"] != "issued":
            return self._reject("revoked")
        if parse_time(now) > parse_time(rec["expiresAt"]):
            rec["status"] = "expired"
            return self._reject("expired")
        if self._is_member(req):
            return self._reject("alreadyMember")
        rec.update(status="used", usedByDeviceId=req["guestDeviceId"], usedAt=now)
        self.members[req["guestDeviceId"]] = req["guestKeySha256"]
        self.log.append({"event": "joined", "inviteId": invite_id, "deviceId": req["guestDeviceId"]})
        return _result("accepted", grants=grants_for(rec["captureRole"], rec["commandRole"]), device=req["guestDeviceId"])

    def lookup(self, display_code: str, source: str, now: str) -> dict:
        """Manual-entry lookup. Finds an open, unexpired invitation for on-screen host approval; never authenticates.
        Misses are counted per requesting source in a sliding window, so one guesser cannot lock out everyone else."""
        t = parse_time(now).timestamp()
        recent = [m for m in self.lookup_misses.get(source, []) if t - m < LOOKUP_WINDOW_S]
        self.lookup_misses[source] = recent
        if len(recent) >= LOOKUP_MAX_MISSES:
            return {"result": "lookupThrottled", "inviteId": None, "authenticates": False}
        for rec in self.records.values():
            if rec["displayCode"] != display_code or rec["status"] != "issued" or rec["hostEpoch"] != self.host_epoch:
                continue
            if parse_time(now) > parse_time(rec["expiresAt"]):
                rec["status"] = "expired"
                continue
            return {"result": "found", "inviteId": rec["inviteId"], "authenticates": False}
        recent.append(t)
        return {"result": "notFound", "inviteId": None, "authenticates": False}

    def transfer_host(self, new_epoch: int, new_host_key: str) -> list:
        """A new host epoch revokes every open invitation and pending join; new invitations must be issued."""
        revoked = []
        for rec in self.records.values():
            if rec["status"] == "issued":
                rec.update(status="revoked", revokedReason="hostTransfer")
                revoked.append(rec["inviteId"])
        self.pending.clear()
        self.host_epoch = new_epoch
        self.host_key = new_host_key
        return sorted(revoked)
