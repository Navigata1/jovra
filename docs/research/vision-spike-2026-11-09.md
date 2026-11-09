# Analysis spike 1: what Apple's built-in Vision models give on real match footage

Date: 2026-11-09. Evidence class: **local host measurement** on a Mac, one recording, no ground-truth labels.
These numbers size the problem. They are not accuracy results and they gate nothing.

## Input

The founder's February 2024 match (night, floodlit hard court, camera high behind the near baseline, singles), window
14:00–16:00. Two encodings of the same window: the 1280×720 30 fps excerpt and the 1920×1080 original. See
`docs/fixtures/real-footage.md` for hashes. The footage stayed on the Mac. The tools print aggregate numbers only and
write no frames.

## Method

A Swift command-line tool decodes the window with `AVAssetReader` and runs, per frame:

- `VNDetectHumanBodyPoseRequest` (full frame, then restricted to the far part of the court),
- `VNDetectHumanRectanglesRequest` (full body, every third frame),
- one stateful `VNDetectTrajectoriesRequest` (trajectory length 5, radius 0.0015–0.02 of the frame).

## Results

| Measure | 720p | 1080p |
| --- | --- | --- |
| Frames with a body pose | 88.7% | 88.7% |
| Frames where the largest body has both wrists above 0.3 confidence | 44.9% | 47.1% |
| Median height of the largest body, as a fraction of the frame | 0.25 | 0.25 |
| Frames with two or more body poses | 0% | 0% |
| Frames with two or more person rectangles | 0% | 0% |
| Most people found in any frame | 1 | 1 |
| Frames with a pose inside the far-court region | 0.2–12.9% (depends on the crop) | 0.5% |
| Trajectories reported in 120 s | 11,676 | 15,966 |
| Pose processing speed on the Mac | 128 fps | 117 fps |

## What this means

1. **Near player: usable today.** The built-in pose model holds the near player in about nine frames out of ten at
   faster than real time on a Mac. On-device speed on an iPhone is unmeasured.
2. **Wrists are the weak joint.** With the player's back to the camera, both wrists are confident in under half the
   frames. Stroke classification (V06) cannot rely on wrists alone; it needs shoulders, hips, elbows and timing.
3. **Far player: invisible to built-in models.** Neither the pose model nor the person-rectangle model ever returned a
   second person, at either resolution. V03 needs a small-person detector run at native resolution or on a court-aware
   crop, then pose on the upscaled crop if the pixels allow.
4. **Ball: built-in trajectories are noise here.** Roughly 100 "trajectories" a second on a clip with a few dozen
   shots means the detector is firing on players, lights and neighbouring courts. This confirms
   `docs/research/technical-feasibility.md` §7: match footage needs a trained heatmap ball detector (V04).
   `VNDetectTrajectoriesRequest` stays a candidate only for side-on practice clips, which this spike did not test.
5. **Resolution did not help the built-in models.** 1080p changed none of the conclusions. That says nothing yet about
   a trained detector, where far-court ball size in pixels matters directly.

## Limits

One recording, one two-minute window, 30 fps source, no labels. "Body found" does not prove the body is the near
player rather than someone on a neighbouring court. Nothing was measured on a phone.
