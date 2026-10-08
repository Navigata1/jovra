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

    def test_flags_alert_and_confirmation_dialog_titles(self):
        self.assertEqual(len(lint('view.alert("Delete session?", isPresented: $shown) { }')), 1)
        self.assertEqual(len(lint('view.confirmationDialog("Discard clip?", isPresented: $shown) { }')), 1)

    def test_flags_navigation_links_and_badges(self):
        self.assertEqual(len(lint('NavigationLink("Open settings") { SettingsView() }')), 1)
        self.assertEqual(len(lint('view.badge("New")')), 1)
        self.assertEqual(lint('NavigationLink("Open settings", tableName: "Profile") { }'), [])

    def test_flags_a_localized_string_key_built_from_a_literal(self):
        self.assertEqual(len(lint('Text(LocalizedStringKey("Literal key"))')), 1)
        self.assertEqual(lint('Text(LocalizedStringKey("Literal key"), tableName: "Home")'), [])

    def test_a_table_inside_a_nested_call_or_interpolation_does_not_count(self):
        violations = lint('Text("Shots \\(String(localized: "rally", table: "Home"))")')
        self.assertEqual(len(violations), 1)
        self.assertTrue(violations[0].snippet.startswith('Text("Shots'))
        self.assertEqual(len(lint('Label("Rally", systemImage: icon(String(localized: "x", table: "Home")))')), 1)
        self.assertEqual(len(lint('Button("Rally", action: { log(table: "Home") })')), 1)

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
