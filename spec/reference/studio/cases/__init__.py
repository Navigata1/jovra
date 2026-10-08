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

    SELF_TESTS: dict[str, Callable[[ctx, rep], None]]
        Name -> a check of the module's contract that no fixture file expresses: drift between its schema and a
        shipped contract, deliberate mutations of the Sample project that must be refused, or a refusal the
        reference must make on its own. The validator calls each once. Names are unique across all cases modules.

Every vector checker (per case) and every self-test must call rep.ok(<count label>) or rep.fail(where, message) at
least once; one that does neither fails ("... neither passed nor failed ..."), so a checker cannot pass a case
silently. A raised core.Reject is reported as a failure.

The validator context `ctx` offers: root (the repository root), schemas (the ECMA-262 schema set), profiles_doc and
profiles (the story-profile catalog and id -> story profile), classes (credit-classes contract), transitions and
machine (RenderJob contract and its jobstate.Machine), records (name -> sample record), bundle (the sample project's
records by role), edl_context (the trusted EDL context), fixture(rel) (a parsed file under spec/studio/fixtures) and
load(rel) (a parsed JSON file relative to the repository root). The context is the one shared piece a contract may
need to extend (a new contract file or bundle role); everything else is added in its own files.

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
        self.self_tests: dict[str, object] = {}
        self.owner: dict[str, str] = {}   # registered kind (vector kind or schemaVersion) -> cases module path
        self.self_test_owner: dict[str, str] = {}   # self-test name -> cases module path
        self.problems: list[str] = []
        for module in modules:
            where = repo_path(module)
            for attr, target, owner in (("VECTOR_CHECKERS", self.checkers, self.owner),
                                        ("SCHEMAS", self.schemas, self.owner),
                                        ("RECORD_RULES", self.rules, None),
                                        ("SELF_TESTS", self.self_tests, self.self_test_owner)):
                for key, value in getattr(module, attr, {}).items():
                    if key in target:
                        first = (owner or self.owner).get(key, "?")
                        self.problems.append(f"{key} is registered twice ({first} and {where})")
                        continue
                    target[key] = value
                    if owner is not None:
                        owner[key] = where
        for version in self.rules:
            if version not in self.schemas:
                self.problems.append(f"reference rule for {version} has no registered schema")

    def kinds(self) -> list[str]:
        """Every registered kind: vector kinds and schemaVersions."""
        return sorted(set(self.checkers) | set(self.schemas))
