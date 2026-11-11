/**
 * The heuristic planner adapter (contract planner kind `heuristic`): a server copy of the device's StoryDirector,
 * RulesPlanner, trust check, grammar lint, EDL compiler and edit-plan/2 validator, byte for byte with the S06 and S07
 * reference vectors (spec/reference/studio). The jovra-internal Workflow's plan step imports this module; model
 * adapters (S89) sit beside it and always fall back to it.
 *
 * Pure and deterministic: no network, no clock, no randomness, no file access. Every input is plain data built from
 * stored records; every output is canonical JSON.
 */

export { canonicalJson, canonicalSha256, Reject, type J } from "./core.ts";
export { brief, lint, CARD_TEMPLATES, PLANNER, profilesFrom, type Finding } from "./director.ts";
export { check, plan, type Beat, type PlanResult } from "./planner.ts";
export { compilePlan, OPS, STAGES } from "./compile.ts";
export { validate, type Validation } from "./edl.ts";
export { compare as compareProgress } from "./progress.ts";
export { rank as rankKeepers } from "./keepers.ts";

export const ADAPTER = { kind: "heuristic", adapterVersion: "jovra-planner@0.1.0", modelId: null } as const;
