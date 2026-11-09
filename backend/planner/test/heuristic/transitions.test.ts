import assert from "node:assert/strict";
import { test } from "node:test";

import { runVector } from "../../src/heuristic/compile.ts";
import { canonicalJson, type J } from "../../src/heuristic/core.ts";
import { compileBases, compileContext, FIXTURES, loadJson, loadProfiles } from "./vectors.ts";

const doc = loadJson(`${FIXTURES}/vectors/barcode-court.json`);
const cases: J[] = doc.cases.filter((c: J) => c.op === "compile");
const bases = compileBases(doc);
const profiles = loadProfiles();

function compileInput(c: J): J {
  return { ...structuredClone(c.input), context: compileContext(c, bases) };
}

function compile(input: J): J {
  return runVector(profiles, { op: "compile", input });
}

test("the S09 suite includes both transition compiles and a refusal", () => {
  assert.ok(cases.some((c) => c.expect.edl));
  assert.ok(cases.some((c) => c.expect.rejectCode === "contactProtected"));
});

for (const c of cases) {
  test(`S09 compile result matches the Python reference: ${c.id}`, () => {
    const input = compileInput(c);
    const before = canonicalJson(input);
    const got = compile(input);
    // The barcode fixture also carries renderer facts from framemap.py and a clean alternate.
    // Compare the complete compiler result, which is the part owned by this adapter.
    const { frameMap, frameMapSha256, clickMap, overlays, operations, cleanAlternate, ...expected } = c.expect;
    assert.equal(canonicalJson(got), canonicalJson(expected));
    assert.equal(canonicalJson(input), before, "compiling leaves the request and trusted context intact");
    assert.equal(canonicalJson(compile(JSON.parse(before))), canonicalJson(got));
  });
}

function rallyInput(): J {
  const c = cases.find((vector) => vector.id === "rally-60-portrait");
  assert.ok(c, "the shared rally transition case is present");
  return compileInput(c);
}

test("an unsupported renderer transition keeps a cut and reports the omitted operation", () => {
  const input = rallyInput();
  input.context.renderer.supportedOps = input.context.renderer.supportedOps.filter((op: string) => op !== "transition");
  const got = compile(input);
  assert.ok(got.edl.segments.every((s: J) => s.transitionIn.type === "cut" && s.transitionIn.frames === 0));
  assert.deepEqual(got.omitted, ["b03", "b04", "b05"].map((beatId) => ({
    beatId, op: "transition", reason: "notInThisBuild",
  })));
  assert.deepEqual(got.notInThisBuild, ["transition"]);
});

test("unshown beats are reported in canonical order, including prototype-named ids", () => {
  const input = rallyInput();
  input.request.transitions = JSON.parse('{"constructor":{"type":"dip","frames":6},"a-missing":{"type":"dip","frames":6}}');
  const got = compile(input);
  assert.deepEqual(got.omitted, ["a-missing", "constructor"].map((beatId) => ({
    beatId, op: "transition", reason: "beatOmitted",
  })));
  assert.ok(got.edl.segments.every((s: J) => s.transitionIn.type === "cut"));
});

test("a requested transition on the first shown beat is refused", () => {
  const input = rallyInput();
  input.request.transitions = { b01: { type: "dissolve", frames: 6 } };
  assert.deepEqual(compile(input), { rejectCode: "badRequest" });
});

test("malformed transition maps and entries are refused", () => {
  for (const transitions of [
    true, [{ type: "dip", frames: 6 }], { b03: null }, { b03: { type: "cut", frames: 0 } },
    { b03: { type: "dip", frames: true } }, { b03: { type: "dip", frames: 1.5 } },
    { b03: { type: "dip", frames: 6, extra: true } },
  ]) {
    const input = rallyInput();
    input.request.transitions = transitions;
    assert.deepEqual(compile(input), { rejectCode: "badRequest" });
  }
});

test("a very large transition frame count fails as a typed refusal", () => {
  const input = rallyInput();
  input.request.transitions = { b03: { type: "dissolve", frames: Number.MAX_SAFE_INTEGER } };
  assert.deepEqual(compile(input), { rejectCode: "transitionTooLong" });
});
