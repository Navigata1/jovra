import Foundation
import Testing
import JovraStudioCore

/// STU-02 (S11): the Swift validator gives the reference's code on every shared case (spec/reference/studio/edl.py).
@Suite("EDL validator: parity with edl.py")
struct EDLParityTests {
    /// The reference's code for each schema-layer case, from running `edl.validate` on them (the fixtures store only
    /// `layer: schema` for these; the Swift validator refuses them on its own, not only through the decoder).
    static let schemaLayerCodes: [String: String] = [
        "coach-cut-serve#free-text-card": "badTemplate",
        "court-memories-storyboard#executable-command": "forbiddenField",
        "court-memories-storyboard#approval-in-plan": "forbiddenField",
        "court-memories-storyboard#signed-url-source": "forbiddenField",
        "court-memories-storyboard#unlabelled-speed": "badSpeed",
        "court-memories-storyboard#wipe-transition": "transitionNotAllowed",
        "court-memories-storyboard#copied-score-digits": "unknownField",
        "court-memories-storyboard#aspect-21-9": "badOutput",
        "court-memories-storyboard#model-guessed-reframe": "reframeNotReviewed",
    ]

    static func key(_ item: EDLTestFixtures.InvalidCase) -> String {
        "\(item.file.replacingOccurrences(of: "edit-plan.", with: "").replacingOccurrences(of: ".invalid.json", with: ""))#\(item.id)"
    }

    @Test("every edit-plan invalid case fails with the reference's finding code (zero mismatches)")
    func invalidCasesMatchTheReference() throws {
        let validator = try EDLTestFixtures.validator(), context = try EDLTestFixtures.context()
        var table: [String: (expected: Int, matched: Int)] = [:]
        var mismatches: [String] = []
        var total = 0
        for item in try EDLTestFixtures.invalidCases() {
            let expected = item.code ?? Self.schemaLayerCodes[Self.key(item)]
            let got = validator.validate(item.plan, context: context).first?.code.rawValue
            total += 1
            let code = expected ?? "(no reference code)"
            table[code, default: (0, 0)].expected += 1
            if got == expected {
                table[code, default: (0, 0)].matched += 1
            } else {
                mismatches.append("\(Self.key(item)) [\(item.layer)]: Swift \(got ?? "valid"), reference \(code)")
            }
        }
        print("EDL parity: \(total) edit-plan invalid cases, \(total - mismatches.count) match, \(mismatches.count) mismatch(es)")
        print("  code                         cases  matched")
        for (code, row) in table.sorted(by: { $0.key < $1.key }) {
            print("  \(code.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(row.expected).padding(toLength: 6, withPad: " ", startingAt: 0)) \(row.matched)")
        }
        for m in mismatches { print("  MISMATCH \(m)") }
        #expect(total == 79)
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("every valid edit-plan record passes as stored")
    func validRecordsPass() throws {
        let validator = try EDLTestFixtures.validator(), context = try EDLTestFixtures.context()
        let plans = try EDLTestFixtures.plans()
        #expect(plans.count == 7)
        for (name, plan) in plans {
            let summary = try validator.check(plan, context: context)
            print("  valid \(name): \(summary.segments) segments, \(summary.durationSeconds) s, motion \(summary.motionEffects), "
                  + "needsCleanAlternate \(summary.needsCleanAlternate)")
            #expect(summary.needsCleanAlternate == (name.hasSuffix(".clean") ? false : summary.motionEffects))
        }
    }

    @Test("the two clean-alternate pairs are reproduced byte for byte by cleanAlternate")
    func cleanAlternatePairs() throws {
        let validator = try EDLTestFixtures.validator(), context = try EDLTestFixtures.context()
        for name in ["court-memories-storyboard", "rally-pulse-portrait"] {
            let plan = try EDLTestFixtures.json("records/edit-plan.\(name).json")
            let stored = try StudioFixtures.data("records/edit-plan.\(name).clean.json")
            let derived = EDLValidator.cleanAlternate(plan)
            #expect(EDLTestFixtures.pythonIndented(derived) == stored, "\(name).clean differs from the derived alternate")
            let summary = try validator.check(derived, context: context)
            #expect(summary.motionEffects == false && summary.needsCleanAlternate == false)
            print("  clean alternate \(name): \(stored.count) bytes, identical")
        }
    }

    @Test("the typed clean alternate equals the stored typed record")
    func typedCleanAlternate() throws {
        let plan = try EDLTestFixtures.record(EditPlan.self, "edit-plan.rally-pulse-portrait")
        let stored = try EDLTestFixtures.record(EditPlan.self, "edit-plan.rally-pulse-portrait.clean")
        #expect(try EDLValidator.cleanAlternate(plan) == stored)
        #expect(try EDLTestFixtures.validator().validate(stored, context: EDLTestFixtures.context()).isEmpty)
    }

    @Test("validate() without a trusted context returns contextMissing")
    func contextIsRequired() throws {
        let validator = try EDLTestFixtures.validator()
        let plan = try EDLTestFixtures.json("records/edit-plan.coach-cut-serve.json")
        #expect(validator.validate(plan, context: nil).map(\.code) == [.contextMissing])
        #expect(validator.validate(plan, contextJSON: nil).map(\.code) == [.contextMissing])
        #expect(validator.validate(plan, contextJSON: .object([])).map(\.code) == [.contextMissing])
        guard case .object(let members) = try EDLTestFixtures.context().json else { Issue.record("context JSON"); return }
        let partial = StudioJSONValue.object(members.filter { $0.key != "references" })
        #expect(validator.validate(plan, contextJSON: partial).map(\.code) == [.contextMissing])
        // and the full context accepts the same plan
        #expect(validator.validate(plan, contextJSON: .object(members)).isEmpty)
    }

    @Test("a boolean speed is badSpeed in the validator itself, not only in the schema layer")
    func booleanSpeedIsRefused() throws {
        let plan = try EDLTestFixtures.json("records/edit-plan.court-memories-storyboard.json")
        let bad = try StudioJSONPatch.apply(StudioJSONParser.parse(Data(#"[{"op": "replace", "path": "/segments/1/speed", "value": {"num": true, "den": 1}}]"#.utf8)), to: plan)
        #expect(try EDLTestFixtures.validator().validate(bad, context: EDLTestFixtures.context()).map(\.code) == [.badSpeed])
    }

    @Test("the trusted context is built from the stored records, with the reviewed sync map's coverage")
    func contextFromRecords() throws {
        let context = try EDLTestFixtures.context()
        #expect(context.projectId == "sample-court-day")
        #expect(context.current == ["sourceManifestRevision": 1, "syncRevision": 2, "eventRevision": 3,
                                    "keeperCatalogRevision": 1, "brollCatalogRevision": 1])
        let camera2 = try #require(context.sources["camera-2"])
        #expect(camera2.role == "match" && camera2.hasAudio)
        // the reviewed sync piece of Camera 2: offset 119 837 µs and a 300 ppm drift
        guard case .array(let coverage) = camera2.coverage, let first = coverage.first else { Issue.record("coverage"); return }
        #expect(first["sessionStartUs"] == .number(try #require(Self.number("119837"))))
        #expect(first["rate"]?["num"] == .number(try #require(Self.number("1000300102"))))
        #expect(context.sources["broll-1"]?.coverage == (try StudioJSONParser.parse(Data(
            #"[{"inFrame":0,"outFrame":1800,"sessionStartUs":null,"rate":null}]"#.utf8))))
        // a round trip through the JSON form keeps the context
        #expect(try EDLTrustedContext(json: context.json) == context)
    }

    @Test("every finding code except the stage gate is a code edl.py raises")
    func findingCodesAreTheReferences() throws {
        let url = StudioFixtures.repositoryRoot().appendingPathComponent("spec/reference/studio/edl.py")
        let source = try String(contentsOf: url, encoding: .utf8)
        for code in EDLFindingCode.allCases where code != .stageNotEnabled {
            #expect(source.contains("\"\(code.rawValue)\""), "\(code.rawValue) is not a code of edl.py")
        }
    }

    static func number(_ text: String) -> StudioJSONNumber? {
        if case .number(let n) = try? StudioJSONParser.parse(Data(text.utf8)) { return n }
        return nil
    }
}
