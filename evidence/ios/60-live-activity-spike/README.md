# T60 Live Activity spike: simulator evidence

The decision report is [`docs/spikes/live-activity.md`](../../../docs/spikes/live-activity.md). The decision is to **drop it from v1**.

**What produced this evidence.** The evidence comes from the throwaway branch `ticket/t60-live-activity-spike-throwaway`
(commit `3e265ba`), tested with `LiveActivitySpikeUITests` and `RecordingLiveActivityPolicyTests`. The setup was:

- the iOS 27.2 simulator on an iPhone 17 Pro, named `JOVRA-T60` (UDID `001D1321-0519-4155-AB46-0BCB204C77DA`);
- Xcode 27.2 (27B52);
- the fixture camera, so every capture is **Sample** data.

None of it ran on hardware.

**Commands.** All were run on the spike branch from the worktree root:

```sh
scripts/ios/generate.sh
xcodebuild test -project ios/Jovra.xcodeproj -scheme Jovra \
  -only-testing:JovraTests/RecordingLiveActivityPolicyTests \
  -destination id=001D1321-0519-4155-AB46-0BCB204C77DA -derivedDataPath .derivedData JOVRA_SKIP_SAMPLE_MEDIA=YES
#   6 tests, 0 failures (red first: "cannot find 'RecordingLiveActivityPolicy' in scope")
xcodebuild test ... -only-testing:JovraUITests/LiveActivitySpikeUITests
#   2 tests, 0 failures (observation tests; they record, they do not gate)
xcrun simctl spawn <udid> log stream --style compact --predicate 'category == "T60Spike"'
```

| File | What it shows |
|---|---|
| `01-app-foreground-recording.jpg` | JOVRA recording in the foreground (Sample fixture, "Saved through 00:22"). |
| `02-notification-centre-over-recording.jpg` | Notification Centre pulled over the recorder. The activity reads "REC 0:26 · Saved 2 sec ago · Battery unknown · Sample", above the iOS permission prompt. |
| `03-notification-centre-after-backgrounding-paused.jpg` | The same banner about 8 s later. iOS has backgrounded JOVRA, the recording paused, and the banner reads "Paused 0:25". |
| `04-lock-screen-paused-always-on-prerender.jpg` | The Lock Screen after locking. It shows "Paused" in the Always-On frame, which is pre-rendered with the clock about 5 minutes ahead. |
| `05-after-kill-rec-frozen.jpg` | The app was killed mid-recording. The bounded REC timer has frozen at 0:14 (last heartbeat plus 10 s). |
| `06-after-kill-74s-no-status-unknown.jpg` | 74 s after the last update, the stale date still has **not** rendered "Status unknown". |
| `07-unbounded-rec-timer-overstates.jpg` | The earlier, unbounded timer reads "REC 0:41" after the recording stopped at about 0:05. |
| `cadence-foreground-springboard.txt` | SpringBoard's accessible text for the activity, sampled about every 1.3 s over a foreground recording, then after locking. |
| `cadence-after-kill-springboard.txt` | The same sampling after the app is killed, about 74 s with no "Status unknown". |
| `cadence-unbounded-timer-springboard.txt` | The same sampling for the unbounded-timer run. |
| `app-log-T60Spike.txt` | The app log for the main run: request and updates every 2.0 s, lifecycle (resign active, then background 1.9 s later), and the pause. |
| `app-log-T60Spike-unbounded-run.txt` | The app log for the unbounded-timer run. The last heartbeat was rec=4 at 15:45:03, followed by background 3.6 s after Notification Centre opened. |

UNVERIFIED (device-only): the Lock Screen on hardware, the Apple Watch Smart Stack, stale rendering on a device,
whether capture continues under the permission prompt, long-session throttling and the real battery percentage.
