"""Receiver-owned freshness, frozen remote elapsed time, derived counts and the disconnect rule.

Freshness is computed only from monotonic durations measured on one device at a time and chained:

    age = sender-side age (ageAtHostMs or ageAtBridgeMs)  +  transport-observed transit  +  receiver time since accept

Wall clocks from different devices are never subtracted. If transit cannot be bounded (a queued background delivery),
or the receiving process's monotonic baseline is not the one the payload was accepted under (restart), the state is
Unknown until a bounded exchange renews it. Arrival time alone never resets freshness. Counts are taken over the
roster's enrolled cameras, never over the rows that happen to be present.
"""

from __future__ import annotations

FRESH, DELAYED, UNKNOWN, LOCAL = "Fresh", "Delayed", "Unknown", "Local"
DEFAULT_POLICY = {"freshMaxMs": 5000, "delayedMaxMs": 15000}
ACTIVE_CAPTURE = frozenset({"Starting", "Recording", "Paused", "Finalizing"})


def _duration(name: str, value) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{name} must be an integer number of milliseconds")
    if value < 0:
        raise ValueError(f"negativeAge: {name} = {value}")
    return value


def chained_age_ms(sender_age_ms, since_accept_ms, *, transit_bounded: bool, baseline_valid: bool, transit_ms=None):
    """The receiver's conservative age in ms, or None when it cannot be established (Unknown)."""
    sender_age_ms = _duration("senderAgeMs", sender_age_ms)
    since_accept_ms = _duration("sinceAcceptMs", since_accept_ms)
    if transit_bounded:
        if transit_ms is None:
            raise ValueError("transitBoundMissing: a bounded transit must state its bound")
        transit_ms = _duration("transitMs", transit_ms)
    if not transit_bounded or not baseline_valid:
        return None
    return sender_age_ms + transit_ms + since_accept_ms


def classify_age(age_ms, policy=None) -> str:
    policy = policy or DEFAULT_POLICY
    if age_ms is None:
        return UNKNOWN
    if age_ms <= policy["freshMaxMs"]:
        return FRESH
    if age_ms <= policy["delayedMaxMs"]:
        return DELAYED
    return UNKNOWN


def classify(sender_age_ms, since_accept_ms, *, transit_bounded: bool, baseline_valid: bool, transit_ms=None, policy=None) -> str:
    return classify_age(chained_age_ms(sender_age_ms, since_accept_ms, transit_bounded=transit_bounded,
                                       baseline_valid=baseline_valid, transit_ms=transit_ms), policy)


def _observe(devices, age_key: str, obs: dict, now_mono_ms: int, current_baseline_id: str, policy: dict) -> list:
    """Shared by the phone path (snapshot ageAtHostMs) and the watch path (bridge ageAtBridgeMs).

    The receiver's process baseline id must change on every process start and every reboot (include a boot id), so a
    reused id after a reboot is a contract violation. If one happens anyway and the clock appears to run backwards, the
    age is Unknown: a receiver never crashes on its own clock."""
    baseline_valid = obs["processBaselineId"] == current_baseline_id
    since = now_mono_ms - obs["acceptedAtMonoMs"]
    if since < 0:
        baseline_valid, since = False, 0
    out = []
    for d in devices:
        age = chained_age_ms(d[age_key], since if baseline_valid else 0, transit_bounded=obs["transitBounded"],
                             baseline_valid=baseline_valid, transit_ms=obs["transitMs"])
        out.append((d, classify_age(age, policy), age))
    return out


def observe_bridge(bridge: dict, now_mono_ms: int, current_baseline_id: str) -> list:
    """Watch path: per-camera (device, freshness, ageMs) for a cached watch-bridge payload and its receiverObservation."""
    return _observe(bridge["devices"], "ageAtBridgeMs", bridge["receiverObservation"], now_mono_ms,
                    current_baseline_id, bridge["freshnessPolicy"])


def observe_snapshot(env: dict, obs: dict, now_mono_ms: int, current_baseline_id: str) -> list:
    """Phone path: age = ageAtHostMs + host-to-phone transit + the phone's monotonic time since accepting the snapshot.
    obs has the receiverObservation fields (transitBounded, transitMs, processBaselineId, acceptedAtMonoMs)."""
    return _observe(env["devices"], "ageAtHostMs", obs, now_mono_ms, current_baseline_id, env["freshnessPolicy"])


def display_row(device: dict, freshness: str, age_ms, *, is_local: bool = False, local_elapsed_ms=None) -> dict:
    """What a status row may say. A remote duration is always the last reported value: it is never extended with the
    receiver's clock, even while fresh. Only the device's own UI may run its local capture timer."""
    if is_local:
        return {"deviceId": device["deviceId"], "freshness": "Local", "elapsedMs": _duration("localElapsedMs", local_elapsed_ms),
                "elapsedSource": "local-timer", "extrapolated": False, "stale": False, "lastHeardAgeMs": 0,
                "mayStillBeRecording": False, "captureState": device["captureState"]}
    stale = freshness != FRESH
    return {
        "deviceId": device["deviceId"],
        "freshness": freshness,
        "elapsedMs": device["lastReportedElapsedMs"],
        "elapsedSource": "last-reported",
        "extrapolated": False,
        "stale": stale,
        "lastHeardAgeMs": age_ms,
        "mayStillBeRecording": stale and device["captureState"] in ACTIVE_CAPTURE,
        "captureState": device["captureState"],
    }


def counts(rows, enrolled_ids) -> dict:
    """rows: iterable of (device, freshness); enrolled_ids: the roster's camera ids (never the rows that happen to be
    present). An enrolled camera with no row is Unknown and not recording-fresh. 'Local' (the device's own capture,
    known now) counts as fresh. Only freshly heard (or local) Recording devices enter the fresh-recording numerator,
    and canClaimAllRecording holds only when every enrolled camera is in it."""
    rows = list(rows)
    enrolled = sorted(set(enrolled_ids))
    by_id = {}
    for d, f in rows:
        if d["deviceId"] not in enrolled:
            raise ValueError(f"rowNotEnrolled: {d['deviceId']}")
        by_id[d["deviceId"]] = (d, f)
    fresh_like = (FRESH, LOCAL)
    fresh = sum(1 for _, f in by_id.values() if f in fresh_like)
    delayed = sum(1 for _, f in by_id.values() if f == DELAYED)
    unknown = sum(1 for _, f in by_id.values() if f == UNKNOWN) + (len(enrolled) - len(by_id))
    reported = sum(1 for d, _ in by_id.values() if d["captureState"] == "Recording")
    fresh_recording = sum(1 for d, f in by_id.values() if f in fresh_like and d["captureState"] == "Recording")
    return {"enrolled": len(enrolled), "fresh": fresh, "delayed": delayed, "unknown": unknown,
            "reportedRecording": reported, "freshRecording": fresh_recording,
            "canClaimAllRecording": len(enrolled) > 0 and fresh_recording == len(enrolled)}


def on_room_disconnect(local_device: dict, remote_devices: list) -> dict:
    """The room link (host or network) is lost. Local capture continues untouched; no command of any kind is generated
    (in particular no stop-all); every cached remote status becomes Unknown and keeps its last reported elapsed value."""
    rows = [display_row(d, UNKNOWN, None) for d in remote_devices]
    return {"localCaptureState": local_device["captureState"], "commandsIssued": [],
            "remote": rows, "counts": counts(((d, UNKNOWN) for d in remote_devices), [d["deviceId"] for d in remote_devices])}
