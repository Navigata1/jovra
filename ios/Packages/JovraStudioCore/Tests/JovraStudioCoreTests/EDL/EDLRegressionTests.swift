import Foundation
import Testing
@testable import JovraStudioCore

/// The verifier's repros for the round-2 review findings, each rejected with its own code. Each test names the rule it
/// pins; reverting that rule makes that test fail (the scratch-revert transcript is in
/// evidence/ios/s11-studio-edl-validator-swift).
@Suite("EDL validator: review findings 0, 1, 2, 7 and 8")
struct EDLRegressionTests {
    static func codes(_ file: String, _ id: String) throws -> [EDLFindingCode] {
        let item = try EDLTestFixtures.invalidCase(file, id)
        return try EDLTestFixtures.validator().validate(item.plan, context: EDLTestFixtures.context()).map(\.code)
    }

    /// One edl-context vector, validated by the Swift port only (the stored expectation is not consulted here, so the
    /// literal codes below are the test's own claim).
    static func vector(_ id: String) throws -> [EDLFindingCode] {
        let file = try EDLTestFixtures.json("vectors/edl-context.json")
        guard case .array(let cases)? = file["cases"], let item = cases.first(where: { $0["id"] == .string(id) }),
              case .string(let planPath)? = item["plan"], let planPatch = item["planPatch"], let contextPatch = item["contextPatch"]
        else { throw EDLConsumer.VectorError(description: "no edl-context case \(id)") }
        let plan = try StudioJSONPatch.apply(planPatch, to: EDLTestFixtures.json(planPath))
        let context = try StudioJSONPatch.apply(contextPatch, to: EDLTestFixtures.context().json)
        return try EDLTestFixtures.validator().validate(plan, contextJSON: context).map(\.code)
    }

    @Test("finding 0: the first frame of a restarted interval maps through that interval (half-open coverage)")
    func restartFrameMapping() throws {
        // c05 on Camera 2's first restarted frame: sessionInUs is the restart's own session start (2 000 000 000 µs)
        let firstFrame = try Self.vector("restart-first-frame")
        #expect(firstFrame == [])
        // the previous interval's extrapolated end (1 800 660 021 µs) is not the session time of that frame
        let extrapolated = try Self.vector("restart-extrapolated-session")
        #expect(extrapolated == [.sessionTimeMismatch])
        let endsAtRestart = try Self.vector("window-ends-at-restart")
        #expect(endsAtRestart == [])
        let dissolve = try Self.vector("dissolve-across-restart")
        #expect(dissolve == [.transitionHandle])
    }

    @Test("finding 0: a frame looked up without its window's interval maps half-open (freezes and overlay moments)")
    func restartFrameLookup() throws {
        // Camera 2 of the coach plan, split as the edl-context vectors split it: [0, 108000) and [108000, 216000),
        // the second starting at session 2 000 000 000 µs.
        let file = try EDLTestFixtures.json("vectors/edl-context.json")
        guard case .array(let cases)? = file["cases"], case .array(let patch)? = cases.first?["contextPatch"],
              let coverage = patch.first?["value"],
              case .array(let sources)? = try EDLTestFixtures.json("records/edit-plan.coach-cut-serve.json")["sources"]
        else { Issue.record("fixture shape"); return }
        let camera2 = try EDLPlanSource(sources[1].setting("coverage", to: coverage))
        #expect(camera2.coverage.count == 2)
        #expect(camera2.sessionUs(108_000) == EDLFraction(2_000_000_000))
        // the exclusive end of the last interval is still on the clock; one frame past it is not
        #expect(camera2.sessionUs(216_000) != nil)
        #expect(camera2.sessionUs(216_001) == nil)
    }

    @Test("finding 1: re-showing a live moment as a second 1x live segment is a replay without its label")
    func reShownLiveMoment() throws {
        let got = try Self.codes("coach-cut-serve", "replay-as-unlabelled-live")
        #expect(got == [.replayWithoutLabel])
    }

    @Test("finding 2: a null keeperId does not switch contact protection off")
    func keeperIdNulledOverContact() throws {
        let got = try Self.codes("court-memories-storyboard", "contact-unprotected-without-keeper")
        #expect(got == [.contactUnprotected])
    }

    @Test("finding 7: the alternate bed returning mid-segment, and an alternate bed at a dissolve without an audio dip")
    func altBedSwitches() throws {
        let returnsMidSegment = try Self.codes("coach-cut-serve", "bed-returns-mid-segment")
        #expect(returnsMidSegment == [.bedSwitchNotAtBoundary])
        let atDissolve = try Self.codes("rally-pulse-portrait", "alt-bed-at-dissolve")
        #expect(atDissolve == [.fadeTooShort])
    }

    @Test("finding 8: a plan naming another project is refused against this project's records")
    func foreignProjectId() throws {
        let got = try Self.codes("coach-cut-serve", "plan-for-another-project")
        #expect(got == [.projectMismatch])
    }
}
