import Foundation

/// SD17 · `cleanAlternate(edl)`: the Reduce Motion / clean version of a plan (`edl.clean_alternate`). The same cut list,
/// cuts instead of dissolves and dips, and a moving reframe replaced by letterbox. A pure function on the plan as
/// written: member order and number tokens are kept, so the result is the reference's alternate byte for byte. The
/// result must still validate on its own.
extension EDLValidator {
    public static let cleanPlanIdSuffix = "-clean"

    public static func cleanAlternate(_ plan: StudioJSONValue) -> StudioJSONValue {
        var alt = plan.setting("cleanAlternate", to: .bool(true))
        if let planId = plan["planId"].flatMap(EDLJSON.string) {
            alt = alt.setting("planId", to: .string(String((planId + cleanPlanIdSuffix).prefix(64))))
        }
        guard let segments = alt["segments"].flatMap(EDLJSON.array) else { return alt }
        let cut = StudioJSONValue.members([("type", .string("cut")), ("frames", .int(0))])
        let clean = segments.map { segment -> StudioJSONValue in
            var seg = segment.setting("transitionIn", to: cut)
            if let framing = seg["framing"], framing["mode"] == .string("reframe"), isMoving(framing) {
                seg = seg.setting("framing", to: .members([("mode", .string("letterbox"))]))
            }
            return seg
        }
        return alt.setting("segments", to: .array(clean))
    }

    /// The clean alternate of a typed plan.
    public static func cleanAlternate(_ plan: EditPlan) throws -> EditPlan {
        let json = try StudioJSONParser.parse(try StudioContractCodec.encode(plan))
        return try StudioContractCodec.decode(EditPlan.self, from: cleanAlternate(json).serialized())
    }

    /// A reframe is a motion effect when any window's box differs from the first.
    static func isMoving(_ framing: StudioJSONValue) -> Bool {
        guard let windows = framing["windows"].flatMap(EDLJSON.array), let first = windows.first else { return false }
        func box(_ w: StudioJSONValue) -> [StudioJSONValue?] { ["x", "y", "w", "h"].map { w[$0] } }
        return windows.contains { box($0) != box(first) }
    }
}
