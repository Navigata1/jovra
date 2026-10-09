#!/usr/bin/env python3
"""Prints per-class test counts for an .xcresult bundle, then its path.

Usage: scripts/ios/xcresult-summary.py <bundle.xcresult>

A row is printed for every test class or Swift Testing suite that directly holds test cases, with
passed, failed, skipped and expected-failure (XCTExpectFailure) counts, so every test case is counted.
A parameterized Swift Testing test counts once (its argument runs are noted in the total line).
Exit status: 0 only for a completed Passed receipt with executed cases and no failure, 1 otherwise.
"""
import json
import subprocess
import sys


def load(bundle, kind):
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", bundle],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(output)


def suite_rows(nodes, rows, prefix=""):
    """Collects (identifier, counts) for each suite that directly contains test cases."""
    for node in nodes:
        kind = node.get("nodeType")
        children = node.get("children", [])
        if kind in ("Unit test bundle", "UI test bundle", "Test Plan"):
            suite_rows(children, rows, node.get("name", ""))
            continue
        if kind != "Test Suite":
            continue
        cases = [child for child in children if child.get("nodeType") == "Test Case"]
        if cases:
            url = node.get("nodeIdentifierURL", "")
            identifier = "/".join(url.split("/")[-2:]) if url else f"{prefix}/{node.get('name')}"
            counts = {"Passed": 0, "Failed": 0, "Skipped": 0, "Expected Failure": 0}
            for case in cases:
                counts[case.get("result", "Failed")] = counts.get(case.get("result", "Failed"), 0) + 1
            name = node.get("name", "")
            label = identifier if identifier.endswith(name) else f"{identifier} ({name})"
            rows.append((label, counts))
        suite_rows([child for child in children if child.get("nodeType") == "Test Suite"], rows, prefix)


COLUMNS = (("Passed", "passed"), ("Failed", "failed"), ("Skipped", "skipped"), ("Expected Failure", "expected"))


def totals(rows):
    return {key: sum(counts.get(key, 0) for _, counts in rows) for key, _ in COLUMNS}


def format_table(rows):
    """The header and one line per class: passed, failed, skipped, expected failures."""
    width = max([len(label) for label, _ in rows] + [len("Test class")])
    lines = ["  ".join(["Test class".ljust(width)] + [title for _, title in COLUMNS])]
    for label, counts in rows:
        lines.append("  ".join([label.ljust(width)] + [str(counts.get(key, 0)).rjust(len(title)) for key, title in COLUMNS]))
    return lines


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    bundle = sys.argv[1]
    tests = load(bundle, "tests")
    summary = load(bundle, "summary")
    rows = []
    suite_rows(tests.get("testNodes", []), rows)
    for line in format_table(rows):
        print(line)
    total = totals(rows)
    passed, failed, skipped, expected = (total[key] for key, _ in COLUMNS)
    print(f"Total: {passed} passed, {failed} failed, {skipped} skipped, {expected} expected failure(s) in {len(rows)} classes "
          f"(xcresult summary: {summary.get('passedTests', 0)} passed, {summary.get('failedTests', 0)} failed, "
          f"{summary.get('skippedTests', 0)} skipped; result {summary.get('result')})")
    for failure in summary.get("testFailures", []):
        print(f"FAILED {failure.get('testIdentifierString', '?')}: {failure.get('failureText', '')}")
    device = (summary.get("devicesAndConfigurations") or [{}])[0].get("device", {})
    if device:
        print(f"Device: {device.get('deviceName')} {device.get('deviceId')} ({device.get('modelName')}, "
              f"{device.get('platform')} {device.get('osVersion')})")
    print(f"Result bundle: {bundle}")
    # A disk failure can leave a readable bundle with result "unknown" and no summaries. That is
    # not a passing test run. Count expected failures as executed (the harness has negative controls),
    # but never accept an empty/all-skipped run or silently ignore a new/unknown case status.
    complete = summary.get("result") == "Passed" and passed + expected > 0
    known_results = {key for key, _ in COLUMNS}
    unknown_cases = any(value > 0 for _, counts in rows for key, value in counts.items() if key not in known_results)
    if not complete or unknown_cases:
        print("INCOMPLETE TEST RESULT: require a Passed receipt with executed, recognized test cases.")
    return 0 if complete and not unknown_cases and failed == 0 and summary.get("failedTests", 0) == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
