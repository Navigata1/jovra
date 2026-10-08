"""Room snapshot acceptance on a participant (or a watch bridge phone).

A receiver is bound at join to: the session, the host epoch, the host's TLS key, the host's device id and the roster
(the enrolled camera ids at a roster revision) it was admitted under. It accepts a snapshot only from that session,
epoch, key and host device, with a strictly increasing snapshotSeq, a non-decreasing eventRevision, and a roster that
only changes with a higher rosterRevision (the host announces approved joins and departures that way). Every device
entry must be on the roster; per-device sequences never go backwards within a capture instance, a sequence number is
never reused for different content, and a device never returns to a capture instance it has left.

Nothing unauthenticated changes state. A newer epoch is never accepted on sight: the envelope is refused with
'epochChangeRequiresReconciliation' and the receiver stays live on its current host. Only reconcile(), called after
the transport has authenticated an approved host transfer, adopts a newer epoch. Replay protection (seq high-water
marks, retired capture instances) is persisted across restarts; the monotonic freshness baseline is not.
"""

from __future__ import annotations

import copy

from .core import fingerprint

ACCEPTED = "accepted"


def _entry_fingerprint(device: dict) -> str:
    """A device's own report. ageAtHostMs is the host's measurement and changes between snapshots of one report."""
    return fingerprint({k: v for k, v in device.items() if k != "ageAtHostMs"})


class SnapshotReceiver:
    def __init__(self, session_id: str, host_epoch: int, host_key: str, host_device_id: str, members,
                 roster_revision: int = 0):
        self.session_id = session_id
        self.host_epoch = host_epoch
        self.host_key = host_key
        self.host_device_id = host_device_id
        self.members = set(members)
        self.roster_revision = roster_revision
        self.last_seq = None
        self.event_revision = None
        self.device_seq = {}  # deviceId -> [captureInstanceId, deviceSeq, entry fingerprint]
        self.retired = {}     # deviceId -> set of capture instances the device has left
        self.applied = None

    def accept(self, env: dict) -> str:
        if env["sessionId"] != self.session_id:
            return "wrongSession"
        if env["hostEpoch"] < self.host_epoch:
            return "staleEpoch"
        if env["hostEpoch"] > self.host_epoch:
            return "epochChangeRequiresReconciliation"  # informational; never changes state
        if env["hostKeySha256"] != self.host_key:
            return "hostKeyMismatch"
        if env["hostDeviceId"] != self.host_device_id:
            return "hostDeviceChanged"
        if self.last_seq is not None and env["snapshotSeq"] <= self.last_seq:
            return "replayOrOutOfOrder"
        if self.event_revision is not None and env["eventRevision"] < self.event_revision:
            return "eventRevisionRegressed"
        roster = env["roster"]
        roster_ids = set(roster["cameraDeviceIds"])
        if roster["rosterRevision"] < self.roster_revision:
            return "rosterRegressed"
        if roster["rosterRevision"] == self.roster_revision and roster_ids != self.members:
            return "rosterChangedWithoutRevision"
        seen = set()
        for d in env["devices"]:
            dev = d["deviceId"]
            if dev not in roster_ids:
                return "unauthenticatedDevice"
            if dev in seen:
                return "duplicateDevice"
            seen.add(dev)
            if d["captureInstanceId"] in self.retired.get(dev, ()):
                return "captureInstanceRetired"
            prev = self.device_seq.get(dev)
            if prev and prev[0] == d["captureInstanceId"]:
                if d["deviceSeq"] < prev[1]:
                    return "deviceSeqRegressed"
                if d["deviceSeq"] == prev[1] and _entry_fingerprint(d) != prev[2]:
                    return "deviceSeqReused"
        self.last_seq = env["snapshotSeq"]
        self.event_revision = env["eventRevision"]
        self.members = roster_ids
        self.roster_revision = roster["rosterRevision"]
        for d in env["devices"]:
            prev = self.device_seq.get(d["deviceId"])
            if prev and prev[0] != d["captureInstanceId"]:
                self.retired.setdefault(d["deviceId"], set()).add(prev[0])
            self.device_seq[d["deviceId"]] = [d["captureInstanceId"], d["deviceSeq"], _entry_fingerprint(d)]
        self.applied = copy.deepcopy(env)
        return ACCEPTED

    def reconcile(self, new_epoch: int, new_host_key: str, new_host_device_id: str, approved_host_keys) -> str:
        """Adopt a newer host epoch only for an approved, authenticated host key (the transport authenticated the
        transfer). Snapshot seq and event revision restart with the new epoch; device sequences, retired capture
        instances and the roster are device- or room-owned and keep protecting against replay."""
        if new_epoch <= self.host_epoch:
            return "epochNotNewer"
        if new_host_key not in set(approved_host_keys):
            return "hostNotAuthenticated"
        self.host_epoch = new_epoch
        self.host_key = new_host_key
        self.host_device_id = new_host_device_id
        self.last_seq = None
        self.event_revision = None
        return "reconciled"

    def persisted(self) -> dict:
        return {"sessionId": self.session_id, "hostEpoch": self.host_epoch, "hostKey": self.host_key,
                "hostDeviceId": self.host_device_id, "members": sorted(self.members),
                "rosterRevision": self.roster_revision, "lastSeq": self.last_seq, "eventRevision": self.event_revision,
                "deviceSeq": {k: list(v) for k, v in sorted(self.device_seq.items())},
                "retired": {k: sorted(v) for k, v in sorted(self.retired.items())}}

    @classmethod
    def restore(cls, state: dict) -> "SnapshotReceiver":
        r = cls(state["sessionId"], state["hostEpoch"], state["hostKey"], state["hostDeviceId"], state["members"],
                state["rosterRevision"])
        r.last_seq = state["lastSeq"]
        r.event_revision = state["eventRevision"]
        r.device_seq = {k: list(v) for k, v in state["deviceSeq"].items()}
        r.retired = {k: set(v) for k, v in state["retired"].items()}
        return r
