#!/usr/bin/env python3
"""Validate JOVRA Studio's contracts (spec/schemas/studio, spec/studio). Standard library only.

Separate from scripts/spec/validate.py (the core contracts), which it never imports or changes.

1. Every Studio schema uses only keywords the bundled checker implements, every $ref resolves, and pattern anchors
   follow ECMA-262.
2. Contracts (spec/studio/contracts) validate against their registered schemas.
3. Every record fixture validates against the schema its schemaVersion names, then passes its registered reference
   rule.
4. Every invalid case is rejected by the expected layer: 'schema' cases fail the schema; 'reference' cases pass
   the schema and are rejected by the reference with the expected code.
5. Vectors: each vector file's `kind` is checked, case by case, by the checker its cases module registers (a kind
   with no checker fails, and so does a case its checker neither passes nor fails).
6. Self-tests: every SELF_TESTS entry of every cases module runs once (contract drift, deliberate mutations of the
   Sample project, refusals the reference makes on its own); one that neither passes nor fails is a failure.
7. Module pages (spec/studio/modules/*.md): every registered vector kind and schemaVersion appears in exactly one
   page's `kinds:` front matter, every page's kinds are registered, and spec/studio/README.md names no module (not
   its name as a whole word, its page path or its reference and cases files).
8. Determinism: regenerating the fixtures gives exactly the files on disk, and the module index is current.

Schemas, reference rules, vector checkers and self-tests are registered by the cases modules
(spec/reference/studio/cases/*_cases.py, discovered by file name); this script holds no per-module check. What stays
central is the generic passes above and the shared context Ctx (the loaded contracts, the Sample project's records by
role, the trusted EDL context and the job machine): a contract that needs a new contract file or bundle role on the
context edits Ctx, and nothing else here. Exit status is non-zero on any failure.

Usage:  python3 scripts/spec/validate_studio.py [-v]
        python3 scripts/spec/validate_studio.py --list   # every registered kind: type, count, module and status
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "spec"
SCHEMAS = SPEC / "schemas" / "studio"
STUDIO = SPEC / "studio"
FIX = STUDIO / "fixtures"
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(SPEC / "reference"))
sys.path.insert(0, str(SPEC / "reference" / "studio"))

import re  # noqa: E402

from jsonschema_subset import SchemaSet  # noqa: E402

from studio import bundle, jobstate  # noqa: E402
from studio import cases as studio_cases  # noqa: E402
from studio.core import Reject, apply_patch  # noqa: E402

MODULES = STUDIO / "modules"
MODULE_INDEX = MODULES / "README.md"
PAGE_KEYS = ("module", "reference", "cases", "kinds", "coverage", "swift", "kotlin")
PAGE_LISTS = ("reference", "cases", "kinds")
PAGE_ENUMS = {"coverage": ("covered", "not-covered"), "swift": ("pending", "consumed"), "kotlin": ("pending", "consumed")}


def ecma_pattern(pattern: str) -> str:
    r"""JSON Schema 2020-12 'pattern' is an ECMA-262 regex: without the multiline flag, '$' matches only at the very end
    of the input. Python's '$' also matches before a trailing newline, so 'c01\n' would pass '^...$'. Rewrite every
    unescaped '$' outside a character class as '\Z' (Python's end-of-input anchor)."""
    out, i, in_class = [], 0, False
    while i < len(pattern):
        ch = pattern[i]
        if ch == "\\":
            out.append(pattern[i:i + 2])
            i += 2
            continue
        if ch == "[" and not in_class:
            in_class = True
        elif ch == "]" and in_class:
            in_class = False
        out.append("\\Z" if ch == "$" and not in_class else ch)
        i += 1
    return "".join(out)


class StudioSchemaSet(SchemaSet):
    """The shared subset checker with ECMA-262 end anchors (scripts/spec/jsonschema_subset.py uses re.search, whose '$'
    accepts a trailing newline; that file belongs to the core gate, so Studio corrects the semantics here and the Swift
    and Kotlin ports must follow ECMA, not Python)."""

    def _pattern(self, pattern: str) -> re.Pattern:
        if pattern not in self._patterns:
            self._patterns[pattern] = re.compile(ecma_pattern(pattern))
        return self._patterns[pattern]


class Report:
    def __init__(self, verbose: bool):
        self.verbose = verbose
        self.failures: list[str] = []
        self.counts: dict[str, int] = {}
        self.marks = 0   # calls to ok() and fail(): a checker that makes none has neither passed nor failed

    def ok(self, what: str, n: int = 1) -> None:
        self.counts[what] = self.counts.get(what, 0) + n
        self.marks += 1

    def fail(self, where: str, message: str) -> None:
        self.failures.append(f"FAIL {where}: {message}")
        self.marks += 1

    def log(self, message: str) -> None:
        if self.verbose:
            print(message)


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class Ctx:
    """Loaded schemas, contracts and the sample project's records."""

    def __init__(self, registry: studio_cases.Registry):
        self.registry = registry
        self.root = ROOT
        self.schemas = StudioSchemaSet(SCHEMAS)
        self.profiles_doc = load(STUDIO / "contracts" / "story-profiles.v1.json")
        self.profiles = {p["id"]: p for p in self.profiles_doc["profiles"]}
        self.transitions = load(STUDIO / "contracts" / "render-job-transitions.v1.json")
        self.classes = load(STUDIO / "contracts" / "credit-classes.v1.json")
        self.machine = jobstate.Machine(self.transitions)
        self.records = {p.name[: -len(".json")]: load(p) for p in sorted((FIX / "records").glob("*.json"))}
        r = self.records
        self.bundle = {
            "lock": r["project-lock"], "manifest": r["source-manifest"], "syncMap": r["sync-map"],
            "keepers": r["keeper-catalog"], "brolls": r["broll-catalog"], "references": r["reference-catalog"],
            "plans": [d for d in r.values() if d["schemaVersion"] == "jovra.edit-plan/2"],
            "artifacts": [d for d in r.values() if d["schemaVersion"] == "jovra.delivered-artifact/1"],
            "jobs": {d["jobId"]: d for d in r.values() if d["schemaVersion"] == "jovra.render-job/1"},
            "reservations": {d["reservationId"]: d for d in r.values() if d["schemaVersion"] == "jovra.usage-reservation/1"},
            "quotes": {d["quoteId"]: d for d in r.values() if d["schemaVersion"] == "jovra.quote/1"},
            "briefs": [d for d in r.values() if d["schemaVersion"] == "jovra.story-brief/1"],
            "observations": [d for d in r.values() if d["schemaVersion"] == "jovra.observation/1"],
            "lessons": [d for d in r.values() if d["schemaVersion"] == "jovra.lesson/1"],
        }
        self.edl_context = bundle.edl_context(self.bundle)

    def fixture(self, rel: str):
        """A parsed file under spec/studio/fixtures."""
        return load(FIX / rel)

    def load(self, rel: str):
        """A parsed JSON file, by its path relative to the repository root."""
        return load(ROOT / rel)

    def schema_for(self, version) -> str | None:
        return self.registry.schemas.get(version)

    def semantic(self, doc: dict):
        """The reference rule for one record, as its cases module registered it (raises Reject)."""
        rule = self.registry.rules.get(doc["schemaVersion"])
        if rule is None:
            raise Reject("noReferenceRule", f"no reference rule registered for {doc['schemaVersion']}")
        return rule(self, doc)


# ----- 1-2: schemas, contracts --------------------------------------------------------------

def check_schemas(ctx: Ctx, rep: Report) -> None:
    for problem in ctx.schemas.check_all():
        rep.fail("schemas", problem)
    missing = set(ctx.registry.schemas.values()) - set(ctx.schemas.files)
    for name in sorted(missing):
        rep.fail("schemas", f"missing {name}")
    rep.ok("schemas checked", len(ctx.schemas.files))
    # the checker is not vacuous for these schemas
    if ctx.schemas._pattern("^[0-9a-f]{64}$").search("a" * 64 + "\n") or not ctx.schemas._pattern("^[0-9a-f]{64}$").search("a" * 64):
        rep.fail("schema self-test", "pattern anchors are not ECMA-262 ('$' must not accept a trailing newline)")
    else:
        rep.ok("schema self-tests")


def check_contracts(ctx: Ctx, rep: Report) -> None:
    for path in sorted((STUDIO / "contracts").glob("*.json")):
        doc = load(path)
        schema = ctx.schema_for(doc.get("schemaVersion"))
        errors = ctx.schemas.validate(doc, schema) if schema else [f"no schema registered for {doc.get('schemaVersion')!r}"]
        if errors:
            rep.fail(str(path.relative_to(ROOT)), "; ".join(errors[:5]))
            continue
        rep.ok("contracts valid")


# ----- 3: records --------------------------------------------------------------------

def check_records(ctx: Ctx, rep: Report) -> None:
    for name, doc in ctx.records.items():
        where = f"records/{name}.json"
        schema = ctx.schema_for(doc.get("schemaVersion"))
        if schema is None:
            rep.fail(where, f"no schema registered for {doc.get('schemaVersion')!r}")
            continue
        errors = ctx.schemas.validate(doc, schema)
        if errors:
            rep.fail(where, f"schema {schema}: " + "; ".join(errors[:5]))
            continue
        if not doc.get("sample", True):
            rep.fail(where, "every Studio fixture is fictional and must be labelled sample")
        try:
            result = ctx.semantic(doc)
        except Reject as exc:
            rep.fail(where, f"reference: {exc}")
            continue
        rep.log(f"ok {where} {result if isinstance(result, dict) and 'status' in result else ''}")
        rep.ok("records valid")


# ----- 4: invalid cases ---------------------------------------------------------------------------

def check_invalid(ctx: Ctx, rep: Report) -> None:
    for path in sorted((FIX / "invalid").glob("*.json")):
        where = str(path.relative_to(ROOT))
        doc = load(path)
        errors = ctx.schemas.validate(doc, "fixture.schema.json")
        if errors:
            rep.fail(where, "; ".join(errors[:3]))
            continue
        base = load(FIX / doc["base"])
        schema = ctx.schema_for(base["schemaVersion"])
        if schema is None:
            rep.fail(where, f"no schema registered for the base's {base['schemaVersion']!r}")
            continue
        for case in doc["cases"]:
            label = f"{where}#{case['id']}"
            try:
                bad = apply_patch(base, case["patch"])
            except (KeyError, IndexError, ValueError) as exc:
                rep.fail(label, f"patch does not apply: {exc}")
                continue
            schema_errors = ctx.schemas.validate(bad, schema)
            if case["expect"]["layer"] == "schema":
                if not schema_errors:
                    rep.fail(label, "expected a schema rejection; the schema accepted it")
                else:
                    rep.ok("invalid cases rejected (schema)")
                continue
            if schema_errors:
                rep.fail(label, "reference case must pass the schema first: " + "; ".join(schema_errors[:2]))
                continue
            try:
                ctx.semantic(bad)
            except Reject as exc:
                if exc.code != case["expect"]["code"]:
                    rep.fail(label, f"rejected with {exc.code} ({exc.message}), expected {case['expect']['code']}")
                else:
                    rep.ok("invalid cases rejected (reference)")
                continue
            rep.fail(label, f"accepted; expected {case['expect']['code']}")


# ----- 5-6: vectors and self-tests ---------------------------------------------------------------------------------

def check_vectors(ctx: Ctx, rep: Report) -> None:
    for path in sorted((FIX / "vectors").glob("*.json")):
        doc = load(path)
        errors = ctx.schemas.validate(doc, "fixture.schema.json")
        if errors:
            rep.fail(str(path.relative_to(ROOT)), "; ".join(errors[:3]))
            continue
        checker = ctx.registry.checkers.get(doc["kind"])
        if checker is None:
            rep.fail(str(path.relative_to(ROOT)), f"no checker for kind {doc['kind']} (register one in the VECTOR_CHECKERS "
                                                  "of the cases module that writes it)")
            continue
        for case in doc["cases"]:
            where = f"{path.relative_to(ROOT)}#{case['id']}"
            before = rep.marks
            try:
                checker(ctx, case, rep, where)
            except Reject as exc:
                rep.fail(where, str(exc))
            if rep.marks == before:
                rep.fail(where, f"checker for kind {doc['kind']} neither passed nor failed case {case['id']} (it must "
                                "call rep.ok or rep.fail)")


def run_self_tests(ctx: Ctx, rep: Report) -> None:
    """Every SELF_TESTS entry of every cases module, in module then registration order."""
    for name, test in ctx.registry.self_tests.items():
        owner = ctx.registry.self_test_owner[name]
        before = rep.marks
        try:
            test(ctx, rep)
        except Reject as exc:
            rep.fail(f"self-test {name}", str(exc))
        if rep.marks == before:
            rep.fail("self-tests", f"self-test {name} of {owner} neither passed nor failed (it must call rep.ok or "
                                   "rep.fail)")


# ----- 7: module pages ----------------------------------------------------------------------------

def parse_page(path: Path) -> dict:
    """The front matter of a module page: the first lines between two '---' lines, each 'key: value' with value a
    word or a flow list '[a, b]'. Exactly the keys in PAGE_KEYS. Raises ValueError."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        raise ValueError("no front matter (the page must start with a '---' line and close it with another)")
    meta: dict = {}
    for line in lines[1:lines.index("---", 1)]:
        key, sep, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if not sep or key in meta:
            raise ValueError(f"bad front matter line {line!r}")
        if key in PAGE_LISTS:
            if not (value.startswith("[") and value.endswith("]")):
                raise ValueError(f"{key} must be a flow list like [a, b]")
            meta[key] = [item.strip() for item in value[1:-1].split(",") if item.strip()]
        else:
            meta[key] = value
    if sorted(meta) != sorted(PAGE_KEYS):
        raise ValueError(f"front matter keys {sorted(meta)}, expected {sorted(PAGE_KEYS)}")
    if meta["module"] != path.stem:
        raise ValueError(f"module {meta['module']!r} differs from the file name")
    for key, allowed in PAGE_ENUMS.items():
        if meta[key] not in allowed:
            raise ValueError(f"{key}: {meta[key]!r} is not one of {', '.join(allowed)}")
    for key in ("reference", "cases"):
        for rel in meta[key]:
            if not (ROOT / rel).is_file():
                raise ValueError(f"{key} names {rel}, which does not exist")
    if meta["coverage"] == "covered" and not meta["kinds"]:
        raise ValueError("a covered module owns at least one kind")
    if meta["coverage"] == "not-covered" and meta["kinds"]:
        raise ValueError("a not-covered module has no fixtures yet, so it owns no kind")
    return meta


def load_pages(rep: Report | None = None) -> dict:
    """Module name -> parsed front matter, for every page under spec/studio/modules (the index excluded)."""
    pages = {}
    for path in sorted(MODULES.glob("*.md")):
        if path == MODULE_INDEX:
            continue
        try:
            pages[path.stem] = parse_page(path)
        except ValueError as exc:
            if rep is not None:
                rep.fail(str(path.relative_to(ROOT)), str(exc))
    return pages


def vector_cases_by_kind() -> dict:
    counts: dict = {}
    for path in sorted((FIX / "vectors").glob("*.json")):
        doc = load(path)
        counts[doc.get("kind")] = counts.get(doc.get("kind"), 0) + len(doc.get("cases", []))
    return counts


def check_modules(ctx: Ctx, rep: Report, pages: dict) -> None:
    registry = ctx.registry
    for problem in registry.problems:
        rep.fail("cases modules", problem)
    claimed: dict = {}
    for name, meta in pages.items():
        for kind in meta["kinds"]:
            if kind in claimed:
                rep.fail("module pages", f"kind {kind} is claimed by {claimed[kind]}.md and {name}.md")
            claimed[kind] = name
            if kind not in registry.owner:
                rep.fail(f"spec/studio/modules/{name}.md", f"names kind {kind}, which no cases module registers")
        rep.ok("module pages checked")
    on_disk = vector_cases_by_kind()
    for kind in registry.kinds():
        page = claimed.get(kind)
        if page is None:
            rep.fail("module pages", f"kind {kind} has no module page (add it to the kinds: of "
                                     "spec/studio/modules/<module>.md)")
            continue
        if registry.owner[kind] not in pages[page]["cases"]:
            rep.fail(f"spec/studio/modules/{page}.md", f"kind {kind} is registered by {registry.owner[kind]}, "
                                                       "which the page's cases: does not list")
            continue
        if kind in registry.checkers and kind not in on_disk:
            rep.fail("module pages", f"kind {kind} has a checker but no vector file")
            continue
        rep.ok("registered kinds with a module page")
    check_readme(rep, pages)


def readme_patterns(name: str, meta: dict) -> list:
    """What would make a README line a per-module line: the module's name as a whole word in any case (what
    `grep -iw <name>` finds, so '**Sync:**' or a 'Normalization' bullet counts), the page path, or a file name (or
    `stem.attribute`) of the module's reference or cases files."""
    patterns = [rf"(?i)(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", re.escape(f"modules/{name}.md")]
    for rel in meta["reference"] + meta["cases"]:
        stem = Path(rel).stem
        patterns += [rf"\b{re.escape(Path(rel).name)}\b", rf"\b{re.escape(stem)}\.[A-Za-z_]"]
    return [re.compile(p) for p in patterns]


def check_readme(rep: Report, pages: dict) -> None:
    readme = STUDIO / "README.md"
    text = readme.read_text(encoding="utf-8").splitlines()
    if not any("modules/README.md" in line for line in text):
        rep.fail("spec/studio/README.md", "does not link the generated module index modules/README.md")
    clean = True
    for name, meta in pages.items():
        for number, line in enumerate(text, 1):
            if any(p.search(line) for p in readme_patterns(name, meta)):
                rep.fail("spec/studio/README.md", f"names module {name} on line {number}; per-module text belongs on "
                                                  f"spec/studio/modules/{name}.md")
                clean = False
    if clean:
        rep.ok("README without per-module lines")


# ----- 8: determinism -----------------------------------------------------------------------------

def check_determinism(rep: Report) -> None:
    import generate_studio_fixtures as gen
    try:
        expected = gen.build()
    except gen.DeclarationError as exc:
        rep.fail("determinism", str(exc))
        return
    on_disk = {p.relative_to(FIX).as_posix(): load(p) for p in FIX.rglob("*.json")}
    for rel in sorted(set(expected) - set(on_disk)):
        rep.fail("determinism", f"generated file missing: {rel}; run spec/reference/studio/generate_studio_fixtures.py")
    for rel in sorted(set(on_disk) - set(expected)):
        rep.fail("determinism", f"file not written by any cases module: {rel}")
    for rel, doc in expected.items():
        if rel in on_disk and json.loads(json.dumps(doc)) != on_disk[rel]:
            rep.fail("determinism", f"{rel} is stale; run spec/reference/studio/generate_studio_fixtures.py")
    if gen.profile_catalog() != load(STUDIO / "contracts" / "story-profiles.v1.json"):
        rep.fail("determinism", "story-profiles.v1.json is stale")
    if not MODULE_INDEX.is_file() or MODULE_INDEX.read_text(encoding="utf-8") != gen.module_index():
        rep.fail("determinism", "spec/studio/modules/README.md is stale; run "
                                "spec/reference/studio/generate_studio_fixtures.py")
    rep.ok("generated files current", len(expected) + 2)


def list_kinds(ctx: Ctx, rep: Report, pages: dict) -> None:
    """--list: every registered kind with its type, count, invalid cases, module page and statuses, then every page
    that owns no kind (a not-covered module)."""
    page_of = {kind: name for name, meta in pages.items() for kind in meta["kinds"]}
    vectors = vector_cases_by_kind()
    records_by_version: dict = {}
    invalid_by_version: dict = {}
    for path in sorted(FIX.rglob("*.json")) + sorted((STUDIO / "contracts").glob("*.json")):
        doc = load(path)
        v = doc.get("schemaVersion")
        records_by_version[v] = records_by_version.get(v, 0) + 1
        if v == "jovra.studio-fixture.invalid-cases/1":
            base = load(FIX / doc["base"])["schemaVersion"]
            invalid_by_version[base] = invalid_by_version.get(base, 0) + len(doc["cases"])
    rows = [("kind", "type", "count", "invalid", "module", "coverage", "swift", "kotlin")]
    for kind in ctx.registry.kinds():
        meta = pages.get(page_of.get(kind), {})
        status = (page_of.get(kind, "(none)"), meta.get("coverage", "-"), meta.get("swift", "-"), meta.get("kotlin", "-"))
        if kind in ctx.registry.checkers:
            rows.append((kind, "vector", str(vectors.get(kind, 0)), "-", *status))
        else:
            rows.append((kind, "schema", str(records_by_version.get(kind, 0)), str(invalid_by_version.get(kind, 0)),
                         *status))
    for name, meta in pages.items():
        if not meta["kinds"]:
            rows.append((name, "page", "-", "-", name, meta["coverage"], meta["swift"], meta["kotlin"]))
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    for r in rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(r, widths)).rstrip())


def main() -> int:
    args = sys.argv[1:]
    rep = Report("-v" in args)
    try:
        registry = studio_cases.Registry(studio_cases.discover())
        ctx = Ctx(registry)
    except (OSError, KeyError, ValueError, ImportError) as exc:
        print(f"FAIL loading Studio contracts: {exc}")
        return 1
    pages = load_pages(rep)
    if "--list" in args:
        check_modules(ctx, rep, pages)
        list_kinds(ctx, rep, pages)
        for line in rep.failures:
            print(line)
        return 1 if rep.failures else 0
    check_schemas(ctx, rep)
    check_contracts(ctx, rep)
    check_records(ctx, rep)
    check_invalid(ctx, rep)
    check_vectors(ctx, rep)
    run_self_tests(ctx, rep)
    check_modules(ctx, rep, pages)
    check_determinism(rep)
    for line in rep.failures:
        print(line)
    width = max(len(k) for k in rep.counts) if rep.counts else 0
    for key, value in rep.counts.items():
        print(f"{key:<{width}}  {value}")
    print("RESULT:", "FAIL" if rep.failures else "PASS")
    return 1 if rep.failures else 0


if __name__ == "__main__":
    sys.exit(main())
