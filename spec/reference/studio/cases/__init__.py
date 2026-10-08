"""Studio cases modules, discovered by file name: every `spec/reference/studio/cases/*_cases.py` is one.

A later contract ticket adds its own cases module (and its module page under spec/studio/modules/) and never edits
a shared list: generate_studio_fixtures.py writes what each module declares, and scripts/spec/validate_studio.py
checks what each module registers. A cases module may define any of:

    fixtures(sample) -> dict[str, dict]
        Documents to write, keyed by path relative to spec/studio/fixtures ("vectors/x.json", "invalid/y.json",
        "records/z.json"). `sample` is the sample project built by generate_studio_fixtures.sample_project().
        Two modules may not declare the same path.

    VECTOR_CHECKERS: dict[str, Callable[[ctx, case, rep, where], None]]
        Vector kind -> checker. The validator calls the checker once per case of every vector file whose `kind`
        is that key; a vector kind with no checker fails ("no checker for kind <name>"). The checker re-runs the
        reference, compares its stored expectation and checks the hand-derived assertions, then calls
        rep.ok(<count label>) or rep.fail(where, message); a raised core.Reject is reported as a failure.

    SCHEMAS: dict[str, str]
        schemaVersion -> schema file name under spec/schemas/studio.

    RECORD_RULES: dict[str, Callable[[ctx, doc], object]]
        schemaVersion -> the reference rule for one record (raises core.Reject).

The validator context `ctx` offers: schemas (the ECMA-262 schema set), profiles (id -> story profile), classes
(credit-classes contract), transitions and machine (RenderJob contract and its jobstate.Machine), records
(name -> sample record), bundle (the sample project's records by role), edl_context (the trusted EDL context) and
fixture(rel) (a parsed file under spec/studio/fixtures).

Every vector kind and schemaVersion a module registers must appear in the `kinds:` front matter of exactly one
module page (spec/studio/modules/<module>.md), whose `cases:` list names the registering module.
"""

from __future__ import annotations

import importlib
from pathlib import Path
from types import ModuleType

HERE = Path(__file__).resolve().parent
SUFFIX = "_cases.py"


def module_files() -> list[Path]:
    """Every cases module file, in name order (the order never changes an output byte)."""
    return sorted(HERE.glob(f"*{SUFFIX}"))


def discover() -> list[ModuleType]:
    return [importlib.import_module(f"{__name__}.{path.stem}") for path in module_files()]


def repo_path(module: ModuleType) -> str:
    """The module's file relative to the repository root, as module pages name it."""
    return Path(module.__file__).resolve().relative_to(HERE.parents[3]).as_posix()


class Registry:
    """What the discovered cases modules register, with every conflict found while merging."""

    def __init__(self, modules: list[ModuleType]):
        self.modules = modules
        self.checkers: dict[str, object] = {}
        self.schemas: dict[str, str] = {}
        self.rules: dict[str, object] = {}
        self.owner: dict[str, str] = {}   # registered kind (vector kind or schemaVersion) -> cases module path
        self.problems: list[str] = []
        for module in modules:
            where = repo_path(module)
            for attr, target, owns in (("VECTOR_CHECKERS", self.checkers, True), ("SCHEMAS", self.schemas, True),
                                       ("RECORD_RULES", self.rules, False)):
                for key, value in getattr(module, attr, {}).items():
                    if key in target:
                        self.problems.append(f"{key} is registered twice ({self.owner.get(key, '?')} and {where})")
                        continue
                    target[key] = value
                    if owns:
                        self.owner[key] = where
        for version in self.rules:
            if version not in self.schemas:
                self.problems.append(f"reference rule for {version} has no registered schema")

    def kinds(self) -> list[str]:
        """Every registered kind: vector kinds and schemaVersions."""
        return sorted(set(self.checkers) | set(self.schemas))
