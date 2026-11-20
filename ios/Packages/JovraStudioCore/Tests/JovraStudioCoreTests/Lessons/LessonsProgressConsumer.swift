import Foundation
import JovraStudioCore

/// STU-14 (S36): `ProgressStoryBuilder.compare` replays the shared `progress-comparison` vectors with the reference's
/// outputs (`spec/reference/studio/progress.py`). `jovra.lesson/1` itself is decoded by ContractsConsumer (S10); the
/// lesson record rules are checked by LessonsRecordRulesTests.
struct LessonsProgressConsumer: StudioFixtureConsumer {
    var vectorCheckers: [String: @Sendable (StudioJSONValue) throws -> Void] {
        ["progress-comparison": { try LessonsProgressVectors.check($0) }]
    }
}

/// Runs one `progress-comparison` case the way `progress_cases.check_progress_vector` does: the Swift output must equal
/// the stored `expect` (the reference's output) and satisfy the hand-derived `assert` block. Expected values come from
/// the vector file, never from the Swift code.
enum LessonsProgressVectors {
    struct Mismatch: Error, CustomStringConvertible { let description: String }

    /// Words a proportion's change must never be stated in (`progress_cases.BANNED`).
    static let banned = ["improvement", "improved", "improve"]

    @discardableResult
    static func check(_ item: StudioJSONValue) throws -> StudioJSONValue {
        guard case .string(let id)? = item["id"], let input = item["input"], let expect = item["expect"],
              let hand = item["assert"], case .string(let stat)? = input["statDefinitionId"],
              let earlier = input["earlier"], let later = input["later"] else {
            throw Mismatch(description: "malformed progress-comparison case")
        }
        let got: StudioJSONValue
        do throws(ProgressRejection) {
            let comparison = try ProgressStoryBuilder.compare(stat, earlier: ProgressScope(json: earlier),
                                                              later: ProgressScope(json: later))
            got = json(comparison)
        } catch {
            got = .object([StudioJSONMember(key: "rejectCode", value: .string(error.code.rawValue))])
        }
        guard got == expect else {
            throw Mismatch(description: "progress-comparison \(id): Swift gives \(text(got)), reference stored \(text(expect))")
        }
        let problems = assertions(got, hand)
        guard problems.isEmpty else { throw Mismatch(description: "progress-comparison \(id): \(problems)") }
        print("  progress-comparison \(id): \(got["summary"].flatMap { if case .string(let s) = $0 { s } else { nil } } ?? got["claim"].map(text) ?? text(got))")
        return got
    }

    /// The hand-derived checks of `progress_cases._check_assertions`.
    static func assertions(_ got: StudioJSONValue, _ hand: StudioJSONValue) -> [String] {
        if let code = hand["rejectCode"] {
            return got["rejectCode"] == code ? [] : ["expected rejection \(text(code)), got \(text(got))"]
        }
        if got["rejectCode"] != nil { return ["rejected with \(text(got))"] }
        var problems: [String] = []
        let checks: [String: StudioJSONValue?] = [
            "comparable": got["comparable"], "reasons": got["reasons"], "claim": got["claim"],
            "deltaPercentagePoints": got["deltaPercentagePoints"], "deltaDisplay": got["deltaDisplay"],
            "summary": got["summary"],
            "pct": .array([got["earlier"]?["pct"] ?? .null, got["later"]?["pct"] ?? .null]),
            "earlierSelectionLabel": got["earlier"]?["selectionLabel"], "laterSelectionLabel": got["later"]?["selectionLabel"],
            "earlierDisplay": got["earlier"]?["display"],
        ]
        for (key, value) in checks {
            if let wanted = hand[key], wanted != value { problems.append("\(key): \(value.map(text) ?? "nil"), hand value \(text(wanted))") }
        }
        if case .array(let include)? = hand["reasonsInclude"], case .array(let reasons)? = got["reasons"] {
            for reason in include where !reasons.contains(reason) { problems.append("reason \(text(reason)) missing") }
        }
        if got["comparable"] == .bool(false), got["deltaPercentagePoints"] != .null || got["summary"] != .null {
            problems.append("a non-comparable result carries a delta")
        }
        let lowered = text(got).lowercased()
        if banned.contains(where: lowered.contains) { problems.append("output words a change as an improvement") }
        return problems
    }

    /// The comparison in the reference's member order, so it compares equal to the stored `expect`.
    static func json(_ c: ProgressComparison) -> StudioJSONValue {
        func side(_ s: ProgressSide) -> StudioJSONValue {
            .object([
                .init(key: "date", value: .string(s.date)),
                .init(key: "sessionIds", value: .array(s.sessionIds.map { .string($0) })),
                .init(key: "numerator", value: number(s.fraction.n)),
                .init(key: "denominator", value: number(s.fraction.d)),
                .init(key: "pct", value: s.fraction.pct.value.map(number) ?? .null),
                .init(key: "display", value: .string(s.display)),
                .init(key: "selectionLabel", value: s.selectionLabel.map { .string($0) } ?? .null),
            ])
        }
        return .object([
            .init(key: "statDefinitionId", value: .string(c.statDefinitionId)),
            .init(key: "earlier", value: side(c.earlier)),
            .init(key: "later", value: side(c.later)),
            .init(key: "comparable", value: .bool(c.comparable)),
            .init(key: "reasons", value: .array(c.reasons.map { .string($0.rawValue) })),
            .init(key: "deltaPercentagePoints", value: c.deltaPercentagePoints.map(number) ?? .null),
            .init(key: "deltaDisplay", value: c.deltaDisplay.map { .string($0) } ?? .null),
            .init(key: "summary", value: c.summary.map { .string($0) } ?? .null),
            .init(key: "claim", value: .string(c.claim.rawValue)),
        ])
    }

    static func number(_ value: Int) -> StudioJSONValue {
        // a number token through the strict parser, so it compares equal to one read from a vector file
        try! StudioJSONParser.parse(Data(String(value).utf8))
    }

    static func text(_ value: StudioJSONValue) -> String { String(decoding: value.serialized(), as: UTF8.self) }

    /// Every case of the shared progress vectors, by id.
    static func cases() throws -> [(id: String, item: StudioJSONValue)] {
        let file = try StudioJSONParser.parse(StudioFixtures.data("vectors/progress-comparison.json"))
        guard case .array(let items)? = file["cases"] else { throw Mismatch(description: "progress vectors have no cases") }
        return items.compactMap { item in
            guard case .string(let id)? = item["id"] else { return nil }
            return (id, item)
        }
    }
}
