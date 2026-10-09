"""xcresult-summary: every test case is counted, expected failures (XCTExpectFailure) included."""
import contextlib
import io
import importlib.util
import pathlib
import unittest
from unittest import mock

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
    def run_receipt(self, tree, result):
        output = io.StringIO()
        with mock.patch.object(summary, "load", side_effect=lambda _, kind: {"testNodes": tree} if kind == "tests" else result), \
             mock.patch.object(summary.sys, "argv", ["xcresult-summary.py", "receipt.xcresult"]), \
             contextlib.redirect_stdout(output):
            status = summary.main()
        return status, output.getvalue()

    def test_empty_unknown_receipt_from_disk_failure_is_not_success(self):
        status, output = self.run_receipt([], {"result": "unknown", "passedTests": 0, "failedTests": 0})
        self.assertEqual(status, 1)
        self.assertIn("INCOMPLETE", output)

    def test_unknown_completion_is_rejected_even_when_cases_look_passed(self):
        self.assertEqual(self.run_receipt(TREE, {"result": "unknown"})[0], 1)

    def test_empty_passed_receipt_and_all_skipped_run_are_rejected(self):
        self.assertEqual(self.run_receipt([], {"result": "Passed"})[0], 1)
        skipped = [{"nodeType": "UI test bundle", "name": "UI", "children": [
            {"nodeType": "Test Suite", "name": "Skipped", "children": [case("x", "Skipped")]}]}]
        self.assertEqual(self.run_receipt(skipped, {"result": "Passed"})[0], 1)

    def test_real_pass_with_expected_failure_negative_control_is_accepted(self):
        self.assertEqual(self.run_receipt(TREE, {"result": "Passed", "failedTests": 0})[0], 0)

    def test_reported_failure_is_not_masked_by_a_passed_summary(self):
        failed = [{"nodeType": "UI test bundle", "name": "UI", "children": [
            {"nodeType": "Test Suite", "name": "Failed", "children": [case("x", "Failed")]}]}]
        self.assertEqual(self.run_receipt(failed, {"result": "Passed"})[0], 1)
        self.assertEqual(self.run_receipt(TREE, {"result": "Passed", "failedTests": 1})[0], 1)

    def test_unknown_case_status_is_not_silently_dropped(self):
        unknown = [{"nodeType": "UI test bundle", "name": "UI", "children": [
            {"nodeType": "Test Suite", "name": "Unknown", "children": [case("a", "Passed"), case("b", "unknown")]}]}]
        self.assertEqual(self.run_receipt(unknown, {"result": "Passed"})[0], 1)

    def test_an_expected_failure_is_counted_in_its_own_column(self):
        rows = []
        summary.suite_rows(TREE, rows)
        lines = summary.format_table(rows)
        self.assertIn("expected", lines[0])
        self.assertEqual(lines[1].split(), ["JovraUITests/HarnessUITests", "1", "0", "1", "1"])
        self.assertEqual(summary.totals(rows), {"Passed": 1, "Failed": 0, "Skipped": 1, "Expected Failure": 1})


if __name__ == "__main__":
    unittest.main()
