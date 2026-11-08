/**
 * Port of spec/reference/studio/director.py: StoryDirector (the story-brief header for one profile and the player's
 * options), the card text catalog and the grammar lint. Module page: spec/studio/modules/planner.md.
 *
 * brief(profiles, context, profileId, options) -> {brief, directions} | {refusal}
 * lint(profiles, plan, context) -> grammarViolation findings (an empty list passes)
 */

import {
  F, Reject, floorDiv, has, isDict, own, pyEq, pyStr, require, roundHalfUp, sortedStrings, truthy, within, type J,
} from "./core.ts";

export const LENGTHS: Record<string, number> = { "3min": 180, "5min": 300 };
export const LENGTH_KEYS = ["3min", "5min", "full"] as const;
const OPTION_KEYS = ["length", "aspect", "effects", "shake", "keepFullRallies", "caption", "dedication", "venueVisible",
  "blurBystanders", "audience", "music", "narration"];
const ASPECTS = ["16:9", "9:16"];
const EFFECTS: Record<string, string> = { subtle: "low", medium: "medium" };
const AUDIENCES = ["self", "coach", "family", "private-share"];
const FEELING: Record<string, string> = {
  "coach-cut": "feeling.next-action", "match-broadcast": "feeling.relive-match",
  "rally-pulse": "feeling.worth-keeping", "progress-story": "feeling.growing-game",
  "court-memories": "feeling.day-mattered",
};
const DEFAULT_AUDIENCE: Record<string, string> = { "court-memories": "family" };
const CLEAN_ALTERNATE = ["rally-pulse", "court-memories"];   // motion-forward profiles render a Reduce Motion version
const EFFECT_OPTION_PROFILES = ["rally-pulse"];              // only Rally Pulse offers an effects choice
const WIDE_ANGLE_PROFILES = ["match-broadcast"];             // live play stays on the selected wide angle
export const PLANNER = { kind: "heuristic", modelId: null, adapterVersion: "jovra-planner@0.1.0" } as const;
export const NO_KEEPERS = "Mark a few moments first";
export const AT_LEAST_REVIEWED = ["reviewed", "validated"];

export interface CardTemplate {
  profiles: string[];
  note: string | null;
  slots: string[];
  text?: string;
}

/** The card text catalog (story 157): a template id and at most one stored note; code fills every other slot. */
export const CARD_TEMPLATES: Record<string, CardTemplate> = {
  "card.goal": { profiles: ["coach-cut", "progress-story"], note: "goal", slots: ["note", "date"] },
  "card.examples": { profiles: ["coach-cut"], note: null, slots: [], text: "Your examples" },
  "card.drill": { profiles: ["coach-cut"], note: "drill", slots: ["note"] },
  "card.next-checkpoint": { profiles: ["coach-cut"], note: "next", slots: ["note"] },
  "card.match-intro": { profiles: ["match-broadcast"], note: "players", slots: ["note", "date", "format"] },
  "card.final-score": { profiles: ["match-broadcast"], note: null, slots: ["score"] },
  "card.accent": { profiles: ["rally-pulse"], note: null, slots: ["date"] },
  "card.lesson": { profiles: ["progress-story"], note: "lesson", slots: ["note", "date"] },
  "card.what-changed": { profiles: ["progress-story"], note: null, slots: ["comparison"] },
  "card.method-change": {
    profiles: ["progress-story"], note: null, slots: ["dates"],
    text: "These sessions were counted differently, so they are not compared.",
  },
  "card.not-compared": { profiles: ["progress-story"], note: null, slots: ["dates", "reason"] },
  "card.next-goal": { profiles: ["progress-story"], note: "next", slots: ["note"] },
  "card.date": { profiles: ["court-memories"], note: null, slots: ["date"] },
  "card.dedication": { profiles: ["court-memories"], note: "dedication", slots: ["note"] },
};
export const INSTRUCTION_TEMPLATES = ["card.drill", "card.next-checkpoint"];   // Coach's Cut cards that instruct

export function cardTemplate(id: unknown): CardTemplate | undefined {
  return own(CARD_TEMPLATES, id);
}

/** {profileId: profile} from spec/studio/contracts/story-profiles.v1.json. */
export function profilesFrom(catalog: J): Record<string, J> {
  return Object.fromEntries(catalog.profiles.map((p: J) => [p.id, p]));
}

// ----- copy helpers -------------------------------------------------------------------------------------------------

/** 180 -> "3 min", 200 -> "3 min 20 s". */
export function lengthLabel(secondsValue: number): string {
  const m = floorDiv(secondsValue, 60);
  const s = secondsValue - m * 60;
  return s === 0 ? `${m} min` : `${m} min ${s} s`;
}

/** An estimate in whole seconds, rounded half up: 184500 -> "3 min 5 s". */
export function estimateLabel(ms: number): string {
  return lengthLabel(roundHalfUp(F.of(ms, 1000)));
}

function profileOf(profiles: Record<string, J>, profileId: unknown): J {
  require(has(profiles, profileId), "unknownProfile", `profile ${pyStr(profileId)}`);
  return profiles[profileId as string];
}

// ----- options ------------------------------------------------------------------------------------------------------

function noteOf(context: J, noteId: unknown, use: string, what: string): unknown {
  if (noteId === null || noteId === undefined) return null;
  const note = context.notes.find((n: J) => pyEq(n.noteId, noteId));
  require(note !== undefined && note.use === use, "untrustedReference",
    `${what} ${pyStr(noteId)} is not a stored ${use} note`);
  return noteId;
}

function bool(options: J, key: string, fallback: boolean): boolean {
  const value = own(options, key, fallback);
  require(typeof value === "boolean", "badOptions", `${key} must be true or false`);
  return value;
}

/** The player's choices, checked against the profile; a choice the profile does not offer is refused. */
export function resolveOptions(profile: J, context: J, options: J): J {
  require(isDict(options), "badOptions", "options must be an object");
  const extra = sortedStrings(Object.keys(options).filter((k) => !OPTION_KEYS.includes(k)));
  require(!extra.length, "unknownField", `unknown option(s) ${extra.join(", ")}`);
  const pid = profile.id;
  const g = profile.grammar;
  const aspect = own(options, "aspect", "16:9");
  require(within(aspect, ASPECTS), "badOptions", `aspect ${pyStr(aspect)}`);
  const effects = own(options, "effects", "subtle");
  require(within(effects, ["subtle", "medium", "high"]), "badOptions", `effects ${pyStr(effects)}`);
  require(effects === "subtle" || EFFECT_OPTION_PROFILES.includes(pid), "optionUnavailable",
    `${profile.name} has no effects choice`);
  require(effects !== "high", "optionUnavailable", "High effects are not available yet");
  require(!bool(options, "shake", false), "optionUnavailable", "shake stays off in this version");
  require(bool(options, "keepFullRallies", true), "optionUnavailable", "rallies are always kept whole");
  const audience = own(options, "audience", own(DEFAULT_AUDIENCE, pid, "self"));
  require(within(audience, AUDIENCES), "badOptions", `audience ${pyStr(audience)}`);
  const length = own(options, "length", null);
  require(length === null || within(length, LENGTH_KEYS), "badOptions", `length ${pyStr(length)}`);
  const music = own(options, "music", null);
  let musicDoc: J = null;
  let musicUnavailable: J = null;
  if (music !== null) {
    require(isDict(music) && Object.keys(music).length === 1 && has(music, "assetId"), "badOptions",
      "music is {assetId}");
    require(truthy(g.music), "optionUnavailable", `${profile.name} uses court sound only`);
    const rights = context.rights.find((r: J) => pyEq(r.assetId, music.assetId));
    if (rights === undefined) {
      musicUnavailable = music.assetId;   // never played without a rights record: court sound instead
    } else {
      musicDoc = { assetId: music.assetId, rightsRecordId: rights.rightsRecordId };
    }
  }
  let narration = own(options, "narration", null);
  if (narration !== null) {
    require(isDict(narration) && Object.keys(narration).length === 2 && has(narration, "voice")
      && has(narration, "consentRecordId") && within(narration.voice, ["user-recorded", "generated"]), "badOptions",
    "narration is {voice, consentRecordId}");
    require(truthy(g.narration), "optionUnavailable", `${profile.name} has no narration`);
    const consentId = narration.consentRecordId;
    const consent = context.consents.find((c: J) => pyEq(c.consentRecordId, consentId));
    require(consent !== undefined && truthy(consent.granted) && within("narration-voice", consent.scope), "noConsent",
      "narration needs a granted voice consent");
    narration = { voice: narration.voice, consentRecordId: narration.consentRecordId };
  }
  const effectIntensity = EFFECTS[effects as string];
  const caption = noteOf(context, own(options, "caption", null), "caption", "caption");
  const dedication = noteOf(context, own(options, "dedication", null), "dedication", "dedication");
  const venueVisible = bool(options, "venueVisible", false);
  const blurBystanders = bool(options, "blurBystanders", false);
  return {
    length, aspect, effectIntensity, audience, caption, dedication, venueVisible, blurBystanders,
    music: musicDoc, musicUnavailable, narration,
  };
}

function lengthRefusal(profile: J, secondsValue: number, coverage: number): string | null {
  const lo = profile.grammar.durationSeconds.min;
  const hi = profile.grammar.durationSeconds.max;
  if (secondsValue < lo) return `${profile.name} needs at least ${lengthLabel(lo)}.`;
  if (secondsValue > hi) return `${profile.name} films are up to ${lengthLabel(hi)}.`;
  if (secondsValue > coverage) return `The recording is shorter than ${lengthLabel(secondsValue)}.`;
  return null;
}

/** [seconds, null] or [null, refusal message] for 3min, 5min or full. */
export function targetSeconds(profile: J, length: string, coverage: number): [number | null, string | null] {
  const hi = profile.grammar.durationSeconds.max;
  const secondsValue = length === "full" ? Math.min(hi, coverage) : LENGTHS[length];
  const refusal = lengthRefusal(profile, secondsValue, coverage);
  return refusal ? [null, refusal] : [secondsValue, null];
}

/** 5 min when the profile allows it (ST29), else 3 min, else Full. */
export function defaultLength(profile: J, coverage: number): string {
  for (const key of ["5min", "3min"]) {
    if (targetSeconds(profile, key, coverage)[1] === null) return key;
  }
  return "full";
}

// ----- brief --------------------------------------------------------------------------------------------------------

export function brief(profiles: Record<string, J>, context: J, profileId: unknown, options: J): J {
  const profile = profileOf(profiles, profileId);
  const opts = resolveOptions(profile, context, options);
  if (!truthy(context.keepers)) return { refusal: { code: "noKeepers", message: NO_KEEPERS } };
  const coverage = context.coverageSeconds;
  const length = opts.length ?? defaultLength(profile, coverage);
  const [secondsValue, refusal] = targetSeconds(profile, length, coverage);
  if (refusal) return { refusal: { code: "lengthUnavailable", message: refusal } };
  const silent = truthy(context.juniorMode) || !truthy(context.primaryHasAudio);
  const pid = profileId as string;
  const header = {
    schemaVersion: "jovra.story-brief/1", briefId: `brief-${pid}-${length}`,
    projectId: context.projectId, revision: 1, sample: context.sample,
    profile: { id: pid, revision: profile.revision }, bindings: { ...context.bindings },
    planner: { ...PLANNER }, feelingKey: FEELING[pid], audience: opts.audience,
    durationTargetSeconds: secondsValue, aspect: opts.aspect,
    primaryAudioPolicy: silent ? "no-audio" : "continuous-primary-court-audio",
    effectIntensity: opts.effectIntensity, cleanAlternate: CLEAN_ALTERNATE.includes(pid),
    privacy: { venueVisible: opts.venueVisible, faces: opts.blurBystanders ? "blur-bystanders" : "show" },
    music: opts.music, narration: opts.narration,
    beats: [], comparisons: [], omitted: [], unresolved: [],
  };
  const directions = {
    length, framing: opts.aspect === "9:16" ? "letterbox" : "fill", shake: false, keepFullRallies: true,
    caption: opts.caption, dedication: opts.dedication, musicUnavailable: opts.musicUnavailable,
  };
  return { brief: header, directions };
}

// ----- grammar lint -------------------------------------------------------------------------------------------------

export interface Finding {
  code: "grammarViolation";
  rule: string;
  beatId: string | null;
}

/** Bold grammar rules for the plan's profile. Ids that do not resolve are planner.check's concern. */
export function lint(profiles: Record<string, J>, plan: J, context: J): Finding[] {
  const pid = plan.profile.id;
  const profile = profileOf(profiles, pid);
  const g = profile.grammar;
  const refs = new Map<unknown, J>(context.references.map((r: J) => [r.refId, r]));
  const keepers = new Map<unknown, J>(context.keepers.map((k: J) => [k.keeperId, k]));
  const brolls = new Map<unknown, J>(context.brolls.map((b: J) => [b.brollId, b]));
  const found: Finding[] = [];
  const hit = (rule: string, beat: J = null) => {
    found.push({ code: "grammarViolation", rule, beatId: beat ? beat.beatId : null });
  };

  const target = plan.durationTargetSeconds;
  if (!(g.durationSeconds.min <= target && target <= g.durationSeconds.max)) hit("duration-range");
  if (plan.effectIntensity !== "low" && !EFFECT_OPTION_PROFILES.includes(pid)) hit("effect-intensity");
  const music = plan.music;
  if (music !== null && !(truthy(g.music) && context.rights.some((r: J) =>
    pyEq(r.rightsRecordId, music.rightsRecordId) && pyEq(r.assetId, music.assetId)))) {
    hit("music");
  }
  const narration = plan.narration;
  if (narration !== null && !(truthy(g.narration) && context.consents.some((c: J) =>
    pyEq(c.consentRecordId, narration.consentRecordId) && truthy(c.granted) && within("narration-voice", c.scope)))) {
    hit("narration");
  }
  const strict = g.chronology === "strict";
  const liveSeen = new Set<unknown>();
  let lastStart: number | null = null;
  let previous: J = null;
  const reviewedCue = plan.beats.some((b: J) => b.overlays.some((o: J) =>
    o.kind === "cue" && within(refs.get(o.refId)?.provenance, AT_LEAST_REVIEWED)));
  for (const beat of plan.beats) {
    const t = beat.treatment;
    const kid = beat.keeperId;
    if (!within(t, g.ops)) hit("op-not-in-profile", beat);
    if (t === "replay") {
      if (!within(beat.replaySpeedDen, g.replaySpeedDens)) hit("replay-speed", beat);
      if (!liveSeen.has(kid)) hit("replay-before-live", beat);
      if (strict && !(previous && pyEq(previous.keeperId, kid) && within(previous.treatment, ["live", "replay"]))) {
        hit("strict-chronology", beat);   // a replay ends before the next point's serve
      }
    } else if (beat.replaySpeedDen !== null) {
      hit("replay-speed", beat);
    }
    if (t === "live" && keepers.has(kid)) {
      if (liveSeen.has(kid)) hit("one-live-showing", beat);
      liveSeen.add(kid);
      const start = keepers.get(kid).session.startUs;
      if (strict && lastStart !== null && start < lastStart) hit("strict-chronology", beat);
      lastStart = lastStart === null ? start : Math.max(lastStart, start);
      if (WIDE_ANGLE_PROFILES.includes(pid) && !within(beat.angle, [null, keepers.get(kid).slots[0]])) {
        hit("wide-angle-only", beat);
      }
    }
    for (const o of beat.overlays) {
      const ref = refs.get(o.refId);
      if (ref !== undefined && !within(ref.provenance, own(g.overlays, o.kind, []))) hit("overlay-not-allowed", beat);
    }
    if (t === "title-card") {
      const tmpl = cardTemplate(beat.templateId);
      if (tmpl !== undefined && !tmpl.profiles.includes(pid)) hit("card-template", beat);
      if (beat.templateId === "card.final-score" && !truthy(context.pointCoverageComplete)) {
        hit("final-score-incomplete", beat);
      }
      if (pid === "coach-cut" && INSTRUCTION_TEMPLATES.includes(beat.templateId) && !reviewedCue) {
        hit("instruction-without-cue", beat);
      }
    }
    if (t === "broll" && brolls.has(beat.brollId)) {
      const b = brolls.get(beat.brollId);
      if (!truthy(b.depictsThisMatch)) hit("broll-not-this-match", beat);
      if (truthy(b.revealsLocation) && !truthy(plan.privacy.venueVisible)) hit("hidden-location", beat);
    }
    previous = beat;
  }
  for (const c of plan.comparisons) {
    const shown = Object.values(c.display).filter((v) => typeof v === "string").join(" ").toLowerCase();
    if (shown.includes("improv") || pyStr(c.display.delta).includes("%")) {
      hit("comparison-claim");
    } else if (c.claim === "change" && !(within(c.before.provenance, AT_LEAST_REVIEWED)
      && within(c.after.provenance, AT_LEAST_REVIEWED))) {
      hit("comparison-claim");
    }
  }
  return found;
}

// ----- vectors ------------------------------------------------------------------------------------------------------

/** A director vector case (op brief, lint or templates) -> its result, or {rejectCode}. */
export function runVector(profiles: Record<string, J>, c: J): J {
  const input = c.input;
  try {
    if (c.op === "brief") return brief(profiles, input.context, input.profileId, input.options);
    if (c.op === "lint") return { findings: lint(profiles, input.plan, input.context) };
    if (c.op === "templates") return { templates: CARD_TEMPLATES, instructionTemplates: [...INSTRUCTION_TEMPLATES] };
    throw new Reject("badOp", `op ${pyStr(c.op)}`);
  } catch (exc) {
    if (exc instanceof Reject) return { rejectCode: exc.code };
    throw exc;
  }
}
