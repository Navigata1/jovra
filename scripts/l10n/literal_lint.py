#!/usr/bin/env python3
"""Literal-string lint for the iOS app: user-visible text must come from a named String Catalog table.

Usage: scripts/l10n/literal_lint.py [path ...]      (default: ios/Jovra)

Accepted forms: Text("key", tableName: "Home"), String(localized: "key", table: "Home"),
LocalizedStringResource("key", table: "Home"), and Text(verbatim:) for text that is never translated
(the brand, the public contact address). Flagged, unless the call names a table:
  - a string literal as the first argument of a SwiftUI text-taking view (Text, Button, Label, ...);
  - a string literal passed to .accessibilityLabel/Hint/Value, .navigationTitle or .help;
  - a string literal in a display argument (title:, subtitle:, message:, text:, label:, caption:, ...)
    or assigned to a display property (var title = "...");
  - String(localized:) / LocalizedStringResource without table:;
  - a literal returned from a switch case inside a display property (var title/label/...: String).
Strings with no letters are ignored. `#Preview` blocks are skipped. A line ending in
`// l10n-lint: ignore (reason)` is skipped; a file starting with `// l10n-lint: ignore-file (reason)`
is skipped (the reason is required). Exit status 1 when anything is flagged.
"""
from __future__ import annotations

import pathlib
import re
import sys
from dataclasses import dataclass

VIEWS = ("Text|Button|Label|Toggle|Link|TextField|SecureField|Picker|Section|Menu|LabeledContent|"
         "Stepper|DatePicker|ProgressView|ContentUnavailableView|ShareLink|Tab|GroupBox|DisclosureGroup")
VIEW_CALL = re.compile(rf"(?<![\w.])(?:{VIEWS})\s*\(\s*(?=\")")
MODIFIER_CALL = re.compile(r"\.(?:accessibilityLabel|accessibilityHint|accessibilityValue|navigationTitle|help)\s*\(\s*(?=\")")
DISPLAY_ARGUMENT = re.compile(
    r"(?<![\w.])(?:title|subtitle|message|text|label|caption|placeholder|prompt|hint|detail|headline|footnote)\s*:\s*(?=\")")
LOCALIZED_CALL = re.compile(r"(?:String\s*\(\s*localized:\s*|LocalizedStringResource\s*\(\s*)(?=\")")
DISPLAY_PROPERTY = re.compile(
    r"\bvar\s+(?:title|subtitle|label|message|text|caption|headline|accessibility\w*|hint|displayName)\s*:\s*String\??\s*\{")
OTHER_PROPERTY = re.compile(r"\b(?:var|func|let|init|case\s+\w+\s*=)")
DISPLAY_DEFAULT = re.compile(
    r"\b(?:var|let)\s+(?:title|subtitle|label|message|text|caption|headline|hint|displayName)\s*(?::\s*String\??\s*)?=\s*(?=\")")
SWITCH_CASE_LITERAL = re.compile(r"^\s*(?:case\s+[^:]+|default)\s*:\s*(?:return\s+)?(?=\")")
LETTER = re.compile(r"[A-Za-z]")
IGNORE_LINE = re.compile(r"//\s*l10n-lint:\s*ignore\b(?!-file)")
IGNORE_FILE = re.compile(r"^\s*//\s*l10n-lint:\s*ignore-file\s*\((?P<reason>[^)]+)\)")
IGNORE_FILE_BARE = re.compile(r"^\s*//\s*l10n-lint:\s*ignore-file\b")


@dataclass(frozen=True)
class Violation:
    path: str
    line: int
    snippet: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.message}: {self.snippet}"


def _string_end(text: str, start: int) -> int:
    """Index just past the string literal starting at `start` (handles escapes, interpolation, \"\"\")."""
    if text.startswith('"""', start):
        end = text.find('"""', start + 3)
        return len(text) if end < 0 else end + 3
    index = start + 1
    while index < len(text):
        char = text[index]
        if char == "\\":
            if text.startswith("\\(", index):
                index = _call_end(text, index + 1)
                continue
            index += 2
            continue
        if char == '"' or char == "\n":
            return index + 1
        index += 1
    return index


def _call_end(text: str, open_paren: int) -> int:
    """Index just past the parenthesis matching the one at `open_paren`."""
    depth, index = 0, open_paren
    while index < len(text):
        char = text[index]
        if char == '"':
            index = _string_end(text, index)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return index


def _literal(text: str, start: int) -> str:
    return text[start:_string_end(text, start)]


def _enclosing_call(text: str, position: int) -> tuple[int, int] | None:
    """The (open, end) span of the innermost call whose parentheses contain `position`."""
    depth, index = 0, position - 1
    while index >= 0:
        char = text[index]
        if char == ")":
            depth += 1
        elif char == "(":
            if depth == 0:
                return index, _call_end(text, index)
            depth -= 1
        elif char == "\n" and text[max(0, index - 200):index].count("\n") > 8:
            break
        index -= 1
    return None


def _masked_regions(text: str) -> list[tuple[int, int]]:
    """Spans of `#Preview { ... }` blocks."""
    regions = []
    for match in re.finditer(r"#Preview\b[^{]*\{", text):
        depth, index = 0, match.end() - 1
        while index < len(text):
            if text[index] == '"':
                index = _string_end(text, index)
                continue
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        regions.append((match.start(), index + 1))
    return regions


def _comment_spans(text: str) -> list[tuple[int, int]]:
    spans, index = [], 0
    while index < len(text):
        if text[index] == '"':
            index = _string_end(text, index)
            continue
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = len(text) if end < 0 else end
            spans.append((index, end))
            index = end
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index)
            end = len(text) if end < 0 else end + 2
            spans.append((index, end))
            index = end
            continue
        index += 1
    return spans


def lint_source(text: str, path: str) -> list[Violation]:
    lines = text.splitlines()
    first_line = lines[0] if lines else ""
    violations: list[Violation] = []
    if IGNORE_FILE.match(first_line):
        return []
    if IGNORE_FILE_BARE.match(first_line):
        violations.append(Violation(path, 1, first_line.strip(), "ignore-file needs a reason in parentheses"))

    skipped = _masked_regions(text) + _comment_spans(text)
    line_starts = [0]
    for line in lines:
        line_starts.append(line_starts[-1] + len(line) + 1)

    def line_of(position: int) -> int:
        low, high = 0, len(line_starts) - 1
        while low < high:
            middle = (low + high + 1) // 2
            if line_starts[middle] <= position:
                low = middle
            else:
                high = middle - 1
        return low + 1

    def is_skipped(position: int) -> bool:
        if any(start <= position < end for start, end in skipped):
            return True
        line = lines[line_of(position) - 1]
        return bool(IGNORE_LINE.search(line))

    def report(position: int, snippet: str, message: str) -> None:
        violations.append(Violation(path, line_of(position), snippet.strip(), message))

    seen: set[int] = set()

    def check_call(pattern: re.Pattern[str], message: str, needs_table_in_call: bool) -> None:
        for match in pattern.finditer(text):
            literal_start = match.end()
            if literal_start in seen or is_skipped(match.start()):
                continue
            literal = _literal(text, literal_start)
            if not LETTER.search(literal):
                continue
            span = _enclosing_call(text, literal_start)
            call_text = text[span[0]:span[1]] if span else literal
            if needs_table_in_call and re.search(r"\b(?:tableName|table)\s*:", call_text):
                continue
            seen.add(literal_start)
            head_start = match.start()
            snippet = text[head_start:span[1]] if span and span[0] >= head_start - 1 else text[head_start:literal_start] + literal
            report(head_start, snippet, message)

    check_call(LOCALIZED_CALL, "localized string without a table", True)
    check_call(VIEW_CALL, "hard-coded text literal (use a catalog key with tableName:, or Text(verbatim:))", True)
    check_call(MODIFIER_CALL, "hard-coded accessibility or title literal (pass a String(localized:table:) or Text)", False)
    check_call(DISPLAY_ARGUMENT, "hard-coded display argument (pass String(localized:table:))", True)
    check_call(DISPLAY_DEFAULT, "hard-coded display property value (use String(localized:table:))", False)

    display_property_open = False
    for number, line in enumerate(lines, start=1):
        position = line_starts[number - 1]
        if DISPLAY_PROPERTY.search(line):
            display_property_open = True
            continue
        if OTHER_PROPERTY.search(line) and not line.strip().startswith("case ."):
            display_property_open = False
        if not display_property_open or is_skipped(position):
            continue
        match = SWITCH_CASE_LITERAL.match(line)
        if match and LETTER.search(_literal(line, match.end())):
            report(position, line, "hard-coded literal in a display property (use String(localized:table:))")
    return sorted(violations, key=lambda violation: violation.line)


def lint_paths(paths: list[pathlib.Path]) -> list[Violation]:
    violations: list[Violation] = []
    for root in paths:
        files = [root] if root.is_file() else sorted(root.rglob("*.swift"))
        for file in files:
            violations += lint_source(file.read_text(encoding="utf-8"), str(file))
    return violations


def main(argv: list[str]) -> int:
    root = pathlib.Path(__file__).resolve().parents[2]
    paths = [pathlib.Path(arg) for arg in argv] or [root / "ios" / "Jovra"]
    violations = lint_paths(paths)
    for violation in violations:
        print(violation)
    files = sum(1 if p.is_file() else len(list(p.rglob("*.swift"))) for p in paths)
    print(f"literal lint: {len(violations)} violation(s) in {files} Swift file(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
