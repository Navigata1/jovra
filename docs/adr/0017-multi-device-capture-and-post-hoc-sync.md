# Multi-device capture records independently; synchronization is computed after capture

Status: accepted (2026-10-07).

**Build your match** uses one primary baseline camera plus up to five more phones: the opposite baseline and the four
corners, all outside the playing area. Each phone records **independently to its own storage**, using the existing
segment, journal and recovery pipeline (ADR-0010). Recording never depends on pairing, the host, the network or
another phone. If a link drops, every capture keeps running. Sources can also be imported later from Photos or Files,
including an old single-camera match.

- **One live analysis feed.** Only the primary angle is analysed on court. The other cameras send status and, at most,
  a still every few seconds, labelled with its age. About five stills every 5 s is roughly 0.32 Mbit/s, while five
  live 720p streams would be about 12.5 Mbit/s and heat every phone (INFERRED arithmetic, multicam-sync §2.6). Full
  multi-angle analysis runs after capture.
- **Pairing is coordination, not synchronization.** One shared room protocol ("JOVRA Room v1") carries roles, real
  recording acknowledgements, telemetry, stills and clock pings over several transports:
  - LAN TLS/TCP, found by Bonjour/DNS-SD on both platforms;
  - an opt-in cloud room on Supabase Realtime, behind ADR-0014 gates;
  - MultipeerConnectivity, as an Apple-only experiment.

  Phones join with a single-use QR code that expires within 10 minutes, carries the TLS key fingerprint and needs the
  host to tap approve. A host's "start all" does not prove that any camera started; only acknowledgements do.
- **Clock hints are only hints.** Each segment's file-zero host time is journalled. On iOS it is derived from
  `AVAssetWriter.startSession(atSourceTime:)` through `CMSyncConvertTime`, or from the start-PTS delegate (iOS 18.2+).
  NTP-style pings can seed alignment but never finalize it.

**The match clock and the SyncMap.** The match clock is light time, anchored to the primary angle's video clock, with
its origin at the earliest covered instant. It is stored as integer microseconds. Source times are stored as
rationals. The core `timeMs` schema stays unchanged, and so does the comparison "sync point" in the glossary.

Each source maps onto the match clock through piecewise affine maps, `t_match = offset + (1 + drift)·t_source`, with
one drift rate per device. The map is fitted by robust regression on **anchors**: visible contacts, bounces, a
net-centre clap or ball drop, and manual markers. The versioned **SyncMap** records, per source:
- the offset and drift;
- the anchors and their residuals;
- a 95% prediction band;
- the coverage gaps and discontinuities;
- the review status.

A map never extends into a coverage gap.

**Speed-of-sound correction.** Audio anchors are corrected for sound travel using court geometry, with role priors
from the point-event log (server, end, deuce or ad court). Between the two baseline phones the uncorrected bias flips
by about ±69 ms depending on the hitter. That is more than 4 frames at 60 fps (computed at 343 m/s, multicam-sync
§4.4). Audio-only alignment without this correction is never auto-approved.

A map is auto-approved only when its band stays within half an output frame over the interval used and its anchors
cover the first, middle and last thirds of that interval. Otherwise the source is marked Needs review. Reviewed means
a person checked it. Validated is reserved for a benchmarked sync capability (ADR-0004).

## Considered Options

- **Hardware or genlock-style sync from a shared start command.** Rejected. Phones have no shared capture clock, and a
  network start has jitter of milliseconds to tens of milliseconds.
- **Plain audio cross-correlation.** Rejected as the sole method. In a synthetic run it locked onto the rally rhythm
  1,178 ms off. Event pairing with geometry correction recovered the offset within 0.4 ms (OBSERVED in a scratch
  simulation, not field evidence; multicam-sync §4.10).
- **Six live streams into one phone.** Rejected because of heat, bandwidth and battery. It is also not needed for
  replay.

## Consequences

Sync is tested first with a synthetic multi-angle generator: exact ground truth, embedded frame IDs, and mutation
tests that must catch a one-frame error. The default drift range is 1 to 50 ppm; the UI sample's 300 ppm is kept as a
stress case. Two-view real footage can only reach Reviewed. Six-phone endurance and wireless behaviour can only be
proven on physical devices. A single old match cannot supply other angles, and none is ever synthesized and labelled
as recorded.

Sources: `docs/research/studio/multicam-sync.md` §§0–4, 7–8; RFC 5905 https://www.rfc-editor.org/rfc/rfc5905 ;
https://developer.apple.com/documentation/avfoundation/avassetwriter/startsession(atsourcetime:) ;
https://developer.apple.com/documentation/coremedia/cmsyncconverttime(_:from:to:) ;
https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy ;
https://developer.android.com/reference/android/net/nsd/NsdManager ;
https://supabase.com/docs/guides/realtime/limits .
