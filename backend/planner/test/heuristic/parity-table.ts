/**
 * Prints the parity table: every S06 (director, planner) and S07 (compile) reference vector, what the reference
 * produced, the canonical SHA-256 of the stored expectation and of the port's output, and whether they are identical.
 * Exits non-zero when any case differs. Run: npm run parity
 */

import { runAll, summarize } from "./vectors.ts";

const outcomes = runAll();
const lines: string[] = [];
lines.push("| vector file | case | op | reference result | expect sha256 | port sha256 | parity |");
lines.push("|---|---|---|---|---|---|---|");
for (const o of outcomes) {
  const verdict = o.role === "base" ? "base context" : o.problems.length ? `FAIL: ${o.problems.join("; ")}` : "identical";
  lines.push(`| ${o.kind} | ${o.id} | ${o.op} | ${o.result} | ${o.expectSha256.slice(0, 16)} | `
    + `${(o.gotSha256 ?? "-").slice(0, 16)} | ${verdict} |`);
}
lines.push("");
let failed = 0;
let parity = 0;
for (const s of summarize(outcomes)) {
  parity += s.parity;
  failed += s.failed.length;
  lines.push(`${s.kind} (${s.file}): ${s.identical}/${s.parity} byte-identical, plus ${s.base} base context case(s); `
    + `results ${JSON.stringify(s.results)}`);
}
lines.push(`TOTAL: ${parity - failed}/${parity} reference vectors reproduced byte for byte (canonical JSON).`);
process.stdout.write(`${lines.join("\n")}\n`);
process.exitCode = failed ? 1 : 0;
