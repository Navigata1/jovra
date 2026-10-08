"""Side-by-side evidence page: simulator screenshots paired with reference PNGs, each with a reviewer line."""
import os
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import side_by_side  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[3]
PNG = bytes.fromhex("89504e470d0a1a0a")  # enough of a PNG for pairing; the page only links to files


class SideBySideTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.evidence = pathlib.Path(self.temp.name) / "evidence" / "ios" / "t19-home-dashboard"
        self.evidence.mkdir(parents=True)
        for name in ("s03-light-home.png", "s03-dark-home.jpg", "s21-light-studio-home.png", "pseudo-1-home.png"):
            (self.evidence / name).write_bytes(PNG)

    def tearDown(self):
        self.temp.cleanup()

    def run_generator(self, reviews):
        (self.evidence / "reviews.txt").write_text(reviews)
        return side_by_side.main([str(self.evidence), "--repo", str(ROOT)])

    def test_pairs_screenshots_with_references_by_screen_number(self):
        pairs = side_by_side.find_pairs(self.evidence, ROOT)
        self.assertEqual([(p.screen, p.screenshot.name, p.reference.relative_to(ROOT).as_posix()) for p in pairs], [
            (3, "s03-dark-home.jpg", "design-reference/screens/03-home.png"),
            (3, "s03-light-home.png", "design-reference/screens/03-home.png"),
            (21, "s21-light-studio-home.png", "design-reference/studio/screens/21-studio-home.png"),
        ])

    def test_a_pair_without_a_reviewer_line_fails_and_writes_no_page(self):
        status = self.run_generator(
            "s03-light-home: Claude (T19 agent) — matches the reference; tiles follow the spec order\n"
            "s21-light-studio-home: Jon — approved\n"
        )
        self.assertEqual(status, 2)
        self.assertFalse((self.evidence / "side-by-side.html").exists())

    def test_a_placeholder_reviewer_line_does_not_count(self):
        status = self.run_generator(
            "s03-light-home: TODO\n"
            "s03-dark-home: Claude (T19 agent) — matches\n"
            "s21-light-studio-home: Jon — approved\n"
        )
        self.assertEqual(status, 2)

    def test_every_pair_reviewed_writes_the_page(self):
        status = self.run_generator(
            "# reviewer lines: <screenshot>: <reviewer> — <verdict and notes>\n"
            "s03-light-home: Claude (T19 agent) — matches the reference; tiles follow the spec order\n"
            "s03-dark-home: Claude (T19 agent) — matches; forest card keeps contrast\n"
            "s21-light-studio-home: Jon — approved\n"
        )
        self.assertEqual(status, 0)
        page = (self.evidence / "side-by-side.html").read_text()
        self.assertIn("Screen 03", page)
        self.assertIn(os.path.relpath(ROOT / "design-reference/screens/03-home.png", self.evidence), page)
        self.assertIn('src="s03-dark-home.jpg"', page)
        self.assertIn("Jon — approved", page)
        self.assertNotIn("pseudo-1-home", page)

    def test_a_screen_number_without_a_reference_is_an_error(self):
        (self.evidence / "s41-light-nowhere.png").write_bytes(PNG)
        status = self.run_generator("")
        self.assertEqual(status, 1)


if __name__ == "__main__":
    unittest.main()
