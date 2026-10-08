"""Adapter from the design handoff's illustrative watch snapshot (design-reference/adaptive/brief/
watch-snapshot.sample.json, which predates this contract and uses schemaVersion 1) to jovra.room.watch-bridge/1.

The values (session, epoch, sequences, states, ages, elapsed durations, receipt) are carried over unchanged; the
illustrative 74 mph result is not carried into latestServe because the sample's capabilities do not include
serveSpeedResults (a post-capture estimate may be forwarded only when they do; live serve speed is never v1). The
bridge instance, roster (the sample's six cameras at revision 1) and participant are added: the sample predates them.
"""

from __future__ import annotations

# Not in the design sample (it predates roles): the sample watch belongs to Jon, a scorer, with every ability on.
SAMPLE_PARTICIPANT = {"memberId": "sample-member-jon", "commandRoles": ["scorer"],
                      "watchCommandTypes": ["MarkForReview", "PointWon", "Undo"]}
SCORE_POINT = {"0": "0", "15": "15", "30": "30", "40": "40", "AD": "AD"}


def from_design_sample(raw: dict) -> dict:
    s = raw["score"]
    players = [{"playerId": "jon", "games": s["jonGames"], "point": SCORE_POINT[s["jonPoint"]]},
               {"playerId": "alex", "games": s["alexGames"], "point": SCORE_POINT[s["alexPoint"]]}]
    obs = raw["transportObservation"]
    return {
        "schemaVersion": "jovra.room.watch-bridge/1",
        "sample": raw["sample"],
        "sessionId": raw["sessionId"],
        "hostEpoch": raw["hostEpoch"],
        "snapshotSeq": raw["snapshotSeq"],
        "eventRevision": raw["eventRevision"],
        "bridge": {"bridgeDeviceId": "sample-bridge-phone", "bridgeInstanceId": "sample-bridge-run-1",
                   "channel": "watchconnectivity", "bridgeSeq": raw["snapshotSeq"],
                   "snapshotAgeAtBridgeMs": min(d["ageAtBridgeMs"] for d in raw["devices"])},
        "participant": dict(SAMPLE_PARTICIPANT, commandRoles=list(SAMPLE_PARTICIPANT["commandRoles"]),
                            watchCommandTypes=list(SAMPLE_PARTICIPANT["watchCommandTypes"])),
        "freshnessPolicy": {"freshMaxMs": raw["freshnessPolicy"]["freshMaxMs"],
                            "delayedMaxMs": raw["freshnessPolicy"]["delayedMaxMs"], "proposalOnly": True},
        "capabilities": dict(raw["capabilities"]),
        "score": {"eventRevision": raw["eventRevision"], "label": s["label"].lower(), "players": players},
        "roster": {"rosterRevision": 1, "cameraDeviceIds": [d["deviceId"] for d in raw["devices"]]},
        "latestServe": None,
        "devices": [{k: d[k] for k in ("deviceId", "captureInstanceId", "segmentId", "deviceSeq", "captureState",
                                        "ageAtBridgeMs", "lastReportedElapsedMs")} for d in raw["devices"]],
        "alerts": [],
        "receipts": [{
            "schemaVersion": "jovra.room.receipt/1",
            "commandId": r["commandId"], "sessionId": raw["sessionId"], "hostEpoch": raw["hostEpoch"],
            "type": r["type"], "status": r["status"], "reason": None,
            "canonicalEventRevision": raw["eventRevision"], "appliedRecordId": "sample-mark-42",
            "conflict": None, "deviceResults": [],
        } for r in raw["receipts"]],
        "receiverObservation": {"delivery": "fixture", "transitBounded": bool(obs["transitBounded"]), "transitMs": 0,
                                "processBaselineId": "sample-watch-boot-1", "acceptedAtMonoMs": 0},
    }
