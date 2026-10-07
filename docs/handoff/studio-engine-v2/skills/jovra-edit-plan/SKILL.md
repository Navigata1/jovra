---
name: jovra-edit-plan
description: Compile a grounded JOVRA story brief into a typed, bounded edit decision list with source times, session context, overlays and explicit audio routing.
---

# Compile the edit plan

Read `references/contract.md`, the selected story profile and the current source/keeper catalogs. Use `../../examples/edit-plan.sample.json` only as a fictional structural example. `../../scripts/validate_edit_plan.py` implements a limited planning check; it does not verify footage, alignment, rights or editorial truth.

Resolve each beat to approved source IDs/windows or omit it. Map output frames separately from source proxy frames and session events. Use one rational output frame clock; represent rounding explicitly. Keep live action at original speed. A slow replay is labelled and outside the original keeper. A freeze, title or transition is an explicit supported operation, not hidden repeated frames.

Bind plan identity to project/source manifest, sync revision, event revision, profile revision and output spec. Keep stale revisions out of a ready export. Overlays reference stored point/metric/note records; the renderer derives display content rather than trusting model-generated numbers. No unknown source, gap-spanning cut, unsupported effect, invented quote or unapproved music.

Require one declared audio route. Changing video angle does not silently change court audio. Keep scene orientation and rally integrity. For advanced multi-track audio, freeze frames, annotated replays, titles and reframing, extend the contract and validator before enabling them; the supplied basic validator intentionally accepts only ordinary 1× source cuts with one audio bed.

The model emits data from an allowlist, never shell commands, filter strings, executable JavaScript, local paths, signed URLs or credentials. Validation runs before any rendering/spend. Enforce source/window bounds, complete output coverage, source hashes, supported operations, frame/output limits and access rights using trusted manifests on the server.

Output: a readable story brief, typed EDL, validation findings, omitted beats and estimated job requirements. A valid plan remains pending actual-source verification and content review.
