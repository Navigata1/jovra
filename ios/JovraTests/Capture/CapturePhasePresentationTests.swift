import JovraMedia
import XCTest
@testable import Jovra

final class CapturePhasePresentationTests: XCTestCase {
    func testEveryEnginePhaseHasTruthfulUserCopyBeforeSaveAcknowledgment() {
        let cases: [(CapturePhase, String)] = [
            (.idle, "Preparing your recording"), (.ready, "Frame your court"),
            (.recording, "Recording"), (.pausing, "Pausing recording"),
            (.paused, "Paused · Not recording"), (.stopping, "Stopping and saving"),
            (.stopped, "Stopped · Not recording")
        ]
        for (phase, expected) in cases {
            XCTAssertEqual(CapturePhasePresentation.title(for: phase), expected, "phase \(phase)")
        }
        XCTAssertFalse(CapturePhasePresentation.title(for: .stopped).contains("Saved"))
    }
}
