/**
 * core.ts against literals produced by spec/reference/studio/core.py (Python 3, the reference): canonical bytes and
 * hash, half-up rounding, the time -> frame rule, exact fractions, integer pct and the fixture patch subset.
 */

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  F, Reject, canonicalJson, canonicalSha256, deltaPpDisplay, frameAtUs, pct, pyCompare, pyEq,
  roundHalfUp,
} from "../../src/heuristic/core.ts";
import { applyPatch } from "./fixture-patch.ts";

const DOC = { b: [1, null, true], a: "Coach’s \"cut\"\n\u0001", "é": { z: 0, y: -3 } };

test("canonical JSON is Python's json.dumps(sort_keys, compact, ensure_ascii=False) and hashes the same", () => {
  assert.equal(canonicalJson(DOC), '{"a":"Coach’s \\"cut\\"\\n\\u0001","b":[1,null,true],"é":{"y":-3,"z":0}}');
  assert.equal(canonicalSha256(DOC), "ed631c72019fa2e5f7610968e3d099fa322ace678cac275ad563ec41830aa0e3");
});

test("canonical JSON refuses floats, as the reference does", () => {
  assert.throws(() => canonicalJson({ fps: 29.97 }), (e: unknown) => e instanceof Reject && e.code === "floatInContract");
});

test("half-up rounding and the one time -> frame rule", () => {
  assert.equal(roundHalfUp(F.of(5, 2)), 3);
  assert.equal(roundHalfUp(F.of(-5, 2)), -2);
  assert.equal(roundHalfUp(F.of(7, 3)), 2);
  const fps60 = { num: 60, den: 1 };
  assert.equal(frameAtUs(1_196_000_000, fps60), 71760);
  assert.equal(frameAtUs(8333, fps60), 0);
  assert.equal(frameAtUs(8334, fps60), 1);
});

test("fractions are exact and print like Python's Fraction", () => {
  assert.equal(String(F.of(5435, 30)), "1087/6");
  assert.equal(String(F.of(10, 5)), "2");
  assert.ok(F.of(1, 3).add(F.of(2, 3)).eq(1));
  assert.equal(F.of(-7, 2).floor(), -4);
  assert.equal(F.of(-7, 2).ceil(), -3);
  assert.equal(F.of(-7, 2).trunc(), -3);
});

test("integer pct and the percentage-point delta copy", () => {
  assert.equal(pct(12, 30), 40);
  assert.equal(pct(1, 3), 33);
  assert.equal(pct(0, 0), null);
  assert.equal(deltaPpDisplay(40, 60), "+20 percentage points");
  assert.equal(deltaPpDisplay(41, 40), "-1 percentage point");
  assert.equal(deltaPpDisplay(null, 40), "—");
});

test("the RFC 6902 subset patches a copy", () => {
  const doc = { a: [1, 2, 3], b: { c: 1 } };
  const out = applyPatch(doc, [
    { op: "add", path: "/a/1", value: 9 }, { op: "remove", path: "/b/c" }, { op: "add", path: "/a/-", value: 4 },
    { op: "replace", path: "/a/0", value: 0 },
  ]);
  assert.deepEqual(out, { a: [0, 9, 2, 3, 4], b: {} });
  assert.deepEqual(doc, { a: [1, 2, 3], b: { c: 1 } });
});

test("Python equality and tuple ordering", () => {
  assert.ok(pyEq({ a: [1, "x"] }, { a: [1, "x"] }));
  assert.ok(pyEq(true, 1));
  assert.ok(!pyEq({ a: 1 }, { a: 1, b: null }));
  assert.equal(pyCompare([1, "2026-09-09", 0], [1, "2026-09-09", 1]), -1);
  assert.equal(pyCompare([0], [0, 5]), -1);
  assert.equal(pyCompare([2, 1], [1, 9]), 1);
});
