"""Mutation run for S06: copy the Studio contract tree to a temp dir, apply one mutation to the director or planner
reference, optionally regenerate the fixtures (so the stored expectations follow the mutant and only the hand
assertions, the lint, the schema and the determinism check can catch it), run the validator and report the result.
Usage: python3 mutate.py <repo root>"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1])
COPIED = ("scripts/spec", "spec", "design-reference/studio/brief")
D = "spec/reference/studio/director.py"
P = "spec/reference/studio/planner.py"

# (name, file, old, new, regenerate)
MUTATIONS = [
    ("delete-body:planner.plan", P, '    if "refusal" in briefed:\n', '    return {}\n    if "refusal" in briefed:\n',
     False),
    ("delete-body:director.lint", D, '    pid = plan["profile"]["id"]\n    profile = _profile(profiles, pid)\n    g = ',
     '    return []\n    pid = plan["profile"]["id"]\n    profile = _profile(profiles, pid)\n    g = ', True),
    ("full-ignores-coverage", D, 'seconds = min(hi, coverage) if length == "full"', 'seconds = hi if length == "full"',
     True),
    ("over-maximum-length-allowed", D, "    if seconds > hi:\n        return f", "    if False:\n        return f", True),
    ("no-keepers-not-refused", D, '    if not context["keepers"]:\n        return {"refusal": {"code": "noKeepers"',
     '    if False:\n        return {"refusal": {"code": "noKeepers"', True),
    ("music-without-rights-played", D, "            music_unavailable = music[\"assetId\"]",
     "            music_doc = {\"assetId\": music[\"assetId\"], \"rightsRecordId\": \"rights-\" + music[\"assetId\"]}",
     True),
    ("estimated-cue-instructs", P,
     'if c["provenance"] in director.AT_LEAST_REVIEWED and d.allowed("cue", c["cueId"]):',
     'if d.refs.get(c["cueId"]) is not None:', True),
    ("pad-past-the-target", P, '        if total + g["ms"] <= target_ms:', '        if True:', True),
    ("no-pass-to-the-minimum", P, '        if total >= min_ms:\n            break', '        break', True),
    ("compare-across-method-change", P, 'comparable = bool(got and got["comparable"])', 'comparable = bool(got)', True),
    ("no-arrival-card-without-broll", P, '    if not arrival:\n        d.add((0, 0), True, card("arrival"',
     '    if False:\n        d.add((0, 0), True, card("arrival"', True),
    ("broadcast-replay-from-primary", P, "keeper=kid, angle=slots[1], den=den", "keeper=kid, angle=slots[0], den=den",
     True),
    ("strict-chronology-off", D, '    strict = g["chronology"] == "strict"', "    strict = False", True),
    ("free-text-card-accepted", P, "    fields(beat, BEAT_FIELDS, label)\n", "", True),
    ("unknown-keeper-accepted", P, '        k = keepers.get(beat["keeperId"])\n',
     '        k = keepers.get(beat["keeperId"]) or {"slots": [beat["angle"]]}\n', True),
    ("nondeterministic-order", P, '    return sorted(chosen, key=lambda g: g["key"])',
     '    import random\n    random.shuffle(chosen)\n    return chosen', False),
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
                note = " (regenerated)" if g.returncode == 0 else \
                    f" (generator failed: {g.stderr.strip().splitlines()[-1][:160]})"
            v = run(tmp, "scripts/spec/validate_studio.py")
            fails = [line for line in v.stdout.splitlines() if line.startswith("FAIL")]
            result = v.stdout.strip().splitlines()[-1] if v.stdout.strip() else v.stderr.strip()[-200:]
            ok = v.returncode != 0 or "generator failed" in note
            caught += ok
            print(f"{name}{note}: {result}; {len(fails)} FAIL lines")
            for line in fails[:2]:
                print("    " + line[:230])
    print(f"caught {caught} of {len(MUTATIONS)} mutations")


main()
