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

    BIND = {"lens": "wide", "width": 1920, "height": 1080, "zoomFactor": "1.0"}

    def twisted_taps(self) -> dict:
        t = [camera(court.POINTS[n]) for n in court.DOUBLES_CORNERS]
        return {
            "far right bracket dragged to the middle of the court": t[:2] + [(960.0, 600.0)] + t[3:],
            "far brackets swapped": t[:2] + [t[3], t[2]],
            "near brackets swapped": [t[1], t[0]] + t[2:],
            "far right bracket dragged below the near baseline": t[:2] + [(t[2][0], 1000.0)] + t[3:],
        }

    def test_a_twisted_fit_is_poor_and_invalid_with_nothing_measured(self):
        # No line detector exists yet, so nothing is measured for any calibration the app makes. A quad no camera
        # can produce must be caught from the taps alone: the fit puts its own tapped corners beyond its horizon.
        corners = [court.POINTS[n] for n in court.DOUBLES_CORNERS]
        for name, taps in self.twisted_taps().items():
            with self.subTest(name):
                h = court.fit(taps, corners)
                self.assertTrue(any(court.project(h, c) is None for c in corners), "premise: a tapped corner has no pixel")
                self.assertTrue(court.is_twisted(h, corners))
                got = court.fit_check(h, [], 1080, corners)
                self.assertEqual((got["verdict"], got["rmsePx"]), ("poor", None))
                self.assertEqual(court.validity(self.BIND, self.BIND, None, 0, got), {"status": "invalid", "reason": "poorFit"})
                # Never checked at all (the app today): the twist alone makes it unusable.
                self.assertEqual(court.validity(self.BIND, self.BIND, None, 0, None, twisted=court.is_twisted(h, corners)),
                                 {"status": "invalid", "reason": "poorFit"})
                # A record stored valid with a good residual does not outrank its own taps.
                self.assertEqual(court.validity(self.BIND, self.BIND, None, 0, {"verdict": "good"}, "valid", twisted=True),
                                 {"status": "invalid", "reason": "poorFit"})

    def test_the_true_point_reads_back_wrong_under_a_twisted_fit(self):
        # Why it matters: with the far brackets swapped the true court point (2, 4) reads back about 31 m away.
        corners = [court.POINTS[n] for n in court.DOUBLES_CORNERS]
        h = court.fit(self.twisted_taps()["far brackets swapped"], corners)
        x, y = court.unproject(h, camera((2.0, 4.0)))
        self.assertGreater(math.hypot(x - 2.0, y - 4.0), 10)

    def test_an_untwisted_fit_with_nothing_measured_stays_not_measurable_and_usable(self):
        corners = [court.POINTS[n] for n in court.DOUBLES_CORNERS]
        h = court.fit([camera(c) for c in corners], corners)
        self.assertFalse(court.is_twisted(h, corners))
        got = court.fit_check(h, [], 1080, corners)
        self.assertEqual(got["verdict"], "notMeasurable")
        self.assertEqual(court.validity(self.BIND, self.BIND, None, 0, got, twisted=False), {"status": "valid"})

    def test_rotated_and_mirrored_corner_orders_are_out_of_reach_of_the_twist_rule(self):
        # The limit of the rule, stated: brackets put on the corners one place round, or mirrored left to right,
        # still make a convex quad with a homography that places every court point. Only measured lines catch these.
        corners = [court.POINTS[n] for n in court.DOUBLES_CORNERS]
        t = [camera(c) for c in corners]
        observed = [(p, camera(p)) for n, p in court.INTERSECTIONS if n not in court.DOUBLES_CORNERS]
        for name, taps in {"rotated one place": t[1:] + t[:1], "mirrored": [t[1], t[0], t[3], t[2]]}.items():
            with self.subTest(name):
                h = court.fit(taps, corners)
                self.assertFalse(court.is_twisted(h, corners))
                self.assertEqual(court.fit_check(h, [], 1080, corners)["verdict"], "notMeasurable")
                self.assertEqual(court.fit_check(h, observed, 1080, corners)["verdict"], "poor")

    def test_a_fit_that_puts_a_court_line_beyond_its_horizon_is_twisted_whatever_was_tapped(self):
        # w = 1 - 0.1 y: the horizon crosses the court 10 m beyond the net, so the far baseline has no pixel although
        # the four tapped near-half points (y <= -6.4) are all in front of it.
        h = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, -0.1, 1.0]]
        tapped = [court.POINTS[n] for n in ("nearLeftSingles", "nearRightSingles", "nearRightService", "nearLeftService")]
        self.assertTrue(all(court.project(h, p) is not None for p in tapped))
        self.assertIsNone(court.project(h, court.POINTS["farCentreMark"]))
        self.assertTrue(court.is_twisted(h, tapped))
        # And a tapped point beyond the horizon is twisted even when every court line is in front of it.
        level = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, -0.05, 1.0]]    # horizon at y = 20
        self.assertFalse(court.is_twisted(level, tapped))
        self.assertTrue(court.is_twisted(level, tapped[:3] + [(0.0, 25.0)]))


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
