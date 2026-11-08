import Foundation

/// Pre-roll and post-roll rules shared by segmentation, the plan and the session writers (N7, story 195).
public enum RallyRolls {
    public static let defaultPreRollMs = 1_500
    public static let defaultPostRollMs = 2_500
    /// The most a single clip may be widened by (session.schema.json `rollMs`).
    public static let maxClipRollMs = 10_000
    /// Playback settings: 0–5 s in 0.5 s steps.
    public static let maxSessionRollMs = 5_000
    public static let sessionRollStepMs = 500

    static func check(_ roll: Int) throws(RallyError) {
        guard (0...maxClipRollMs).contains(roll) else { throw .rollOutOfRange }
    }

    static func checkTime(_ tMs: Int, durationMs: Int) throws(RallyError) {
        guard tMs >= 0, tMs <= durationMs else { throw .timeOutsideRecording }
    }

    /// `[startMs - preRollMs, endMs + postRollMs)` clamped to `[0, durationMs]`.
    static func clip(startMs: Int, endMs: Int, preRollMs: Int, postRollMs: Int, durationMs: Int) -> MediaRange {
        MediaRange(fromMs: max(0, startMs - preRollMs), toMs: min(durationMs, endMs + postRollMs))
    }
}

/// A point or mark the rally-only plan cuts around: a point event's `tStartMs`/`tEndMs`, or a mark's time twice.
public struct RallyTarget: Codable, Equatable, Hashable, Sendable {
    public let targetId: String
    public let startMs: Int
    public let endMs: Int

    public init(targetId: String, startMs: Int, endMs: Int) {
        self.targetId = targetId
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// Rally-only playback and the condensed export (ios-v1-spec `RallyOnlyPlan.build`, screens.md N7): the merged
/// ranges to play and the gaps between them, each gap keeping its duration for its "+0:42" chip.
public struct RallyOnlyPlan: Codable, Equatable, Sendable {
    public struct PlannedRange: Codable, Equatable, Sendable {
        /// Half-open session time.
        public let range: MediaRange
        public let durationMs: Int
        /// The points and marks this range plays, in time order.
        public let targetIds: [String]

        public init(range: MediaRange, durationMs: Int, targetIds: [String]) {
            self.range = range
            self.durationMs = durationMs
            self.targetIds = targetIds
        }
    }

    /// Skipped session time, shown as a GapChip ("+0:42"), never silently closed up.
    public struct Gap: Codable, Equatable, Sendable {
        public let range: MediaRange
        public let durationMs: Int
        public let label: String

        public init(range: MediaRange, durationMs: Int, label: String) {
            self.range = range
            self.durationMs = durationMs
            self.label = label
        }
    }

    public let ranges: [PlannedRange]
    public let gaps: [Gap]
    /// Deselected in the Rallies list: left out of playback and exports, never out of the session.
    public let excludedTargetIds: [String]
    /// What rally-only playback shows ("Rally only · 18 min of 54").
    public let keptMs: Int
    public let skippedMs: Int
    public let durationMs: Int

    public init(ranges: [PlannedRange], gaps: [Gap], excludedTargetIds: [String], keptMs: Int, skippedMs: Int, durationMs: Int) {
        self.ranges = ranges
        self.gaps = gaps
        self.excludedTargetIds = excludedTargetIds
        self.keptMs = keptMs
        self.skippedMs = skippedMs
        self.durationMs = durationMs
    }

    /// Widens each target by its rolls (a clip entry beats the session's, which beat the 1.5 s / 2.5 s defaults),
    /// clamps it to the recording, merges ranges that overlap or touch, and lists every gap including the lead-in
    /// and the tail. `keptMs + skippedMs == durationMs`.
    public static func build(targets: [RallyTarget], rolls: SessionRallyPlayback?, durationMs: Int) throws(RallyError) -> RallyOnlyPlan {
        let sessionPre = rolls?.preRollMs ?? RallyRolls.defaultPreRollMs
        let sessionPost = rolls?.postRollMs ?? RallyRolls.defaultPostRollMs
        try RallyRolls.check(sessionPre)
        try RallyRolls.check(sessionPost)
        var overrides: [String: SessionRallyPlaybackClipsItem] = [:]
        for clip in rolls?.clips ?? [] {
            if let pre = clip.preRollMs { try RallyRolls.check(pre) }
            if let post = clip.postRollMs { try RallyRolls.check(post) }
            overrides[clip.targetId] = clip
        }
        var seen = Set<String>()
        for target in targets {
            guard seen.insert(target.targetId).inserted else { throw .duplicateId }
            guard target.endMs >= target.startMs else { throw .rangeBackwards }
            try RallyRolls.checkTime(target.startMs, durationMs: durationMs)
            try RallyRolls.checkTime(target.endMs, durationMs: durationMs)
        }

        var excluded: [String] = []
        var pieces: [(range: MediaRange, id: String)] = []
        for target in targets {
            let override = overrides[target.targetId]
            if override?.excluded == true { excluded.append(target.targetId); continue }
            let range = RallyRolls.clip(startMs: target.startMs, endMs: target.endMs,
                                        preRollMs: override?.preRollMs ?? sessionPre,
                                        postRollMs: override?.postRollMs ?? sessionPost, durationMs: durationMs)
            pieces.append((range, target.targetId))
        }
        pieces.sort { ($0.range.fromMs, $0.range.toMs, $0.id) < ($1.range.fromMs, $1.range.toMs, $1.id) }

        var merged: [(from: Int, to: Int, ids: [String])] = []
        for piece in pieces {
            if let last = merged.last, piece.range.fromMs <= last.to {
                merged[merged.count - 1] = (last.from, max(last.to, piece.range.toMs), last.ids + [piece.id])
            } else {
                merged.append((piece.range.fromMs, piece.range.toMs, [piece.id]))
            }
        }
        var gaps: [Gap] = []
        var cursor = 0
        for (from, to) in merged.map({ ($0.from, $0.to) }) + [(durationMs, durationMs)] {
            if from > cursor {
                gaps.append(Gap(range: MediaRange(fromMs: cursor, toMs: from), durationMs: from - cursor, label: gapLabel(from - cursor)))
            }
            cursor = max(cursor, to)
        }
        let ranges = merged.map { PlannedRange(range: MediaRange(fromMs: $0.from, toMs: $0.to), durationMs: $0.to - $0.from, targetIds: $0.ids) }
        return RallyOnlyPlan(ranges: ranges, gaps: gaps, excludedTargetIds: excluded.sorted(),
                             keptMs: ranges.reduce(0) { $0 + $1.durationMs }, skippedMs: gaps.reduce(0) { $0 + $1.durationMs },
                             durationMs: durationMs)
    }

    /// GapChip text: "+m:ss", or "+h:mm:ss" from one hour. Whole seconds are truncated so skipped time is never
    /// overstated (the same rule as `DurationLabel`).
    public static func gapLabel(_ durationMs: Int) -> String {
        let seconds = max(0, durationMs) / 1_000
        let (hours, minutes, secs) = (seconds / 3_600, seconds % 3_600 / 60, seconds % 60)
        let two = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "+\(hours):\(two(minutes)):\(two(secs))" : "+\(minutes):\(two(secs))"
    }
}
