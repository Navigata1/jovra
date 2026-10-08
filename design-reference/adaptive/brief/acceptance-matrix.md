# Native/adaptive/watch acceptance matrix

Status: planned, not executed on native emulators or physical devices in this reference handoff.

| Scenario | Required result |
|---|---|
| Phone↔fold inner/outer; rotation; split screen | Selection/playhead/drafts survive; no duplicate render, score or charge |
| Hinge/occlusion/compact height | Controls remain reachable; pane count adapts; keyboard does not hide confirmation |
| Process death | Restored drafts; cached remote status Unknown until renewed; pending commands reconcile |
| Expired/replayed invite | Refused; no camera permission or originals exposed |
| Wrong host/session/epoch; arbitrary QR endpoint | Refused; identity/authentication and allowed transport verified |
| Camera reports Recording but receiver hears nothing | Last elapsed stays frozen; delayed/Unknown label with age; may still record locally |
| Phone sees fresh camera but watch bridge is stale | Watch shows Unknown; cannot call the aggregate live |
| Queued watch snapshot arrives after suspension | Unknown until bounded freshness/interactive refresh; arrival time alone cannot reset freshness |
| Duplicate identical command | Original receipt returned; one event/device action |
| Same command ID, different payload | Rejected and recorded as conflict/security failure |
| Two scores against the same revision | One authoritative update, second conflict; no silent double count |
| Undo/correct earlier point | Recompute every later score/stat/export from event log |
| Offline score/marker | Pending draft visible; canonical event not advanced without receipt |
| Viewer attempts stop-all/score | Permission denied; pairing does not grant controller role |
| Start with camera permission denied/phone backgrounded | Explicit Pending/Rejected/foreground action; no fictitious recording state |
| Stop one/all fan-out partially fails | Per-device Accepted/Failed/Unknown results; no blanket success banner |
| Host/network disappears | Local originals survive; new host epoch requires reconciliation |
| Watch rectangular vs round; large fonts | No clipping, readable score, reachable controls and correct accessibility labels |
| Haptics/always-on/low-power | Deduplicated critical alerts; quiet during rallies; timestamped snapshot, no fake workout privilege |
| Serve capability absent/calibration missing | Unavailable explanation; no invented live speed |
| Result older than current point | Explicit source/time/point; not shown as current serve |
| Bounce ambiguous/occluded/uncalibrated | Review needed/bookmark; no automated score change |
| Six-device endurance | Record loss/recovery, storage/heat/battery, permissions and actual clocks independently |

Attach commands, named profiles, raw test output, screenshots and observed limitations to each native/physical gate. Passing the included fixture verifier only demonstrates the illustrative freshness and command rules; it does not test a native transport.
