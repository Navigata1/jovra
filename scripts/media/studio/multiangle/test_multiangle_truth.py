"""Ground-truth tests of the synthetic multi-angle generator (S58). No ffmpeg and no media: these read the generator's
plan (``jovra_multiangle.truth``) and the committed files under spec/studio/fixtures/media/multiangle/.

    python3 -m unittest discover -s scripts/media/studio/multiangle -p 'test_*.py' -v

Expected values come from sources independent of the generator: the multicam research section 4.4 table (as the
sound-delay vectors carry it, ``docTableMs``), the profile definitions in the ticket (41 s gap, 300 ppm, 60/30/240
fps) and hand-worked frame times.
"""

from __future__ import annotations

import json
import sys
import unittest
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
for _p in (HERE, HERE.parent, HERE.parents[1], ROOT / "spec" / "reference"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

from jovra_multiangle import truth  # noqa: E402

VECTORS = ROOT / "spec" / "studio" / "fixtures" / "vectors" / "sound-delay.json"
COMMITTED = ROOT / "spec" / "studio" / "fixtures" / "media" / "multiangle"


def ms(text: str) -> Fraction:
    return Fraction(text)


class SoundDelayTableTests(unittest.TestCase):
    """Acceptance: sound delays in the ground truth reproduce the multicam research 4.4 tables within 0.1 ms."""

    @classmethod
    def setUpClass(cls):
        cls.rig = truth.rig()
        cls.vectors = json.loads(VECTORS.read_text(encoding="utf-8"))["cases"]

    def delay_us(self, event: dict, mic: dict) -> int:
        slot = next(p["code"] for p in self.rig["placements"] if p["positionMm"] == mic)
        row = next(r for r in self.rig["soundDelayTable"]["rows"] if r["positionMm"] == event)
        return row["delaysUs"][slot]

    def test_every_research_table_entry_is_reproduced_within_a_tenth_of_a_millisecond(self):
        checked = 0
        for case in self.vectors:
            if "event" not in case or "otherMic" in case:
                continue
            got = Fraction(self.delay_us(case["event"], case["mic"]), 1000)
            want = ms(case["assert"]["docTableMs"])
            self.assertLessEqual(abs(got - want), Fraction(1, 10), case["id"])
            checked += 1
        self.assertEqual(checked, 36, "six table rows by six placements")

    def test_pairwise_biases_reproduce_the_research_bias_table(self):
        checked = 0
        for case in self.vectors:
            if "otherMic" not in case:
                continue
            bias = self.delay_us(case["event"], case["mic"]) - self.delay_us(case["event"], case["otherMic"])
            self.assertLessEqual(abs(Fraction(bias, 1000) - ms(case["assert"]["docTableMs"])), Fraction(1, 10), case["id"])
            checked += 1
        self.assertGreaterEqual(checked, 9)

    def test_net_centre_is_almost_equidistant_from_all_six_placements(self):
        # Research 4.4, bold row: 50.6 ms to both baselines, 56.4 ms to every corner (club fence).
        row = next(r for r in self.rig["soundDelayTable"]["rows"] if r["id"] == "net-centre")
        self.assertEqual({k: round(v / 1000, 1) for k, v in row["delaysUs"].items()},
                         {"BS": 50.6, "BN": 50.6, "CSW": 56.4, "CSE": 56.4, "CNW": 56.4, "CNE": 56.4})


def exact(q: dict) -> Fraction:
    return Fraction(q["num"], q["den"])


def apply(transform: dict, source_us: Fraction) -> Fraction:
    """t_match = offset + rate * t_source, read from the JSON alone."""
    return exact(transform["offsetUs"]) + exact(transform["rate"]) * source_us


class ProfileTruthTests(unittest.TestCase):
    """Each profile of the ticket, checked against the ticket's numbers and hand-worked times."""

    @classmethod
    def setUpClass(cls):
        cls.docs = {pid: truth.profile_plan(pid) for pid in truth.profile_ids()}

    def cam(self, pid: str, cid: str) -> dict:
        return next(c for c in self.docs[pid]["cameras"] if c["cameraId"] == cid)

    def test_the_ticket_profiles_are_all_there(self):
        self.assertEqual(sorted(self.docs), sorted([
            "drift-default", "drift-stress-300ppm", "restart-41s-journal", "restart-41s-no-journal", "late-start",
            "shake", "muted", "mixed-fps", "vfr-rotated-hdr", "no-shared-coverage", "opposite-baseline-audio-only"]))

    def test_every_profile_has_one_reference_camera_at_rate_one_from_the_scene_start(self):
        for pid, doc in self.docs.items():
            refs = [c for c in doc["cameras"] if c["reference"]]
            self.assertEqual(len(refs), 1, pid)
            self.assertEqual(refs[0]["cameraId"], doc["matchClock"]["referenceCameraId"])
            self.assertEqual(refs[0]["segments"][0]["transform"]["rate"], {"num": 10**9, "den": 10**9})
            self.assertEqual(refs[0]["segments"][0]["matchCoverageUs"]["startUs"], 0)

    def test_default_drift_uses_all_six_placements_with_drifts_between_one_and_fifty_ppm(self):
        cams = self.docs["drift-default"]["cameras"]
        self.assertEqual(sorted(c["placement"] for c in cams), ["BN", "BS", "CNE", "CNW", "CSE", "CSW"])
        drifts = sorted(c["clock"]["driftPpb"] for c in cams if not c["reference"])
        self.assertTrue(all(1_000 <= abs(d) <= 50_000 for d in drifts), drifts)
        self.assertTrue(drifts[0] < 0 < drifts[-1], "both signs")

    def test_worked_frame_time_on_a_fifty_ppm_camera(self):
        # cnw-drift: first frame at 0.7331 s, +50 ppm, 30 fps. Frame 3000 is 100 s of its own clock:
        # 0.7331 s + 100 s x 1.00005 = 100.7381 s on the match clock.
        seg = self.cam("drift-default", "cnw-drift")["segments"][0]
        self.assertEqual(apply(seg["transform"], Fraction(3000 * 1_000_000, 30)), 100_738_100)

    def test_worked_frame_time_on_the_240_fps_camera(self):
        # cnw-240fps: first frame at 12.0041 s, -15 ppm. Frame 2400 is 10 s of its clock: 12.0041 + 9.99985 s.
        seg = self.cam("mixed-fps", "cnw-240fps")["segments"][0]
        self.assertEqual(apply(seg["transform"], Fraction(2400 * 1_000_000, 240)), 22_003_950)

    def test_stress_profile_drifts_by_three_hundred_ppm(self):
        c = self.cam("drift-stress-300ppm", "cse-stress")
        self.assertEqual(c["clock"]["driftPpb"], 300_000)
        self.assertEqual(c["clock"]["rate"], {"num": 1_000_300_000, "den": 1_000_000_000})

    def test_restart_with_journal_has_a_41_second_host_gap_and_one_host_clock_map(self):
        c = self.cam("restart-41s-journal", "cne-restart-journal")
        self.assertEqual(len(c["segments"]), 2)
        gap = c["gaps"][0]
        self.assertEqual(gap["hostUs"]["endUs"] - gap["hostUs"]["startUs"], 41_000_000)
        self.assertEqual(gap["reason"], "restart")
        self.assertEqual([s["fileZeroHostUs"] for s in c["journal"]["segments"]], [0, 71_000_000])
        # Segment 1's offset follows from the host map: 0.511 s + 71 s x 1.000012 = 71.511852 s.
        self.assertEqual(exact(c["segments"][1]["transform"]["offsetUs"]), 71_511_852)
        self.assertEqual(c["segments"][0]["transform"]["rate"], c["segments"][1]["transform"]["rate"])

    def test_restart_without_journal_still_states_both_true_pieces(self):
        c = self.cam("restart-41s-no-journal", "cnw-restart-import")
        self.assertIsNone(c["journal"])
        self.assertEqual(len(c["segments"]), 2)
        gap = c["gaps"][0]
        self.assertEqual(gap["hostUs"]["endUs"] - gap["hostUs"]["startUs"], 41_000_000)
        # The match-clock gap is the host gap at the device rate (-20 ppm): 41 s x 0.99998 = 40.99918 s.
        self.assertEqual(gap["matchUs"]["endUs"] - gap["matchUs"]["startUs"], 40_999_180)

    def test_late_start_coverage_begins_where_its_recording_begins(self):
        c = self.cam("late-start", "bn-late")
        self.assertEqual(c["segments"][0]["matchCoverageUs"]["startUs"], 47_300_000)
        self.assertTrue(all(v["frameMatchUs"] >= 47_300_000 for v in c["visualEvents"]))

    def test_mixed_profile_has_30_60_and_240_fps(self):
        rates = sorted(c["frameRate"]["num"] for c in self.docs["mixed-fps"]["cameras"])
        self.assertEqual(rates, [30, 60, 240])

    def test_vfr_rotated_and_hdr_variants(self):
        vfr, rot, hdr = (self.cam("vfr-rotated-hdr", c) for c in ("bn-vfr", "csw-rot90", "cne-hdr"))
        self.assertEqual(vfr["frameTiming"]["kind"], "vfr")
        self.assertEqual(sum(vfr["frameTiming"]["cycle"]), 10 * vfr["frameTiming"]["timescale"] // 30)
        self.assertEqual(rot["rotation"], 90)
        self.assertEqual((hdr["codec"], hdr["hdr"], hdr["bitDepth"]), ("hevc", "hlg", 10))

    def test_no_shared_coverage_pair_is_null(self):
        pairs = self.docs["no-shared-coverage"]["sharedCoverage"]
        self.assertEqual(len(pairs), 1)
        self.assertIsNone(pairs[0]["matchUs"])

    def test_drift_default_pairs_all_overlap(self):
        pairs = self.docs["drift-default"]["sharedCoverage"]
        self.assertEqual(len(pairs), 15)
        self.assertTrue(all(p["matchUs"] is not None for p in pairs))

    def test_muted_camera_hears_nothing_but_sees_the_events(self):
        c = self.cam("muted", "cse-muted")
        self.assertEqual(c["audio"]["mode"], "muted")
        self.assertTrue(c["audioArrivals"])
        self.assertFalse(any(a["heard"] for a in c["audioArrivals"]))
        reasons = {a["reason"] for a in c["audioArrivals"]}
        self.assertEqual(reasons, {"muted", "notRecording"}, "muted while recording; after 60.4 s it has stopped")
        recording = [a for a in c["audioArrivals"] if a["segment"] is not None]
        self.assertTrue(recording and all(a["reason"] == "muted" for a in recording))
        self.assertTrue(c["visualEvents"])
        self.assertTrue(all(f["clickSamples"] == [] for s in c["segments"] for f in s["files"]))

    def test_audio_only_profile_has_no_visual_events_and_baseline_dependent_sound_delays(self):
        bs, bn = (self.cam("opposite-baseline-audio-only", c) for c in ("bs-covered", "bn-covered"))
        self.assertEqual((bs["view"], bn["view"]), ("covered", "covered"))
        self.assertEqual(bs["visualEvents"] + bn["visualEvents"], [])
        events = {e["id"]: e for e in self.docs["opposite-baseline-audio-only"]["scene"]["events"]}
        bn_delay = {a["eventId"]: a["delayUs"] for a in bn["audioArrivals"]}
        for a in bs["audioArrivals"]:
            south = events[a["eventId"]]["positionMm"]["yMm"] < 0
            self.assertEqual(a["delayUs"] < bn_delay[a["eventId"]], south, a["eventId"])

    def test_heard_arrivals_are_the_click_samples_of_their_files(self):
        for pid, doc in self.docs.items():
            for c in doc["cameras"]:
                for seg in c["segments"]:
                    heard = sorted(a["sourceSample"] for a in c["audioArrivals"] if a["heard"] and a["segment"] == seg["segment"])
                    for f in seg["files"]:
                        self.assertEqual(f["clickSamples"], heard, f"{pid} {c['cameraId']}")


class ShakeTruthTests(unittest.TestCase):
    """Acceptance: the shake profile's ground truth marks the shaken stretch so anchor tests can down-weight it."""

    @classmethod
    def setUpClass(cls):
        cls.cam = next(c for c in truth.profile_plan("shake")["cameras"] if c["cameraId"] == "csw-shake")

    def test_the_stretch_is_marked_in_frames_and_on_the_match_clock(self):
        s = self.cam["shake"]
        self.assertEqual((s["segment"], s["fromFrame"], s["toFrame"]), (0, 1105, 1210))
        # Frame 1105 at 30 fps is 36.8333 s of the camera's clock: 20.15 s + 36.8333 s x 1.000003 = 56.98344 s.
        self.assertEqual(s["matchUs"]["startUs"], 56_983_444)
        self.assertEqual(s["settledNudgeDeg"], {"yaw": 1, "pitch": 0})

    def test_events_inside_the_stretch_are_flagged_and_the_rest_are_not(self):
        s = self.cam["shake"]
        inside = [v for v in self.cam["visualEvents"] if v["inShake"]]
        self.assertGreaterEqual(len([v for v in inside if v["kind"] != "bounce"]), 3, "three racket contacts shaken")
        for v in self.cam["visualEvents"]:
            self.assertEqual(v["inShake"], s["fromFrame"] <= v["frame"] < s["toFrame"], v["eventId"])

    def test_other_profiles_mark_no_shake(self):
        for pid in truth.profile_ids():
            for c in truth.profile_plan(pid)["cameras"]:
                if c["cameraId"] != "csw-shake":
                    self.assertIsNone(c["shake"])
                    self.assertFalse(any(v["inShake"] for v in c["visualEvents"]))


class DeterminismTests(unittest.TestCase):
    """Acceptance (ground-truth half): two runs produce unchanged ground-truth files."""

    def test_two_plans_are_byte_identical(self):
        for pid in truth.profile_ids():
            self.assertEqual(truth.dumps(truth.profile_plan(pid)), truth.dumps(truth.profile_plan(pid)), pid)

    def test_the_committed_ground_truth_is_the_current_plan(self):
        for pid in truth.profile_ids():
            path = COMMITTED / f"{pid}.json"
            self.assertTrue(path.is_file(), f"{path} is not committed: run scripts/media/studio/multiangle/generate.py")
            committed = json.loads(path.read_text(encoding="utf-8"))
            committed.pop("hashes")
            self.assertEqual(committed, json.loads(truth.dumps(truth.profile_plan(pid))), pid)
        self.assertEqual((COMMITTED / "rig.json").read_text(encoding="utf-8"), truth.dumps(truth.rig()))


if __name__ == "__main__":
    unittest.main()
