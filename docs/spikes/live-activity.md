# Spike T60: a recording Live Activity (P1-13)

**Decision: drop from v1.** No follow-up implementation ticket is filed now. The project file stays frozen.
The spike can be reopened only through the device gate described under [Reopen condition](#reopen-condition).

Ticket: [#62](https://github.com/Navigata1/jovra/issues/62) · Story 376 · Spec `docs/spec/ios-v1-spec.md` (P1-13, Out of Scope)
Spike code (throwaway, never merged): branch
[`ticket/t60-live-activity-spike-throwaway`](https://github.com/Navigata1/jovra/tree/ticket/t60-live-activity-spike-throwaway),
commit [`3e265ba`](https://github.com/Navigata1/jovra/commit/3e265ba).
Evidence: [`evidence/ios/60-live-activity-spike/`](../../evidence/ios/60-live-activity-spike/README.md).

## The question

Can a Live Activity mirror "REC 32:10 · Saved 4 s ago · Battery 64%" from the capture journal heartbeat, show
"Status unknown" when no heartbeat has arrived for 10 s, and stay current while JOVRA records in the foreground?

## What was tried

The work ran on the throwaway branch only.

- **A widget extension, `JovraLiveActivity`.** It has three presentations:
  - the Lock Screen and Notification Centre banner;
  - the Dynamic Island;
  - the `.small` supplemental family, which iOS 18+ uses in the Apple Watch Smart Stack.

  It uses the brand forest, ivory and chartreuse. The phase is shown as text ("REC", "Paused", "Status unknown"), not only as a colour, and Sample captures carry a "Sample" tag.
- **`RecordingLiveActivityPolicy`.** This is a pure mapping from the capture heartbeat to the activity content. It was built test-first, with 6 XCTest cases written red and then green.
  - It sends one update each time the journal's saved-through time advances.
  - It sets `staleDate` to the last heartbeat plus 10 s.
  - It freezes the time on pause.
  - It never invents a battery level.
- **`RecordingLiveActivityMirror`.** This wires the policy into `NativeCaptureCoordinator`'s status stream.
  - ActivityKit calls are fire-and-forget, so recording never waits on them (ADR-0010).
  - It logs every request and update, the capture status and the app lifecycle (os_log category `T60Spike`).
- **`LiveActivitySpikeUITests`.** These tests record with the simulator fixture camera and then read the activity's text from SpringBoard's accessibility tree about once every 1.3 s, in three cases:
  - Notification Centre pulled down over the recorder;
  - after locking the device;
  - after the app is killed in the middle of a recording.
- **Two REC timers.** The first was `Text(date, style: .timer)`, which has no upper bound. The second was `Text(timerInterval: start...deadline)`, which stops counting at the stale deadline.

Environment: Xcode 27.2 (27B52), the iOS 27.2 simulator on an iPhone 17 Pro (simulator `JOVRA-T60`), and the fixture
camera, so every capture is Sample. Nothing in this report ran on hardware.

## What the simulator showed

| # | Observation | Evidence |
|---|---|---|
| O1 | **Updates do flow while JOVRA records in the foreground.** `Activity.request` succeeded at the first durable checkpoint (`areActivitiesEnabled=true`). In 20 s of foreground recording the app sent 11 updates, one for each saved-through advance. Each `activity.update` returned in about 7 ms with the state `active`. The banner then showed the latest update ("Saved 2 sec ago"). | `app-log-T60Spike.txt` 15:49:20–15:49:42, `02-…jpg` |
| O2 | **No iPhone surface can show the activity while recording continues.** Pulling down Notification Centre made the app resign active, then **enter the background 1.9 s later** (3.6 s in an earlier run). Locking the device did the same. `CaptureScreen` pauses on background by design, so the banner switched to "Paused 0:25". The Dynamic Island compact view also appears only when JOVRA is not in the foreground. On the phone itself the activity can therefore only ever report a paused recording. | `cadence-foreground-springboard.txt`, `03-…jpg`, `04-…jpg`, app log 15:49:41–15:49:52 |
| O3 | **Text driven by the system clock keeps moving with no updates.** "Saved N sec ago" (relative style) counts up honestly. The unbounded REC timer kept counting to **0:53 while the recording had stopped at 0:05**, which is a fabricated number. The bounded `timerInterval` timer **froze at 0:14**, the last heartbeat plus 10 s, after the app was killed. | `07-…jpg`, `cadence-unbounded-timer-springboard.txt` + `app-log-T60Spike-unbounded-run.txt` (last heartbeat rec=4 at 15:45:03); `05-…jpg`, `cadence-after-kill-springboard.txt` |
| O4 | **`staleDate` never rendered "Status unknown".** No "Status unknown" appeared 74 s after the last update (stale date +10 s), while Notification Centre stayed on screen. This held when the app was backgrounded and when it was killed. On the simulator the 10 s "Status unknown" requirement is **not met** by ActivityKit's stale date alone. | `cadence-after-kill-springboard.txt`, `06-…jpg` |
| O5 | **A killed app leaves its activity on the Lock Screen.** It still read "REC 0:14 · Saved 1 min, 20 sec ago". The app ends any leftover activity before it starts a new one. | `06-…jpg`, app log 15:50:49 "ended 1 leftover activities" |
| O6 | **The Lock Screen is rendered ahead of time for Always-On.** Screenshots of the locked iPhone 17 Pro show the clock about 5 minutes ahead and "Saved 5 min ago", while the live accessibility text read "Saved 22 sec ago". Relative text is drawn for future always-on frames. | `04-…jpg` vs `cadence-foreground-springboard.txt` t+83 s |
| O7 | **iOS asks for permission.** The first activity raised "Allow Live Activities from JOVRA?". A later activity asked "continue to allow … Always Allow". Shipping the feature would add a permission moment to recording. | `02-…jpg` |
| O8 | **The simulator has no battery level**, so the activity showed "Battery unknown" and never invented a value. A real battery percentage can only be checked on a device. | all screenshots |
| O9 | **The copy is not exact.** The system's auto-updating relative style reads "Saved 9 sec ago", not "Saved 4 s ago", and the app cannot change that format. | all screenshots |

**The observed update cadence is one update per journal checkpoint, every 2.0 s (the fragment interval).** It
showed no throttling over 20 s on the simulator. Throttling on a device over a long session is UNVERIFIED.

A side observation, outside this ticket: when the app is backgrounded in the middle of a recording, the pause that
`CaptureScreen` requests finished 8.8 s later in one run. In another run it was still "Pausing recording" when the app
returned to the foreground. This matters for T15/T16 hardware testing; nothing was changed here.

## Decision: drop from v1

The spec's rule is: "if the spike shows the activity does not update while the app is foreground-recording, it is
dropped from v1 and noted, not faked." The simulator shows that updates are *accepted* while JOVRA records in the
foreground (O1), but four findings settle the decision against shipping:

1. **On the iPhone, the user cannot see it during a recording (O2).** The Lock Screen, Notification Centre and Dynamic Island all
   take JOVRA out of the foreground, and that pauses the recording. On the phone, "REC 32:10 · Saved 4 s ago" can never be
   seen while it is true.
2. **The required "Status unknown" after 10 s is not delivered (O4).** Without it, a crashed or killed recorder stays
   on the Lock Screen as "REC" (O5). That conflicts with hard rule 1 (honest analysis) and rule 9 (evidence, not claims).
3. **The only surface that adds value, the Apple Watch Smart Stack, is device-only.** No evidence about it can be
   gathered here.
4. **It adds a system permission prompt (O7)** to the record flow, for a surface that can only say "Paused" on the phone.

Story 376 therefore stays out of v1. In-app status (Session time, "Saved through mm:ss") remains the source of truth
for recording status.

## Reopen condition

The lead may file the follow-up implementation ticket, the only ticket allowed to add the widget target to
`ios/project.yml`, if a hardware run of the spike branch on an iPhone paired with an Apple Watch shows **all** of
the following:

1. The activity appears in the Watch Smart Stack and updates while the iPhone stays in the foreground and records.
2. A missing heartbeat is visible within about 15 s on every surface that shows the activity, either through
   `staleDate` or through a push-free alternative proved on the device.
3. The camera keeps recording when the activity is requested, which is when the iOS permission prompt appears over the
   recorder.

If the condition is met, the follow-up starts from the spike's design. That design keeps the REC timer bounded with
`Text(timerInterval: start...deadline)` (O3 mitigation), keeps "Saved … ago" in the relative style, and keeps
"Battery unknown" when no level is reported.

## UNVERIFIED (device-only)

- **Lock Screen on hardware:** rendering, Always-On behaviour and whether the stale date renders "Status unknown" on a real
  iPhone.
- **Apple Watch Smart Stack:** visibility, update cadence and the stale state while the iPhone records in the foreground.
- **Camera capture under the permission prompt:** whether the camera keeps running while the system's
  Live Activity permission prompt sits over the recorder.
- **Long sessions:** ActivityKit throttling over a session of up to 8 h, and the real battery percentage.
