"""End-to-end tests of the Studio media fixtures (S08). They read the rendered cache, so run the generator first
(the Studio workflow's studio-media job renders, then runs these):

    python3 scripts/media/studio/render_studio.py
    python3 -m unittest discover -s scripts/media/studio -p 'test_*.py' -v

A test whose media is not rendered is skipped with the command to run; tests that need no media always run.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(ROOT / "spec" / "reference"))

import check_added_binaries  # noqa: E402
import install_demo  # noqa: E402
import reader  # noqa: E402
from jovra_studio_media import barcode as bc  # noqa: E402
from jovra_studio_media import pipeline  # noqa: E402

MEDIA = ROOT / "spec" / "studio" / "fixtures" / "media"
HAVE_FFMPEG = shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None


def manifest(set_name: str, clip_id: str) -> dict:
    return json.loads((MEDIA / set_name / f"{clip_id}.json").read_text(encoding="utf-8"))


def manifests(role: str | None = None) -> list[dict]:
    docs = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(MEDIA.rglob("*.json")) if p.name != "demo-subset.json"]
    return [d for d in docs if role is None or d["role"] == role]


def media(doc: dict) -> Path:
    path = ROOT / doc["media"]["path"]
    if not path.exists():
        raise unittest.SkipTest(f"{doc['media']['path']} is not rendered: run python3 scripts/media/studio/render_studio.py")
    return path


class MatchFoldTests(unittest.TestCase):
    def test_the_coherent_match_point_events_fold_to_six_four_six_three(self):
        from jovra_ref import scoring
        m = manifest("match", "match-jon-vs-alex")["match"]
        result = scoring.fold(m["setup"], m["log"])
        # Hand-checked literal: the core Jon vs Alex sample is 6-4 6-3 to Jon (side A), 124 points.
        self.assertEqual(result["match"]["scoreline"], "6-4 6-3")
        self.assertEqual(result["match"]["winner"], "A")
        self.assertEqual(result["match"]["pointsPlayed"], 124)
        self.assertEqual(m["expected"]["scoreline"], "6-4 6-3")


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class BarcodeReaderTests(unittest.TestCase):
    def test_reader_recovers_every_frame_id_of_the_24_30_and_60_fps_sources(self):
        for clip_id, frames in (("bc-024", 240), ("bc-030", 300), ("bc-060", 600)):
            with self.subTest(clip_id):
                doc = manifest("barcodeSources", clip_id)
                report = reader.compare_to_map(media(doc), doc)
                self.assertEqual((report.frames, report.matched, report.mismatches), (frames, frames, []))

    def test_the_restarted_segment_reads_session_frame_ids_after_the_gap(self):
        doc = manifest("barcodeSources", "bc-030-restart-seg1")
        width, height = reader.probe_size(media(doc))
        reads = [got for _, got in reader.read_frames(media(doc), width, height, reader.rect_of(doc))]
        self.assertEqual(reads[0], bc.Payload(4, 1, 195))
        self.assertEqual(reads[-1], bc.Payload(4, 1, 344))

    def test_flipping_one_barcode_bit_in_a_scratch_copy_is_reported_as_a_mismatch(self):
        """Decode bc-030, flip bit 20 of frame 100's barcode in a scratch copy, re-encode it, read it back: exactly
        that frame is reported, and the original still reads clean."""
        doc = manifest("barcodeSources", "bc-030")
        source = media(doc)
        w, h = doc["video"]["width"], doc["video"]["height"]
        x, y, bw, bh = bc.block(reader.rect_of(doc), 20)
        with tempfile.TemporaryDirectory() as tmp:
            raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(source), "-f", "rawvideo",
                                  "-pix_fmt", "yuv420p", "pipe:1"], capture_output=True, check=True).stdout
            frame_bytes = w * h * 3 // 2
            frames = bytearray(raw)
            base = 100 * frame_bytes
            centre = frames[base + (y + bh // 2) * w + x + bw // 2]
            flipped = 16 if centre > 128 else 235
            for row in range(y, y + bh):
                frames[base + row * w + x: base + row * w + x + bw] = bytes([flipped]) * bw
            scratch = Path(tmp) / "bc-030-flipped.mp4"
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "yuv420p",
                            "-s", f"{w}x{h}", "-framerate", "30", "-i", "pipe:0", "-c:v", "libx264", "-crf", "18",
                            "-pix_fmt", "yuv420p", str(scratch)], input=bytes(frames), check=True)
            report = reader.compare_to_map(scratch, doc)
        self.assertEqual([m[0] for m in report.mismatches], [100])
        self.assertIn("CRC", str(report.mismatches[0][2]))
        self.assertTrue(reader.compare_to_map(source, doc).ok)

    def test_a_plan_one_frame_off_mismatches_every_frame(self):
        doc = manifest("barcodeSources", "bc-024")
        shifted = [bc.Payload(p.source, p.segment, p.frame + 1) for p in reader.expected_payloads(doc)]
        report = reader.compare_to_map(media(doc), doc, expected=shifted)
        self.assertEqual(report.matched, 0)
        self.assertEqual(len(report.mismatches), 240)

    def test_match_and_broll_barcodes_read_on_every_frame(self):
        for doc in manifests("broll") + manifests("match"):
            with self.subTest(doc["id"]):
                report = reader.compare_to_map(media(doc), doc)
                self.assertTrue(report.ok, report.mismatches[:3])
                self.assertEqual(report.frames, doc["video"]["frameCount"])


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class ClickDetectionTests(unittest.TestCase):
    def test_every_click_is_found_within_one_frame_of_its_truth_and_no_extra(self):
        docs = [d for d in manifests() if d["clicks"] is not None]
        self.assertGreaterEqual(len(docs), 9)
        for doc in docs:
            with self.subTest(doc["id"]):
                found, count = pipeline.decoded_audio(media(doc))
                truth = doc["clicks"]["events"]
                self.assertEqual(len(found), len(truth), "a click is missing or extra")
                fps = Fraction(doc["video"]["frameRate"]["num"], doc["video"]["frameRate"]["den"])
                for got, want in zip(found, truth):
                    self.assertLessEqual(abs(int(Fraction(got, 48_000) * fps) - want["frame"]), 1)
                self.assertLessEqual(abs(count - doc["audio"]["sampleCount"]), 1024)

    def test_the_silent_variant_has_no_audio_track(self):
        doc = manifest("barcodeSources", "bc-030-silent")
        self.assertEqual(pipeline.audio_streams(media(doc)), [])
        self.assertIsNone(doc["clicks"])


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class LabelTests(unittest.TestCase):
    def test_every_sampled_frame_of_the_angle_renders_and_broll_carries_its_labels(self):
        docs = manifests("angle") + manifests("broll")
        self.assertEqual(len(docs), 9)
        for doc in docs:
            with self.subTest(doc["id"]):
                kinds = [label["kind"] for label in doc["labels"]]
                self.assertIn("sample", kinds)
                if doc["role"] == "angle":
                    self.assertIn("angle", kinds)
                frames = reader.sample_frames(doc["video"]["frameCount"], 12)
                self.assertEqual(reader.check_labels(media(doc), doc, frames), [])

    def test_a_frame_without_the_label_fails_the_check(self):
        doc = manifest("barcodeSources", "bc-030")   # a barcode source carries no Sample label
        entry = manifest("broll", "broll-court-push")["labels"][0]
        luma = reader.frame_luma(media(doc), 10, Fraction(30), 1280, 720)
        self.assertTrue(reader.label_failures(luma, 1280, 720, dict(entry)))


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class DemoSubsetTests(unittest.TestCase):
    def test_the_demo_subset_installs_within_its_budget(self):
        subset = json.loads((MEDIA / "demo-subset.json").read_text(encoding="utf-8"))
        for entry in subset["files"]:
            media(json.loads((ROOT / "spec" / "studio" / "fixtures" / entry["manifest"]).read_text(encoding="utf-8")))
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "StudioSampleMedia"
            (dest).mkdir()
            # A file a previous install wrote (it is in that install's index) is replaced or removed.
            (dest / "stale.mp4").write_bytes(b"old")
            (dest / "studio-sample-media.json").write_text(json.dumps({"files": [{"fileName": "stale.mp4"}]}),
                                                           encoding="utf-8")
            total, problems = install_demo.install(dest)
            self.assertEqual(problems, [])
            names = sorted(p.name for p in dest.iterdir())
            du_k = int(subprocess.run(["du", "-sk", str(dest)], capture_output=True, text=True, check=True).stdout.split()[0])
            print(f"\ndemo subset: {total:,} bytes, du -sk {du_k} KiB, budget {subset['budgetBytes']:,} bytes")
        self.assertLessEqual(total, 25_000_000)
        self.assertLessEqual(du_k * 1024, 25_000_000 + 64 * 1024)
        self.assertEqual(names, sorted([f["fileName"] for f in subset["files"]] + ["studio-sample-media.json"]))


class InstallDestinationGuardTests(unittest.TestCase):
    """The installer only ever deletes files it wrote itself. These need no media: the destination is checked
    before anything is read from the render cache, and a refused install touches nothing."""

    def assert_refused(self, dest: Path, reason: str) -> None:
        before = sorted(str(p.relative_to(dest)) for p in dest.rglob("*")) if dest.exists() else []
        total, problems = install_demo.install(dest)
        self.assertTrue(problems, "the install should have been refused")
        self.assertIn(reason, " ".join(problems))
        after = sorted(str(p.relative_to(dest)) for p in dest.rglob("*")) if dest.exists() else []
        self.assertEqual(after, before)

    def test_a_destination_not_named_studio_sample_media_is_refused_and_left_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "Resources"
            (dest / "Assets.xcassets").mkdir(parents=True)
            (dest / "Assets.xcassets" / "Contents.json").write_text("{}", encoding="utf-8")
            (dest / "Info.plist").write_text("<plist/>", encoding="utf-8")
            self.assert_refused(dest, "StudioSampleMedia")
            self.assertTrue((dest / "Info.plist").is_file())
            self.assertTrue((dest / "Assets.xcassets" / "Contents.json").is_file())

    def test_a_non_empty_folder_without_an_index_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "StudioSampleMedia"
            dest.mkdir()
            (dest / "Info.plist").write_text("<plist/>", encoding="utf-8")
            self.assert_refused(dest, "studio-sample-media.json")
            self.assertTrue((dest / "Info.plist").is_file())

    def test_a_file_the_previous_index_does_not_list_survives(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "StudioSampleMedia"
            (dest / "Nested").mkdir(parents=True)
            (dest / "Nested" / "keep.txt").write_text("mine", encoding="utf-8")
            (dest / "notes.txt").write_text("mine", encoding="utf-8")
            (dest / "studio-sample-media.json").write_text(json.dumps({"files": [{"fileName": "old.mp4"}]}),
                                                           encoding="utf-8")
            self.assert_refused(dest, "notes.txt")
            self.assertTrue((dest / "notes.txt").is_file())
            self.assertTrue((dest / "Nested" / "keep.txt").is_file())

    def test_an_index_that_names_a_path_outside_the_folder_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            outside = Path(tmp) / "outside.mp4"
            outside.write_bytes(b"not yours")
            dest = Path(tmp) / "StudioSampleMedia"
            dest.mkdir()
            (dest / "studio-sample-media.json").write_text(json.dumps({"files": [{"fileName": "../outside.mp4"}]}),
                                                           encoding="utf-8")
            self.assert_refused(dest, "../outside.mp4")
            self.assertTrue(outside.is_file())

    def test_an_unreadable_index_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "StudioSampleMedia"
            dest.mkdir()
            (dest / "studio-sample-media.json").write_text("not json", encoding="utf-8")
            self.assert_refused(dest, "studio-sample-media.json")


@unittest.skipUnless(HAVE_FFMPEG, "needs ffmpeg and ffprobe")
class DeterminismTests(unittest.TestCase):
    def test_two_forced_runs_write_byte_identical_media_and_reproduce_the_manifests(self):
        """The short sets, re-encoded from scratch twice into fresh caches with --check (which never writes the
        manifests and fails unless they are reproduced): the SHA-256 lists must be identical. The full-size run of
        every set is the evidence in evidence/studio/s08-studio-media-fixtures/."""
        with tempfile.TemporaryDirectory() as tmp:
            logs = []
            for run in ("a", "b"):
                log = Path(tmp) / f"{run}.txt"
                proc = subprocess.run([sys.executable, str(HERE / "render_studio.py"), "--check", "--force",
                                       "--set", "barcodeSources", "--set", "broll", "--cache", str(Path(tmp) / run),
                                       "--sha256-log", str(log)], capture_output=True, text=True)
                self.assertEqual(proc.returncode, 0, proc.stdout[-2000:] + proc.stderr[-2000:])
                logs.append(log.read_text(encoding="utf-8"))
        self.assertEqual(logs[0], logs[1])
        self.assertEqual(len(logs[0].splitlines()), 9)


class AddedBinaryCheckTests(unittest.TestCase):
    def repo(self, tmp: Path) -> Path:
        repo = tmp / "repo"
        repo.mkdir()
        for args in (["init", "-q", "-b", "main"], ["config", "user.email", "test@example.invalid"],
                     ["config", "user.name", "test"], ["commit", "-q", "--allow-empty", "-m", "base"]):
            subprocess.run(["git", "-C", str(repo), *args], check=True)
        return repo

    def add(self, repo: Path, path: str, data: bytes) -> None:
        (repo / path).parent.mkdir(parents=True, exist_ok=True)
        (repo / path).write_bytes(data)
        subprocess.run(["git", "-C", str(repo), "add", "-f", path], check=True)
        subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m", f"add {path}"], check=True)

    def run_check(self, repo: Path, base: str) -> int:
        return check_added_binaries.main(["--repo", str(repo), "--base", base])

    def test_media_outside_the_bundle_folder_fails_and_images_pass(self):
        mp4 = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00" + bytes(range(256)) * 4
        png = b"\x89PNG\r\n\x1a\n" + bytes(range(256)) * 4
        cases = (("evidence/x/screen.png", png, 0), ("ios/Jovra/Resources/StudioSampleMedia/a.mp4", mp4, 0),
                 ("evidence/x/clip.mp4", mp4, 1), ("spec/studio/fixtures/media/renamed.bin", mp4, 1))
        for path, data, want in cases:
            with self.subTest(path), tempfile.TemporaryDirectory() as tmp:
                repo = self.repo(Path(tmp))
                base = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True,
                                      text=True, check=True).stdout.strip()
                self.add(repo, path, data)
                self.assertEqual(self.run_check(repo, base), want)


if __name__ == "__main__":
    unittest.main()
