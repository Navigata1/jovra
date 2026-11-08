/**
 * Port of spec/reference/studio/progress.py: ProgressStoryBuilder.compare. Is a change between two dated scopes of one
 * stat honest to state? Both fractions use the core integer pct; the delta comes from the two displayed integers;
 * a scope pair that is not comparable becomes a chronology and never claims a change. Module page:
 * spec/studio/modules/progress.md.
 */

import { deltaPpDisplay, isDict, isInt, pct, pyEq, require, sortedStrings, type J } from "./core.ts";

const SCOPE_FIELDS = ["date", "sessionIds", "sessionKind", "statDefinitionId", "methodId", "methodVersion",
  "capabilityVersion", "selectionRule", "numerator", "denominator", "provenance"];
const SELECTION_RULES = ["all", "seeded-random", "user-chosen"];
const PROVENANCE = ["manual", "estimated", "reviewed", "validated"];
const AT_LEAST_REVIEWED = ["reviewed", "validated"];
const CHOSEN_LABEL = "Examples you chose";

/** The reasons a comparison is dropped, in the order they are reported. */
export const REASONS = ["statDefinitionChange", "methodChange", "sessionKindChange", "differingSelection",
  "notReviewed", "emptySample"] as const;

function integer(value: unknown, what: string): number {
  require(isInt(value), "badScope", `${what} must be an integer`);
  return value;
}

/**
 * A calendar date as YYYY-MM-DD, or null. The reference uses Python's date.fromisoformat; stored scopes are always
 * YYYY-MM-DD (studio-common `date`), and for that form string order is date order.
 */
function isoDay(value: unknown): string | null {
  if (typeof value !== "string" || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value)) return null;
  const [y, m, d] = value.split("-").map(Number);
  if (y < 1 || m < 1 || m > 12 || d < 1) return null;
  const days = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return d <= days ? value : null;
}

function scopeOf(scope: unknown, side: string): J {
  require(isDict(scope), "badScope", `${side} scope must be an object`);
  const missing = SCOPE_FIELDS.filter((k) => !Object.hasOwn(scope, k));
  const extra = sortedStrings(Object.keys(scope).filter((k) => !SCOPE_FIELDS.includes(k)));
  require(!missing.length && !extra.length, "badScope",
    `${side} scope fields: missing ${missing.join(", ")}, unknown ${extra.join(", ")}`);
  const day = isoDay(scope.date);
  require(day !== null, "badScope", `${side} date ${String(scope.date)} is not YYYY-MM-DD`);
  require(Array.isArray(scope.sessionIds) && scope.sessionIds.length > 0, "badScope", `${side} needs a session`);
  require(SELECTION_RULES.includes(scope.selectionRule), "badScope", `${side} selection rule`);
  require(PROVENANCE.includes(scope.provenance), "badScope", `${side} provenance`);
  const n = integer(scope.numerator, `${side} numerator`);
  const d = integer(scope.denominator, `${side} denominator`);
  require(n >= 0 && n <= d, "badFraction", `${side} fraction ${n} / ${d}`);
  return { ...scope, day };
}

function sideOf(scope: J): J {
  const n = scope.numerator;
  const d = scope.denominator;
  const shown = pct(n, d);
  return {
    date: scope.date, sessionIds: [...scope.sessionIds], numerator: n, denominator: d, pct: shown,
    display: `${n} / ${d} · ${shown === null ? "—" : `${shown}%`}`,
    selectionLabel: scope.selectionRule === "user-chosen" ? CHOSEN_LABEL : null,
  };
}

export function compare(statDefinitionId: J, earlier: J, later: J): J {
  const e = scopeOf(earlier, "earlier");
  const l = scopeOf(later, "later");
  require(e.day < l.day, "notChronological", `earlier ${e.date} is not before later ${l.date}`);
  const found = new Set<string>();
  if (!pyEq(e.statDefinitionId, statDefinitionId) || !pyEq(l.statDefinitionId, statDefinitionId)) {
    found.add("statDefinitionChange");
  }
  if (!pyEq([e.methodId, e.methodVersion, e.capabilityVersion], [l.methodId, l.methodVersion, l.capabilityVersion])) {
    found.add("methodChange");
  }
  if (!pyEq(e.sessionKind, l.sessionKind)) found.add("sessionKindChange");
  if (!pyEq(e.selectionRule, l.selectionRule)) found.add("differingSelection");
  if (!AT_LEAST_REVIEWED.includes(e.provenance) || !AT_LEAST_REVIEWED.includes(l.provenance)) found.add("notReviewed");
  if (e.denominator === 0 || l.denominator === 0) found.add("emptySample");
  const reasons = REASONS.filter((r) => found.has(r));
  const before = sideOf(e);
  const after = sideOf(l);
  const comparable = reasons.length === 0;
  const out: J = {
    statDefinitionId, earlier: before, later: after, comparable, reasons, deltaPercentagePoints: null,
    deltaDisplay: null, summary: null, claim: "chronology",
  };
  if (comparable) {
    const delta = after.pct - before.pct;   // from the displayed integers, never the exact difference
    const display = deltaPpDisplay(before.pct, after.pct);
    out.deltaPercentagePoints = delta;
    out.deltaDisplay = display;
    out.summary = `${before.display} → ${after.display}, ${display}`;
    out.claim = delta ? "change" : "no-change";
  }
  return out;
}
