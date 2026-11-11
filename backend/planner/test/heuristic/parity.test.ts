/**
 * Byte parity with the S06 (director, planner) and S07 (compile) reference vectors: every case the port re-runs must
 * give canonical JSON identical to the stored Python expectation, and pass the extra checks in vectors.ts.
 */

import assert from "node:assert/strict";
import { test } from "node:test";

import { runAll, summarize, type Outcome } from "./vectors.ts";

const outcomes: Outcome[] = runAll();

for (const o of outcomes) {
  test(`${o.kind} ${o.op} ${o.id}`, () => {
    assert.deepEqual(o.problems, [], `${o.kind} ${o.id}: ${o.problems.join("; ")}`);
    if (o.role === "parity") assert.equal(o.gotSha256, o.expectSha256);
  });
}

test("every vector file has cases, and every re-run case is byte-identical", () => {
  const summary = summarize(outcomes);
  for (const s of summary) {
    process.stdout.write(`# ${s.kind}: ${s.identical}/${s.parity} byte-identical (${s.base} base context case(s)) ` +
      `${JSON.stringify(s.results)}\n`);
    assert.ok(s.parity > 0, `${s.file} has no cases`);
    assert.deepEqual(s.failed, []);
    assert.equal(s.identical, s.parity);
  }
  const parity = summary.reduce((n, s) => n + s.parity, 0);
  process.stdout.write(`# total: ${parity} reference vectors reproduced byte for byte\n`);
});
