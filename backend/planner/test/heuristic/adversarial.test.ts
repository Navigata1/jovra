/**
 * Hazards the Python reference does not have but a JavaScript port could: ids that name Object.prototype members must
 * resolve to nothing, so a plan cannot smuggle "constructor" or "__proto__" past the trust check, the grammar lint or
 * the EDL validator. Each mutation starts from a plan or EDL that passes and must be refused with the reference's code.
 */

import assert from "node:assert/strict";
import { test } from "node:test";

import * as compiler from "../../src/heuristic/compile.ts";
import { Reject, deepClone, type J } from "../../src/heuristic/core.ts";
import { validate } from "../../src/heuristic/edl.ts";
import * as planner from "../../src/heuristic/planner.ts";
import { applyPatch } from "./fixture-patch.ts";
import { CONTEXT_CASE, compileBases, compileContext, loadProfiles, loadVectors } from "./vectors.ts";

const profiles = loadProfiles();
const vectors = loadVectors();
const PROTOTYPE_IDS = ["constructor", "__proto__", "toString", "hasOwnProperty"];

function rejects(fn: () => unknown, code: string): void {
  assert.throws(fn, (e: unknown) => e instanceof Reject && e.code === code, `expected ${code}`);
}

const plannerBase = vectors.planner.cases.find((c: J) => c.id === CONTEXT_CASE).expect.context;
const coachPlan = vectors.planner.cases.find((c: J) => c.id === "coach-cut-3min").expect.plan;

test("the base plan passes the trust check (so each refusal below is the mutation's)", () => {
  assert.deepEqual(planner.check(profiles, coachPlan, plannerBase), { beats: coachPlan.beats.length });
});

for (const id of PROTOTYPE_IDS) {
  test(`trust check: a keeper, note, template or overlay named ${id} is untrusted`, () => {
    for (const [path, code] of [
      ["/beats/1/keeperId", "untrustedReference"], ["/beats/0/noteId", "untrustedReference"],
      ["/beats/0/templateId", "untrustedReference"], ["/beats/2/overlays/0/refId", "untrustedReference"],
    ] as const) {
      rejects(() => planner.check(profiles, applyPatch(coachPlan, [{ op: "replace", path, value: id }]), plannerBase), code);
    }
  });

  test(`trust check: a profile named ${id} is a profile mismatch`, () => {
    rejects(() => planner.check(profiles, applyPatch(coachPlan, [{ op: "replace", path: "/profile/id", value: id }]),
      plannerBase), "profileMismatch");
  });
}

const compileCase = vectors.compile.cases.find((c: J) => c.id === "coach-cut-3min");
const compileCtx = compileContext(compileCase, compileBases(vectors.compile));
const edl = compileCase.expect.edl;

test("the base EDL validates (so each refusal below is the mutation's)", () => {
  assert.equal(validate(edl, profiles, compileCtx.edl).status, "valid-plan");
});

for (const id of PROTOTYPE_IDS.filter((x) => /^[A-Za-z0-9]/.test(x))) {
  test(`edl.validate: a source, overlay or card text named ${id} is refused`, () => {
    const card = edl.segments.findIndex((s: J) => s.op === "title-card" && s.textRefs.length);
    rejects(() => validate(applyPatch(edl, [{ op: "replace", path: "/segments/1/sourceId", value: id }]), profiles,
      compileCtx.edl), "unknownSource");
    rejects(() => validate(applyPatch(edl, [{ op: "replace", path: `/segments/${card}/textRefs/0`, value: id }]),
      profiles, compileCtx.edl), "untrustedReference");
    rejects(() => validate(applyPatch(edl, [{ op: "replace", path: "/bindings/profileId", value: id }]), profiles,
      compileCtx.edl), "unknownProfile");
  });
}

test("the compiler refuses a request field it does not know, and a trim outside the trusted window", () => {
  const run = (request: J) => compiler.runVector(profiles, {
    op: "compile", input: { plan: deepClone(compileCase.input.plan), request, context: deepClone(compileCtx) },
  });
  assert.deepEqual(run({ ...compileCase.input.request, constructor: 1 }), { rejectCode: "unknownField" });
  assert.deepEqual(run({ ...compileCase.input.request, trims: { b02: { inFrame: 0, outFrame: 10 } } }),
    { rejectCode: "trimOutsideWindow" });
});

test("a plan with a URL or a shell string is never an EDL", () => {
  rejects(() => validate(applyPatch(edl, [{ op: "replace", path: "/planId", value: "https://example.test/x" }]),
    profiles, compileCtx.edl), "forbiddenValue");
  rejects(() => validate(applyPatch(edl, [{ op: "add", path: "/segments/1/command", value: "ffmpeg -i x" }]),
    profiles, compileCtx.edl), "forbiddenField");
});
