"""The host's command ledger and the issuer's offline outbox.

Order of checks on the host (each code is pinned by fixtures). Steps 1-3 run before the idempotency store is touched,
and their rejections are never cached, so an unauthenticated or out-of-epoch submission cannot burn a commandId:
  1. channel authentication: the transport hands the ledger the authenticated peer device (the TLS peer key bound to a
     device at join). No peer is 'unauthenticatedChannel'; a peer that is not a member is 'notMember'
  2. issuer binding: issuer.memberId must be the peer's member; a phone issuer's deviceId must be the peer; a watch
     issuer's bridgeDeviceId must be the peer and its deviceId one of that member's registered watches. Otherwise
     'issuerNotAuthenticated'. Steps 1-2 are security-logged
  3. session, host epoch ('wrongSession', 'staleEpoch', 'unknownEpoch')
  4. idempotency, scoped to the authenticated member: a known (memberId, commandId) with the same fingerprint returns
     the original receipt; different contents are 'commandIdReuse' (security-logged, stored receipt untouched). The
     fingerprint is the canonical JSON of the command WITHOUT the volatile send field expiry.ageAtSendMs, which the
     issuer recomputes on every send
  5. the claimed role must be one of the member's granted roles (a set: a host may hold scorer and
     capture-controller); 'roleNotGranted' is security-logged. A paired watch acts with its member's grants
  6. the claimed role permits the command type ('roleNotPermitted'); a watch never issues a capture request
     ('surfaceNotPermitted': its own-phone stop is local to the bridge, never a room command)
  7. expiry from chained monotonic ages; the host's own transit/hold observation fails closed: a missing, partial,
     negative or non-integer observation is unbounded transit. A capture request with unbounded transit expires;
     capture TTL <= 30 s
  8. targets: a capture request needs at least one target ('noTargets') and every target is an enrolled camera
  9. score commands: baseEventRevision must equal the current revision (else Conflicted, never applied); Undo must
     name a live PointWon
 10. apply exactly once; capture requests fan out with a Pending result per target device
Decisions from step 4 onwards are cached under (memberId, commandId). Point and undo events form an append-only log;
totals are always recomputed from it, never edited in place.
"""

from __future__ import annotations

import copy

from .core import fingerprint

ROLE_COMMANDS = {
    "viewer": frozenset(),
    "marker": frozenset({"MarkForReview"}),
    "scorer": frozenset({"PointWon", "Undo", "MarkForReview"}),
    "capture-controller": frozenset({"StartRequest", "StopOne", "StopAllRequest", "MarkForReview"}),
}
SCORE_TYPES = frozenset({"PointWon", "Undo"})
CAPTURE_TYPES = frozenset({"StartRequest", "StopOne", "StopAllRequest"})
CAPTURE_TTL_MAX_MS = 30000
ACTIVE = frozenset({"Starting", "Recording", "Paused"})
SECURITY_CODES = frozenset({"commandIdReuse", "notMember", "roleNotGranted", "issuerNotAuthenticated",
                            "unauthenticatedChannel"})
FINAL_STATUSES = frozenset({"Accepted", "Rejected", "Expired", "Conflicted"})
# Rejections an issuer may retry unchanged (never cached by the host, never final for the outbox).
TRANSIENT_REASONS = frozenset({"unauthenticatedChannel", "notMember", "issuerNotAuthenticated", "wrongSession",
                               "staleEpoch", "unknownEpoch"})


def command_fingerprint(command: dict) -> str:
    """Idempotency fingerprint: canonical JSON without the volatile send field expiry.ageAtSendMs."""
    body = copy.deepcopy(command)
    body["expiry"].pop("ageAtSendMs", None)
    return fingerprint(body)


def _nonneg_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def observed_extra_age(delivery) -> int | None:
    """Transit + host holding time measured by the host's own transport, or None when it cannot be bounded.
    Fails closed: no observation, transitBounded not exactly true, or a missing/negative/non-integer value is
    unbounded. A negative value can therefore never extend a TTL."""
    if not isinstance(delivery, dict) or delivery.get("transitBounded") is not True:
        return None
    transit, hold = delivery.get("transitMs"), delivery.get("hostHoldMs")
    if not (_nonneg_int(transit) and _nonneg_int(hold)):
        return None
    return transit + hold


def receipt(command: dict, status: str, reason=None, revision=None, applied=None, conflict=None, results=None) -> dict:
    return {
        "schemaVersion": "jovra.room.receipt/1",
        "commandId": command["commandId"],
        "sessionId": command["sessionId"],
        "hostEpoch": command["hostEpoch"],
        "type": command["payload"]["type"],
        "status": status,
        "reason": reason,
        "canonicalEventRevision": revision,
        "appliedRecordId": applied,
        "conflict": conflict,
        "deviceResults": results or [],
    }


def summarize(rec: dict) -> dict:
    """Banner text for a capture fan-out comes from per-device results only; 'allConfirmed' needs every target."""
    tally = {}
    for r in rec["deviceResults"]:
        tally[r["status"]] = tally.get(r["status"], 0) + 1
    n = len(rec["deviceResults"])
    banner = "allConfirmed" if n and tally.get("Accepted", 0) == n else ("waiting" if n and tally.get("Pending", 0) == n else "partial")
    return {"targets": n, "byStatus": dict(sorted(tally.items())), "banner": banner}


def _member(spec: dict) -> dict:
    roles = sorted(set(spec["roles"]))
    if not roles or any(r not in ROLE_COMMANDS for r in roles):
        raise ValueError(f"bad member roles {spec['roles']!r}")
    return {"roles": roles, "deviceId": spec["deviceId"], "watchDeviceIds": sorted(spec.get("watchDeviceIds", []))}


class CommandLedger:
    def __init__(self, session_id: str, host_epoch: int, event_revision: int, members: dict, devices: dict):
        self.session_id = session_id
        self.host_epoch = host_epoch
        self.revision = event_revision
        # memberId -> {"roles": [...], "deviceId": the member's authenticated phone, "watchDeviceIds": [...]}
        self.members = {m: _member(s) for m, s in members.items()}
        self.devices = copy.deepcopy(devices)  # deviceId -> simulated device conditions + captureState
        self.events = []
        self.marks = []
        self.receipts = {}                     # "memberId/commandId" -> {"fingerprint", "receipt"}
        self.security_log = []

    # ----- host decisions ------------------------------------------------------------------------
    def submit(self, command: dict, delivery: dict | None = None, peer: dict | None = None) -> dict:
        cid = command["commandId"]
        member_id, code = self._authenticate(command, peer)
        if code is not None:
            self.security_log.append({"commandId": cid, "code": code})
            return receipt(command, "Rejected", code, self.revision)
        if command["sessionId"] != self.session_id:
            return receipt(command, "Rejected", "wrongSession", self.revision)
        if command["hostEpoch"] < self.host_epoch:
            return receipt(command, "Rejected", "staleEpoch", self.revision)
        if command["hostEpoch"] > self.host_epoch:
            return receipt(command, "Rejected", "unknownEpoch", self.revision)
        key = f"{member_id}/{cid}"
        fp = command_fingerprint(command)
        stored = self.receipts.get(key)
        if stored is not None:
            if stored["fingerprint"] == fp:
                return copy.deepcopy(stored["receipt"])
            self.security_log.append({"commandId": cid, "code": "commandIdReuse"})
            return receipt(command, "Rejected", "commandIdReuse", self.revision)
        rec = self._decide(command, self.members[member_id], delivery)
        if rec["reason"] in SECURITY_CODES:
            self.security_log.append({"commandId": cid, "code": rec["reason"]})
        self.receipts[key] = {"fingerprint": fp, "receipt": rec}
        return copy.deepcopy(rec)

    def _authenticate(self, c: dict, peer):
        """Binds the command's issuer to the authenticated channel peer. Returns (memberId, None) or (None, code)."""
        if not isinstance(peer, dict) or not isinstance(peer.get("deviceId"), str):
            return None, "unauthenticatedChannel"
        member_id = next((m for m, s in sorted(self.members.items()) if s["deviceId"] == peer["deviceId"]), None)
        if member_id is None:
            return None, "notMember"
        issuer, member = c["issuer"], self.members[member_id]
        if issuer["memberId"] != member_id:
            return None, "issuerNotAuthenticated"
        if issuer["surface"] == "phone":
            bound = issuer["deviceId"] == peer["deviceId"]
        else:
            bound = issuer["bridgeDeviceId"] == peer["deviceId"] and issuer["deviceId"] in member["watchDeviceIds"]
        return (member_id, None) if bound else (None, "issuerNotAuthenticated")

    def _decide(self, c: dict, member: dict, delivery) -> dict:
        kind = c["payload"]["type"]
        if c["role"] not in member["roles"]:
            return receipt(c, "Rejected", "roleNotGranted", self.revision)
        if kind not in ROLE_COMMANDS[c["role"]]:
            return receipt(c, "Rejected", "roleNotPermitted", self.revision)
        if c["issuer"]["surface"] == "watch" and kind in CAPTURE_TYPES:
            return receipt(c, "Rejected", "surfaceNotPermitted", self.revision)  # ADR-0026 as amended: no watch capture control
        ttl = c["expiry"]["ttlMs"]
        if kind in CAPTURE_TYPES and ttl > CAPTURE_TTL_MAX_MS:
            return receipt(c, "Rejected", "ttlTooLong", self.revision)
        extra = observed_extra_age(delivery)
        if extra is None:
            if kind in CAPTURE_TYPES:
                return receipt(c, "Expired", "unboundedTransit", self.revision)
        elif c["expiry"]["ageAtSendMs"] + extra > ttl:
            return receipt(c, "Expired", "expired", self.revision)
        targets = self._targets(c)
        if kind in CAPTURE_TYPES and not targets:
            return receipt(c, "Rejected", "noTargets", self.revision)
        if any(t not in self.devices for t in targets):
            return receipt(c, "Rejected", "unknownTarget", self.revision)
        if kind in SCORE_TYPES:
            if c["baseEventRevision"] != self.revision:
                return receipt(c, "Conflicted", "baseRevisionStale", self.revision,
                               conflict={"baseEventRevision": c["baseEventRevision"], "currentEventRevision": self.revision})
            if kind == "Undo" and not self._undoable(c["payload"]["targetEventId"]):
                return receipt(c, "Rejected", "undoTargetInvalid", self.revision)
            self.revision += 1
            event_id = f"evt-{self.revision}"
            entry = {"eventId": event_id, "revision": self.revision, "type": kind, "commandId": c["commandId"]}
            entry.update({k: v for k, v in c["payload"].items() if k != "type"})
            self.events.append(entry)
            return receipt(c, "Accepted", None, self.revision, applied=event_id)
        if kind == "MarkForReview":
            mark_id = f"mark-{len(self.marks) + 1}"
            p = c["payload"]
            self.marks.append({"markId": mark_id, "commandId": c["commandId"], "reason": p["reason"],
                               "pointEventId": p["pointEventId"], "sourceRefs": copy.deepcopy(p["sourceRefs"]),
                               "atEventRevision": self.revision})
            return receipt(c, "Accepted", None, self.revision, applied=mark_id)
        results = [{"deviceId": t, "status": "Pending", "reason": None} for t in targets]
        return receipt(c, "Accepted", None, self.revision, results=results)

    def _targets(self, c: dict) -> list:
        if c["target"]["scope"] == "allCameras":
            return sorted(self.devices)
        return list(c["target"]["deviceIds"])

    def _undoable(self, event_id: str) -> bool:
        undone = {e["targetEventId"] for e in self.events if e["type"] == "Undo"}
        return any(e["eventId"] == event_id and e["type"] == "PointWon" for e in self.events) and event_id not in undone

    def begin_epoch(self, new_epoch: int) -> None:
        """Host recovery on the same device at a higher epoch keeps the event log and cached decisions."""
        if new_epoch <= self.host_epoch:
            raise ValueError("epochNotNewer")
        self.host_epoch = new_epoch

    # ----- device side of a capture request ----------------------------------------------------
    def deliver(self, command_id: str) -> dict:
        """Each target device decides locally; the host records what each actually answered."""
        keys = [k for k in self.receipts if k.split("/", 1)[1] == command_id]
        if len(keys) != 1:
            raise KeyError(f"no single receipt for {command_id}")
        rec = self.receipts[keys[0]]["receipt"]
        for r in rec["deviceResults"]:
            if r["status"] != "Pending":
                continue  # final per-device results are immutable
            r["status"], r["reason"] = self._device_answer(rec["type"], self.devices[r["deviceId"]])
        return copy.deepcopy(rec)

    @staticmethod
    def _device_answer(kind: str, d: dict):
        if not d.get("reachable", True):
            return "TimedOut", "unreachable"
        if d.get("ackLost", False):
            return "Unknown", "noAcknowledgement"
        if kind == "StartRequest":
            if d.get("cameraPermission", "granted") != "granted":
                return "Denied", "cameraPermissionDenied"
            if not d.get("foreground", True):
                return "Denied", "foregroundRequired"
            if d["captureState"] == "Finalizing":
                return "Denied", "finalizing"  # never report Starting while the previous take is still finalizing
            if d["captureState"] in ACTIVE:
                return "Accepted", "alreadyRecording"
            d["captureState"] = "Starting"  # Recording only when the device itself reports it
            return "Accepted", "startRequested"
        if d["captureState"] not in ACTIVE:
            return "Accepted", "notRecording"
        if d.get("stopFault", False):
            return "Failed", "finalizeFailed"
        d["captureState"] = "Finalizing"
        return "Accepted", "stopRequested"

    def device_report(self, device_id: str, capture_state: str) -> None:
        self.devices[device_id]["captureState"] = capture_state

    def room_link_lost(self) -> list:
        """A lost participant or network never generates a command. Returns the (empty) list of commands issued."""
        return []

    # ----- derived state -------------------------------------------------------------------------
    def tally(self) -> dict:
        """Points per player recomputed from the event log (undo removes the target event's effect)."""
        undone = {e["targetEventId"] for e in self.events if e["type"] == "Undo"}
        out = {}
        for e in self.events:
            if e["type"] == "PointWon" and e["eventId"] not in undone:
                out[e["winnerPlayerId"]] = out.get(e["winnerPlayerId"], 0) + 1
        return dict(sorted(out.items()))

    def state(self) -> dict:
        return {"eventRevision": self.revision, "eventCount": len(self.events), "markCount": len(self.marks),
                "tally": self.tally(), "securityLog": copy.deepcopy(self.security_log),
                "captureStates": {k: v["captureState"] for k, v in sorted(self.devices.items())},
                "hostEpoch": self.host_epoch}

    # ----- persistence (process death) -----------------------------------------------------------
    def to_json(self) -> dict:
        return copy.deepcopy({"sessionId": self.session_id, "hostEpoch": self.host_epoch, "revision": self.revision,
                              "members": self.members, "devices": self.devices, "events": self.events,
                              "marks": self.marks, "receipts": self.receipts, "securityLog": self.security_log})

    @classmethod
    def from_json(cls, s: dict) -> "CommandLedger":
        led = cls(s["sessionId"], s["hostEpoch"], s["revision"], s["members"], s["devices"])
        led.events = copy.deepcopy(s["events"])
        led.marks = copy.deepcopy(s["marks"])
        led.receipts = copy.deepcopy(s["receipts"])
        led.security_log = copy.deepcopy(s["securityLog"])
        return led


class Outbox:
    """Issuer side (phone or watch). Offline commands are pending drafts: shown as Pending, never applied to the
    canonical score, and never treated as sent until a final host receipt exists.

    - Every send recomputes expiry.ageAtSendMs from the issuer's monotonic clock, so time spent queued counts towards
      the TTL (the host cannot see it). The idempotency fingerprint excludes that field, so a refreshed retry still
      matches its original.
    - flush() sends nothing while the outbox's epoch differs from the host's: reconcile() first. Drafts whose answer
      is transient (session, epoch, channel) stay queued.
    - Consecutive score drafts are a chain (each based on the previous draft's expected revision). Once one is not
      Accepted, the later score drafts are held as Pending/requiresResubmit and never sent against a revision their
      author did not see."""

    def __init__(self, host_epoch: int, known_revision: int):
        self.host_epoch = host_epoch
        self.known_revision = known_revision
        self.queue = []      # [{"command": ..., "issuedAtMonoMs": ...}]
        self.receipts = {}

    def submit_offline(self, command: dict, now_mono_ms: int = 0) -> dict:
        issued = now_mono_ms - command["expiry"]["ageAtSendMs"]
        self.queue.append({"command": copy.deepcopy(command), "issuedAtMonoMs": issued})
        rec = receipt(command, "Pending", "offlineDraft", None)
        self.receipts[command["commandId"]] = rec
        return copy.deepcopy(rec)

    @staticmethod
    def outgoing(entry: dict, now_mono_ms: int) -> dict:
        age = now_mono_ms - entry["issuedAtMonoMs"]
        if age < 0:
            raise ValueError("negativeAge: the issuer's monotonic clock went backwards")
        c = copy.deepcopy(entry["command"])
        c["expiry"]["ageAtSendMs"] = age
        return c

    def flush(self, ledger: CommandLedger, now_mono_ms: int = 0, delivery: dict | None = None, peer: dict | None = None) -> list:
        if self.host_epoch != ledger.host_epoch:
            return []  # the drafts wait for reconcile(); nothing is sent, nothing is dropped
        out, keep, chain_broken = [], [], False
        for entry in self.queue:
            c = entry["command"]
            kind = c["payload"]["type"]
            if chain_broken and kind in SCORE_TYPES:
                rec = receipt(c, "Pending", "requiresResubmit", None)
                keep.append(entry)
            else:
                rec = ledger.submit(self.outgoing(entry, now_mono_ms), delivery, peer)
                if rec["status"] not in FINAL_STATUSES or rec["reason"] in TRANSIENT_REASONS:
                    keep.append(entry)
                if kind in SCORE_TYPES and rec["status"] != "Accepted":
                    chain_broken = True
                if rec["canonicalEventRevision"] is not None:
                    self.known_revision = rec["canonicalEventRevision"]
            self.receipts[c["commandId"]] = rec
            out.append(copy.deepcopy(rec))
        self.queue = keep
        return out

    def reconcile(self, new_epoch: int, host_receipts: dict) -> dict:
        """After a host epoch change: adopt receipts the new host already holds; capture requests it does not know
        expire (never replayed under a new host); other drafts stay Pending until the user resubmits them against the
        new epoch and revision."""
        result = {}
        keep = []
        for entry in self.queue:
            c = entry["command"]
            cid = c["commandId"]
            if cid in host_receipts:
                self.receipts[cid] = copy.deepcopy(host_receipts[cid])
            elif c["payload"]["type"] in CAPTURE_TYPES:
                self.receipts[cid] = receipt(c, "Expired", "hostEpochChanged", None)
            else:
                self.receipts[cid] = receipt(c, "Pending", "requiresResubmit", None)
                keep.append(entry)
            result[cid] = {"status": self.receipts[cid]["status"], "reason": self.receipts[cid]["reason"]}
        self.queue = keep
        self.host_epoch = new_epoch
        return dict(sorted(result.items()))
