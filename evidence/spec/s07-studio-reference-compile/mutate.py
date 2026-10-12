"""Mutation run for S07: copy the Studio contract tree to a temp dir, apply one mutation to the compile reference,
regenerate the fixtures (so the stored expectations follow the mutant and only the hand assertions, edl.validate, the
schema and the determinism check can catch it), run the validator and report the result.
Usage: python3 mutate.py <repo root>"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1])
COPIED = ("scripts/spec", "spec", "design-reference/studio/brief")
C = "spec/reference/studio/compile.py"

# (name, old, new)
MUTATIONS = [
    ("clean-frame-rule-off", "if k < 1:", "if False:"),
    ("upscale-allowed", "        return src.height < oh", "        return False"),
    ("no-gap-cards", 'if c.g["chronology"] != "strict":', "if True:"),
    ("final-card-over-gap", "and c.recording_gap():", "and False:"),
    ("titles-ignore-renderer-set", '        if op not in self.supported:\n            return "notInThisBuild"',
     '        if False:\n            return "notInThisBuild"'),
    ("replay-centre-floor-not-half-up", "centre = round_half_up(position(src, lsrc.session_us(anchor)))",
     "centre = position(src, lsrc.session_us(anchor)).__floor__()"),
    ("hold-bed-over-kept-play", "for k in c.keepers.values():", "for k in []:"),
    ("hold-bed-ignores-renderer-set", 'if item["op"] == "broll" or c.available("hold-bed")',
     'if item["op"] == "broll"'),
    ("fps-above-source-allowed", "        if slow:\n", "        if False:\n"),
    ("stage-allowlist-off", '        if op not in self.stage["ops"]:\n            return "notInThisStage"',
     '        if False:\n            return "notInThisStage"'),
    ("non-deterministic-plan-id", '"planId": c.request.get("planId") or',
     '"planId": __import__("uuid").uuid4().hex[:8] if not c.request.get("planId") else c.request.get("planId") or'),
]


def run(name: str, old: str, new: str) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        for rel in COPIED:
            shutil.copytree(ROOT / rel, Path(tmp) / rel)
        path = Path(tmp) / C
        text = path.read_text()
        assert old in text, f"{name}: mutation anchor not found"
        path.write_text(text.replace(old, new, 1))
        env = {"PYTHONDONTWRITEBYTECODE": "1", "PATH": "/usr/bin:/bin:/opt/homebrew/bin"}
        subprocess.run([sys.executable, "spec/reference/studio/generate_studio_fixtures.py"], cwd=tmp, env=env,
                       capture_output=True, text=True)
        out = subprocess.run([sys.executable, "scripts/spec/validate_studio.py"], cwd=tmp, env=env,
                             capture_output=True, text=True).stdout
        fails = [line for line in out.splitlines() if line.startswith("FAIL")]
        result = "RESULT: PASS" if "RESULT: PASS" in out else "RESULT: FAIL"
        body = "\n".join("    " + line[:300] for line in fails[:2])
        return f"{name} (regenerated): {result}; {len(fails)} FAIL lines\n{body}"


survived = 0
for m in MUTATIONS:
    line = run(*m)
    survived += "RESULT: PASS" in line
    print(line)
print(f"mutations: {len(MUTATIONS)}, survived: {survived}")
