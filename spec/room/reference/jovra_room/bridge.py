"""Watch-side acceptance of jovra.room.watch-bridge/1 payloads.

The watch is bound at pairing to one bridge: its own paired phone (bridgeDeviceId). The companion channel
(WatchConnectivity / Wearable Data Layer) authenticates the pairing; the threats here are an OS queue redelivering an
old payload, a late resend, or a payload from a previous bridge process. A payload is accepted only when:

  1. it comes from the paired phone                                   'notPairedBridge'
  2. its bridge instance is current or new, never one the watch has left  'bridgeInstanceRetired'
  3. bridgeSeq strictly increases within the bridge instance           'replayOrOutOfOrder'
  4. within one session: hostEpoch never decreases                    'staleEpoch'
  5. within one session and epoch: snapshotSeq and eventRevision never decrease
                                                                       'snapshotSeqRegressed', 'eventRevisionRegressed'
A new bridge instance (the phone app restarted) or a new session (the phone joined another room) starts new marks;
an old instance or an old session can never come back because its bridgeSeq/instance is behind. Replay marks persist
across a watch restart; freshness never does (a new process baseline makes every cached age Unknown).
"""

from __future__ import annotations

ACCEPTED = "accepted"


class BridgeReceiver:
    def __init__(self, paired_phone_id: str):
        self.paired = paired_phone_id
        self.instance = None
        self.bridge_seq = None
        self.retired = set()
        self.sessions = {}  # sessionId -> [hostEpoch, snapshotSeq, eventRevision]

    def accept(self, env: dict) -> str:
        b = env["bridge"]
        if b["bridgeDeviceId"] != self.paired:
            return "notPairedBridge"
        if b["bridgeInstanceId"] in self.retired:
            return "bridgeInstanceRetired"
        if b["bridgeInstanceId"] == self.instance and b["bridgeSeq"] <= self.bridge_seq:
            return "replayOrOutOfOrder"
        marks = self.sessions.get(env["sessionId"])
        if marks is not None:
            epoch, seq, revision = marks
            if env["hostEpoch"] < epoch:
                return "staleEpoch"
            if env["hostEpoch"] == epoch:
                if env["snapshotSeq"] < seq:
                    return "snapshotSeqRegressed"
                if env["eventRevision"] < revision:
                    return "eventRevisionRegressed"
        if self.instance is not None and b["bridgeInstanceId"] != self.instance:
            self.retired.add(self.instance)
        self.instance = b["bridgeInstanceId"]
        self.bridge_seq = b["bridgeSeq"]
        self.sessions[env["sessionId"]] = [env["hostEpoch"], env["snapshotSeq"], env["eventRevision"]]
        return ACCEPTED

    def persisted(self) -> dict:
        return {"paired": self.paired, "instance": self.instance, "bridgeSeq": self.bridge_seq,
                "retired": sorted(self.retired), "sessions": {k: list(v) for k, v in sorted(self.sessions.items())}}

    @classmethod
    def restore(cls, state: dict) -> "BridgeReceiver":
        r = cls(state["paired"])
        r.instance = state["instance"]
        r.bridge_seq = state["bridgeSeq"]
        r.retired = set(state["retired"])
        r.sessions = {k: list(v) for k, v in state["sessions"].items()}
        return r
