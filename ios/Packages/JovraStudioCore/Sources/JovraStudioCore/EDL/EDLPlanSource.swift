import Foundation

/// One source snapshot of a plan, after its own shape is checked (`edl.Source`).
struct EDLPlanSource: Sendable {
    /// A half-open coverage interval `[lo, hi)` of proxy frames; match coverage carries its session start and rate.
    struct Coverage: Sendable {
        let lo: Int
        let hi: Int
        let start: Int?
        let rate: EDLFraction?
    }

    static let maxOutputSeconds = 14_400
    static let sessionRateDen = 1_000_000_000

    let id: String
    let role: String
    let sha256: String
    let fps: EDLFraction
    let fpsNum: Int
    let fpsDen: Int
    let width: Int
    let height: Int
    let frames: Int
    let hasAudio: Bool
    let coverage: [Coverage]

    /// Exact duration of one proxy frame in microseconds.
    var frameDurationUs: EDLFraction { EDLValidator.frameDurationUs(num: fpsNum, den: fpsDen) }

    init(_ raw: StudioJSONValue) throws {
        let obj = try EDLJSON.fields(raw, "id role sha256 proxy hasAudio coverage", "source")
        id = try EDLJSON.identifier(obj["id"], "source id")
        guard let role = EDLJSON.string(obj["role"]), role == "match" || role == "broll" else {
            throw EDLFinding(.badEnum, "source role must be match or broll")
        }
        self.role = role
        try require(EDLJSON.isHex64(obj["sha256"]), .badHash, "source sha256 must be 64 lowercase hex")
        sha256 = EDLJSON.string(obj["sha256"]) ?? ""
        let proxy = try EDLJSON.fields(obj["proxy"], "fps width height frameCount ptsTableSha256", "source proxy")
        (fpsNum, fpsDen, fps) = try EDLValidator.fps(proxy["fps"], "proxy fps")
        width = try EDLJSON.integer(proxy["width"], "proxy width", minimum: 2)
        height = try EDLJSON.integer(proxy["height"], "proxy height", minimum: 2)
        frames = try EDLJSON.integer(proxy["frameCount"], "proxy frameCount", minimum: 1)
        try require(EDLFraction(frames) / fps <= EDLFraction(Self.maxOutputSeconds), .sourceTooLong,
                    "source exceeds four hours")
        try require(EDLJSON.isHex64(proxy["ptsTableSha256"]), .badHash, "proxy ptsTableSha256 must be 64 lowercase hex")
        guard let hasAudio = EDLJSON.boolean(obj["hasAudio"]) else { throw EDLFinding(.badBoolean, "hasAudio must be boolean") }
        self.hasAudio = hasAudio
        guard let intervals = EDLJSON.array(obj["coverage"]), (1...64).contains(intervals.count) else {
            throw EDLFinding(.badCoverage, "coverage needs 1-64 intervals")
        }
        var cursor = 0
        var coverage: [Coverage] = []
        for raw in intervals {
            let c = try EDLJSON.fields(raw, "inFrame outFrame sessionStartUs rate", "coverage interval")
            let lo = try EDLJSON.integer(c["inFrame"], "coverage inFrame")
            let hi = try EDLJSON.integer(c["outFrame"], "coverage outFrame", minimum: 1)
            try require(cursor <= lo && lo < hi && hi <= frames, .badCoverage,
                        "coverage intervals must be ordered, disjoint and inside the proxy")
            cursor = hi
            if role == "broll" {
                try require(c["sessionStartUs"] == .null && c["rate"] == .null, .badCoverage,
                            "B-roll is not on the session clock (sessionStartUs and rate are null)")
                coverage.append(Coverage(lo: lo, hi: hi, start: nil, rate: nil))
            } else {
                let start = try EDLJSON.integer(c["sessionStartUs"], "coverage sessionStartUs")
                let rate = try EDLJSON.fields(c["rate"], "num den", "coverage rate")
                guard let den = EDLJSON.exactInt(rate["den"]), den == Self.sessionRateDen,
                      let num = EDLJSON.exactInt(rate["num"]), (900_000_000...1_100_000_000).contains(num) else {
                    throw EDLFinding(.badRate, "rate must be num/1000000000 within 0.9-1.1")
                }
                coverage.append(Coverage(lo: lo, hi: hi, start: start, rate: EDLFraction(num, den)))
            }
        }
        self.coverage = coverage
    }

    /// The index of the coverage interval containing the source-frame range `[lo, hi)`, else nil (gap or outside).
    func interval(_ lo: Int, _ hi: Int) -> Int? {
        coverage.firstIndex { $0.lo <= lo && hi <= $0.hi }
    }

    /// Exact session time of a (possibly fractional) proxy frame position, or nil off the session clock.
    ///
    /// Coverage intervals are half-open and may be adjacent (a restart). Without `cov` the lookup is half-open, so the
    /// first frame of a restarted interval maps through that interval, never through the previous interval's
    /// extrapolated end; the exclusive end of the last interval is allowed. With `cov` (the interval a window was
    /// already found inside) the position may equal that interval's exclusive end, which is how a window's end time
    /// is computed.
    func sessionUs(_ frame: EDLFraction, in cov: Int? = nil) -> EDLFraction? {
        var index = cov
        if index == nil {
            index = coverage.firstIndex { EDLFraction($0.lo) <= frame && frame < EDLFraction($0.hi) }
            if index == nil, let last = coverage.last, frame == EDLFraction(last.hi) { index = coverage.count - 1 }
        }
        guard let index else { return nil }
        let c = coverage[index]
        guard EDLFraction(c.lo) <= frame, frame <= EDLFraction(c.hi), let start = c.start, let rate = c.rate else { return nil }
        return EDLFraction(start) + (frame - EDLFraction(c.lo)) * frameDurationUs * rate
    }

    func sessionUs(_ frame: Int, in cov: Int? = nil) -> EDLFraction? { sessionUs(EDLFraction(frame), in: cov) }
}
