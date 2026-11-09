/**
 * Port of spec/reference/studio/compile.py: the EDLCompiler. A StoryPlan plus the trusted context -> a
 * jovra.edit-plan/2 that edl.validate accepts. Pure and deterministic: the same plan, context and request give
 * byte-identical canonical JSON and the same sha256. Module page: spec/studio/modules/compile.md.
 *
 * compilePlan(profiles, plan, context, request) -> {edl, sha256, omitted, notInThisBuild, gaps, validation} | {refusal}
 *
 * The compiler never invents material. A beat it cannot make honestly is omitted and listed with its reason; a film
 * whose real material then falls outside the profile range is refused.
 */

import {
  F, Reject, US_PER_S, canonicalSha256, floorDiv, has, isDict, isInt, lcm, minF, own, pyEq, pyMod, require,
  roundHalfUp, sortedBy, sortedStrings, truthy, type J,
} from "./core.ts";
import * as director from "./director.ts";
import { ASPECTS, Source, fpsOf, validate, type Coverage } from "./edl.ts";
import * as planner from "./planner.ts";

const VERSION = "jovra.edit-plan/2";
/** SD6b operation names (the edit-plan/2 fields they map to are listed on the module page). */
export const OPS = ["live", "broll", "replay", "freeze", "card", "transition", "overlay", "grade", "primary-bed",
  "hold-bed", "silence", "alt-bed", "reframe", "music", "narration"];
const S1_OPS = ["live", "broll", "replay", "freeze", "card", "transition", "overlay", "grade", "primary-bed", "hold-bed",
  "silence"];
interface Stage { ops: string[]; gradePresets: string[]; multiAngle: boolean }
export const STAGES: Record<string, Stage> = {
  S1: { ops: S1_OPS, gradePresets: ["none"], multiAngle: false },
  S2: { ops: [...S1_OPS, "alt-bed"], gradePresets: ["none", "warm-court-1"], multiAngle: true },
};
const REQUIRED_OPS = ["live", "silence"];   // a build without these cannot render any film
const TREATMENT_OP: Record<string, string> = {
  live: "live", replay: "replay", freeze: "freeze", "title-card": "card", broll: "broll",
};
const REQUEST_KEYS = ["fps", "width", "height", "planId", "trims", "transitions"];
const CONTEXT_KEYS = ["edl", "media", "stage", "renderer"];
const GAP_TEMPLATE = "card.recording-gap";
const FINAL_TEMPLATE = "card.final-score";
const PROFILE_GRADE: Record<string, string> = { "court-memories": "warm-court-1" };
const CONTACT_PAD_MS = 250;   // contact protection, +/- 0.25 s
const FADE_MS = 20;           // every bed piece fades 20 ms (the minimum at a switching cut)
const LABELS = { replay: "label.replay", freeze: "label.paused" };
const CUT = { type: "cut", frames: 0 };
/** A beat role opens the named chapter; null continues the open one. NEW_EACH roles open a chapter every time. */
const CHAPTERS: Record<string, Record<string, string | null>> = {
  "coach-cut": {
    goal: "chapter.goal", context: "chapter.goal", example: "chapter.example", cue: null, replay: null,
    drill: "chapter.practice", checkpoint: "chapter.practice",
  },
  "match-broadcast": {
    intro: "chapter.intro", point: "chapter.games", replay: null, gap: null, "final-score": "chapter.final",
  },
  "rally-pulse": {},
  "progress-story": {
    goal: "chapter.goal", "early-evidence": "chapter.before", lesson: "chapter.lessons",
    "recent-evidence": "chapter.recent", replay: null, "what-changed": "chapter.what-changed",
    "next-goal": "chapter.next",
  },
  "court-memories": {
    arrival: "chapter.arrival", "match-moment": "chapter.match", highlight: "chapter.match", after: "chapter.after",
    dedication: "chapter.dedication",
  },
};
const NEW_EACH = ["example"];

// ----- small exact helpers ------------------------------------------------------------------------------------------

function framesForMs(ms: number, fps: F): number {
  return roundHalfUp(F.from(ms).mul(fps).div(1000));
}

/** A hold of `ms` on the output clock (half up), kept inside [loMs, hiMs] after rounding. */
function clampFrames(ms: number, loMs: number, hiMs: number, fps: F): number {
  const lo = F.from(loMs).mul(fps).div(1000).ceil();
  const hi = F.from(hiMs).mul(fps).div(1000).floor();
  return Math.min(Math.max(framesForMs(ms, fps), lo), hi);
}

function floorMultiple(n: number, q: number): number {
  return n - pyMod(n, q);
}

/** Whole seconds, half up, as m:ss (h:mm:ss from an hour). */
function labelMmss(us: number): string {
  const total = roundHalfUp(F.of(Math.max(us, 0), US_PER_S));
  const h = floorDiv(total, 3600);
  const rest = total - h * 3600;
  const m = floorDiv(rest, 60);
  const s = rest - m * 60;
  const two = (v: number) => String(v).padStart(2, "0");
  return h ? `${h}:${two(m)}:${two(s)}` : `${m}:${two(s)}`;
}

/** The exact proxy-frame position that shows a session time, or null off the coverage (inverse of sessionUs). */
function position(src: Source, sessionUs: F | number): F | null {
  for (const [lo, hi, start, rate] of src.coverage) {
    if (start === null || rate === null) continue;
    const pos = F.from(sessionUs).sub(start).div(rate.mul(US_PER_S).div(src.fps)).add(lo);
    if (pos.ge(lo) && pos.le(hi)) return pos;
  }
  return null;
}

function intervalIndex(src: Source, lo: number, hi: number): number | null {
  const n = src.coverage.findIndex((c) => c[0] <= lo && hi <= c[1]);
  return n < 0 ? null : n;
}

// ----- context ------------------------------------------------------------------------------------------------------

/** The trusted compile context, checked and indexed once. */
class Ctx {
  readonly profile: J;
  readonly g: J;
  readonly plan: J;
  readonly context: J;
  readonly request: J;
  readonly stage: Stage;
  readonly supported: Set<string>;
  readonly edl: J;
  readonly media: J;
  readonly primaryId: string;
  readonly sources: Map<string, Source>;
  readonly primary: Source;
  readonly keepers: Map<unknown, J>;

  constructor(profiles: Record<string, J>, plan: J, context: J, request: J) {
    require(isDict(context) && CONTEXT_KEYS.every((k) => Object.hasOwn(context, k)), "contextMissing",
      `compile needs the trusted context keys ${CONTEXT_KEYS.join(", ")}`);
    require(has(STAGES, context.stage), "badContext", `unknown stage ${String(context.stage)}`);
    const supported = context.renderer.supportedOps;
    require(Array.isArray(supported) && supported.every((op: J) => OPS.includes(op)), "badContext",
      "the renderer's supported operations are SD6b operation names");
    require(isDict(request) && Object.keys(request).every((k) => REQUEST_KEYS.includes(k)), "unknownField",
      `request keys are ${REQUEST_KEYS.join(", ")}`);
    this.profile = profiles[plan.profile.id];
    this.g = this.profile.grammar;
    this.plan = plan;
    this.context = context;
    this.request = request;
    this.stage = STAGES[context.stage];
    this.supported = new Set(supported);
    this.edl = context.edl;
    this.media = context.media;
    this.primaryId = this.media.primarySourceId;
    require(has(this.edl.sources, this.primaryId), "untrustedSource",
      `the primary ${String(this.primaryId)} is not offered by the trusted manifest and sync map`);
    this.sources = new Map(Object.entries(this.edl.sources).map(([sid, raw]) => [sid, new Source({ ...(raw as J), id: sid })]));
    this.primary = this.sources.get(this.primaryId)!;
    this.keepers = new Map(context.keepers.map((k: J) => [k.keeperId, k]));
    const current = this.edl.current;
    require(Object.keys(plan.bindings).every((k) => pyEq(own(current, k), plan.bindings[k])), "staleRevision",
      "the plan is bound to other revisions than the stored records");
  }

  /** null when the stage enables `op` and the renderer supports it, else the omission reason. */
  available(op: string): string | null {
    if (!this.stage.ops.includes(op)) return "notInThisStage";
    if (!this.supported.has(op)) return "notInThisBuild";
    return null;
  }

  sourceFor(beat: J): string {
    const slot = beat.angle !== null ? beat.angle : this.keepers.get(beat.keeperId).slots[0];
    const sid = own(this.media.slots, slot, null);
    require(has(this.edl.sources, sid), "untrustedSource",
      `${beat.beatId}: the ${slot} angle is not offered for cutting (no reviewed sync)`);
    return sid;
  }

  recordingGap(): boolean {
    return this.primary.coverage.length > 1;
  }
}

// ----- the compiler -------------------------------------------------------------------------------------------------

interface Omitted { beatId: string | null; op: string; reason: string; [extra: string]: J }

interface Entry { beat: J; op: string; sid: string | null; overlays?: J[] }

interface Transition { type: "dissolve" | "dip"; frames: number }

interface Item {
  beat: J;
  op: string;
  role: string;
  overlays: J[];
  sid: string | null;
  n: number;
  template?: string;
  textRefs?: string[];
  sIn?: number;
  sOut?: number;
  speed?: number;
  interval?: number;
  frame?: number;
  of?: Item;
  transition?: Transition;
  id?: string;
  oIn?: number;
  oOut?: number;
}

interface Gap { item: Item; gapUs: number; display: string }

export function compilePlan(profiles: Record<string, J>, plan: J, context: J, request: J): J {
  planner.check(profiles, plan, context);
  require(!director.lint(profiles, plan, context).length, "grammarViolation", "the plan breaks its profile grammar");
  const c = new Ctx(profiles, plan, context, request);
  const missing = REQUIRED_OPS.filter((op) => c.available(op));
  if (missing.length) return refusal("rendererIncomplete", `This build cannot render a film yet (no ${missing.join(", ")}).`);
  const omitted: Omitted[] = [];
  const chosen = choose(c, omitted);
  const output = outputOf(c, chosen);
  if ("refusal" in output) return output;
  const { fps, size } = output;
  const built = build(c, chosen, fps, omitted);
  const gapped = gapCards(c, built, fps);
  if ("refusal" in gapped) return gapped;
  const { items, gaps } = gapped;
  if (!items.some((i) => i.op === "live" || i.op === "broll")) return refusal("noRelevantKeepers", director.NO_KEEPERS);
  const total = items.reduce((sum, i) => sum + i.n, 0);
  const outside = rangeRefusal(c, total, fps);
  if (outside) return { refusal: outside };
  applyTransitions(c, items, omitted);
  const doc = assemble(c, items, fps, size, total, omitted);
  const result = validate(doc, profiles, c.edl);
  return {
    edl: doc, sha256: canonicalSha256(doc), omitted,
    notInThisBuild: sortedStrings(new Set(omitted.filter((o) => o.reason === "notInThisBuild").map((o) => o.op))),
    gaps: gaps.map((g) => ({ segment: g.item.id, gapUs: g.gapUs, display: g.display })),
    validation: {
      status: result.status, segments: result.segments, frames: result.frames,
      durationSeconds: result.durationSeconds, motionEffects: result.motionEffects,
      needsCleanAlternate: result.needsCleanAlternate,
    },
  };
}

function refusal(code: string, message: string): { refusal: { code: string; message: string } } {
  return { refusal: { code, message } };
}

function omit(omitted: Omitted[], beat: J, op: string, reason: string, extra: Record<string, J> = {}): void {
  omitted.push({ beatId: beat ? beat.beatId : null, op, reason, ...extra });
}

/** The beats that can be made at this stage with this renderer, each with its source; the rest are listed. */
function choose(c: Ctx, omitted: Omitted[]): Entry[] {
  const chosen: Entry[] = [];
  const liveKept = new Set<unknown>();
  for (const beat of c.plan.beats) {
    const t = beat.treatment;
    let op = TREATMENT_OP[t];
    const entry: Entry = { beat, op, sid: null };
    if (t === "live" || t === "replay" || t === "freeze") {
      entry.sid = c.sourceFor(beat);
    } else if (t === "broll") {
      const item = own(c.media.brolls, beat.brollId);
      require(item !== undefined && item !== null && has(c.edl.sources, item.sourceId), "untrustedSource",
        `${beat.beatId}: B-roll ${String(beat.brollId)} has no trusted source`);
      entry.sid = item.sourceId;
    }
    let reason = c.available(op);
    if (reason === null && entry.sid !== null && entry.sid !== c.primaryId
      && c.sources.get(entry.sid)!.role === "match" && !c.stage.multiAngle) {
      op = "multi-angle";
      reason = "notInThisStage";
    }
    if (reason === null && t === "replay" && !liveKept.has(beat.keeperId)) reason = "originalOmitted";
    if (reason === null && beat.templateId === FINAL_TEMPLATE && c.recordingGap()) reason = "coverageIncomplete";
    if (reason) {
      omit(omitted, beat, op, reason);
      continue;
    }
    if (t === "live") liveKept.add(beat.keeperId);
    const overlays: J[] = [];
    for (const o of beat.overlays) {
      const stored = own(c.edl.references, o.refId);
      require(stored !== undefined && stored !== null && stored.kind === o.kind, "untrustedReference",
        `${beat.beatId}: overlay ${String(o.refId)} is not a stored ${String(o.kind)}`);
      require(pyEq(stored.eventRevision, c.edl.current.eventRevision), "staleRevision",
        `${beat.beatId}: overlay ${String(o.refId)} was stored at another event revision`);
      const why = c.available("overlay");
      if (why) {
        omit(omitted, beat, "overlay", why, { overlay: `${o.kind}:${o.refId}` });
        continue;
      }
      overlays.push({ kind: o.kind, refId: o.refId, eventRevision: stored.eventRevision, provenance: stored.provenance });
    }
    entry.overlays = overlays;
    chosen.push(entry);
  }
  for (const lane of ["music", "narration"]) {
    if (c.plan[lane] !== null) omit(omitted, null, lane, c.available(lane) || "notInThisStage");
  }
  return chosen;
}

// ----- output clock and size ----------------------------------------------------------------------------------------

function moving(c: Ctx, chosen: Entry[]): string[] {
  return sortedStrings(new Set([...chosen.filter((e) => e.op === "live" || e.op === "replay" || e.op === "broll")
    .map((e) => e.sid as string), c.primaryId]));
}

function fpsLabel(fps: F): string {
  return fps.isInteger() ? String(fps.n) : fps.toNumber().toFixed(2);
}

/** Landscape: the primary's own size when it is 16:9, else the 16:9 frame of its height; portrait turns it. */
function defaultSize(src: Source, aw: number, ah: number): [number, number] {
  let w: number;
  let h: number;
  if (src.width * 9 === src.height * 16) {
    w = src.width;
    h = src.height;
  } else {
    h = src.height - pyMod(src.height, 2);
    w = floorMultiple(floorDiv(h * 16, 9), 2);
  }
  return aw > ah ? [w, h] : [h, w];
}

function fills(src: Source, size: [number, number]): boolean {
  return src.width * size[1] === src.height * size[0];
}

function upscales(src: Source, size: [number, number]): boolean {
  const [ow, oh] = size;
  if (fills(src, size)) return src.height < oh;
  return ow > src.width && oh > src.height;
}

/** The default clock is the primary's capture rate, never above any source the film moves through. */
function outputOf(c: Ctx, chosen: Entry[]): { fps: F; size: [number, number] } | { refusal: J } {
  const used = moving(c, chosen);
  const want = own(c.request, "fps", null);
  let fps: F;
  if (want !== null) {
    fps = fpsOf(want, "requested fps");
    const slow = used.filter((s) => c.sources.get(s)!.fps.lt(fps));
    if (slow.length) {
      const s = c.sources.get(slow[0])!;
      return refusal("fpsAboveSource",
        `A ${fpsLabel(fps)} fps film would repeat frames: ${slow[0]} was recorded at ${fpsLabel(s.fps)} fps.`);
    }
  } else {
    fps = minF([c.primary.fps, ...used.map((s) => c.sources.get(s)!.fps)]);
  }
  const [aw, ah] = ASPECTS[c.plan.aspect];
  const fallback = defaultSize(c.primary, aw, ah);
  const w = own(c.request, "width", null);
  const h = own(c.request, "height", null);
  let size: [number, number];
  if (w === null && h === null) {
    size = fallback;
  } else {
    require(isInt(w) && isInt(h) && w > 0 && h > 0 && w % 2 === 0 && h % 2 === 0 && w * ah === h * aw, "badRequest",
      `${String(w)}x${String(h)} is not an even ${c.plan.aspect} size`);
    size = [w, h];
  }
  const video = sortedStrings(new Set([...chosen.filter((e) => e.sid !== null).map((e) => e.sid as string), c.primaryId]));
  for (const sid of video) {
    const s = c.sources.get(sid)!;
    if (upscales(s, size)) {
      return refusal("upscaleRefused", `A ${size[0]}x${size[1]} film from a ${s.width}x${s.height} recording would `
        + `only enlarge it, which adds no detail. The film can be at most ${fallback[0]}x${fallback[1]}.`);
    }
  }
  return { fps, size };
}

// ----- segments -----------------------------------------------------------------------------------------------------

/** Source frames per output frame. */
function kOf(srcFps: F, speed: F, outFps: F): F {
  return srcFps.mul(speed).div(outFps);
}

/** The most whole output frames whose source span is a whole number of frames and fits in nSrc source frames. */
function snap(nSrc: number, k: F, q: number): number {
  return floorMultiple(F.from(nSrc).div(k).floor(), q);
}

/** The trusted cut window of a keeper on one source: its stored view inside the keeper's session window. */
function keeperWindow(c: Ctx, kid: string, sid: string): [number, number] {
  const view = (own(c.media.views, kid, []) as J[]).find((v) => v.sourceId === sid)?.window;
  require(view !== undefined, "outsideKeeper", `keeper ${kid} has no view on ${sid}`);
  const src = c.sources.get(sid)!;
  const s = c.keepers.get(kid).session;
  const pa = position(src, s.startUs);
  const pb = position(src, s.endUs);
  const a = pa === null ? view.inFrame : Math.max(view.inFrame, roundHalfUp(pa));
  const b = pb === null ? view.outFrame : Math.min(view.outFrame, roundHalfUp(pb));
  require(a < b, "outsideCoverage", `keeper ${kid} has no frames on ${sid}`);
  return [a, b];
}

function trimmed(c: Ctx, beat: J, window: [number, number]): [number, number] {
  const trims = own(c.request, "trims", null);
  const trim = own(trims || {}, beat.beatId, null);
  if (trim === null) return window;
  require(isDict(trim) && Object.keys(trim).length === 2 && has(trim, "inFrame") && has(trim, "outFrame"),
    "badRequest", "a trim is {inFrame, outFrame}");
  require(window[0] <= trim.inFrame && trim.inFrame < trim.outFrame && trim.outFrame <= window[1], "trimOutsideWindow",
    `${beat.beatId}: trim leaves the trusted window [${window.join(", ")}]`);
  return [trim.inFrame, trim.outFrame];
}

function contactsIn(c: Ctx, sid: string, lo: number, hi: number): number[] {
  return (own(c.edl.contacts, sid, []) as number[]).filter((f) => lo <= f && f < hi);
}

/** The frame a pause or replay centres on: the middle stored contact in the window, else the window's middle. */
function anchorOf(c: Ctx, sid: string, lo: number, hi: number): number {
  const found = contactsIn(c, sid, lo, hi);
  return found.length ? found[floorDiv(found.length, 2)] : floorDiv(lo + hi, 2);
}

function covered(src: Source, lo: number, hi: number, beat: J): number {
  const n = intervalIndex(src, lo, hi);
  require(n !== null, "outsideCoverage", `${beat.beatId}: ${src.id} frames ${lo}-${hi} cross a recording gap`);
  return n;
}

function build(c: Ctx, chosen: Entry[], fps: F, omitted: Omitted[]): Item[] {
  const items: Item[] = [];
  const lives = new Map<unknown, Item>();
  const court = courtBedWanted(c);
  const qBed = court ? kOf(c.primary.fps, F.from(1), fps).den : 1;
  for (const e of chosen) {
    const beat = e.beat;
    const op = e.op;
    const item: Item = { beat, op, role: beat.role, overlays: e.overlays!, sid: e.sid, n: 0 };
    if (op === "card") {
      item.n = clampFrames(planner.CARD_MS, c.g.cardMs.min, c.g.cardMs.max, fps);
      item.template = beat.templateId;
      item.textRefs = beat.noteId ? [beat.noteId] : [];
    } else if (op === "live") {
      const src = c.sources.get(e.sid!)!;
      const [a, b] = trimmed(c, beat, keeperWindow(c, beat.keeperId, e.sid!));
      const k = kOf(src.fps, F.from(1), fps);
      const n = snap(b - a, k, lcm(k.den, qBed));
      require(n > 0, "outsideKeeper", `${beat.beatId}: the window is shorter than one output frame`);
      const span = k.mul(n).trunc();
      Object.assign(item, { n, sIn: a, sOut: a + span, speed: 1, interval: covered(src, a, a + span, beat) });
      lives.set(beat.keeperId, item);
    } else if (op === "replay") {
      if (!replay(c, item, lives.get(beat.keeperId)!, fps, omitted)) continue;
    } else if (op === "freeze") {
      const src = c.sources.get(e.sid!)!;
      const [lo, hi] = keeperWindow(c, beat.keeperId, e.sid!);
      const frame = anchorOf(c, e.sid!, lo, hi);
      covered(src, frame, frame + 1, beat);
      item.n = clampFrames(planner.FREEZE_MS, c.g.freezeMs.min, c.g.freezeMs.max, fps);
      item.frame = frame;
    } else {
      const src = c.sources.get(e.sid!)!;
      const w = c.media.brolls[beat.brollId].window;
      let [a, b] = trimmed(c, beat, [w.inFrame, w.outFrame]);
      if (a === w.inFrame && b === w.outFrame) {   // untrimmed: the middle of the item, at most 6 s
        const nSrc = Math.min(b - a, framesForMs(planner.BROLL_MAX_MS, src.fps));
        a += floorDiv(b - a - nSrc, 2);
        b = a + nSrc;
      }
      const k = kOf(src.fps, F.from(1), fps);
      const n = snap(b - a, k, k.den);
      require(n > 0, "outsideBroll", `${beat.beatId}: the B-roll window is shorter than one output frame`);
      const span = k.mul(n).trunc();
      Object.assign(item, { n, sIn: a, sOut: a + span, speed: 1, interval: covered(src, a, a + span, beat) });
    }
    items.push(item);
  }
  return items;
}

/** A labelled slow replay inside the session time its live original showed; false (listed) under the clean-frame rule. */
function replay(c: Ctx, item: Item, live: Item, fps: F, omitted: Omitted[]): boolean {
  const beat = item.beat;
  const src = c.sources.get(item.sid!)!;
  const den = beat.replaySpeedDen;
  const k = kOf(src.fps, F.of(1, den), fps);
  if (k.lt(1)) {
    omit(omitted, beat, "replay", "cleanFrame", { fallback: "originalSpeedFallback" });
    return false;
  }
  const lsrc = c.sources.get(live.sid!)!;
  const lcov: Coverage = lsrc.coverage[live.interval!];
  const l0 = lsrc.sessionUs(live.sIn!, lcov)!;
  const l1 = lsrc.sessionUs(live.sOut!, lcov)!;
  const p0 = position(src, l0);
  const p1 = position(src, l1);
  require(p0 !== null && p1 !== null, "outsideCoverage",
    `${beat.beatId}: ${src.id} does not cover the moment its live original shows`);
  const [v0, v1] = keeperWindow(c, beat.keeperId, item.sid!);
  const lo = Math.max(p0.ceil(), v0);
  const hi = Math.min(p1.floor(), v1);
  let n = snap(hi - lo, k, k.den);
  n = Math.min(n, floorMultiple(F.from(c.g.replayMaxMs).mul(fps).div(1000).floor(), k.den));
  require(n > 0, "outsideKeeper", `${beat.beatId}: no replay window inside the original`);
  const span = k.mul(n).trunc();
  const anchor = anchorOf(c, live.sid!, live.sIn!, live.sOut!);
  const centre = roundHalfUp(position(src, lsrc.sessionUs(anchor)!)!);
  const start = Math.min(Math.max(centre - floorDiv(span, 2), lo), hi - span);
  Object.assign(item, { n, sIn: start, sOut: start + span, speed: den, of: live,
    interval: covered(src, start, start + span, beat) });
  return true;
}

// ----- recording gaps -----------------------------------------------------------------------------------------------

/** Strict-chronology profiles show a recording gap as a card; a gap is never closed up. */
function gapCards(c: Ctx, items: Item[], fps: F): { items: Item[]; gaps: Gap[] } | { refusal: J } {
  if (c.g.chronology !== "strict") return { items, gaps: [] };
  const out: Item[] = [];
  const gaps: Gap[] = [];
  let prev: Item | null = null;
  for (const item of items) {
    if (item.op === "live" && prev !== null && item.sid === prev.sid && item.interval! > prev.interval!) {
      for (let n = prev.interval!; n < item.interval!; n++) {
        if (c.available("card")) {
          return refusal("gapNotShown", "The recording has a gap and this build cannot show it, so the film is not made.");
        }
        const src = c.sources.get(item.sid!)!;
        const end = src.sessionUs(src.coverage[n][1], src.coverage[n])!;
        const gapUs = roundHalfUp(F.from(src.coverage[n + 1][2]!).sub(end));
        const gapCard: Item = {
          beat: null, op: "card", role: "gap", overlays: [], sid: null, template: GAP_TEMPLATE, textRefs: [],
          n: clampFrames(planner.CARD_MS, c.g.cardMs.min, c.g.cardMs.max, fps),
        };
        out.push(gapCard);
        gaps.push({ item: gapCard, gapUs, display: `Recording gap · ${labelMmss(gapUs)}` });
      }
    }
    if (item.op === "live") prev = item;
    out.push(item);
  }
  return { items: out, gaps };
}

function rangeRefusal(c: Ctx, total: number, fps: F): J {
  const lo = c.g.durationSeconds.min;
  const hi = c.g.durationSeconds.max;
  const secondsValue = F.from(total).div(fps);
  const ms = roundHalfUp(secondsValue.mul(1000));
  if (secondsValue.lt(lo)) {
    return {
      code: "belowProfileMinimum", message: `About ${director.estimateLabel(ms)} of real material; ${c.profile.name} `
        + `needs at least ${director.lengthLabel(lo)}. Mark more moments for a longer film.`,
    };
  }
  if (secondsValue.gt(hi)) {
    return {
      code: "aboveProfileMaximum", message: `About ${director.estimateLabel(ms)} of material; ${c.profile.name} films `
        + `are up to ${director.lengthLabel(hi)}.`,
    };
  }
  return null;
}

/** Apply an incoming transition to each shown beat; the EDL validator checks its handles and contact windows. */
function applyTransitions(c: Ctx, items: Item[], omitted: Omitted[]): void {
  const offered = own(c.request, "transitions");
  const wanted = truthy(offered) ? offered : {};
  require(isDict(wanted), "badRequest", "transitions are {beatId: {type, frames}}");
  const shown = new Map<string, number>();
  items.forEach((item, i) => { if (item.beat !== null) shown.set(item.beat.beatId, i); });
  for (const beatId of sortedStrings(Object.keys(wanted))) {
    const tr = wanted[beatId];
    require(isDict(tr) && Object.keys(tr).length === 2 && has(tr, "type") && has(tr, "frames")
      && (tr.type === "dissolve" || tr.type === "dip") && Number.isSafeInteger(tr.frames),
    "badRequest", `${beatId}: a transition is {type: dissolve|dip, frames}`);
    const index = shown.get(beatId);
    if (index === undefined) {
      omit(omitted, { beatId }, "transition", "beatOmitted");
      continue;
    }
    require(index > 0, "badRequest", `${beatId}: the film's first segment starts with a cut`);
    const why = c.available("transition");
    if (why) {
      omit(omitted, { beatId }, "transition", why);
      continue;
    }
    items[index].transition = { type: tr.type, frames: tr.frames };
  }
}

// ----- the document -------------------------------------------------------------------------------------------------

function courtBedWanted(c: Ctx): boolean {
  return c.plan.primaryAudioPolicy === "continuous-primary-court-audio" && c.primary.hasAudio;
}

function assemble(c: Ctx, items: Item[], fps: F, size: [number, number], total: number, omitted: Omitted[]): J {
  let cursor = 0;
  items.forEach((item, i) => {
    item.id = `s${String(i + 1).padStart(2, "0")}`;
    item.oIn = cursor;
    item.oOut = cursor + item.n;
    cursor += item.n;
  });
  const segments = items.map((item) => segmentOf(c, item, size));
  let grade = own(PROFILE_GRADE, c.profile.id, "none");
  if (grade !== "none") {
    const why = (c.stage.gradePresets.includes(grade) ? null : "notInThisStage") || c.available("grade");
    if (why) {
      omit(omitted, null, "grade", why, { preset: grade });
      grade = "none";
    }
  }
  const audio = audioOf(c, items, fps, total, omitted);
  const used = new Set<string>([
    ...segments.filter((s) => Object.hasOwn(s, "sourceId")).map((s) => s.sourceId),
    ...audio.bed.filter((p: J) => p.sourceId).map((p: J) => p.sourceId),
  ]);
  const order = sortedBy(used, (s) => [s !== c.primaryId, c.sources.get(s)!.role !== "match", s]);
  const current = c.edl.current;
  const briefId: string = c.plan.briefId;
  return {
    schemaVersion: VERSION, projectId: c.plan.projectId,
    planId: own(c.request, "planId", null) || `film-${briefId.startsWith("brief-") ? briefId.slice(6) : briefId}`.slice(0, 64),
    planRevision: c.plan.revision, sample: c.plan.sample, cleanAlternate: false,
    bindings: {
      sourceManifestRevision: current.sourceManifestRevision, syncRevision: current.syncRevision,
      eventRevision: current.eventRevision, profileId: c.profile.id, profileRevision: c.profile.revision,
      keeperCatalogRevision: current.keeperCatalogRevision, brollCatalogRevision: current.brollCatalogRevision,
    },
    output: {
      fps: { num: fps.num, den: fps.den }, width: size[0], height: size[1], aspect: c.plan.aspect, totalFrames: total,
      container: "mp4", videoCodec: "h264", audioCodec: "aac", audioSampleRate: 48000,
    },
    grade: { presetId: grade },
    sources: order.map((sid) => ({ id: sid, ...c.edl.sources[sid] })),
    segments, chapters: chaptersOf(c, items), audio,
  };
}

function segmentOf(c: Ctx, item: Item, size: [number, number]): J {
  const head = {
    id: item.id, op: item.op === "card" ? "title-card" : item.op, outputInFrame: item.oIn,
    outputOutFrame: item.oOut, transitionIn: { ...(item.transition ?? CUT) },
  };
  if (item.op === "card") {
    return { ...head, templateId: item.template, textRefs: [...item.textRefs!], overlayRefs: item.overlays };
  }
  const src = c.sources.get(item.sid!)!;
  const framing = { mode: fills(src, size) ? "fill" : "letterbox" };
  if (item.op === "freeze") {
    return {
      ...head, sourceId: item.sid, sourceFrame: item.frame, labelTemplateId: LABELS.freeze, overlayRefs: item.overlays,
      framing,
    };
  }
  const body = {
    ...head, sourceId: item.sid, sourceInFrame: item.sIn, sourceOutFrame: item.sOut,
    speed: { num: 1, den: item.speed },
  };
  if (item.op === "live") {
    const pad = framesForMs(CONTACT_PAD_MS, src.fps);
    const protectedFrames = contactsIn(c, item.sid!, item.sIn!, item.sOut!)
      .map((f) => ({ inFrame: Math.max(item.sIn!, f - pad), outFrame: Math.min(item.sOut!, f + pad + 1) }));
    const session = src.sessionUs(item.sIn!, src.coverage[item.interval!])!;
    return {
      ...body, sessionInUs: roundHalfUp(session), keeperId: item.beat.keeperId, protectedFrames,
      overlayRefs: item.overlays, framing,
    };
  }
  if (item.op === "replay") {
    return { ...body, replayOf: item.of!.id, labelTemplateId: LABELS.replay, overlayRefs: item.overlays, framing };
  }
  return { ...body, brollId: item.beat.brollId, overlayRefs: item.overlays, framing };
}

function chaptersOf(c: Ctx, items: Item[]): J[] {
  const roles = own(CHAPTERS, c.profile.id, {});
  const out: J[] = [];
  const seen = new Map<string, number>();
  let current: string | null = null;
  for (const item of items) {
    const template = own(roles, item.role, null);
    if (template === null || (template === current && !NEW_EACH.includes(item.role))) continue;
    current = template;
    const name = template.startsWith("chapter.") ? template.slice("chapter.".length) : template;
    const count = (seen.get(name) ?? 0) + 1;
    seen.set(name, count);
    out.push({ id: count === 1 ? `ch-${name}` : `ch-${name}-${count}`, outputInFrame: item.oIn, templateId: template });
  }
  if (out.length) out[0].outputInFrame = 0;   // the first chapter starts the film
  return out;
}

// ----- the audio bed ------------------------------------------------------------------------------------------------

interface BedPiece {
  route: string;
  sourceId: string | null;
  sourceInFrame: number | null;
  outputInFrame: number;
  outputOutFrame: number;
  fadeInMs: number;
  fadeOutMs: number;
}

/** One route per output frame. Bed switches use 20 ms fades, or longer fades across a transition. */
function audioOf(c: Ctx, items: Item[], fps: F, total: number, omitted: Omitted[]): J {
  let court = courtBedWanted(c);
  if (court && c.available("primary-bed")) {
    omit(omitted, null, "primary-bed", c.available("primary-bed")!);
    court = false;
  }
  if (court && c.available("hold-bed") && items.some((i) => i.op === "replay" || i.op === "freeze" || i.op === "card")) {
    omit(omitted, null, "hold-bed", c.available("hold-bed")!);
  }
  const pieces: BedPiece[] = [];
  for (const item of items) {
    let piece = court ? courtPiece(c, item, items, pieces, fps) : null;
    if (piece === null && item.op === "broll" && court && !c.available("alt-bed") && c.sources.get(item.sid!)!.hasAudio) {
      piece = pieceOf("alt-bed", item.sid, item.sIn!, item);
    }
    if (piece === null) piece = pieceOf("silence", null, null, item);
    if (piece.route === "silence" && pieces.length && pieces[pieces.length - 1].route === "silence") {
      pieces[pieces.length - 1].outputOutFrame = item.oOut!;
      continue;
    }
    pieces.push(piece);
  }
  for (const item of items) {
    const transition = item.transition;
    // The validator rejects impossible frame spans before it checks audio.
    if (!transition || transition.frames < 2 || transition.frames > total) continue;
    const after = Math.floor(transition.frames / 2);
    const before = transition.frames - after;
    for (const piece of pieces) {
      if (piece.outputOutFrame === item.oIn) piece.fadeOutMs = Math.max(FADE_MS, F.from(before).mul(1000).div(fps).ceil());
      if (piece.outputInFrame === item.oIn) piece.fadeInMs = Math.max(FADE_MS, F.from(after).mul(1000).div(fps).ceil());
    }
  }
  const sounding = pieces.some((p) => p.route !== "silence");
  return { primarySourceId: sounding ? c.primaryId : null, bed: pieces.map((p) => ({ ...p })), narration: null, music: null };
}

function pieceOf(route: string, sid: string | null, sIn: number | null, item: Item): BedPiece {
  return {
    route, sourceId: sid, sourceInFrame: sIn, outputInFrame: item.oIn!, outputOutFrame: item.oOut!, fadeInMs: FADE_MS,
    fadeOutMs: FADE_MS,
  };
}

function courtPiece(c: Ctx, item: Item, items: Item[], pieces: BedPiece[], fps: F): BedPiece | null {
  const p = c.primary;
  const n = F.from(item.n).mul(p.fps).div(fps);
  if (item.op === "live") {
    const src = c.sources.get(item.sid!)!;
    const at = position(p, src.sessionUs(item.sIn!, src.coverage[item.interval!])!);
    if (at !== null && n.isInteger()) {
      const f = roundHalfUp(at);
      if (intervalIndex(p, f, f + n.trunc()) !== null) return pieceOf("primary-bed", c.primaryId, f, item);
    }
    if (!c.available("alt-bed") && src.hasAudio && item.sid !== c.primaryId) {
      return pieceOf("alt-bed", item.sid, item.sIn!, item);
    }
    throw new Reject("noCourtAudio", `${item.beat.beatId}: no reviewed court sound covers this live moment`);
  }
  if (item.op === "broll" || c.available("hold-bed") || !pieces.length || !n.isInteger()) return null;
  const prev = pieces[pieces.length - 1];
  if (prev.route !== "primary-bed" && prev.route !== "hold-bed") return null;
  const start = prev.sourceInFrame! + F.from(prev.outputOutFrame - prev.outputInFrame).mul(p.fps).div(fps).trunc();
  const end = start + n.trunc();
  const cov = intervalIndex(p, start, end);
  if (cov === null) return null;
  const b0 = p.sessionUs(start, p.coverage[cov])!;
  const b1 = p.sessionUs(end, p.coverage[cov])!;
  const shown = lastLiveKeeper(items, item);
  for (const other of items) {
    if (other.op === "live") {
      const src = c.sources.get(other.sid!)!;
      const cv = src.coverage[other.interval!];
      if (src.sessionUs(other.sIn!, cv)!.lt(b1) && b0.lt(src.sessionUs(other.sOut!, cv)!)) return null;
    }
  }
  for (const k of c.keepers.values()) {   // the only play the context knows: another kept point is never dead time
    if (k.keeperId !== shown && b1.gt(k.session.startUs) && b0.lt(k.session.endUs)) return null;
  }
  return pieceOf("hold-bed", c.primaryId, start, item);
}

function lastLiveKeeper(items: Item[], item: Item): unknown {
  let last: unknown = null;
  for (const other of items) {
    if (other === item) return last;
    if (other.op === "live") last = other.beat.keeperId;
  }
  return last;
}

// ----- vectors ------------------------------------------------------------------------------------------------------

/** A compile vector case (op compile) -> its result, or {rejectCode}. */
export function runVector(profiles: Record<string, J>, c: J): J {
  const input = c.input;
  try {
    if (c.op === "compile") return compilePlan(profiles, input.plan, input.context, input.request);
    throw new Reject("badOp", `op ${String(c.op)}`);
  } catch (exc) {
    if (exc instanceof Reject) return { rejectCode: exc.code };
    throw exc;
  }
}
