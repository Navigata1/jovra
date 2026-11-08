import Foundation
import JovraCore

/// Framing, overlays, transitions and chapters (`edl._check_framing`, `_check_overlays`, `_check_transition`,
/// `_check_chapters`).
extension EDLPlanCheck {
    static let frameUnits = 10_000              // reframe windows are in 1/10 000 of the source frame
    static let maxPanUnitsPerFrame = 50         // proposal: at most 0.5% of the frame per output frame
    static let maxReframeUpscale = 2
    static let maxOverlays = 8
    static let overlayKinds: Set<String> = ["score", "metric", "note", "cue", "annotation"]
    static let provenances: Set<String> = Set(Provenance.allCases.map(\.rawValue))

    /// Returns true when the framing is a motion effect (a moving reframe).
    func checkFraming(_ framing: StudioJSONValue, src: EDLPlanSource, length: Int) throws -> Bool {
        guard let mode = framing["mode"].flatMap(EDLJSON.string), ["fill", "letterbox", "reframe"].contains(mode) else {
            throw EDLFinding(.badFraming, "framing mode must be fill, letterbox or reframe")
        }
        let ow = EDLJSON.exactInt(output["width"]) ?? 0, oh = EDLJSON.exactInt(output["height"]) ?? 0
        let sameAspect = src.width * oh == src.height * ow
        switch mode {
        case "fill":
            _ = try EDLJSON.fields(framing, "mode", "framing")
            try require(sameAspect, .framingAspect,
                        "fill needs the source aspect to equal the output aspect; letterbox or reframe instead of a blind crop")
            try require(src.height >= oh, .upscaleRefused, "output resolution above the source does not create detail")
            return false
        case "letterbox":
            _ = try EDLJSON.fields(framing, "mode", "framing")
            try require(EDLFraction(ow, src.width) <= EDLFraction(1) || EDLFraction(oh, src.height) <= EDLFraction(1),
                        .upscaleRefused, "letterbox would upscale the source")
            return false
        default:
            break
        }
        let obj = try EDLJSON.fields(framing, "mode basis windows", "framing")
        try require(grammar.reframe == .ifBoxFits, .opNotAllowed, "this profile letterboxes instead of reframing")
        try require(EDLJSON.string(obj["basis"]) == "reviewed-action-box", .reframeNotReviewed,
                    "reframe windows come only from a reviewed action-safe box")
        guard let windows = EDLJSON.array(obj["windows"]), (1...32).contains(windows.count) else {
            throw EDLFinding(.badReframe, "1-32 reframe windows")
        }
        let tolerance = max(src.width * oh, src.height * ow)
        var boxes: [(at: Int, x: Int, y: Int, w: Int, h: Int)] = []
        for raw in windows {
            let w = try EDLJSON.fields(raw, "atFrame x y w h", "reframe window")
            let at = try EDLJSON.integer(w["atFrame"], "atFrame")
            let x = try EDLJSON.integer(w["x"], "x"), y = try EDLJSON.integer(w["y"], "y")
            let cw = try EDLJSON.integer(w["w"], "w", minimum: 1), ch = try EDLJSON.integer(w["h"], "h", minimum: 1)
            try require(x + cw <= Self.frameUnits && y + ch <= Self.frameUnits, .badReframe, "window leaves the source frame")
            try require(abs(cw * src.width * oh - ch * src.height * ow) <= tolerance, .badReframe,
                        "window aspect does not match the output aspect")
            try require(oh * Self.frameUnits <= Self.maxReframeUpscale * ch * src.height, .upscaleRefused,
                        "reframe crop is upscaled more than 2x; letterbox instead")
            if let prev = boxes.last {
                try require(prev.at < at && at < length, .badReframe, "reframe windows must be strictly increasing")
                let step = at - prev.at
                try require(abs(x - prev.x) <= Self.maxPanUnitsPerFrame * step && abs(y - prev.y) <= Self.maxPanUnitsPerFrame * step,
                            .panTooFast, "reframe pans too fast")
            } else {
                try require(at == 0, .badReframe, "the first window starts at the segment's first frame")
            }
            boxes.append((at, x, y, cw, ch))
        }
        let first = boxes[0]
        return boxes.contains { ($0.x, $0.y, $0.w, $0.h) != (first.x, first.y, first.w, first.h) }
    }

    /// The session interval of match play a segment shows, or nil (a card, B-roll).
    func shownSession(_ info: EDLSegmentInfo) -> (EDLFraction, EDLFraction)? {
        if info.op == "live" || info.op == "replay" { return info.session }
        if info.op == "freeze", let src = info.src, src.role == "match", let frame = EDLJSON.exactInt(info.seg["sourceFrame"]),
           let a = src.sessionUs(frame), let b = src.sessionUs(frame + 1) {
            return (a, b)
        }
        return nil
    }

    func allowedProvenances(_ kind: String) -> [Provenance]? {
        let o = grammar.overlays
        switch kind {
        case "score": return o.score
        case "metric": return o.metric
        case "note": return o.note
        case "cue": return o.cue
        case "annotation": return o.annotation
        default: return nil
        }
    }

    func checkOverlays(_ raw: StudioJSONValue, sid: String, info: EDLSegmentInfo) throws {
        guard let refs = EDLJSON.array(raw), refs.count <= Self.maxOverlays else {
            throw EDLFinding(.badOverlays, "at most 8 overlay refs")
        }
        let eventRevision = EDLJSON.exactInt(bindings["eventRevision"]) ?? 0
        var parsed: [(kind: String, refId: String, provenance: String)] = []
        for item in refs {
            let ref = try EDLJSON.fields(item, "kind refId eventRevision provenance", "overlay")
            guard let kind = EDLJSON.string(ref["kind"]), Self.overlayKinds.contains(kind) else {
                throw EDLFinding(.overlayNotAllowed, "unsupported overlay kind")
            }
            let refId = try EDLJSON.identifier(ref["refId"], "overlay refId")
            let revision = try EDLJSON.integer(ref["eventRevision"], "overlay eventRevision", minimum: 1)
            try require(revision == eventRevision, .staleRevision,
                        "segment \(sid): overlay bound to event revision \(revision), plan uses \(eventRevision)")
            guard let provenance = EDLJSON.string(ref["provenance"]), Self.provenances.contains(provenance) else {
                throw EDLFinding(.badEnum, "invalid provenance")
            }
            guard let allowed = allowedProvenances(kind) else {
                throw EDLFinding(.overlayNotAllowed, "\(kind) overlays are not used in this profile")
            }
            try require(allowed.map(\.rawValue).contains(provenance), .provenanceNotAllowed,
                        "\(provenance) \(kind) overlays are not allowed in this profile")
            parsed.append((kind, refId, provenance))
        }
        try require(parsed.filter { $0.kind == "annotation" }.count <= 1, .badOverlays, "at most one annotation at a time")
        for ref in parsed {
            // an overlay is a reference to a stored record: it must resolve, and its kind and provenance are the stored
            // record's, never the plan's own claim (an estimated cue cannot be relabelled reviewed)
            guard let stored = context.references[ref.refId] else {
                throw EDLFinding(.untrustedReference,
                                 "segment \(sid): overlay \(ref.kind) '\(ref.refId)' does not resolve to a stored record")
            }
            try require(stored.kind == ref.kind, .kindMismatch,
                        "segment \(sid): '\(ref.refId)' is a stored \(stored.kind), not a \(ref.kind)")
            try require(stored.provenance == ref.provenance, .provenanceMismatch,
                        "segment \(sid): '\(ref.refId)' is stored as \(stored.provenance), the plan says \(ref.provenance)")
            try require(stored.eventRevision == eventRevision, .staleRevision,
                        "segment \(sid): '\(ref.refId)' was resolved at another event revision")
            // a point's score or metric is bound to that point's moment: over live, replayed or frozen match play it is
            // shown only when the play lies inside the session window of a keeper that carries the point
            if ref.kind == "score" || ref.kind == "metric", let windows = stored.pointWindows,
               let (lo, hi) = shownSession(info), let src = info.src {
                let half = src.frameDurationUs / EDLFraction(2)   // half a source frame of rounding at each edge
                try require(windows.contains { EDLFraction($0.startUs) - half <= lo && hi <= EDLFraction($0.endUs) + half },
                            .overlayOutsideMoment,
                            "segment \(sid): \(ref.kind) '\(ref.refId)' belongs to a point whose keeper windows do not "
                            + "contain the session time shown")
            }
        }
    }

    func checkTransition(_ raw: StudioJSONValue, info: EDLSegmentInfo, index: Int) throws -> Bool {
        let tr = try EDLJSON.fields(raw, "type frames", "transitionIn")
        guard let kind = EDLJSON.string(tr["type"]), ["cut", "dissolve", "dip"].contains(kind) else {
            throw EDLFinding(.transitionNotAllowed, "transitions come from cut, dissolve, dip")
        }
        let n = try EDLJSON.integer(tr["frames"], "transition frames")
        if kind == "cut" {
            try require(n == 0, .badTransition, "a cut has 0 frames")
            return false
        }
        try require(index > 0, .badTransition, "the first segment starts with a cut")
        try require(grammar.transitions.map(\.rawValue).contains(kind), .transitionNotAllowed,
                    "\(kind) is not allowed in this profile")
        try require(n >= 2, .badTransition, "a dissolve or dip spans at least 2 frames")
        let ms = EDLFraction(n * 1000) / outFps
        try require(ms <= EDLFraction(grammar.maxTransitionMs), .transitionTooLong,
                    "\(ms) ms exceeds \(grammar.maxTransitionMs) ms")
        guard let prev = order.last else { throw EDLFinding(.badTransition, "the first segment starts with a cut") }
        let hOut = n / 2          // output frames after the boundary that still show the outgoing source
        let hIn = n - hOut        // output frames before the boundary that already show the incoming source
        try require(prev.length >= hIn && info.length >= hOut, .badTransition, "transition longer than an adjacent segment")
        for (side, edge) in [(prev, prev.sOut), (info, info.sIn)] {
            guard Self.movingOps.contains(side.op), let src = side.src else { continue }
            let k = src.fps * side.speed / outFps     // source frames per output frame
            guard let lo = (EDLInteger(edge) - (EDLFraction(hIn) * k).ceil).intValue,
                  let hi = (EDLInteger(edge) + (EDLFraction(hOut) * k).ceil).intValue else {
                throw EDLFinding(.transitionHandle, "transition handles are out of range")
            }
            try require(lo >= 0 && src.interval(lo, hi) == side.cov, .transitionHandle,
                        "transition needs source handles [\(lo),\(hi)) inside the same coverage (never across a gap)")
            for (a, b) in side.protected {
                try require(hi <= a || b <= lo, .contactProtected, "a transition may not touch a protected contact window")
            }
            for c in context.contacts[src.id] ?? [] {
                try require(!(lo <= c && c < hi), .contactProtected,
                            "a transition may not blend the stored contact at frame \(c) (live or replay)")
            }
        }
        return true
    }

    func checkChapters(_ raw: StudioJSONValue) throws {
        guard let chapters = EDLJSON.array(raw), chapters.count <= 64 else {
            throw EDLFinding(.badChapters, "chapters must be a list")
        }
        var prev = -1
        var ids: Set<String> = []
        for (i, item) in chapters.enumerated() {
            let ch = try EDLJSON.fields(item, "id outputInFrame templateId", "chapter")
            let id = try EDLJSON.identifier(ch["id"], "chapter id")
            try require(!ids.contains(id), .duplicateId, "duplicate chapter id")
            ids.insert(id)
            _ = try EDLJSON.template(ch["templateId"], "chapter templateId", prefix: "chapter.")
            let at = try EDLJSON.integer(ch["outputInFrame"], "chapter outputInFrame")
            try require((i == 0 && at == 0) || (i > 0 && prev < at && at < total), .badChapters,
                        "chapters start at frame 0 and strictly increase inside the film")
            prev = at
        }
    }

    func checkWindows(_ raw: StudioJSONValue, _ label: String) throws {
        guard let windows = EDLJSON.array(raw), (1...64).contains(windows.count) else {
            throw EDLFinding(.badWindows, "\(label) needs 1-64 windows")
        }
        var prev = 0
        for item in windows {
            let w = try EDLJSON.fields(item, "outputInFrame outputOutFrame", "\(label) window")
            let a = try EDLJSON.integer(w["outputInFrame"], "window in")
            let b = try EDLJSON.integer(w["outputOutFrame"], "window out", minimum: 1)
            try require(prev <= a && a < b && b <= total, .badWindows, "\(label) windows must be ordered and inside the film")
            prev = b
        }
    }
}
