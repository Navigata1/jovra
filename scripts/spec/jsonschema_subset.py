"""A minimal, dependency-free JSON Schema (draft 2020-12) checker for the subset JOVRA's schemas use.

It refuses any keyword it does not implement (``check_schema``), so a schema can never rely on a
keyword that is silently ignored here. ``format`` is treated as an annotation, as 2020-12 allows.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

ANNOTATIONS = {"$schema", "$comment", "title", "description", "default", "examples", "deprecated", "format"}
APPLICATORS = {"$ref", "$defs", "allOf", "anyOf", "oneOf", "not", "if", "then", "else", "properties",
               "patternProperties", "additionalProperties", "propertyNames", "items", "prefixItems", "contains"}
ASSERTIONS = {"type", "enum", "const", "required", "minProperties", "maxProperties", "dependentRequired",
              "minItems", "maxItems", "uniqueItems", "minimum", "maximum", "exclusiveMinimum",
              "exclusiveMaximum", "multipleOf", "minLength", "maxLength", "pattern"}
SUPPORTED = ANNOTATIONS | APPLICATORS | ASSERTIONS


class SchemaError(Exception):
    pass


def json_type(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    raise SchemaError(f"not a JSON value: {value!r}")


def json_equal(a, b) -> bool:
    ta, tb = json_type(a), json_type(b)
    numeric = {"integer", "number"}
    if ta in numeric and tb in numeric:
        return a == b
    if ta != tb:
        return False
    if ta == "array":
        return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b))
    if ta == "object":
        return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)
    return a == b


def _type_matches(value, expected: str) -> bool:
    actual = json_type(value)
    if expected == "number":
        return actual in ("integer", "number")
    if expected == "integer":
        return actual == "integer" or (actual == "number" and math.isfinite(value) and value.is_integer())
    return actual == expected


class SchemaSet:
    def __init__(self, schema_dir: Path):
        self.dir = Path(schema_dir)
        self.files: dict[str, dict] = {}
        for path in sorted(self.dir.glob("*.schema.json")):
            self.files[path.name] = json.loads(path.read_text(encoding="utf-8"))
        self._patterns: dict[str, re.Pattern] = {}

    # ----- schema meta-checks --------------------------------------------------------------
    def check_all(self) -> list[str]:
        problems = []
        for name, schema in self.files.items():
            problems += self._check(schema, name, "#")
        return problems

    def _check(self, schema, file: str, where: str) -> list[str]:
        if isinstance(schema, bool):
            return []
        if not isinstance(schema, dict):
            return [f"{file}{where}: schema must be an object or boolean"]
        problems = []
        for key in schema:
            if key not in SUPPORTED:
                problems.append(f"{file}{where}: unsupported keyword {key!r}")
        if "$ref" in schema:
            try:
                self.resolve(schema["$ref"], file)
            except SchemaError as exc:
                problems.append(f"{file}{where}: {exc}")
        if "pattern" in schema:
            try:
                re.compile(schema["pattern"])
            except re.error as exc:
                problems.append(f"{file}{where}: bad pattern ({exc})")
        for key in ("$defs", "properties", "patternProperties"):
            for sub_key, sub in schema.get(key, {}).items():
                problems += self._check(sub, file, f"{where}/{key}/{sub_key}")
        for key in ("allOf", "anyOf", "oneOf", "prefixItems"):
            for i, sub in enumerate(schema.get(key, [])):
                problems += self._check(sub, file, f"{where}/{key}/{i}")
        for key in ("not", "if", "then", "else", "additionalProperties", "propertyNames", "items", "contains"):
            if key in schema:
                problems += self._check(schema[key], file, f"{where}/{key}")
        return problems

    def resolve(self, ref: str, base_file: str):
        file_part, _, pointer = ref.partition("#")
        file = file_part or base_file
        if file not in self.files:
            raise SchemaError(f"unresolvable $ref {ref!r} (no file {file!r})")
        node = self.files[file]
        if pointer:
            for token in pointer.lstrip("/").split("/"):
                token = token.replace("~1", "/").replace("~0", "~")
                if not isinstance(node, dict) or token not in node:
                    raise SchemaError(f"unresolvable $ref {ref!r}")
                node = node[token]
        return node, file

    # ----- validation ------------------------------------------------------------------------
    def validate(self, instance, schema_file: str) -> list[str]:
        return self._validate(instance, self.files[schema_file], schema_file, "$")

    def _pattern(self, pattern: str) -> re.Pattern:
        if pattern not in self._patterns:
            self._patterns[pattern] = re.compile(pattern)
        return self._patterns[pattern]

    def _validate(self, value, schema, file: str, path: str) -> list[str]:
        if schema is True:
            return []
        if schema is False:
            return [f"{path}: no value is allowed here"]
        errors: list[str] = []
        if "$ref" in schema:
            target, target_file = self.resolve(schema["$ref"], file)
            errors += self._validate(value, target, target_file, path)
        if "type" in schema:
            types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
            if not any(_type_matches(value, t) for t in types):
                return errors + [f"{path}: expected type {types}, got {json_type(value)}"]
        if "enum" in schema and not any(json_equal(value, c) for c in schema["enum"]):
            errors.append(f"{path}: {value!r} not in {schema['enum']}")
        if "const" in schema and not json_equal(value, schema["const"]):
            errors.append(f"{path}: expected const {schema['const']!r}, got {value!r}")
        kind = json_type(value)
        if kind in ("integer", "number"):
            errors += self._numeric(value, schema, path)
        elif kind == "string":
            errors += self._string(value, schema, path)
        elif kind == "array":
            errors += self._array(value, schema, file, path)
        elif kind == "object":
            errors += self._object(value, schema, file, path)
        for sub in schema.get("allOf", []):
            errors += self._validate(value, sub, file, path)
        if "anyOf" in schema:
            if not any(not self._validate(value, sub, file, path) for sub in schema["anyOf"]):
                errors.append(f"{path}: matches none of anyOf")
        if "oneOf" in schema:
            results = [self._validate(value, sub, file, path) for sub in schema["oneOf"]]
            passing = sum(1 for r in results if not r)
            if passing != 1:
                detail = "" if passing else "; closest: " + min(results, key=len)[0]
                errors.append(f"{path}: matches {passing} of oneOf (exactly 1 required){detail}")
        if "not" in schema and not self._validate(value, schema["not"], file, path):
            errors.append(f"{path}: must not match the 'not' schema")
        if "if" in schema:
            if not self._validate(value, schema["if"], file, path):
                if "then" in schema:
                    errors += self._validate(value, schema["then"], file, path)
            elif "else" in schema:
                errors += self._validate(value, schema["else"], file, path)
        return errors

    def _numeric(self, value, schema, path: str) -> list[str]:
        errors = []
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: {value} < minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: {value} > maximum {schema['maximum']}")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            errors.append(f"{path}: {value} <= exclusiveMinimum {schema['exclusiveMinimum']}")
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            errors.append(f"{path}: {value} >= exclusiveMaximum {schema['exclusiveMaximum']}")
        if "multipleOf" in schema and (value / schema["multipleOf"]) % 1 != 0:
            errors.append(f"{path}: {value} not a multiple of {schema['multipleOf']}")
        return errors

    def _string(self, value: str, schema, path: str) -> list[str]:
        errors = []
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(f"{path}: longer than {schema['maxLength']}")
        if "pattern" in schema and not self._pattern(schema["pattern"]).search(value):
            errors.append(f"{path}: {value!r} does not match {schema['pattern']!r}")
        return errors

    def _array(self, value: list, schema, file: str, path: str) -> list[str]:
        errors = []
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{path}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{path}: more than {schema['maxItems']} items")
        if schema.get("uniqueItems"):
            for i in range(len(value)):
                for j in range(i + 1, len(value)):
                    if json_equal(value[i], value[j]):
                        errors.append(f"{path}: items {i} and {j} are equal")
        prefix = schema.get("prefixItems", [])
        for i, sub in enumerate(prefix[: len(value)]):
            errors += self._validate(value[i], sub, file, f"{path}[{i}]")
        if "items" in schema:
            for i in range(len(prefix), len(value)):
                errors += self._validate(value[i], schema["items"], file, f"{path}[{i}]")
        if "contains" in schema and not any(not self._validate(v, schema["contains"], file, path) for v in value):
            errors.append(f"{path}: no item matches 'contains'")
        return errors

    def _object(self, value: dict, schema, file: str, path: str) -> list[str]:
        errors = []
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing required property {key!r}")
        if "minProperties" in schema and len(value) < schema["minProperties"]:
            errors.append(f"{path}: fewer than {schema['minProperties']} properties")
        if "maxProperties" in schema and len(value) > schema["maxProperties"]:
            errors.append(f"{path}: more than {schema['maxProperties']} properties")
        for key, needed in schema.get("dependentRequired", {}).items():
            if key in value:
                for other in needed:
                    if other not in value:
                        errors.append(f"{path}: {key!r} requires {other!r}")
        props = schema.get("properties", {})
        patterns = schema.get("patternProperties", {})
        for key, item in value.items():
            matched = False
            if key in props:
                matched = True
                errors += self._validate(item, props[key], file, f"{path}.{key}")
            for pattern, sub in patterns.items():
                if self._pattern(pattern).search(key):
                    matched = True
                    errors += self._validate(item, sub, file, f"{path}.{key}")
            if not matched and "additionalProperties" in schema:
                errors += self._validate(item, schema["additionalProperties"], file, f"{path}.{key}")
            if "propertyNames" in schema:
                errors += self._validate(key, schema["propertyNames"], file, f"{path}.<{key}>")
        return errors
