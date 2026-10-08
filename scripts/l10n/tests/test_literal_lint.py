"""Literal-string lint: user-visible strings must come from a named String Catalog table."""
import pathlib
import shutil
import sys
import tempfile
import textwrap
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import literal_lint  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[3]


def lint(source):
    return literal_lint.lint_source(textwrap.dedent(source), "Fixture.swift")


class LiteralLintTests(unittest.TestCase):
    def test_flags_a_hard_coded_text_literal(self):
        violations = lint('''
            struct V: View {
                var body: some View { Text("Hello there") }
            }
        ''')
        self.assertEqual([(v.line, v.snippet) for v in violations], [(3, 'Text("Hello there")')])

    def test_accepts_a_literal_key_with_an_explicit_table(self):
        self.assertEqual(lint('Text("Hello there", tableName: "Home")'), [])
        self.assertEqual(lint('let s = String(localized: "Hello", table: "Home")'), [])
        self.assertEqual(lint('Button(String(localized: "Done", table: "Capture")) { }'), [])

    def test_accepts_verbatim_text_and_strings_without_letters(self):
        self.assertEqual(lint('Text(verbatim: "hello@islanddevcrew.com")'), [])
        self.assertEqual(lint('Text(" · ")'), [])

    def test_flags_controls_modifiers_and_labelled_arguments(self):
        source = '''
            Button("Done") { }
            Label("Record a session", systemImage: "arrow.right")
            view.accessibilityLabel("Close")
            ComingLaterCard(symbol: "house", message: "Arrives later.")
            SectionHeader(title: "This week")
            let s = String(localized: "No table")
        '''
        self.assertEqual([v.line for v in lint(source)], [2, 3, 4, 5, 6, 7])

    def test_flags_literals_returned_by_a_display_property(self):
        source = '''
            var title: String {
                switch self {
                case .home: "Home"
                case .profile: return "Profile"
                }
            }
            var symbol: String {
                switch self {
                case .home: "house"
                }
            }
        '''
        self.assertEqual([v.line for v in lint(source)], [4, 5])

    def test_flags_display_property_defaults(self):
        source = '''
            var title = "Coming in a later ticket"
            let message: String = "Arrives later"
            var symbol = "hammer"
        '''
        self.assertEqual([v.line for v in lint(source)], [2, 3])

    def test_ignores_previews_and_marked_lines(self):
        source = '''
            #Preview("Light") {
                Text("Preview only")
            }
            Text("Brand") // l10n-lint: ignore (brand name)
        '''
        self.assertEqual(lint(source), [])

    def test_a_file_can_opt_out_with_a_reason(self):
        self.assertEqual(lint('// l10n-lint: ignore-file (previews)\nText("Gallery")'), [])
        self.assertEqual(len(lint('// l10n-lint: ignore-file\nText("Gallery")')), 2,
                         "an ignore-file without a reason is itself a violation and ignores nothing")

    def test_the_shell_passes(self):
        violations = literal_lint.lint_paths([ROOT / "ios" / "Jovra"])
        self.assertEqual([str(v) for v in violations], [])

    def test_a_literal_seeded_into_a_copy_of_the_shell_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            shell = pathlib.Path(temp) / "Jovra"
            shutil.copytree(ROOT / "ios" / "Jovra", shell)
            home = shell / "Features" / "Home" / "HomeView.swift"
            home.write_text(home.read_text() + '\nprivate struct Seeded: View {\n    var body: some View { Text("Seeded literal") }\n}\n')
            violations = literal_lint.lint_paths([shell])
        self.assertEqual(len(violations), 1)
        self.assertIn('Text("Seeded literal")', str(violations[0]))


if __name__ == "__main__":
    unittest.main()
