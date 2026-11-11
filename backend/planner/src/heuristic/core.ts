/**
 * Port of spec/reference/studio/core.py: exact fractions, the one half-up rounding, time <-> frame, integer pct,
 * canonical JSON and its SHA-256 and typed rejections. Plus the few Python semantics the
 * reference relies on and JavaScript does not give for free (deep equality, tuple ordering, floor division).
 *
 * No floating point reaches a decision: times are integer microseconds or exact fractions (BigInt numerator and
 * denominator), and every rounding goes through roundHalfUp.
 */

import { createHash } from "node:crypto";

/**
 * A JSON value from a stored record or a plan. The reference rules below check its shape field by field (strict
 * fields, typed integers, ids that resolve), exactly as the Python reference does, so it is typed loosely here.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type J = any;

export const US_PER_S = 1_000_000;

/** A rule violation with a stable machine code (vectors assert the code, not the message). */
export class Reject extends Error {
  readonly code: string;
  readonly detail: string;

  constructor(code: string, message: string) {
    super(`${code}: ${message}`);
    this.name = "Reject";
    this.code = code;
    this.detail = message;
  }
}

export function require(condition: unknown, code: string, message: string): asserts condition {
  if (!condition) throw new Reject(code, message);
}

// ----- exact fractions ---------------------------------------------------------------------------------------------

export type Num = number | bigint | F;

function big(value: number | bigint): bigint {
  if (typeof value === "bigint") return value;
  if (!Number.isSafeInteger(value)) throw new RangeError(`${value} is not a safe integer`);
  return BigInt(value);
}

function gcd(a: bigint, b: bigint): bigint {
  let x = a < 0n ? -a : a;
  let y = b < 0n ? -b : b;
  while (y !== 0n) [x, y] = [y, x % y];
  return x;
}

function floorDivBig(a: bigint, b: bigint): bigint {
  const q = a / b;
  return (a % b !== 0n && (a < 0n) !== (b < 0n)) ? q - 1n : q;
}

function toSafe(value: bigint): number {
  const n = Number(value);
  if (!Number.isSafeInteger(n)) throw new RangeError(`${value} does not fit a safe integer`);
  return n;
}

/** Python's fractions.Fraction, reduced, with a positive denominator. */
export class F {
  readonly n: bigint;
  readonly d: bigint;

  private constructor(n: bigint, d: bigint) {
    this.n = n;
    this.d = d;
  }

  static of(num: Num, den: Num = 1n): F {
    const a = F.from(num);
    const b = F.from(den);
    if (b.n === 0n) throw new RangeError("Fraction with a zero denominator");
    let n = a.n * b.d;
    let d = a.d * b.n;
    if (d < 0n) {
      n = -n;
      d = -d;
    }
    const g = gcd(n, d) || 1n;
    return new F(n / g, d / g);
  }

  static from(value: Num): F {
    if (value instanceof F) return value;
    return new F(big(value), 1n);
  }

  add(o: Num): F { const b = F.from(o); return F.of(this.n * b.d + b.n * this.d, this.d * b.d); }
  sub(o: Num): F { const b = F.from(o); return F.of(this.n * b.d - b.n * this.d, this.d * b.d); }
  mul(o: Num): F { const b = F.from(o); return F.of(this.n * b.n, this.d * b.d); }
  div(o: Num): F { const b = F.from(o); return F.of(this.n * b.d, this.d * b.n); }
  neg(): F { return new F(-this.n, this.d); }
  abs(): F { return this.n < 0n ? this.neg() : this; }

  cmp(o: Num): number {
    const b = F.from(o);
    const left = this.n * b.d;
    const right = b.n * this.d;
    return left < right ? -1 : left > right ? 1 : 0;
  }

  eq(o: Num): boolean { return this.cmp(o) === 0; }
  lt(o: Num): boolean { return this.cmp(o) < 0; }
  le(o: Num): boolean { return this.cmp(o) <= 0; }
  gt(o: Num): boolean { return this.cmp(o) > 0; }
  ge(o: Num): boolean { return this.cmp(o) >= 0; }

  floor(): number { return toSafe(floorDivBig(this.n, this.d)); }
  ceil(): number { return toSafe(-floorDivBig(-this.n, this.d)); }
  /** Python int(): toward zero. */
  trunc(): number { return toSafe(this.n / this.d); }
  get num(): number { return toSafe(this.n); }
  get den(): number { return toSafe(this.d); }
  isInteger(): boolean { return this.d === 1n; }
  toNumber(): number { return Number(this.n) / Number(this.d); }
  toString(): string { return this.d === 1n ? `${this.n}` : `${this.n}/${this.d}`; }
}

export function minF(values: F[]): F {
  return values.reduce((m, v) => (v.lt(m) ? v : m));
}

// ----- Python integer semantics ------------------------------------------------------------------------------------

/** Python's a // b for integers. */
export function floorDiv(a: number, b: number): number {
  return toSafe(floorDivBig(big(a), big(b)));
}

/** Python's a % b for integers (the sign of b). */
export function pyMod(a: number, b: number): number {
  return a - b * floorDiv(a, b);
}

export function gcdInt(a: number, b: number): number {
  return toSafe(gcd(big(a), big(b)));
}

export function lcm(a: number, b: number): number {
  return a === 0 || b === 0 ? 0 : Math.abs(floorDiv(a, gcdInt(a, b)) * b);
}

/** Python `type(v) is int` (a JSON number with no fraction; booleans are not ints here, as there). */
export function isInt(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value);
}

export function isDict(value: unknown): value is Record<string, J> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Python truthiness of a JSON value. */
export function truthy(value: unknown): boolean {
  if (value === null || value === undefined || value === false || value === 0 || value === "") return false;
  if (Array.isArray(value)) return value.length > 0;
  if (isDict(value)) return Object.keys(value).length > 0;
  return true;
}

/** dict.get(key, default) without reaching the prototype ("constructor" is a key like any other). */
export function own(obj: unknown, key: unknown, fallback: J = undefined): J {
  if (!isDict(obj) || typeof key !== "string") return fallback;
  return Object.hasOwn(obj, key) ? obj[key] : fallback;
}

export function has(obj: unknown, key: unknown): boolean {
  return isDict(obj) && typeof key === "string" && Object.hasOwn(obj, key);
}

/** Python == on JSON values: numbers and booleans compare numerically, dicts by key set, lists element-wise. */
export function pyEq(a: unknown, b: unknown): boolean {
  if (a instanceof F || b instanceof F) {
    const x = a instanceof F ? a : (typeof a === "number" && Number.isInteger(a)) ? F.from(a) : null;
    const y = b instanceof F ? b : (typeof b === "number" && Number.isInteger(b)) ? F.from(b) : null;
    return x !== null && y !== null && x.eq(y);
  }
  const numeric = (v: unknown) => typeof v === "number" || typeof v === "boolean";
  if (numeric(a) && numeric(b)) return Number(a) === Number(b);
  if (a === null || b === null || a === undefined || b === undefined) return a === b;
  if (typeof a === "string" || typeof b === "string") return a === b;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((x, i) => pyEq(x, b[i]));
  }
  if (isDict(a) && isDict(b)) {
    const ka = Object.keys(a);
    if (ka.length !== Object.keys(b).length) return false;
    return ka.every((k) => Object.hasOwn(b, k) && pyEq(a[k], b[k]));
  }
  return false;
}

/** `value in items` with Python equality. */
export function within(value: unknown, items: readonly unknown[]): boolean {
  return items.some((x) => pyEq(value, x));
}

function codePointCompare(a: string, b: string): number {
  const x = Array.from(a);
  const y = Array.from(b);
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    const p = x[i].codePointAt(0)!;
    const q = y[i].codePointAt(0)!;
    if (p !== q) return p < q ? -1 : 1;
  }
  return x.length === y.length ? 0 : x.length < y.length ? -1 : 1;
}

export type SortKey = number | string | boolean | F | null | SortKey[];

/** Python's ordering of sort keys: numbers (and booleans) numerically, strings by code point, tuples element-wise. */
export function pyCompare(a: SortKey, b: SortKey): number {
  if (Array.isArray(a) && Array.isArray(b)) {
    for (let i = 0; i < Math.min(a.length, b.length); i++) {
      const c = pyCompare(a[i], b[i]);
      if (c !== 0) return c;
    }
    return a.length === b.length ? 0 : a.length < b.length ? -1 : 1;
  }
  if (typeof a === "string" && typeof b === "string") return codePointCompare(a, b);
  const num = (v: SortKey) => (v instanceof F ? v : typeof v === "number" || typeof v === "boolean" ? F.from(Number(v)) : null);
  const x = num(a);
  const y = num(b);
  if (x !== null && y !== null) return x.cmp(y);
  throw new TypeError(`'<' not supported between ${typeof a} and ${typeof b}`);
}

/** Python's sorted(items, key=...): stable. */
export function sortedBy<T>(items: Iterable<T>, key: (item: T) => SortKey): T[] {
  return Array.from(items).map((item) => ({ item, k: key(item) }))
    .sort((p, q) => pyCompare(p.k, q.k)).map((p) => p.item);
}

/** sorted() of strings. */
export function sortedStrings(items: Iterable<string>): string[] {
  return Array.from(items).sort(codePointCompare);
}

/** Python str() of a JSON value, where the reference formats one into a test (only its characters matter). */
export function pyStr(value: unknown): string {
  if (value === null || value === undefined) return "None";
  if (value === true) return "True";
  if (value === false) return "False";
  if (typeof value === "string") return value;
  if (typeof value === "number" || value instanceof F) return String(value);
  return JSON.stringify(value);
}

/** Python repr() of a short value for messages. */
export function pyRepr(value: unknown): string {
  if (typeof value === "string") return `'${value}'`;
  return pyStr(value);
}

export function deepClone<T>(value: T): T {
  return value === undefined ? value : structuredClone(value);
}

// ----- rounding and time --------------------------------------------------------------------------------------------

/** floor(value + 1/2) in exact arithmetic. */
export function roundHalfUp(value: Num): number {
  return F.from(value).add(F.of(1, 2)).floor();
}

export interface Rate { num: number; den: number }

export function fpsFraction(fps: Rate): F {
  return F.of(fps.num, fps.den);
}

export function frameDurationUs(fps: Rate): F {
  return F.of(US_PER_S * fps.den, fps.num);
}

/** The one time -> frame rule: frame = floor(t * fps + 1/2). */
export function frameAtUs(timeUs: Num, fps: Rate): number {
  return roundHalfUp(F.from(timeUs).mul(fpsFraction(fps)).div(US_PER_S));
}

export function seconds(frames: number, fps: Rate): F {
  return F.from(frames).div(fpsFraction(fps));
}

export function rateFraction(rate: Rate): F {
  return F.of(rate.num, rate.den);
}

// ----- percentages --------------------------------------------------------------------------------------------------

/** (200n + d) div 2d, half up; d = 0 gives null (display an em dash). */
export function pct(n: number, d: number): number | null {
  if (d === 0) return null;
  return floorDiv(200 * n + d, 2 * d);
}

export function deltaPpDisplay(before: number | null, after: number | null): string {
  if (before === null || after === null) return "—";
  const delta = after - before;
  const unit = Math.abs(delta) === 1 ? "percentage point" : "percentage points";
  return `${delta > 0 ? "+" : ""}${delta} ${unit}`;
}

// ----- canonical JSON and hashing -----------------------------------------------------------------------------------

function canonicalString(value: string, where: string): string {
  // In Unicode mode a valid surrogate pair is one scalar and does not match this range.
  if (/[\uD800-\uDFFF]/u.test(value)) throw new Reject("badUnicode", `${where}: unpaired Unicode surrogate`);
  return JSON.stringify(value);
}

function canonical(value: unknown, where: string): string {
  if (value === null) return "null";
  if (value === true) return "true";
  if (value === false) return "false";
  if (typeof value === "number") {
    if (!Number.isInteger(value)) {
      throw new Reject("floatInContract", `${where}: floating point value ${value}; use integers or rationals`);
    }
    if (!Number.isSafeInteger(value)) throw new Reject("floatInContract", `${where}: ${value} is not an exact integer`);
    return Object.is(value, -0) ? "0" : String(value);
  }
  if (typeof value === "string") return canonicalString(value, where);
  if (Array.isArray(value)) return `[${value.map((v, i) => canonical(v, `${where}[${i}]`)).join(",")}]`;
  if (isDict(value)) {
    const keys = sortedStrings(Object.keys(value));
    return `{${keys.map((k) => `${canonicalString(k, where)}:${canonical(value[k], `${where}.${k}`)}`).join(",")}}`;
  }
  throw new TypeError(`${where}: ${typeof value} is not JSON`);
}

/** Studio reference bytes: Unicode scalar key order, compact UTF-8, safe integers, no lone surrogates. */
export function canonicalJson(value: unknown): string {
  return canonical(value, "$");
}

export function canonicalBytes(value: unknown): Buffer {
  return Buffer.from(canonicalJson(value), "utf8");
}

export function canonicalSha256(value: unknown): string {
  return createHash("sha256").update(canonicalBytes(value)).digest("hex");
}
