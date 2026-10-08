"""The two fixture formats every other cases module writes: invalid-case sets (core.apply_patch patches applied to a
valid record) and reference vectors. Module page: spec/studio/modules/core.md.
"""

from __future__ import annotations

SCHEMAS = {
    "jovra.studio-fixture.invalid-cases/1": "fixture.schema.json",
    "jovra.studio-fixture.vectors/1": "fixture.schema.json",
}
