#!/usr/bin/env python3
"""Generate JovraStudioCore's typed Studio contract models and its embedded copy of the Studio schemas (S10).

Run from the repository root after any change under spec/schemas/studio:

    python3 ios/Packages/JovraStudioCore/Tools/generate_contract_models.py           # rewrite both files
    python3 ios/Packages/JovraStudioCore/Tools/generate_contract_models.py --check   # exit 1 if either is stale

It writes two files under Sources/JovraStudioCore/Contracts/Generated/:

- StudioContractModels.swift: named Codable structs and enums for every Studio record and contract data file
  (typed stored properties, Swift enums for schema choices, ContractNullable for required nullable fields,
  discriminated unions for oneOf). Shapes only: every constraint (patterns, ranges, if/then rules) is enforced by
  the strict decoder, which checks each document against the schema before these models see it.
- StudioSchemaSource.swift: the schema files, byte for byte, so the strict decoder runs on iOS and Linux without
  reading spec/ at runtime. A Swift test compares them with spec/schemas/studio and checks that the models were
  generated from the same bytes (the digest below), so a schema change without a regeneration fails the suite.

Standard library only. The output is deterministic (same bytes every run).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SCHEMAS = ROOT / "spec" / "schemas" / "studio"
DEST = ROOT / "ios" / "Packages" / "JovraStudioCore" / "Sources" / "JovraStudioCore" / "Contracts" / "Generated"
MODELS = DEST / "StudioContractModels.swift"
SOURCE = DEST / "StudioSchemaSource.swift"

# Every Studio record and contract data file this package reads and writes: (schema file, JSON pointer, Swift name).
# Order fixes which name a node shared by two roots keeps (the first root that reaches it).
ROOTS = [
    ("project-lock.schema.json", "", "ProjectLock"),
    ("source-manifest.schema.json", "", "SourceManifest"),
    ("sync-map.schema.json", "", "SyncMap"),
    ("observation.schema.json", "", "Observation"),
    ("keeper-catalog.schema.json", "", "KeeperCatalog"),
    ("broll-catalog.schema.json", "", "BrollCatalog"),
    ("story-profile.schema.json", "", "StoryProfileCatalog"),
    ("story-brief.schema.json", "", "StoryBrief"),
    ("edit-plan.schema.json", "", "EditPlan"),
    ("reference-catalog.schema.json", "", "ReferenceCatalog"),
    ("render-job.schema.json", "", "RenderJob"),
    ("quote.schema.json", "", "Quote"),
    ("usage-reservation.schema.json", "", "UsageReservation"),
    ("delivered-artifact.schema.json", "", "DeliveredArtifact"),
    ("lesson.schema.json", "", "Lesson"),
    ("camera-invite.schema.json", "", "CameraInvite"),
    ("storage-provider-capability.schema.json", "", "StorageProviders"),
    ("contracts.schema.json", "/$defs/transitions", "RenderJobTransitions"),
    ("contracts.schema.json", "/$defs/creditClasses", "CreditClasses"),
]

# Names for shared definitions (location -> Swift name). "Provenance" is JovraCore's ADR-0004 type, reused, not copied.
NAMES = {
    ("studio-common.schema.json", "/$defs/rational"): "StudioRational",
    ("studio-common.schema.json", "/$defs/fps"): "StudioFrameRate",
    ("studio-common.schema.json", "/$defs/rate"): "StudioClockRate",
    ("studio-common.schema.json", "/$defs/rationalTime"): "StudioRationalTime",
    ("studio-common.schema.json", "/$defs/intervalUs"): "StudioIntervalUs",
    ("studio-common.schema.json", "/$defs/frameWindow"): "StudioFrameWindow",
    ("studio-common.schema.json", "/$defs/positionMm"): "StudioCourtPositionMm",
    ("studio-common.schema.json", "/$defs/placementSlot"): "StudioPlacementSlot",
    ("studio-common.schema.json", "/$defs/provenanceStatus"): "Provenance",
    ("studio-common.schema.json", "/$defs/environment"): "StudioEnvironment",
    ("studio-common.schema.json", "/$defs/profileId"): "StudioProfileId",
    ("studio-common.schema.json", "/$defs/aspect"): "StudioAspect",
    ("studio-common.schema.json", "/$defs/segmentOp"): "StudioSegmentOp",
    ("studio-common.schema.json", "/$defs/transitionType"): "StudioTransitionType",
    ("studio-common.schema.json", "/$defs/audioRoute"): "StudioAudioRoute",
    ("studio-common.schema.json", "/$defs/overlayKind"): "StudioOverlayKind",
    ("studio-common.schema.json", "/$defs/gradePreset"): "StudioGradePreset",
    ("studio-common.schema.json", "/$defs/speed"): "StudioSpeed",
    ("story-profile.schema.json", "/$defs/profile"): "StoryProfile",
    ("render-job.schema.json", "/$defs/state"): "RenderJobState",
}
EXTERNAL = {"Provenance"}   # declared in JovraCore

KEYWORDS = set("""associatedtype class deinit enum extension fileprivate func import init inout internal let open operator
private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default
defer do else fallthrough for guard if in repeat return throw switch where while as Any false is nil self Self super
throws true try Type""".split())


class GenerationError(Exception):
    pass


def pascal(text: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in re.split(r"[^A-Za-z0-9]+", text) if part)


def camel(text: str) -> str:
    p = pascal(text)
    return p[:1].lower() + p[1:]


def identifier(text: str) -> str:
    return f"`{text}`" if text in KEYWORDS else text


def is_identifier(text: str) -> bool:
    return re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", text) is not None


def singular(word: str) -> str | None:
    """Plural property name -> element name ('segments' -> 'segment'); None when the word is not a plural."""
    if word.endswith("ies") and len(word) > 3:
        return word[:-3] + "y"
    for suffix in ("sses", "ches", "shes", "xes"):
        if word.endswith(suffix):
            return word[:-2]
    if word.endswith("s") and not word.endswith("ss") and len(word) > 1:
        return word[:-1]
    return None


def case_name(value) -> str:
    text = str(value)
    if re.match(r"^[0-9]", text):
        return "v" + re.sub(r"[^A-Za-z0-9]+", "_", text)
    name = camel(text)
    if not name:
        raise GenerationError(f"no Swift case name for {value!r}")
    return identifier(name)


def fnv1a64(files: list[tuple[str, bytes]]) -> str:
    """FNV-1a 64 over name, NUL, bytes, NUL for each file in name order (mirrored by StudioSchemaSource.digest(of:))."""
    h = 0xcbf29ce484222325
    for name, data in files:
        for byte in name.encode("utf-8") + b"\0" + data + b"\0":
            h ^= byte
            h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"


class Generator:
    def __init__(self) -> None:
        self.raw = {p.name: p.read_bytes() for p in sorted(SCHEMAS.glob("*.schema.json"))}
        self.docs = {name: json.loads(data) for name, data in self.raw.items()}
        self.memo: dict[tuple[str, str], str] = {}   # (file, pointer) -> Swift type expression
        self.output: dict[str, str] = {}             # Swift type name -> declaration
        self.owner: dict[str, tuple[str, str]] = {}  # Swift type name -> (file, pointer) that declared it

    # ----- schema navigation --------------------------------------------------------------------------------
    def node(self, file: str, pointer: str):
        node = self.docs[file]
        for token in [t for t in pointer.split("/") if t]:
            token = token.replace("~1", "/").replace("~0", "~")
            node = node[int(token)] if isinstance(node, list) else node[token]
        return node

    def resolve(self, ref: str, file: str) -> tuple[str, str]:
        target, _, pointer = ref.partition("#")
        return (target or file), pointer

    def location_name(self, file: str, pointer: str) -> str:
        named = dict(NAMES)
        named.update({(f, p): n for f, p, n in ROOTS})
        named[("studio-common.schema.json", "")] = "Studio"
        named[("contracts.schema.json", "")] = "StudioContractData"
        tokens = [t for t in pointer.split("/") if t]
        # Start from the longest named prefix of the pointer (a root or a shared definition), else the file's prefix.
        for cut in range(len(tokens), -1, -1):
            prefix = "".join("/" + t for t in tokens[:cut])
            if (file, prefix) in named:
                name, rest = named[(file, prefix)], tokens[cut:]
                break
        else:
            raise GenerationError(f"no name prefix for {file}#{pointer}")
        for token in rest:
            if token in ("properties", "$defs", "items"):
                continue  # element names come from the parent property, see element_name()
            name += "Value" if token == "additionalProperties" else pascal(token)
        return name

    # ----- type mapping -------------------------------------------------------------------------------------
    def type(self, schema, file: str, pointer: str, name: str) -> str:
        """The Swift type for the schema at (file, pointer); `name` is the name to give a declaration it needs."""
        if schema is True or schema is False:
            raise GenerationError(f"{file}#{pointer}: boolean schema has no Swift shape")
        key = (file, pointer)
        if key in self.memo:
            return self.memo[key]
        result = self._type(schema, file, pointer, name)
        self.memo[key] = result
        return result

    def _type(self, s: dict, file: str, pointer: str, name: str) -> str:
        if "$ref" in s:
            tf, tp = self.resolve(s["$ref"], file)
            return self.type(self.node(tf, tp), tf, tp, self.location_name(tf, tp))
        types = s.get("type")
        if isinstance(types, list):
            non_null = [t for t in types if t != "null"]
            if len(non_null) != 1 or "null" not in types:
                raise GenerationError(f"{file}#{pointer}: unsupported type list {types}")
            child = dict(s, type=non_null[0])
            return f"ContractNullable<{self._type(child, file, pointer, name)}>"
        if "oneOf" in s:
            members = s["oneOf"]
            non_null = [m for m in members if m != {"type": "null"}]
            if len(non_null) == 1 and len(members) == 2:
                return f"ContractNullable<{self.type(non_null[0], file, pointer + '/oneOf/' + str(members.index(non_null[0])), name)}>"
            if len(non_null) != len(members):
                raise GenerationError(f"{file}#{pointer}: nullable union of several members")
            return self.union(name, members, file, pointer)
        if "enum" in s:
            values = s["enum"]
            if None in values:
                child = dict(s, enum=[v for v in values if v is not None])
                return f"ContractNullable<{self._type(child, file, pointer, name)}>"
            if all(isinstance(v, str) for v in values):
                return self.string_enum(name, values, file, pointer)
            if all(isinstance(v, int) and not isinstance(v, bool) for v in values):
                return "Int"
            raise GenerationError(f"{file}#{pointer}: mixed enum {values}")
        if "const" in s:
            value = s["const"]
            if isinstance(value, bool):
                return "Bool"
            if isinstance(value, int):
                return "Int"
            if isinstance(value, str):
                return self.string_enum(name, [value], file, pointer)
            raise GenerationError(f"{file}#{pointer}: const {value!r} has no Swift shape")
        primitive = {"string": "String", "integer": "Int", "number": "Decimal", "boolean": "Bool"}
        if types in primitive:
            return primitive[types]
        if types == "array":
            if "items" in s:
                return f"[{self.type(s['items'], file, pointer + '/items', self.element_name(name))}]"
            prefix = s.get("prefixItems")
            if prefix:
                element = {self.type(p, file, f"{pointer}/prefixItems/{i}", self.element_name(name)) for i, p in enumerate(prefix)}
                if len(element) == 1 and s.get("maxItems") == len(prefix):
                    return f"[{element.pop()}]"
            raise GenerationError(f"{file}#{pointer}: array without items")
        if types == "object" or "properties" in s:
            if isinstance(s.get("additionalProperties"), dict) and not s.get("properties"):
                return f"[String: {self.type(s['additionalProperties'], file, pointer + '/additionalProperties', name + 'Value')}]"
            if s.get("additionalProperties") is not False:
                raise GenerationError(f"{file}#{pointer}: open object (additionalProperties must be false)")
            return self.struct(name, s, file, pointer)
        raise GenerationError(f"{file}#{pointer}: no Swift shape for {json.dumps(s)[:120]}")

    def element_name(self, name: str) -> str:
        """Array element name: the singular of the property part of `name` when it is a plural, else name + Item."""
        match = re.match(r"^(.*?)([A-Z][a-z0-9]*)$", name)
        if match:
            head, last = match.groups()
            one = singular(last.lower())
            if one is not None:
                return head + pascal(one)
        return name + "Item"

    def claim(self, name: str, file: str, pointer: str) -> bool:
        """Reserve a declaration name; False when this exact node already declared it."""
        if name in EXTERNAL:
            return False
        if name in self.owner:
            if self.owner[name] == (file, pointer):
                return False
            raise GenerationError(f"Swift name {name} is used by {self.owner[name]} and {(file, pointer)}")
        self.owner[name] = (file, pointer)
        return True

    def string_enum(self, name: str, values: list[str], file: str, pointer: str) -> str:
        if self.claim(name, file, pointer):
            cases = ["value"] if len(values) == 1 else [case_name(v) for v in values]
            if len(set(cases)) != len(cases):
                raise GenerationError(f"{name}: case names collide {cases}")
            body = "".join(f"    case {c} = {json.dumps(v, ensure_ascii=False)}\n" for c, v in zip(cases, values))
            self.output[name] = f"public enum {name}: String, Codable, CaseIterable, Hashable, Sendable {{\n{body}}}\n"
        return name

    def check_conditionals(self, s: dict, file: str, pointer: str) -> None:
        """if/then/else may constrain declared properties but never introduce one (the model would not hold it)."""
        declared = set(s.get("properties", {}))
        stack = [(s.get(k), f"{pointer}/{k}") for k in ("if", "then", "else")]
        for sub in s.get("allOf", []):
            stack += [(sub.get(k), f"{pointer}/allOf/{k}") for k in ("if", "then", "else")]
        while stack:
            node, where = stack.pop()
            if not isinstance(node, dict):
                continue
            extra = set(node.get("properties", {})) - declared
            if extra:
                raise GenerationError(f"{file}#{where}: conditional introduces undeclared properties {sorted(extra)}")
        if any("$ref" in sub or "properties" in sub for sub in s.get("allOf", [])):
            raise GenerationError(f"{file}#{pointer}: allOf merging is not supported for Studio records")

    def struct(self, name: str, s: dict, file: str, pointer: str) -> str:
        if not self.claim(name, file, pointer):
            return name
        self.output[name] = ""  # reserve the slot (recursive references)
        self.check_conditionals(s, file, pointer)
        required = s.get("required", [])
        fields = []
        for key, sub in s.get("properties", {}).items():
            swift = self.type(sub, file, f"{pointer}/properties/{key}", name + pascal(key))
            optional = key not in required
            if optional and swift.startswith("ContractNullable<"):
                raise GenerationError(f"{file}#{pointer}/properties/{key}: optional and nullable (absence and null "
                                      "would collapse); make it required")
            default = None
            if optional:
                swift += "?"
                default = "nil"
            elif self.output.get(swift, "").count("    case ") == 1 and "const" in self.resolved(sub, file):
                default = ".value"
            fields.append((key, swift, default))
        lines = [f"public struct {name}: Codable, Equatable, Sendable {{"]
        lines += [f"    public var {identifier(self.property(k))}: {t}" for k, t, _ in fields]
        if any(not is_identifier(k) or self.property(k) != k for k, _, _ in fields):
            lines += ["", "    private enum CodingKeys: String, CodingKey {"]
            lines += [f"        case {identifier(self.property(k))} = {json.dumps(k)}" for k, _, _ in fields]
            lines += ["    }"]
        params = ", ".join(f"{identifier(self.property(k))}: {t}" + (f" = {d}" if d else "") for k, t, d in fields)
        lines += ["", f"    public init({params}) {{"]
        lines += [f"        self.{self.property(k)} = {identifier(self.property(k))}" for k, _, _ in fields]
        lines += ["    }", "}"]
        self.output[name] = "\n".join(lines) + "\n"
        return name

    def property(self, key: str) -> str:
        return key if is_identifier(key) else camel(key)

    def resolved(self, s, file: str):
        while isinstance(s, dict) and "$ref" in s:
            tf, tp = self.resolve(s["$ref"], file)
            s, file = self.node(tf, tp), tf
        return s

    def union(self, name: str, members: list, file: str, pointer: str) -> str:
        if not self.claim(name, file, pointer):
            return name
        self.output[name] = ""
        bodies = []
        for i, member in enumerate(members):
            tf, tp = (self.resolve(member["$ref"], file) if "$ref" in member else (file, f"{pointer}/oneOf/{i}"))
            bodies.append((tf, tp, self.node(tf, tp)))
        discriminator = self.discriminator([b for _, _, b in bodies])
        if discriminator is None:
            return self.kind_union(name, bodies)
        cases = []
        for tf, tp, body in bodies:
            prop = body["properties"][discriminator]
            values = prop["enum"] if "enum" in prop else [prop["const"]]
            case = camel("-or-".join(values))
            member_name = self.location_name(tf, tp) if tp.startswith("/$defs/") and "/oneOf/" not in tp else name + pascal(case)
            swift = self.type(body, tf, tp, member_name)
            cases.append((identifier(case), swift, values))
        lines = [f"public enum {name}: Codable, Equatable, Sendable {{"]
        lines += [f"    case {c}({t})" for c, t, _ in cases]
        lines += ["", f"    private enum CodingKeys: String, CodingKey {{ case {identifier(discriminator)} }}", "",
                  "    public init(from decoder: Decoder) throws {",
                  "        let container = try decoder.container(keyedBy: CodingKeys.self)",
                  f"        switch try container.decode(String.self, forKey: .{identifier(discriminator)}) {{"]
        for c, t, values in cases:
            lines.append(f"        case {', '.join(json.dumps(v) for v in values)}: self = .{c}(try {t}(from: decoder))")
        lines += [f"        default: throw DecodingError.dataCorruptedError(forKey: .{identifier(discriminator)}, in: container, "
                  f"debugDescription: \"Unknown {name} {discriminator}\")",
                  "        }", "    }", "", "    public func encode(to encoder: Encoder) throws {", "        switch self {"]
        lines += [f"        case .{c}(let value): try value.encode(to: encoder)" for c, _, _ in cases]
        lines += ["        }", "    }", "}"]
        self.output[name] = "\n".join(lines) + "\n"
        return name

    def discriminator(self, bodies: list) -> str | None:
        if not all(isinstance(b, dict) and b.get("type") == "object" for b in bodies):
            return None
        for field in ("op", "mode", "type", "kind"):
            seen: list = []
            for body in bodies:
                prop = body.get("properties", {}).get(field, {})
                if "const" in prop and isinstance(prop["const"], str):
                    seen.append([prop["const"]])
                elif "enum" in prop and all(isinstance(v, str) for v in prop["enum"]):
                    seen.append(prop["enum"])
                else:
                    break
            else:
                flat = [v for values in seen for v in values]
                if len(flat) == len(set(flat)) and all(field in b.get("required", []) for b in bodies):
                    return field
        raise GenerationError(f"union of objects without a string discriminator: {[list(b.get('properties', {})) for b in bodies]}")

    def kind_union(self, name: str, bodies: list) -> str:
        """oneOf whose members differ by JSON type (a text or a list of texts)."""
        cases = []
        for tf, tp, body in bodies:
            body = self.resolved(body, tf)
            kind = body.get("type")
            if kind == "string":
                cases.append(("text", "String"))
            elif kind == "array":
                cases.append(("list", self.type(body, tf, tp, name + "List")))
            else:
                raise GenerationError(f"{name}: union member of type {kind!r} is not supported")
        if len({c for c, _ in cases}) != len(cases):
            raise GenerationError(f"{name}: members share a JSON type")
        lines = [f"public enum {name}: Codable, Equatable, Sendable {{"]
        lines += [f"    case {c}({t})" for c, t in cases]
        lines += ["", "    public init(from decoder: Decoder) throws {",
                  "        let container = try decoder.singleValueContainer()"]
        for i, (c, t) in enumerate(cases):
            if i < len(cases) - 1:
                lines.append(f"        if let value = try? container.decode({t}.self) {{ self = .{c}(value); return }}")
            else:
                lines.append(f"        self = .{c}(try container.decode({t}.self))")
        lines += ["    }", "", "    public func encode(to encoder: Encoder) throws {",
                  "        var container = encoder.singleValueContainer()", "        switch self {"]
        lines += [f"        case .{c}(let value): try container.encode(value)" for c, _ in cases]
        lines += ["        }", "    }", "}"]
        self.output[name] = "\n".join(lines) + "\n"
        return name

    # ----- output -------------------------------------------------------------------------------------------
    def models(self, digest: str) -> str:
        conformances = []
        for file, pointer, name in ROOTS:
            swift = self.type(self.node(file, pointer), file, pointer, name)
            if swift != name:
                raise GenerationError(f"root {name} mapped to {swift}")
            version = self.node(file, pointer)["properties"]["schemaVersion"]["const"]
            conformances.append(
                f"extension {name}: StudioContract {{\n"
                f"    public static let schemaVersion = {json.dumps(version)}\n"
                f"    public static let schemaLocation = StudioSchemaLocation(file: {json.dumps(file)}, pointer: {json.dumps(pointer)})\n"
                f"}}\n")
        header = (
            "// Generated by ios/Packages/JovraStudioCore/Tools/generate_contract_models.py from spec/schemas/studio.\n"
            "// Do not edit. Shapes only: StudioContractCodec checks every document against its schema first.\n"
            "import Foundation\nimport JovraCore\n\n"
            "/// The schema bytes these models were generated from (StudioSchemaSource.digest(of:)).\n"
            f"public enum StudioContractModels {{\n    public static let schemaDigest = \"{digest}\"\n}}\n\n")
        return header + "\n".join(self.output[k] for k in sorted(self.output)) + "\n" + "\n".join(conformances)

    def source(self, digest: str) -> str:
        parts = []
        for name, data in self.raw.items():
            text = data.decode("utf-8")
            if '"""#' in text or not text.endswith("\n"):
                raise GenerationError(f"{name} cannot be embedded as a raw string (needs a final newline, no '\"\"\"#')")
            parts.append(f"        {json.dumps(name)}: #\"\"\"\n{text}\"\"\"#,\n")
        return (
            "// Generated by ios/Packages/JovraStudioCore/Tools/generate_contract_models.py from spec/schemas/studio.\n"
            "// Do not edit: a test compares every entry with spec/schemas/studio byte for byte.\n\n"
            "extension StudioSchemaSource {\n"
            "    /// spec/schemas/studio/*.schema.json by file name, each without its final newline.\n"
            "    static let embedded: [String: String] = [\n" + "".join(parts) + "    ]\n\n"
            f"    /// The digest of the embedded files when they were generated.\n"
            f"    static let generatedDigest = \"{digest}\"\n"
            "}\n")

    def run(self, check: bool) -> int:
        digest = fnv1a64(sorted((name, data.rstrip(b"\n")) for name, data in self.raw.items()))
        outputs = {MODELS: self.models(digest), SOURCE: self.source(digest)}
        stale = [p for p, text in outputs.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        if check:
            for path in stale:
                print(f"stale: {path.relative_to(ROOT)} (run {Path(__file__).relative_to(ROOT)})")
            return 1 if stale else 0
        DEST.mkdir(parents=True, exist_ok=True)
        for path, text in outputs.items():
            path.write_text(text, encoding="utf-8")
        print(f"Generated {len(self.output)} models/enums for {len(ROOTS)} contracts; embedded {len(self.raw)} schemas; "
              f"digest {digest}")
        return 0


if __name__ == "__main__":
    try:
        sys.exit(Generator().run("--check" in sys.argv[1:]))
    except GenerationError as exc:
        print(f"generation failed: {exc}", file=sys.stderr)
        sys.exit(2)
