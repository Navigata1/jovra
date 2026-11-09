/**
 * Port of spec/reference/studio/edl.py: the jovra.edit-plan/2 validator. Strict unknown-field rejection, contiguous
 * output coverage, revision binding, labelled replays at bounded speeds, freezes, title cards, B-roll, overlay
 * references bound to the event revision, allowlisted transitions with source handles and contact protection, the
 * audio bed (one route per output frame, primary court audio in sync during live play), consented narration,
 * rights-bound music, aspect with letterbox or reviewed reframe windows, chapters and the clean-alternate flag.
 *
 * Everything a plan names is resolved against the trusted context built from stored records; validate() refuses to
 * run without it. A valid plan is a checked proposal only: it proves nothing about real footage and never approves
 * spend. Module page: spec/studio/modules/edl.md.
 */

import {
  F, canonicalSha256, fpsFraction, frameDurationUs, has, isDict, isInt, own, pyEq, pyStr, rateFraction, require,
  roundHalfUp, seconds, sortedStrings, type J, type Num, type Rate,
} from "./core.ts";

export const VERSION = "jovra.edit-plan/2";
const MAX_MATCH_SOURCES = 6;
const MAX_BROLL_SOURCES = 12;
const MAX_SEGMENTS = 128;
const MAX_OUTPUT_SECONDS = 14400;
const MAX_OVERLAYS = 8;
const MAX_DIMENSION = 3840;
const FRAME_UNITS = 10000;
const MAX_PAN_UNITS_PER_FRAME = 50;
const MAX_REFRAME_UPSCALE = 2;
const ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const TEMPLATE = /^[a-z][a-z0-9-]{0,31}(\.[a-z0-9][a-z0-9-]{0,31}){0,3}$/;
const HEX64 = /^[0-9a-f]{64}$/;
export const ASPECTS: Record<string, [number, number]> = { "16:9": [16, 9], "9:16": [9, 16], "1:1": [1, 1], "4:5": [4, 5] };
const PROVENANCE = ["manual", "estimated", "reviewed", "validated"];
const OVERLAY_KINDS = ["score", "metric", "note", "cue", "annotation"];
const FORBIDDEN_KEYS = new Set(["command", "cmd", "shell", "script", "path", "localpath", "file", "url", "uri", "href",
  "endpoint", "secret", "token", "apikey", "password", "credential", "signedurl", "filter", "filtergraph", "approved",
  "paid", "renderallowed", "price", "amount", "cost"]);

const SEGMENT_FIELDS: Record<string, string> = {
  live: "id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
    + "sessionInUs keeperId protectedFrames overlayRefs framing",
  broll: "id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
    + "brollId overlayRefs framing",
  replay: "id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
    + "replayOf labelTemplateId overlayRefs framing",
  freeze: "id op outputInFrame outputOutFrame transitionIn sourceId sourceFrame labelTemplateId overlayRefs framing",
  "title-card": "id op outputInFrame outputOutFrame transitionIn templateId textRefs overlayRefs",
};
const LABELS = { replay: "label.replay", freeze: "label.paused" };
const VIDEO_OPS = ["live", "broll", "replay", "freeze"];
const MOVING_OPS = ["live", "broll", "replay"];

// ----- small strict helpers -----------------------------------------------------------------------------------------

function fullmatch(re: RegExp, value: unknown): boolean {
  return typeof value === "string" && re.test(value);
}

export function fields(obj: unknown, names: string, label: string): asserts obj is Record<string, J> {
  require(isDict(obj), "notObject", `${label} must be an object`);
  const want = new Set(names.split(" ").filter(Boolean));
  const have = Object.keys(obj);
  const unknown = sortedStrings(have.filter((k) => !want.has(k)));
  require(!unknown.length, "unknownField", `${label}: unknown field(s) ${unknown.join(", ")}`);
  const missing = sortedStrings([...want].filter((k) => !Object.hasOwn(obj, k)));
  require(!missing.length, "missingField", `${label}: missing field(s) ${missing.join(", ")}`);
}

export function integer(value: unknown, label: string, minimum = 0): number {
  require(isInt(value) && value >= minimum, "badInteger", `${label} must be an integer >= ${minimum}`);
  return value;
}

export function identifier(value: unknown, label: string): string {
  require(fullmatch(ID, value), "badIdentifier", `${label}: invalid id`);
  return value as string;
}

function template(value: unknown, label: string, prefix = ""): string {
  require(fullmatch(TEMPLATE, value) && (value as string).startsWith(prefix), "badTemplate",
    `${label}: invalid template id`);
  return value as string;
}

export function fpsOf(value: unknown, label: string): F {
  fields(value, "num den", label);
  const rate = F.of(integer(value.num, `${label}.num`, 1), integer(value.den, `${label}.den`, 1));
  require(rate.ge(1) && rate.le(240), "badFps", `${label} outside 1-240 fps`);
  return rate;
}

/** Defense in depth: executable, location, credential and spend fields are refused by name anywhere. */
export function scanForbidden(value: unknown, where = "$"): void {
  if (isDict(value)) {
    for (const [key, item] of Object.entries(value)) {
      require(!FORBIDDEN_KEYS.has(key.toLowerCase()), "forbiddenField", `${where}.${key} is never allowed in an EDL`);
      scanForbidden(item, `${where}.${key}`);
    }
  } else if (Array.isArray(value)) {
    value.forEach((item, i) => scanForbidden(item, `${where}[${i}]`));
  } else if (typeof value === "string") {
    require(!value.includes("://") && !value.startsWith("/") && !value.startsWith("~") && !value.startsWith("\\")
      && !value.includes(".."), "forbiddenValue", `${where}: looks like a path or URL`);
  }
}

// ----- sources and coverage -----------------------------------------------------------------------------------------

/** A coverage interval: [inFrame, outFrame), session start (null for B-roll) and clock rate (null for B-roll). */
export type Coverage = readonly [number, number, number | null, F | null];

export class Source {
  readonly id: string;
  readonly role: string;
  readonly sha256: string;
  readonly fps: F;
  readonly fpsRaw: Rate;
  readonly width: number;
  readonly height: number;
  readonly frames: number;
  readonly hasAudio: boolean;
  readonly coverage: Coverage[];

  constructor(raw: unknown) {
    fields(raw, "id role sha256 proxy hasAudio coverage", "source");
    this.id = identifier(raw.id, "source id");
    require(raw.role === "match" || raw.role === "broll", "badEnum", "source role must be match or broll");
    this.role = raw.role;
    require(fullmatch(HEX64, raw.sha256), "badHash", "source sha256 must be 64 lowercase hex");
    this.sha256 = raw.sha256;
    const proxy = raw.proxy;
    fields(proxy, "fps width height frameCount ptsTableSha256", "source proxy");
    this.fps = fpsOf(proxy.fps, "proxy fps");
    this.fpsRaw = proxy.fps;
    this.width = integer(proxy.width, "proxy width", 2);
    this.height = integer(proxy.height, "proxy height", 2);
    this.frames = integer(proxy.frameCount, "proxy frameCount", 1);
    require(seconds(this.frames, this.fpsRaw).le(MAX_OUTPUT_SECONDS), "sourceTooLong", "source exceeds four hours");
    require(fullmatch(HEX64, proxy.ptsTableSha256), "badHash", "proxy ptsTableSha256 must be 64 lowercase hex");
    require(typeof raw.hasAudio === "boolean", "badBoolean", "hasAudio must be boolean");
    this.hasAudio = raw.hasAudio;
    require(Array.isArray(raw.coverage) && raw.coverage.length >= 1 && raw.coverage.length <= 64, "badCoverage",
      "coverage needs 1-64 intervals");
    const coverage: Coverage[] = [];
    let cursor = 0;
    for (const c of raw.coverage) {
      fields(c, "inFrame outFrame sessionStartUs rate", "coverage interval");
      const lo = integer(c.inFrame, "coverage inFrame");
      const hi = integer(c.outFrame, "coverage outFrame", 1);
      require(cursor <= lo && lo < hi && hi <= this.frames, "badCoverage",
        "coverage intervals must be ordered, disjoint and inside the proxy");
      cursor = hi;
      if (this.role === "broll") {
        require(c.sessionStartUs === null && c.rate === null, "badCoverage",
          "B-roll is not on the session clock (sessionStartUs and rate are null)");
        coverage.push([lo, hi, null, null]);
      } else {
        const start = integer(c.sessionStartUs, "coverage sessionStartUs");
        fields(c.rate, "num den", "coverage rate");
        require(isInt(c.rate.den) && c.rate.den === 1_000_000_000 && isInt(c.rate.num)
          && c.rate.num >= 900_000_000 && c.rate.num <= 1_100_000_000, "badRate",
        "rate must be num/1000000000 within 0.9-1.1");
        coverage.push([lo, hi, start, rateFraction(c.rate as Rate)]);
      }
    }
    this.coverage = coverage;
  }

  /** The coverage interval containing the source-frame range [lo, hi), else null (gap or outside). */
  interval(lo: Num, hi: Num): Coverage | null {
    for (const c of this.coverage) {
      if (F.from(lo).ge(c[0]) && F.from(hi).le(c[1])) return c;
    }
    return null;
  }

  /**
   * Exact session time of a (possibly fractional) proxy frame position, or null off the session clock. Without `cov`
   * the lookup is half-open (the first frame of a restarted interval maps through that interval); with `cov` the
   * position may equal that interval's exclusive end.
   */
  sessionUs(frame: Num, cov: Coverage | null = null): F | null {
    const at = F.from(frame);
    let c = cov;
    if (c === null) {
      c = this.coverage.find((x) => at.ge(x[0]) && at.lt(x[1])) ?? null;
      if (c === null && this.coverage.length && at.eq(this.coverage[this.coverage.length - 1][1])) {
        c = this.coverage[this.coverage.length - 1];
      }
      if (c === null) return null;
    }
    const [lo, hi, start, rate] = c;
    if (!(at.ge(lo) && at.le(hi)) || start === null || rate === null) return null;
    return at.sub(lo).mul(frameDurationUs(this.fpsRaw)).mul(rate).add(start);
  }
}

// ----- the validator ------------------------------------------------------------------------------------------------

const CONTEXT_KEYS = ["projectId", "current", "sources", "keepers", "contacts", "brolls", "references", "consents",
  "rights"];

interface SegInfo {
  seg: J;
  op: string;
  in: number;
  out: number;
  session: [F | null, F | null] | null;
  src?: Source;
  sIn?: number;
  sOut?: number;
  speed?: F;
  cov?: Coverage;
  protected?: [number, number][];
}

export interface Validation {
  status: "valid-plan";
  sample: boolean;
  profileId: string;
  segments: number;
  frames: number;
  durationSeconds: string;
  motionEffects: boolean;
  needsCleanAlternate: boolean;
  planSha256: string;
  actualMediaVerified: false;
  rendered: false;
}

/** Validate a jovra.edit-plan/2 document against the trusted context; raises Reject on the first violation. */
export function validate(plan: J, profiles: Record<string, J>, context: J): Validation {
  require(isDict(context) && CONTEXT_KEYS.every((k) => Object.hasOwn(context, k)), "contextMissing",
    `validate() needs the trusted context (${CONTEXT_KEYS.join(", ")}); a plan is never checked against itself`);
  scanForbidden(plan);
  fields(plan, "schemaVersion projectId planId planRevision sample cleanAlternate bindings output grade "
    + "sources segments chapters audio", "plan");
  require(plan.schemaVersion === VERSION, "badVersion", `schemaVersion must be ${VERSION}`);
  identifier(plan.projectId, "projectId");
  require(plan.projectId === context.projectId, "projectMismatch",
    "the plan names another project than the stored records it is checked against");
  identifier(plan.planId, "planId");
  integer(plan.planRevision, "planRevision", 1);
  require(typeof plan.sample === "boolean", "badBoolean", "sample must be boolean");
  require(typeof plan.cleanAlternate === "boolean", "badBoolean", "cleanAlternate must be boolean");

  const bindings = plan.bindings;
  fields(bindings, "sourceManifestRevision syncRevision eventRevision profileId profileRevision "
    + "keeperCatalogRevision brollCatalogRevision", "bindings");
  for (const key of ["sourceManifestRevision", "syncRevision", "eventRevision", "profileRevision",
    "keeperCatalogRevision", "brollCatalogRevision"]) {
    integer(bindings[key], key, 1);
  }
  require(has(profiles, bindings.profileId), "unknownProfile", "unknown story profile");
  const profile = profiles[bindings.profileId];
  const grammar = profile.grammar;
  require(pyEq(bindings.profileRevision, profile.revision), "staleRevision",
    "plan is bound to a different story-profile revision");
  for (const [key, current] of Object.entries(context.current)) {
    require(pyEq(own(bindings, key, null), current), "staleRevision", `${key} is not current (${String(current)})`);
  }

  const out = plan.output;
  fields(out, "fps width height aspect totalFrames container videoCodec audioCodec audioSampleRate", "output");
  const outFps = fpsOf(out.fps, "output fps");
  const width = integer(out.width, "output width", 2);
  const height = integer(out.height, "output height", 2);
  require(width % 2 === 0 && height % 2 === 0 && width <= MAX_DIMENSION && height <= MAX_DIMENSION, "badOutput",
    "output dimensions must be even and at most 3840");
  require(has(ASPECTS, out.aspect), "badOutput", "unsupported aspect");
  const [aw, ah] = ASPECTS[out.aspect];
  require(width * ah === height * aw, "badOutput", "width/height do not match the declared aspect");
  const total = integer(out.totalFrames, "totalFrames", 1);
  const duration = seconds(total, out.fps);
  require(duration.le(MAX_OUTPUT_SECONDS), "outputTooLong", "output exceeds four hours");
  require(out.container === "mp4" && (out.videoCodec === "h264" || out.videoCodec === "hevc")
    && out.audioCodec === "aac" && pyEq(out.audioSampleRate, 48000), "badOutput",
  "output must be MP4, H.264/HEVC, AAC 48 kHz");
  const loS = grammar.durationSeconds.min;
  const hiS = grammar.durationSeconds.max;
  require(duration.ge(loS) && duration.le(hiS), "durationOutsideProfile",
    `${duration} s is outside the profile's ${loS}-${hiS} s`);

  const grade = plan.grade;
  fields(grade, "presetId", "grade");
  require(grammar.gradePresets.some((p: J) => pyEq(p, grade.presetId)), "opNotAllowed",
    "grade preset not allowed for this profile");

  // sources
  require(Array.isArray(plan.sources) && plan.sources.length > 0, "badSources", "at least one source");
  const sources = new Map<string, Source>();
  for (const raw of plan.sources) {
    const src = new Source(raw);
    require(!sources.has(src.id), "duplicateId", `duplicate source ${src.id}`);
    const trusted = own(context.sources, src.id);
    require(trusted !== undefined && trusted !== null && trusted.sha256 === src.sha256, "untrustedSource",
      `source ${src.id} is not offered by the trusted manifest and sync map with this hash`);
    require(raw.role === trusted.role && pyEq(raw.proxy, trusted.proxy) && raw.hasAudio === trusted.hasAudio,
      "untrustedSource", `source ${src.id}: the plan's snapshot differs from the trusted manifest`);
    require(pyEq(raw.coverage, trusted.coverage), "coverageMismatch",
      `source ${src.id}: coverage (session start, rate, frames) is not the reviewed sync map's`);
    sources.set(src.id, src);
  }
  const nMatch = [...sources.values()].filter((s) => s.role === "match").length;
  const nBroll = sources.size - nMatch;
  require(nMatch >= 1 && nMatch <= MAX_MATCH_SOURCES && nBroll <= MAX_BROLL_SOURCES, "badSources",
    "one to six match sources and at most twelve B-roll sources");

  // segments
  const segs = plan.segments;
  require(Array.isArray(segs) && segs.length >= 1 && segs.length <= MAX_SEGMENTS, "tooManySegments", "1-128 segments");
  const seen = new Map<string, SegInfo>();
  const order: SegInfo[] = [];
  let cursor = 0;
  let motion = false;
  let lastLiveSession: number | null = null;
  const shownLive: [F, F, Source][] = [];
  segs.forEach((seg: J, index: number) => {
    require(isDict(seg) && has(SEGMENT_FIELDS, own(seg, "op")), "badOp", "unknown segment op");
    const op: string = seg.op;
    fields(seg, SEGMENT_FIELDS[op], `segment ${index} (${op})`);
    const sid = identifier(seg.id, "segment id");
    require(!seen.has(sid), "duplicateId", `duplicate segment id ${sid}`);
    require(grammar.ops.includes(op), "opNotAllowed", `${op} is not allowed in ${profile.id}`);
    const oIn = integer(seg.outputInFrame, "outputInFrame");
    const oOut = integer(seg.outputOutFrame, "outputOutFrame", 1);
    require(oIn === cursor, "outputGap", `segment ${sid} must start at output frame ${cursor}`);
    require(oIn < oOut && oOut <= total, "badInterval", `segment ${sid} has an invalid output interval`);
    cursor = oOut;
    const outLen = oOut - oIn;
    const info: SegInfo = { seg, op, in: oIn, out: oOut, session: null };

    if (MOVING_OPS.includes(op)) {
      const src = sourceFor(seg, sources, op);
      const sIn = integer(seg.sourceInFrame, "sourceInFrame");
      const sOut = integer(seg.sourceOutFrame, "sourceOutFrame", 1);
      require(sIn < sOut, "badInterval", `segment ${sid} has an empty source window`);
      const speed = speedOf(seg.speed, op, grammar);
      // source seconds == output seconds x speed, exactly
      require(F.from(sOut - sIn).div(src.fps).eq(F.from(outLen).div(outFps).mul(speed)), "durationMismatch",
        `segment ${sid}: source and output durations disagree at speed ${speed}`);
      // clean-frame rule: every output frame is a distinct real captured frame
      require(src.fps.mul(speed).ge(outFps), "cleanFrameRule",
        `segment ${sid}: source fps x speed is below the output fps (no interpolated frames)`);
      const cov = src.interval(sIn, sOut);
      require(cov !== null, "outsideCoverage",
        `segment ${sid}: source window leaves the reviewed coverage or crosses a gap`);
      Object.assign(info, { src, sIn, sOut, speed, cov });
      if (src.role === "match") info.session = [src.sessionUs(sIn, cov), src.sessionUs(sOut, cov)];
      if (op === "live") {
        require(src.role === "match", "badSourceRole", `live segment ${sid} needs a match source`);
        require(seg.keeperId === null || fullmatch(ID, pyStr(seg.keeperId)), "badIdentifier",
          "keeperId must be an id or null");
        if (seg.keeperId !== null) {
          require(context.keepers.some((k: J) => pyEq(k, seg.keeperId)), "untrustedReference", "unknown keeper");
        }
        const expected = roundHalfUp(src.sessionUs(sIn, cov)!);
        require(pyEq(seg.sessionInUs, expected), "sessionTimeMismatch",
          `segment ${sid}: sessionInUs must be ${expected} from the sync map`);
        require(Array.isArray(seg.protectedFrames) && seg.protectedFrames.length <= 64, "badProtected",
          "protectedFrames must be a list");
        const prot: [number, number][] = [];
        for (const w of seg.protectedFrames) {
          fields(w, "inFrame outFrame", "protected window");
          const a = integer(w.inFrame, "protected in");
          const b = integer(w.outFrame, "protected out", 1);
          require(sIn <= a && a < b && b <= sOut, "badProtected", "protected window must lie inside the segment");
          prot.push([a, b]);
        }
        info.protected = prot;
        // every stored contact in the window is protected, whatever keeperId says
        for (const c of own(context.contacts, src.id, []) as number[]) {
          if (sIn <= c && c < sOut) {
            require(prot.some(([a, b]) => a <= c && c < b), "contactUnprotected",
              `segment ${sid}: stored contact at frame ${c} is not inside a protected window`);
          }
        }
        if (grammar.chronology === "strict") {
          require(lastLiveSession === null || seg.sessionInUs > lastLiveSession, "chronology",
            `segment ${sid}: live segments must keep session order in ${profile.id}`);
        }
        lastLiveSession = seg.sessionInUs;
        // a moment shown live is shown live once; two angles cut at one instant may overlap by one coarser frame
        const [l0, l1] = info.session as [F, F];
        for (const [p0, p1, other] of shownLive) {
          const a = frameDurationUs(src.fpsRaw);
          const b = frameDurationUs(other.fpsRaw);
          const slack = a.ge(b) ? a : b;
          const overlap = (l1.lt(p1) ? l1 : p1).sub(l0.gt(p0) ? l0 : p0);
          require(overlap.le(slack), "replayWithoutLabel",
            `segment ${sid} shows session time an earlier live segment already showed; a repeat is a labelled replay`);
        }
        shownLive.push([l0, l1, src]);
      } else if (op === "broll") {
        require(src.role === "broll", "badSourceRole", `broll segment ${sid} needs a B-roll source`);
        identifier(seg.brollId, "brollId");
        require(context.brolls.some((b: J) => pyEq(b, seg.brollId)), "untrustedReference", "unknown B-roll item");
      } else {
        checkReplay(seg, info, seen, order, grammar, outFps, outLen);
      }
    } else if (op === "freeze") {
      const src = sourceFor(seg, sources, op);
      const frame = integer(seg.sourceFrame, "sourceFrame");
      require(src.interval(frame, frame + 1) !== null, "outsideCoverage", `freeze ${sid} frame not covered`);
      require(seg.labelTemplateId === LABELS.freeze, "labelMissing", "a freeze needs the Paused label");
      const ms = F.from(outLen).div(outFps).mul(1000);
      require(ms.ge(grammar.freezeMs.min) && ms.le(grammar.freezeMs.max), "freezeDuration",
        `freeze ${sid} lasts ${ms} ms`);
      info.src = src;
    } else {
      template(seg.templateId, "card templateId", "card.");
      require(Array.isArray(seg.textRefs) && seg.textRefs.length <= 4, "badTextRefs", "at most 4 text refs");
      for (const ref of seg.textRefs) {
        identifier(ref, "textRef");
        resolveNote(ref, context, `card ${sid} textRef`);
      }
      const ms = F.from(outLen).div(outFps).mul(1000);
      require(ms.ge(grammar.cardMs.min) && ms.le(grammar.cardMs.max), "cardDuration", `card ${sid} lasts ${ms} ms`);
    }

    if (VIDEO_OPS.includes(op)) {
      motion = checkFraming(seg.framing, sources.get(seg.sourceId)!, out, grammar, outLen) || motion;
    }
    checkOverlays(seg.overlayRefs, bindings, grammar, sid, context, info, sources);
    motion = checkTransition(seg.transitionIn, info, order, grammar, out.fps, index, context) || motion;
    seen.set(sid, info);
    order.push(info);
  });
  require(cursor === total, "incompleteCoverage", "segments must cover every output frame exactly once");

  checkChapters(plan.chapters, total);
  checkAudio(plan.audio, sources, order, total, outFps, out.fps, grammar, context);

  if (plan.cleanAlternate) {
    require(!motion, "motionInCleanAlternate", "a clean alternate has no dissolves, dips or moving reframes");
  }
  return {
    status: "valid-plan", sample: plan.sample, profileId: profile.id, segments: segs.length, frames: total,
    durationSeconds: String(duration), motionEffects: motion, needsCleanAlternate: motion && !plan.cleanAlternate,
    planSha256: canonicalSha256(plan), actualMediaVerified: false, rendered: false,
  };
}

function sourceFor(seg: J, sources: Map<string, Source>, op: string): Source {
  const sid = identifier(seg.sourceId, `${op} sourceId`);
  require(sources.has(sid), "unknownSource", `unknown source ${sid}`);
  return sources.get(sid)!;
}

function speedOf(raw: J, op: string, grammar: J): F {
  fields(raw, "num den", "speed");
  require(isInt(raw.num) && raw.num === 1 && isInt(raw.den) && [1, 2, 4, 8].includes(raw.den), "badSpeed",
    "speed must be 1, 1/2, 1/4 or 1/8");
  if (op === "live" || op === "broll") {
    require(raw.den === 1, "badSpeed", "live action and B-roll stay at original speed");
  } else {
    require(grammar.replaySpeedDens.includes(raw.den), "badSpeed", "replay speed not allowed by this profile");
  }
  return F.of(1, raw.den);
}

function checkReplay(seg: J, info: SegInfo, seen: Map<string, SegInfo>, order: SegInfo[], grammar: J, outFps: F,
  outLen: number): void {
  const sid = seg.id;
  require(seg.labelTemplateId === LABELS.replay, "labelMissing", "a replay needs the Replay label");
  require(F.from(outLen).div(outFps).mul(1000).le(grammar.replayMaxMs), "replayTooLong",
    `replay ${sid} is longer than ${grammar.replayMaxMs} ms of output`);
  const target = typeof seg.replayOf === "string" ? seen.get(seg.replayOf) : undefined;
  require(target !== undefined && target.op === "live", "replayBeforeOriginal",
    `replay ${sid} must follow the live segment it re-shows`);
  require(info.src!.role === "match", "badSourceRole", "a replay re-shows match footage");
  const half = frameDurationUs({ num: outFps.num, den: outFps.den }).div(2);
  const [r0, r1] = info.session as [F, F];
  const [l0, l1] = target.session as [F, F];
  require(l0.sub(half).le(r0) && r1.le(l1.add(half)), "replayOutsideOriginal",
    `replay ${sid} shows session time that its original live segment did not show`);
  if (grammar.chronology === "strict") {
    const laterLive = order.slice(order.indexOf(target) + 1).filter((o) => o.op === "live");
    require(!laterLive.length, "chronology", `replay ${sid} must come before the next live point`);
  }
}

/** True when the framing is a motion effect (a moving reframe). */
function checkFraming(framing: J, src: Source, out: J, grammar: J, outLen: number): boolean {
  require(isDict(framing) && ["fill", "letterbox", "reframe"].includes(own(framing, "mode")), "badFraming",
    "framing mode must be fill, letterbox or reframe");
  const ow = out.width;
  const oh = out.height;
  const sameAspect = src.width * oh === src.height * ow;
  const mode = framing.mode;
  if (mode === "fill") {
    fields(framing, "mode", "framing");
    require(sameAspect, "framingAspect", "fill needs the source aspect to equal the output aspect");
    require(src.height >= oh, "upscaleRefused", "output resolution above the source does not create detail");
    return false;
  }
  if (mode === "letterbox") {
    fields(framing, "mode", "framing");
    require(F.of(ow, src.width).le(1) || F.of(oh, src.height).le(1), "upscaleRefused",
      "letterbox would upscale the source");
    return false;
  }
  fields(framing, "mode basis windows", "framing");
  require(grammar.reframe === "if-box-fits", "opNotAllowed", "this profile letterboxes instead of reframing");
  require(framing.basis === "reviewed-action-box", "reframeNotReviewed",
    "reframe windows come only from a reviewed action-safe box");
  const windows = framing.windows;
  require(Array.isArray(windows) && windows.length >= 1 && windows.length <= 32, "badReframe", "1-32 reframe windows");
  let prev: J = null;
  const tolerance = Math.max(src.width * oh, src.height * ow);
  for (const w of windows) {
    fields(w, "atFrame x y w h", "reframe window");
    const at = integer(w.atFrame, "atFrame");
    const x = integer(w.x, "x");
    const y = integer(w.y, "y");
    const cw = integer(w.w, "w", 1);
    const ch = integer(w.h, "h", 1);
    require(x + cw <= FRAME_UNITS && y + ch <= FRAME_UNITS, "badReframe", "window leaves the source frame");
    require(Math.abs(cw * src.width * oh - ch * src.height * ow) <= tolerance, "badReframe",
      "window aspect does not match the output aspect");
    require(oh * FRAME_UNITS <= MAX_REFRAME_UPSCALE * ch * src.height, "upscaleRefused",
      "reframe crop is upscaled more than 2x; letterbox instead");
    if (prev === null) {
      require(at === 0, "badReframe", "the first window starts at the segment's first frame");
    } else {
      require(prev.atFrame < at && at < outLen, "badReframe", "reframe windows must be strictly increasing");
      const step = at - prev.atFrame;
      require(Math.abs(x - prev.x) <= MAX_PAN_UNITS_PER_FRAME * step
        && Math.abs(y - prev.y) <= MAX_PAN_UNITS_PER_FRAME * step, "panTooFast", "reframe pans too fast");
    }
    prev = w;
  }
  const first = windows[0];
  return windows.some((w: J) => w.x !== first.x || w.y !== first.y || w.w !== first.w || w.h !== first.h);
}

/** Text on screen and narration scripts come only from stored notes in the trusted reference catalog. */
function resolveNote(ref: string, context: J, label: string): void {
  const stored = own(context.references, ref);
  require(stored !== undefined && stored !== null, "untrustedReference", `${label} '${ref}' is not a stored record`);
  require(stored.kind === "note", "kindMismatch", `${label} '${ref}' is a ${stored.kind}, not a note`);
}

/** The session interval of match play a segment shows, or null (a card, B-roll). */
function shownSession(info: SegInfo, sources: Map<string, Source>): [F | null, F | null] | null {
  if (info.op === "live" || info.op === "replay") return info.session;
  if (info.op === "freeze") {
    const src = sources.get(info.seg.sourceId)!;
    if (src.role === "match") {
      const frame = info.seg.sourceFrame;
      return [src.sessionUs(frame), src.sessionUs(frame + 1)];
    }
  }
  return null;
}

function checkOverlays(refs: J, bindings: J, grammar: J, sid: string, context: J, info: SegInfo,
  sources: Map<string, Source>): void {
  require(Array.isArray(refs) && refs.length <= MAX_OVERLAYS, "badOverlays", "at most 8 overlay refs");
  let annotations = 0;
  for (const ref of refs) {
    fields(ref, "kind refId eventRevision provenance", "overlay");
    require(OVERLAY_KINDS.includes(ref.kind), "overlayNotAllowed", "unsupported overlay kind");
    identifier(ref.refId, "overlay refId");
    integer(ref.eventRevision, "overlay eventRevision", 1);
    require(ref.eventRevision === bindings.eventRevision, "staleRevision",
      `segment ${sid}: overlay bound to event revision ${ref.eventRevision}, plan uses ${bindings.eventRevision}`);
    require(PROVENANCE.includes(ref.provenance), "badEnum", "invalid provenance");
    const allowed = own(grammar.overlays, ref.kind);
    require(allowed !== undefined && allowed !== null, "overlayNotAllowed",
      `${ref.kind} overlays are not used in this profile`);
    require(allowed.includes(ref.provenance), "provenanceNotAllowed",
      `${ref.provenance} ${ref.kind} overlays are not allowed in this profile`);
    if (ref.kind === "annotation") annotations += 1;
  }
  require(annotations <= 1, "badOverlays", "at most one annotation at a time");
  for (const ref of refs) {
    // an overlay is a reference to a stored record: its kind and provenance are the stored record's
    const stored = own(context.references, ref.refId);
    require(stored !== undefined && stored !== null, "untrustedReference",
      `segment ${sid}: overlay ${ref.kind} '${ref.refId}' does not resolve to a stored record`);
    require(stored.kind === ref.kind, "kindMismatch", `segment ${sid}: '${ref.refId}' is a stored ${stored.kind}`);
    require(stored.provenance === ref.provenance, "provenanceMismatch",
      `segment ${sid}: '${ref.refId}' is stored as ${stored.provenance}, the plan says ${ref.provenance}`);
    require(pyEq(stored.eventRevision, bindings.eventRevision), "staleRevision",
      `segment ${sid}: '${ref.refId}' was resolved at another event revision`);
    require(has(stored, "pointWindows"), "contextMissing",
      `segment ${sid}: the trusted reference '${ref.refId}' carries no pointWindows binding`);
    const windows = stored.pointWindows;
    const shown = shownSession(info, sources);
    if ((ref.kind === "score" || ref.kind === "metric") && windows !== null && shown !== null) {
      const half = frameDurationUs(info.src!.fpsRaw).div(2);   // half a source frame of rounding at each edge
      const [lo, hi] = shown as [F, F];
      require(windows.some(([w0, w1]: [number, number]) => half.neg().add(w0).le(lo) && hi.le(half.add(w1))),
        "overlayOutsideMoment",
        `segment ${sid}: ${ref.kind} '${ref.refId}' belongs to a point whose keeper windows do not contain the ` +
        `session time ${(lo.toNumber() / 1e6).toFixed(3)}-${(hi.toNumber() / 1e6).toFixed(3)} s shown`);
    }
  }
}

function checkTransition(tr: J, info: SegInfo, order: SegInfo[], grammar: J, outFpsRaw: Rate, index: number,
  context: J): boolean {
  fields(tr, "type frames", "transitionIn");
  const kind = tr.type;
  require(["cut", "dissolve", "dip"].includes(kind), "transitionNotAllowed", "transitions come from cut, dissolve, dip");
  const n = integer(tr.frames, "transition frames");
  if (kind === "cut") {
    require(n === 0, "badTransition", "a cut has 0 frames");
    return false;
  }
  require(index > 0, "badTransition", "the first segment starts with a cut");
  require(grammar.transitions.includes(kind), "transitionNotAllowed", `${kind} is not allowed in this profile`);
  require(n >= 2, "badTransition", "a dissolve or dip spans at least 2 frames");
  const ms = F.from(n).mul(1000).div(fpsFraction(outFpsRaw));
  require(ms.le(grammar.maxTransitionMs), "transitionTooLong", `${ms} ms exceeds ${grammar.maxTransitionMs} ms`);
  const prev = order[order.length - 1];
  const hOut = Math.floor(n / 2);   // output frames after the boundary that still show the outgoing source
  const hIn = n - hOut;             // output frames before the boundary that already show the incoming source
  require(prev.out - prev.in >= hIn && info.out - info.in >= hOut, "badTransition",
    "transition longer than an adjacent segment");
  const sides: [SegInfo, "sOut" | "sIn"][] = [[prev, "sOut"], [info, "sIn"]];
  for (const [side, edge] of sides) {
    if (!MOVING_OPS.includes(side.op)) continue;
    const src = side.src!;
    const k = src.fps.mul(side.speed!).div(fpsFraction(outFpsRaw));   // source frames per output frame
    const lo = side[edge]! - F.from(hIn).mul(k).ceil();
    const hi = side[edge]! + F.from(hOut).mul(k).ceil();
    require(lo >= 0 && src.interval(lo, hi) === side.cov, "transitionHandle",
      `transition needs source handles [${lo},${hi}) inside the same coverage (never across a gap)`);
    for (const [a, b] of side.protected ?? []) {
      require(hi <= a || b <= lo, "contactProtected", "a transition may not touch a protected contact window");
    }
    for (const c of own(context.contacts, src.id, []) as number[]) {
      require(!(lo <= c && c < hi), "contactProtected",
        `a transition may not blend the stored contact at frame ${c} (live or replay)`);
    }
  }
  return true;
}

function checkChapters(chapters: J, total: number): void {
  require(Array.isArray(chapters) && chapters.length <= 64, "badChapters", "chapters must be a list");
  let prev = -1;
  const ids = new Set<string>();
  chapters.forEach((ch: J, i: number) => {
    fields(ch, "id outputInFrame templateId", "chapter");
    identifier(ch.id, "chapter id");
    require(!ids.has(ch.id), "duplicateId", "duplicate chapter id");
    ids.add(ch.id);
    template(ch.templateId, "chapter templateId", "chapter.");
    const at = integer(ch.outputInFrame, "chapter outputInFrame");
    require((i === 0 && at === 0) || (i > 0 && prev < at && at < total), "badChapters",
      "chapters start at frame 0 and strictly increase inside the film");
    prev = at;
  });
}

interface Piece {
  route: string;
  in: number;
  out: number;
  raw: J;
  src?: Source;
  sIn?: number;
  n?: number;
  cov?: Coverage;
}

function checkAudio(audio: J, sources: Map<string, Source>, order: SegInfo[], total: number, outFps: F,
  outFpsRaw: Rate, grammar: J, context: J): void {
  fields(audio, "primarySourceId bed narration music", "audio");
  const bed = audio.bed;
  require(Array.isArray(bed) && bed.length >= 1 && bed.length <= 256, "bedCoverage", "the bed needs 1-256 pieces");
  const allSilent = bed.every((p: J) => isDict(p) && own(p, "route") === "silence");
  const primary = audio.primarySourceId;
  if (allSilent) {
    require(primary === null, "primaryBedSource", "an all-silent plan names no primary audio source");
  } else {
    identifier(primary, "primarySourceId");
    require(sources.has(primary) && sources.get(primary)!.role === "match" && sources.get(primary)!.hasAudio,
      "primaryBedSource", "the primary bed comes from a match source with audio");
  }
  const half = frameDurationUs(outFpsRaw).div(2);
  let cursor = 0;
  const pieces: Piece[] = [];
  for (const p of bed) {
    fields(p, "route sourceId sourceInFrame outputInFrame outputOutFrame fadeInMs fadeOutMs", "bed piece");
    const route = p.route;
    require(["primary-bed", "alt-bed", "hold-bed", "silence"].includes(route), "badEnum", "unknown audio route");
    const oIn = integer(p.outputInFrame, "bed outputInFrame");
    const oOut = integer(p.outputOutFrame, "bed out", 1);
    require(oIn === cursor && oIn < oOut && oOut <= total, "bedCoverage",
      "exactly one bed route per output frame, contiguous from frame 0");
    cursor = oOut;
    const fin = integer(p.fadeInMs, "fadeInMs");
    const fout = integer(p.fadeOutMs, "fadeOutMs");
    require(fin <= 2000 && fout <= 2000, "badFade", "fades are at most 2000 ms");
    const piece: Piece = { route, in: oIn, out: oOut, raw: p };
    if (route === "silence") {
      require(p.sourceId === null && p.sourceInFrame === null, "silenceBindsAudio", "silence must not bind a source");
      require(fin >= 10 && fout >= 10, "fadeTooShort", "silence needs >= 10 ms fades");
      pieces.push(piece);
      continue;
    }
    const srcId = identifier(p.sourceId, "bed sourceId");
    require(sources.has(srcId) && sources.get(srcId)!.hasAudio, "bedSourceUnavailable", "bed source has no audio");
    const src = sources.get(srcId)!;
    const sIn = integer(p.sourceInFrame, "bed sourceInFrame");
    const nSrc = F.from(oOut - oIn).mul(src.fps).div(outFps);
    require(nSrc.isInteger(), "bedClock", "bed window is not a whole number of source frames");
    const cov = src.interval(sIn, sIn + nSrc.trunc());
    require(cov !== null, "outsideCoverage", "bed window leaves the source coverage or crosses a gap");
    Object.assign(piece, { src, sIn, n: nSrc.trunc(), cov });
    if (route === "primary-bed" || route === "hold-bed") {
      require(srcId === primary, "primaryBedSource", `${route} uses the designated primary source`);
    }
    if (route === "alt-bed") {
      require(srcId !== primary, "badAltBed", "alt-bed switches to another source's audio");
      require(fin >= 20 && fout >= 20, "fadeTooShort", "alt-bed needs >= 20 ms fades");
    }
    if (route === "hold-bed") {
      const prev = pieces.length ? pieces[pieces.length - 1] : null;
      require(prev !== null && (prev.route === "primary-bed" || prev.route === "hold-bed") && prev.src === src
        && prev.sIn! + prev.n! === sIn, "holdBedNotContinuous", "hold-bed continues the primary bed without a jump");
    }
    pieces.push(piece);
  }
  require(cursor === total, "bedCoverage", "the bed must cover every output frame");
  for (const p of pieces) {
    if (p.route === "primary-bed" || (p.route === "alt-bed" && p.src!.role === "match")) {
      // court audio that is not held dead time plays only under live play, where it is checked for sync
      require(order.every((o) => !(o.in < p.out && p.in < o.out) || o.op === "live"), "courtBedOffLive",
        `${p.route} from ${p.raw.sourceId} at output frames ${p.in}-${p.out} plays under a non-live segment`);
    }
  }
  checkBedSwitches(pieces, order, outFps);

  const lives = order.filter((o) => o.op === "live");
  for (const p of pieces) {
    const overlapping = order.filter((o) => o.in < p.out && p.in < o.out);
    if (p.route === "hold-bed") {
      require(overlapping.every((o) => o.op !== "live"), "holdBedOverLive",
        "hold-bed plays only under replays, freezes, cards or B-roll");
      const b0 = p.src!.sessionUs(p.sIn!, p.cov!);
      const b1 = p.src!.sessionUs(p.sIn! + p.n!, p.cov!);
      require(b0 !== null && lives.every((l) => (l.session![1] as F).le(b0) || b1!.le(l.session![0] as F)),
        "holdBedNotDeadTime", "hold-bed must be real dead time that no live segment shows");
    }
  }
  if (allSilent) return;
  for (const live of lives) {
    for (const p of pieces) {
      const lo = Math.max(live.in, p.in);
      const hi = Math.min(live.out, p.out);
      if (lo >= hi) continue;
      require(p.route === "primary-bed" || p.route === "alt-bed", "liveWithoutCourtAudio",
        "live play is under the primary (or a point-boundary alternate) court bed");
      for (const o of [lo, hi - 1]) {
        const v = live.src!.sessionUs(F.from(o - live.in).mul(live.src!.fps).mul(live.speed!).div(outFps)
          .add(live.sIn!), live.cov!)!;
        const a = p.src!.sessionUs(F.from(o - p.in).mul(p.src!.fps).div(outFps).add(p.sIn!), p.cov!);
        require(a !== null && v.sub(a).abs().le(half), "bedOutOfSync",
          "court audio is out of sync with the picture (limit: half an output frame)");
      }
    }
  }

  const narration = audio.narration;
  if (narration !== null) {
    fields(narration, "voice consent disclosureTemplateId duckDb scriptNoteIds windows", "narration");
    require(grammar.narration, "opNotAllowed", "narration is not used in this profile");
    require(narration.voice === "user-recorded" || narration.voice === "generated", "badEnum", "narration voice");
    fields(narration.consent, "consentRecordId granted", "narration consent");
    identifier(narration.consent.consentRecordId, "consentRecordId");
    require(narration.consent.granted === true, "consentMissing", "narration needs recorded consent");
    if (narration.voice === "generated") {
      require(narration.disclosureTemplateId === "label.narration-generated", "disclosureMissing",
        "generated narration is labelled and disclosed");
    } else {
      require(narration.disclosureTemplateId === null, "badNarration", "only generated narration is labelled");
    }
    const stored = own(context.consents, narration.consent.consentRecordId);
    const need = narration.voice === "generated" ? "generated-voice" : "narration-voice";
    require(stored !== undefined && stored !== null && stored.granted === true && stored.scope.includes(need),
      "consentMissing", `narration needs a stored, granted ${need} consent; a plan cannot attest its own consent`);
    require(isInt(narration.duckDb) && narration.duckDb >= -24 && narration.duckDb <= -6, "badNarration",
      "court bed ducks by 6-24 dB under narration");
    require(Array.isArray(narration.scriptNoteIds) && narration.scriptNoteIds.length > 0, "badNarration",
      "a narration script is grounded in stored notes");
    for (const nid of narration.scriptNoteIds) {
      identifier(nid, "scriptNoteId");
      resolveNote(nid, context, "narration scriptNoteId");
    }
    checkWindows(narration.windows, total, "narration");
  }
  const music = audio.music;
  if (music !== null) {
    fields(music, "assetId rightsRecordId rightsScope windows", "music");
    require(grammar.music, "opNotAllowed", "music is not used in this profile");
    identifier(music.assetId, "music assetId");
    identifier(music.rightsRecordId, "rightsRecordId");
    require(Array.isArray(music.rightsScope) && music.rightsScope.every((x: J) => typeof x === "string")
      && music.rightsScope.includes("private-film"), "rightsMissing", "music needs rights for at least the private film");
    const stored = own(context.rights, music.rightsRecordId);
    require(stored !== undefined && stored !== null && stored.assetId === music.assetId
      && music.rightsScope.every((s: string) => stored.scope.includes(s)), "rightsMissing",
    "music needs a stored rights record for this asset covering every claimed scope");
    checkWindows(music.windows, total, "music");
  }
}

/** Every change of bed source sits on a segment boundary with fades (see the reference's docstring). */
function checkBedSwitches(pieces: Piece[], order: SegInfo[], outFps: F): void {
  const starts = new Map<number, SegInfo>(order.map((o) => [o.in, o]));
  for (let i = 0; i + 1 < pieces.length; i++) {
    const a = pieces[i];
    const b = pieces[i + 1];
    const srcA = a.route === "silence" ? null : a.raw.sourceId;
    const srcB = b.route === "silence" ? null : b.raw.sourceId;
    if (srcA === srcB && (srcA === null || a.sIn! + a.n! === b.sIn)) continue;
    const seg = starts.get(b.in);
    require(seg !== undefined, "bedSwitchNotAtBoundary",
      `the bed changes source at output frame ${b.in}, inside a segment; switch only at a boundary`);
    const tr = seg.seg.transitionIn;
    let needOut: number;
    let needIn: number;
    if (tr.type === "cut") {
      needOut = srcA !== null ? 20 : 0;
      needIn = srcB !== null ? 20 : 0;
    } else {
      const hOut = Math.floor(tr.frames / 2);
      const hIn = tr.frames - hOut;
      needOut = F.from(hIn * 1000).div(outFps).ceil();
      needIn = F.from(hOut * 1000).div(outFps).ceil();
    }
    require(a.raw.fadeOutMs >= needOut && b.raw.fadeInMs >= needIn, "fadeTooShort",
      `bed switch at output frame ${b.in} (${tr.type}) needs fades of at least ${needOut} ms out and ${needIn} ms in`);
  }
}

function checkWindows(windows: J, total: number, label: string): void {
  require(Array.isArray(windows) && windows.length >= 1 && windows.length <= 64, "badWindows",
    `${label} needs 1-64 windows`);
  let prev = 0;
  for (const w of windows) {
    fields(w, "outputInFrame outputOutFrame", `${label} window`);
    const a = integer(w.outputInFrame, "window in");
    const b = integer(w.outputOutFrame, "window out", 1);
    require(prev <= a && a < b && b <= total, "badWindows", `${label} windows must be ordered and inside the film`);
    prev = b;
  }
}
