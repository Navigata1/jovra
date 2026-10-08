#!/usr/bin/env python3
"""Builds the side-by-side evidence page: simulator screenshots next to the reference PNGs.

Usage: scripts/ios/side_by_side.py evidence/ios/<ticket> [--reviews FILE] [--out FILE]

Screenshots are paired with references by screen number: a screenshot named sNN-<anything>.png (or
.jpg) pairs with design-reference/screens/NN-*.png (screens 01-20),
design-reference/studio/screens/NN-*.png (21-40) or design-reference/adaptive/screens/NN-*.png (41 and
up: Android, watchOS, Wear OS and iOS fold). Other screenshots are left out of the page.

The references are AI-generated rasters, so pixel diffs mean nothing (spec, Testing Decisions): a
person or agent compares each pair and writes one reviewer line per screenshot in
<evidence>/reviews.txt:

    s03-light-home: Claude (T19 agent) — matches the reference; tile order follows the spec

i.e. "<screenshot name without extension>: <reviewer> — <verdict and notes>". Blank lines and lines
starting with # are ignored; "TODO" or an empty note does not count.

Exit status: 0 page written (or nothing to pair); 1 a screenshot names a screen with no reference;
2 a pair has no reviewer line (the page is not written and the missing lines are printed).
"""
from __future__ import annotations

import argparse
import html
import os
import pathlib
import re
import sys
from dataclasses import dataclass

SCREENSHOT = re.compile(r"^s(?P<screen>\d{2})[-_].+\.(?:png|jpe?g)$", re.I)
REVIEW = re.compile(r"^(?P<stem>[\w.-]+):\s*(?P<reviewer>[^—]*\S)\s+—\s+(?P<note>\S.*)$")


@dataclass(frozen=True)
class Pair:
    screen: int
    screenshot: pathlib.Path
    reference: pathlib.Path | None


REFERENCE_FOLDERS = (  # (last screen number, folder), in screen order
    (20, "design-reference/screens"),
    (40, "design-reference/studio/screens"),
    (99, "design-reference/adaptive/screens"),
)


def reference_for(screen: int, repo: pathlib.Path) -> pathlib.Path | None:
    folder = repo / next(path for last, path in REFERENCE_FOLDERS if screen <= last)
    matches = sorted(folder.glob(f"{screen:02d}-*.png"))
    return matches[0] if matches else None


def find_pairs(evidence: pathlib.Path, repo: pathlib.Path) -> list[Pair]:
    pairs = []
    for path in sorted(evidence.iterdir()):
        match = SCREENSHOT.match(path.name)
        if match:
            screen = int(match.group("screen"))
            pairs.append(Pair(screen, path, reference_for(screen, repo)))
    return sorted(pairs, key=lambda pair: (pair.screen, pair.screenshot.name))


def read_reviews(path: pathlib.Path) -> dict[str, str]:
    reviews = {}
    if not path.exists():
        return reviews
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = REVIEW.match(line)
        if match and match.group("note").strip().upper() not in {"TODO", "TBD"}:
            reviews[match.group("stem")] = f"{match.group('reviewer')} — {match.group('note')}"
    return reviews


def render(pairs: list[Pair], reviews: dict[str, str], out: pathlib.Path, title: str) -> str:
    rows = []
    for pair in pairs:
        reference = os.path.relpath(pair.reference, out.parent)
        screenshot = os.path.relpath(pair.screenshot, out.parent)
        review = reviews[pair.screenshot.stem]
        rows.append(f"""
  <section>
    <h2>Screen {pair.screen:02d} · {html.escape(pair.screenshot.stem)}</h2>
    <div class="pair">
      <figure><img src="{html.escape(reference)}" alt="Reference {pair.screen:02d}"><figcaption>Reference: {html.escape(pair.reference.name)}</figcaption></figure>
      <figure><img src="{html.escape(screenshot)}" alt="Simulator {html.escape(pair.screenshot.stem)}"><figcaption>Simulator: {html.escape(pair.screenshot.name)}</figcaption></figure>
    </div>
    <p class="review"><strong>Reviewer:</strong> {html.escape(review)}</p>
  </section>""")
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
  body {{ font: 15px/1.45 -apple-system, system-ui, sans-serif; margin: 24px; color: #182F29; background: #F4F1E8; }}
  .pair {{ display: flex; gap: 24px; flex-wrap: wrap; }}
  figure {{ margin: 0; }} img {{ max-height: 720px; max-width: 100%; border: 1px solid #DCD7CA; border-radius: 12px; }}
  section {{ margin-bottom: 40px; }} .review {{ background: #FBFAF6; padding: 8px 12px; border-radius: 8px; }}
</style></head><body>
<h1>{html.escape(title)}</h1>
<p>References are AI-generated rasters: they guide layout, rhythm, palette and hierarchy; the written spec wins.</p>
{"".join(rows)}
</body></html>
"""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("evidence", type=pathlib.Path)
    parser.add_argument("--reviews", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path)
    parser.add_argument("--repo", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    evidence = args.evidence.resolve()
    reviews_path = args.reviews or evidence / "reviews.txt"
    out = (args.out or evidence / "side-by-side.html").resolve()

    pairs = find_pairs(evidence, args.repo.resolve())
    if not pairs:
        print(f"side-by-side: no sNN-* screenshots in {evidence}; nothing to pair")
        return 0
    orphans = [pair for pair in pairs if pair.reference is None]
    for pair in orphans:
        print(f"side-by-side: {pair.screenshot.name} names screen {pair.screen:02d}, which has no reference PNG")
    if orphans:
        return 1
    reviews = read_reviews(reviews_path)
    missing = [pair for pair in pairs if pair.screenshot.stem not in reviews]
    if missing:
        print(f"side-by-side: {len(missing)} of {len(pairs)} pair(s) have no reviewer line in {reviews_path}.")
        print("Compare each pair, then add one line per screenshot, for example:")
        for pair in missing:
            print(f"  {pair.screenshot.stem}: <reviewer> — <verdict and notes against {pair.reference.name}>")
        return 2
    out.write_text(render(pairs, reviews, out, f"Side by side: {evidence.name}"), encoding="utf-8")
    print(f"side-by-side: {len(pairs)} reviewed pair(s) -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
