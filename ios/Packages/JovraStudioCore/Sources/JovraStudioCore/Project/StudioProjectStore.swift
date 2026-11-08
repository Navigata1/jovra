import Foundation
import JovraCore

public enum StudioProjectStoreError: Error, Equatable, Sendable {
    case invalidID, unsafePath, notFound, alreadyExists, writeFailed
    case renameFailed(Int32), durabilityUnconfirmed(Int32)
    /// studio.json names a version this build cannot read.
    case unsupportedVersion(String)
    /// Another source already holds this camera slot (story 27): the warning the UI shows before two phones record
    /// the same slot.
    case slotTaken(StudioPlacementSlot, heldBy: String)
    case unknownSource(String)
    /// The core session a source names does not exist.
    case sessionNotFound(String)
    /// A revision may only grow (SD20).
    case revisionRegressed(current: Int, offered: Int)
    /// `StudioEntitlements.localStudio` is off: no new Studio film project or film lock. The reason is user-facing.
    case localStudioUnavailable(reason: String)
    /// A lock needs the project's source manifest (`manifests/source-manifest.json`).
    case manifestMissing
    /// The stored source manifest is not the revision the project is at.
    case manifestStale(manifest: Int, project: Int)
    /// Every match source in a lock needs an owner (the lock's `sourceRights`).
    case ownerMissing(String)
    /// A lock outside demo needs the signed-in identity.
    case identityRequired
    /// A film record with this id already exists; older versions are kept, never overwritten (story 163).
    case filmExists(String)
    /// A record is not a Studio record for this project, or breaks its contract.
    case invalidRecord(String)
    /// A real project already uses this id.
    case idInUse(String)
}

/// The folders of a project. Records live in their folder by kind; originals never live here.
public enum StudioProjectFolder: String, CaseIterable, Sendable {
    case manifests, sync, catalogs, plans, edls, films, proxies, locks, jobs, quotes, observations, lessons
    case room, providers, cloud
}

/// What `delete(_:of:)` removes. **No scope deletes an original**: originals live in core session folders, and
/// deleting one stays the core's explicit, confirmed action.
public enum StudioDeleteScope: String, CaseIterable, Sendable {
    /// Rebuildable output: films and proxies (story 165). The project, its plans and manifests stay.
    case derived
    /// The project's record of cloud copies (story 225). Local originals and films stay.
    case cloudCopies
    /// The whole project folder: plans, films, proxies, records. Originals stay in their sessions.
    case project
}

/// Bytes used by a project's derived output, so films and proxies can be managed apart from originals (story 165).
public struct StudioProjectStorage: Equatable, Sendable {
    public let filmsBytes: Int64
    public let proxiesBytes: Int64

    public init(filmsBytes: Int64, proxiesBytes: Int64) {
        self.filmsBytes = filmsBytes
        self.proxiesBytes = proxiesBytes
    }
}

/// Studio projects as folders in app storage (spec StudioProjectStore):
///
/// ```
/// <root>/index.json                       disposable cache, rebuilt from the folders
/// <root>/projects/<projectId>/studio.json versioned, written temp-then-rename
/// <root>/projects/<projectId>/<folder>/   manifests, sync, catalogs, plans, edls, films, proxies, locks, ...
/// ```
///
/// All writers share this actor. Each transaction validates, reads and writes without a suspension point once it
/// starts writing, so two calls never interleave inside one read-modify-write.
public actor StudioProjectStore {
    public nonisolated let entitlements: StudioEntitlements
    let root: URL
    let projectsFolder: URL
    private let sessions: SessionStore?
    private let environment: StudioEnvironment
    private let now: @Sendable () -> Date
    private let atomic: StudioAtomicFile

    /// - Parameters:
    ///   - sessions: the core session store; when given, every source's session must exist there.
    ///   - environment: the Studio environment this build runs in (Config/Studio.xcconfig; `demo` by default).
    public init(root: URL, entitlements: StudioEntitlements = .build, sessions: SessionStore? = nil,
                environment: StudioEnvironment = .demo, now: @escaping @Sendable () -> Date = { Date() },
                writeFault: (@Sendable (StudioProjectWriteCheckpoint) throws -> Void)? = nil) throws {
        self.root = root.standardizedFileURL
        self.projectsFolder = self.root.appendingPathComponent("projects", isDirectory: true)
        self.entitlements = entitlements
        self.sessions = sessions
        self.environment = environment
        self.now = now
        self.atomic = StudioAtomicFile(fault: writeFault)
        try DurableDirectory.create(at: projectsFolder)
        try StudioPath.refuseSymbolicLink(self.root)
        try StudioPath.refuseSymbolicLink(projectsFolder)
    }

    // MARK: Projects

    /// Starts a project. With `primarySession` it holds that session as `camera-1`, the primary: one phone is a
    /// complete path (story 22). Refused when `localStudio` is off.
    public func create(kind: StudioProjectKind, primarySession: String? = nil,
                       segmentIds: [String] = []) async throws -> StudioProject {
        try requireLocalStudio()
        if let primarySession { try await requireSession(primarySession) }
        let id = UUID().uuidString.lowercased()
        var project = StudioProject(projectId: id, kind: kind, sample: false, createdAt: timestamp(),
                                    environment: environment)
        if let primarySession {
            project.sources = [StudioProjectSource(sourceId: "camera-1", sessionId: primarySession,
                                                   segmentIds: segmentIds, slot: nil)]
            project.primarySourceId = "camera-1"
            project.revisions.sourceManifestRevision = 1
        }
        try insert(project)
        return project
    }

    public func project(_ id: String) throws -> StudioProject {
        let url = try folder(id).appendingPathComponent("studio.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw StudioProjectStoreError.notFound }
        try StudioPath.refuseSymbolicLink(url)
        let data = try Data(contentsOf: url)
        struct Version: Decodable { let schemaVersion: String }
        let version = try JSONDecoder().decode(Version.self, from: data).schemaVersion
        guard version == StudioProject.currentSchemaVersion else { throw StudioProjectStoreError.unsupportedVersion(version) }
        let project = try ContractCodec.decode(StudioProject.self, from: data)
        guard project.projectId == id else { throw StudioProjectStoreError.invalidID }
        return project
    }

    /// Every project, oldest first, from the index when it matches the folders and from the folders otherwise
    /// (a missing, unreadable or stale index is rebuilt). `sample: false` is the player's own projects only.
    public func projects(sample: Bool? = nil) throws -> [StudioProjectSummary] {
        let all = try indexedProjects()
        return all.filter { sample == nil || $0.sample == sample }
    }

    // MARK: Sources, slots and the primary

    /// Adds a core session as a new source. The original stays in its session; only the reference is stored.
    @discardableResult
    public func addSource(sessionId: String, segmentIds: [String] = [], slot: StudioPlacementSlot?,
                          role: SourceManifestSourceRole = .match, owner: String? = nil,
                          to projectId: String) async throws -> StudioProjectSource {
        guard StudioPath.isValidID(sessionId) else { throw StudioProjectStoreError.invalidID }
        try await requireSession(sessionId)
        var project = try project(projectId)
        if let slot { try requireFree(slot, in: project, except: nil) }
        let next = (project.sources.compactMap { Int($0.sourceId.dropFirst("camera-".count)) }.max() ?? 0) + 1
        let source = StudioProjectSource(sourceId: "camera-\(next)", sessionId: sessionId, segmentIds: segmentIds,
                                         slot: slot, role: role, ownerParticipantId: owner)
        project.sources.append(source)
        if project.primarySourceId == nil, role == .match { project.primarySourceId = source.sourceId }
        project.revisions.sourceManifestRevision += 1
        try save(project)
        return source
    }

    /// Puts a source in a slot (or clears it with `nil`). An occupied slot is refused with `slotTaken`; `custom` is
    /// a free-form placement and may be held by more than one source.
    @discardableResult
    public func assignSlot(_ slot: StudioPlacementSlot?, to sourceId: String, in projectId: String) throws -> StudioProject {
        var project = try project(projectId)
        guard let index = project.sources.firstIndex(where: { $0.sourceId == sourceId }) else {
            throw StudioProjectStoreError.unknownSource(sourceId)
        }
        if let slot { try requireFree(slot, in: project, except: sourceId) }
        guard project.sources[index].slot != slot else { return project }
        project.sources[index].slot = slot
        project.revisions.sourceManifestRevision += 1
        try save(project)
        return project
    }

    @discardableResult
    public func setPrimary(_ sourceId: String, in projectId: String) throws -> StudioProject {
        var project = try project(projectId)
        guard project.sources.contains(where: { $0.sourceId == sourceId }) else {
            throw StudioProjectStoreError.unknownSource(sourceId)
        }
        guard project.primarySourceId != sourceId else { return project }
        project.primarySourceId = sourceId
        project.revisions.sourceManifestRevision += 1
        try save(project)
        return project
    }

    /// Names the people in the project (the lock's participants) and, optionally, who owns each source.
    @discardableResult
    public func setParticipants(_ participants: [ProjectLockParticipant], owners: [String: String] = [:],
                                in projectId: String) throws -> StudioProject {
        var project = try project(projectId)
        let ids = Set(participants.map(\.participantId))
        guard ids.count == participants.count, owners.values.allSatisfy(ids.contains) else {
            throw StudioProjectStoreError.invalidRecord("participants")
        }
        for (sourceId, owner) in owners {
            guard let index = project.sources.firstIndex(where: { $0.sourceId == sourceId }) else {
                throw StudioProjectStoreError.unknownSource(sourceId)
            }
            project.sources[index].ownerParticipantId = owner
        }
        project.participants = participants
        try save(project)
        return project
    }

    // MARK: Revisions

    public func revisions(_ projectId: String) throws -> StudioProjectRevisions {
        try project(projectId).revisions
    }

    /// Records a newer sync map revision; an older one is refused, the same one is a no-op.
    @discardableResult
    public func recordSyncRevision(_ revision: Int, for projectId: String) throws -> StudioProjectRevisions {
        try advance(projectId) { $0.syncRevision = try Self.monotonic($0.syncRevision, revision) }
    }

    @discardableResult
    public func recordKeeperRevision(_ revision: Int, for projectId: String) throws -> StudioProjectRevisions {
        try advance(projectId) { $0.keeperRevision = try Self.monotonic($0.keeperRevision, revision) }
    }

    @discardableResult
    public func recordEventLogVersion(_ version: Int, for projectId: String) throws -> StudioProjectRevisions {
        try advance(projectId) { $0.eventLogVersion = try Self.monotonic($0.eventLogVersion, version) }
    }

    /// Reads the primary session's event-log version (its highest event `seq`) from the core session store.
    @discardableResult
    public func refreshEventLogVersion(for projectId: String) async throws -> StudioProjectRevisions {
        guard let sessions, let sessionId = try project(projectId).primarySource?.sessionId else {
            return try revisions(projectId)
        }
        let document = try await sessions.load(sessionId)
        return try recordEventLogVersion(document.match?.log.map(\.seq).max() ?? 0, for: projectId)
    }

    // MARK: Records

    /// Stores a Studio record of this project in `folder` (its bytes verbatim, temp-then-rename). It must be a
    /// Studio record (a `jovra.<kind>/<n>` header) whose Sample flag matches the project's.
    public func writeRecord(_ bytes: Data, named name: String, in folder: StudioProjectFolder,
                            of projectId: String) throws {
        let project = try project(projectId)
        guard StudioPath.isValidFileName(name) else { throw StudioProjectStoreError.invalidID }
        let header: StudioRecordHeader
        do { header = try StudioRecordHeader(json: bytes) } catch { throw StudioProjectStoreError.invalidRecord(name) }
        guard header.isSample == project.sample else { throw StudioProjectStoreError.invalidRecord(name) }
        try atomic.write(bytes, named: name, in: subfolder(folder, of: projectId))
    }

    /// A stored record's bytes, or `nil`.
    public func record(named name: String, in folder: StudioProjectFolder, of projectId: String) throws -> Data? {
        guard StudioPath.isValidFileName(name) else { throw StudioProjectStoreError.invalidID }
        _ = try project(projectId)
        let url = try projectFolder(projectId).appendingPathComponent(folder.rawValue, isDirectory: true)
            .appendingPathComponent(name)
        try StudioPath.refuseSymbolicLink(url)
        return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    /// Names of the records in `folder`, sorted.
    public func recordNames(in folder: StudioProjectFolder, of projectId: String) throws -> [String] {
        _ = try project(projectId)
        let url = try projectFolder(projectId).appendingPathComponent(folder.rawValue, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try StudioPath.refuseSymbolicLink(url)
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { StudioPath.isValidFileName($0) }.sorted()
    }

    // MARK: Films

    /// Keeps a film record. A rebuild is a new artifact id; an existing film is never overwritten (story 163).
    public func recordFilm(_ film: DeliveredArtifact, in projectId: String) throws {
        let project = try project(projectId)
        guard film.projectId == projectId, film.sample == project.sample, StudioPath.isValidID(film.artifactId) else {
            throw StudioProjectStoreError.invalidRecord(film.artifactId)
        }
        let folder = try subfolder(.films, of: projectId)
        let name = "\(film.artifactId).json"
        guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) else {
            throw StudioProjectStoreError.filmExists(film.artifactId)
        }
        let bytes: Data
        do { bytes = try StudioContractCodec.encode(film) } catch { throw StudioProjectStoreError.invalidRecord(film.artifactId) }
        try atomic.write(bytes, named: name, in: folder)
    }

    /// Every film of the project, each read strictly as a `jovra.delivered-artifact/1` record, by artifact id.
    /// Films stay readable whatever `localStudio` says.
    public func films(_ projectId: String) throws -> [DeliveredArtifact] {
        try recordNames(in: .films, of: projectId).compactMap { name in
            guard let data = try record(named: name, in: .films, of: projectId),
                  (try? StudioRecordHeader(json: data))?.schemaVersion.kind == "delivered-artifact" else { return nil }
            do { return try StudioContractCodec.decode(DeliveredArtifact.self, from: data) }
            catch { throw StudioProjectStoreError.invalidRecord(name) }
        }.sorted { $0.artifactId < $1.artifactId }
    }

    // MARK: Lock

    /// Freezes what a film is built from (story 162): the source manifest (revision and canonical SHA-256), the
    /// event-log version, the sync revision, the profile and the output. Each lock is a new revision, kept in
    /// `locks/project-lock.r<n>.json`. Refused when `localStudio` is off.
    public func lock(profile: ProjectLockProfile, output: ProjectLockOutput, identity: ProjectLockIdentity? = nil,
                     in projectId: String) throws -> ProjectLock {
        try requireLocalStudio()
        var project = try project(projectId)
        guard let manifestBytes = try record(named: "source-manifest.json", in: .manifests, of: projectId) else {
            throw StudioProjectStoreError.manifestMissing
        }
        let manifest: SourceManifest
        do { manifest = try StudioContractCodec.decode(SourceManifest.self, from: manifestBytes) }
        catch { throw StudioProjectStoreError.invalidRecord("source-manifest.json") }
        guard manifest.revision == project.revisions.sourceManifestRevision else {
            throw StudioProjectStoreError.manifestStale(manifest: manifest.revision, project: project.revisions.sourceManifestRevision)
        }
        // Rights cover the match angles; b-roll clips carry their rights in the b-roll catalog.
        let rights = try project.sources.filter { $0.role == .match }.map { source -> ProjectLockSourceRight in
            guard let owner = source.ownerParticipantId else { throw StudioProjectStoreError.ownerMissing(source.sourceId) }
            return ProjectLockSourceRight(sourceId: source.sourceId, ownerParticipantId: owner, cloudConsent: false,
                                          consentRecordId: .null)
        }
        let resolvedIdentity: ProjectLockIdentity
        if let identity { resolvedIdentity = identity }
        else if project.environment == .demo { resolvedIdentity = ProjectLockIdentity(mode: .demoProfile, accountRef: .null) }
        else { throw StudioProjectStoreError.identityRequired }
        let revisions = project.revisions
        let lock = ProjectLock(
            projectId: projectId, revision: project.lockRevision + 1, sample: project.sample,
            environment: project.environment, identity: resolvedIdentity, createdAt: timestamp(),
            sourceManifest: ProjectLockSourceManifest(revision: manifest.revision,
                                                      sha256: StudioSHA256.hex(try CanonicalJSON.encode(manifest))),
            eventRevision: revisions.eventLogVersion,
            syncRevision: revisions.syncRevision == 0 ? .null : .value(revisions.syncRevision),
            profile: profile, output: output, participants: project.participants, sourceRights: rights,
            privacy: project.privacy, quoteAuthorization: .null, brand: ProjectLockBrand())
        let bytes: Data
        do { bytes = try StudioContractCodec.encode(lock) } catch { throw StudioProjectStoreError.invalidRecord("project-lock: \(error)") }
        try atomic.write(bytes, named: "project-lock.r\(lock.revision).json", in: subfolder(.locks, of: projectId))
        project.lockRevision = lock.revision
        try save(project)
        return lock
    }

    // MARK: Storage and deletion

    public func storage(_ projectId: String) throws -> StudioProjectStorage {
        _ = try project(projectId)
        let folder = try projectFolder(projectId)
        return StudioProjectStorage(filmsBytes: try Self.bytes(under: folder.appendingPathComponent("films")),
                                    proxiesBytes: try Self.bytes(under: folder.appendingPathComponent("proxies")))
    }

    /// Deletes by scope. Nothing here can reach an original: they live in core session folders, a source holds only
    /// a reference, and a link inside a project folder is removed as a link, never followed.
    public func delete(_ scope: StudioDeleteScope, of projectId: String) throws {
        _ = try project(projectId)
        let folder = try projectFolder(projectId)
        switch scope {
        case .derived:
            try removeIfPresent(folder.appendingPathComponent(StudioProjectFolder.films.rawValue, isDirectory: true))
            try removeIfPresent(folder.appendingPathComponent(StudioProjectFolder.proxies.rawValue, isDirectory: true))
        case .cloudCopies:
            try removeIfPresent(folder.appendingPathComponent(StudioProjectFolder.cloud.rawValue, isDirectory: true))
        case .project:
            try removeIfPresent(folder)
            try DurableDirectory.synchronize(projectsFolder)
            writeIndex()
        }
    }

    // MARK: Sample support (StudioSampleContent)

    /// Writes a Sample project document as given (the sample installer's records state its revisions).
    func installSampleProject(_ project: StudioProject) throws {
        guard project.sample else { throw StudioProjectStoreError.invalidRecord(project.projectId) }
        let url = try folder(project.projectId)
        if FileManager.default.fileExists(atPath: url.path) {
            guard (try? self.project(project.projectId))?.sample == true else {
                throw StudioProjectStoreError.idInUse(project.projectId)
            }
            return
        }
        try insert(project)
    }

    /// Deletes every Sample project; a real project, or a folder that cannot be read as a Sample project, stays.
    func removeSampleProjects() throws -> [String] {
        var removed: [String] = []
        for id in try folderIDs() where (try? project(id))?.sample == true {
            try removeIfPresent(try projectFolder(id))
            removed.append(id)
        }
        try DurableDirectory.synchronize(projectsFolder)
        writeIndex()
        return removed.sorted()
    }

    // MARK: Internals

    private func requireLocalStudio() throws {
        guard entitlements.localStudio else {
            throw StudioProjectStoreError.localStudioUnavailable(reason: StudioEntitlements.localStudioUnavailableReason)
        }
    }

    private func requireSession(_ id: String) async throws {
        guard StudioPath.isValidID(id) else { throw StudioProjectStoreError.invalidID }
        guard let sessions else { return }
        do { _ = try await sessions.load(id) }
        catch SessionStoreError.notFound { throw StudioProjectStoreError.sessionNotFound(id) }
    }

    private func requireFree(_ slot: StudioPlacementSlot, in project: StudioProject, except sourceId: String?) throws {
        guard slot != .custom else { return }
        if let holder = project.sources.first(where: { $0.slot == slot && $0.sourceId != sourceId }) {
            throw StudioProjectStoreError.slotTaken(slot, heldBy: holder.sourceId)
        }
    }

    private static func monotonic(_ current: Int, _ offered: Int) throws -> Int {
        guard offered >= current else { throw StudioProjectStoreError.revisionRegressed(current: current, offered: offered) }
        return offered
    }

    private func advance(_ projectId: String, _ change: (inout StudioProjectRevisions) throws -> Void) throws -> StudioProjectRevisions {
        var project = try project(projectId)
        var revisions = project.revisions
        try change(&revisions)
        guard revisions != project.revisions else { return revisions }
        project.revisions = revisions
        try save(project)
        return revisions
    }

    private func insert(_ project: StudioProject) throws {
        let url = try folder(project.projectId)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw StudioProjectStoreError.alreadyExists }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do {
            try save(project)
            try DurableDirectory.synchronize(projectsFolder)
        } catch {
            if !FileManager.default.fileExists(atPath: url.appendingPathComponent("studio.json").path) {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
        writeIndex()
    }

    private func save(_ project: StudioProject) throws {
        try atomic.write(CanonicalJSON.encode(project), named: "studio.json", in: projectFolder(project.projectId))
    }

    func folder(_ id: String) throws -> URL {
        guard StudioPath.isValidID(id) else { throw StudioProjectStoreError.invalidID }
        let url = projectsFolder.appendingPathComponent(id, isDirectory: true)
        try StudioPath.refuseSymbolicLink(url)
        return url
    }

    private func projectFolder(_ id: String) throws -> URL {
        let url = try folder(id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw StudioProjectStoreError.notFound }
        return url
    }

    private func subfolder(_ folder: StudioProjectFolder, of projectId: String) throws -> URL {
        let url = try projectFolder(projectId).appendingPathComponent(folder.rawValue, isDirectory: true)
        try StudioPath.refuseSymbolicLink(url)
        if !FileManager.default.fileExists(atPath: url.path) { try DurableDirectory.create(at: url) }
        return url
    }

    private func removeIfPresent(_ url: URL) throws {
        // `removeItem` deletes a symbolic link itself, never its target.
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func folderIDs() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: projectsFolder.path).filter { name in
            guard StudioPath.isValidID(name),
                  let type = try? FileManager.default.attributesOfItem(atPath: projectsFolder.appendingPathComponent(name).path)[.type] as? FileAttributeType
            else { return false }
            return type == .typeDirectory
        }.sorted()
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    private struct Index: Codable { let projects: [StudioProjectSummary] }

    private func indexedProjects() throws -> [StudioProjectSummary] {
        let ids = try folderIDs()
        if let data = try? Data(contentsOf: indexURL),
           let index = try? ContractCodec.decode(Index.self, from: data),
           index.projects.map(\.projectId).sorted() == ids {
            return index.projects
        }
        return writeIndex()
    }

    /// Rebuilds the index from the folders. A folder that cannot be read is left alone and not listed.
    @discardableResult
    private func writeIndex() -> [StudioProjectSummary] {
        let ids = (try? folderIDs()) ?? []
        let summaries = ids.compactMap { try? StudioProjectSummary(project($0)) }
            .sorted { ($0.createdAt, $0.projectId) < ($1.createdAt, $1.projectId) }
        // The index is disposable: failing to cache it never hides a project.
        if let bytes = try? CanonicalJSON.encode(Index(projects: summaries)) {
            try? atomic.write(bytes, named: "index.json", in: root)
        }
        return summaries
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: now())
    }

    private static func bytes(under url: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(atPath: url.path)
        while let path = enumerator?.nextObject() as? String {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent(path).path)
            if attributes[.type] as? FileAttributeType == .typeRegular {
                total += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        return total
    }
}
