import Foundation

/// Story 195: pre-roll and post-roll per session (Playback settings) and per clip (the clip range sheet and the
/// Rallies list), written into `session.rallyPlayback`. Each edit returns a new document; the original is untouched.
/// The edits match spec/reference/jovra_ref/rally.py's writers byte for byte (spec/fixtures/rally/session.rolls.json).
public extension SessionDocument {
    /// Sets the session's rolls: 0–5 s in 0.5 s steps (N7).
    func settingRallyRolls(preRollMs: Int, postRollMs: Int) throws(RallyError) -> SessionDocument {
        for roll in [preRollMs, postRollMs] {
            guard (0...RallyRolls.maxSessionRollMs).contains(roll), roll % RallyRolls.sessionRollStepMs == 0 else {
                throw .rollOutOfRange
            }
        }
        var copy = withRallyPlayback()
        copy.rallyPlayback?.preRollMs = preRollMs
        copy.rallyPlayback?.postRollMs = postRollMs
        return copy
    }

    /// Sets one clip's own rolls (0–10 s); nil leaves that side as it was.
    func settingClipRolls(targetId: String, preRollMs: Int? = nil, postRollMs: Int? = nil) throws(RallyError) -> SessionDocument {
        if let preRollMs { try RallyRolls.check(preRollMs) }
        if let postRollMs { try RallyRolls.check(postRollMs) }
        return try editingClip(targetId) { clip in
            if let preRollMs { clip.preRollMs = preRollMs }
            if let postRollMs { clip.postRollMs = postRollMs }
        }
    }

    /// Deselects (or reselects) a clip in the Rallies list. Deselected clips leave rally-only playback and exports,
    /// never the session.
    func settingClipExcluded(targetId: String, _ excluded: Bool) throws(RallyError) -> SessionDocument {
        try editingClip(targetId) { clip in clip.excluded = excluded ? true : nil }
    }

    private var rallyTargetIds: Set<String> {
        var ids = Set((marks ?? []).map(\.id))
        for case .point(let point) in match?.log ?? [] { ids.insert(point.id) }
        return ids
    }

    /// rallyPlayback is a 1.1.0 field, so a 1.0 document is stamped 1.1.0 when it gains one ($defs/v1_0).
    private func withRallyPlayback() -> SessionDocument {
        var copy = self
        if copy.schemaVersion.minor < 1 { copy.schemaVersion = .v1_1 }
        if copy.rallyPlayback == nil {
            copy.rallyPlayback = SessionRallyPlayback(preRollMs: RallyRolls.defaultPreRollMs, postRollMs: RallyRolls.defaultPostRollMs)
        }
        return copy
    }

    private func editingClip(_ targetId: String, _ edit: (inout SessionRallyPlaybackClipsItem) -> Void) throws(RallyError) -> SessionDocument {
        guard rallyTargetIds.contains(targetId) else { throw .unknownTarget }
        var copy = withRallyPlayback()
        var clips = copy.rallyPlayback?.clips ?? []
        if !clips.contains(where: { $0.targetId == targetId }) {
            clips.append(SessionRallyPlaybackClipsItem(targetId: targetId))
        }
        if let index = clips.firstIndex(where: { $0.targetId == targetId }) { edit(&clips[index]) }
        copy.rallyPlayback?.clips = clips
        return copy
    }
}
