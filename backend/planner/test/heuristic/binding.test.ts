/**
 * The parity check is binding, not vacuous: one keeper window moved in a vector's input changes the output hash, and
 * one stored expectation altered makes the parity runner fail exactly that case.
 */

import assert from "node:assert/strict";
import { test } from "node:test";

import * as compiler from "../../src/heuristic/compile.ts";
import { applyPatch, canonicalSha256, deepClone, type J } from "../../src/heuristic/core.ts";
import * as planner from "../../src/heuristic/planner.ts";
import {
  CONTEXT_CASE, compileBases, compileContext, loadProfiles, loadVectors, resolvePlanning, runCompile, runPlanner,
} from "./vectors.ts";

const profiles = loadProfiles();
const vectors = loadVectors();
const KEEPER = "k-02";
const ONE_SECOND_US = 1_000_000;

function caseOf(doc: J, id: string): J {
  const found = doc.cases.find((c: J) => c.id === id);
  assert.ok(found, `no case ${id}`);
  return found;
}

/** A contextPatch that ends keeper k-02's session window one second earlier. */
function shortenKeeper(context: J): J[] {
  const index = context.keepers.findIndex((k: J) => k.keeperId === KEEPER);
  assert.ok(index >= 0, `the context has no ${KEEPER}`);
  const endUs = context.keepers[index].session.endUs;
  return [{ op: "replace", path: `/keepers/${index}/session/endUs`, value: endUs - ONE_SECOND_US }];
}

test("a planner vector: moving one keeper window changes the output hash and the estimate", () => {
  const doc = vectors.planner;
  const base = caseOf(doc, CONTEXT_CASE).expect.context;
  const c = caseOf(doc, "coach-cut-3min");
  const planned = new Map<string, J>(doc.cases.map((x: J) => [x.id, x]));

  const same = planner.runVector(profiles, resolvePlanning(c, base, planned));
  assert.equal(canonicalSha256(same), canonicalSha256(c.expect));

  const moved = planner.runVector(profiles, resolvePlanning({ ...c, contextPatch: shortenKeeper(base) }, base, planned));
  assert.notEqual(canonicalSha256(moved), canonicalSha256(c.expect));
  assert.equal(moved.estimate.totalMs, c.expect.estimate.totalMs - 1000, "k-02's live beat is one second shorter");
});

test("a compile vector: moving one keeper window changes the EDL's sha256", () => {
  const doc = vectors.compile;
  const c = caseOf(doc, "coach-cut-3min");
  const bases = compileBases(doc);
  const context = compileContext(c, bases);

  const same = compiler.runVector(profiles, { op: "compile", input: { ...deepClone(c.input), context } });
  assert.equal(same.sha256, c.expect.sha256);

  const moved = compiler.runVector(profiles, {
    op: "compile", input: { ...deepClone(c.input), context: applyPatch(context, shortenKeeper(context)) },
  });
  assert.ok(moved.edl, `the shortened keeper still compiles (${JSON.stringify(moved.refusal ?? moved.rejectCode)})`);
  assert.notEqual(moved.sha256, c.expect.sha256);
  assert.ok(moved.edl.output.totalFrames < c.expect.edl.output.totalFrames, "the film is shorter");
});

test("one altered stored vector fails parity for that case only", () => {
  const plannerDoc = deepClone(vectors.planner);
  const victim = caseOf(plannerDoc, "coach-cut-3min");
  victim.expect.estimate.beats[1].ms += 1;
  const failed = runPlanner(profiles, plannerDoc).filter((o) => o.problems.length).map((o) => o.id);
  assert.deepEqual(failed, ["coach-cut-3min"]);

  const compileDoc = deepClone(vectors.compile);
  caseOf(compileDoc, "coach-cut-3min").expect.edl.segments[1].sourceInFrame += 1;
  const compileFailed = runCompile(profiles, compileDoc).filter((o) => o.problems.length).map((o) => o.id);
  assert.deepEqual(compileFailed, ["coach-cut-3min"]);
});
