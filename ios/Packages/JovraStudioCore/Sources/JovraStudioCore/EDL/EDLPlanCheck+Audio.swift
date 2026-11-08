import Foundation

/// One piece of the audio bed after its own shape is checked.
struct EDLBedPiece {
    let route: String
    let outIn: Int
    let outOut: Int
    let sourceId: String?
    let fadeInMs: Int
    let fadeOutMs: Int
    var src: EDLPlanSource?
    var sIn = 0
    var n = 0
    var cov: Int?

    func overlaps(_ seg: EDLSegmentInfo) -> Bool { seg.outIn < outOut && outIn < seg.outOut }
}

/// The audio bed, narration and music (`edl._check_audio`, `_check_bed_switches`).
extension EDLPlanCheck {
    static let routes: Set<String> = ["primary-bed", "alt-bed", "hold-bed", "silence"]

    func checkAudio(_ raw: StudioJSONValue) throws {
        let audio = try EDLJSON.fields(raw, "primarySourceId bed narration music", "audio")
        guard let bed = EDLJSON.array(audio["bed"]), (1...256).contains(bed.count) else {
            throw EDLFinding(.bedCoverage, "the bed needs 1-256 pieces")
        }
        let allSilent = bed.allSatisfy { EDLJSON.object($0) != nil && $0["route"] == .string("silence") }
        var primary: String?
        if allSilent {
            try require(audio["primarySourceId"] == .null, .primaryBedSource, "an all-silent plan names no primary audio source")
        } else {
            let id = try EDLJSON.identifier(audio["primarySourceId"], "primarySourceId")
            try require(sources[id].map { $0.role == "match" && $0.hasAudio } == true, .primaryBedSource,
                        "the primary bed comes from a match source with audio")
            primary = id
        }
        let pieces = try bedPieces(bed, primary: primary)
        for p in pieces where p.route == "primary-bed" || (p.route == "alt-bed" && p.src?.role == "match") {
            // court audio that is not held dead time plays only under live play, where it is checked for sync: under a
            // replay, freeze, card or B-roll it would be unchecked court audio from any moment. There, the bed is
            // hold-bed (real dead time), B-roll audio, or silence.
            try require(order.filter(p.overlaps).allSatisfy { $0.op == "live" }, .courtBedOffLive,
                        "\(p.route) from \(p.sourceId ?? "-") at output frames \(p.outIn)-\(p.outOut) plays under a non-live "
                        + "segment; use hold-bed over real dead time, or silence")
        }
        try checkBedSwitches(pieces)

        let lives = order.filter { $0.op == "live" }
        for p in pieces where p.route == "hold-bed" {
            try require(order.filter(p.overlaps).allSatisfy { $0.op != "live" }, .holdBedOverLive,
                        "hold-bed plays only under replays, freezes, cards or B-roll")
            let b0 = p.src?.sessionUs(p.sIn, in: p.cov), b1 = p.src?.sessionUs(p.sIn + p.n, in: p.cov)
            let dead = b0.flatMap { b0 in b1.map { b1 in
                lives.allSatisfy { live in live.session.map { $0.1 <= b0 || b1 <= $0.0 } ?? true }
            } } ?? false
            try require(dead, .holdBedNotDeadTime, "hold-bed must be real dead time that no live segment shows")
        }
        if allSilent { return }
        try checkBedSync(lives: lives, pieces: pieces)
        try checkNarration(audio["narration"])
        try checkMusic(audio["music"])
    }

    private func bedPieces(_ bed: [StudioJSONValue], primary: String?) throws -> [EDLBedPiece] {
        var cursor = 0
        var pieces: [EDLBedPiece] = []
        for item in bed {
            let p = try EDLJSON.fields(item, "route sourceId sourceInFrame outputInFrame outputOutFrame fadeInMs fadeOutMs",
                                       "bed piece")
            guard let route = EDLJSON.string(p["route"]), Self.routes.contains(route) else {
                throw EDLFinding(.badEnum, "unknown audio route")
            }
            let oIn = try EDLJSON.integer(p["outputInFrame"], "bed outputInFrame")
            let oOut = try EDLJSON.integer(p["outputOutFrame"], "bed out", minimum: 1)
            try require(oIn == cursor && oIn < oOut && oOut <= total, .bedCoverage,
                        "exactly one bed route per output frame, contiguous from frame 0")
            cursor = oOut
            let fin = try EDLJSON.integer(p["fadeInMs"], "fadeInMs"), fout = try EDLJSON.integer(p["fadeOutMs"], "fadeOutMs")
            try require(fin <= 2000 && fout <= 2000, .badFade, "fades are at most 2000 ms")
            if route == "silence" {
                try require(p["sourceId"] == .null && p["sourceInFrame"] == .null, .silenceBindsAudio,
                            "silence must not bind a source")
                try require(fin >= 10 && fout >= 10, .fadeTooShort, "silence needs >= 10 ms fades")
                pieces.append(EDLBedPiece(route: route, outIn: oIn, outOut: oOut, sourceId: nil, fadeInMs: fin, fadeOutMs: fout))
                continue
            }
            let srcId = try EDLJSON.identifier(p["sourceId"], "bed sourceId")
            guard let src = sources[srcId], src.hasAudio else {
                throw EDLFinding(.bedSourceUnavailable, "bed source has no audio")
            }
            let sIn = try EDLJSON.integer(p["sourceInFrame"], "bed sourceInFrame")
            let nSrc = EDLFraction(oOut - oIn) * src.fps / outFps
            guard nSrc.denominator == .one, let n = nSrc.numerator.intValue else {
                throw EDLFinding(.bedClock, "bed window is not a whole number of source frames")
            }
            guard let cov = src.interval(sIn, sIn + n) else {
                throw EDLFinding(.outsideCoverage, "bed window leaves the source coverage or crosses a gap")
            }
            var piece = EDLBedPiece(route: route, outIn: oIn, outOut: oOut, sourceId: srcId, fadeInMs: fin, fadeOutMs: fout)
            piece.src = src
            piece.sIn = sIn
            piece.n = n
            piece.cov = cov
            if route == "primary-bed" || route == "hold-bed" {
                try require(srcId == primary, .primaryBedSource, "\(route) uses the designated primary source")
            }
            if route == "alt-bed" {
                try require(srcId != primary, .badAltBed, "alt-bed switches to another source's audio")
                try require(fin >= 20 && fout >= 20, .fadeTooShort, "alt-bed needs >= 20 ms fades")
            }
            if route == "hold-bed" {
                let prev = pieces.last
                try require(prev.map { ($0.route == "primary-bed" || $0.route == "hold-bed") && $0.sourceId == srcId
                                       && $0.sIn + $0.n == sIn } == true,
                            .holdBedNotContinuous, "hold-bed continues the primary bed without a jump")
            }
            pieces.append(piece)
        }
        try require(cursor == total, .bedCoverage, "the bed must cover every output frame")
        return pieces
    }

    /// Every change of bed source (another source, or to or from silence) sits on a segment boundary, never inside a
    /// segment. At a cut, each sounding side fades for at least 20 ms (silence keeps its own 10 ms minimum). At a
    /// dissolve or dip, the switch becomes an audio dip across the picture transition. The same source continuing is
    /// not a switch only when it continues without a jump.
    private func checkBedSwitches(_ pieces: [EDLBedPiece]) throws {
        let starts = Dictionary(order.map { ($0.outIn, $0) }, uniquingKeysWith: { first, _ in first })
        for (a, b) in zip(pieces, pieces.dropFirst()) {
            if a.sourceId == b.sourceId && (a.sourceId == nil || a.sIn + a.n == b.sIn) { continue }
            guard let seg = starts[b.outIn] else {
                throw EDLFinding(.bedSwitchNotAtBoundary,
                                 "the bed changes source at output frame \(b.outIn), inside a segment; switch only at a boundary")
            }
            let tr = seg.seg["transitionIn"]
            let kind = tr["type"].flatMap(EDLJSON.string) ?? "cut"
            let needOut: EDLInteger, needIn: EDLInteger
            if kind == "cut" {
                needOut = EDLInteger(a.sourceId != nil ? 20 : 0)
                needIn = EDLInteger(b.sourceId != nil ? 20 : 0)
            } else {
                let frames = tr["frames"].flatMap(EDLJSON.exactInt) ?? 0
                let hOut = frames / 2, hIn = frames - hOut
                needOut = (EDLFraction(hIn * 1000) / outFps).ceil
                needIn = (EDLFraction(hOut * 1000) / outFps).ceil
            }
            try require(EDLInteger(a.fadeOutMs) >= needOut && EDLInteger(b.fadeInMs) >= needIn, .fadeTooShort,
                        "bed switch at output frame \(b.outIn) (\(kind)) needs fades of at least \(needOut) ms out and \(needIn) ms in")
        }
    }

    /// Live play is under the primary (or a point-boundary alternate) court bed, in sync to half an output frame.
    private func checkBedSync(lives: [EDLSegmentInfo], pieces: [EDLBedPiece]) throws {
        let half = outFrameDurationUs / EDLFraction(2)
        for live in lives {
            guard let liveSrc = live.src else { continue }
            for p in pieces {
                let lo = max(live.outIn, p.outIn), hi = min(live.outOut, p.outOut)
                if lo >= hi { continue }
                try require(p.route == "primary-bed" || p.route == "alt-bed", .liveWithoutCourtAudio,
                            "live play is under the primary (or a point-boundary alternate) court bed")
                guard let bedSrc = p.src else { continue }
                for o in [lo, hi - 1] {
                    let v = liveSrc.sessionUs(EDLFraction(live.sIn) + EDLFraction(o - live.outIn) * liveSrc.fps * live.speed / outFps,
                                              in: live.cov)
                    let a = bedSrc.sessionUs(EDLFraction(p.sIn) + EDLFraction(o - p.outIn) * bedSrc.fps / outFps, in: p.cov)
                    let inSync = v.flatMap { v in a.map { a in (v - a).magnitude <= half } } ?? false
                    try require(inSync, .bedOutOfSync, "court audio is out of sync with the picture at output frame \(o) "
                                + "(limit: half an output frame)")
                }
            }
        }
    }

    private func checkNarration(_ raw: StudioJSONValue) throws {
        if raw == .null { return }
        let narration = try EDLJSON.fields(raw, "voice consent disclosureTemplateId duckDb scriptNoteIds windows", "narration")
        try require(grammar.narration, .opNotAllowed, "narration is not used in this profile")
        guard let voice = EDLJSON.string(narration["voice"]), voice == "user-recorded" || voice == "generated" else {
            throw EDLFinding(.badEnum, "narration voice")
        }
        let consent = try EDLJSON.fields(narration["consent"], "consentRecordId granted", "narration consent")
        let consentId = try EDLJSON.identifier(consent["consentRecordId"], "consentRecordId")
        try require(consent["granted"] == .bool(true), .consentMissing, "narration needs recorded consent")
        if voice == "generated" {
            try require(EDLJSON.string(narration["disclosureTemplateId"]) == "label.narration-generated", .disclosureMissing,
                        "generated narration is labelled and disclosed")
        } else {
            try require(narration["disclosureTemplateId"] == .null, .badNarration, "only generated narration is labelled")
        }
        let need = voice == "generated" ? "generated-voice" : "narration-voice"
        try require(context.consents[consentId].map { $0.granted && $0.scope.contains(need) } == true, .consentMissing,
                    "narration needs a stored, granted \(need) consent; a plan cannot attest its own consent")
        try require(EDLJSON.exactInt(narration["duckDb"]).map { (-24 ... -6).contains($0) } == true, .badNarration,
                    "court bed ducks by 6-24 dB under narration")
        guard let notes = EDLJSON.array(narration["scriptNoteIds"]), !notes.isEmpty else {
            throw EDLFinding(.badNarration, "a narration script is grounded in stored notes")
        }
        for note in notes {
            try resolveNote(try EDLJSON.identifier(note, "scriptNoteId"), "narration scriptNoteId")
        }
        try checkWindows(narration["windows"], "narration")
    }

    private func checkMusic(_ raw: StudioJSONValue) throws {
        if raw == .null { return }
        let music = try EDLJSON.fields(raw, "assetId rightsRecordId rightsScope windows", "music")
        try require(grammar.music, .opNotAllowed, "music is not used in this profile")
        let assetId = try EDLJSON.identifier(music["assetId"], "music assetId")
        let rightsId = try EDLJSON.identifier(music["rightsRecordId"], "rightsRecordId")
        let scope = EDLJSON.array(music["rightsScope"]).map { $0.compactMap(EDLJSON.string) }
        try require(scope != nil && scope?.count == EDLJSON.array(music["rightsScope"])?.count
                    && scope?.contains("private-film") == true, .rightsMissing,
                    "music needs rights for at least the private film")
        let stored = context.rights[rightsId]
        try require(stored.map { $0.assetId == assetId && Set(scope ?? []).isSubset(of: Set($0.scope)) } == true,
                    .rightsMissing, "music needs a stored rights record for this asset covering every claimed scope; "
                    + "a plan cannot attest its own rights")
        try checkWindows(music["windows"], "music")
    }
}
