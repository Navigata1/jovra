"""Media tests of the synthetic multi-angle generator (S58). They read the rendered cache, so render first (the Studio
workflow's studio-media job does):

    python3 scripts/media/studio/multiangle/generate.py
    python3 -m unittest discover -s scripts/media/studio/multiangle -p 'test_*.py' -v

A test whose media is not rendered is skipped with the command to run. The two-run test renders its own files.
"""

from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
for _p in (HERE, HERE.parent, HERE.parents[1], ROOT / "spec" / "reference"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import check_added_binaries  # noqa: E402
import generate  # noqa: E402
import recover  # noqa: E402
from jovra_multiangle import truth  # noqa: E402

TRUTH = ROOT / "spec" / "studio" / "fixtures" / "media" / "multiangle"
HAVE_FFMPEG = shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None


def doc(pid: str) -> dict:
    return json.loads((TRUTH / f"{pid}.json").read_text(encoding="utf-8"))


def require_rendered(d: dict) -> None:
    for c in d["cameras"]:
        for s in c["segments"]:
            for f in s["files"]:
                if not (ROOT / f["path"]).is_file():
                    raise unittest.SkipTest(f"{f['path']} is not rendered: run python3 "
                                            "scripts/media/studio/multiangle/generate.py")


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class RecoveryTests(unittest.TestCase):
    """Acceptance: reading the embedded ids from each generated camera and applying the ground-truth map recovers
    the true match time of every frame within half an output frame."""

    def test_every_frame_of_every_coded_camera_recovers_its_painted_match_time(self):
        files = frames = 0
        for pid in recover.profile_ids():
            d = doc(pid)
            require_rendered(d)
            for c in d["cameras"]:
                for s in c["segments"]:
                    with self.subTest(profile=pid, camera=c["cameraId"], segment=s["segment"]):
                        r = recover.recover_file(d, c["cameraId"], s["segment"])
                        self.assertEqual(r["frames"], s["frameCount"])
                        self.assertLessEqual(r["maxFrameErrorUs"], 1.0, "an exact map leaves only rounding")
                        self.assertLessEqual(r["maxLightTimeErrorUs"], recover.LIGHT_TOLERANCE_US)
                        files += 1
                        frames += r["frames"]
        self.assertGreaterEqual(files, 31)
        self.assertGreater(frames, 80_000)

    def test_a_ground_truth_one_output_frame_off_is_caught(self):
        d = doc("drift-default")
        require_rendered(d)
        bad = copy.deepcopy(d)
        cam = next(c for c in bad["cameras"] if c["cameraId"] == "cnw-drift")
        off = recover.exact(cam["segments"][0]["transform"]["offsetUs"]) + Fraction(1_000_000, 30)
        cam["segments"][0]["transform"]["offsetUs"] = {"num": off.numerator, "den": off.denominator}
        with self.assertRaisesRegex(recover.RecoveryError, "more than half an output frame"):
            recover.recover_file(bad, "cnw-drift", 0)

    def test_a_ground_truth_drift_wrong_by_300_ppm_is_caught_late_in_the_file(self):
        d = doc("drift-stress-300ppm")
        require_rendered(d)
        bad = copy.deepcopy(d)
        cam = next(c for c in bad["cameras"] if c["cameraId"] == "cse-stress")
        cam["segments"][0]["transform"]["rate"] = {"num": 1_000_000_000, "den": 1_000_000_000}
        with self.assertRaisesRegex(recover.RecoveryError, "frame (\\d+).*more than half an output frame"):
            recover.recover_file(bad, "cse-stress", 0)

    def test_a_vfr_file_described_as_cfr_is_caught(self):
        d = doc("vfr-rotated-hdr")
        require_rendered(d)
        bad = copy.deepcopy(d)
        next(c for c in bad["cameras"] if c["cameraId"] == "bn-vfr")["frameTiming"] = {"kind": "cfr"}
        with self.assertRaisesRegex(recover.RecoveryError, "presented at"):
            recover.recover_file(bad, "bn-vfr", 0)

    def test_a_wrong_sound_delay_is_caught_through_the_audio(self):
        d = doc("opposite-baseline-audio-only")
        require_rendered(d)
        bad = copy.deepcopy(d)
        cam = next(c for c in bad["cameras"] if c["cameraId"] == "bn-covered")
        next(a for a in cam["audioArrivals"] if a["heard"])["delayUs"] += 1_000
        with self.assertRaisesRegex(recover.RecoveryError, "maps to light time"):
            recover.recover_file(bad, "bn-covered", 0)

    def test_restarted_segments_are_each_recovered_through_their_own_piece(self):
        for pid, cid in (("restart-41s-journal", "cne-restart-journal"), ("restart-41s-no-journal", "cnw-restart-import")):
            d = doc(pid)
            require_rendered(d)
            bad = copy.deepcopy(d)
            cam = next(c for c in bad["cameras"] if c["cameraId"] == cid)
            cam["segments"][1]["transform"] = cam["segments"][0]["transform"]    # forget the restart
            with self.assertRaisesRegex(recover.RecoveryError, "more than half an output frame"):
                recover.recover_file(bad, cid, 1)


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class TwoRunTests(unittest.TestCase):
    """Acceptance: two runs produce byte-identical media and unchanged ground-truth files (one restarted camera, both
    segments and both variants, rendered twice from scratch into separate caches)."""

    def test_two_forced_renders_are_byte_identical_and_reproduce_the_committed_hashes(self):
        src_hash = truth.source_hash()
        committed = doc("restart-41s-no-journal")["hashes"]
        if committed["renderedWithSourceHash"] != src_hash:
            self.skipTest("the committed hashes are from another generator source: run generate.py")
        runs = []
        for _ in range(2):
            with tempfile.TemporaryDirectory() as cache:
                run = {}
                for cid, k, variant in generate.jobs_for(["cnw-restart-import"]):
                    r = generate._render_one((cid, k, variant, src_hash, cache, True))
                    self.assertNotIn("error", r, r.get("error"))
                    run[r["file"]] = (r["sha256"], r["hashes"])
                runs.append(run)
        self.assertEqual(len(runs[0]), 4)
        self.assertEqual({f: s for f, (s, _) in runs[0].items()}, {f: s for f, (s, _) in runs[1].items()})
        for name, (_, hashes) in runs[0].items():
            self.assertEqual(hashes, committed["files"][name], name)


class NoMediaCommittedTests(unittest.TestCase):
    """Acceptance: no generated media is committed (the cache is git-ignored; the ground truth folder holds JSON)."""

    def test_every_media_path_is_inside_the_git_ignored_cache(self):
        paths = [f["path"] for pid in recover.profile_ids() for c in doc(pid)["cameras"] for s in c["segments"]
                 for f in s["files"]]
        self.assertTrue(paths and all(p.startswith(".cache/media/studio/multiangle-") for p in paths))
        ignored = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--no-index", *paths[:5]],
                                 capture_output=True, text=True)
        self.assertEqual(ignored.stdout.split(), paths[:5])

    def test_the_ground_truth_folder_holds_no_media(self):
        for path in TRUTH.iterdir():
            self.assertEqual(path.suffix, ".json", path.name)
            self.assertIsNone(check_added_binaries.media_kind(ROOT, path.relative_to(ROOT).as_posix()), path.name)

    def test_the_added_binary_check_flags_a_rendered_camera_file(self):
        d = doc("late-start")
        require_rendered(d)
        f = d["cameras"][1]["segments"][0]["files"][0]
        with tempfile.TemporaryDirectory() as tmp:
            disguised = Path(tmp) / "ground-truth.json"
            shutil.copyfile(ROOT / f["path"], disguised)
            self.assertIsNotNone(check_added_binaries.media_kind(Path(tmp), disguised.name), "sniffed by its bytes")


if __name__ == "__main__":
    unittest.main()
