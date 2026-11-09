# Labelling the benchmark recordings (V01)

The V track's gates (`docs/spec/vision-tickets.md`) are measured against labels a person made on real recordings.
This page is the how-to for making them. Authority: [ADR-0031](../adr/0031-automatic-analysis-in-v1-and-iphone-first.md);
footage rules: [real-footage.md](real-footage.md).

**Who labels.** The founder, on the build Mac. An agent must not open the founder's recordings in the tool or look at
their frames: that would send them to a model API. An agent may run the scorer and read label files, which hold times
and points only.

## What a label file is

`spec/benchmarks/labels/rec-<first 12 hex of the recording's SHA-256>.labels.json`, schema
`spec/schemas/benchmark-labels.schema.json`. It holds:

| Label | Fields |
|---|---|
| Hit | media time, player (near or far), stroke type (serve, forehand, backhand, volley, overhead, other, or not set) |
| Bounce | media time, image point, in play or dead ball (never a line call) |
| Rally | start and end media time |
| Camera position | the frame it starts on and the four doubles corners (far left, far right, near right, near left) |
| Hit candidates | audio onsets the tool offered, each pending, confirmed or rejected. Never ground truth |

It never holds a frame, audio, a file name, a path or a person's name. Times are the presentation time of the frame on
screen as a rational; image points are 0..1 from the top-left of the displayed picture (GLOSSARY, Court model).

## The split is fixed by the recording's hash

A recording's timeline is cut into 30 s windows. The held-out windows are the 30% (rounded, at least one, never all)
whose SHA-256 of `jovra.hashWindows.v1`, the recording hash and the window number is smallest. Nobody chooses them and
they exist before the first label: the tool writes the split into the label file when it creates it. Every other
window is a tuning window, so the two never overlap. Label held-out windows exactly like the rest; the timeline
hatches them only so you can see them.

## Labelling

```sh
scripts/benchmarks/label.sh /path/to/recording.mp4
```

The window shows the frame, a timeline and, on the right, every key. The line at the bottom says what the last key
did, or why it did nothing.

| Do this | Key |
|---|---|
| Play or pause; next / previous frame; 10 frames; 1 second | Space; → / ←; ⇧→ / ⇧←; ⌥→ / ⌥← |
| Slower / faster (0.25×, 0.5×, 1×, 2×) | - / = |
| Hit by the near / far player on this frame | H / J |
| Stroke type of the selected hit | 1 serve, 2 forehand, 3 backhand, 4 volley, 5 overhead, 6 other, 0 clear |
| Bounce: point at the ball's contact with the ground and press | B (with the pointer off the picture, B then click) |
| Bounce was a dead ball / in play | X |
| Rally starts / ends on this frame | [ / ] |
| Next court corner at the pointer; corner not visible; camera moved | C; V; M |
| Next / previous hit candidate; reject the candidate on this frame | N / P; R |
| Next / previous label; delete the selected label | . / ,; ⌫ |
| Undo; redo; save; open | ⌘Z; ⇧⌘Z; ⌘S; ⌘O |

The quick way through a match: **N** jumps to the next sound that might be a hit. If it is one, step to the contact
frame and press **H** or **J**, then its stroke number; if it is not (a bounce, a footstep, the next court), press
**R**, which also moves on. Mark bounces as you pass them. Mark the four corners once, and again after **M** wherever
the camera was moved.

Edits are saved as you make them; ⌘S saves at once. The tool reads the recording where it is and writes nothing but
the label file.

## Sealing a label file into the label set

```sh
scripts/benchmarks/seal-labels.sh spec/benchmarks/labels/rec-<hash>.labels.json
git add spec/benchmarks/labels && git commit
```

Sealing records the file's SHA-256, its split and its counts in `spec/benchmarks/labels/manifest.json`. It refuses a
file with an open rally, a file that is not consistent, and labels that were not made by a person on a recording.
`scripts/spec/validate.py` (CI job `spec`) re-hashes every sealed file, re-derives its split from the recording hash
and re-counts it, so a label file edited after sealing, or a hand-picked split, fails the build.

The set is `founderPending` until every target is met, and `complete` after:

| Recording | Target |
|---|---|
| Feb 2024 match (behind the baseline) | at least 300 hits and 150 bounces |
| Oct 4 2026 side view | at least 100 hits with a stroke type |
| Sep 29 2026 corner angle | the court corners of at least one camera position |

Only labels made on the original file count towards a target; a label file made on an excerpt may be sealed and
scored, but it does not count. `scripts/benchmarks/seal-labels.sh` with no argument prints the progress. **V02 to V07
may not turn a capability on while the set is `founderPending`.**

## Scoring a stage against labels

```sh
swift run --package-path ios/Packages/JovraMedia jovra-benchmark score \
  --labels spec/benchmarks/labels/rec-<hash>.labels.json --observations /path/to/observations.json
```

Observations are a stage's output in `spec/schemas/benchmark-observations.schema.json`: hits, bounces, rallies, court
corners and the ranges it analysed, whichever of these it produces. The scorer prints, for the tuning windows and the
held-out windows side by side and never combined:

- **hits**: precision, recall, recall for the near and the far player, timing MAE and bias, stroke accuracy;
- **bounces**: precision and recall on in-play bounces, timing MAE, placement error in display pixels (median, mean);
- **rally boundaries**: precision, recall and F1;
- **court corners**: mean and maximum corner error in display pixels;
- **coverage**: the share of each split the stage analysed. A label the stage never looked at still counts as missed.

A matched pair belongs to the split of its label, an unmatched observation to the split of its own time, so nothing
is counted in both. Tolerances default to 100 ms for hits and bounces and 1 s for rally boundaries
(`--hit-tolerance`, `--bounce-tolerance`, `--boundary-tolerance`, as `VALUE/TIMESCALE`); `--json` prints the rows as
JSON. The rule is written out in `spec/reference/jovra_ref/labels.py`, and `spec/fixtures/labels/L01` and `L02` are
worked by hand: both the Python reference and the Swift scorer must reproduce them.

Placement error is in pixels here. Metres on the court need the court model and a homography, which V02 and V07 add.
A benchmark record that gates a capability on these labels is a contract of the first ticket that gates on them.

## Checking the tool itself

```sh
swift test --package-path tools/label-tool        # the founder's flow through the real window, on the synthetic sample video
scripts/benchmarks/label-tool-ui-test.sh          # XCUITest on the built app (needs UI automation; runs in CI)
```
