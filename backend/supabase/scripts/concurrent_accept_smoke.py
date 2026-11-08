#!/usr/bin/env python3
"""T-DB-71 against the running local stack (S79 / B-06): two concurrent accept_quote calls at the ceiling.

pgTAP runs in one session, so it cannot race two transactions; this script opens real concurrent sessions with psql:
  1. setup (committed): two owners, each with a project, a verified source in the current manifest, a story plan and an
     open quote made by create_quote as jovra_gateway; an environment daily ceiling that fits exactly one of the two
     caps on top of today's commitments;
  2. session A accepts its quote as jovra_gateway and holds its transaction open (pg_sleep) before committing;
     session B starts while A is open and accepts the other quote;
  3. while both are open, a third connection sees B waiting on the spend advisory lock (the serialization point);
  4. exactly one acceptance succeeds, the other is P0402 budget_exceeded, B waited for A's commit, and
     app_ops.spend_commitments holds exactly one cap_open row for the two quotes;
  5. cleanup: the two auth users (cascading their projects, quotes, holds and jobs), the environment limits row and the
     temporary role grant are removed; the two append-only ledgers keep their rows, as they would in production.

If the advisory lock in app_private.commit_spend were missing, both sessions would read today's total before either
committed and both acceptances would pass: this check would then fail.

Usage (from backend/): supabase status -o env > "$TMP/status.env"
                       python3 supabase/scripts/concurrent_accept_smoke.py "$TMP/status.env"
Python standard library and psql only. Prints check labels and SQLSTATEs, never a key. Exit status is non-zero when
any check fails.
"""

from __future__ import annotations

import json
import subprocess
import sys
import threading
import time
import uuid

from otp_smoke import Checks, read_env  # same folder; shared helpers

OUTPUT = {"fps": {"num": 30, "den": 1}, "width": 1920, "height": 1080, "aspect": "16:9", "container": "mp4",
          "videoCodec": "h264", "audioCodec": "aac", "audioSampleRate": 48000, "durationTargetSec": 120}
CONSENT = {"at": "2026-11-08T10:00:00Z", "consentRecordId": "consent-t71", "consentTextVersion": "studio-cloud-consent@1.0.0",
           "modelProvider": False, "retentionDays": 7, "textClasses": [], "uploadSelectedSources": True}
HOLD_SECONDS = 4


def psql(db_url: str, script: str) -> subprocess.CompletedProcess:
    return subprocess.run(["psql", db_url, "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-f", "-"],
                          input="\\set VERBOSITY verbose\n" + script, capture_output=True, text=True, timeout=120)


def lit(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    env = read_env(sys.argv[1])
    db_url = env.get("DB_URL", "")
    if "127.0.0.1" not in db_url and "localhost" not in db_url:
        print("FAIL  the env file must name the local stack (DB_URL on 127.0.0.1)")
        return 2
    checks = Checks()
    run = uuid.uuid4().hex[:8]
    owners = [f"t71_{run}_a", f"t71_{run}_b"]
    projects = [str(uuid.uuid4()), str(uuid.uuid4())]
    sources = [str(uuid.uuid4()), str(uuid.uuid4())]
    plans = [str(uuid.uuid4()), str(uuid.uuid4())]

    # 1. Setup, committed.
    setup = ["begin;", "grant jovra_gateway to postgres;"]
    for i in range(2):
        setup += [
            f"select tests.create_supabase_user({lit(owners[i])});",
            f"insert into public.projects (id, owner_id, local_project_id, title) values ({lit(projects[i])}, "
            f"tests.get_supabase_uid({lit(owners[i])}), gen_random_uuid(), 'T-DB-71 Sample');",
            f"insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, "
            f"declared_sha256) values ({lit(sources[i])}, {lit(projects[i])}, 'primary_baseline', gen_random_uuid(), "
            f"'verified', 100000000, sha256({lit(sources[i])}::bytea));",
            f"insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values "
            f"({lit(projects[i])}, jsonb_build_object('sources', jsonb_build_array(jsonb_build_object('sourceId', "
            f"{lit(sources[i])}))), sha256('t71'::bytea), 'render');",
            f"insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values "
            f"({lit(plans[i])}, {lit(projects[i])}, 'coach-cut', 1, 'T-DB-71 plan');",
        ]
    setup += ["insert into app_ops.settings (env) values ('local') on conflict (id) do update set env = excluded.env;",
              "commit;"]
    result = psql(db_url, "\n".join(setup))
    if not checks.check(result.returncode == 0, "T-DB-71 setup: two owners, verified sources and plans (committed)",
                        result.stderr.strip()[-300:]):
        return 1

    quotes = []
    for i in range(2):
        result = psql(db_url, f"set role jovra_gateway;\nselect app_gateway.create_quote("
                              f"{lit(owner_id(db_url, owners[i]))}, {lit(projects[i])}, {lit(plans[i])}, null, "
                              f"'heuristic', {lit(json.dumps(OUTPUT))}::jsonb, array[{lit(sources[i])}]::uuid[], 7, "
                              f"gen_random_uuid());")
        if result.returncode != 0:
            checks.check(False, f"T-DB-71 setup: create_quote for owner {i + 1}", result.stderr.strip()[-300:])
            cleanup(db_url, owners)
            return 1
        quotes.append(json.loads(result.stdout.strip().splitlines()[-1]))
    caps = [quote_cap(db_url, q["quoteId"]) for q in quotes]
    # The ceiling fits exactly one cap on top of today's cap commitments (the ledger is append-only, so earlier rows of
    # today count too).
    result = psql(db_url, "insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, "
                          "daily_ceiling_micro_usd) select 'environment', null, 1000000000000, coalesce(sum(amount_micro_usd), 0) "
                          f"+ {max(caps)} + {min(caps) // 2} from app_ops.spend_commitments "
                          "where at >= date_trunc('day', now(), 'UTC') and kind in ('cap_open', 'cap_topup');")
    checks.check(result.returncode == 0, "T-DB-71 setup: an environment ceiling that fits one of the two caps",
                 f"caps {caps}")

    # 2. Two sessions.
    def accept_script(i: int, hold: bool) -> str:
        owner = owner_id(db_url, owners[i])
        return "\n".join([
            "begin;",
            "set local role jovra_gateway;",
            f"select app_gateway.accept_quote({lit(owner)}, {lit(quotes[i]['quoteId'])}, "
            f"decode({lit(quotes[i]['inputsSha256'])}, 'hex'), {lit(json.dumps(CONSENT))}::jsonb, "
            f"{quotes[i]['capCredits']}, {lit('t71-' + run + '-' + str(i))}, gen_random_uuid()) ->> 'state';",
            f"select pg_sleep({HOLD_SECONDS});" if hold else "",
            "commit;",
        ])

    scripts = [accept_script(0, True), accept_script(1, False)]
    results: dict[int, subprocess.CompletedProcess] = {}
    timing: dict[int, float] = {}

    def worker(i: int) -> None:
        start = time.monotonic()
        results[i] = psql(db_url, scripts[i])
        timing[i] = time.monotonic() - start

    thread_a = threading.Thread(target=worker, args=(0,))
    thread_a.start()
    time.sleep(1.0)
    thread_b = threading.Thread(target=worker, args=(1,))
    thread_b.start()
    time.sleep(1.0)

    # 3. While A holds its transaction, B waits on the spend advisory lock.
    waiting = psql(db_url, "select count(*) from pg_catalog.pg_locks where locktype = 'advisory' and not granted;")
    thread_a.join()
    thread_b.join()
    checks.check(waiting.returncode == 0 and waiting.stdout.strip().isdigit() and int(waiting.stdout.strip()) >= 1,
                 "T-DB-71: while A is open, B waits on the spend advisory lock", f"waiting={waiting.stdout.strip()}")

    # 4. Exactly one succeeds; the other is P0402.
    outcomes = []
    for i in range(2):
        r = results[i]
        if r.returncode == 0 and "consented" in r.stdout:
            outcomes.append("consented")
        elif "P0402" in r.stderr and "budget_exceeded" in r.stderr:
            outcomes.append("P0402")
        else:
            outcomes.append("unexpected: " + (r.stderr.strip()[-200:] or r.stdout.strip()[-200:]))
    checks.check(sorted(outcomes) == ["P0402", "consented"],
                 "T-DB-71: exactly one of two concurrent acceptances succeeds, the other is P0402 budget_exceeded",
                 f"A={outcomes[0]} B={outcomes[1]}")
    checks.check(timing.get(1, 0) >= HOLD_SECONDS - 1.5,
                 "T-DB-71: B returned only after A committed (the ceiling checks were serialized)",
                 f"B took {timing.get(1, 0):.1f}s")
    ids = ", ".join(lit(q["quoteId"]) for q in quotes)
    counts = psql(db_url, "select (select count(*) from app_ops.spend_commitments c join public.usage_reservations r "
                          f"on r.id = c.reservation_id where r.initial_quote_id in ({ids}) and c.kind = 'cap_open')"
                          " || ' ' || (select count(*) from app_ops.spend_commitments c where c.kind = 'cap_open' "
                          "and c.owner_id in (select id from public.profiles where id in "
                          f"('{owner_id(db_url, owners[0])}', '{owner_id(db_url, owners[1])}')))"
                          f" || ' ' || (select count(*) from public.render_jobs where quote_id in ({ids}));")
    checks.check(counts.returncode == 0 and counts.stdout.strip() == "1 1 1",
                 "T-DB-71: spend_commitments holds one cap_open row and one job exists for the two quotes",
                 f"commitments/ledger/jobs={counts.stdout.strip()}")

    # 5. Cleanup.
    cleaned = cleanup(db_url, owners)
    checks.check(cleaned.returncode == 0, "T-DB-71 cleanup: users, projects and the limits row removed",
                 cleaned.stderr.strip()[-200:])
    print("T-DB-71: all checks passed" if checks.failed == 0 else f"T-DB-71: {checks.failed} check(s) failed")
    return 1 if checks.failed else 0


_OWNER_IDS: dict[str, str] = {}


def owner_id(db_url: str, identifier: str) -> str:
    if identifier not in _OWNER_IDS:
        result = psql(db_url, f"select tests.get_supabase_uid({lit(identifier)});")
        _OWNER_IDS[identifier] = result.stdout.strip().splitlines()[-1]
    return _OWNER_IDS[identifier]


def quote_cap(db_url: str, quote_id: str) -> int:
    result = psql(db_url, f"select cap_cost_micro_usd from public.quotes where id = {lit(quote_id)};")
    return int(result.stdout.strip().splitlines()[-1])


def cleanup(db_url: str, owners: list[str]) -> subprocess.CompletedProcess:
    names = ", ".join(lit(o) for o in owners)
    return psql(db_url, "\n".join([
        "begin;",
        "delete from app_ops.spend_limits where scope = 'environment';",
        f"delete from auth.users where raw_user_meta_data ->> 'test_identifier' in ({names});",
        "revoke jovra_gateway from postgres;",
        "commit;",
    ]))


if __name__ == "__main__":
    sys.exit(main())
