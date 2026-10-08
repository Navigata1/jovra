"""Mutation run for S05: copy the Studio contract tree to a temp dir, apply one mutation, optionally regenerate, run the
validator, and report whether it failed (and which hand assertions caught it)."""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1])
COPIED = ("scripts/spec", "spec", "design-reference/studio/brief")
REF = "spec/reference/studio/"

# (name, file, old, new, regenerate)
MUTATIONS = [
    ("delete-body:progress.compare", REF + "progress.py",
     '    e, l = _scope(earlier, "earlier"), _scope(later, "later")\n',
     '    return {}\n    e, l = _scope(earlier, "earlier"), _scope(later, "later")\n', False),
    ("delete-body:keepers.candidates", REF + "keepers.py",
     '    duration = _int(project["sessionDurationUs"], "sessionDurationUs")\n',
     '    return {"keepers": [], "unplaced": []}\n', False),
    ("delete-body:staleness.propagate", REF + "staleness.py",
     '    projects = copy.deepcopy(state["projects"])\n',
     '    return {}\n    projects = copy.deepcopy(state["projects"])\n', False),
    ("pre-roll-1s", REF + "keepers.py", "PRE_ROLL_US = 1_500_000", "PRE_ROLL_US = 1_000_000", True),
    ("estimated-never-absorbed", REF + "keepers.py",
     "        if any(c[\"protect\"][\"startUs\"] <= s[\"atUs\"] < c[\"protect\"][\"endUs\"] for c in out if c[\"label\"] is None):\n            continue\n",
     "", True),
    ("estimated-narrower-protection", REF + "keepers.py",
     '"protect": {"startUs": s["atUs"] - CONTACT_PAD_US, "endUs": s["atUs"] + CONTACT_PAD_US}})\n    return sorted',
     '"protect": {"startUs": s["atUs"] - CONTACT_PAD_US // 2, "endUs": s["atUs"] + CONTACT_PAD_US // 2}})\n    return sorted', True),
    ("no-cross-angle-dedupe", REF + "keepers.py",
     '        m = merged.get(p["eventId"])\n', '        m = None\n', True),
    ("needs-review-angle-offered", REF + "keepers.py",
     'USABLE_SYNC_STATES = ("reference", "reviewed")', 'USABLE_SYNC_STATES = ("reference", "reviewed", "needs-review")',
     True),
    ("rally-pulse-ignores-pressure", REF + "keepers.py",
     "    eligible.sort(key=lambda k: (0 if _pressure(k) else 1,", "    eligible.sort(key=lambda k: (0,", True),
    ("exclusion-ignored", REF + "keepers.py",
     '    kept = [k for k in keepers if k["keeperId"] not in excluded]', "    kept = list(keepers)", True),
    ("delta-from-exact-fractions", REF + "progress.py",
     '        delta = after["pct"] - before["pct"]',
     '        from fractions import Fraction\n        from studio.core import round_half_up\n'
     '        delta = round_half_up(Fraction(200 * l["numerator"], 2 * l["denominator"]) - Fraction(200 * e["numerator"], 2 * e["denominator"]))',
     True),
    ("method-version-ignored", REF + "progress.py",
     '    if (e["methodId"], e["methodVersion"], e["capabilityVersion"]) != (l["methodId"], l["methodVersion"],\n'
     '                                                                       l["capabilityVersion"]):',
     '    if (e["methodId"], e["capabilityVersion"]) != (l["methodId"], l["capabilityVersion"]):', True),
    ("selection-rule-ignored", REF + "progress.py",
     '    if e["selectionRule"] != l["selectionRule"]:', '    if False:', True),
    ("half-even-pct", REF + "progress.py", "    shown = pct(n, d)",
     "    shown = None if d == 0 else round(100 * n / d)", True),
    ("sync-change-stales-every-plan", REF + "staleness.py",
     '            if kind == "event" or named & set(uses):', '            if True:', True),
    ("event-change-crosses-projects", REF + "staleness.py",
     '            if dep["projectId"] != pid:\n                continue\n', '', True),
    ("film-dropped-when-stale", REF + "staleness.py",
     '                      "keptAsVersion": True})', '                      "keptAsVersion": not stale})', True),
]


def run(tmp, *args):
    return subprocess.run([sys.executable, *args], cwd=tmp, capture_output=True, text=True)


def main():
    caught = 0
    for name, rel, old, new, regen in MUTATIONS:
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            for part in COPIED:
                shutil.copytree(ROOT / part, tmp / part)
            path = tmp / rel
            text = path.read_text()
            if old not in text:
                print(f"{name}: MUTATION DID NOT APPLY")
                continue
            path.write_text(text.replace(old, new, 1))
            note = ""
            if regen:
                g = run(tmp, "spec/reference/studio/generate_studio_fixtures.py")
                note = " (regenerated)" if g.returncode == 0 else f" (generator failed: {g.stderr.strip().splitlines()[-1]})"
            v = run(tmp, "scripts/spec/validate_studio.py")
            fails = [l for l in v.stdout.splitlines() if l.startswith("FAIL")]
            result = v.stdout.strip().splitlines()[-1] if v.stdout.strip() else v.stderr.strip()[-200:]
            ok = v.returncode != 0 or (regen and "generator failed" in note)
            caught += ok
            print(f"{name}{note}: {result}; {len(fails)} FAIL lines")
            for line in fails[:2]:
                print("    " + line[:230])
    print(f"caught {caught} of {len(MUTATIONS)} mutations")


main()
