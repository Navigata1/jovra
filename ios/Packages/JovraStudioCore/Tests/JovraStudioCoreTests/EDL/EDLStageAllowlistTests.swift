import Foundation
import Testing
import JovraStudioCore

/// SD6b: the stage allowlist is separate from the contract. A plan the contract accepts can still use an operation the
/// app has not enabled yet; that is `stageNotEnabled`, one finding per operation.
@Suite("EDL stage allowlist (SD6b)")
struct EDLStageAllowlistTests {
    @Test("S1 enables exactly the spec's list")
    func s1List() {
        let expected: Set<String> = [
            "live", "broll", "replay", "freeze", "card", "transition.cut", "transition.dissolve", "transition.dip",
            "overlay.score", "overlay.metric", "overlay.note", "overlay.cue", "overlay.annotation", "grade.none",
            "primary-bed", "hold-bed", "silence",
        ]
        #expect(Set(EDLStageAllowlist.s1.enabled.map(\.rawValue)) == expected)
        #expect(EDLStageAllowlist.enabledInProduct == .s1)
    }

    @Test("the Rally Pulse 9:16 fixture is valid under the contract and refused by S1 for reframe and music")
    func rallyPulseIsAheadOfS1() throws {
        let plan = try EDLTestFixtures.json("records/edit-plan.rally-pulse-portrait.json")
        #expect(try EDLTestFixtures.validator().validate(plan, context: EDLTestFixtures.context()).isEmpty)
        let refusals = EDLStageAllowlist.s1.refusals(plan)
        for finding in refusals { print("  rally-pulse-portrait under S1: \(finding)") }
        #expect(refusals.allSatisfy { $0.code == .stageNotEnabled })
        let refused = Set(refusals.map { $0.message.components(separatedBy: " ").first ?? "" })
        #expect(refused.isSuperset(of: ["reframe", "music"]))
        // the fixture's other ahead-of-S1 operations are S2's: a second angle and its alternate court bed
        #expect(refused == ["reframe", "music", "multi-angle", "alt-bed"])
    }

    @Test("operations are read from the plan's fields")
    func operationsOfRallyPulse() throws {
        let plan = try EDLTestFixtures.json("records/edit-plan.rally-pulse-portrait.json")
        #expect(EDLStageAllowlist.operations(in: plan).map(\.rawValue) == [
            "alt-bed", "card", "grade.none", "hold-bed", "live", "multi-angle", "music", "overlay.score", "primary-bed",
            "reframe", "transition.cut", "transition.dissolve",
        ])
    }

    @Test("a stage that enables every operation the plan uses refuses nothing")
    func enablingFlipsOneEntry() throws {
        let plan = try EDLTestFixtures.json("records/edit-plan.rally-pulse-portrait.json")
        var enabled = EDLStageAllowlist.s1.enabled
        enabled.insert(.reframe)
        #expect(EDLStageAllowlist(enabled: enabled).refusals(plan).count == 3)
        enabled.formUnion([.music, .multiAngle, .altBed])
        #expect(EDLStageAllowlist(enabled: enabled).refusals(plan).isEmpty)
    }

    @Test("narration and the warm grade are refused in S1")
    func laterStageLanes() throws {
        let coach = try EDLTestFixtures.json("records/edit-plan.coach-cut-serve.json")
        #expect(EDLStageAllowlist.s1.refusals(coach).map { $0.message.components(separatedBy: " ").first ?? "" }
            .contains("narration"))
        let memories = try EDLTestFixtures.json("records/edit-plan.court-memories-storyboard.json")
        #expect(EDLStageAllowlist.s1.refusals(memories).map { $0.message.components(separatedBy: " ").first ?? "" }
            .contains("grade.warm-court-1"))
    }
}
