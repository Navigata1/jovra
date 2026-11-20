import assert from "node:assert/strict";
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, relative } from "node:path";
import { test } from "node:test";

import { canonicalJson } from "../../src/heuristic/core.ts";
import { applyPatch } from "./fixture-patch.ts";
import { FIXTURES, ROOT, resolvePlanning } from "./vectors.ts";

test("fixture patches cannot write to inherited prototypes", () => {
  const marker = "jovraFixturePatchProbe";
  try {
    assert.throws(() => applyPatch({}, [{ op: "add", path: `/__proto__/${marker}`, value: true }]), /Unsafe patch path/);
  } finally {
    const changed = Object.hasOwn(Object.prototype, marker);
    Reflect.deleteProperty(Object.prototype, marker);
    assert.equal(changed, false, "a fixture patch changed Object.prototype");
  }
});

test("fixture patches reject direct prototype replacement", () => {
  assert.throws(() => applyPatch({}, [{ op: "add", path: "/__proto__", value: { inherited: true } }]), /Unsafe patch path/);
});

test("fixture patches do not traverse inherited properties", () => {
  const marker = "jovraInheritedFixturePatchProbe";
  try {
    assert.throws(() => applyPatch({}, [{ op: "add", path: `/toString/${marker}`, value: true }]), /Unsafe patch path/);
  } finally {
    const changed = Object.hasOwn(Object.prototype.toString, marker);
    Reflect.deleteProperty(Object.prototype.toString, marker);
    assert.equal(changed, false, "a fixture patch wrote to an inherited function");
  }
});

function resolveRecord(fromRecord: string): unknown {
  return resolvePlanning({ op: "check", input: {}, contextPatch: [], fromRecord }, {}, new Map());
}

test("vector records cannot escape the fixture directory", (t) => {
  const outside = mkdtempSync(join(tmpdir(), "jovra-s88-outside-"));
  t.after(() => rmSync(outside, { recursive: true, force: true }));
  const target = join(outside, "record.json");
  writeFileSync(target, '{"outside":true}');
  assert.throws(() => resolveRecord(relative(join(ROOT, FIXTURES), target)), /Unsafe fixture path/);
});

for (const kind of ["file", "directory"] as const) {
  test(`vector records refuse a ${kind} symlink even when it names JSON`, (t) => {
    const outside = mkdtempSync(join(tmpdir(), "jovra-s88-outside-"));
    t.after(() => rmSync(outside, { recursive: true, force: true }));
    const records = mkdtempSync(join(ROOT, FIXTURES, "records", ".s88-fixture-"));
    t.after(() => rmSync(records, { recursive: true, force: true }));
    const target = join(outside, "record.json");
    writeFileSync(target, '{"outside":true}');
    const alias = kind === "file" ? "link.json" : "link";
    symlinkSync(kind === "file" ? target : outside, join(records, alias));
    const path = `records/${basename(records)}/${alias}${kind === "directory" ? "/record.json" : ""}`;
    assert.throws(() => resolveRecord(path), /Unsafe fixture path/);
  });
}

for (const [where, value] of [["value", { text: "\ud800" }], ["key", { "\udc00": "text" }]] as const) {
  test(`Studio canonical bytes refuse a lone UTF-16 surrogate in a ${where}`, () => {
    assert.throws(() => canonicalJson(value), /unpaired Unicode surrogate/);
  });
}

test("Studio canonical bytes retain Python scalar key ordering and valid Unicode", () => {
  assert.equal(canonicalJson({ "\u{10000}": "🎾", "\ue000": "é" }), '{"\ue000":"é","\u{10000}":"🎾"}');
});
