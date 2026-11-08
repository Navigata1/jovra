import Foundation
import Testing
import JovraStudioCore

/// STU-02 (S11): the EDL module consumes the `edl-context` vectors (an EDL checked against a patched trusted context:
/// Camera 2 split into two adjacent coverage intervals, as after a restart). `jovra.edit-plan/2` itself is decoded by
/// ContractsConsumer; its record rules are checked by EDLParityTests.
struct EDLConsumer: StudioFixtureConsumer {
    var vectorCheckers: [String: @Sendable (StudioJSONValue) throws -> Void] {
        ["edl-context": { try EDLConsumer.checkContextVector($0) }]
    }

    struct VectorError: Error, CustomStringConvertible { let description: String }

    /// Runs one case and compares it with the reference's stored expectation and the hand-derived assertions
    /// (`edl_cases.check_edl_context_vector`).
    @discardableResult
    static func checkContextVector(_ item: StudioJSONValue) throws -> [EDLFinding] {
        guard case .string(let id)? = item["id"], case .string(let planPath)? = item["plan"], let planPatch = item["planPatch"],
              let contextPatch = item["contextPatch"], let expect = item["expect"], let hand = item["assert"] else {
            throw VectorError(description: "malformed edl-context case")
        }
        let plan = try StudioJSONPatch.apply(planPatch, to: EDLTestFixtures.json(planPath))
        let contextJSON = try StudioJSONPatch.apply(contextPatch, to: EDLTestFixtures.context().json)
        let findings = try EDLTestFixtures.validator().validate(plan, contextJSON: contextJSON)
        let got: StudioJSONValue = findings.first.map { .object([StudioJSONMember(key: "rejectCode", value: .string($0.code.rawValue))]) }
            ?? .object([StudioJSONMember(key: "status", value: .string("valid-plan"))])
        print("  edl-context \(id): \(findings.first?.description ?? "valid-plan")")
        guard got == expect else {
            throw VectorError(description: "edl-context \(id): Swift gives \(String(decoding: got.serialized(), as: UTF8.self)), "
                              + "reference stored \(String(decoding: expect.serialized(), as: UTF8.self))")
        }
        // hand rule: the interval holding the first frame is the half-open one with inFrame <= frame < outFrame
        let seg = plan["segments"].flatMap { if case .array(let s) = $0 { s[4] } else { nil } }
        if case .number(let expected)? = hand["sessionInUs"], let seg, case .number(let sIn)? = seg["sourceInFrame"],
           case .string(let sourceId)? = seg["sourceId"], case .array(let coverage)? = contextJSON["sources"]?[sourceId]?["coverage"] {
            let frame = sIn.int64 ?? -1
            let holder = coverage.first { c in
                guard case .number(let a)? = c["inFrame"], case .number(let b)? = c["outFrame"] else { return false }
                return (a.int64 ?? 0) <= frame && frame < (b.int64 ?? 0)
            }
            if case .number(let start)? = holder?["sessionStartUs"], holder?["inFrame"] == .number(sIn) {
                let valid = findings.isEmpty
                guard valid == (expected == start) else {
                    throw VectorError(description: "edl-context \(id): the first frame of an interval must map to that interval's sessionStartUs")
                }
            }
        }
        if hand["handlesCrossRestart"] == .bool(true), findings.first?.code != .transitionHandle {
            throw VectorError(description: "edl-context \(id): a dissolve across a restart must be refused for its handles")
        }
        return findings
    }
}
