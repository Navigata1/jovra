#!/usr/bin/env python3
"""PostgREST checks for migration 1 against the running local stack (S76 / B-03).

Proves, through Kong and PostgREST of `supabase start`, with real ES256 session tokens from the local Auth service:
  1. T-DB-35: the Data API exposes only `public` and `graphql_public`; `app_private`, `app_gateway` and `app_ops`
     are refused (PGRST106);
  2. T-DB-01: an unauthenticated request (publishable/anon key only) cannot read or write projects;
  3. a seeded owner creates a project through the API, owner_id comes from the token, and the owner membership row
     follows; the owner cannot name another owner_id (T-DB-07) or read profiles.is_tester (T-DB-30);
  4. T-DB-06 / T-DB-09: a seeded unrelated user sees none of it and cannot change its title.

Sessions are minted without email: the admin API's generate_link returns a one-time token hash, which is verified
like an emailed code. Nothing is printed except check labels, HTTP statuses and error codes; never a key or token.

Usage (from backend/): supabase status -o env > "$TMP/status.env"
                       python3 supabase/scripts/postgrest_identity_smoke.py "$TMP/status.env"
Python standard library only. Exit status is non-zero when any check fails.
"""

from __future__ import annotations

import json
import re
import sys
import uuid

from otp_smoke import Checks, read_env, request, summary  # same folder; shared helpers

OWNER = ("owner.tester@example.test", "00000000-0000-4000-8000-00000000a001")
UNRELATED = ("unrelated.tester@example.test", "00000000-0000-4000-8000-00000000a005")
HIDDEN_SCHEMAS = ("app_private", "app_gateway", "app_ops")
EXPOSED = {"public", "graphql_public"}


def exposed_list(body: dict | list | str) -> set[str]:
    """The schema list PostgREST names in a PGRST106 refusal (its hint or, in older versions, its message)."""
    if not isinstance(body, dict):
        return set()
    for field in ("hint", "message"):
        text = body.get(field) or ""
        match = re.search(r"(?:following schemas are exposed|one of the following):\s*(.+)$", text)
        if match:
            return {s.strip() for s in match.group(1).split(",") if s.strip()}
    return set()


def session_token(api: str, admin: dict[str, str], public: dict[str, str], email: str) -> str:
    status, link = request("POST", f"{api}/auth/v1/admin/generate_link", admin, {"type": "magiclink", "email": email})
    if status != 200 or not isinstance(link, dict):
        raise SystemExit(f"FAIL  generate_link for a seeded tester returned HTTP {status} {summary(link)}")
    token_hash = link.get("hashed_token") or (link.get("properties") or {}).get("hashed_token")
    if not token_hash:
        raise SystemExit("FAIL  generate_link returned no token hash")
    for kind in ("magiclink", "email"):
        status, session = request("POST", f"{api}/auth/v1/verify", public, {"type": kind, "token_hash": token_hash})
        if status == 200 and isinstance(session, dict) and session.get("access_token"):
            return session["access_token"]
    raise SystemExit(f"FAIL  verifying the token hash returned HTTP {status} {summary(session)}")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    env = read_env(sys.argv[1])
    api = env.get("API_URL", "").rstrip("/")
    anon = env.get("ANON_KEY") or env.get("PUBLISHABLE_KEY", "")
    service = env.get("SERVICE_ROLE_KEY") or env.get("SECRET_KEY", "")
    if not api.startswith("http://127.0.0.1") or not anon or not service:
        print("FAIL  the env file must name the local stack (API_URL on 127.0.0.1, an anon and a service key)")
        return 2

    rest = f"{api}/rest/v1"
    public = {"apikey": anon}
    admin = {"apikey": service, "Authorization": f"Bearer {service}"}
    checks = Checks()

    # 1. T-DB-35: exposed schemas.
    for schema in HIDDEN_SCHEMAS:
        status, body = request("GET", f"{rest}/projects?select=id", {**public, "Accept-Profile": schema})
        code = body.get("code") if isinstance(body, dict) else None
        checks.check(status == 406 and code == "PGRST106", f"T-DB-35: Accept-Profile {schema} is refused",
                     f"HTTP {status} {code}")
        listed = exposed_list(body)
        checks.check(listed == EXPOSED, f"T-DB-35: the refusal lists exactly {sorted(EXPOSED)}", f"{sorted(listed)}")
    status, body = request("POST", f"{rest}/rpc/has_project_role", {**public, "Content-Profile": "app_private"},
                           {"p_project": str(uuid.uuid4()), "p_roles": ["owner"]})
    checks.check(status == 406, "T-DB-35: an RPC into app_private is refused", f"HTTP {status} {summary(body)}")

    # 2. T-DB-01: unauthenticated.
    status, body = request("GET", f"{rest}/projects?select=id", public)
    checks.check(status in (401, 403) and isinstance(body, dict) and body.get("code") == "42501",
                 "T-DB-01: unauthenticated GET /projects is denied", f"HTTP {status} {summary(body)}")
    status, body = request("POST", f"{rest}/projects", public, {"local_project_id": str(uuid.uuid4()), "title": "x"})
    checks.check(status in (401, 403) and isinstance(body, dict) and body.get("code") == "42501",
                 "T-DB-01: unauthenticated POST /projects is denied", f"HTTP {status} {summary(body)}")

    # 3. Owner, with a real session token.
    owner = {**public, "Authorization": f"Bearer {session_token(api, admin, public, OWNER[0])}"}
    local_id = str(uuid.uuid4())
    status, body = request("POST", f"{rest}/projects", {**owner, "Prefer": "return=representation"},
                           {"local_project_id": local_id, "title": "API match", "kind": "match"})
    created = body[0] if isinstance(body, list) and body else {}
    project_id = created.get("id", "")
    checks.check(status == 201 and created.get("owner_id") == OWNER[1] and created.get("revision") == 1,
                 "owner creates a project; owner_id comes from the token", f"HTTP {status}")
    status, body = request("GET", f"{rest}/project_members?select=user_id,role&project_id=eq.{project_id}", owner)
    checks.check(status == 200 and body == [{"user_id": OWNER[1], "role": "owner"}],
                 "the owner membership row follows the project", f"HTTP {status}")
    status, body = request("POST", f"{rest}/projects", owner,
                           {"owner_id": UNRELATED[1], "local_project_id": str(uuid.uuid4()), "title": "planted"})
    checks.check(status == 403 and isinstance(body, dict) and body.get("code") == "42501",
                 "T-DB-07: naming owner_id is denied", f"HTTP {status} {summary(body)}")
    status, body = request("GET", f"{rest}/profiles?select=is_tester", owner)
    checks.check(status == 403 and isinstance(body, dict) and body.get("code") == "42501",
                 "T-DB-30: profiles.is_tester is not selectable", f"HTTP {status} {summary(body)}")

    # 4. Unrelated user, with a real session token.
    unrelated = {**public, "Authorization": f"Bearer {session_token(api, admin, public, UNRELATED[0])}"}
    status, body = request("GET", f"{rest}/projects?select=id&id=eq.{project_id}", unrelated)
    checks.check(status == 200 and body == [], "T-DB-06: the unrelated user sees 0 rows of the owner's project",
                 f"HTTP {status}")
    status, body = request("GET", f"{rest}/project_members?select=user_id&project_id=eq.{project_id}", unrelated)
    checks.check(status == 200 and body == [], "T-DB-06: the unrelated user sees 0 membership rows", f"HTTP {status}")
    status, body = request("PATCH", f"{rest}/projects?id=eq.{project_id}",
                           {**unrelated, "Prefer": "return=representation"}, {"title": "hijacked"})
    checks.check(status == 200 and body == [], "T-DB-09: the unrelated user's PATCH changes 0 rows", f"HTTP {status}")
    status, body = request("GET", f"{rest}/projects?select=title,revision&id=eq.{project_id}", owner)
    checks.check(status == 200 and body == [{"title": "API match", "revision": 1}],
                 "the owner's project is unchanged", f"HTTP {status}")

    print(json.dumps({"failed": checks.failed}))
    return 1 if checks.failed else 0


if __name__ == "__main__":
    sys.exit(main())
