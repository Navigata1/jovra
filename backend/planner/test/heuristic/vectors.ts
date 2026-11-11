/**
 * The parity harness: runs the TypeScript port over the reference vectors in spec/studio/fixtures/vectors and compares
 * every result with the stored Python expectation as canonical JSON bytes.
 *
 * It resolves each case the way the Python checkers do (spec/reference/studio/cases/planner_cases.py `resolve` and
 * compile_cases.py `resolve` / `make_plan`), with one difference stated plainly: the base context is the vector file's
 * own `context` case, not a re-projection of the Sample records. scripts/spec/validate_studio.py already proves that
 * stored context equals today's records, so this harness checks the port, not the records.
 *
 * Besides byte parity, every plan the port produces must pass the port's own plan-step checks (planner.check and the
 * grammar lint), plan twice to the same bytes and leave its input unchanged; every EDL must pass edl.validate, hash to
 * its stored sha256, compile twice to the same bytes, and come from the plan the port's planner makes for `planFrom`.
 */

import { lstatSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import * as compiler from "../../src/heuristic/compile.ts";
import { canonicalJson, canonicalSha256, deepClone, type J } from "../../src/heuristic/core.ts";
import * as director from "../../src/heuristic/director.ts";
import { validate } from "../../src/heuristic/edl.ts";
import * as planner from "../../src/heuristic/planner.ts";
import { applyPatch } from "./fixture-patch.ts";

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "..");
export const FIXTURES = "spec/studio/fixtures";
export const PROFILES_PATH = "spec/studio/contracts/story-profiles.v1.json";
export const VECTOR_FILES = {
  director: `${FIXTURES}/vectors/director.json`,
  planner: `${FIXTURES}/vectors/planner.json`,
  compile: `${FIXTURES}/vectors/compile.json`,
} as const;
export const CONTEXT_CASE = "context-sample-court-day";

export type VectorKind = keyof typeof VECTOR_FILES;

export interface Outcome {
  kind: VectorKind;
  id: string;
  op: string;
  /** "base": a context case (the input every other case patches); "parity": a case the port re-runs. */
  role: "base" | "parity";
  /** What the reference produced: plan, brief, edl, refusal, reject, findings, check, templates or context. */
  result: string;
  expectSha256: string;
  gotSha256: string | null;
  problems: string[];
}

export function loadJson(rel: string): J {
  const parts = rel.split("/");
  const unsafe = () => new Error(`Unsafe fixture path: ${rel}`);
  if (!rel.endsWith(".json") || parts.some((part) => part === "." || part === ".." || !/^[A-Za-z0-9._-]+$/.test(part))) {
    throw unsafe();
  }
  let path = ROOT;
  for (const [index, part] of parts.entries()) {
    path = join(path, part);
    const info = lstatSync(path);
    if (index === parts.length - 1 ? !info.isFile() : !info.isDirectory()) throw unsafe();
  }
  return JSON.parse(readFileSync(path, "utf8"));
}

export function loadProfiles(): Record<string, J> {
  return director.profilesFrom(loadJson(PROFILES_PATH));
}

export function loadVectors(): Record<VectorKind, J> {
  return {
    director: loadJson(VECTOR_FILES.director),
    planner: loadJson(VECTOR_FILES.planner),
    compile: loadJson(VECTOR_FILES.compile),
  };
}

function record(rel: string): J {
  if (typeof rel !== "string" || !rel.startsWith("records/")) throw new Error("Unsafe fixture path: expected a record");
  return loadJson(`${FIXTURES}/${rel}`);
}

function resultKind(value: J): string {
  for (const key of ["edl", "plan", "brief", "refusal", "rejectCode", "findings", "templates", "context"]) {
    if (value !== null && typeof value === "object" && key in value) return key === "rejectCode" ? "reject" : key;
  }
  return "check";
}

function safeSha(value: J): string | null {
  try {
    return canonicalSha256(value);
  } catch {
    return null;
  }
}

/** planner_cases.resolve: the context case patched by contextPatch; a lint or check case's plan from fromCase/fromRecord. */
export function resolvePlanning(c: J, base: J, planned: Map<string, J>): J {
  const input: J = deepClone(c.input);
  if (["plan", "brief", "lint", "check"].includes(c.op)) {
    input.context = c.contextPatch.length ? applyPatch(base, c.contextPatch) : deepClone(base);
  }
  if (c.op === "lint" || c.op === "check") {
    if ("fromRecord" in c) {
      input.plan = record(c.fromRecord);
    } else {
      const source = planned.get(c.fromCase)?.expect;
      if (!source || !("plan" in source)) throw new Error(`fromCase ${c.fromCase} is not a planner case with a plan`);
      input.plan = applyPatch(source.plan, c.planPatch);
    }
  }
  return { op: c.op, input };
}

function baseOutcome(kind: VectorKind, c: J): Outcome {
  return {
    kind, id: c.id, op: c.op, role: "base", result: "context", expectSha256: canonicalSha256(c.expect),
    gotSha256: canonicalSha256(c.expect), problems: [],
  };
}

function compare(kind: VectorKind, c: J, got: J): Outcome {
  const gotSha256 = safeSha(got);
  const expectSha256 = canonicalSha256(c.expect);
  const problems: string[] = [];
  if (gotSha256 === null) {
    problems.push("the port's output is not canonical JSON");
  } else if (canonicalJson(got) !== canonicalJson(c.expect)) {
    problems.push("the port's output differs from the stored reference expectation");
  }
  return { kind, id: c.id, op: c.op, role: "parity", result: resultKind(c.expect), expectSha256, gotSha256, problems };
}

/** The plan-step checks on a plan the port produced: the trust check and the grammar lint must both pass it. */
function planStepProblems(profiles: Record<string, J>, plan: J, context: J): string[] {
  const problems: string[] = [];
  try {
    planner.check(profiles, plan, context);
  } catch (exc) {
    problems.push(`planner.check rejects the port's own plan: ${String(exc)}`);
  }
  const findings = director.lint(profiles, plan, context);
  if (findings.length) problems.push(`the port's own plan breaks its grammar: ${canonicalJson(findings)}`);
  return problems;
}

export function runDirector(profiles: Record<string, J>, doc: J, plannerDoc: J): Outcome[] {
  const base = doc.cases.find((c: J) => c.id === CONTEXT_CASE).expect.context;
  const planned = new Map<string, J>(plannerDoc.cases.map((c: J) => [c.id, c]));
  return doc.cases.map((c: J) => {
    if (c.op === "context") return baseOutcome("director", c);
    const resolved = resolvePlanning(c, base, planned);
    const snapshot = canonicalJson(resolved);
    const out = compare("director", c, director.runVector(profiles, resolved));
    if (canonicalJson(resolved) !== snapshot) out.problems.push("the director changed its input");
    return out;
  });
}

export function runPlanner(profiles: Record<string, J>, doc: J): Outcome[] {
  const base = doc.cases.find((c: J) => c.id === CONTEXT_CASE).expect.context;
  const planned = new Map<string, J>(doc.cases.map((c: J) => [c.id, c]));
  return doc.cases.map((c: J) => {
    if (c.op === "context") return baseOutcome("planner", c);
    const resolved = resolvePlanning(c, base, planned);
    const snapshot = canonicalJson(resolved);
    const got = planner.runVector(profiles, resolved);
    const out = compare("planner", c, got);
    if (canonicalJson(resolved) !== snapshot) out.problems.push("the planner changed its input");
    if (c.op === "plan" && got.plan) {
      const again = planner.runVector(profiles, JSON.parse(snapshot));
      if (canonicalJson(again.plan) !== canonicalJson(got.plan)) {
        out.problems.push("planning the same brief twice gave different canonical JSON");
      }
      out.problems.push(...planStepProblems(profiles, got.plan, resolved.input.context));
    }
    return out;
  });
}

/** compile_cases.make_plan: the port's RulesPlanner on the case's context, or a Sample record; then planPatch. */
export function makePlan(profiles: Record<string, J>, planFrom: J, context: J): J {
  let doc: J;
  if ("record" in planFrom) {
    doc = record(`records/${planFrom.record}.json`);
  } else {
    const briefed = director.brief(profiles, context, planFrom.profileId, planFrom.options);
    const out = planner.plan(profiles, briefed, context);
    if (!("plan" in out)) throw new Error(`the planner did not plan ${canonicalJson(planFrom)}`);
    doc = out.plan;
  }
  return planFrom.planPatch && planFrom.planPatch.length ? applyPatch(doc, planFrom.planPatch) : doc;
}

export function compileBases(doc: J): Map<string, J> {
  return new Map(doc.cases.filter((c: J) => c.op === "context").map((c: J) => [c.id, c.expect.context]));
}

export function compileContext(c: J, bases: Map<string, J>): J {
  const base = bases.get(c.context);
  return c.contextPatch.length ? applyPatch(base, c.contextPatch) : deepClone(base);
}

export function runCompile(profiles: Record<string, J>, doc: J): Outcome[] {
  const bases = compileBases(doc);
  return doc.cases.map((c: J) => {
    if (c.op === "context") return baseOutcome("compile", c);
    const context = compileContext(c, bases);
    const resolved = { op: "compile", input: { ...deepClone(c.input), context } };
    const snapshot = canonicalJson(resolved);
    const got = compiler.runVector(profiles, resolved);
    const out = compare("compile", c, got);
    if (canonicalJson(resolved) !== snapshot) out.problems.push("the compiler changed its input");
    let remade: J = null;
    try {
      remade = makePlan(profiles, c.planFrom, compileContext(c, bases));
    } catch (exc) {
      out.problems.push(`the port cannot make the case's plan: ${String(exc)}`);
    }
    if (remade !== null && canonicalJson(remade) !== canonicalJson(c.input.plan)) {
      out.problems.push("the port's planner does not make the stored plan for planFrom");
    }
    if (got.edl) {
      if (got.sha256 !== canonicalSha256(got.edl)) out.problems.push("sha256 is not the canonical hash of the EDL");
      try {
        validate(got.edl, profiles, context.edl);
      } catch (exc) {
        out.problems.push(`edl.validate rejects the compiled EDL: ${String(exc)}`);
      }
      const again = compiler.runVector(profiles, JSON.parse(snapshot));
      if (canonicalJson(again.edl) !== canonicalJson(got.edl) || again.sha256 !== got.sha256) {
        out.problems.push("compiling the same plan twice gave different canonical JSON");
      }
    }
    return out;
  });
}

export function runAll(): Outcome[] {
  const profiles = loadProfiles();
  const vectors = loadVectors();
  return [
    ...runDirector(profiles, vectors.director, vectors.planner),
    ...runPlanner(profiles, vectors.planner),
    ...runCompile(profiles, vectors.compile),
  ];
}

export interface Summary {
  kind: VectorKind;
  file: string;
  base: number;
  parity: number;
  identical: number;
  failed: string[];
  results: Record<string, number>;
}

export function summarize(outcomes: Outcome[]): Summary[] {
  return (Object.keys(VECTOR_FILES) as VectorKind[]).map((kind) => {
    const mine = outcomes.filter((o) => o.kind === kind);
    const parity = mine.filter((o) => o.role === "parity");
    const results: Record<string, number> = {};
    for (const o of parity) results[o.result] = (results[o.result] ?? 0) + 1;
    return {
      kind, file: VECTOR_FILES[kind], base: mine.length - parity.length, parity: parity.length,
      identical: parity.filter((o) => o.problems.length === 0).length,
      failed: mine.filter((o) => o.problems.length > 0).map((o) => o.id), results,
    };
  });
}
