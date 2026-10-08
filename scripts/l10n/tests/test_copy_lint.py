"""Copy lint: no String Catalog may carry a claim one camera cannot back (story 371) or a sample-only value."""
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import copy_lint  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[3]


def catalog(strings):
    """A minimal String Catalog: {key: value or (value, comment)}."""
    entries = {}
    for key, value in strings.items():
        value, comment = value if isinstance(value, tuple) else (value, None)
        entry = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": value}}}}
        if comment:
            entry["comment"] = comment
        entries[key] = entry
    return {"sourceLanguage": "en", "strings": entries, "version": "1.0"}


def lint(strings):
    with tempfile.TemporaryDirectory() as temp:
        path = pathlib.Path(temp) / "Fixture.xcstrings"
        path.write_text(json.dumps(catalog(strings)))
        return [(f.key, f.rule) for f in copy_lint.lint_catalog(path)]


class CopyLintTests(unittest.TestCase):
    def test_a_seeded_line_call_fails(self):
        self.assertEqual(lint({"Ball called out": "Line call: out"}), [("Ball called out", "line-call")])

    def test_every_banned_term(self):
        cases = {
            "Spin rate 2,400 RPM": ["spin-rate", "rpm"],
            "Injury risk": ["injury"],
            "Calories burned": ["calories"],
            "Fastest serve": ["fastest-serve"],
            "Best of 3 · Advantage": ["advantage-format"],
            "Advantage": ["advantage-format"],
            "Reference concept": ["reference-concept"],
            "Write to mailto:hello@islanddevcrew.com": ["mailto"],
            "3.2 GB used": ["sample-storage"],
        }
        for text, rules in cases.items():
            with self.subTest(text=text):
                self.assertEqual(sorted(rule for _, rule in lint({"k": text})), sorted(rules))

    def test_honest_wording_passes(self):
        self.assertEqual(lint({
            "a": "Fastest marked serve",
            "b": "Best of 3 · Ad · Tie-break at 6–6",
            "c": "Advantage set",
            "d": "Your next advantage",
            "e": "Questions: hello@islanddevcrew.com",
            "f": "13.2 GB free",
        }), [])

    def test_keys_are_checked_as_well_as_values(self):
        self.assertEqual(lint({"Line calls": "Lines"}), [("Line calls", "line-call")])

    def test_an_entry_comment_can_allow_one_rule_with_a_reason(self):
        allowed = ("JOVRA never makes line calls.", "copy-lint: allow line-call — states what JOVRA does not do")
        self.assertEqual(lint({"no-line-calls": allowed}), [])
        unexplained = ("JOVRA never makes line calls.", "copy-lint: allow line-call")
        self.assertEqual(lint({"no-line-calls": unexplained}), [("no-line-calls", "line-call")])

    def test_every_catalog_in_the_app_passes(self):
        catalogs = copy_lint.find_catalogs(ROOT / "ios")
        self.assertTrue(catalogs, "the app has String Catalogs")
        findings = [str(f) for path in catalogs for f in copy_lint.lint_catalog(path)]
        self.assertEqual(findings, [])


def lint_swift(source):
    with tempfile.TemporaryDirectory() as temp:
        path = pathlib.Path(temp) / "Fixture.swift"
        path.write_text(source)
        return [(f.key, f.rule) for f in copy_lint.lint_swift(path)]


class SwiftCopyLintTests(unittest.TestCase):
    """Story 371 says 'anywhere': the banned terms are banned in Swift literals too, verbatim text included."""

    def test_a_verbatim_text_with_a_banned_claim_fails(self):
        self.assertEqual(lint_swift('Text(verbatim: "Automatic line call, spin RPM 3000")'),
                         [("line 1", "rpm"), ("line 1", "line-call")])

    def test_an_accessibility_label_with_a_banned_claim_fails(self):
        self.assertEqual(lint_swift('view\n    .accessibilityLabel(Text(verbatim: "Calories burned"))'),
                         [("line 2", "calories")])

    def test_comments_are_not_copy_and_a_line_can_allow_one_rule_with_a_reason(self):
        self.assertEqual(lint_swift('// no line calls here\nlet x = 1'), [])
        allowed = 'Text(verbatim: "No line calls") // copy-lint: allow line-call — states what JOVRA does not do'
        self.assertEqual(lint_swift(allowed), [])
        self.assertEqual(lint_swift('Text(verbatim: "No line calls") // copy-lint: allow line-call'),
                         [("line 1", "line-call")])

    def test_the_app_sources_pass_and_the_cli_covers_them(self):
        sources = copy_lint.find_swift_sources(ROOT / "ios" / "Jovra")
        self.assertTrue(sources)
        self.assertEqual([str(f) for path in sources for f in copy_lint.lint_swift(path)], [])
        self.assertIn(ROOT / "ios" / "Jovra", copy_lint.default_targets(ROOT)[1])


if __name__ == "__main__":
    unittest.main()
