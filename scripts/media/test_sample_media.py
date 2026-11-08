"""Tests for the synthetic sample media and the benchmark corpus (T11). They read the rendered cache, so run
``python3 scripts/media/render.py`` first (CI's media-fixtures job renders, then runs these):

    python3 -m unittest discover -s scripts/media -p 'test_*.py' -v
"""

from __future__ import annotations

import ast
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

import render  # noqa: E402
from jovra_media import truth as truth_mod  # noqa: E402
from jovra_media.label import BANNER, INK, Label  # noqa: E402
from jovra_media.sets import corpus, sample  # noqa: E402

TRUTH = ROOT / "spec" / "fixtures" / "media"
MANIFEST = json.loads((ROOT / sample.MANIFEST).read_text(encoding="utf-8"))
HAVE_FFMPEG = shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None


def truths(set_name: str) -> list[dict]:
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted((TRUTH / set_name).glob("*.truth.json"))]


def media(doc: dict) -> Path:
    path = ROOT / doc["media"]["path"]
    if not path.exists():
        raise unittest.SkipTest(f"{doc['media']['path']} is not rendered: run python3 scripts/media/render.py")
    return path


def decoded_luma(path: Path, frame: int, rate: Fraction, width: int, height: int) -> bytes:
    """The luma plane of one frame, by accurate seek to its presentation time."""
    t = Fraction(frame) / rate
    out = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", f"{float(t):.6f}", "-i", str(path),
                          "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1"],
                         capture_output=True, check=True).stdout
    if len(out) != width * height:
        raise AssertionError(f"{path.name} frame {frame}: decoded {len(out)} bytes")
    return out


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class SampleMediaTests(unittest.TestCase):
    def test_every_manifest_media_id_has_a_rendered_file_of_its_duration_and_frame_rate(self):
        by_id = {d["sampleMedia"]["mediaId"]: d for d in truths("sample")}
        self.assertEqual(sorted(by_id), sorted(m["mediaId"] for m in MANIFEST["media"]))
        for m in MANIFEST["media"]:
            with self.subTest(m["mediaId"]):
                path = media(by_id[m["mediaId"]])
                self.assertEqual(path.name, m["fileName"])
                probe = json.loads(subprocess.run(
                    ["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets", "-show_entries",
                     "stream=width,height,r_frame_rate,nb_read_packets,duration_ts,time_base", "-of", "json", str(path)],
                    capture_output=True, text=True, check=True).stdout)["streams"][0]
                rate = Fraction(probe["r_frame_rate"])
                self.assertEqual(rate, Fraction(m["frameRate"]["num"], m["frameRate"]["den"]))
                self.assertEqual((probe["width"], probe["height"]), (m["width"], m["height"]))
                frames = int(probe["nb_read_packets"])
                self.assertEqual(Fraction(frames) / rate * 1000, m["durationMs"])
                audio = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=codec_name",
                                        "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True).stdout.strip()
                self.assertEqual(audio == "aac", m["hasAudio"])

    def test_bundled_sample_media_is_within_the_60_mb_budget(self):
        total = sum(media(d).stat().st_size for d in truths("sample"))
        print(f"\nbundled sample media: {total:,} bytes = {total / 1_000_000:.2f} MB of {sample.BUDGET_BYTES / 1_000_000:.0f} MB")
        self.assertLessEqual(total, sample.BUDGET_BYTES)
        jon_vs_alex = next(d for d in truths("sample") if d["sampleMedia"]["mediaId"] == "sample-media.jon-vs-alex")
        entry = next(m for m in MANIFEST["media"] if m["mediaId"] == "sample-media.jon-vs-alex")
        self.assertEqual(entry["coversSessionMs"], {"fromMs": 0, "toMs": 3_240_000}, "full 54:00 mode, not excerpt mode")
        self.assertEqual(jon_vs_alex["video"]["frameCount"], 3_240 * 60)

    def test_every_sampled_frame_carries_the_visible_synthetic_label(self):
        """Every lit pixel of the label decodes as ink and the banner around the glyphs as background, on
        frames spread across each clip (first, last and ten between; the match also at every point start)."""
        for doc in truths("sample"):
            v = doc["video"]
            rate = Fraction(v["frameRate"]["num"], v["frameRate"]["den"])
            label = Label(v["codedWidth"], v["codedHeight"], v["codedHeight"] // doc["signature"]["rows"])
            self.assertEqual(label.truth(), doc["label"])
            lit = label.lit_pixels()
            ink = {(x + i, y + j) for x, y, w, h in lit for i in range(w) for j in range(h)}
            near_ink = {(x + dx, y + dy) for x, y in ink for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
            region = label.region
            background = [(x, y) for y in range(region["height"]) for x in range(label.scale + 1, region["width"])
                          if (x, y) not in near_ink]
            n = v["frameCount"]
            frames = sorted({0, n - 1, *(n * k // 11 for k in range(1, 11))})
            for frame in frames:
                with self.subTest(clip=doc["id"], frame=frame):
                    luma = decoded_luma(media(doc), frame, rate, v["codedWidth"], v["codedHeight"])
                    w = v["codedWidth"]
                    dark_ink = [p for p in ink if luma[p[1] * w + p[0]] < INK.y - 48]
                    self.assertLessEqual(len(dark_ink), len(ink) // 50, "label glyphs are missing or smeared")
                    bright = [p for p in background if luma[p[1] * w + p[0]] > BANNER.y + 48]
                    self.assertLessEqual(len(bright), len(background) // 50, "label banner is covered")

    def test_the_renderer_draws_primitives_only(self):
        """No image, font, photograph or network input: the scene modules import nothing that could load
        one, and the only files a set reads are its declared INPUTS (data, never pixels)."""
        modules = ["court3d.py", "label.py", "animation.py", "play.py", "canvas.py", "sets/sample.py", "sets/corpus.py"]
        banned_imports = {"PIL", "cv2", "imageio", "urllib", "requests", "http", "socket", "subprocess", "matplotlib"}
        banned_text = re.compile(r"\.(png|jpe?g|gif|heic|webp|ttf|otf|woff2?|svg)\b", re.I)
        for name in modules:
            with self.subTest(name):
                source = (HERE / "jovra_media" / name).read_text(encoding="utf-8")
                tree = ast.parse(source)
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        names = [a.name.split(".")[0] for a in node.names]
                    elif isinstance(node, ast.ImportFrom):
                        names = [(node.module or "").split(".")[0]]
                    else:
                        continue
                    self.assertFalse(set(names) & banned_imports, f"{name} imports {names}")
                self.assertIsNone(banned_text.search(source), f"{name} names an image or font file")
                reads = re.findall(r"\(ROOT / (\w+)\)\.read_", source)
                self.assertNotIn("open(", source.replace("wave.open", ""))
                for constant in reads:
                    self.assertIn(constant, ("MANIFEST", "POINTS"), f"{name} reads {constant}")
        self.assertEqual(sample.INPUTS, (sample.MANIFEST, sample.POINTS))

    def test_two_runs_render_identical_ground_truth_and_hashes(self):
        """The same clip rendered twice from scratch into two caches yields byte-identical ground truth
        (decoded-frame hash and source-frame hash included). CI repeats this for every clip on Ubuntu
        against the committed truth (render.py --check)."""
        clip = next(c for c in sample.clips() if c.id == "2026-09-28-serve-clip")
        texts = []
        for _ in range(2):
            with tempfile.TemporaryDirectory() as cache:
                text, _ = render.clip_truth(sample, clip, Path(cache), True, lambda line: None)
                doc = json.loads(text)
                doc["media"]["path"] = doc["media"]["path"].split("/", 2)[2]   # the temporary cache root differs
                texts.append(truth_mod.dumps(doc))
        self.assertEqual(texts[0], texts[1])
        committed = json.loads((TRUTH / "sample" / "2026-09-28-serve-clip.truth.json").read_text(encoding="utf-8"))
        self.assertEqual(json.loads(texts[0])["signature"], committed["signature"])


class CorpusTests(unittest.TestCase):
    def test_manifest_lists_tuning_and_held_out_seeds_separately_with_two_hours_of_no_nudge_footage(self):
        doc = json.loads((ROOT / corpus.MANIFEST_PATH).read_text(encoding="utf-8"))
        tuning = {c["seed"] for c in doc["splits"]["tuning"]}
        held_out = {c["seed"] for c in doc["splits"]["heldOut"]}
        self.assertFalse(tuning & held_out)
        self.assertGreaterEqual(doc["totals"]["noNudgeMs"]["all"], 2 * 60 * 60 * 1000)
        self.assertGreater(doc["totals"]["noNudgeMs"]["heldOut"], 0)
        for kind in corpus.KINDS:
            for split in ("tuning", "heldOut"):
                self.assertTrue(any(c["kind"] == kind for c in doc["splits"][split]), f"{kind} has no {split} clip")
        expected = corpus.manifest({d["id"].split("/")[1]: d for d in truths("corpus")})[1]
        self.assertEqual(doc, expected)

    def test_nudges_are_one_degree_and_neighbour_clicks_stay_clear_of_hits(self):
        for doc in truths("corpus"):
            hits = [e["sample"] for e in doc.get("events", [])]
            for d in doc.get("distractors", []):
                self.assertTrue(all(abs(d["sample"] - h) >= corpus.DISTRACTOR_GAP for h in hits))
            for m in doc.get("cameraMoves", []):
                self.assertEqual(abs(m["yawDegrees"]) + abs(m["pitchDegrees"]), 1)

    def test_a_one_degree_nudge_moves_the_court_by_the_expected_pixels(self):
        """1 degree of yaw at focal length f moves the centre of the picture by f * tan(1 deg) pixels."""
        cam = corpus.camera(640, 360)
        before = cam.project((0.0, 11.885, 0.0))
        after = cam.nudged(yaw=1).project((0.0, 11.885, 0.0))
        self.assertAlmostEqual(abs(after[0] - before[0]), cam.focal * 0.017455064928217585, delta=1.5)


if __name__ == "__main__":
    unittest.main()
