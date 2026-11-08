import Foundation

/// One operation of SD6b, named as the spec names it and mapped onto the `jovra.edit-plan/2` fields (ADR-0015): segment
/// ops (`card` is op `title-card`), each segment's `transitionIn.type`, `overlayRefs[].kind`, `grade.presetId`,
/// `framing.mode: reframe` (`fill` and `letterbox` are always available), `audio.bed[].route`, the optional `music` and
/// `narration` lanes, and multi-angle live or replay (more than one match source cut into the picture).
public struct EDLOperation: RawRepresentable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let live = EDLOperation(rawValue: "live")
    public static let broll = EDLOperation(rawValue: "broll")
    public static let replay = EDLOperation(rawValue: "replay")
    public static let freeze = EDLOperation(rawValue: "freeze")
    public static let card = EDLOperation(rawValue: "card")
    public static let cut = EDLOperation(rawValue: "transition.cut")
    public static let dissolve = EDLOperation(rawValue: "transition.dissolve")
    public static let dip = EDLOperation(rawValue: "transition.dip")
    public static func overlay(_ kind: StudioOverlayKind) -> EDLOperation { EDLOperation(rawValue: "overlay.\(kind.rawValue)") }
    public static func grade(_ preset: String) -> EDLOperation { EDLOperation(rawValue: "grade.\(preset)") }
    public static let reframe = EDLOperation(rawValue: "reframe")
    public static let primaryBed = EDLOperation(rawValue: "primary-bed")
    public static let altBed = EDLOperation(rawValue: "alt-bed")
    public static let holdBed = EDLOperation(rawValue: "hold-bed")
    public static let silence = EDLOperation(rawValue: "silence")
    public static let music = EDLOperation(rawValue: "music")
    public static let narration = EDLOperation(rawValue: "narration")
    public static let multiAngle = EDLOperation(rawValue: "multi-angle")

    public static func < (a: EDLOperation, b: EDLOperation) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
}

/// SD6b · the product's stage allowlist, separate from the contract. The contract and its fixtures may describe an
/// operation before it is enabled (the Rally Pulse 9:16 fixture already carries a moving reframe and rights-bound
/// music to pin their validator rules); this allowlist decides what a plan may use in the app. An operation is enabled
/// only when its validator rule and its barcode-fixture test exist, so each later ticket flips exactly one entry of
/// `enabledInProduct`.
public struct EDLStageAllowlist: Equatable, Sendable {
    /// The stage that introduces each operation (spec SD6b). Anything the table does not name is refused.
    public static let introducedIn: [EDLOperation: String] = [
        .live: "S1", .broll: "S1", .replay: "S1", .freeze: "S1", .card: "S1",
        .cut: "S1", .dissolve: "S1", .dip: "S1",
        .overlay(.score): "S1", .overlay(.metric): "S1", .overlay(.note): "S1", .overlay(.cue): "S1",
        .overlay(.annotation): "S1",
        .grade("none"): "S1", .primaryBed: "S1", .holdBed: "S1", .silence: "S1",
        .altBed: "S2", .multiAngle: "S2", .grade("warm-court-1"): "S2",
        .reframe: "S5", .music: "S5", .narration: "S5",
    ]

    /// S1: live, broll, replay (clean-frame), freeze, card, cut/dissolve/dip, the overlay kinds, grade none,
    /// primary-bed, hold-bed and silence.
    public static let s1 = EDLStageAllowlist(enabled: Set(introducedIn.filter { $0.value == "S1" }.keys))

    /// What the app enables today. S2 and S5 tickets each add their one operation here.
    public static let enabledInProduct = s1

    public let enabled: Set<EDLOperation>

    public init(enabled: Set<EDLOperation>) { self.enabled = enabled }

    /// Every operation a plan uses, sorted. Run it on a plan the contract validator accepted.
    public static func operations(in plan: StudioJSONValue) -> [EDLOperation] {
        var used: Set<EDLOperation> = []
        var pictureMatchSources: Set<String> = []
        for seg in plan["segments"].flatMap(EDLJSON.array) ?? [] {
            switch seg["op"].flatMap(EDLJSON.string) {
            case "live"?: used.insert(.live)
            case "broll"?: used.insert(.broll)
            case "replay"?: used.insert(.replay)
            case "freeze"?: used.insert(.freeze)
            case "title-card"?: used.insert(.card)
            default: break
            }
            if let op = seg["op"].flatMap(EDLJSON.string), op == "live" || op == "replay",
               let source = seg["sourceId"].flatMap(EDLJSON.string) {
                pictureMatchSources.insert(source)
            }
            if let type = seg["transitionIn"]?["type"].flatMap(EDLJSON.string) {
                used.insert(EDLOperation(rawValue: "transition.\(type)"))
            }
            if seg["framing"]?["mode"] == .string("reframe") { used.insert(.reframe) }
            for ref in seg["overlayRefs"].flatMap(EDLJSON.array) ?? [] {
                if let kind = ref["kind"].flatMap(EDLJSON.string) { used.insert(EDLOperation(rawValue: "overlay.\(kind)")) }
            }
        }
        if pictureMatchSources.count > 1 { used.insert(.multiAngle) }
        if let preset = plan["grade"]?["presetId"].flatMap(EDLJSON.string) { used.insert(.grade(preset)) }
        for piece in plan["audio"]?["bed"].flatMap(EDLJSON.array) ?? [] {
            if let route = piece["route"].flatMap(EDLJSON.string) { used.insert(EDLOperation(rawValue: route)) }
        }
        if let music = plan["audio"]?["music"], music != .null { used.insert(.music) }
        if let narration = plan["audio"]?["narration"], narration != .null { used.insert(.narration) }
        return used.sorted()
    }

    /// One `stageNotEnabled` finding per operation the plan uses that this stage does not enable; empty when the plan
    /// fits the stage.
    public func refusals(_ plan: StudioJSONValue) -> [EDLFinding] {
        Self.operations(in: plan).filter { !enabled.contains($0) }.map { op in
            let stage = Self.introducedIn[op].map { "it is enabled in \($0)" } ?? "no stage enables it"
            return EDLFinding(.stageNotEnabled, "\(op.rawValue) is not enabled in this build; \(stage)")
        }
    }

    /// The typed form of `refusals`.
    public func refusals(_ plan: EditPlan) throws -> [EDLFinding] {
        refusals(try StudioJSONParser.parse(try StudioContractCodec.encode(plan)))
    }
}
