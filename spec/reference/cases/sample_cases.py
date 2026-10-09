"""The Jon vs Alex sample match fixture (engine in jovra_ref.sample_match)."""

from __future__ import annotations

from jovra_ref import sample_match

ORDER = 40  # records (50) and the contract examples read the session file this writes


def generate(ctx) -> int:
    return sample_match.write(ctx.fixtures / "sample", ctx.write_json, ctx.version)
