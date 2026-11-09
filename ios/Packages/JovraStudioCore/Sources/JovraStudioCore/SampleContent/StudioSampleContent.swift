import Foundation
import JovraCore

public enum StudioSampleContentError: Error, Equatable, Sendable {
    /// A sample record is missing from the records folder.
    case missingRecord(String)
    /// A record is not flagged Sample; nothing from it may be installed (CLAUDE.md hard rule 1).
    case notSample(String)
    /// A record breaks its contract, or names another project.
    case invalidRecord(String)
    /// The core sample library does not hold the Jon vs Alex session the match sample reuses.
    case missingCoreSample(String)
}

/// The distinct Sample identities Studio installs (spec StudioSampleContent; implementation-states "Sample source of
/// truth"). Each names the shipped records (`spec/studio/fixtures/records`, bundled as `StudioSample`) it is made of;
/// every number a screen shows for it is computed from these records by the same code as real data.
public enum StudioSampleIdentity: String, CaseIterable, Sendable {
    /// The match: the core Jon vs Alex 124-point log (fold 6-4 6-3, Final) with synthetic multi-angle renders.
    case match
    /// Three 60-minute metadata-only sources of 3.6 GB each, whose bytes are not bundled.
    case importSources = "import"
    /// +120 ms and 18 ms/min on Camera 2 only.
    case sync
    /// Sep 9, Sep 23 and Oct 7 lessons.
    case lesson
    /// Sep 9 12/30 vs Oct 7 18/30 serve practice.
    case progress
    /// The Court Memories film metadata (04:18, 1080p, chapters).
    case courtMemoriesFilm
    /// Camera 2 source 00:12.400-00:18.600 placed at 00:12.000-00:18.200.
    case storyboard
    /// Upload, Align, Build film 42%, Verify queued.
    case queue
    /// $4-$8, $12 cap, Sample (illustrative).
    case quote
    /// Device active; iCloud Drive choose folder; Google Drive not connected; Box, Dropbox planned; cloud off.
    case provider

    /// The record files this identity is made of.
    public var recordNames: [String] {
        switch self {
        case .match:
            ["project-lock.json", "keeper-catalog.json", "broll-catalog.json", "reference-catalog.json",
             "story-brief.court-memories.json", "edit-plan.match-broadcast-set-1.json",
             "edit-plan.rally-pulse-portrait.json", "edit-plan.rally-pulse-portrait.clean.json",
             "edit-plan.coach-cut-serve.json", "observation.calibrated-bounce.json",
             "observation.estimated-cue.json", "observation.reviewed-cue.json", "camera-invite.json"]
        case .importSources: ["source-manifest.json"]
        case .sync: ["sync-map.json"]
        case .lesson: ["lesson.2026-09-09.json", "lesson.2026-09-23.json", "lesson.2026-10-07.json"]
        case .progress: ["story-brief.progress.json"]
        case .courtMemoriesFilm: ["delivered-artifact.film.json", "edit-plan.court-memories-final.json"]
        case .storyboard: ["edit-plan.court-memories-storyboard.json", "edit-plan.court-memories-storyboard.clean.json"]
        case .queue: ["render-job.queue-sample.json", "render-job.ready.json"]
        case .quote: ["quote.sample-illustrative.json", "quote.accepted.json", "quote.accepted-storyboard.json",
                      "usage-reservation.held.json", "usage-reservation.settled.json"]
        case .provider: ["storage-providers.json"]
        }
    }

    /// The identity's project: the lessons form their own lesson-series project; everything else is the match's.
    public var projectId: String {
        self == .lesson ? StudioSampleContent.lessonProjectID : StudioSampleContent.matchProjectID
    }
}

/// The Studio sample's records as shipped, read from a folder (the app bundle's `StudioSample` resources, or
/// `spec/studio/fixtures/records`). Every record must say `"sample": true`; the typed ones are read strictly.
public struct StudioSampleRecords: Sendable {
    /// Bytes by file name, exactly as shipped.
    public let files: [String: Data]
    public let sourceManifest: SourceManifest
    public let syncMap: SyncMap
    public let keeperCatalog: KeeperCatalog
    public let projectLock: ProjectLock
    public let lessons: [Lesson]

    public init(files: [String: Data]) throws {
        let needed = StudioSampleIdentity.allCases.flatMap(\.recordNames)
        for name in needed {
            guard let bytes = files[name] else { throw StudioSampleContentError.missingRecord(name) }
            let header: StudioRecordHeader
            do { header = try StudioRecordHeader(json: bytes) } catch { throw StudioSampleContentError.invalidRecord(name) }
            guard header.isSample else { throw StudioSampleContentError.notSample(name) }
        }
        func decode<T: StudioContract>(_ type: T.Type, _ name: String) throws -> T {
            do { return try StudioContractCodec.decode(type, from: files[name]!) }
            catch { throw StudioSampleContentError.invalidRecord("\(name): \(error)") }
        }
        self.files = files.filter { needed.contains($0.key) }
        sourceManifest = try decode(SourceManifest.self, "source-manifest.json")
        syncMap = try decode(SyncMap.self, "sync-map.json")
        keeperCatalog = try decode(KeeperCatalog.self, "keeper-catalog.json")
        projectLock = try decode(ProjectLock.self, "project-lock.json")
        lessons = try StudioSampleIdentity.lesson.recordNames.map { try decode(Lesson.self, $0) }
        for name in needed where name != "storage-providers.json" && !name.hasPrefix("lesson.") {
            struct Owner: Decodable { let projectId: String? }
            let owner = try? JSONDecoder().decode(Owner.self, from: files[name]!)
            guard owner?.projectId == StudioSampleContent.matchProjectID else {
                throw StudioSampleContentError.invalidRecord("\(name) names another project")
            }
        }
    }

    /// Reads every record an identity needs from `directory`.
    public static func load(from directory: URL) throws -> StudioSampleRecords {
        var files: [String: Data] = [:]
        for name in StudioSampleIdentity.allCases.flatMap(\.recordNames) {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { throw StudioSampleContentError.missingRecord(name) }
            files[name] = try Data(contentsOf: url)
        }
        return try StudioSampleRecords(files: files)
    }
}

/// Installs and removes the Studio sample (spec StudioSampleContent). It needs no account, network or upload
/// (story 13); every project it installs carries `isSample` and every record says `"sample": true` (story 14); it
/// never touches the core session store, so the player's stats, trends, lessons and goals are unchanged (story 15,
/// the core sample-scope rule); and one call removes it all (story 16).
public struct StudioSampleContent: Sendable {
    /// The core Jon vs Alex sample session (core T09, spec/fixtures/sample/library/sessions/jon-vs-alex.session.json).
    public static let matchSessionID = "b75c57d3-04df-5b4d-b969-32ed5cbfd97a"
    /// The match sample's project id, as its records name it.
    public static let matchProjectID = "sample-court-day"
    public static let lessonProjectID = "sample-lesson-series"

    public let records: StudioSampleRecords

    public init(records: StudioSampleRecords) {
        self.records = records
    }

    /// Installs what is missing: the match project and the lesson-series project, with every record copied byte for
    /// byte into its project folder. A Sample project already installed is kept as it is; a real project using a
    /// sample id is never touched (`idInUse`). Installing works whatever `localStudio` says: the sample is the safe
    /// way to look at Studio.
    public func install(into store: StudioProjectStore) async throws {
        try await store.installSampleProject(matchProject())
        try await store.installSampleProject(lessonProject())
        for identity in StudioSampleIdentity.allCases {
            for name in identity.recordNames {
                let (folder, fileName) = Self.placement(of: name)
                if try await store.record(named: fileName, in: folder, of: identity.projectId) == nil {
                    try await store.writeRecord(records.files[name]!, named: fileName, in: folder, of: identity.projectId)
                }
            }
        }
    }

    /// Deletes every Sample project; real projects stay. Returns the removed project ids.
    @discardableResult
    public func remove(from store: StudioProjectStore) async throws -> [String] {
        try await store.removeSampleProjects()
    }

    public static func isInstalled(in store: StudioProjectStore) async throws -> Bool {
        try await !store.projects(sample: true).isEmpty
    }

    /// The match project document, from the source manifest, sync map, keeper catalog and lock records.
    public func matchProject() throws -> StudioProject {
        let manifest = records.sourceManifest
        let lock = records.projectLock
        let owners = Dictionary(uniqueKeysWithValues: lock.sourceRights.map { ($0.sourceId, $0.ownerParticipantId) })
        let sources = manifest.sources.map { source in
            StudioProjectSource(sourceId: source.sourceId,
                                // Camera 1 is the core Jon vs Alex session; the other angles are metadata only.
                                sessionId: source.isPrimary ? Self.matchSessionID : nil,
                                segmentIds: source.segments.map(\.segmentId), slot: source.slot.value,
                                role: source.role, ownerParticipantId: owners[source.sourceId])
        }
        return StudioProject(
            projectId: Self.matchProjectID, kind: .match, sample: true, createdAt: manifest.createdAt,
            environment: lock.environment, primarySourceId: manifest.sources.first { $0.isPrimary }?.sourceId,
            sources: sources, participants: lock.participants, privacy: lock.privacy,
            revisions: StudioProjectRevisions(sourceManifestRevision: manifest.revision,
                                              syncRevision: records.syncMap.revision,
                                              keeperRevision: records.keeperCatalog.revision,
                                              eventLogVersion: lock.eventRevision),
            lockRevision: lock.revision)
    }

    /// The lesson-series project; it holds the three lesson records and no camera sources.
    public func lessonProject() throws -> StudioProject {
        guard let first = records.lessons.map(\.date).min() else { throw StudioSampleContentError.missingRecord("lesson") }
        return StudioProject(projectId: Self.lessonProjectID, kind: .lessonSeries, sample: true,
                             createdAt: "\(first)T00:00:00Z", environment: records.projectLock.environment)
    }

    /// The core sample session the match sample's primary source reuses.
    public static func matchSession(in library: SampleLibrary) throws -> SessionDocument {
        guard let session = library.sessions.first(where: { $0.id == matchSessionID }), session.sample != nil else {
            throw StudioSampleContentError.missingCoreSample(matchSessionID)
        }
        return session
    }

    /// Where a shipped record goes in its project folder: by contract kind; the lock is stored as revision 1.
    static func placement(of name: String) -> (StudioProjectFolder, String) {
        switch name {
        case "source-manifest.json": (.manifests, name)
        case "sync-map.json": (.sync, name)
        case "project-lock.json": (.locks, "project-lock.r1.json")
        case "camera-invite.json": (.room, name)
        case "storage-providers.json": (.providers, name)
        case _ where name.hasSuffix("-catalog.json"): (.catalogs, name)
        case _ where name.hasPrefix("edit-plan.") || name.hasPrefix("story-brief."): (.plans, name)
        case _ where name.hasPrefix("delivered-artifact."): (.films, name)
        case _ where name.hasPrefix("render-job."): (.jobs, name)
        case _ where name.hasPrefix("quote.") || name.hasPrefix("usage-reservation."): (.quotes, name)
        case _ where name.hasPrefix("observation."): (.observations, name)
        case _ where name.hasPrefix("lesson."): (.lessons, name)
        default: (.manifests, name)
        }
    }
}
