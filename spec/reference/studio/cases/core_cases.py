"""The two fixture formats every other cases module writes: invalid-case sets (core.apply_patch patches applied to a
valid record) and reference vectors. Module page: spec/studio/modules/core.md.
"""

from __future__ import annotations

SCHEMAS = {
    "jovra.studio-fixture.invalid-cases/1": "fixture.schema.json",
    "jovra.studio-fixture.vectors/1": "fixture.schema.json",
}


def check_provenance_drift(ctx, report) -> None:
    """studio-common.schema.json's provenance enum is the app's (spec/schemas/common.schema.json), in order."""
    app = ctx.load("spec/schemas/common.schema.json")["$defs"]["provenanceStatus"]["enum"]
    studio = ctx.schemas.files["studio-common.schema.json"]["$defs"]["provenanceStatus"]["enum"]
    if app != studio:
        report.fail("drift", f"provenance enum {studio} != spec/schemas/common.schema.json {app}")
    else:
        report.ok("drift checks")


SELF_TESTS = {"core-provenance-drift": check_provenance_drift}
