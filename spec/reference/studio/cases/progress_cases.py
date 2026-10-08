"""Progress Story comparability vectors (`progress-comparison`) and their checker. Module page:
spec/studio/modules/progress.md.

The base scopes come from the Sample progress brief (records/story-brief.progress.json, comparison cmp-first-serve);
each case is that comparison or one deliberate change to it. "expect" comes from the reference (progress.py); every
"assert" block is hand-derived from the spec (user stories 134-137, ProgressStoryBuilder) and the core pct rule
(200n + d) div 2d, worked by hand, and is checked independently of the reference.
"""

from __future__ import annotations

import copy
import json

from studio import progress

KIND = "progress-comparison"
STAT = "first-serve-in-pct"
# Fields the brief does not carry: the sample is a serve practice, and the method id "manual-tagging-v1" is version 1.
SAMPLE_KIND = "practice"
SAMPLE_METHOD_VERSION = "1"
BANNED = ("improvement", "improved", "improve")


def sample_scopes(brief: dict) -> tuple[dict, dict]:
    """The Sample brief's comparison as the two scopes compare() takes."""
    cmp = brief["comparisons"][0]

    def scope(side: dict) -> dict:
        return {"date": side["date"], "sessionIds": list(side["sessionIds"]), "sessionKind": SAMPLE_KIND,
                "statDefinitionId": cmp["metricDefinitionId"], "methodId": cmp["methodId"],
                "methodVersion": SAMPLE_METHOD_VERSION, "capabilityVersion": None,
                "selectionRule": cmp["selectionRule"], "numerator": side["numerator"],
                "denominator": side["denominator"], "provenance": side["provenance"]}
    return scope(cmp["before"]), scope(cmp["after"])


def progress_vectors(brief: dict) -> dict:
    base_e, base_l = sample_scopes(brief)
    cases = []

    def case(cid, why, assertions, earlier=None, later=None, stat=STAT):
        e = copy.deepcopy(base_e)
        l = copy.deepcopy(base_l)
        e.update(earlier or {})
        l.update(later or {})
        inp = {"statDefinitionId": stat, "earlier": e, "later": l}
        c = {"id": cid, "why": why, "input": inp}
        c["expect"] = progress.run_vector(c)
        c["assert"] = assertions
        cases.append(c)

    case("sample-serve-practice", "Story 134: the Sample serve practice, 12 / 30 on Sep 9 and 18 / 30 on Oct 7",
         {"comparable": True, "reasons": [], "pct": [40, 60], "deltaPercentagePoints": 20,
          "summary": "12 / 30 · 40% → 18 / 30 · 60%, +20 percentage points", "claim": "change"})
    case("later-method-version-changed", "Story 135: the later session was tagged with method version 2",
         {"comparable": False, "reasonsInclude": ["methodChange"], "deltaPercentagePoints": None,
          "claim": "chronology"}, later={"methodVersion": "2"})
    case("later-capability-version-changed", "A capability version change is a method change too",
         {"comparable": False, "reasons": ["methodChange"], "claim": "chronology"},
         earlier={"capabilityVersion": "0.1.0"}, later={"capabilityVersion": "0.2.0"})
    case("user-chosen-one-side", "Story 136: hand-picked examples on one side only cannot be compared with all",
         {"comparable": False, "reasons": ["differingSelection"], "laterSelectionLabel": "Examples you chose",
          "earlierSelectionLabel": None}, later={"selectionRule": "user-chosen"})
    case("user-chosen-both-sides", "Both sides hand-picked: the rule matches, and each side is labelled",
         {"comparable": True, "reasons": [], "deltaPercentagePoints": 20,
          "earlierSelectionLabel": "Examples you chose", "laterSelectionLabel": "Examples you chose"},
         earlier={"selectionRule": "user-chosen"}, later={"selectionRule": "user-chosen"})
    case("seeded-random-vs-all", "A seeded random sample is not the same selection as all",
         {"comparable": False, "reasons": ["differingSelection"]}, earlier={"selectionRule": "seeded-random"})
    case("earlier-estimated", "Both sides must be at least Reviewed before any change is stated",
         {"comparable": False, "reasons": ["notReviewed"], "claim": "chronology"},
         earlier={"provenance": "estimated"})
    case("later-manual", "Manual (unreviewed) evidence on one side drops the comparison",
         {"comparable": False, "reasons": ["notReviewed"]}, later={"provenance": "manual"})
    case("both-validated", "Validated counts as at least Reviewed",
         {"comparable": True, "reasons": [], "deltaPercentagePoints": 20},
         earlier={"provenance": "validated"}, later={"provenance": "validated"})
    case("match-vs-practice", "A match is not compared with a practice",
         {"comparable": False, "reasons": ["sessionKindChange"]}, later={"sessionKind": "match"})
    case("different-stat-definition", "The later scope counts another stat",
         {"comparable": False, "reasons": ["statDefinitionChange"]},
         later={"statDefinitionId": "second-serve-in-pct"})
    case("several-reasons-in-order", "Every reason is reported, in the fixed order",
         {"comparable": False,
          "reasons": ["methodChange", "sessionKindChange", "differingSelection", "notReviewed"]},
         later={"methodVersion": "2", "sessionKind": "match", "selectionRule": "user-chosen",
                "provenance": "estimated"})
    case("no-change", "Same fraction: 0 percentage points, never a claim of change",
         {"comparable": True, "deltaPercentagePoints": 0, "deltaDisplay": "0 percentage points",
          "claim": "no-change"}, earlier={"numerator": 18})
    case("decline", "18 / 30 to 15 / 30: 60% to 50%",
         {"comparable": True, "pct": [60, 50], "deltaPercentagePoints": -10, "deltaDisplay": "-10 percentage points"},
         earlier={"numerator": 18}, later={"numerator": 15})
    case("one-point-singular", "1 / 4 (25%) to 13 / 50 (26%): one percentage point, singular",
         {"comparable": True, "pct": [25, 26], "deltaPercentagePoints": 1, "deltaDisplay": "+1 percentage point"},
         earlier={"numerator": 1, "denominator": 4}, later={"numerator": 13, "denominator": 50})
    case("delta-from-displayed-integers", "1 / 8 is 12.5% shown 13%, 5 / 16 is 31.25% shown 31%: the delta is 31 - 13 "
         "= 18 from the shown numbers, not 18.75 rounded to 19",
         {"comparable": True, "pct": [13, 31], "deltaPercentagePoints": 18},
         earlier={"numerator": 1, "denominator": 8}, later={"numerator": 5, "denominator": 16})
    case("half-up-at-ties", "3 / 8 is 37.5% shown 38% and 5 / 8 is 62.5% shown 63% (half up; half even "
         "would give 62)", {"comparable": True, "pct": [38, 63], "deltaPercentagePoints": 25},
         earlier={"numerator": 3, "denominator": 8}, later={"numerator": 5, "denominator": 8})
    case("no-earlier-evidence", "0 / 0 earlier: shown as an em dash and not comparable",
         {"comparable": False, "reasons": ["emptySample"], "earlierDisplay": "0 / 0 · —"},
         earlier={"numerator": 0, "denominator": 0})
    case("not-chronological", "The later scope must be dated after the earlier one",
         {"rejectCode": "notChronological"}, later={"date": "2026-09-09"})
    case("numerator-above-denominator", "31 / 30 is not a fraction of attempts",
         {"rejectCode": "badFraction"}, later={"numerator": 31})
    return {"schemaVersion": "jovra.studio-fixture.vectors/1", "kind": KIND,
            "status": "expect from spec/reference/studio/progress.py; assert blocks hand-derived from stories 134-137 "
                      "and the core pct rule", "cases": cases}


def fixtures(sample):
    return {"vectors/progress-comparison.json": progress_vectors(sample.records["records/story-brief.progress.json"])}


# ----- checker ------------------------------------------------------------------------------------

def _check_assertions(got: dict, a: dict) -> list:
    problems = []
    if "rejectCode" in a:
        if got.get("rejectCode") != a["rejectCode"]:
            problems.append(f"expected rejection {a['rejectCode']}, got {got}")
        return problems
    if "rejectCode" in got:
        return [f"rejected with {got['rejectCode']}"]
    checks = {
        "comparable": got["comparable"], "reasons": got["reasons"], "claim": got["claim"],
        "deltaPercentagePoints": got["deltaPercentagePoints"], "deltaDisplay": got["deltaDisplay"],
        "summary": got["summary"], "pct": [got["earlier"]["pct"], got["later"]["pct"]],
        "earlierSelectionLabel": got["earlier"]["selectionLabel"], "laterSelectionLabel": got["later"]["selectionLabel"],
        "earlierDisplay": got["earlier"]["display"],
    }
    for key, value in checks.items():
        if key in a and a[key] != value:
            problems.append(f"{key}: {value!r}, hand value {a[key]!r}")
    for reason in a.get("reasonsInclude", []):
        if reason not in got["reasons"]:
            problems.append(f"reason {reason} missing from {got['reasons']}")
    # a comparison that is dropped never carries a delta; no output ever states a percentage improvement
    if not got["comparable"] and (got["deltaPercentagePoints"] is not None or got["summary"] is not None):
        problems.append("a non-comparable result carries a delta")
    text = json.dumps(got, ensure_ascii=False).lower()
    if any(word in text for word in BANNED):
        problems.append("output words a change as an improvement")
    return problems


def check_progress_vector(ctx, case, report, where) -> None:
    got = progress.run_vector(case)
    if got != case["expect"]:
        report.fail(where, f"reference output differs from the stored expectation: {got}")
        return
    problems = _check_assertions(got, case["assert"])
    for problem in problems:
        report.fail(where, problem)
    if not problems:
        report.ok("progress-comparison vectors")


VECTOR_CHECKERS = {KIND: check_progress_vector}


# ----- self-test: the Sample brief's stored display agrees with the comparison ------------------------------

def check_brief_display(ctx, report) -> None:
    """The display strings the Sample progress brief stores are exactly what compare() gives for its scopes."""
    brief = ctx.records["story-brief.progress"]
    earlier, later = sample_scopes(brief)
    got = progress.compare(STAT, earlier, later)
    stored = brief["comparisons"][0]["display"]
    try:
        shown = {"before": got["earlier"]["display"], "after": got["later"]["display"], "delta": got["deltaDisplay"]}
    except (KeyError, TypeError) as exc:
        report.fail("progress brief", f"compare() gave no displays ({exc!r})")
        return
    if shown != stored:
        report.fail("progress brief", f"stored display {stored} differs from the comparison {shown}")
    else:
        report.ok("progress self-tests")


SELF_TESTS = {"progress-brief-display": check_brief_display}
