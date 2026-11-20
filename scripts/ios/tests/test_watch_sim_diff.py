"""watch-sim.sh before/after check: only the three JOVRA watch simulators may change (ticket W03)."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import watch_sim_diff  # noqa: E402

NAMES = ["JOVRA Watch Ultra 3 49mm", "JOVRA Watch Series 11 42mm", "JOVRA Watch SE 3 40mm"]
WATCH = "com.apple.CoreSimulator.SimRuntime.watchOS-26-5"
IOS = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"


def ident(udid, name, runtime=WATCH, kind="watch"):
    return udid, name, kind, runtime


OTHER = {"o1": ident("o1", "Someone else's phone", IOS, "iphone"), "o2": ident("o2", "An existing watch")}
OURS = {f"j{i}": ident(f"j{i}", name) for i, name in enumerate(NAMES)}


class WatchSimDiffTests(unittest.TestCase):
    def test_create_that_adds_only_ours_passes(self):
        lines, problems = watch_sim_diff.compare("create", dict(OTHER), {**OTHER, **OURS}, NAMES)
        self.assertEqual(problems, [])
        self.assertIn("other devices after, unchanged: 2", "\n".join(lines))

    def test_delete_that_removes_only_ours_passes(self):
        _, problems = watch_sim_diff.compare("delete", {**OTHER, **OURS}, dict(OTHER), NAMES)
        self.assertEqual(problems, [])

    def test_removing_another_device_fails(self):
        after = {**OURS, "o1": OTHER["o1"]}
        _, problems = watch_sim_diff.compare("create", dict(OTHER), after, NAMES)
        self.assertEqual(problems, ["a device this script does not own was removed or changed: o2"])

    def test_renaming_another_device_fails(self):
        after = {**OTHER, **OURS, "o2": ident("o2", "Renamed watch")}
        _, problems = watch_sim_diff.compare("create", dict(OTHER), after, NAMES)
        self.assertEqual(len(problems), 1)

    def test_device_added_by_another_process_is_reported_not_failed(self):
        after = {**OTHER, **OURS, "x9": ident("x9", "Another agent's phone", IOS, "iphone")}
        lines, problems = watch_sim_diff.compare("create", dict(OTHER), after, NAMES)
        self.assertEqual(problems, [])
        self.assertIn("added meanwhile by another process (not touched): 1", "\n".join(lines))

    def test_create_missing_one_of_ours_fails(self):
        after = {**OTHER, "j0": OURS["j0"], "j1": OURS["j1"]}
        _, problems = watch_sim_diff.compare("create", dict(OTHER), after, NAMES)
        self.assertEqual(problems, ["JOVRA Watch SE 3 40mm is missing after create"])

    def test_delete_leaving_one_of_ours_fails(self):
        _, problems = watch_sim_diff.compare("delete", {**OTHER, **OURS}, {**OTHER, "j2": OURS["j2"]}, NAMES)
        self.assertEqual(problems, ["JOVRA Watch SE 3 40mm is still present after delete"])

    def test_report_never_names_other_devices(self):
        lines, _ = watch_sim_diff.compare("create", dict(OTHER), {**OTHER, **OURS}, NAMES)
        self.assertNotIn("Someone else", "\n".join(lines))


if __name__ == "__main__":
    unittest.main()
