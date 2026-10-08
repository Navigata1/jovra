"""AlertPolicy: the phone-side single source of watch alerts (watch spec "Haptics and alerts"; ADR-0026 §8 as amended).

Rules, each pinned by vectors/alerts.json:
  - cameraUnknown is raised only for a camera that was freshly Recording and has then been Unknown for >= 3 s without
    interruption; a shorter blip raises nothing. A camera that was never freshly Recording never raises it.
  - One alert per camera per outage. The outage ends only when the camera has been Fresh for >= 4 s (clear). An
    acknowledged alert closes for the rest of that outage.
  - The same camera raises at most once per 5 min; a new outage inside that window raises when the window ends, if the
    camera is still Unknown.
  - cameraUnknown is never critical: its haptic is deferred until the next accepted point event or 45 s after the
    oldest pending alert, whichever comes first, and every pending alert collapses into one haptic. An alert that is
    cleared or acknowledged before its haptic fires drops out of it.
  - Critical alerts (ownRecordingFailed, ownStorageCritical) are raised and vibrate at once, once.
  - No alert ever issues a command (no stop of any kind).
Times are the phone's monotonic milliseconds.
"""

from __future__ import annotations

RAISE_AFTER_MS = 3000
CLEAR_AFTER_MS = 4000
REALERT_MIN_MS = 300000
DEFER_MAX_MS = 45000
OWN_CRITICAL = frozenset({"ownRecordingFailed", "ownStorageCritical"})


class AlertPolicy:
    def __init__(self):
        self.cams = {}     # deviceId -> state
        self.open = {}     # alertId -> alert
        self.pending = []  # [(raisedAt, alertId)] deferred haptics
        self.events = []
        self.seq = 0
        self.commands_issued = []

    def _cam(self, dev: str) -> dict:
        return self.cams.setdefault(dev, {"armed": False, "unknownSince": None, "freshSince": None, "alertId": None,
                                          "outageAcked": False, "lastRaisedAt": None})

    def _emit(self, t: int, event: str, alert: dict) -> None:
        self.events.append({"t": t, "event": event, "alertId": alert["alertId"], "kind": alert["kind"],
                            "deviceId": alert["deviceId"], "severity": alert["severity"]})

    def _raise(self, t: int, kind: str, dev, severity: str) -> dict:
        self.seq += 1
        alert = {"alertId": f"alert-{self.seq}", "kind": kind, "deviceId": dev, "severity": severity}
        self.open[alert["alertId"]] = alert
        self._emit(t, "raise", alert)
        return alert

    def _close(self, t: int, alert_id: str, event: str) -> None:
        alert = self.open.pop(alert_id)
        self.pending = [(r, a) for r, a in self.pending if a != alert_id]
        self._emit(t, event, alert)

    def _evaluate(self, t: int) -> None:
        for dev, c in sorted(self.cams.items()):
            if c["alertId"] is None and not c["outageAcked"] and c["armed"] and c["unknownSince"] is not None:
                due = t - c["unknownSince"] >= RAISE_AFTER_MS
                capped = c["lastRaisedAt"] is not None and t - c["lastRaisedAt"] < REALERT_MIN_MS
                if due and not capped:
                    alert = self._raise(t, "cameraUnknown", dev, "deferred")
                    c["alertId"], c["lastRaisedAt"] = alert["alertId"], t
                    self.pending.append((t, alert["alertId"]))
            if c["freshSince"] is not None and t - c["freshSince"] >= CLEAR_AFTER_MS:
                if c["alertId"] is not None:
                    self._close(t, c["alertId"], "clear")
                    c["alertId"] = None
                c["outageAcked"] = False
        if self.pending and t - min(r for r, _ in self.pending) >= DEFER_MAX_MS:
            self._haptic(t)

    def _haptic(self, t: int, pattern: str = "deferred", ids=None) -> None:
        ids = ids if ids is not None else sorted(a for _, a in self.pending)
        if pattern == "deferred":
            self.pending = []
        if ids:
            self.events.append({"t": t, "event": "haptic", "alertIds": ids, "pattern": pattern})

    def status(self, t: int, dev: str, freshness: str, capture_state: str) -> None:
        c = self._cam(dev)
        if freshness == "Fresh":
            if capture_state == "Recording":
                c["armed"] = True
            c["unknownSince"] = None
            c["freshSince"] = c["freshSince"] if c["freshSince"] is not None else t
        elif freshness == "Unknown":
            c["freshSince"] = None
            c["unknownSince"] = c["unknownSince"] if c["unknownSince"] is not None else t
        else:  # Delayed interrupts both runs
            c["freshSince"] = None
            c["unknownSince"] = None
        self._evaluate(t)

    def tick(self, t: int) -> None:
        self._evaluate(t)

    def point(self, t: int) -> None:
        self._evaluate(t)
        if self.pending:
            self._haptic(t)

    def own(self, t: int, kind: str, dev: str) -> None:
        if kind not in OWN_CRITICAL:
            raise ValueError(f"not an own-phone critical kind: {kind}")
        alert = self._raise(t, kind, dev, "critical")
        self._haptic(t, "critical", [alert["alertId"]])
        self._evaluate(t)

    def ack(self, t: int, alert_id: str) -> None:
        if alert_id not in self.open:
            return
        dev = self.open[alert_id]["deviceId"]
        self._close(t, alert_id, "ack")
        c = self.cams.get(dev)
        if c is not None and c["alertId"] == alert_id:
            c["alertId"], c["outageAcked"] = None, True
        self._evaluate(t)
