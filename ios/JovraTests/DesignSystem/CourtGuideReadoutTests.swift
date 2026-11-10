#if DEBUG
import JovraCore
import Testing
@testable import Jovra

/// T13, story 66: what the gallery says under the framing guide. The good state is shown for a good check only; a
/// fit with no residual to print (refused, or measured lines beyond its horizon) says so and never reads 0.0 px.
/// The 5.4 px figure is `spec/fixtures/calibration/C04-fit-check.json` (5.443457562 for the same 11 px offset).
@Suite("Court guide readout")
struct CourtGuideReadoutTests {
    private let trueCorners = SyntheticCourtCamera.trueCorners

    private func corners(farRight: VideoPixel) -> [VideoPixel] {
        [trueCorners[0], trueCorners[1], farRight, trueCorners[3]]
    }

    @Test("brackets on the true corners pass with a 0.0 px residual")
    func exact() {
        let readout = CourtGuideReadout(corners: trueCorners)
        #expect(readout.passes)
        #expect(readout.residual == "Untapped lines: 0.0 px RMSE, limit 3 px")
    }

    @Test("a far corner 11 px off is a poor fit with its residual")
    func poor() {
        let readout = CourtGuideReadout(corners: corners(farRight: VideoPixel(x: trueCorners[2].x + 9, y: trueCorners[2].y - 7)))
        #expect(!readout.passes)
        #expect(readout.residual == "Untapped lines: 5.4 px RMSE, limit 3 px")
    }

    @Test("a bracket dragged across the court never reads as the good state or as 0.0 px",
          arguments: [CourtGuideReadout.twistedFarRight, VideoPixel(x: SyntheticCourtCamera.trueCorners[2].x, y: 1000)])
    func twisted(farRight: VideoPixel) {
        let readout = CourtGuideReadout(corners: corners(farRight: farRight))
        #expect(!readout.passes)
        #expect(readout.residual == "Untapped lines: beyond the horizon, limit 3 px")
    }

    @Test("the far brackets swapped read the same")
    func swapped() {
        let readout = CourtGuideReadout(corners: [trueCorners[0], trueCorners[1], trueCorners[3], trueCorners[2]])
        #expect(!readout.passes)
        #expect(readout.residual == "Untapped lines: beyond the horizon, limit 3 px")
    }

    @Test("four brackets on one spot are no fit, not a pass")
    func refused() {
        let readout = CourtGuideReadout(corners: Array(repeating: trueCorners[0], count: 4))
        #expect(!readout.passes)
        #expect(readout.residual == "Untapped lines: no fit through these corners")
    }

    @Test("with no line pixels measured nothing passes")
    func unmeasured() {
        let readout = CourtGuideReadout(corners: trueCorners, observations: [])
        #expect(!readout.passes)
        #expect(readout.residual == "Untapped lines: not measured")
    }
}
#endif
