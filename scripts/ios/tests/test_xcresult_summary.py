"""xcresult-summary: every test case is counted, expected failures (XCTExpectFailure) included."""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "xcresult-summary.py"
spec = importlib.util.spec_from_file_location("xcresult_summary", SCRIPT)
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


def case(name, result):
    return {"nodeType": "Test Case", "name": name, "result": result}


TREE = [{
    "nodeType": "UI test bundle", "name": "JovraUITests", "children": [{
        "nodeType": "Test Suite", "name": "HarnessUITests",
        "nodeIdentifierURL": "test://com.apple.xcode/Jovra/JovraUITests/HarnessUITests",
        "children": [case("a", "Passed"), case("b", "Expected Failure"), case("c", "Skipped")],
    }],
}]


class XcresultSummaryTests(unittest.TestCase):
    def test_an_expected_failure_is_counted_in_its_own_column(self):
        rows = []
        summary.suite_rows(TREE, rows)
        lines = summary.format_table(rows)
        self.assertIn("expected", lines[0])
        self.assertEqual(lines[1].split(), ["JovraUITests/HarnessUITests", "1", "0", "1", "1"])
        self.assertEqual(summary.totals(rows), {"Passed": 1, "Failed": 0, "Skipped": 1, "Expected Failure": 1})


if __name__ == "__main__":
    unittest.main()
