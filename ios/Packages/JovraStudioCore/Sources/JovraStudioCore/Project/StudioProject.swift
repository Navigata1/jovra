import Foundation
import JovraCore

/// What a Studio project is for (spec StudioProjectStore): one match filmed by one or more phones, or a series of
/// lessons. A single phone is a complete match project (story 22).
public enum StudioProjectKind: String, Codable, CaseIterable, Hashable, Sendable {
    case match
    case lessonSeries
}

/// One camera angle of a project. The original is **referenced** by its core session and segments, never copied:
/// an imported angle becomes an ordinary core session first (core ImportPipeline), so the own-your-footage contract,
/// backup exclusion and archive apply to it unchanged.
public struct StudioProjectSource: Codable, Equatable, Sendable {
    /// Stable within the project, `camera-<n>` in the order sources were added.
    public var sourceId: String
    /// The core session holding the original. `nil` only for a Sample metadata-only angle whose bytes are not bundled
    /// (the import sample); a real project never has one.
    public var sessionId: String?
    /// The session's recording segments this source uses; empty means every segment.
    public var segmentIds: [String]
    /// The camera slot; `nil` until assigned. Two sources never hold the same slot (except `custom`).
    public var slot: StudioPlacementSlot?
    public var role: SourceManifestSourceRole
    /// Who owns this footage (the lock's `sourceRights`); `nil` until a participant is named.
    public var ownerParticipantId: String?

    public init(sourceId: String, sessionId: String?, segmentIds: [String] = [], slot: StudioPlacementSlot?,
                role: SourceManifestSourceRole = .match, ownerParticipantId: String? = nil) {
        self.sourceId = sourceId
        self.sessionId = sessionId
        self.segmentIds = segmentIds
        self.slot = slot
        self.role = role
        self.ownerParticipantId = ownerParticipantId
    }
}

/// The revisions every plan and film is bound to (spec SD20). Each only ever increases; a change to any of them marks
/// dependent plans stale and films "Made before a correction".
public struct StudioProjectRevisions: Codable, Equatable, Sendable {
    /// Bumped whenever the source set, a slot or the primary changes.
    public var sourceManifestRevision: Int
    /// The project's current sync map revision (angle alignment).
    public var syncRevision: Int
    /// The keeper catalog revision (KeeperSelector).
    public var keeperRevision: Int
    /// Snapshot of the primary session's event-log version (the highest event `seq`), as core exports record it.
    public var eventLogVersion: Int

    public init(sourceManifestRevision: Int = 0, syncRevision: Int = 0, keeperRevision: Int = 0, eventLogVersion: Int = 0) {
        self.sourceManifestRevision = sourceManifestRevision
        self.syncRevision = syncRevision
        self.keeperRevision = keeperRevision
        self.eventLogVersion = eventLogVersion
    }
}

/// The project document, `studio.json` in the project's folder. A local app document (like core's `session.json`),
/// not a shared contract: its `schemaVersion` is `jovra.studio-project/1`, and an unknown version is refused.
public struct StudioProject: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "jovra.studio-project/1"

    public var schemaVersion: String
    public var projectId: String
    public var kind: StudioProjectKind
    /// True for the Studio sample (StudioSampleContent): shown labelled "Sample", never counted in the player's
    /// stats, trends, lessons or goals, and removed in one action.
    public var sample: Bool
    public var createdAt: String
    public var environment: StudioEnvironment
    public var primarySourceId: String?
    public var sources: [StudioProjectSource]
    /// The people in the project, as a lock states them.
    public var participants: [ProjectLockParticipant]
    /// Privacy by default: venue not visible, location hidden.
    public var privacy: ProjectLockPrivacy
    public var revisions: StudioProjectRevisions
    /// The revision of the latest `ProjectLock`; 0 before the first lock.
    public var lockRevision: Int

    public var isSample: Bool { sample }

    public init(projectId: String, kind: StudioProjectKind, sample: Bool, createdAt: String,
                environment: StudioEnvironment, primarySourceId: String? = nil, sources: [StudioProjectSource] = [],
                participants: [ProjectLockParticipant] = [],
                privacy: ProjectLockPrivacy = .init(venueVisible: false, locationHidden: true),
                revisions: StudioProjectRevisions = .init(), lockRevision: Int = 0) {
        self.schemaVersion = Self.currentSchemaVersion
        self.projectId = projectId
        self.kind = kind
        self.sample = sample
        self.createdAt = createdAt
        self.environment = environment
        self.primarySourceId = primarySourceId
        self.sources = sources
        self.participants = participants
        self.privacy = privacy
        self.revisions = revisions
        self.lockRevision = lockRevision
    }

    /// The primary source, if one is set.
    public var primarySource: StudioProjectSource? { sources.first { $0.sourceId == primarySourceId } }
}

/// One row of the project index (`index.json`), a disposable cache of the project folders.
public struct StudioProjectSummary: Codable, Equatable, Sendable {
    public let projectId: String
    public let kind: StudioProjectKind
    public let sample: Bool
    public let createdAt: String

    init(_ project: StudioProject) {
        projectId = project.projectId
        kind = project.kind
        sample = project.sample
        createdAt = project.createdAt
    }
}
