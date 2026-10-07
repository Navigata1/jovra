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
