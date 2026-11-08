import Foundation
import JovraCore

/// What a valid plan is (the reference's result dictionary). A valid plan is a checked proposal only: it proves nothing
/// about real footage, alignment quality, rights or editorial truth, and it is never spending permission.
public struct EDLValidPlan: Equatable, Sendable {
    public let sample: Bool
    public let profileId: String
    public let segments: Int
    public let frames: Int
    /// Exact output duration, as the reference prints a Fraction ("192" or "385/2").
    public let durationSeconds: String
    /// The plan has dissolves, dips or a moving reframe.
    public let motionEffects: Bool
    /// The plan has motion effects and is not itself the clean alternate, so a clean alternate must be derived.
    public let needsCleanAlternate: Bool
    public let actualMediaVerified = false
    public let rendered = false
}

/// STU-02 (S11): the `jovra.edit-plan/2` validator, at parity with `spec/reference/studio/edl.py`. Each rule raises the
/// reference's code (`EDLFindingCode`); the validator stops at the first violation, as the reference does.
///
/// It checks a plan against the trusted story-profile catalog and a trusted context built from stored records
/// (`EDLTrustedContext.build`), never against the plan's own claims. It works on the strict JSON tree, so a plan is
/// checked exactly as written (an integral float, a boolean speed or an unknown field is refused by the validator
/// itself, not only by the schema layer). The SD6b stage allowlist is separate (`EDLStageAllowlist`).
public struct EDLValidator: Sendable {
    public static let version = "jovra.edit-plan/2"

    let profiles: [String: StoryProfile]

    public init(profiles: StoryProfileCatalog) {
        self.profiles = Dictionary(profiles.profiles.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The findings for a plan: empty when the plan is valid, else the one contract violation (`contextMissing` when
    /// there is no trusted context).
    public func validate(_ plan: StudioJSONValue, context: EDLTrustedContext?) -> [EDLFinding] {
        do {
            _ = try check(plan, context: context)
            return []
        } catch let finding as EDLFinding {
            return [finding]
        } catch {
            return [EDLFinding(.notObject, "unexpected validator error: \(error)")]
        }
    }

    /// The findings for a typed plan (encoded canonically first, so it is checked exactly as it would be stored).
    public func validate(_ plan: EditPlan, context: EDLTrustedContext?) -> [EDLFinding] {
        do {
            return validate(try StudioJSONParser.parse(try StudioContractCodec.encode(plan)), context: context)
        } catch {
            return [EDLFinding(.notObject, "the plan does not encode as jovra.edit-plan/2: \(error)")]
        }
    }

    /// The findings for a plan against a context in its JSON form; a partial context is `contextMissing`.
    public func validate(_ plan: StudioJSONValue, contextJSON: StudioJSONValue?) -> [EDLFinding] {
        guard let contextJSON else { return validate(plan, context: nil) }
        do {
            return validate(plan, context: try EDLTrustedContext(json: contextJSON))
        } catch let finding as EDLFinding {
            return [finding]
        } catch {
            return [EDLFinding(.contextMissing, "\(error)")]
        }
    }

    /// Validates a plan, throwing the first `EDLFinding`.
    public func check(_ plan: StudioJSONValue, context: EDLTrustedContext?) throws -> EDLValidPlan {
        guard let context else {
            throw EDLFinding(.contextMissing, "validate() needs the trusted context (\(EDLTrustedContext.jsonKeys.joined(separator: ", "))); "
                             + "a plan is never checked against itself")
        }
        var run = EDLPlanCheck(profiles: profiles, context: context)
        return try run.check(plan)
    }

    // ----- shared time helpers (core.py) -----------------------------------------------------------------------------

    static func frameDurationUs(num: Int, den: Int) -> EDLFraction {
        EDLFraction(EDLInteger(1_000_000) * EDLInteger(den), EDLInteger(num))
    }

    /// `edl.fps_of`: `{num, den}` integers >= 1 with a rate inside 1-240 fps.
    static func fps(_ value: StudioJSONValue, _ label: String) throws -> (num: Int, den: Int, rate: EDLFraction) {
        let obj = try EDLJSON.fields(value, "num den", label)
        let num = try EDLJSON.integer(obj["num"], label + ".num", minimum: 1)
        let den = try EDLJSON.integer(obj["den"], label + ".den", minimum: 1)
        let rate = EDLFraction(num, den)
        try require(EDLFraction(1) <= rate && rate <= EDLFraction(240), .badFps, "\(label) outside 1-240 fps")
        return (num, den, rate)
    }
}

/// One segment as the checks see it (the reference's `seg_info`).
struct EDLSegmentInfo {
    let id: String
    let op: String
    let seg: EDLObject
    let outIn: Int
    let outOut: Int
    var session: (EDLFraction, EDLFraction)?
    var src: EDLPlanSource?
    var sIn = 0
    var sOut = 0
    var speed = EDLFraction(1)
    var cov: Int?
    var protected: [(Int, Int)] = []

    var length: Int { outOut - outIn }
}

/// One validation run (the body of `edl.validate`).
struct EDLPlanCheck {
    static let maxMatchSources = 6
    static let maxBrollSources = 12
    static let maxSegments = 128
    static let maxDimension = 3840
    static let aspects: [String: (Int, Int)] = ["16:9": (16, 9), "9:16": (9, 16), "1:1": (1, 1), "4:5": (4, 5)]
    static let segmentFields: [String: String] = [
        "live": "id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
            + "sessionInUs keeperId protectedFrames overlayRefs framing",
        "broll": "id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
            + "brollId overlayRefs framing",
        "replay": "id op outputInFrame outputOutFrame transitionIn sourceId sourceInFrame sourceOutFrame speed "
            + "replayOf labelTemplateId overlayRefs framing",
        "freeze": "id op outputInFrame outputOutFrame transitionIn sourceId sourceFrame labelTemplateId overlayRefs framing",
        "title-card": "id op outputInFrame outputOutFrame transitionIn templateId textRefs overlayRefs",
    ]
    static let videoOps: Set<String> = ["live", "broll", "replay", "freeze"]
    static let movingOps: Set<String> = ["live", "broll", "replay"]
    static let replayLabel = "label.replay"
    static let freezeLabel = "label.paused"

    let profiles: [String: StoryProfile]
    let context: EDLTrustedContext

    // set while checking
    var profile: StoryProfile!
    var grammar: StoryProfileGrammar { profile.grammar }
    var bindings = EDLObject(members: [:])
    var output = EDLObject(members: [:])
    var outFps = EDLFraction(1)
    var outFpsNum = 1
    var outFpsDen = 1
    var total = 0
    var sources: [String: EDLPlanSource] = [:]
    var seen: [String: Int] = [:]           // segment id -> index in `order`
    var order: [EDLSegmentInfo] = []

    init(profiles: [String: StoryProfile], context: EDLTrustedContext) {
        self.profiles = profiles
        self.context = context
    }

    var outFrameDurationUs: EDLFraction { EDLValidator.frameDurationUs(num: outFpsNum, den: outFpsDen) }

    mutating func check(_ raw: StudioJSONValue) throws -> EDLValidPlan {
        try EDLJSON.scanForbidden(raw)
        let plan = try EDLJSON.fields(raw, "schemaVersion projectId planId planRevision sample cleanAlternate bindings "
                                      + "output grade sources segments chapters audio", "plan")
        try require(EDLJSON.string(plan["schemaVersion"]) == EDLValidator.version, .badVersion,
                    "schemaVersion must be \(EDLValidator.version)")
        let projectId = try EDLJSON.identifier(plan["projectId"], "projectId")
        try require(projectId == context.projectId, .projectMismatch,
                    "the plan names another project than the stored records it is checked against")
        _ = try EDLJSON.identifier(plan["planId"], "planId")
        _ = try EDLJSON.integer(plan["planRevision"], "planRevision", minimum: 1)
        guard let sample = EDLJSON.boolean(plan["sample"]) else { throw EDLFinding(.badBoolean, "sample must be boolean") }
        guard let cleanAlternate = EDLJSON.boolean(plan["cleanAlternate"]) else {
            throw EDLFinding(.badBoolean, "cleanAlternate must be boolean")
        }

        try checkBindings(plan["bindings"])
        let duration = try checkOutput(plan["output"])
        let grade = try EDLJSON.fields(plan["grade"], "presetId", "grade")
        try require(grammar.gradePresets.map(\.rawValue).contains(EDLJSON.string(grade["presetId"]) ?? "\u{0}"),
                    .opNotAllowed, "grade preset not allowed for this profile")
        try checkSources(plan["sources"])

        guard let segs = EDLJSON.array(plan["segments"]), (1...Self.maxSegments).contains(segs.count) else {
            throw EDLFinding(.tooManySegments, "1-128 segments")
        }
        var motion = false
        var cursor = 0
        var lastLiveSession: Int?
        var shownLive: [(EDLFraction, EDLFraction, EDLPlanSource)] = []
        for (index, rawSeg) in segs.enumerated() {
            guard let op = rawSeg["op"].flatMap(EDLJSON.string), let names = Self.segmentFields[op], EDLJSON.object(rawSeg) != nil else {
                throw EDLFinding(.badOp, "unknown segment op")
            }
            let seg = try EDLJSON.fields(rawSeg, names, "segment \(index) (\(op))")
            let sid = try EDLJSON.identifier(seg["id"], "segment id")
            try require(seen[sid] == nil, .duplicateId, "duplicate segment id \(sid)")
            try require(grammar.ops.map(\.rawValue).contains(op), .opNotAllowed, "\(op) is not allowed in \(profile.id.rawValue)")
            let oIn = try EDLJSON.integer(seg["outputInFrame"], "outputInFrame")
            let oOut = try EDLJSON.integer(seg["outputOutFrame"], "outputOutFrame", minimum: 1)
            try require(oIn == cursor, .outputGap, "segment \(sid) must start at output frame \(cursor)")
            try require(oIn < oOut && oOut <= total, .badInterval, "segment \(sid) has an invalid output interval")
            cursor = oOut
            var info = EDLSegmentInfo(id: sid, op: op, seg: seg, outIn: oIn, outOut: oOut)

            if Self.movingOps.contains(op) {
                try checkMoving(&info, lastLiveSession: &lastLiveSession, shownLive: &shownLive)
            } else if op == "freeze" {
                let src = try sourceFor(seg, op)
                let frame = try EDLJSON.integer(seg["sourceFrame"], "sourceFrame")
                try require(src.interval(frame, frame + 1) != nil, .outsideCoverage, "freeze \(sid) frame not covered")
                try require(EDLJSON.string(seg["labelTemplateId"]) == Self.freezeLabel, .labelMissing,
                            "a freeze needs the Paused label")
                let ms = EDLFraction(info.length) / outFps * EDLFraction(1000)
                try require(EDLFraction(grammar.freezeMs.min) <= ms && ms <= EDLFraction(grammar.freezeMs.max),
                            .freezeDuration, "freeze \(sid) lasts \(ms) ms")
                info.src = src
            } else {
                _ = try EDLJSON.template(seg["templateId"], "card templateId", prefix: "card.")
                guard let refs = EDLJSON.array(seg["textRefs"]), refs.count <= 4 else {
                    throw EDLFinding(.badTextRefs, "at most 4 text refs")
                }
                for ref in refs {
                    let id = try EDLJSON.identifier(ref, "textRef")
                    try resolveNote(id, "card \(sid) textRef")
                }
                let ms = EDLFraction(info.length) / outFps * EDLFraction(1000)
                try require(EDLFraction(grammar.cardMs.min) <= ms && ms <= EDLFraction(grammar.cardMs.max),
                            .cardDuration, "card \(sid) lasts \(ms) ms")
            }

            if Self.videoOps.contains(op), let src = EDLJSON.string(seg["sourceId"]).flatMap({ sources[$0] }) {
                motion = try checkFraming(seg["framing"], src: src, length: info.length) || motion
            }
            try checkOverlays(seg["overlayRefs"], sid: sid, info: info)
            motion = try checkTransition(seg["transitionIn"], info: info, index: index) || motion
            seen[sid] = order.count
            order.append(info)
        }
        try require(cursor == total, .incompleteCoverage, "segments must cover every output frame exactly once")

        try checkChapters(plan["chapters"])
        try checkAudio(plan["audio"])

        if cleanAlternate {
            try require(!motion, .motionInCleanAlternate, "a clean alternate has no dissolves, dips or moving reframes")
        }
        return EDLValidPlan(sample: sample, profileId: profile.id.rawValue, segments: segs.count, frames: total,
                            durationSeconds: duration.description, motionEffects: motion,
                            needsCleanAlternate: motion && !cleanAlternate)
    }

    // ----- bindings, output, sources ---------------------------------------------------------------------------------

    private mutating func checkBindings(_ raw: StudioJSONValue) throws {
        bindings = try EDLJSON.fields(raw, "sourceManifestRevision syncRevision eventRevision profileId profileRevision "
                                      + "keeperCatalogRevision brollCatalogRevision", "bindings")
        for key in ["sourceManifestRevision", "syncRevision", "eventRevision", "profileRevision", "keeperCatalogRevision",
                    "brollCatalogRevision"] {
            _ = try EDLJSON.integer(bindings[key], key, minimum: 1)
        }
        guard let id = EDLJSON.string(bindings["profileId"]), let found = profiles[id] else {
            throw EDLFinding(.unknownProfile, "unknown story profile")
        }
        profile = found
        try require(EDLJSON.equals(bindings["profileRevision"], found.revision), .staleRevision,
                    "plan is bound to a different story-profile revision")
        for key in EDLTrustedContext.currentKeys + context.current.keys.filter({ !EDLTrustedContext.currentKeys.contains($0) }).sorted() {
            guard let current = context.current[key] else { continue }
            let bound = bindings.members[key]
            try require(bound.map { EDLJSON.equals($0, current) } ?? false, .staleRevision,
                        "\(key) \(bound.map { String(decoding: $0.serialized(), as: UTF8.self) } ?? "None") is not current (\(current))")
        }
    }

    private mutating func checkOutput(_ raw: StudioJSONValue) throws -> EDLFraction {
        output = try EDLJSON.fields(raw, "fps width height aspect totalFrames container videoCodec audioCodec audioSampleRate",
                                    "output")
        (outFpsNum, outFpsDen, outFps) = try EDLValidator.fps(output["fps"], "output fps")
        let width = try EDLJSON.integer(output["width"], "output width", minimum: 2)
        let height = try EDLJSON.integer(output["height"], "output height", minimum: 2)
        try require(width % 2 == 0 && height % 2 == 0 && width <= Self.maxDimension && height <= Self.maxDimension,
                    .badOutput, "output dimensions must be even and at most 3840")
        guard let aspect = EDLJSON.string(output["aspect"]).flatMap({ Self.aspects[$0] }) else {
            throw EDLFinding(.badOutput, "unsupported aspect")
        }
        try require(width * aspect.1 == height * aspect.0, .badOutput, "width/height do not match the declared aspect")
        total = try EDLJSON.integer(output["totalFrames"], "totalFrames", minimum: 1)
        let duration = EDLFraction(total) / outFps
        try require(duration <= EDLFraction(EDLPlanSource.maxOutputSeconds), .outputTooLong, "output exceeds four hours")
        let codec = EDLJSON.string(output["videoCodec"])
        try require(EDLJSON.string(output["container"]) == "mp4" && (codec == "h264" || codec == "hevc")
                    && EDLJSON.string(output["audioCodec"]) == "aac" && EDLJSON.equals(output["audioSampleRate"], 48000),
                    .badOutput, "output must be MP4, H.264/HEVC, AAC 48 kHz")
        let range = grammar.durationSeconds
        try require(EDLFraction(range.min) <= duration && duration <= EDLFraction(range.max), .durationOutsideProfile,
                    "\(duration) s is outside the profile's \(range.min)-\(range.max) s")
        return duration
    }

    private mutating func checkSources(_ raw: StudioJSONValue) throws {
        guard let list = EDLJSON.array(raw), !list.isEmpty else { throw EDLFinding(.badSources, "at least one source") }
        for item in list {
            let src = try EDLPlanSource(item)
            try require(sources[src.id] == nil, .duplicateId, "duplicate source \(src.id)")
            let trusted = context.sources[src.id]
            try require(trusted?.sha256 == src.sha256, .untrustedSource,
                        "source \(src.id) is not offered by the trusted manifest and sync map with this hash")
            guard let trusted else { continue }
            try require(item["role"].flatMap(EDLJSON.string) == trusted.role
                        && EDLJSON.pythonEquals(item["proxy"] ?? .null, trusted.proxy)
                        && src.hasAudio == trusted.hasAudio, .untrustedSource,
                        "source \(src.id): the plan's snapshot differs from the trusted manifest")
            try require(EDLJSON.pythonEquals(item["coverage"] ?? .null, trusted.coverage), .coverageMismatch,
                        "source \(src.id): coverage (session start, rate, frames) is not the reviewed sync map's")
            sources[src.id] = src
        }
        let match = sources.values.filter { $0.role == "match" }.count
        try require((1...Self.maxMatchSources).contains(match) && sources.count - match <= Self.maxBrollSources,
                    .badSources, "one to six match sources and at most twelve B-roll sources")
    }

    // ----- segments --------------------------------------------------------------------------------------------------

    func sourceFor(_ seg: EDLObject, _ op: String) throws -> EDLPlanSource {
        let id = try EDLJSON.identifier(seg["sourceId"], "\(op) sourceId")
        guard let src = sources[id] else { throw EDLFinding(.unknownSource, "unknown source \(id)") }
        return src
    }

    private func speed(_ raw: StudioJSONValue, _ op: String) throws -> EDLFraction {
        let obj = try EDLJSON.fields(raw, "num den", "speed")
        guard let num = EDLJSON.exactInt(obj["num"]), num == 1, let den = EDLJSON.exactInt(obj["den"]), [1, 2, 4, 8].contains(den) else {
            throw EDLFinding(.badSpeed, "speed must be 1, 1/2, 1/4 or 1/8")
        }
        if op == "live" || op == "broll" {
            try require(den == 1, .badSpeed, "live action and B-roll stay at original speed")
        } else {
            try require(grammar.replaySpeedDens.contains(den), .badSpeed, "replay speed not allowed by this profile")
        }
        return EDLFraction(1, den)
    }

    private mutating func checkMoving(_ info: inout EDLSegmentInfo, lastLiveSession: inout Int?,
                                      shownLive: inout [(EDLFraction, EDLFraction, EDLPlanSource)]) throws {
        let seg = info.seg, sid = info.id, op = info.op
        let src = try sourceFor(seg, op)
        let sIn = try EDLJSON.integer(seg["sourceInFrame"], "sourceInFrame")
        let sOut = try EDLJSON.integer(seg["sourceOutFrame"], "sourceOutFrame", minimum: 1)
        try require(sIn < sOut, .badInterval, "segment \(sid) has an empty source window")
        let speed = try speed(seg["speed"], op)
        // source seconds == output seconds x speed, exactly
        try require(EDLFraction(sOut - sIn) / src.fps == EDLFraction(info.length) / outFps * speed, .durationMismatch,
                    "segment \(sid): source and output durations disagree at speed \(speed)")
        // clean-frame rule: every output frame is a distinct real captured frame
        try require(src.fps * speed >= outFps, .cleanFrameRule,
                    "segment \(sid): source fps x speed is below the output fps (no interpolated frames)")
        guard let cov = src.interval(sIn, sOut) else {
            throw EDLFinding(.outsideCoverage, "segment \(sid): source window leaves the reviewed coverage or crosses a gap")
        }
        info.src = src
        info.sIn = sIn
        info.sOut = sOut
        info.speed = speed
        info.cov = cov
        if src.role == "match", let a = src.sessionUs(sIn, in: cov), let b = src.sessionUs(sOut, in: cov) {
            info.session = (a, b)
        }
        switch op {
        case "live":
            try checkLive(&info, src: src, lastLiveSession: &lastLiveSession, shownLive: &shownLive)
        case "broll":
            try require(src.role == "broll", .badSourceRole, "broll segment \(sid) needs a B-roll source")
            let brollId = try EDLJSON.identifier(seg["brollId"], "brollId")
            try require(context.brolls.contains(brollId), .untrustedReference, "unknown B-roll item")
        default:
            try checkReplay(info)
        }
    }

    private func checkLive(_ info: inout EDLSegmentInfo, src: EDLPlanSource, lastLiveSession: inout Int?,
                           shownLive: inout [(EDLFraction, EDLFraction, EDLPlanSource)]) throws {
        let seg = info.seg, sid = info.id
        try require(src.role == "match", .badSourceRole, "live segment \(sid) needs a match source")
        let keeper = seg["keeperId"]
        try require(keeper == .null || EDLJSON.pythonText(keeper).map(EDLJSON.isIdentifier) == true, .badIdentifier,
                    "keeperId must be an id or null")
        if keeper != .null {
            try require(EDLJSON.string(keeper).map(context.keepers.contains) == true, .untrustedReference, "unknown keeper")
        }
        guard let start = src.sessionUs(info.sIn, in: info.cov), let session = info.session,
              let expected = start.roundedHalfUp.intValue else {
            throw EDLFinding(.sessionTimeMismatch, "segment \(sid): no session time from the sync map")
        }
        try require(EDLJSON.equals(seg["sessionInUs"], expected), .sessionTimeMismatch,
                    "segment \(sid): sessionInUs must be \(expected) from the sync map")
        guard let windows = EDLJSON.array(seg["protectedFrames"]), windows.count <= 64 else {
            throw EDLFinding(.badProtected, "protectedFrames must be a list")
        }
        var protected: [(Int, Int)] = []
        for w in windows {
            let obj = try EDLJSON.fields(w, "inFrame outFrame", "protected window")
            let a = try EDLJSON.integer(obj["inFrame"], "protected in")
            let b = try EDLJSON.integer(obj["outFrame"], "protected out", minimum: 1)
            try require(info.sIn <= a && a < b && b <= info.sOut, .badProtected, "protected window must lie inside the segment")
            protected.append((a, b))
        }
        info.protected = protected
        // every stored contact in the window is protected, whatever keeperId says (a plan cannot opt out of contact
        // protection by naming no keeper)
        for c in context.contacts[src.id] ?? [] where info.sIn <= c && c < info.sOut {
            try require(protected.contains { $0.0 <= c && c < $0.1 }, .contactUnprotected,
                        "segment \(sid): stored contact at frame \(c) is not inside a protected window")
        }
        if grammar.chronology == .strict {
            try require(lastLiveSession.map { expected > $0 } ?? true, .chronology,
                        "segment \(sid): live segments must keep session order in \(profile.id.rawValue)")
        }
        lastLiveSession = expected
        // a moment shown live is shown live once: showing it again is a replay and carries the Replay label. Two angles
        // cut at one instant may overlap by up to one source frame of the coarser angle.
        let (l0, l1) = session
        for (p0, p1, other) in shownLive {
            let slack = max(src.frameDurationUs, other.frameDurationUs)
            try require(min(l1, p1) - max(l0, p0) <= slack, .replayWithoutLabel,
                        "segment \(sid) shows session time an earlier live segment already showed; a repeat is a labelled replay")
        }
        shownLive.append((l0, l1, src))
    }

    private func checkReplay(_ info: EDLSegmentInfo) throws {
        let seg = info.seg, sid = info.id
        try require(EDLJSON.string(seg["labelTemplateId"]) == Self.replayLabel, .labelMissing, "a replay needs the Replay label")
        try require(EDLFraction(info.length) / outFps * EDLFraction(1000) <= EDLFraction(grammar.replayMaxMs), .replayTooLong,
                    "replay \(sid) is longer than \(grammar.replayMaxMs) ms of output")
        let targetIndex = EDLJSON.string(seg["replayOf"]).flatMap { seen[$0] }
        guard let targetIndex, order[targetIndex].op == "live" else {
            throw EDLFinding(.replayBeforeOriginal, "replay \(sid) must follow the live segment it re-shows")
        }
        let target = order[targetIndex]
        try require(info.src?.role == "match", .badSourceRole, "a replay re-shows match footage")
        guard let (r0, r1) = info.session, let (l0, l1) = target.session else {
            throw EDLFinding(.replayOutsideOriginal, "replay \(sid) has no session time")
        }
        let half = outFrameDurationUs / EDLFraction(2)
        try require(l0 - half <= r0 && r1 <= l1 + half, .replayOutsideOriginal,
                    "replay \(sid) shows session time that its original live segment did not show")
        if grammar.chronology == .strict {
            try require(!order[(targetIndex + 1)...].contains { $0.op == "live" }, .chronology,
                        "replay \(sid) must come before the next live point")
        }
    }

    /// Text on screen and narration scripts come only from stored notes in the trusted reference catalog.
    func resolveNote(_ ref: String, _ label: String) throws {
        guard let stored = context.references[ref] else {
            throw EDLFinding(.untrustedReference, "\(label) '\(ref)' is not a stored record")
        }
        try require(stored.kind == "note", .kindMismatch, "\(label) '\(ref)' is a \(stored.kind), not a note")
    }
}
