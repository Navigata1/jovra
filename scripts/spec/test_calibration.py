"""Tests of the court calibration reference (spec/reference/jovra_ref/court.py, T13) against hand-worked values.

Expected values here are worked by hand or come from an independent source (the renderer's pinhole camera), never
from the homography under test.
"""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "spec" / "reference"))

from jovra_ref import benchmark, court, sample_match  # noqa: E402


def camera(p, w=1920, h=1080):
    return sample_match.project((p[0], p[1] + court.HALF_LENGTH, 0.0), w, h)


class FitTests(unittest.TestCase):
    def test_a_scale_and_shift_is_recovered_exactly(self):
        # Pixels = 10 x court + (500, 300): an affine map, so H = [[10, 0, 500], [0, 10, 300], [0, 0, 1]].
        court_pts = [(-5.0, -10.0), (5.0, -10.0), (5.0, 10.0), (-5.0, 10.0)]
        image = [(10 * x + 500, 10 * y + 300) for x, y in court_pts]
        h = court.fit(image, court_pts)
        for got, want in zip([v for row in h for v in row], [10, 0, 500, 0, 10, 300, 0, 0, 1]):
            self.assertAlmostEqual(got, want, places=9)
        self.assertEqual(tuple(round(v, 9) for v in court.unproject(h, (520.0, 350.0))), (2.0, 5.0))

    def test_perspective_camera_every_intersection_within_a_micropixel(self):
        corners = [court.POINTS[n] for n in court.DOUBLES_CORNERS]
        h = court.fit([camera(c) for c in corners], corners)
        for _, p in court.INTERSECTIONS:
            u, v = court.project(h, p)
            tu, tv = camera(p)
            self.assertLess(math.sqrt((u - tu) ** 2 + (v - tv) ** 2), 1e-6)

    def test_least_squares_on_exact_data_equals_the_exact_fit(self):
        names = [n for n, _ in court.INTERSECTIONS]
        pts = [court.POINTS[n] for n in names]
        h = court.fit([camera(p) for p in pts], pts)
        u, v = court.project(h, (1.0, 2.0))
        tu, tv = camera((1.0, 2.0))
        self.assertLess(abs(u - tu) + abs(v - tv), 1e-6)

    def test_refusals(self):
        four = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]
        for image, pts, code in [(four[:3], four[:3], "tooFewPoints"), (four, four[:3], "countMismatch"),
                                 ([(0.0, 0.0), (1.0, 1.0), (2.0, 2.0), (5.0, 0.0)], four, "degenerate"),
                                 ([four[0]] * 4, four, "degenerate")]:
            with self.assertRaises(court.CalibrationError) as caught:
                court.fit(image, pts)
            self.assertEqual(caught.exception.code, code)

    def test_a_point_above_the_horizon_has_no_ground_position(self):
        corners = [court.POINTS[n] for n in court.DOUBLES_CORNERS]
        h = court.fit([camera(c) for c in corners], corners)
        # The camera looks 17.4 degrees down with a 15 degree half-height field of view, so the top row still sees
        # ground about 182 m away (2.4 degrees below the horizon); the horizon sits 85 px above the frame.
        self.assertGreater(court.unproject(h, (960.0, 0.0))[1], 150)
        self.assertIsNone(court.unproject(h, (960.0, -200.0)))


class CheckTests(unittest.TestCase):
    def test_rmse_by_hand_and_threshold_scaling(self):
        h = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
        # Errors of 3 and 4 px: RMSE = sqrt((9 + 16) / 2) = 3.5355...
        obs = [((0.0, 0.0), (3.0, 0.0)), ((1.0, 1.0), (1.0, 5.0))]
        self.assertAlmostEqual(court.reprojection_rmse(h, obs), math.sqrt(12.5), places=12)
        self.assertEqual(court.fit_check(h, obs, 1080)["verdict"], "poor")
        self.assertEqual(court.fit_check(h, obs, 2160)["verdict"], "good")   # 6 px at 4K
        self.assertEqual(court.poor_fit_threshold_px(720), 2.0)
        self.assertEqual(court.fit_check(h, [], 1080)["verdict"], "notMeasurable")

    def test_measured_lines_the_fit_puts_beyond_its_horizon_are_a_poor_fit_never_unmeasured(self):
        # Story 66: one bracket dragged across the court twists the quad so far that court points the lines were
        # measured at cannot be projected at all. That is the worst fit there is, not an absent measurement.
        corners = [court.POINTS[n] for n in court.DOUBLES_CORNERS]
        true_taps = [camera(c) for c in corners]
        observed = [(p, camera(p)) for n, p in court.INTERSECTIONS if n not in court.DOUBLES_CORNERS]
        bind = {"lens": "wide", "width": 1920, "height": 1080, "zoomFactor": "1.0"}
        twisted = {
            "far right bracket dragged to the middle of the court": true_taps[:2] + [(960.0, 600.0)] + true_taps[3:],
            "far brackets swapped": true_taps[:2] + [true_taps[3], true_taps[2]],
            "far right bracket dragged below the near baseline": true_taps[:2] + [(true_taps[2][0], 1000.0)] + true_taps[3:],
        }
        for name, taps in twisted.items():
            with self.subTest(name):
                h = court.fit(taps, corners)
                self.assertTrue(any(court.project(h, p) is None for p, _ in observed), "premise: a line is unprojectable")
                got = court.fit_check(h, observed, 1080)
                self.assertEqual((got["verdict"], got["rmsePx"]), ("poor", None))
                self.assertEqual(court.validity(bind, bind, None, 0, got), {"status": "invalid", "reason": "poorFit"})
        # Nothing measured is still the only way to read notMeasurable, however twisted the fit.
        h = court.fit(twisted["far brackets swapped"], corners)
        self.assertEqual(court.fit_check(h, [], 1080)["verdict"], "notMeasurable")


class ValidityTests(unittest.TestCase):
    BIND = {"lens": "wide", "width": 1920, "height": 1080, "zoomFactor": "1.0"}

    def test_reasons_in_order(self):
        self.assertEqual(court.validity(self.BIND, self.BIND, None, 0, None), {"status": "valid"})
        self.assertEqual(court.validity(self.BIND, self.BIND, 5000, 5000, None)["reason"], "stale")
        self.assertEqual(court.validity(self.BIND, self.BIND, 5000, 4999, None)["status"], "valid")
        self.assertEqual(court.validity(self.BIND, {**self.BIND, "zoomFactor": "1.5"}, 0, 9, {"verdict": "poor"})["reason"],
                         "zoomChanged")

    def test_a_record_stored_unusable_is_never_valid_when_reopened(self):
        # Refitting the stored taps always succeeds, so the stored status has to be carried, not re-derived.
        for status, reason in [("invalid", "recordedInvalid"), ("needsReview", "needsReview"), ("cameraMoved", "cameraMoved")]:
            self.assertEqual(court.validity(self.BIND, self.BIND, None, 0, None, status),
                             {"status": "invalid", "reason": reason})
        self.assertEqual(court.validity(self.BIND, self.BIND, None, 0, {"verdict": "good"}, "valid"), {"status": "valid"})

    def test_a_dated_camera_move_is_stale_from_that_time_only(self):
        self.assertEqual(court.validity(self.BIND, self.BIND, 120_000, 119_999, None, "cameraMoved"), {"status": "valid"})
        self.assertEqual(court.validity(self.BIND, self.BIND, 120_000, 120_000, None, "cameraMoved"),
                         {"status": "invalid", "reason": "stale", "staleFromMs": 120_000})

    def test_a_camera_reason_is_reported_before_the_stored_status(self):
        other = {**self.BIND, "lens": "telephoto"}
        self.assertEqual(court.validity(self.BIND, other, None, 0, None, "invalid")["reason"], "lensChanged")


class MappingAndWordsTests(unittest.TestCase):
    def test_aspect_fit_letterbox(self):
        # 1920 x 1080 in 393 x 852: scale 0.2046875, video 221.0625 pt tall, bars 315.46875 pt.
        self.assertEqual(court.view_to_video((0.0, 315.46875), (393, 852), (1920, 1080)), (0.0, 0.0))
        self.assertIsNone(court.view_to_video((10.0, 10.0), (393, 852), (1920, 1080)))

    def test_story_364_example(self):
        words = court.placement_words({"x": -3.0, "y": 10.0}, 2.0, "in")
        self.assertEqual(court.english(words), "Deep cross-court, in")

    def test_centre_service_line_runs_only_through_the_service_boxes(self):
        line = next(l for l in court.LINES if l[0] == "centreServiceLine")
        self.assertEqual((line[2], line[3]), ((0.0, -6.40), (0.0, 6.40)))
        kinds = [l[1] for l in court.LINES]
        self.assertEqual(kinds.count("doublesSideline"), 2)


class BenchmarkScorerTests(unittest.TestCase):
    def test_court_calibration_is_scored_exactly_and_split_by_half(self):
        est = [list(p) for p in benchmark.UNTAPPED_INTERSECTIONS_MM]
        est[0] = [est[0][0] + 60, est[0][1] + 80]    # near half, 100 mm: within
        est[1] = [est[1][0], est[1][1] + 101]        # near half, 101 mm: outside
        est[2] = [est[2][0], est[2][1] - 150]        # far half, 150 mm: outside
        record = {"clips": [{"truthId": "t", "outputs": [{"intersectionsMm": est, "bouncesMm": [[10, -20]]}]}]}
        truths = {"t": {"serves": [{"bounce": {"courtMm": {"x": 10, "y": 11885 - 20}}}]}}
        got = {m["name"]: (m["exact"], m.get("unit"), m["value"]) for m in benchmark.score_court_calibration(record, truths)}
        self.assertEqual(list(got), [name for name, _ in benchmark.TASK_METRICS[benchmark.TASK_COURT_CALIBRATION]])
        self.assertEqual(got["intersections within 0.10 m"], ({"n": 5, "d": 6}, None, "0.8333"))
        self.assertEqual(got["intersection MSE"], ({"n": 42701, "d": 12}, "mm2", "3558.417"))
        self.assertEqual(got["near-half intersections within 0.10 m"][0], {"n": 5, "d": 6})
        self.assertEqual(got["near-half intersection MSE"][0], {"n": 20201, "d": 6})
        self.assertEqual(got["near-half worst squared error"], ({"n": 10201, "d": 1}, "mm2", "10201.000"))
        self.assertEqual(got["far-half intersections within 0.10 m"][0], {"n": 5, "d": 6})
        self.assertEqual(got["far-half intersection MSE"][0], {"n": 3750, "d": 1})
        self.assertEqual(got["far-half worst squared error"][0], {"n": 22500, "d": 1})
        self.assertEqual(got["bounces within 0.10 m"][0], {"n": 1, "d": 1})
        self.assertEqual(got["bounce MSE"][0], {"n": 0, "d": 1})


if __name__ == "__main__":
    unittest.main()
