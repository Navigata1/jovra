import Foundation
import JovraCore

/// The project's staleness ledger, `staleness.json` in the project folder: a local app document (like `studio.json`),
/// not a shared contract. It keeps what the plan and film records cannot say on their own: the revisions a spared plan
/// was carried to, and the keeper reason (`jovra.delivered-artifact/1` `stale.reason` has no `keeper-revision` value
/// yet, spec/studio/modules/keepers.md, "Decisions").
public struct StudioStalenessLedger: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "jovra.studio-staleness/1"
    static let fileName = "staleness.json"

    public struct Plan: Codable, Equatable, Sendable {
        public var planId: String
        public var editPlanSha256: String
        public var status: String
        public var reasons: [String]
        public var eventRevision: Int
        public var syncRevision: Int
        public var keeperCatalogRevision: Int
    }

    public struct Film: Codable, Equatable, Sendable {
        public var artifactId: String
        public var planId: String?
        public var status: String
        /// "Made before a correction" when stale.
        public var label: String?
        public var reasons: [String]
        public var keptAsVersion: Bool
    }

    public struct LastChange: Codable, Equatable, Sendable {
        public var kind: String
        public var revision: Int
        /// The sources or keepers it named, or the points the core fold recalculated (`ScoringEngine.diff`).
        public var named: [String]
    }

    public var schemaVersion: String
    public var plans: [Plan]
    public var films: [Film]
    public var lastChange: LastChange?

    public func plan(_ planId: String) -> Plan? { plans.first { $0.planId == planId } }
    public func film(_ artifactId: String) -> Film? { films.first { $0.artifactId == artifactId } }
}

/// What one revision change writes, computed before anything is written.
struct StudioStalenessUpdate: Sendable {
    let projectId: String
    let ledger: StudioStalenessLedger
    /// Films whose record gains its `stale` block now.
    let films: [DeliveredArtifact]
}

/// SD20 in the store: every revision the store records (event-log version, sync revision, keeper revision) runs
/// staleness propagation over the project's stored plans and films **in the same actor transaction**: dependent plans
/// become stale, their films are labelled "Made before a correction" and kept as versions, and the revision is saved
/// last, so a crash part-way leaves plans no fresher than before (a plan bound behind its project is stale on its own).
extension StudioProjectStore {
    /// Records a newer sync map revision naming the sources whose mapping changed: only plans that cut or play one of
    /// them go stale; the others are carried to the new revision.
    @discardableResult
    public func recordSyncRevision(_ revision: Int, changedSources: [String], for projectId: String) throws -> StudioProjectRevisions {
        try advance(projectId, .sync, to: revision, named: changedSources)
    }

    /// Records a newer keeper-catalog revision naming the keepers that changed (what `KeeperEdits` returns).
    @discardableResult
    public func recordKeeperRevision(_ revision: Int, changedKeepers: [String], for projectId: String) throws -> StudioProjectRevisions {
        try advance(projectId, .keepers, to: revision, named: changedKeepers)
    }

    /// The project's plans and films with their status now, and the ledger's last change.
    public func staleness(_ projectId: String) throws -> (result: StudioStaleness.Result, lastChange: StudioStalenessLedger.LastChange?) {
        let project = try project(projectId)
        let state = try stalenessState(project)
        let result = try judge(state, project: project, change: nil)
        return (result.result, state.ledger?.lastChange)
    }

    /// Refuses a plan made before a correction (story 233): a stale plan is never rendered as current.
    public func requireCurrentPlan(_ planId: String, in projectId: String) throws {
        let (result, _) = try staleness(projectId)
        guard let plan = result.plans.first(where: { $0.planId == planId }) else { throw StudioProjectStoreError.notFound }
        guard plan.status == .current else { throw StudioProjectStoreError.planStale(planId) }
    }

    // MARK: Transaction

    func advance(_ projectId: String, _ kind: StudioStaleness.ChangeKind, to revision: Int, named: [String]?) throws -> StudioProjectRevisions {
        var project = try project(projectId)
        let before = project.revisions
        var revisions = before
        switch kind {
        case .event: revisions.eventLogVersion = try Self.monotonic(before.eventLogVersion, revision)
        case .sync: revisions.syncRevision = try Self.monotonic(before.syncRevision, revision)
        case .keepers: revisions.keeperRevision = try Self.monotonic(before.keeperRevision, revision)
        }
        guard revisions != before else { return revisions }
        let update = try stalenessUpdate(for: project, kind, to: revision, named: named)
        if let update { try commit(update) }
        project.revisions = revisions
        try save(project)
        return revisions
    }

    /// The writes a change makes, or nil when the project has no plans or films to judge.
    func stalenessUpdate(for project: StudioProject, _ kind: StudioStaleness.ChangeKind, to revision: Int,
                         named: [String]?) throws -> StudioStalenessUpdate? {
        let state = try stalenessState(project)
        guard !state.plans.isEmpty || !state.films.isEmpty else { return nil }
        let uses = Set(state.plans.flatMap { kind == .sync ? $0.dep.sourceIds : $0.dep.keeperIds })
        // Without names, everything the plans use changed (the conservative reading).
        var names = named ?? uses.sorted(by: codePointPrecedes)
        if kind != .event, names.isEmpty { names = ["(all)"] }
        let change = StudioStaleness.Change(kind: kind, projectId: project.projectId, revision: revision, named: names)
        let judged = try judge(state, project: project, change: change)
        let current = judged.result.current[project.projectId]!
        var stamped: [DeliveredArtifact] = []
        for status in judged.result.films where status.status == .stale {
            guard var film = state.films.first(where: { $0.artifactId == status.artifactId }), film.stale.value == nil else { continue }
            // the record's stale reasons are event, sync, manifest and profile revisions; a keeper-only reason stays
            // in the ledger until the schema has a value for it
            let reason: DeliveredArtifactStaleReason?
            if status.reasons.contains(.eventRevision) { reason = .eventRevision }
            else if status.reasons.contains(.syncRevision) { reason = .syncRevision }
            else { reason = nil }
            guard let reason else { continue }
            film.stale = .value(DeliveredArtifactStale(reason: reason, currentEventRevision: current.eventRevision))
            stamped.append(film)
        }
        let ledger = StudioStalenessLedger(
            schemaVersion: StudioStalenessLedger.currentSchemaVersion,
            plans: judged.result.plans.map { p in
                StudioStalenessLedger.Plan(planId: p.planId, editPlanSha256: state.plans.first { $0.dep.planId == p.planId }!.dep.editPlanSha256,
                                           status: p.status.rawValue, reasons: p.reasons.map(\.rawValue),
                                           eventRevision: p.bindings.eventRevision, syncRevision: p.bindings.syncRevision,
                                           keeperCatalogRevision: p.bindings.keeperCatalogRevision)
            },
            films: judged.result.films.map { f in
                StudioStalenessLedger.Film(artifactId: f.artifactId, planId: f.planId.isEmpty ? nil : f.planId, status: f.status.rawValue,
                                           label: f.label, reasons: f.reasons.map(\.rawValue), keptAsVersion: f.keptAsVersion)
            },
            lastChange: .init(kind: kind.rawValue, revision: revision, named: named ?? []))
        return StudioStalenessUpdate(projectId: project.projectId, ledger: ledger, films: stamped)
    }

    /// Writes the labelled films and the ledger (each temp-then-rename). Films are relabelled, never re-rendered or
    /// deleted.
    func commit(_ update: StudioStalenessUpdate) throws {
        let folder = try subfolder(.films, of: update.projectId)
        for film in update.films {
            let bytes: Data
            do { bytes = try StudioContractCodec.encode(film) } catch { throw StudioProjectStoreError.invalidRecord(film.artifactId) }
            try atomic.write(bytes, named: "\(film.artifactId).json", in: folder)
        }
        try atomic.write(CanonicalJSON.encode(update.ledger), named: StudioStalenessLedger.fileName,
                         in: projectFolder(update.projectId))
    }

    // MARK: Reading the project

    struct StalenessState {
        struct StoredPlan {
            let dep: StudioStaleness.PlanDependencies
        }

        let plans: [StoredPlan]
        let films: [DeliveredArtifact]
        let ledger: StudioStalenessLedger?
    }

    struct Judged {
        let result: StudioStaleness.Result
    }

    func stalenessState(_ project: StudioProject) throws -> StalenessState {
        let id = project.projectId
        let ledger = try readLedger(id)
        var plans: [StalenessState.StoredPlan] = []
        for name in try recordNames(in: .plans, of: id) {
            guard let data = try record(named: name, in: .plans, of: id),
                  (try? StudioRecordHeader(json: data))?.schemaVersion.kind == "edit-plan" else { continue }
            var dep: StudioStaleness.PlanDependencies
            do { dep = try StudioStaleness.planDependencies(record: data) } catch { throw StudioProjectStoreError.invalidRecord(name) }
            guard dep.projectId == id else { throw StudioProjectStoreError.invalidRecord(name) }
            // a plan the ledger carried forward keeps its carried bindings (same plan, same bytes)
            if let carried = ledger?.plan(dep.planId), carried.editPlanSha256 == dep.editPlanSha256 {
                dep.bindings = .init(eventRevision: carried.eventRevision, syncRevision: carried.syncRevision,
                                     keeperCatalogRevision: carried.keeperCatalogRevision)
            }
            plans.append(.init(dep: dep))
        }
        return StalenessState(plans: plans, films: try films(id), ledger: ledger)
    }

    /// Propagation over the stored state. A film whose plan is not stored cannot be matched by hash: it stays as the
    /// ledger last judged it, and any change makes it stale (it cannot be shown to be current).
    func judge(_ state: StalenessState, project: StudioProject, change: StudioStaleness.Change?) throws -> Judged {
        let id = project.projectId
        let r = project.revisions
        let revisions = StudioStaleness.Revisions(eventRevision: r.eventLogVersion, syncRevision: r.syncRevision,
                                                  keeperCatalogRevision: r.keeperRevision)
        let hashes = Set(state.plans.map(\.dep.editPlanSha256))
        let matched = state.films.filter { hashes.contains($0.bindings.editPlanSha256) }
        let unmatched = state.films.filter { !hashes.contains($0.bindings.editPlanSha256) }
        var result: StudioStaleness.Result
        do {
            result = try StudioStaleness.propagate(
                projects: [id: revisions], plans: state.plans.map(\.dep),
                films: matched.map { film in
                    var dep = StudioStaleness.filmDependencies(film)
                    dep.stale = dep.stale || state.ledger?.film(film.artifactId)?.status == StudioStaleness.Status.stale.rawValue
                    return dep
                },
                changes: change.map { [$0] } ?? [])
        } catch let rejection as StudioStaleness.Rejection {
            throw StudioProjectStoreError.stalenessRefused(rejection.code.rawValue)
        }
        for film in unmatched {
            let before = state.ledger?.film(film.artifactId)
            let stale = film.stale.value != nil || before?.status == StudioStaleness.Status.stale.rawValue || change != nil
            let reasons = (before?.reasons.compactMap(StudioStaleness.Reason.init(rawValue:)) ?? []) + (change.map { [$0.kind.reason] } ?? [])
            result.films.append(StudioStaleness.FilmStatus(
                artifactId: film.artifactId, projectId: id, planId: "", status: stale ? .stale : .current,
                label: stale ? StudioStaleness.filmLabel : nil, reasons: Array(Set(reasons)).sorted(), keptAsVersion: true))
        }
        result.films.sort { codePointPrecedes($0.artifactId, $1.artifactId) }
        result.staleFilmIds = result.films.filter { $0.status == .stale }.map(\.artifactId).sorted(by: codePointPrecedes)
        return Judged(result: result)
    }

    func readLedger(_ projectId: String) throws -> StudioStalenessLedger? {
        let url = try projectFolder(projectId).appendingPathComponent(StudioStalenessLedger.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try StudioPath.refuseSymbolicLink(url)
        guard let ledger = try? JSONDecoder().decode(StudioStalenessLedger.self, from: Data(contentsOf: url)),
              ledger.schemaVersion == StudioStalenessLedger.currentSchemaVersion else {
            throw StudioProjectStoreError.invalidRecord(StudioStalenessLedger.fileName)
        }
        return ledger
    }

    /// The points a correction recalculated: the core fold of the log as it was at `version` against the fold now
    /// (`ScoringEngine.diff`). Core logs only grow (a correction is a new event), so the earlier log is the prefix up
    /// to that `seq`. Empty when the session has no match to fold.
    func recalculatedPointIds(sessionId: String, since version: Int) async throws -> [String] {
        guard let document = try await loadSession(sessionId), let input = try? ScoringInput(session: document) else { return [] }
        var earlier = input
        earlier.log = input.log.filter { $0.seq <= version }
        guard let before = try? ScoringEngine.fold(earlier), let after = try? ScoringEngine.fold(input) else { return [] }
        return ScoringEngine.diff(previous: before, current: after).recalculatedPointIds
    }
}
