/**
 * Port of spec/reference/studio/planner.py: the RulesPlanner (contract planner kind `heuristic`, the default and always
 * the fallback, ADR-0016) and the trust check every story plan passes before it is compiled, whichever planner wrote
 * it. Beats name only keeper, B-roll, note, overlay and card-template ids from the context and the card catalog; no
 * beat carries text that reaches the picture (story 157). Module page: spec/studio/modules/planner.md.
 *
 * plan(profiles, briefed, context) -> {plan, estimate, fallback, belowMinimum} | {refusal}
 * check(profiles, plan, context) -> {beats: n}, or a typed Reject
 */

import { Reject, floorDiv, has, own, pyEq, require, sortedBy, truthy, within, type J, type SortKey } from "./core.ts";
import * as director from "./director.ts";
import { fields } from "./edl.ts";
import { rank } from "./keepers.ts";
import * as progress from "./progress.ts";

const BRIEF_FIELDS = "schemaVersion briefId projectId revision sample profile bindings planner feelingKey audience "
  + "durationTargetSeconds aspect primaryAudioPolicy effectIntensity cleanAlternate privacy music narration beats "
  + "comparisons omitted unresolved";
const BEAT_FIELDS = "beatId role treatment keeperId brollId angle replaySpeedDen overlays noteId templateId reasonForReview";
const KEEPER_TREATMENTS = ["live", "replay", "freeze"];
export const CARD_MS = 4000;       // a card's proposed hold, clamped to the profile's cardMs range
export const FREEZE_MS = 2000;     // a freeze's proposed hold, clamped to the profile's freezeMs range
export const BROLL_MAX_MS = 6000;  // Court Memories B-roll shots run 2-6 s (film-engine 6.5)
const MAX_EXAMPLES = 3;            // Coach's Cut shows two or three examples (film-engine 6.1)
const REASON_TEXT: Record<string, string> = {
  statDefinitionChange: "The two sessions count different stats, so they are not compared.",
  methodChange: "The two sessions were counted differently, so they are not compared.",
  sessionKindChange: "One session is a match and one is a practice, so they are not compared.",
  differingSelection: "The examples were chosen differently, so they are not compared.",
  notReviewed: "One side is not reviewed yet, so they are not compared.",
  emptySample: "One session has nothing counted, so they are not compared.",
};
const MISSING_TEXT: Record<string, [string, string]> = {
  "arrival-broll": ["Arrival footage", "No B-roll is marked for the arrival."],
  "after-broll": ["After the match", "No B-roll is marked for after the match."],
  "match-moments": ["Match moments", "No marked, lesson-linked or pressure point is kept."],
};
const BROLL_CHAPTERS: Record<string, [string, string]> = {
  "arrival-broll": ["arrival", "the arrival"], "after-broll": ["after", "after the match"],
};
const NOT_THIS_MATCH = "is not from this match";
const VENUE_HIDDEN = "shows where you played, and the venue is hidden";

export interface Overlay { kind: string; refId: string }

export interface Beat {
  beatId: string | null;
  role: string;
  treatment: string;
  keeperId: string | null;
  brollId: string | null;
  angle: string | null;
  replaySpeedDen: number | null;
  overlays: Overlay[];
  noteId: string | null;
  templateId: string | null;
  reasonForReview: string;
}

interface Group { key: SortKey[]; required: boolean; beats: Beat[]; ms: number }

interface Omission { idea: string; missingEvidence: string }

// ----- plan building helpers ----------------------------------------------------------------------------------------

/** Everything one profile proposes: groups of beats (each atomic), omitted ideas and header changes. */
class Draft {
  readonly profile: J;
  readonly g: J;
  readonly context: J;
  readonly directions: J;
  readonly brief: J;
  readonly keepers: Map<unknown, J>;
  readonly refs: Map<unknown, J>;
  readonly notes: Map<unknown, J>;
  readonly groups: Group[] = [];
  readonly omitted: Omission[] = [];
  readonly comparisons: J[] = [];
  fallback: string | null = null;
  readonly header: Record<string, J> = {};
  finalize: ((beats: Beat[]) => void) | null = null;

  constructor(profile: J, context: J, briefed: J) {
    this.profile = profile;
    this.g = profile.grammar;
    this.context = context;
    this.directions = briefed.directions;
    this.brief = briefed.brief;
    this.keepers = new Map(context.keepers.map((k: J) => [k.keeperId, k]));
    this.refs = new Map(context.references.map((r: J) => [r.refId, r]));
    this.notes = new Map(context.notes.map((n: J) => [n.noteId, n]));
  }

  // durations (ms): the planner's estimate; the compiler binds exact frames
  liveMs(kid: string): number {
    const s = this.keepers.get(kid).session;
    return floorDiv(s.endUs - s.startUs, 1000);
  }

  ms(beat: Beat): number {
    const t = beat.treatment;
    if (t === "live") return this.liveMs(beat.keeperId!);
    if (t === "replay") return Math.min(this.g.replayMaxMs, this.liveMs(beat.keeperId!) * beat.replaySpeedDen!);
    if (t === "freeze") return Math.min(Math.max(FREEZE_MS, this.g.freezeMs.min), this.g.freezeMs.max);
    if (t === "title-card") return Math.min(Math.max(CARD_MS, this.g.cardMs.min), this.g.cardMs.max);
    const broll = this.context.brolls.find((b: J) => pyEq(b.brollId, beat.brollId));
    return Math.min(broll.durationMs, BROLL_MAX_MS);
  }

  allowed(kind: string, refId: unknown): boolean {
    const ref = this.refs.get(refId);
    return ref !== undefined && ref.kind === kind && within(ref.provenance, own(this.g.overlays, kind, []));
  }

  scores(kid: string): Overlay[] {
    return this.keepers.get(kid).eventRefs.filter((e: string) => this.allowed("score", e))
      .map((e: string) => ({ kind: "score", refId: e }));
  }

  /** The first stored note with this use (notes keep context order), or null. */
  note(use: string): string | null {
    return this.context.notes.find((n: J) => n.use === use)?.noteId ?? null;
  }

  primary(kid: string): string {
    return this.keepers.get(kid).slots[0];
  }

  add(key: SortKey[], required: boolean, ...beats: Beat[]): void {
    this.groups.push({ key, required, beats, ms: beats.reduce((sum, b) => sum + this.ms(b), 0) });
  }

  omit(idea: string, missing: string): void {
    this.omitted.push({ idea, missingEvidence: missing });
  }
}

interface BeatOptions {
  keeper?: string | null;
  broll?: string | null;
  angle?: string | null;
  den?: number | null;
  overlays?: readonly Overlay[];
  note?: string | null;
  template?: string | null;
}

function beat(role: string, treatment: string, reason: string, o: BeatOptions = {}): Beat {
  return {
    beatId: null, role, treatment, keeperId: o.keeper ?? null, brollId: o.broll ?? null, angle: o.angle ?? null,
    replaySpeedDen: o.den ?? null, overlays: (o.overlays ?? []).map((x) => ({ ...x })), noteId: o.note ?? null,
    templateId: o.template ?? null, reasonForReview: reason,
  };
}

function card(role: string, template: string, reason: string, note: string | null = null,
  overlays: readonly Overlay[] = []): Beat {
  return beat(role, "title-card", reason, { note, template, overlays });
}

function ranked(d: Draft, options: J): ReturnType<typeof rank> {
  return rank(d.profile.id, d.context.keepers, options);
}

// ----- the five profiles --------------------------------------------------------------------------------------------

function coachCut(d: Draft): void {
  const cues = d.context.cues.filter((c: J) => d.keepers.has(c.keeperId))
    .map((c: J) => ({ cueId: c.cueId, keeperId: c.keeperId, provenance: c.provenance }));
  const reviewed = new Map<string, string>();
  for (const c of sortedBy(cues, (x: J) => x.cueId)) {
    if (director.AT_LEAST_REVIEWED.includes(c.provenance) && d.allowed("cue", c.cueId) && !reviewed.has(c.keeperId)) {
      reviewed.set(c.keeperId, c.cueId);
    }
  }
  const order = ranked(d, { cues }).order.map((i) => i.id);
  const chosen = sortedBy(d.context.keepers.filter((k: J) => k.selection === "manual" && !order.includes(k.keeperId)),
    (k: J) => [k.session.startUs, k.keeperId]);
  const examples: string[] = [...order, ...chosen.map((k: J) => k.keeperId)].slice(0, MAX_EXAMPLES);
  if (reviewed.size) {
    const goal = d.note("goal");
    if (goal) d.add([0], true, card("goal", "card.goal", "The player's goal note opens the film.", goal));
    else d.omit("Goal card", "No goal note is stored.");
  } else {
    d.fallback = "your-examples";
    d.add([0], true, card("context", "card.examples",
      "No reviewed cue: the film shows your examples and gives no instruction."));
  }
  const den = d.g.replaySpeedDens[0];
  examples.forEach((kid, i) => {
    const angle = d.primary(kid);
    const cue = reviewed.get(kid);
    const beats = [beat("example", "live", `${kid} at original speed` + (cue ? `; reviewed cue ${cue}.` : "."),
      { keeper: kid, angle, overlays: d.scores(kid) })];
    if (cue) {
      const notes = d.context.annotations
        .filter((a: J) => a.keeperId === kid && d.allowed("annotation", a.refId)).map((a: J) => a.refId);
      const sortedNotes = sortedBy(notes as string[], (x) => x);
      let replayOverlays: Overlay[];
      if (sortedNotes.length) {
        beats.push(beat("cue", "freeze", `Paused on ${kid} with annotation ${sortedNotes[0]} and cue ${cue}.`, {
          keeper: kid, angle, overlays: [{ kind: "annotation", refId: sortedNotes[0] }, { kind: "cue", refId: cue }],
        }));
        replayOverlays = [];
      } else {
        replayOverlays = [{ kind: "cue", refId: cue }];
      }
      beats.push(beat("replay", "replay", `Labelled replay of ${kid} at 1/${den} speed.`,
        { keeper: kid, angle, den, overlays: replayOverlays }));
    }
    d.add([1, i], i === 0, ...beats);
  });
  if (!examples.length) return;
  if (reviewed.size) {
    const instructions: [string, string, string, string][] = [
      ["drill", "card.drill", "Practice drill", "drill"],
      ["next", "card.next-checkpoint", "Next checkpoint", "checkpoint"],
    ];
    instructions.forEach(([use, template, idea, role], n) => {
      const note = d.note(use);
      if (note) d.add([2, n], true, card(role, template, `The player's ${idea.toLowerCase()} note.`, note));
      else d.omit(idea, `No ${idea.toLowerCase()} note is stored.`);
    });
  } else {
    d.omit("Reviewed cue", "No reviewed cue links to these keepers.");
    d.omit("Practice drill and next checkpoint", "Without a reviewed cue the film gives no instruction.");
  }
}

function matchBroadcast(d: Draft): void {
  const players = d.note("players");
  if (players) d.add([0], true, card("intro", "card.match-intro", "Players as entered open the match.", players));
  else d.omit("Match introduction", "No players note is stored.");
  const order = ranked(d, {}).order.map((i) => i.id);
  const den = d.g.replaySpeedDens[0];
  const replays: [SortKey[], Beat][] = [];
  order.forEach((kid, i) => {
    d.add([1, i, 0], true, beat("point", "live", `${kid} in match order.`,
      { keeper: kid, angle: d.primary(kid), overlays: d.scores(kid) }));
    const slots = d.keepers.get(kid).slots;
    if (slots.length > 1) {
      replays.push([[1, i, 1], beat("replay", "replay", `Replay of ${kid} from the ${slots[1]} angle after the point.`,
        { keeper: kid, angle: slots[1], den })]);
    }
  });
  for (const [key, b] of replays) d.add(key, false, b);
  if (order.length && !replays.length) {
    d.fallback = "one-angle-match";
    d.omit("Replays from another angle", "No second camera covers these points.");
  }
  if (truthy(d.context.pointCoverageComplete)) {
    d.add([2], true, card("final-score", "card.final-score", "Every point is recorded, so the final score shows."));
  } else {
    d.omit("Final score", "The recorded points do not cover the whole match.");
  }
}

function rallyPulse(d: Draft): void {
  const order = ranked(d, {}).order.map((i) => i.id);
  if (truthy(d.directions.musicUnavailable)) {
    d.fallback = "court-sound-highlights";
    d.header.effectIntensity = "low";
    d.omit("Licensed music", `No rights record for ${d.directions.musicUnavailable}.`);
  }
  if (!order.length) return;
  const rally = (kid: string) => beat("build", "live", `${kid}: a whole rally.`,
    { keeper: kid, angle: d.primary(kid), overlays: d.scores(kid) });
  d.add([0, d.keepers.get(order[0]).session.startUs, order[0]], true, rally(order[0]));
  d.add([1], false, card("close", "card.accent", "A quiet static close on court sound."));
  for (const kid of order.slice(1)) d.add([0, d.keepers.get(kid).session.startUs, kid], false, rally(kid));
  const top = order[0];
  d.finalize = (beats: Beat[]) => {
    const rallies = beats.filter((b) => b.treatment === "live");
    rallies.forEach((b, n) => {
      if (n === 0) b.role = "opening";
      else if (n === rallies.length - 1) b.role = "payoff";
      else if (b.keeperId === top) b.role = "key-exchange";
    });
  };
}

function comparisonOf(p: J, got: J): J {
  const side = (scope: J) => ({
    date: scope.date, sessionIds: [...scope.sessionIds], numerator: scope.numerator, denominator: scope.denominator,
    provenance: scope.provenance,
  });
  return {
    comparisonId: `cmp-${p.statDefinitionId}`, statId: p.statId, metricDefinitionId: p.statDefinitionId,
    methodId: p.earlier.methodId, selectionRule: p.earlier.selectionRule, claim: "change",
    before: side(p.earlier), after: side(p.later),
    display: { before: got.earlier.display, after: got.later.display, delta: got.deltaDisplay },
  };
}

function progressStory(d: Draft): void {
  const p = d.context.progress;
  const got = truthy(p) ? progress.compare(p.statDefinitionId, p.earlier, p.later) : null;
  const comparable = Boolean(got && got.comparable);
  const options: J = {
    dates: truthy(p) ? p.dates : {}, selectionRule: truthy(p) ? p.selectionRule : "all", comparable,
  };
  for (const key of ["chosen", "seed", "count"]) {
    if (truthy(p) && has(p, key)) options[key] = p[key];
  }
  const order = ranked(d, options).order.map((i) => i.id);
  const dates = options.dates;
  const goal = d.note("goal");
  const nxt = d.note("next");
  if (goal) d.add([0], true, card("goal", "card.goal", "The dated starting goal.", goal));
  else d.omit("Starting goal", "No goal note is stored.");
  const lessons: [J, string][] = [];
  for (const lesson of sortedBy(d.context.lessons, (x: J) => [x.date, x.lessonId])) {
    const note = lesson.noteIds.find((n: J) => d.notes.has(n) && d.notes.get(n).use === "lesson");
    if (note) lessons.push([lesson, note]);
  }
  const metric: Overlay[] = truthy(p) && d.allowed("metric", p.statId) ? [{ kind: "metric", refId: p.statId }] : [];
  const lessonCard = (lesson: J, note: string) => card("lesson", "card.lesson", `Lesson of ${lesson.date}.`, note);

  if (comparable && order.length) {
    const early = order[0];
    const recent = order[order.length - 1];
    d.add([1], true, beat("early-evidence", "live", `Earliest dated example (${dates[early]}).`,
      { keeper: early, angle: d.primary(early), overlays: metric }));
    if (recent !== early) {
      d.add([3, 0], true, beat("recent-evidence", "live", `Latest dated example (${dates[recent]}).`,
        { keeper: recent, angle: d.primary(recent) }));
    }
    d.add([4], true, card("what-changed", "card.what-changed", "The stored before and after comparison.", null, metric));
    if (nxt) d.add([5], true, card("next-goal", "card.next-goal", "The next practice goal.", nxt));
    for (const [lesson, note] of lessons) {
      if (dates[early] <= lesson.date && lesson.date <= dates[recent]) {
        d.add([2, lesson.date, lesson.lessonId], false, lessonCard(lesson, note));
      }
    }
    const den = d.g.replaySpeedDens[0];
    d.add([3, 1], false, beat("replay", "replay", `Labelled replay of ${recent} at 1/${den} speed.`,
      { keeper: recent, angle: d.primary(recent), den }));
    d.comparisons.push(comparisonOf(p, got));
  } else {
    d.fallback = "lesson-chronology";
    order.forEach((kid, n) => {
      d.add([1, dates[kid], 0, kid], true, beat(n === 0 ? "early-evidence" : "recent-evidence", "live",
        `Dated example (${dates[kid]}).`, { keeper: kid, angle: d.primary(kid) }));
    });
    for (const [lesson, note] of lessons) d.add([1, lesson.date, 1, lesson.lessonId], true, lessonCard(lesson, note));
    if (got) {
      const template = got.reasons.includes("methodChange") ? "card.method-change" : "card.not-compared";
      d.add([4], true, card("what-changed", template, REASON_TEXT[got.reasons[0]]));
      d.omit("Before and after comparison", REASON_TEXT[got.reasons[0]]);
    } else {
      d.omit("Before and after comparison", "No stat is stored for two dated sessions.");
    }
    if (nxt) d.add([5], true, card("next-goal", "card.next-goal", "The next practice goal.", nxt));
  }
  if (!nxt) d.omit("Next practice goal", "No next-goal note is stored.");
}

/** Story 147: why a B-roll chapter is missing when B-roll is marked for it but none can be used. */
function missingBroll(idea: string, brolls: J[]): string | null {
  if (!has(BROLL_CHAPTERS, idea)) return null;
  const [chapter, label] = BROLL_CHAPTERS[idea];
  const marked = brolls.filter((b) => b.chapter === chapter);
  if (!marked.length) return null;
  const causes: [string, boolean][] = [
    [NOT_THIS_MATCH, marked.some((b) => !truthy(b.depictsThisMatch))],
    [VENUE_HIDDEN, marked.some((b) => truthy(b.depictsThisMatch) && truthy(b.revealsLocation))],
  ];
  return `The B-roll marked for ${label} ${causes.filter(([, hit]) => hit).map(([c]) => c).join(", or ")}.`;
}

function courtMemories(d: Draft): void {
  const venue = truthy(d.brief.privacy.venueVisible);
  const usable = d.context.brolls.filter((b: J) => truthy(b.depictsThisMatch) && (venue || !truthy(b.revealsLocation)));
  const got = ranked(d, { brolls: usable.map((b: J) => ({ brollId: b.brollId, chapter: b.chapter })) });
  const caption = d.directions.caption;
  const captionOverlay: Overlay[] = truthy(caption) && d.allowed("note", caption) ? [{ kind: "note", refId: caption }] : [];
  const moments = got.order.filter((i) => i.kind === "keeper").map((i) => i.id);
  const arrival = got.order.filter((i) => i.kind === "broll" && i.chapter === "arrival").map((i) => i.id);
  const after = got.order.filter((i) => i.kind === "broll" && i.chapter === "after").map((i) => i.id);
  arrival.forEach((bid, n) => {
    d.add([0, n], true, beat("arrival", "broll", `B-roll ${bid} for the arrival.`,
      { broll: bid, overlays: n === 0 ? captionOverlay : [] }));
  });
  if (!arrival.length) {
    d.add([0, 0], true, card("arrival", "card.date", "No arrival footage: a date card opens the day.", null,
      captionOverlay));
  }
  if (!usable.length) d.fallback = "one-camera-excerpts";
  for (const idea of got.missing) {
    d.omit(MISSING_TEXT[idea][0], missingBroll(idea, d.context.brolls) || MISSING_TEXT[idea][1]);
  }
  const moment = (kid: string, role: string) => beat(role, "live",
    `${kid}, ` + (role === "highlight" ? "the top-ranked moment." : "a real moment of the day."),
    { keeper: kid, angle: d.primary(kid) });
  moments.forEach((kid, n) => {
    d.add([1, d.keepers.get(kid).session.startUs, kid], n === 0, moment(kid, n === 0 ? "highlight" : "match-moment"));
  });
  after.forEach((bid, n) => {
    d.add([2, n], true, beat("after", "broll", `B-roll ${bid} for after the match.`, { broll: bid }));
  });
  const chosen = sortedBy(d.context.keepers.filter((k: J) => k.selection === "manual" && !moments.includes(k.keeperId)),
    (k: J) => [k.session.startUs, k.keeperId]);
  for (const k of chosen) d.add([1, k.session.startUs, k.keeperId], false, moment(k.keeperId, "match-moment"));
  if (truthy(d.directions.dedication)) {
    d.add([3], true, card("dedication", "card.dedication", "The player's dedication.", d.directions.dedication));
  }
}

const PROFILE_PLANNERS: Record<string, (d: Draft) => void> = {
  "coach-cut": coachCut, "match-broadcast": matchBroadcast, "rally-pulse": rallyPulse,
  "progress-story": progressStory, "court-memories": courtMemories,
};

// ----- fill, number, finish -----------------------------------------------------------------------------------------

/**
 * Required groups always; optional groups in priority order while the estimate stays within the target; then, only if
 * the estimate is under the profile minimum, more optional groups while it stays within the profile maximum. Real
 * material only: nothing is repeated or stretched to fill time.
 */
export function fill(groups: Group[], targetMs: number, minMs: number, maxMs: number): Group[] {
  const chosen = groups.filter((g) => g.required);
  let total = chosen.reduce((sum, g) => sum + g.ms, 0);
  const optional = groups.filter((g) => !g.required);
  for (const g of optional) {
    if (total + g.ms <= targetMs) {
      chosen.push(g);
      total += g.ms;
    }
  }
  for (const g of optional) {
    if (total >= minMs) break;
    if (!chosen.some((c) => pyEq(c, g)) && total + g.ms <= maxMs) {
      chosen.push(g);
      total += g.ms;
    }
  }
  return sortedBy(chosen, (g) => g.key);
}

export interface PlanResult {
  plan: J;
  estimate: { totalMs: number; beats: { beatId: string; ms: number }[] };
  fallback: string | null;
  belowMinimum: boolean;
}

export function plan(profiles: Record<string, J>, briefed: J, context: J): PlanResult | { refusal: J } {
  if (has(briefed, "refusal")) return { refusal: { ...briefed.refusal } };
  const brief = briefed.brief;
  const profile = profiles[brief.profile.id];
  require(!director.lint(profiles, brief, context).length, "grammarViolation", "the brief breaks its profile grammar");
  if (!truthy(context.keepers)) return { refusal: { code: "noKeepers", message: director.NO_KEEPERS } };
  const d = new Draft(profile, context, briefed);
  PROFILE_PLANNERS[profile.id](d);
  const g = profile.grammar.durationSeconds;
  const targetMs = brief.durationTargetSeconds * 1000;
  const chosen = fill(d.groups, targetMs, g.min * 1000, g.max * 1000);
  const beats: Beat[] = chosen.flatMap((grp) => grp.beats.map((b) => ({ ...b, overlays: b.overlays.map((o) => ({ ...o })) })));
  if (!beats.some((b) => b.treatment === "live" || b.treatment === "broll")) {
    return { refusal: { code: "noRelevantKeepers", message: director.NO_KEEPERS } };
  }
  if (d.finalize) d.finalize(beats);
  const perBeat = beats.map((b, n) => {
    b.beatId = `b${String(n + 1).padStart(2, "0")}`;
    return { beatId: b.beatId, ms: d.ms(b) };
  });
  const total = perBeat.reduce((sum, x) => sum + x.ms, 0);
  const unresolved: string[] = [];
  const below = total < g.min * 1000;
  if (below) {
    unresolved.push(`About ${director.estimateLabel(total)} of real material; ${profile.name} needs at least `
      + `${director.lengthLabel(g.min)}. Mark more moments for a longer film.`);
  } else if (total < targetMs) {
    unresolved.push(`About ${director.estimateLabel(total)} of real material, so this film is shorter than `
      + `${director.lengthLabel(brief.durationTargetSeconds)}. Nothing is padded.`);
  }
  const doc = {
    ...brief, ...d.header, beats, comparisons: d.comparisons, omitted: d.omitted, unresolved,
    bindings: { ...brief.bindings }, profile: { ...brief.profile }, planner: { ...brief.planner },
    privacy: { ...brief.privacy },
  };
  check(profiles, doc, context);
  const findings = director.lint(profiles, doc, context);
  require(!findings.length, "grammarViolation", "the planner broke its own grammar");
  return { plan: doc, estimate: { totalMs: total, beats: perBeat }, fallback: d.fallback, belowMinimum: below };
}

// ----- trust check --------------------------------------------------------------------------------------------------

function checkBeat(b: J, label: string, keepers: Map<unknown, J>, brolls: Map<unknown, J>, notes: Map<unknown, J>,
  refs: Map<unknown, J>): void {
  fields(b, BEAT_FIELDS, label);
  const t = b.treatment;
  if (within(t, KEEPER_TREATMENTS)) {
    require(b.keeperId !== null && b.brollId === null && b.templateId === null && b.noteId === null,
      "treatmentMismatch", `${label}: a ${t} beat names one keeper only`);
    const k = keepers.get(b.keeperId);
    require(k !== undefined, "untrustedReference", `${label}: keeper ${String(b.keeperId)} is not in the catalog`);
    require(b.angle === null || within(b.angle, k.slots), "untrustedReference",
      `${label}: ${String(b.keeperId)} has no view from ${String(b.angle)}`);
  } else if (t === "broll") {
    require(b.brollId !== null && b.keeperId === null && b.templateId === null && b.noteId === null
      && b.angle === null, "treatmentMismatch", `${label}: a B-roll beat names one B-roll item only`);
    require(brolls.has(b.brollId), "untrustedReference", `${label}: B-roll ${String(b.brollId)} is not in the catalog`);
  } else if (t === "title-card") {
    require(b.templateId !== null && b.keeperId === null && b.brollId === null && b.angle === null
      && b.replaySpeedDen === null, "treatmentMismatch", `${label}: a card names a template and at most a note`);
    const tmpl = director.cardTemplate(b.templateId);
    require(tmpl !== undefined, "untrustedReference", `${label}: ${String(b.templateId)} is not a catalog card`);
    if (tmpl.note === null) {
      require(b.noteId === null, "badTemplateSlot", `${label}: ${b.templateId} takes no note`);
    } else {
      require(b.noteId !== null, "badTemplateSlot", `${label}: ${b.templateId} needs a note`);
      const note = notes.get(b.noteId);
      require(note !== undefined, "untrustedReference", `${label}: note ${String(b.noteId)} is not stored`);
      require(note.use === tmpl.note, "badTemplateSlot",
        `${label}: ${b.templateId} needs a ${tmpl.note} note, not a ${note.use} note`);
    }
  } else {
    throw new Reject("treatmentMismatch", `${label}: treatment ${String(t)}`);
  }
  for (const o of b.overlays) {
    fields(o, "kind refId", `${label} overlay`);
    const ref = refs.get(o.refId);
    require(ref !== undefined && pyEq(ref.kind, o.kind), "untrustedReference",
      `${label}: overlay ${String(o.refId)} is not a stored ${String(o.kind)}`);
  }
}

export function check(profiles: Record<string, J>, planDoc: J, context: J): { beats: number } {
  fields(planDoc, BRIEF_FIELDS, "story plan");
  require(planDoc.schemaVersion === "jovra.story-brief/1", "badVersion", "not a jovra.story-brief/1");
  require(pyEq(planDoc.projectId, context.projectId), "projectMismatch", "plan of another project");
  require(pyEq(planDoc.bindings, context.bindings), "staleRevision", "plan bound to other revisions");
  const profile = own(profiles, planDoc.profile.id);
  require(profile !== undefined && pyEq(planDoc.profile.revision, profile.revision), "profileMismatch",
    "unknown profile or revision");
  const keepers = new Map<unknown, J>(context.keepers.map((k: J) => [k.keeperId, k]));
  const brolls = new Map<unknown, J>(context.brolls.map((b: J) => [b.brollId, b]));
  const notes = new Map<unknown, J>(context.notes.map((n: J) => [n.noteId, n]));
  const refs = new Map<unknown, J>(context.references.map((r: J) => [r.refId, r]));
  const ids = planDoc.beats.map((b: J) => own(b, "beatId", null));
  require(new Set(ids).size === ids.length, "duplicateId", "beat ids must be unique");
  planDoc.beats.forEach((b: J, n: number) => checkBeat(b, `beat ${n}`, keepers, brolls, notes, refs));
  const music = planDoc.music;
  require(music === null || context.rights.some((r: J) => pyEq(r.rightsRecordId, music.rightsRecordId)
    && pyEq(r.assetId, music.assetId)), "untrustedReference", "music without its rights record");
  const narration = planDoc.narration;
  require(narration === null || context.consents.some((c: J) => pyEq(c.consentRecordId, narration.consentRecordId)),
    "untrustedReference", "narration without its consent record");
  for (const c of planDoc.comparisons) {
    const ref = refs.get(c.statId);
    require(ref !== undefined && ref.kind === "metric", "untrustedReference", `comparison stat ${String(c.statId)}`);
  }
  checkComparisons(planDoc.comparisons, context);
  return { beats: planDoc.beats.length };
}

/**
 * Stories 146 and 157: the only comparison a plan may carry is the one progress.compare derives from the context's
 * stored progress, field for field (its comparisonId is a label and may differ).
 */
function checkComparisons(comparisons: J[], context: J): void {
  if (!comparisons.length) return;
  const p = context.progress;
  require(p !== null, "untrustedReference", "a comparison, but no progress is stored for two dated sessions");
  let got: J;
  try {
    got = progress.compare(p.statDefinitionId, p.earlier, p.later);
  } catch (exc) {
    if (exc instanceof Reject) {
      throw new Reject("untrustedReference", `a comparison from stored progress that does not compare (${exc.code})`);
    }
    throw exc;
  }
  require(got.comparable, "untrustedReference",
    `a comparison the stored progress does not allow (${got.reasons.join(", ")})`);
  const derived = comparisonOf(p, got);
  require(comparisons.length === 1, "untrustedReference", "one stored progress gives one comparison");
  fields(comparisons[0], Object.keys(derived).join(" "), "comparison");
  const strip = (c: J) => Object.fromEntries(Object.entries(c).filter(([k]) => k !== "comparisonId"));
  require(pyEq(strip(comparisons[0]), strip(derived)), "untrustedReference",
    "a comparison that differs from the one derived from the stored progress");
}

// ----- vectors ------------------------------------------------------------------------------------------------------

/** A planner vector case (op plan or check) -> its result, or {rejectCode}. */
export function runVector(profiles: Record<string, J>, c: J): J {
  const input = c.input;
  try {
    if (c.op === "plan") {
      const briefed = director.brief(profiles, input.context, input.profileId, input.options);
      const out = plan(profiles, briefed, input.context);
      return { ...out, directions: own(briefed, "directions", null) };
    }
    if (c.op === "check") return check(profiles, input.plan, input.context);
    throw new Reject("badOp", `op ${String(c.op)}`);
  } catch (exc) {
    if (exc instanceof Reject) return { rejectCode: exc.code };
    throw exc;
  }
}

