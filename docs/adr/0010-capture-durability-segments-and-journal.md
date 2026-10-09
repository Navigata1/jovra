# Capture durability: segments, a write-ahead journal and a recovery scan at launch

A recording is an ordered list of **segments** with **gaps** between them, described by a write-ahead journal next to
the media (atomic temp-then-rename, ADR-0002). The journal records each segment's start, a heartbeat of how far media is
saved ("Saved through mm:ss"), every interruption and every heat-ladder rung. Any interruption (call, backgrounding,
heat, camera error) closes the current segment and opens a gap; it never ends the session. The first engine is
`AVCaptureMovieFileOutput` with a movie fragment interval of about 2 s set before recording starts. At every launch a
recovery scan reconciles the journal with the files on disk and checks each segment by **decoding to the end**, because
the finish callback never fires after a crash, jetsam kill or power loss, and a torn file can report a duration it
cannot play.

Recording depends on nothing but the camera and local storage. It never waits on analysis (nothing is inferred on
court; analysis runs after), network (no upload while recording), the microphone (optional; silent recording works),
a Watch or Live Activity, or an account.

## Considered Options

- One long file with the default 10 s fragments: a crash costs up to 10 s, and a single bad file loses the session.
- `AVAssetWriter` writing fMP4 segments: tighter loss bound and segments that can be archived while recording, but the
  app then owns audio/video sync and back-pressure. Kept behind the same `RecordingEngine` seam as the fallback if the
  device soak test fails.

## Consequences

Replay, export and analysis work on a segment timeline in session time, never file time, and gaps are visible in replay.
The pass bar (no more than 3 s lost per crash, no unrecoverable session, journal and video within one frame) can only be
proven on hardware; simulator runs through the fixture camera (ADR-0012) prove the pipeline, not durability.

## Amendment — 2026-10-09: one sample-buffer recording pipeline

The finalized iOS v1 specification (D9) and T15 supersede the earlier mechanism above: use an `AVAssetWriter`
segment pipeline for both `CameraSource` and `FixtureCamera`, with fragmented MP4 output at approximately two-second
intervals behind the same atomic write-ahead journal. The camera supplies video/audio sample buffers; the simulator
fixture supplies decoded sample buffers. A fixture recording must pass through the real writer and journal, never
copy an already completed movie and label it a live capture. The source adapter changes; recording, persistence,
recovery and gap semantics do not.

The original durability goal and device-only loss-bound gate remain unchanged. Simulator decode/recovery results
do not establish the hardware crash-loss bound, lens selection, focus locks, thermal endurance or power-loss safety.
