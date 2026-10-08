"""Tests for the backend contract tools (S81). Run from the repo root:

    python3 -m unittest discover -s backend/contracts/tools -p 'test_*.py'

Seams under test are the three command-line tools and their importable entry points:
route coverage (architecture §5.1 against routes.v1.json), the fixture validator and the fixture hygiene check.
Expected values come from the architecture document read by hand (41 routes), not from the tools.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
CONTRACTS = TOOLS.parent
REPO = CONTRACTS.parents[1]
ARCHITECTURE = REPO / "docs" / "backend" / "architecture.md"
sys.path.insert(0, str(TOOLS))

import route_coverage  # noqa: E402


def run(tool: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(TOOLS / tool), *args], capture_output=True, text=True, cwd=REPO)


class RouteCoverageTest(unittest.TestCase):
    def test_reads_every_route_of_section_5_1(self):
        routes = route_coverage.routes_from_architecture(ARCHITECTURE.read_text(encoding="utf-8"))
        # Counted by hand from the §5.1 table: 40 rows, one of which ("pause", "/resume") names two routes.
        self.assertEqual(len(routes), 41)
        self.assertIn(("GET", "/v1/health"), routes)
        self.assertIn(("POST", "/v1/jobs/{jobId}/pause"), routes)
        self.assertIn(("POST", "/v1/jobs/{jobId}/resume"), routes)
        self.assertIn(("GET", "/s/{token}/thumbnail"), routes)
        self.assertIn(("POST", "/internal/v1/attempts/{attemptId}/result"), routes)
        self.assertIn(("GET", "/v1/deletion-requests/{id}"), routes)

    def test_section_ends_at_the_next_heading(self):
        text = (
            "### 5.1 Endpoints\n\n| Method and path | Caller |\n|---|---|\n| `GET /v1/a` | x |\n"
            "\n### 5.2 Next\n\n| `GET /v1/not-a-route` | x |\n"
        )
        self.assertEqual(route_coverage.routes_from_architecture(text), [("GET", "/v1/a")])

    def test_the_committed_manifest_covers_the_document(self):
        result = run("route_coverage.py")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("41 routes in architecture §5.1", result.stdout)

    def test_a_missing_route_fails_and_is_named(self):
        manifest = json.loads((CONTRACTS / "routes.v1.json").read_text(encoding="utf-8"))
        manifest["routes"] = [r for r in manifest["routes"] if r["path"] != "/v1/jobs/{jobId}/resume"]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "routes.v1.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            result = run("route_coverage.py", "--manifest", str(path))
        self.assertEqual(result.returncode, 1)
        self.assertIn("MISSING  POST /v1/jobs/{jobId}/resume", result.stdout)

    def test_a_route_without_a_fixture_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "contracts"
            shutil.copytree(CONTRACTS, copy, ignore=shutil.ignore_patterns("__pycache__"))
            for fixture in (copy / "fixtures" / "routes" / "health").glob("response.*.json"):
                fixture.unlink()
            result = run("route_coverage.py", "--contracts", str(copy))
        self.assertEqual(result.returncode, 1)
        self.assertIn("health: no response fixture", result.stdout)


class ValidatorTest(unittest.TestCase):
    def test_the_committed_contracts_validate(self):
        result = run("validate.py")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def _validate_copy(self, mutate) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "contracts"
            shutil.copytree(CONTRACTS, copy, ignore=shutil.ignore_patterns("__pycache__"))
            mutate(copy)
            return run("validate.py", "--contracts", str(copy))

    def test_a_queue_message_with_an_extra_field_is_invalid(self):
        def mutate(copy: Path):
            path = copy / "fixtures" / "queues" / "render-work" / "message.wake-up.json"
            message = json.loads(path.read_text(encoding="utf-8"))
            message["leaseToken"] = "jvl_" + "Sample" * 7 + "S"
            path.write_text(json.dumps(message), encoding="utf-8")

        result = self._validate_copy(mutate)
        self.assertEqual(result.returncode, 1)
        self.assertIn("leaseToken", result.stdout)

    def test_an_invalid_fixture_in_a_valid_slot_turns_the_check_red(self):
        def mutate(copy: Path):
            bad = copy / "fixtures" / "invalid" / "quotes.accept" / "request.missing-inputs-hash.json"
            shutil.copy(bad, copy / "fixtures" / "routes" / "quotes.accept" / "request.deliberately-invalid.json")

        result = self._validate_copy(mutate)
        self.assertEqual(result.returncode, 1)
        self.assertIn("request.deliberately-invalid.json", result.stdout)

    def test_an_invalid_case_that_validates_turns_the_check_red(self):
        def mutate(copy: Path):
            good = copy / "fixtures" / "routes" / "health" / "request.anonymous.json"
            shutil.copy(good, copy / "fixtures" / "invalid" / "health" / "request.anonymous.json")
            cases = json.loads((copy / "fixtures" / "invalid" / "cases.json").read_text(encoding="utf-8"))
            cases["cases"].append({"file": "health/request.anonymous.json", "schema": "route.health.request.schema.json",
                                   "why": "planted: a valid request listed as invalid", "errorContains": "$"})
            (copy / "fixtures" / "invalid" / "cases.json").write_text(json.dumps(cases), encoding="utf-8")

        result = self._validate_copy(mutate)
        self.assertEqual(result.returncode, 1)
        self.assertIn("health/request.anonymous.json: expected to be invalid but validated", result.stdout)

    def test_request_id_header_and_body_must_agree(self):
        def mutate(copy: Path):
            path = copy / "fixtures" / "routes" / "health" / "response.ok.json"
            response = json.loads(path.read_text(encoding="utf-8"))
            response["body"]["requestId"] = "00000000-0000-4000-8000-0000000000ff"
            path.write_text(json.dumps(response), encoding="utf-8")

        result = self._validate_copy(mutate)
        self.assertEqual(result.returncode, 1)
        self.assertIn("requestId differs from the X-Request-Id header", result.stdout)

    def test_schemas_are_what_the_generator_writes(self):
        result = run("generate.py", "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class HygieneTest(unittest.TestCase):
    def test_the_committed_fixtures_are_clean(self):
        result = run("check_fixture_hygiene.py")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def _scan(self, text: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixture.json"
            path.write_text(text, encoding="utf-8")
            return run("check_fixture_hygiene.py", str(path))

    def test_each_forbidden_kind_is_caught(self):
        planted = {
            "hosted url": '{"url": "https://jovra-gateway.' + 'workers.dev/v1/health"}',
            "project ref": '{"iss": "https://abcdefghijklmnopqrst.' + 'supabase.co/auth/v1"}',
            "jwt": '{"Authorization": "Bearer eyJ' + 'hbGciOiJFUzI1NiJ9.eyJ' + 'zdWIiOiIxMjM0NTY3ODkwIn0.x"}',
            "email": '{"inviteeEmail": "coach@' + 'gmail.com"}',
            "real-looking uuid": '{"jobId": "3f2b8c1e-9d4a-4e7b-8a6c-1b2d3e4f5a6b"}',
            "non-sample token": '{"code": "jvi_' + "Q" * 43 + '"}',
        }
        for kind, text in planted.items():
            with self.subTest(kind=kind):
                result = self._scan(text)
                self.assertEqual(result.returncode, 1, f"{kind} was not caught: {result.stdout}")

    def test_example_test_values_pass(self):
        text = json.dumps({
            "url": "https://gateway.example.test/s/jvh_" + "Sample" * 7 + "S",
            "inviteeEmail": "coach.tester@example.test",
            "jobId": "00000000-0000-4000-8000-000000000042",
        })
        result = self._scan(text)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
