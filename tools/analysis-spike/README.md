# Analysis spike tools

Two throwaway Swift command-line tools behind `docs/research/vision-spike-2026-11-09.md`. They run Apple Vision over a
local video file and print aggregate numbers. They write no frames and make no network calls.

```sh
mkdir -p /tmp/spike && cp tools/analysis-spike/pose_trajectory_spike.swift /tmp/spike/main.swift
swiftc -O -swift-version 5 -o /tmp/spike/pose /tmp/spike/main.swift
/tmp/spike/pose <video> <startSeconds> <durationSeconds>
ROI_Y0=0.55 /tmp/spike/pose <video> <startSeconds> <durationSeconds>   # pose only, far part of the frame
```

`person_rect_spike.swift` builds the same way. These are measurement scripts, not product code. V00 replaces them with
the `JovraVision` package and V01 with a scorer that has ground truth.
