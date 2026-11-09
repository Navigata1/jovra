# Synthetic multi-angle generator (S58)

One synthetic scene is recorded by a rig of up to six phones. That gives per-camera videos (coded and clean) and
their ground truth. Each phone has its own clock, so the rig covers:

- drift of 1-50 ppm, and 300 ppm as a stress case;
- 41 s restarts, with and without a capture journal;
- a late start, a knocked-tripod shake and a muted microphone;
- mixed 60/30/240 fps;
- VFR, rotated and HLG angles;
- no shared coverage, and opposite baselines with audio only.

The design, the clock model, the profiles and what is checked are on the module page:
[`spec/studio/modules/multiangle-generator.md`](../../../../spec/studio/modules/multiangle-generator.md).

```sh
python3 scripts/media/studio/multiangle/generate.py              # render into .cache/media/studio, write spec/studio/fixtures/media/multiangle
python3 scripts/media/studio/multiangle/generate.py --check      # verify every file; fail unless the committed ground truth reproduces
python3 scripts/media/studio/multiangle/generate.py --force --sha256-log run.txt   # two runs, then diff the lists
python3 scripts/media/studio/multiangle/recover.py               # every frame's match time from its barcode and the ground truth
python3 -m unittest discover -s scripts/media/studio/multiangle -p 'test_*.py' -v
```

It needs ffmpeg with libx264 and libx265, and Python 3.10+ with the standard library only.

It reuses S08 (`jovra_studio_media`: barcode, clicks, badge, pipeline), T10's renderer core, T11's court scene and
play, and syncfit's sound-delay rule. It edits none of them.

Media is never committed. It is written to the git-ignored cache, keyed by the generator's source hash, and the
Studio workflow's added-binary check fails on any media file a branch adds.

| File | Role |
|---|---|
| `generate.py` | The generator CLI. It renders through S08's pipeline, then decodes every file in full and checks the barcodes, clicks, VFR times, rotation and painted frame times. It writes the ground truth. |
| `recover.py` | Recovers each coded frame's match time from its barcode and the committed ground truth alone, and each click's light time through the sound delays. |
| `jovra_multiangle/rig.py` | The placements, the camera spec and the camera clock (host clock, drift, segments, shake). |
| `jovra_multiangle/scene.py` | The scene: the first 120 s of T11's sample play, as events with light times and court positions. |
| `jovra_multiangle/profiles.py` | The cameras and the eleven named profiles. |
| `jovra_multiangle/clips.py` | The painter (the scene at each frame's true match time) and the S08 `StudioClip` for each file. |
| `jovra_multiangle/truth.py` | The ground-truth documents, the rig tables and the source hash. |
| `test_multiangle_truth.py` | Ground-truth tests, with no media needed: the research 4.4 delays, each profile's condition, hand-worked frame times, shake marks and determinism. |
| `test_multiangle_media.py` | Recovery of every frame, mutations that must be caught, the two-run byte identity, and the check that no media is committed. |

This folder is not a Python package. The S08 `unittest discover -s scripts/media/studio` run and the core
`-s scripts/media` run therefore do not pick these tests up. The Studio workflow runs them in its own step.
