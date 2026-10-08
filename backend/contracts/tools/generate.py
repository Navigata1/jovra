#!/usr/bin/env python3
"""Write backend/contracts/schemas/*.schema.json and routes.v1.json from definitions.py (S81).

    python3 backend/contracts/tools/generate.py           # rewrite (deterministic: same bytes every run)
    python3 backend/contracts/tools/generate.py --check   # exit 1 if a committed file differs from the output

Two shapes are imported from the shared app contracts instead of being restated, so they cannot drift:
the quote response is spec/schemas/studio/quote.schema.json (jovra.quote/1) without its internal-cost fields, and
a quote request's outputSpec is the EDL output of spec/schemas/studio/edit-plan.schema.json with totalFrames
replaced by a duration target. A change to either spec file makes --check fail until this is regenerated.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import definitions as d  # noqa: E402

CONTRACTS = Path(__file__).resolve().parents[1]
REPO = CONTRACTS.parents[1]
STUDIO_SCHEMAS = REPO / "spec" / "schemas" / "studio"
DRAFT = "https://json-schema.org/draft/2020-12/schema"
QUOTE_INTERNAL_COST = ("estimatedMaxCostMicroUsd", "creditCostBudgetMicroUsd")


# ----- importing shapes from spec/schemas/studio --------------------------------------------------------------

def _import(node, file: str, defs: dict, studio: dict):
    """Deep-copy node, rewriting every $ref into a local '#/$defs/<file stem>.<name>' and collecting its target."""
    if isinstance(node, list):
        return [_import(x, file, defs, studio) for x in node]
    if not isinstance(node, dict):
        return node
    out = {}
    for key, value in node.items():
        if key == "$ref" and value.startswith(d.COMMON + "#"):
            out[key] = value  # already one of ours
        elif key == "$ref":
            target_file, _, pointer = value.partition("#")
            target_file = target_file or file
            parts = pointer.lstrip("/").split("/")
            if parts[0] != "$defs" or len(parts) != 2:
                raise ValueError(f"cannot import {value!r} from {file}")
            local = f"{target_file.removesuffix('.schema.json')}.{parts[1]}"
            if local not in defs:
                defs[local] = None  # reserve before recursing (cycles)
                defs[local] = _import(studio[target_file]["$defs"][parts[1]], target_file, defs, studio)
            out[key] = f"#/$defs/{local}"
        else:
            out[key] = _import(value, file, defs, studio)
    return out


def studio_shapes() -> tuple[dict, dict, dict]:
    """(quote data schema, outputSpec schema, imported $defs) taken from the shared Studio contracts."""
    studio = {p.name: json.loads(p.read_text(encoding="utf-8")) for p in sorted(STUDIO_SCHEMAS.glob("*.schema.json"))}
    defs: dict = {}

    quote = copy.deepcopy(studio["quote.schema.json"])
    for key in ("$schema", "title", "$defs"):
        quote.pop(key, None)
    for name in QUOTE_INTERNAL_COST:
        quote["properties"].pop(name)
        quote["required"].remove(name)
    quote["description"] = (
        "A jovra.quote/1 document (spec/schemas/studio/quote.schema.json) without the internal cost fields "
        f"{', '.join(QUOTE_INTERNAL_COST)} (architecture §5.1: all quotes columns except internal cost), plus the "
        "wire ids of the story plan it was computed for. Imported by generate.py; edit the spec, not this file.")
    quote["properties"]["storyPlanId"] = d.ref("uuid")
    quote["properties"]["storyPlanVersionId"] = d.nullable(d.ref("uuid"))
    quote["required"] += ["storyPlanId", "storyPlanVersionId"]
    quote = _import(quote, "quote.schema.json", defs, studio)

    output = copy.deepcopy(studio["edit-plan.schema.json"]["properties"]["output"])
    output["required"].remove("totalFrames")
    output["properties"].pop("totalFrames")
    output["properties"]["durationTargetSec"] = d.described(
        "Target length in whole seconds; the frame count is computed from the plan (INFERRED).",
        {"type": "integer", "minimum": 1, "maximum": 14400})
    output["required"].append("durationTargetSec")
    output = d.described(
        "The film's output: the EDL output of spec/schemas/studio/edit-plan.schema.json (jovra.edit-plan/2) with "
        "totalFrames replaced by durationTargetSec (architecture §4.3 render_jobs.output_spec: fps rational, width, "
        "height, container and codecs, aspect, duration target). Imported by generate.py.",
        _import(output, "edit-plan.schema.json", defs, studio))
    return quote, output, defs


# ----- route schemas ------------------------------------------------------------------------------------------

def headers_schema(route: d.Route) -> dict:
    optional = {"X-Request-Id": d.ref("requestIdHeader")}
    required_extra = {}
    if route.idempotency_required:
        required_extra["Idempotency-Key"] = d.ref("idempotencyKeyHeader")
    if route.body is not None:
        required_extra["Content-Type"] = d.ref("jsonContentType")
    if route.bytes_body:
        required_extra["Content-Type"] = {"const": "application/octet-stream"}
        required_extra["Content-Length"] = d.ref("contentLengthHeader")
        required_extra["X-Jovra-Part-Sha256"] = d.described("SHA-256 of this part's bytes.", d.ref("sha256"))
    if route.range_request:
        optional["Range"] = d.ref("rangeHeader")
    alternatives = []
    for auth in route.auth:
        auth_headers = dict(d.AUTH_HEADERS[auth])
        extra_optional = dict(optional)
        if auth == "host-lease" or auth == "host":
            extra_optional.update(d.HOST_SIGNATURE_HEADERS)
        properties = {**auth_headers, **required_extra, **extra_optional}
        alternative = d.obj(properties, optional=tuple(extra_optional))
        if auth in ("host", "host-lease"):
            alternative["dependentRequired"] = {"JOVRA-Signature": ["JOVRA-Timestamp", "JOVRA-Nonce"]}
        alternatives.append(alternative)
    if len(alternatives) == 1:
        return alternatives[0]
    return {"description": "One of: " + "; ".join(route.auth) + ".", "oneOf": alternatives}


def request_schema(route: d.Route) -> dict:
    properties: dict = {}
    if route.path_params:
        properties["pathParams"] = d.obj({p: d.PATH_PARAM_SCHEMAS.get(p, d.ref("uuid")) for p in route.path_params})
    if route.query:
        properties["query"] = d.obj(route.query, optional=tuple(route.query))
    properties["headers"] = {"$ref": "#/$defs/headers"}
    if route.body is not None:
        properties["body"] = {"$ref": "#/$defs/body"}
    defs = {"headers": headers_schema(route)}
    if route.body is not None:
        defs["body"] = route.body
    body_note = ("JSON body: #/$defs/body." if route.body is not None
                 else "Raw bytes body (not in the descriptor)." if route.bytes_body else "No body.")
    return {
        "$schema": DRAFT,
        "title": f"{route.method} {route.path} request",
        "description": (f"{route.id} ({route.worker}; caller: {route.caller}). {route.description} ".strip()
                        + f" A request descriptor: pathParams, query, headers and body. {body_note} Header names "
                          "are canonical; compare them case-insensitively. A real request may carry other headers "
                          "(User-Agent, Accept-Encoding) that the contract does not use."),
        **d.obj(properties, optional=tuple(k for k in properties if k == "query")),
        "$defs": defs,
    }


def error_schema(route: d.Route) -> tuple[dict, list[str]]:
    codes = list(dict.fromkeys(
        [c for auth in route.auth for c in d.AUTH_ERRORS.get(auth, [])]
        + (["invalid", "idempotency_key_reused"] if route.idempotency_required else [])
        + list(route.errors)
        + (["internal"] if "internal" not in route.errors else [])))
    if route.idempotency_required and "invalid" not in codes:
        codes.append("invalid")
    order = [c for c, _, _ in d.ERROR_CODES]
    codes.sort(key=order.index)
    by_status: dict[int, list[str]] = {}
    for code in codes:
        by_status.setdefault(d.ERROR_STATUS[code], []).append(code)
    branches = [{"properties": {"status": {"const": status},
                                "body": {"properties": {"error": {"properties": {"code": {"enum": group}}}}}}}
                for status, group in sorted(by_status.items())]
    schema = {
        "description": "An error: the §5 envelope with one of this route's codes at its HTTP status.",
        **d.obj({"status": {"enum": sorted(by_status)}, "headers": d.ref("jsonResponseHeaders"),
                 "body": d.ref("errorBody")}),
        "oneOf": branches,
    }
    return schema, codes


def success_schemas(route: d.Route) -> dict:
    if route.data is not None:
        return {"success": {
            "description": "Success: 200 with the §5 envelope {data, requestId}.",
            **d.obj({"status": {"const": 200}, "headers": d.ref("jsonResponseHeaders"),
                     "body": d.obj({"data": {"$ref": "#/$defs/data"}, "requestId": d.ref("uuid"),
                                    "clientRequestId": d.ref("uuid")}, optional=("clientRequestId",))})}}
    base = {"X-Request-Id": d.ref("requestIdHeader"), "Content-Type": {"enum": list(route.response_types)},
            "Content-Length": d.ref("contentLengthHeader")}
    if route.range_request:
        base["Accept-Ranges"] = {"const": "bytes"}
    out = {"success": {
        "description": "Success: 200 with the whole object's bytes (not in the descriptor). No Set-Cookie, ever.",
        **d.obj({"status": {"const": 200}, "headers": d.obj(base)})}}
    if route.range_request:
        out["partial"] = {
            "description": "Success: 206 with the requested range's bytes (not in the descriptor).",
            **d.obj({"status": {"const": 206},
                     "headers": d.obj({**base, "Content-Range": d.ref("contentRangeHeader")})})}
    return out


def response_schema(route: d.Route, extra_defs: dict) -> tuple[dict, list[str]]:
    successes = success_schemas(route)
    error, codes = error_schema(route)
    defs = dict(successes)
    defs["error"] = error
    if route.data is not None:
        defs["data"] = route.data
    defs.update(extra_defs)
    kind = "JSON" if route.data is not None else "bytes (" + ", ".join(route.response_types) + ")"
    schema = {
        "$schema": DRAFT,
        "title": f"{route.method} {route.path} response",
        "description": (f"{route.id}: a response descriptor (status, headers, body). Success body: {kind}. Every "
                        "response carries X-Request-Id; a JSON body's requestId equals it."),
        "oneOf": [{"$ref": f"#/$defs/{name}"} for name in successes] + [{"$ref": "#/$defs/error"}],
        "$defs": defs,
    }
    return schema, codes


def uses(schema, name: str) -> bool:
    return f'"#/$defs/{name}"' in json.dumps(schema)


def build() -> dict[str, dict]:
    quote, output_spec, studio_defs = studio_shapes()
    files: dict[str, dict] = {}
    files["schemas/common.schema.json"] = {
        "$schema": DRAFT,
        "title": "JOVRA backend contracts: shared definitions",
        "description": "Shared $defs of the gateway and queue contracts (backend/contracts, S81). Generated by "
                       "backend/contracts/tools/generate.py from tools/definitions.py.",
        "$defs": d.COMMON_DEFS,
    }
    files["schemas/queue.render-work.message.schema.json"] = {
        "$schema": DRAFT, "title": "render-work queue message", **d.QUEUE_MESSAGE}
    manifest_routes = []
    for route in d.ROUTES:
        request = request_schema(route)
        if uses(request, "outputSpec"):
            request["$defs"]["outputSpec"] = output_spec
        response, codes = response_schema(route, {})
        if uses(response, "quote"):
            response["$defs"]["quote"] = quote
        for schema in (request, response):
            needed = {k: v for k, v in studio_defs.items() if uses(schema, k)}
            while True:  # transitive closure of imported defs
                more = {k: v for k, v in studio_defs.items() if k not in needed and uses(needed, k)}
                if not more:
                    break
                needed.update(more)
            schema["$defs"].update(dict(sorted(needed.items())))
        request_name = f"route.{route.id}.request.schema.json"
        response_name = f"route.{route.id}.response.schema.json"
        files[f"schemas/{request_name}"] = request
        files[f"schemas/{response_name}"] = response
        manifest_routes.append({
            "id": route.id,
            "method": route.method,
            "path": route.path,
            "worker": route.worker,
            "caller": route.caller,
            "auth": list(route.auth),
            "idempotencyKey": "required" if route.idempotency_required else "none",
            "request": {"schema": request_name,
                        "body": "json" if route.body is not None else "bytes" if route.bytes_body else "none"},
            "response": {"schema": response_name, "body": "json" if route.data is not None else "bytes"},
            "errors": codes,
        })
    files["routes.v1.json"] = {
        "schemaVersion": "jovra.backend-contracts/1",
        "status": "contract for S82 (gateway) and S97 (iOS client); nothing is provisioned (ADR-0014)",
        "source": "docs/backend/architecture.md §5 and §5.1; docs/backend/security-model.md §8",
        "basePath": "/v1 (user gateway), /internal/v1 (jovra-internal), /s (share links)",
        "descriptors": "Fixtures are HTTP exchange descriptors: a request is {pathParams?, query?, headers, body?}, "
                       "a response is {status, headers, body?}. Bytes bodies are not in descriptors.",
        "errorCodes": [{"code": c, "status": s, "basis": b} for c, s, b in d.ERROR_CODES],
        "queues": d.QUEUES,
        "routes": manifest_routes,
    }
    return files


def render(value: dict) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="compare instead of writing")
    parser.add_argument("--contracts", type=Path, default=CONTRACTS)
    args = parser.parse_args(argv)
    files = build()
    expected_schemas = {Path(name).name for name in files if name.startswith("schemas/")}
    stale = [p.name for p in sorted((args.contracts / "schemas").glob("*.schema.json")) if p.name not in expected_schemas]
    if args.check:
        differ = [name for name, value in files.items()
                  if not (args.contracts / name).is_file()
                  or (args.contracts / name).read_text(encoding="utf-8") != render(value)]
        for name in differ:
            print(f"DIFFERS  {name}")
        for name in stale:
            print(f"STALE    schemas/{name} (not generated)")
        if differ or stale:
            print("FAIL  run python3 backend/contracts/tools/generate.py and commit the result")
            return 1
        print(f"OK  {len(files)} generated files match")
        return 0
    for name, value in files.items():
        path = args.contracts / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render(value), encoding="utf-8")
    for name in stale:
        (args.contracts / "schemas" / name).unlink()
    print(f"wrote {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
