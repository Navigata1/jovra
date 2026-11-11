/**
 * Port of the ranking half of spec/reference/studio/keepers.py (`rank`, the per-profile orders, SplitMix64). The
 * planner ranks the keepers the planning context already holds; building candidates from the core fold stays on the
 * device (S37) and is not part of the server copy. Module page: spec/studio/modules/keepers.md.
 */

import { has, isInt, own, require, sortedBy, truthy, type J } from "./core.ts";

const CHOSEN_LABEL = "Examples you chose";

/** The core sample generator's PRNG, so a seeded random selection is the same on every platform. */
export class SplitMix64 {
  private static readonly MASK = (1n << 64n) - 1n;
  private state: bigint;

  constructor(seed: number | bigint) {
    this.state = BigInt(seed) & SplitMix64.MASK;
  }

  next(): bigint {
    const mask = SplitMix64.MASK;
    this.state = (this.state + 0x9E3779B97F4A7C15n) & mask;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & mask;
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & mask;
    return z ^ (z >> 31n);
  }

  shuffled<T>(items: T[]): T[] {
    const out = [...items];
    for (let i = out.length - 1; i > 0; i--) {
      const j = Number(this.next() % BigInt(i + 1));
      [out[i], out[j]] = [out[j], out[i]];
    }
    return out;
  }
}

function int(value: unknown, what: string): number {
  require(isInt(value), "badInput", `${what} must be an integer`);
  return value;
}

export interface RankItem { kind: string; id: string; chapter: string | null }

interface Ranked { order: RankItem[]; label?: string | null; fallback?: string | null; missing?: string[] }

function pressure(k: J): boolean {
  const f = k.facts;
  return truthy(f.breakPoint) || truthy(f.setPoint) || truthy(f.matchPoint);
}

function item(id: string, chapter: string | null = null, kind = "keeper"): RankItem {
  return { kind, id, chapter };
}

function rallyPulse(keepers: J[]): Ranked {
  const eligible = keepers.filter((k) => k.origin === "point" && (pressure(k) || truthy(k.facts.rallyReal)));
  const order = sortedBy(eligible, (k) => [pressure(k) ? 0 : 1,
    -(truthy(k.facts.rallyReal) ? k.facts.rallyLength : 0), k.facts.index]);
  return { order: order.map((k) => item(k.keeperId)) };
}

function coachCut(keepers: J[], options: J): Ranked {
  const reviewed = new Set((own(options, "cues", []) as J[])
    .filter((c) => c.provenance === "reviewed" || c.provenance === "validated").map((c) => c.keeperId));
  const eligible = keepers.filter((k) => reviewed.has(k.keeperId) || truthy(k.lessonClipIds));
  const order = sortedBy(eligible, (k) => [reviewed.has(k.keeperId) ? 0 : 1, k.session.startUs, k.keeperId]);
  return { order: order.map((k) => item(k.keeperId)) };
}

function matchBroadcast(keepers: J[]): Ranked {
  const points = sortedBy(keepers.filter((k) => k.origin === "point"), (k) => k.facts.index);
  return { order: points.map((k) => item(k.keeperId)) };
}

function progressStory(keepers: J[], options: J): Ranked {
  const dates = own(options, "dates", {});
  const dated = sortedBy(keepers.filter((k) => has(dates, k.keeperId)),
    (k) => [dates[k.keeperId], k.session.startUs, k.keeperId]);
  if (!truthy(own(options, "comparable", true))) {
    // no comparable evidence: the film becomes a lesson chronology (story 137)
    const lessons = dated.filter((k) => truthy(k.lessonClipIds));
    return { order: lessons.map((k) => item(k.keeperId)), fallback: "lesson-chronology" };
  }
  const rule = own(options, "selectionRule", null);
  require(["all", "seeded-random", "user-chosen"].includes(rule), "badOptions", `selection rule ${String(rule)}`);
  let picked: J[];
  if (rule === "all") {
    picked = dated;
  } else if (rule === "seeded-random") {
    const count = int(own(options, "count", null), "count");
    require(count > 0 && count <= dated.length, "badOptions", `count ${count} of ${dated.length} dated examples`);
    const chosen = new Set(new SplitMix64(int(own(options, "seed", null), "seed")).shuffled(dated).slice(0, count)
      .map((k) => k.keeperId));
    picked = dated.filter((k) => chosen.has(k.keeperId));
  } else {
    const chosen = own(options, "chosen", []);
    const ids = new Set(dated.map((k) => k.keeperId));
    require(truthy(chosen) && chosen.every((c: J) => ids.has(c)), "unknownKeeper",
      "a chosen example is not a dated keeper");
    const wanted = new Set(chosen);
    picked = dated.filter((k) => wanted.has(k.keeperId));
  }
  return { order: picked.map((k) => item(k.keeperId)), label: rule === "user-chosen" ? CHOSEN_LABEL : null };
}

function courtMemories(keepers: J[], options: J): Ranked {
  const excluded = new Set(own(options, "excluded", []));
  const brolls = (own(options, "brolls", []) as J[]).filter((b) => !excluded.has(b.brollId));
  const moments = sortedBy(keepers.filter((k) => truthy(k.markIds) || truthy(k.lessonClipIds) || pressure(k)),
    (k) => [k.session.startUs, k.keeperId]);
  const order = [
    ...brolls.filter((b) => b.chapter === "arrival").map((b) => item(b.brollId, "arrival", "broll")),
    ...moments.map((k) => item(k.keeperId, "match")),
    ...brolls.filter((b) => b.chapter === "after").map((b) => item(b.brollId, "after", "broll")),
  ];
  const present: [string, boolean][] = [
    ["arrival-broll", brolls.some((b) => b.chapter === "arrival")],
    ["match-moments", moments.length > 0],
    ["after-broll", brolls.some((b) => b.chapter === "after")],
  ];
  return { order, missing: present.filter(([, here]) => !here).map(([name]) => name) };
}

const RANKERS: Record<string, (keepers: J[], options: J) => Ranked> = {
  "rally-pulse": rallyPulse, "coach-cut": coachCut, "match-broadcast": matchBroadcast,
  "progress-story": progressStory, "court-memories": courtMemories,
};

export interface Ranking {
  profileId: string;
  order: RankItem[];
  label: string | null;
  fallback: string | null;
  missing: string[];
}

export function rank(profileId: string, keepers: J[], options: J): Ranking {
  require(has(RANKERS, profileId), "unknownProfile", `profile ${profileId}`);
  const excluded = new Set(own(options, "excluded", []));
  const kept = keepers.filter((k) => !excluded.has(k.keeperId));   // an excluded keeper is never offered
  const got = RANKERS[profileId](kept, options);
  const limit = own(options, "limit", null);
  const order = limit === null ? got.order : got.order.slice(0, int(limit, "limit"));
  return { profileId, order, label: got.label ?? null, fallback: got.fallback ?? null, missing: got.missing ?? [] };
}
