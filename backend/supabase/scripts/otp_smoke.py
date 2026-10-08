#!/usr/bin/env python3
"""OTP smoke test against the running local stack (S75 / B-02; finding 15; HTTP half of T-GW-30).

Proves, through the real Auth service, Kong and Mailpit of `supabase start`:
  1. a seeded tester can request an email code (create_user false), read it in Mailpit and sign in;
  2. the session token is ES256 (ADR-0022) and belongs to that tester;
  3. an OTP request with create_user true for an unknown email is refused and creates no user;
  4. an anonymous sign-in is refused;
  5. the hook alone refuses an unknown email even on the admin path, which bypasses enable_signup;
  6. the operator path works with sign-ups off: an allow-listed address can be created through the admin API.

Usage (from backend/): supabase status -o env > "$TMP/status.env"; python3 supabase/scripts/otp_smoke.py "$TMP/status.env"
The env file holds the local stack's throwaway keys. This script never prints a key, a code or a token.
Python standard library only. Exit status is non-zero when any check fails.
"""

from __future__ import annotations

import base64
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TESTER = "owner.tester@example.test"
TESTER_ID = "00000000-0000-4000-8000-00000000a001"
UNKNOWN = "stranger.otp@example.test"
UNKNOWN_ADMIN = "stranger.admin@example.test"
PENDING = "pending.tester@example.test"
MAILPIT_DEFAULT = "http://127.0.0.1:54324"
CODE_PATTERN = re.compile(r"\b(\d{6})\b")


def read_env(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r'^([A-Z_]+)=(?:"(.*)"|(.*))$', line.strip())
            if match:
                values[match.group(1)] = match.group(2) if match.group(2) is not None else match.group(3)
    return values


def request(method: str, url: str, headers: dict[str, str], body: dict | None = None) -> tuple[int, dict | list | str]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json", **headers})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            status, raw = resp.status, resp.read().decode()
    except urllib.error.HTTPError as err:
        status, raw = err.code, err.read().decode()
    try:
        return status, json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        return status, raw


def jwt_part(token: str, index: int) -> dict:
    part = token.split(".")[index]
    return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))


def summary(body: dict | list | str) -> str:
    """Error code and message only, never a token."""
    if isinstance(body, dict):
        keys = ("code", "error_code", "error", "msg", "message")
        return json.dumps({k: body[k] for k in keys if k in body})
    return str(body)[:200]


class Checks:
    def __init__(self) -> None:
        self.failed = 0

    def check(self, ok: bool, label: str, detail: str = "") -> bool:
        print(f"{'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))
        if not ok:
            self.failed += 1
        return ok


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    env = read_env(sys.argv[1])
    api = env.get("API_URL", "").rstrip("/")
    anon = env.get("ANON_KEY") or env.get("PUBLISHABLE_KEY", "")
    service = env.get("SERVICE_ROLE_KEY") or env.get("SECRET_KEY", "")
    mailpit = (env.get("MAILPIT_URL") or env.get("INBUCKET_URL") or MAILPIT_DEFAULT).rstrip("/")
    if not api.startswith("http://127.0.0.1") or not anon or not service:
        print("FAIL  the env file must name the local stack (API_URL on 127.0.0.1, an anon and a service key)")
        return 2

    public = {"apikey": anon}
    admin = {"apikey": service, "Authorization": f"Bearer {service}"}
    checks = Checks()

    def user_emails() -> set[str]:
        status, body = request("GET", f"{api}/auth/v1/admin/users?per_page=1000", admin)
        users = body.get("users", []) if isinstance(body, dict) else []
        if status != 200:
            raise SystemExit(f"FAIL  admin user list returned {status}")
        return {u.get("email", "") for u in users}

    # 1-2. A seeded tester signs in with an email code read from Mailpit.
    request("DELETE", f"{mailpit}/api/v1/messages", {})
    status, body = request("POST", f"{api}/auth/v1/otp", public, {"email": TESTER, "create_user": False})
    checks.check(status == 200, "seed tester can request an email code (create_user false)", f"HTTP {status}")

    code = None
    for _ in range(20):
        status, found = request("GET", f"{mailpit}/api/v1/search?query={urllib.parse.quote('to:' + TESTER)}", {})
        messages = found.get("messages", []) if isinstance(found, dict) else []
        if messages:
            _, message = request("GET", f"{mailpit}/api/v1/message/{messages[0]['ID']}", {})
            text = message.get("Text", "") if isinstance(message, dict) else ""
            match = CODE_PATTERN.search(text)
            code = match.group(1) if match else None
            break
        time.sleep(0.5)
    checks.check(code is not None, "the code arrives in Mailpit", "six digits found" if code else "no message or code")

    if code:
        status, session = request("POST", f"{api}/auth/v1/verify", public, {"type": "email", "email": TESTER, "token": code})
        token = session.get("access_token", "") if isinstance(session, dict) else ""
        if checks.check(status == 200 and bool(token), "the tester signs in with the code", f"HTTP {status}"):
            header, claims = jwt_part(token, 0), jwt_part(token, 1)
            checks.check(header.get("alg") == "ES256", "the access token is ES256", f"alg {header.get('alg')}")
            checks.check(claims.get("sub") == TESTER_ID and claims.get("email") == TESTER,
                         "the token belongs to the seeded tester")
            checks.check(claims.get("is_anonymous") is False and claims.get("role") == "authenticated",
                         "the token is a real, non-anonymous user")
        status, _ = request("POST", f"{api}/auth/v1/verify", public, {"type": "email", "email": TESTER, "token": code})
        checks.check(status >= 400, "the same code cannot be used twice", f"HTTP {status}")

    # 3. Unknown email with create_user true: refused, and no user appears (finding 15).
    status, body = request("POST", f"{api}/auth/v1/otp", public, {"email": UNKNOWN, "create_user": True})
    checks.check(400 <= status < 500, "OTP with create_user true for an unknown email is refused",
                 f"HTTP {status} {summary(body)}")
    checks.check(UNKNOWN not in user_emails(), "no user row was created for the unknown email")

    # 4. Anonymous sign-in is off.
    status, body = request("POST", f"{api}/auth/v1/signup", public, {"data": {}})
    checks.check(400 <= status < 500, "anonymous sign-in is refused", f"HTTP {status} {summary(body)}")

    # 5. The hook alone: the admin API ignores enable_signup, so only the hook can refuse this.
    status, body = request("POST", f"{api}/auth/v1/admin/users", admin, {"email": UNKNOWN_ADMIN, "email_confirm": True})
    checks.check(400 <= status < 500 and "signup_not_allowed" in json.dumps(body),
                 "the hook refuses an unknown email on the admin path", f"HTTP {status} {summary(body)}")
    checks.check(UNKNOWN_ADMIN not in user_emails(), "no user row was created on the admin path")

    # 6. The operator path: an allow-listed address is created with sign-ups off, then removed again.
    status, body = request("POST", f"{api}/auth/v1/admin/users", admin, {"email": PENDING, "email_confirm": True})
    created = status == 200 and isinstance(body, dict) and body.get("email") == PENDING
    checks.check(created, "an allow-listed address can be created through the admin API", f"HTTP {status}")
    if created:
        request("DELETE", f"{api}/auth/v1/admin/users/{body['id']}", admin)

    print(f"\n{'OK' if checks.failed == 0 else 'FAILED'}: {checks.failed} failing check(s)")
    return 1 if checks.failed else 0


if __name__ == "__main__":
    sys.exit(main())
