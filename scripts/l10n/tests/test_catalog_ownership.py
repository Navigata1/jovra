"""String Catalog ownership: a PR may edit only the tables of its ticket's owned areas."""
import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import catalog_ownership  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[3]
FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures"
TICKETS = catalog_ownership.load_tickets(ROOT / "docs" / "spec" / "tickets.json")
L10N = "ios/Jovra/Resources/Localization"


def check(branch, changed):
    return catalog_ownership.check(branch, changed, TICKETS)


class CatalogOwnershipTests(unittest.TestCase):
    def test_pr_fixture_editing_another_areas_table_fails(self):
        pr = json.loads((FIXTURES / "pr-edits-another-areas-table.json").read_text())
        problems = check(pr["branch"], pr["changed"])
        self.assertEqual(len(problems), 1)
        self.assertIn("Home.xcstrings", problems[0])
        self.assertIn("T19", problems[0])

    def test_pr_fixture_editing_its_own_table_passes(self):
        pr = json.loads((FIXTURES / "pr-edits-its-own-table.json").read_text())
        self.assertEqual(check(pr["branch"], pr["changed"]), [])

    def test_the_most_specific_owned_area_owns_a_table(self):
        self.assertEqual(catalog_ownership.owner_of("Capture.Framing", TICKETS), "T23")
        self.assertEqual(catalog_ownership.owner_of("Capture.Framing.Assist", TICKETS), "T35")
        self.assertEqual(catalog_ownership.owner_of("Capture", TICKETS), "T17")
        self.assertEqual(catalog_ownership.owner_of("Replay.RallyOnly", TICKETS), "T33")
        self.assertEqual(catalog_ownership.owner_of("App", TICKETS), "T07")
        self.assertEqual(catalog_ownership.owner_of("DesignSystem.Components", TICKETS), "T12")
        self.assertIsNone(catalog_ownership.owner_of("InfoPlist", TICKETS))
        self.assertEqual(check("ticket/t17-capture-route-recording", [f"{L10N}/Capture.Framing.xcstrings"]),
                         [f"{L10N}/Capture.Framing.xcstrings: table Capture.Framing belongs to T23 (ios/Jovra/Features/Capture/Framing), not T17"])

    def test_the_localization_owner_may_edit_any_table(self):
        self.assertEqual(check("ticket/t06-ui-harness-l10n-plist", [f"{L10N}/Home.xcstrings", f"{L10N}/InfoPlist.xcstrings"]), [])

    def test_catalogs_outside_the_localization_folder_and_non_ticket_branches_fail(self):
        self.assertEqual(check("ticket/t19-home-dashboard", ["ios/Jovra/Features/Home/Home.xcstrings"]),
                         ["ios/Jovra/Features/Home/Home.xcstrings: String Catalogs live in ios/Jovra/Resources/Localization"])
        self.assertEqual(check("fix/typo", [f"{L10N}/Home.xcstrings"]),
                         [f"{L10N}/Home.xcstrings: branch fix/typo is not a ticket branch (ticket/tNN-slug), so it owns no table"])

    def test_changes_without_catalogs_always_pass(self):
        self.assertEqual(check("fix/typo", ["ios/Jovra/Features/Home/HomeView.swift"]), [])


if __name__ == "__main__":
    unittest.main()
