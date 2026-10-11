import CoreMedia
import JovraCore
import JovraMedia

// JovraStudioMedia: JOVRA Studio's AVFoundation / CoreMedia layer (docs/studio/DEVELOPING.md). This file is the
// package's smoke surface (S04). Ingest, proxies, anchors, the film renderer and verifier land in their own folders.

/// Exact source-clock arithmetic shared by Studio media code.
public enum StudioSourceTiming {
    /// The presentation time at which a source of `frameCount` frames at its nominal `rate` ends (the start of the
    /// frame after its last), in the rate's own timescale so no rounding is introduced.
    public static func nominalEnd(frameCount: Int, at rate: FrameRate) -> CMTime {
        CMTime(frame: frameCount, at: rate)
    }
}
