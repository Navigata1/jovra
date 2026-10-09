"""The gateway and queue contract, declared once (S81). generate.py turns it into JSON Schemas and routes.v1.json.

Source of truth for every route: docs/backend/architecture.md §5 and §5.1 (re-verified by S02), with
docs/backend/security-model.md §8 for token formats and request signing. Where those documents leave a wire detail
open (a header name, an HTTP status, a field name), the choice made here is marked INFERRED in its description and
listed in backend/contracts/README.md, so S82 (gateway) and S97 (iOS client) build against one answer.
"""

from __future__ import annotations

from dataclasses import dataclass, field

COMMON = "common.schema.json"

# JSON Schema patterns use ECMAScript, not Python's Unicode `\s`. Spell out ECMA-262
# WhiteSpace + LineTerminator so both the strict shared checker and gateway validators agree.
ECMA_WHITESPACE = r"\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF"


def ref(name: str) -> dict:
    return {"$ref": f"{COMMON}#/$defs/{name}"}


def nullable(schema: dict) -> dict:
    return {"oneOf": [{"type": "null"}, schema]}


def obj(properties: dict, optional: tuple[str, ...] = (), **extra) -> dict:
    """A closed object: every property is required unless named in optional."""
    schema = {"type": "object", "required": [k for k in properties if k not in optional],
              "additionalProperties": False, "properties": properties}
    schema.update(extra)
    return schema


def described(description: str, schema: dict) -> dict:
    return {"description": description, **schema}


def b64url(length: int) -> str:
    return f"^[A-Za-z0-9_-]{{{length}}}$"


def token(prefix: str, what: str) -> dict:
    return {"description": f"{what}: '{prefix}' + 32 random bytes as unpadded base64url (security-model §8.1). "
                           "A bearer secret: never logged, never stored except as its SHA-256.",
            "type": "string", "pattern": f"^{prefix}[A-Za-z0-9_-]{{43}}$"}


# ----- shared definitions (common.schema.json) ------------------------------------------------------------------

ENV = ["test", "live"]
CAMERA_SLOTS = ["primary_baseline", "opposite_baseline", "near_deuce_corner", "near_ad_corner",
                "far_deuce_corner", "far_ad_corner"]
SOURCE_STATES = ["declared", "uploading", "uploaded_unverified", "verified", "rejected", "deleted"]
JOB_STATES = ["consented", "upload_pending", "uploading", "queued", "normalizing", "syncing", "analyzing", "planning",
              "preview_rendering", "awaiting_review", "final_rendering", "verifying", "ready", "paused", "canceled",
              "failed_retryable", "failed_terminal", "quote_expired", "budget_exceeded", "deleted"]
JOB_STAGES = ["verify_sources", "normalize", "sync", "analyze", "plan", "validate", "preview_render", "final_render",
              "remux_no_audio", "verify_output", "deliver", "cleanup"]
ARTIFACT_KINDS = ["analysis_proxy", "render_proxy", "pts_table", "frame_set", "contact_sheet", "preview", "film",
                  "thumbnail", "captions", "chapters", "edit_manifest", "project_bundle", "clip_excerpt"]
ARTIFACT_STATES = ["writing", "verifying", "ready", "failed", "deleted"]
ATTEMPT_STATES = ["reserved", "dispatched", "running", "succeeded", "failed", "lease_expired", "canceled",
                  "dead_lettered"]
INVITATION_GRANT_KINDS = ["project_coach", "lesson_coach", "lesson_view", "film_view", "lesson_clip_view"]
DELETION_SCOPES = ["account", "project", "source", "artifact", "lesson", "lesson_clip"]
DELETION_STATES = ["requested", "canceling_jobs", "deleting_objects", "deleting_rows", "revoking_apple", "done",
                   "failed"]
UPLOAD_SESSION_STATES = ["opening", "open", "completing", "completed", "aborted", "expired"]
PART_SIZE = 32 * 1024 * 1024
MAX_PARTS = 10_000

# Error codes: (code, HTTP status, basis). Documented codes cite the architecture; the rest map the SQL command
# functions' coded errors (security-model §4: P0401 unauthorized, P0402 budget_exceeded, P0404 not_found,
# P0409 conflict, P0410 expired, P0422 invalid, P0429 quota) onto HTTP statuses.
ERROR_CODES = [
    ("unauthorized", 401, "INFERRED from P0401; missing, malformed, expired or wrong-environment credential"),
    ("demo_not_accepted", 401, "architecture §2 rule 1 (T-GW-03)"),
    ("reauth_required", 401, "architecture §5.1 deletion-requests; security-model §2.2"),
    ("budget_exceeded", 402, "INFERRED from P0402"),
    ("not_found", 404, "architecture §5 envelope: also returned for an object the caller may not see"),
    ("conflict", 409, "INFERRED from P0409; wrong state, slot taken, stale or fenced"),
    ("already_claimed", 409, "architecture §5.1 attempt claim"),
    ("parts_mismatch", 409, "architecture §6.3 rule 4"),
    ("requote_required", 409, "architecture §5.1 job review"),
    ("dependents", 409, "architecture §5.1 deletion-requests"),
    ("secret_not_replayable", 409, "architecture §5 idempotency"),
    ("expired", 410, "INFERRED from P0410"),
    ("range_not_satisfiable", 416, "INFERRED; RFC 9110 §15.5.17 for a Range outside the object"),
    ("invalid", 422, "INFERRED from P0422; the request does not match its schema or a server-held expectation"),
    ("idempotency_key_reused", 422, "architecture §5 idempotency"),
    ("rate_limited", 429, "INFERRED from the §5 rate limits and P0429 quotas"),
    ("internal", 500, "INFERRED; never carries detail"),
]
ERROR_STATUS = {code: status for code, status, _ in ERROR_CODES}

probe_summary = described(
    "The device's own probe of its original, allowlisted to these six facts and stored as client_probe, never as "
    "the server probe (architecture §5.1, camera_sources.client_probe). Never free-form tags: QuickTime metadata "
    "can hold a location. Field names carry their units (INFERRED; the document says duration and rotation).",
    obj({
        "codec": {"enum": ["h264", "hevc", "prores", "other"]},
        "width": {"type": "integer", "minimum": 2, "maximum": 7680},
        "height": {"type": "integer", "minimum": 2, "maximum": 7680},
        "fps": ref("fps"),
        "durationUs": {"type": "integer", "minimum": 1, "maximum": 86_400_000_000},
        "rotationDegrees": {"enum": [0, 90, 180, 270]},
    }))

upload_session = described(
    "An opened upload session (architecture §5.1, §6.2). partTarget describes where parts go, so a later move to "
    "direct-to-R2 parts is a server change only; until the B-12 spike it is the gateway's own part route.",
    obj({
        "sessionId": ref("uuid"),
        "partSize": described("Fixed 32 MiB (upload_sessions.part_size).", {"const": PART_SIZE}),
        "partCount": {"type": "integer", "minimum": 1, "maximum": MAX_PARTS},
        "sessionCapability": ref("sessionCapability"),
        "expiresAt": described("Idle expiry, renewed while parts arrive (≤ 24 h after the last part).", ref("dateTime")),
        "hardExpiresAt": described("Absolute ceiling, opening + 48 h, never extended.", ref("dateTime")),
        "partTarget": obj({
            "method": {"const": "PUT"},
            "urlTemplate": described("Absolute https URL with the literal placeholder {n} for the part number.",
                                     {"type": "string", "pattern": (r"^https://[A-Za-z0-9.-]+(:[0-9]+)?/[^" + ECMA_WHITESPACE
                                                  + r"]*\{n\}[^" + ECMA_WHITESPACE + r"]*$"),
                                      "maxLength": 512}),
            "headers": described("Extra headers each part request must carry (names and fixed values only; never "
                                 "a secret other than the session capability placeholder).",
                                 {"type": "object", "maxProperties": 8,
                                  "propertyNames": {"pattern": "^[A-Za-z][A-Za-z0-9-]{0,63}$"},
                                  "additionalProperties": {"type": "string", "maxLength": 256}}),
        }),
    }))

measurements = described(
    "Stage measurements reported by the render host (render_attempts.measurements; never shown to clients). "
    "Integers only.",
    obj({
        "wallMs": {"type": "integer", "minimum": 0},
        "cpuMs": {"type": "integer", "minimum": 0},
        "bytesIn": {"type": "integer", "minimum": 0},
        "bytesOut": {"type": "integer", "minimum": 0},
        "plannerTokens": obj({"input": {"type": "integer", "minimum": 0}, "cache": {"type": "integer", "minimum": 0},
                              "output": {"type": "integer", "minimum": 0}}),
    }, optional=("plannerTokens",)))

error_body = {
    "description": "Error envelope (architecture §5): {error: {code, message, retryable}, requestId}. The message is "
                   "for logs and developers; the app maps code to copy. details is present only for dependents and "
                   "secret_not_replayable (INFERRED shapes).",
    "type": "object",
    "required": ["error", "requestId"],
    "additionalProperties": False,
    "properties": {
        "error": {
            "type": "object",
            "required": ["code", "message", "retryable"],
            "additionalProperties": False,
            "properties": {
                "code": {"enum": [c for c, _, _ in ERROR_CODES]},
                "message": {"type": "string", "minLength": 1, "maxLength": 500},
                "retryable": {"type": "boolean"},
                "details": {"type": "object"},
            },
            "allOf": [
                {"if": {"required": ["code"], "properties": {"code": {"const": "dependents"}}},
                 "then": {"required": ["details"], "properties": {"details": obj({
                     "dependents": {"type": "array", "minItems": 1, "maxItems": 100, "items": obj({
                         "artifactId": ref("uuid"), "kind": ref("artifactKind")})}})}}},
                {"if": {"required": ["code"], "properties": {"code": {"const": "secret_not_replayable"}}},
                 "then": {"required": ["details"], "properties": {"details": obj({"resourceId": ref("uuid")})}}},
                {"if": {"required": ["code"], "properties": {"code": {"enum": ["dependents", "secret_not_replayable"]}}},
                 "else": {"not": {"required": ["details"]}}},
            ],
        },
        "requestId": ref("uuid"),
        "clientRequestId": ref("uuid"),
    },
}

COMMON_DEFS = {
    "uuid": described("A server-generated id: lowercase UUID version 4 (gen_random_uuid()).",
                      {"type": "string", "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"}),
    "localUuid": described("A device-local UUID (ADR-0002), any version, either case; stored in local_*_id columns, "
                           "never a cloud primary key.",
                           {"type": "string", "pattern": "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"}),
    "sha256": described("SHA-256 as 64 lowercase hex digits.", {"type": "string", "pattern": "^[0-9a-f]{64}$"}),
    "dateTime": described("RFC 3339 UTC timestamp with a Z suffix (same rule as spec/schemas/studio).",
                          {"type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,3})?Z$"}),
    "env": described("The gateway's environment. Demo has no gateway and no token (architecture §2).", {"enum": ENV}),
    "fps": described("Exact frame rate num/den (spec/schemas/studio/studio-common.schema.json#/$defs/fps).",
                     obj({"num": {"type": "integer", "minimum": 1, "maximum": 240000},
                          "den": {"type": "integer", "minimum": 1, "maximum": 1001}})),
    "credits": described("Studio Credits, integer only (spec studio-common credits).",
                         {"type": "integer", "minimum": 0, "maximum": 1000}),
    "cameraSlot": {"enum": CAMERA_SLOTS},
    "sourceState": {"enum": SOURCE_STATES},
    "jobState": described("public.job_state (architecture §4.2): the states of spec/studio/contracts/"
                          "render-job-transitions.v1.json except the quote states draft and quoted.",
                          {"enum": JOB_STATES}),
    "jobStage": {"enum": JOB_STAGES},
    "artifactKind": {"enum": ARTIFACT_KINDS},
    "artifactState": {"enum": ARTIFACT_STATES},
    "attemptState": {"enum": ATTEMPT_STATES},
    "deletionScope": {"enum": DELETION_SCOPES},
    "deletionState": {"enum": DELETION_STATES},
    "uploadSessionState": {"enum": UPLOAD_SESSION_STATES},
    "displayLabel": described("Short text a person typed (≤ 60 characters); shown as text, never logged.",
                              {"type": "string", "minLength": 1, "maxLength": 60}),
    "displayTitle": {"type": "string", "minLength": 1, "maxLength": 120},
    "machineCode": described("A machine error or reason code; user copy is mapped in the app.",
                             {"type": "string", "pattern": "^[a-z][a-z0-9_]{0,63}$"}),
    "deviceCode": described("Six digits derived from the guest device key's thumbprint, shown on both phones "
                            "(security-model §8.2).", {"type": "string", "pattern": "^[0-9]{6}$"}),
    "inviteCode": token("jvi_", "Camera invite code (shown once, in the QR)"),
    "guestCapability": token("jvg_", "Guest capability"),
    "sessionCapability": token("jvs_", "Upload session capability"),
    "leaseToken": token("jvl_", "Attempt lease token (minted at claim, never in a queue message)"),
    "shareToken": token("jvh_", "Share link token"),
    "grantCode": token("jvc_", "Coach or viewer invitation code"),
    "p256PublicJwk": described(
        "The guest device's P-256 public key as a JWK (RFC 7517/7518). Public members only: a private 'd' is "
        "invalid.",
        obj({"kty": {"const": "EC"}, "crv": {"const": "P-256"},
             "x": {"type": "string", "pattern": b64url(43)}, "y": {"type": "string", "pattern": b64url(43)}})),
    "nonce": described("A server or client nonce, base64url (16 to 64 bytes).",
                       {"type": "string", "pattern": "^[A-Za-z0-9_-]{22,86}$"}),
    "p256Signature": described("ECDSA P-256 signature as raw r||s (64 bytes, IEEE P1363), unpadded base64url "
                               "(INFERRED encoding; WebCrypto's form).", {"type": "string", "pattern": b64url(86)}),
    "inputRef": described("An attempt input reference from render_attempts.input_refs; URL-safe, opaque.",
                          {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"}),
    "outputRef": described("An attempt output reference from render_attempts.output_plan; URL-safe, opaque.",
                           {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"}),
    "etag": {"type": "string", "pattern": "^[A-Za-z0-9_-]{1,128}$"},
    "probeSummary": probe_summary,
    "uploadSession": upload_session,
    "measurements": measurements,
    "errorBody": error_body,
    # Header values.
    "requestIdHeader": described("X-Request-Id: on a response the gateway's own UUID (equal to the body's "
                                 "requestId); on a request an optional client id, echoed as clientRequestId after "
                                 "format validation (INFERRED request header name).", ref("uuid")),
    "idempotencyKeyHeader": described("Idempotency-Key: a UUIDv4 per logical request (architecture §5).",
                                      ref("uuid")),
    "bearerAuthorization": described("Authorization: Bearer <Supabase access JWT>. The gateway verifies ES256, "
                                     "kid, iss, aud and exp; this schema checks only the scheme.",
                                     {"type": "string", "pattern": "^Bearer [A-Za-z0-9._~+/-]+=*$", "maxLength": 4096}),
    "guestAuthorization": described("Authorization: JOVRA-Capability <jvg_ guest capability>.",
                                    {"type": "string", "pattern": "^JOVRA-Capability jvg_[A-Za-z0-9_-]{43}$"}),
    "sessionAuthorization": described("Authorization: JOVRA-Capability <jvs_ upload session capability>.",
                                      {"type": "string", "pattern": "^JOVRA-Capability jvs_[A-Za-z0-9_-]{43}$"}),
    "hostAuthorization": described("Authorization: JOVRA-Host <host credential> (security-model §8.4). The "
                                   "credential's format is the host adapter's; this schema checks the scheme.",
                                   {"type": "string", "pattern": "^JOVRA-Host [A-Za-z0-9._~-]{16,256}$"}),
    "leaseHeader": described("JOVRA-Lease: the attempt's current jvl_ lease token.",
                             {"type": "string", "pattern": "^jvl_[A-Za-z0-9_-]{43}$"}),
    "signatureTimestampHeader": described("JOVRA-Timestamp: Unix seconds; ±5 minutes skew (INFERRED header name).",
                                          {"type": "string", "pattern": "^[0-9]{10}$"}),
    "signatureNonceHeader": described("JOVRA-Nonce: single use within the 10-minute replay cache (INFERRED name).",
                                      ref("nonce")),
    "guestSignatureHeader": described(
        "JOVRA-Signature: the guest device key's P-256 signature over (method, path, timestamp, nonce, body "
        "SHA-256) (security-model §8.2; INFERRED header name).", ref("p256Signature")),
    "hostSignatureHeader": described(
        "JOVRA-Signature: HMAC-SHA256 over (method, path, timestamp, nonce, body SHA-256) with the per-environment "
        "host secret, unpadded base64url (security-model §8.4, external hosts only; INFERRED header name).",
        {"type": "string", "pattern": b64url(43)}),
    "rangeHeader": described("Range: a single byte range (RFC 9110).",
                             {"type": "string", "pattern": "^bytes=([0-9]+-[0-9]*|-[0-9]+)$"}),
    "contentLengthHeader": {"type": "string", "pattern": "^(0|[1-9][0-9]{0,12})$"},
    "contentRangeHeader": {"type": "string", "pattern": "^bytes [0-9]+-[0-9]+/[0-9]+$"},
    "jsonContentType": {"const": "application/json"},
    "jsonResponseHeaders": obj({"X-Request-Id": ref("requestIdHeader"), "Content-Type": ref("jsonContentType")}),
}


# ----- routes -----------------------------------------------------------------------------------------------

# Authentication alternatives. Each is a set of required headers; optional headers are added per route.
AUTH_HEADERS = {
    "none": {},
    "user": {"Authorization": ref("bearerAuthorization")},
    "guest-signed": {"Authorization": ref("guestAuthorization"), "JOVRA-Timestamp": ref("signatureTimestampHeader"),
                     "JOVRA-Nonce": ref("signatureNonceHeader"), "JOVRA-Signature": ref("guestSignatureHeader")},
    "session": {"Authorization": ref("sessionAuthorization")},
    "host": {"Authorization": ref("hostAuthorization")},
    "host-lease": {"Authorization": ref("hostAuthorization"), "JOVRA-Lease": ref("leaseHeader")},
}
AUTH_ERRORS = {
    "none": [],
    "user-optional": ["unauthorized"],
    "user": ["unauthorized", "demo_not_accepted"],
    "guest-signed": ["unauthorized"],
    "session": ["unauthorized"],
    "host": ["unauthorized"],
    "host-lease": ["unauthorized"],
}
HOST_SIGNATURE_HEADERS = {"JOVRA-Timestamp": ref("signatureTimestampHeader"),
                          "JOVRA-Nonce": ref("signatureNonceHeader"),
                          "JOVRA-Signature": ref("hostSignatureHeader")}

PATH_PARAM_SCHEMAS = {
    "n": described("Part number, 1 to 10,000.", {"type": "string", "pattern": "^([1-9][0-9]{0,3}|10000)$"}),
    "token": ref("shareToken"),
    "inputRef": ref("inputRef"),
}

MEDIA_TYPES = ["video/mp4", "video/quicktime", "image/jpeg", "text/vtt", "application/x-subrip",
               "application/json", "application/zip", "application/octet-stream"]


@dataclass(frozen=True)
class Route:
    id: str
    method: str
    path: str
    caller: str
    auth: tuple[str, ...]                 # alternatives; "user-optional" = no auth or a user JWT
    data: dict | None = None              # JSON response data; None for a bytes response
    body: dict | None = None              # JSON request body
    bytes_body: bool = False              # raw bytes request body (upload parts)
    query: dict | None = None
    range_request: bool = False
    response_types: tuple[str, ...] = ()  # media types of a bytes response
    errors: tuple[str, ...] = ()
    description: str = ""
    worker: str = "jovra-gateway"
    extra_examples: dict = field(default_factory=dict)

    @property
    def path_params(self) -> list[str]:
        return [seg[1:-1] for seg in self.path.split("/") if seg.startswith("{")]

    @property
    def idempotency_required(self) -> bool:
        return self.method == "POST"


def ids(*names: str) -> dict:
    return {name: ref("uuid") for name in names}


def grant_body() -> dict:
    targets = {"project_coach": "projectId", "lesson_coach": "lessonId", "lesson_view": "lessonId",
               "film_view": "artifactId", "lesson_clip_view": "lessonClipId"}
    all_targets = ["projectId", "lessonId", "artifactId", "lessonClipId"]
    rules = []
    for kind, target in targets.items():
        rules.append({"if": {"required": ["kind"], "properties": {"kind": {"const": kind}}},
                      "then": {"required": [target],
                               "properties": {other: False for other in all_targets if other != target}}})
    return obj({
        "kind": {"enum": INVITATION_GRANT_KINDS},
        "inviteeEmail": described("Required; stored only as an HMAC, never logged (architecture §5.1).",
                                  {"type": "string", "maxLength": 254, "pattern": ("^[^@" + ECMA_WHITESPACE + "]+@[^@"
                                               + ECMA_WHITESPACE + r"]+\.[^@" + ECMA_WHITESPACE + "]+$")}),
        **ids("projectId", "lessonId", "artifactId", "lessonClipId"),
        "expiresInSec": described("End of access after redemption (INFERRED bound: up to 365 days).",
                                  {"type": "integer", "minimum": 60, "maximum": 31_536_000}),
    }, optional=("projectId", "lessonId", "artifactId", "lessonClipId"), allOf=rules)


JOB_STATE_DATA = obj({"state": ref("jobState")})

ROUTES: list[Route] = [
    Route("health", "GET", "/v1/health", "anyone", ("none",),
          data=obj({"env": ref("env"), "version": {"type": "string", "pattern": "^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$"}}),
          errors=("internal",), description="Liveness; no data."),
    Route("me", "GET", "/v1/me", "user", ("user",),
          data=obj({"userId": ref("uuid"),
                    "displayName": nullable({"type": "string", "minLength": 1, "maxLength": 80}),
                    "env": ref("env"),
                    "features": described("Server-enabled feature ids (INFERRED shape).",
                                          {"type": "array", "maxItems": 32, "uniqueItems": True,
                                           "items": {"type": "string", "pattern": "^[a-z][a-z0-9.-]{0,63}$"}})})),
    Route("sources.declare", "POST", "/v1/projects/{projectId}/sources", "owner", ("user",),
          body=obj({"slot": ref("cameraSlot"), "localSourceId": ref("localUuid"),
                    "declaredBytes": {"type": "integer", "minimum": 1, "maximum": 1_000_000_000_000},
                    "declaredSha256": ref("sha256"), "probeSummary": ref("probeSummary")}),
          data=obj({"sourceId": ref("uuid"), "state": ref("sourceState")}),
          errors=("not_found", "conflict", "invalid", "rate_limited")),
    Route("cameraInvites.create", "POST", "/v1/projects/{projectId}/camera-invites", "owner", ("user",),
          body=obj({"slot": ref("cameraSlot"), "displayLabel": ref("displayLabel")}),
          data=obj({"inviteId": ref("uuid"), "code": ref("inviteCode"), "redeemBy": ref("dateTime")}),
          errors=("not_found", "conflict", "invalid", "secret_not_replayable"),
          description="The code is returned once; a replay is 409 secret_not_replayable."),
    Route("cameraInvites.revoke", "DELETE", "/v1/projects/{projectId}/camera-invites/{inviteId}", "owner", ("user",),
          data=obj({"revokedAt": ref("dateTime")}), errors=("not_found",)),
    Route("cameraInvites.redeem", "POST", "/v1/camera-invites/redeem", "guest", ("none", "user"),
          body=obj({"code": ref("inviteCode"), "devicePublicKey": ref("p256PublicJwk"),
                    "deviceLabel": ref("displayLabel")}),
          data=described("No project text before approval: the response is closed to exactly these fields.",
                         obj({"redemptionId": ref("uuid"), "deviceCode": ref("deviceCode"),
                              "status": {"const": "awaiting_host"}})),
          errors=("not_found", "conflict", "expired", "invalid", "rate_limited"),
          description="A JWT, if present, is verified and its sub is the only source of redeemed_by_user_id."),
    Route("cameraInvites.approve", "POST", "/v1/projects/{projectId}/camera-invites/{inviteId}/approve", "owner",
          ("user",), body=obj({"redemptionId": ref("uuid"), "deviceCode": ref("deviceCode")}),
          data=obj({"approvedAt": ref("dateTime")}), errors=("not_found", "conflict", "invalid")),
    Route("cameraInvites.capability", "POST", "/v1/camera-invites/redemptions/{redemptionId}/capability", "guest",
          ("none",), body=obj({"nonce": ref("nonce"), "signature": ref("p256Signature")}),
          data=obj({"capability": ref("guestCapability"), "displayLabel": ref("displayLabel"),
                    "slot": ref("cameraSlot"),
                    "scope": obj({"projectRef": ref("uuid"), "slot": ref("cameraSlot"),
                                  "ops": {"const": ["source.declare", "upload"]}}),
                    "expiresAt": ref("dateTime")}),
          errors=("unauthorized", "not_found", "conflict", "expired", "invalid", "secret_not_replayable",
                  "rate_limited"),
          description="Signed challenge: the device key signs a server nonce. Where the guest obtains that nonce "
                      "is not specified by §5.1 (README open question 1)."),
    Route("guestSources.declare", "POST", "/v1/guest/sources", "guest capability", ("guest-signed",),
          body=obj({"localSourceId": ref("localUuid"),
                    "declaredBytes": {"type": "integer", "minimum": 1, "maximum": 1_000_000_000_000},
                    "declaredSha256": ref("sha256"), "probeSummary": ref("probeSummary"),
                    "participantAck": described("The guest confirmed recording with the players' agreement.",
                                                {"const": True})}),
          data=obj({"sourceId": ref("uuid")}), errors=("not_found", "conflict", "expired", "invalid")),
    Route("uploads.open", "POST", "/v1/sources/{sourceId}/uploads", "owner or guest", ("user", "guest-signed"),
          body=obj({"declaredBytes": {"type": "integer", "minimum": 1, "maximum": 1_000_000_000_000},
                    "declaredSha256": ref("sha256"),
                    "contentType": {"enum": ["video/mp4", "video/quicktime"]}}),
          data=ref("uploadSession"),
          errors=("not_found", "conflict", "expired", "invalid", "secret_not_replayable"),
          description="Bytes and hash must equal the server-held declaration; an open session of the source is "
                      "aborted in the same transaction."),
    Route("uploads.status", "GET", "/v1/uploads/{sessionId}", "session holder", ("session",),
          data=obj({"state": ref("uploadSessionState"),
                    "confirmedParts": {"type": "array", "maxItems": MAX_PARTS,
                                       "items": obj({"n": {"type": "integer", "minimum": 1, "maximum": MAX_PARTS},
                                                     "bytes": {"type": "integer", "minimum": 1, "maximum": PART_SIZE},
                                                     "etag": ref("etag")})},
                    "expiresAt": ref("dateTime")}),
          errors=("not_found", "expired")),
    Route("uploads.putPart", "PUT", "/v1/uploads/{sessionId}/parts/{n}", "session holder", ("session",),
          bytes_body=True,
          data=obj({"n": {"type": "integer", "minimum": 1, "maximum": MAX_PARTS},
                    "bytes": {"type": "integer", "minimum": 1, "maximum": PART_SIZE},
                    "etag": ref("etag"), "sha256": ref("sha256")}),
          errors=("not_found", "conflict", "expired", "invalid"),
          description="Raw bytes; exact Content-Length; the streamed SHA-256 must equal X-Jovra-Part-Sha256."),
    Route("uploads.complete", "POST", "/v1/uploads/{sessionId}/complete", "session holder", ("session",),
          body=obj({"parts": {"type": "array", "minItems": 1, "maxItems": MAX_PARTS,
                              "items": obj({"n": {"type": "integer", "minimum": 1, "maximum": MAX_PARTS},
                                            "etag": ref("etag")})}}),
          data=obj({"sourceState": {"const": "uploaded_unverified"}}),
          errors=("not_found", "conflict", "parts_mismatch", "expired", "invalid"),
          description="Section 6.3: the ETags used come from upload_parts, never from this list."),
    Route("uploads.abort", "DELETE", "/v1/uploads/{sessionId}", "session holder or owner", ("session", "user"),
          data=obj({"state": {"const": "aborted"}}), errors=("not_found", "conflict")),
    Route("quotes.create", "POST", "/v1/projects/{projectId}/quotes", "owner", ("user",),
          body=obj({"storyPlanId": ref("uuid"), "storyPlanVersionId": ref("uuid"),
                    "plannerChoice": {"enum": ["heuristic", "model"]},
                    "outputSpec": {"$ref": "#/$defs/outputSpec"},
                    "sourceIds": {"type": "array", "minItems": 1, "maxItems": 6, "uniqueItems": True,
                                  "items": ref("uuid")},
                    "retentionDays": {"enum": [1, 7, 30]}}, optional=("storyPlanVersionId",)),
          data={"$ref": "#/$defs/quote"},
          errors=("not_found", "conflict", "invalid", "rate_limited"),
          description="Every sourceId resolves through this project's current verified source manifest; inputs "
                      "and output_spec_sha256 are computed server-side, never from the request's numbers."),
    Route("quotes.accept", "POST", "/v1/quotes/{quoteId}/accept", "owner", ("user",),
          body=obj({"inputsSha256": ref("sha256"),
                    "consent": obj({"cloudProcessing": {"const": True}, "modelProvider": {"type": "boolean"},
                                    "textClasses": {"type": "array", "maxItems": 3, "uniqueItems": True,
                                                    "items": {"enum": ["ownerNotes", "ownerLessonNotes", "coachNotes"]}},
                                    "retentionDays": {"enum": [1, 7, 30]},
                                    "consentTextVersion": {"type": "string",
                                                           "pattern": "^[a-z0-9-]+@[0-9]+\\.[0-9]+\\.[0-9]+$"}}),
                    "acceptedCapCredits": ref("credits")}),
          data=obj({"jobId": ref("uuid"), "reservationId": ref("uuid"), "state": {"const": "consented"}}),
          errors=("not_found", "budget_exceeded", "conflict", "expired", "invalid"),
          description="A re-quote after budget_exceeded returns the existing job and the topped-up reservation."),
    Route("jobs.get", "GET", "/v1/jobs/{jobId}", "owner, coach", ("user",),
          data=obj({
              "state": ref("jobState"),
              "stage": nullable(ref("jobStage")),
              "stageProgressMilli": described("Progress of the current stage only, 0 to 1000.",
                                              nullable({"type": "integer", "minimum": 0, "maximum": 1000})),
              "errorCode": described("render_jobs.error_code (INFERRED field).", nullable(ref("machineCode"))),
              "stages": described("One entry per stage attempt so far (INFERRED shape).",
                                  {"type": "array", "maxItems": 100,
                                   "items": obj({"stage": ref("jobStage"),
                                                 "attempt": {"type": "integer", "minimum": 1, "maximum": 100},
                                                 "state": ref("attemptState")})}),
              "artifacts": described("Artifacts the caller may see (INFERRED shape).",
                                     {"type": "array", "maxItems": 64,
                                      "items": obj({"artifactId": ref("uuid"), "kind": ref("artifactKind"),
                                                    "state": ref("artifactState"), "stale": {"type": "boolean"},
                                                    "displayTitle": nullable(ref("displayTitle")),
                                                    "bytes": nullable({"type": "integer", "minimum": 0})})}),
              "usage": described("Owner only: coaches never see money (T-DB-25).",
                                 obj({"estimate": obj({"lowCredits": ref("credits"), "highCredits": ref("credits")}),
                                      "cap": ref("credits"), "actual": nullable(ref("credits"))})),
          }, optional=("usage",)),
          errors=("not_found",)),
    Route("jobs.cancel", "POST", "/v1/jobs/{jobId}/cancel", "owner", ("user",), data=JOB_STATE_DATA,
          errors=("not_found", "conflict")),
    Route("jobs.pause", "POST", "/v1/jobs/{jobId}/pause", "owner", ("user",), data=JOB_STATE_DATA,
          errors=("not_found", "conflict")),
    Route("jobs.resume", "POST", "/v1/jobs/{jobId}/resume", "owner", ("user",), data=JOB_STATE_DATA,
          errors=("not_found", "conflict", "budget_exceeded")),
    Route("jobs.review", "POST", "/v1/jobs/{jobId}/review", "owner", ("user",),
          body=obj({"decision": {"enum": ["approve", "revise"]}, "storyPlanVersionId": ref("uuid")},
                   optional=("storyPlanVersionId",),
                   allOf=[{"if": {"required": ["decision"], "properties": {"decision": {"const": "revise"}}},
                           "then": {"required": ["storyPlanVersionId"]},
                           "else": {"not": {"required": ["storyPlanVersionId"]}}}]),
          data=JOB_STATE_DATA, errors=("not_found", "conflict", "requote_required", "invalid")),
    Route("jobs.retry", "POST", "/v1/jobs/{jobId}/retry", "owner", ("user",), data=JOB_STATE_DATA,
          errors=("not_found", "conflict", "budget_exceeded")),
    Route("artifacts.content", "GET", "/v1/artifacts/{artifactId}/content", "owner, coach, granted viewer", ("user",),
          query={"audio": described("Downloads of a film only; none is forced in junior mode.",
                                    {"enum": ["include", "none"]})},
          range_request=True, response_types=tuple(MEDIA_TYPES[:-1]),
          errors=("not_found", "range_not_satisfiable", "rate_limited"),
          description="Bytes of the artifact actually chosen: the film, or its verified no-audio child."),
    Route("shareLinks.create", "POST", "/v1/artifacts/{artifactId}/share-links", "owner", ("user",),
          body=obj({"expiresInSec": {"type": "integer", "minimum": 60, "maximum": 86_400},
                    "includeAudio": described("Required for a film (checked by the gateway); false forced in junior "
                                              "mode.", {"type": "boolean"})}, optional=("includeAudio",)),
          data=obj({"shareLinkId": ref("uuid"),
                    "url": described("The share URL; the jvh_ token is in the path and is returned once.",
                                     {"type": "string", "maxLength": 512,
                                      "pattern": "^https://[A-Za-z0-9.-]+(:[0-9]+)?/s/jvh_[A-Za-z0-9_-]{43}$"}),
                    "expiresAt": ref("dateTime")}),
          errors=("not_found", "conflict", "invalid", "secret_not_replayable", "rate_limited")),
    Route("shareLinks.revoke", "DELETE", "/v1/share-links/{shareLinkId}", "owner", ("user",),
          data=obj({"revokedAt": ref("dateTime")}), errors=("not_found",)),
    Route("shareLinks.open", "GET", "/s/{token}", "anyone with the link", ("none",), range_request=True,
          response_types=("video/mp4",), errors=("not_found", "range_not_satisfiable", "rate_limited"),
          description="No cookie, no account; an expired, revoked or unknown token is the same 404."),
    Route("shareLinks.thumbnail", "GET", "/s/{token}/thumbnail", "anyone with the link", ("none",),
          response_types=("image/jpeg",), errors=("not_found", "rate_limited")),
    Route("grants.create", "POST", "/v1/grants", "owner", ("user",), body=grant_body(),
          data=obj({"grantId": ref("uuid"), "code": ref("grantCode"), "expiresAt": ref("dateTime")}),
          errors=("not_found", "conflict", "invalid", "secret_not_replayable", "rate_limited")),
    Route("grants.redeem", "POST", "/v1/grants/redeem", "user", ("user",), body=obj({"code": ref("grantCode")}),
          data=obj({"kind": {"enum": INVITATION_GRANT_KINDS},
                    "target": described("The one target the grant reaches.",
                                        {"type": "object", "minProperties": 1, "maxProperties": 1,
                                         "additionalProperties": False,
                                         "properties": ids("projectId", "lessonId", "artifactId", "lessonClipId")}),
                    "status": {"enum": ["active", "awaiting_owner"]},
                    "approvalCode": described("project_coach only: six digits the redeemer reads to the owner "
                                              "(INFERRED field name).", ref("deviceCode"))},
                   optional=("approvalCode",),
                   allOf=[{"if": {"required": ["status"], "properties": {"status": {"const": "awaiting_owner"}}},
                           "then": {"required": ["approvalCode"], "properties": {"kind": {"const": "project_coach"}}},
                           "else": {"not": {"required": ["approvalCode"]}}}]),
          errors=("not_found", "invalid", "rate_limited"),
          description="A code for someone else, an expired or an unknown code are the same 404."),
    Route("members.approve", "POST", "/v1/projects/{projectId}/members/{userId}/approve", "owner", ("user",),
          body=obj({"code": ref("deviceCode")}), data=obj({"approvedAt": ref("dateTime")}),
          errors=("not_found", "conflict", "invalid")),
    Route("lessonClips.approveShare", "POST", "/v1/lesson-clips/{clipId}/share-approval", "project owner", ("user",),
          data=obj({"shareApprovedAt": ref("dateTime")}), errors=("not_found",)),
    Route("lessonClips.revokeShare", "DELETE", "/v1/lesson-clips/{clipId}/share-approval", "project owner",
          ("user",), data=obj({"shareApprovedAt": {"type": "null"}}), errors=("not_found",)),
    Route("grants.revoke", "DELETE", "/v1/grants/{grantId}", "grant creator or footage owner", ("user",),
          data=obj({"revokedAt": ref("dateTime")}), errors=("not_found",)),
    Route("account.appleLink", "POST", "/v1/account/apple-link", "user (SIWA)", ("user",),
          body=obj({"authorizationCode": {"type": "string", "minLength": 1, "maxLength": 2048,
                                          "pattern": "^[A-Za-z0-9._~-]+$"}}),
          data=obj({"linked": {"const": True}}), errors=("conflict", "invalid")),
    Route("deletionRequests.create", "POST", "/v1/deletion-requests", "user", ("user",),
          body=obj({"scope": ref("deletionScope"), "targetId": ref("uuid"),
                    "confirmDependents": {"type": "boolean"}}, optional=("confirmDependents",)),
          data=obj({"deletionRequestId": ref("uuid"), "state": ref("deletionState")}),
          errors=("reauth_required", "not_found", "dependents", "conflict", "invalid"),
          description="Account scope needs an Auth session created ≤ 10 minutes ago (401 reauth_required)."),
    Route("deletionRequests.get", "GET", "/v1/deletion-requests/{id}", "requester", ("user",),
          data=obj({"state": ref("deletionState"),
                    "counts": described("Objects and rows deleted per class: numbers only.",
                                        {"type": "object", "maxProperties": 32,
                                         "propertyNames": {"pattern": "^[a-z][a-z0-9_]{0,63}$"},
                                         "additionalProperties": {"type": "integer", "minimum": 0}})}),
          errors=("not_found",)),
    Route("internal.claim", "POST", "/internal/v1/attempts/{attemptId}/claim", "render host", ("host",),
          worker="jovra-internal",
          data=obj({"leaseToken": ref("leaseToken"), "leasedUntil": ref("dateTime"),
                    "inputRefs": described("render_attempts.input_refs, computed by reserve_stage (INFERRED item "
                                           "shape).", {"type": "array", "maxItems": 64,
                                                       "items": obj({"inputRef": ref("inputRef"),
                                                                     "kind": {"enum": ["source", "artifact"]},
                                                                     "bytes": {"type": "integer", "minimum": 1},
                                                                     "sha256": ref("sha256")})}),
                    "outputPlan": described("render_attempts.output_plan: refs, kinds and a byte cap per output.",
                                            {"type": "array", "minItems": 1, "maxItems": 32,
                                             "items": obj({"outputRef": ref("outputRef"), "kind": ref("artifactKind"),
                                                           "maxBytes": {"type": "integer", "minimum": 1}})})}),
          errors=("not_found", "already_claimed", "secret_not_replayable"),
          description="The lease token is minted now and returned once; only its hash is stored."),
    Route("internal.heartbeat", "POST", "/internal/v1/attempts/{attemptId}/heartbeat", "render host",
          ("host-lease",), worker="jovra-internal",
          body=obj({"progressMilli": {"type": "integer", "minimum": 0, "maximum": 1000},
                    "measurementsSoFar": ref("measurements")}),
          data=obj({"leasedUntil": ref("dateTime"), "cancel": {"type": "boolean"}}),
          errors=("not_found", "conflict", "invalid")),
    Route("internal.input", "GET", "/internal/v1/attempts/{attemptId}/inputs/{inputRef}", "render host",
          ("host-lease",), worker="jovra-internal", range_request=True,
          response_types=("video/mp4", "video/quicktime", "image/jpeg", "application/json", "application/octet-stream"),
          errors=("not_found", "range_not_satisfiable"),
          description="inputRef must be in render_attempts.input_refs; nothing from the queue message is consulted."),
    Route("internal.outputs", "POST", "/internal/v1/attempts/{attemptId}/outputs", "render host", ("host-lease",),
          worker="jovra-internal",
          body=obj({"outputRef": ref("outputRef"), "kind": ref("artifactKind"),
                    "declaredBytes": {"type": "integer", "minimum": 1, "maximum": 1_000_000_000_000},
                    "sha256": ref("sha256")}),
          data=ref("uploadSession"), errors=("not_found", "conflict", "invalid", "secret_not_replayable")),
    Route("internal.result", "POST", "/internal/v1/attempts/{attemptId}/result", "render host", ("host-lease",),
          worker="jovra-internal",
          body=obj({"outcome": {"enum": ["succeeded", "failed"]},
                    "outputs": {"type": "array", "maxItems": 32,
                                "items": obj({"outputRef": ref("outputRef"), "bytes": {"type": "integer", "minimum": 1},
                                              "sha256": ref("sha256")})},
                    "measurements": ref("measurements"), "errorCode": ref("machineCode"),
                    "retryable": {"type": "boolean"}},
                   optional=("errorCode", "retryable"),
                   allOf=[{"if": {"required": ["outcome"], "properties": {"outcome": {"const": "failed"}}},
                           "then": {"required": ["errorCode", "retryable"]},
                           "else": {"properties": {"errorCode": False, "retryable": False}}}]),
          data=obj({"accepted": {"type": "boolean"}}), errors=("not_found", "conflict", "invalid"),
          description="Lease-token fencing: a result from a stale lease is refused and its outputs never registered."),
]

QUEUES = [
    {"name": "render-work", "schema": "queue.render-work.message.schema.json",
     "description": "Wake-up hint for a render host (architecture §7.3 step 2). Consumed at least once."},
    {"name": "render-work-dlq", "schema": "queue.render-work.message.schema.json",
     "description": "Dead letters of render-work (architecture §7.4); the same message, replayed by an operator."},
]

QUEUE_MESSAGE = {
    "description": "A render-work queue message: the attempt id and nothing else (architecture §7.3, security-model "
                   "§8.4, ADR-0018). No media, URL, user text, token, input or output list: a forged or replayed "
                   "message can only name an attempt that already exists and is fenced. Any other field is invalid.",
    **obj({"attemptId": ref("uuid")}),
}
