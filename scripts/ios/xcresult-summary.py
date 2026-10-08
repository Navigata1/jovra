#!/usr/bin/env python3
"""Prints per-class test counts for an .xcresult bundle, then its path.

Usage: scripts/ios/xcresult-summary.py <bundle.xcresult>

A row is printed for every test class or Swift Testing suite that directly holds test cases. A
parameterized Swift Testing test counts once (its argument runs are noted in the total line).
Exit status: 0 when every counted test passed or was skipped, 1 otherwise.
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


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    bundle = sys.argv[1]
    tests = load(bundle, "tests")
    summary = load(bundle, "summary")
    rows = []
    suite_rows(tests.get("testNodes", []), rows)
    width = max([len(label) for label, _ in rows] + [len("Test class")])
    print(f"{'Test class'.ljust(width)}  passed  failed  skipped")
    for label, counts in rows:
        print(f"{label.ljust(width)}  {counts['Passed']:>6}  {counts['Failed']:>6}  {counts['Skipped']:>7}")
    failed = sum(counts["Failed"] for _, counts in rows)
    passed = sum(counts["Passed"] for _, counts in rows)
    skipped = sum(counts["Skipped"] for _, counts in rows)
    print(f"Total: {passed} passed, {failed} failed, {skipped} skipped in {len(rows)} classes "
          f"(xcresult summary: {summary.get('passedTests', 0)} passed, {summary.get('failedTests', 0)} failed, "
          f"{summary.get('skippedTests', 0)} skipped; result {summary.get('result')})")
    for failure in summary.get("testFailures", []):
        print(f"FAILED {failure.get('testIdentifierString', '?')}: {failure.get('failureText', '')}")
    device = (summary.get("devicesAndConfigurations") or [{}])[0].get("device", {})
    if device:
        print(f"Device: {device.get('deviceName')} {device.get('deviceId')} ({device.get('modelName')}, "
              f"{device.get('platform')} {device.get('osVersion')})")
    print(f"Result bundle: {bundle}")
    return 0 if failed == 0 and summary.get("result") != "Failed" else 1


if __name__ == "__main__":
    sys.exit(main())
