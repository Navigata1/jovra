---
name: jovra-media-ingest-sync
description: Prepare one to six JOVRA camera sources, preserving originals and mapping normalization, coverage, offset and drift for reviewed replay and editing.
---

# Source preparation and synchronization

Record a source manifest from actual files, not labels inferred from filenames. Capture immutable ID/hash, original size/duration, codec, dimensions, rotation, colour/HDR, rational timebase, timestamp behaviour, audio availability, lens and available capture hints. Preserve originals and keep them outside all destructive output targets.

Normalize proxies for the chosen renderer’s measured requirements; retain original-PTS ↔ proxy-frame ↔ session-time mappings. Apply rotation once, handle HDR intentionally, and check decoded frame clocks rather than assuming average FPS proves constant frame rate. All normalized timestamps, crops and audio changes have provenance.

One source requires no multi-view claim. For several sources, align against actual visual/audio anchors, review offset and drift at start/middle/end, and use piecewise maps across restarts. Court-distance sound travel and phone clocks can bias a clap alignment. A shared pairing/start button does not establish frame synchronization.

Emit a SyncMap with source ID, covered session intervals, alignment transform/version, anchors/residuals, discontinuities and review status. Preserve missing spans. The initial two-view target is within one output frame on reviewed visible anchors; flag uncertain intervals. Six-device readiness requires real field footage and device endurance checks.

Keepers reference exact source windows and the corresponding session events. Catalogue genuine B-roll separately, including source rights and whether it depicts this match. Deduplicate the same point across angles; a view is additional evidence, not another statistical event. Never synthesize an alternate view of a single-camera recording as captured footage.

If adapting the existing editor, reread its current constraints before calling it. Its inspected draft interface requires compatible constant-frame media, identical dimensions/FPS, no rotation and explicit source hashes; normalization is a separate stage. Output: SourceManifest, SyncMap, KeeperCatalog, BrollCatalog and unresolved source gaps.
