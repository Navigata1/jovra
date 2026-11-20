import Foundation
import JovraCore

/// Staleness propagation (spec SD20; reference spec/reference/studio/staleness.py): which plans and films a revision
/// bump makes stale.
///
/// A plan depends on three revisions: the event revision (the point-event log), the sync revision and the
/// keeper-catalog revision.
/// - An **event** bump stales every plan of that project: scores, stats and keeper windows come from the whole fold.
/// - A **sync** bump names the sources whose mapping changed; only plans that cut or play one of them are stale, the
///   others are carried to the new sync revision.
/// - A **keeper** bump names the keepers that changed; only plans that use one of them are stale, the others are
///   carried to the new keeper-catalog revision.
/// A film is stale when its plan (matched by canonical edit-plan hash) is stale or it already was. It is labelled
/// "Made before a correction" and kept as a version: nothing is deleted or re-rendered.
public enum StudioStaleness {
    public static let filmLabel = "Made before a correction"

    /// A refusal with the reference's stable code.
    public struct Rejection: Error, Equatable, Sendable, CustomStringConvertible {
        public enum Code: String, Sendable {
            case badRevision, unknownProject, duplicateId, futureRevision, unknownChange, revisionNotIncreasing
            case badChange, unknownPlan, badInput
        }

        public let code: Code
        public let detail: String

        public init(_ code: Code, _ detail: String) {
            self.code = code
            self.detail = detail
        }

        public var description: String { "\(code.rawValue): \(detail)" }
    }

    /// The revisions a plan binds to, and a project's current ones.
    public struct Revisions: Equatable, Sendable {
        public var eventRevision: Int
        public var syncRevision: Int
        public var keeperCatalogRevision: Int

        public init(eventRevision: Int, syncRevision: Int, keeperCatalogRevision: Int) {
            self.eventRevision = eventRevision
            self.syncRevision = syncRevision
            self.keeperCatalogRevision = keeperCatalogRevision
        }

        subscript(kind: ChangeKind) -> Int {
            get {
                switch kind {
                case .event: eventRevision
                case .sync: syncRevision
                case .keepers: keeperCatalogRevision
                }
            }
            set {
                switch kind {
                case .event: eventRevision = newValue
                case .sync: syncRevision = newValue
                case .keepers: keeperCatalogRevision = newValue
                }
            }
        }
    }

    /// Why a plan or film is stale, in the reference's order.
    public enum Reason: String, Sendable, CaseIterable, Comparable {
        case eventRevision = "event-revision"
        case syncRevision = "sync-revision"
        case keeperRevision = "keeper-revision"

        var order: Int { Self.allCases.firstIndex(of: self)! }
        public static func < (a: Reason, b: Reason) -> Bool { a.order < b.order }
    }

    public enum ChangeKind: String, Sendable, CaseIterable {
        case event, sync, keepers

        var reason: Reason {
            switch self {
            case .event: .eventRevision
            case .sync: .syncRevision
            case .keepers: .keeperRevision
            }
        }
    }

    /// What a stored edit plan depends on.
    public struct PlanDependencies: Equatable, Sendable {
        public var planId: String
        public var planRevision: Int
        public var projectId: String
        public var editPlanSha256: String
        public var bindings: Revisions
        /// Every source a segment or the audio bed uses, sorted.
        public var sourceIds: [String]
        /// Every keeper a segment names, sorted.
        public var keeperIds: [String]

        public init(planId: String, planRevision: Int, projectId: String, editPlanSha256: String, bindings: Revisions,
                    sourceIds: [String], keeperIds: [String]) {
            self.planId = planId
            self.planRevision = planRevision
            self.projectId = projectId
            self.editPlanSha256 = editPlanSha256
            self.bindings = bindings
            self.sourceIds = sourceIds
            self.keeperIds = keeperIds
        }
    }

    /// What a delivered film depends on: the plan it was rendered from, and whether it is already stale.
    public struct FilmDependencies: Equatable, Sendable {
        public var artifactId: String
        public var projectId: String
        public var editPlanSha256: String
        public var stale: Bool

        public init(artifactId: String, projectId: String, editPlanSha256: String, stale: Bool) {
            self.artifactId = artifactId
            self.projectId = projectId
            self.editPlanSha256 = editPlanSha256
            self.stale = stale
        }
    }

    /// One revision bump. A sync change names the sources whose mapping changed and a keeper change the keepers that
    /// changed; an event change may name the recalculated points (core `ScoringEngine.diff`), for display only.
    public struct Change: Equatable, Sendable {
        public var kind: ChangeKind
        public var projectId: String
        public var revision: Int
        public var named: [String]

        public init(kind: ChangeKind, projectId: String, revision: Int, named: [String] = []) {
            self.kind = kind
            self.projectId = projectId
            self.revision = revision
            self.named = named
        }

        public static func event(_ projectId: String, revision: Int, changedPointIds: [String] = []) -> Change {
            Change(kind: .event, projectId: projectId, revision: revision, named: changedPointIds)
        }

        public static func sync(_ projectId: String, revision: Int, sourceIds: [String]) -> Change {
            Change(kind: .sync, projectId: projectId, revision: revision, named: sourceIds)
        }

        public static func keepers(_ projectId: String, revision: Int, keeperIds: [String]) -> Change {
            Change(kind: .keepers, projectId: projectId, revision: revision, named: keeperIds)
        }
    }

    public enum Status: String, Sendable {
        case current, stale
    }

    public struct PlanStatus: Equatable, Sendable {
        public var planId: String
        public var projectId: String
        public var status: Status
        public var reasons: [Reason]
        /// The plan's bindings after the changes: carried forward when nothing it uses changed.
        public var bindings: Revisions
    }

    public struct FilmStatus: Equatable, Sendable {
        public var artifactId: String
        public var projectId: String
        public var planId: String
        public var status: Status
        /// "Made before a correction" when stale.
        public var label: String?
        public var reasons: [Reason]
        /// Always true: a stale film stays as a labelled version.
        public var keptAsVersion: Bool
    }

    public struct Result: Equatable, Sendable {
        public var current: [String: Revisions]
        public var plans: [PlanStatus]
        public var films: [FilmStatus]
        public var stalePlanIds: [String]
        public var staleFilmIds: [String]
    }

    // MARK: Dependencies

    /// What a stored edit plan (`jovra.edit-plan/2`, as parsed JSON) depends on, keyed by its canonical SHA-256.
    public static func planDependencies(_ plan: StudioJSONValue) throws -> PlanDependencies {
        func string(_ v: StudioJSONValue?, _ what: String) throws -> String {
            guard case .string(let s)? = v else { throw Rejection(.badInput, "plan \(what)") }
            return s
        }
        func int(_ v: StudioJSONValue?, _ what: String) throws -> Int {
            guard case .number(let n)? = v, let i = n.int64 else { throw Rejection(.badInput, "plan \(what)") }
            return Int(i)
        }
        func array(_ v: StudioJSONValue?) -> [StudioJSONValue] { if case .array(let a)? = v { a } else { [] } }
        func id(_ v: StudioJSONValue?) -> String? { if case .string(let s)? = v, !s.isEmpty { s } else { nil } }
        let segments = array(plan["segments"]), bed = array(plan["audio"]?["bed"])
        let sources = Set(segments.compactMap { id($0["sourceId"]) } + bed.compactMap { id($0["sourceId"]) })
        let keepers = Set(segments.compactMap { id($0["keeperId"]) })
        let b = plan["bindings"]
        let canonical = try CanonicalJSON.canonicalize(plan.serialized())
        return PlanDependencies(
            planId: try string(plan["planId"], "planId"), planRevision: try int(plan["planRevision"], "planRevision"),
            projectId: try string(plan["projectId"], "projectId"), editPlanSha256: StudioSHA256.hex(canonical),
            bindings: Revisions(eventRevision: try int(b?["eventRevision"], "eventRevision"),
                                syncRevision: try int(b?["syncRevision"], "syncRevision"),
                                keeperCatalogRevision: try int(b?["keeperCatalogRevision"], "keeperCatalogRevision")),
            sourceIds: sources.sorted(by: codePointPrecedes), keeperIds: keepers.sorted(by: codePointPrecedes))
    }

    /// The same for a plan record's bytes.
    public static func planDependencies(record bytes: Data) throws -> PlanDependencies {
        try planDependencies(StudioJSONParser.parse(bytes))
    }

    /// What a delivered film depends on.
    public static func filmDependencies(_ film: DeliveredArtifact) -> FilmDependencies {
        FilmDependencies(artifactId: film.artifactId, projectId: film.projectId,
                         editPlanSha256: film.bindings.editPlanSha256, stale: film.stale.value != nil)
    }

    // MARK: Propagation

    /// Applies `changes` in order to `projects` (each project's current revisions) and returns every plan and film
    /// with its status. Refuses a revision that does not increase, a plan bound ahead of its project, a film whose plan
    /// is not listed, an unknown project and a sync or keeper change that names nothing.
    public static func propagate(projects: [String: Revisions], plans: [PlanDependencies], films: [FilmDependencies],
                                 changes: [Change]) throws -> Result {
        var current = projects
        for (pid, revisions) in projects.sorted(by: { codePointPrecedes($0.key, $1.key) }) {
            for kind in ChangeKind.allCases { try requireRevision(revisions[kind], "\(pid) \(kind.rawValue)") }
        }
        struct Working {
            let dep: PlanDependencies
            var bindings: Revisions
            var reasons: Set<Reason>
        }
        var working: [Working] = []
        var seen = Set<String>()
        for dep in plans {
            guard let project = current[dep.projectId] else {
                throw Rejection(.unknownProject, "plan \(dep.planId): project \(dep.projectId)")
            }
            guard seen.insert(dep.planId).inserted else { throw Rejection(.duplicateId, "plan \(dep.planId) listed twice") }
            var reasons = Set<Reason>()
            for kind in ChangeKind.allCases {
                let bound = dep.bindings[kind]
                try requireRevision(bound, "\(dep.planId) \(kind.rawValue)")
                guard bound <= project[kind] else {
                    throw Rejection(.futureRevision, "\(dep.planId) is bound to \(kind.rawValue) \(bound), ahead of the project (\(project[kind]))")
                }
                if bound < project[kind] { reasons.insert(kind.reason) }   // already behind before any change
            }
            working.append(Working(dep: dep, bindings: dep.bindings, reasons: reasons))
        }

        for change in changes {
            guard var project = current[change.projectId] else {
                throw Rejection(.unknownProject, "change for project \(change.projectId)")
            }
            let kind = change.kind
            try requireRevision(change.revision, "\(kind.rawValue) revision")
            guard change.revision > project[kind] else {
                throw Rejection(.revisionNotIncreasing, "\(kind.rawValue) \(change.revision) is not after the current \(project[kind])")
            }
            let named = Set(change.named)
            guard kind == .event || !named.isEmpty else { throw Rejection(.badChange, "a \(kind.rawValue) change names what changed") }
            for i in working.indices where working[i].dep.projectId == change.projectId {
                let uses = kind == .sync ? working[i].dep.sourceIds : working[i].dep.keeperIds
                if kind == .event || !named.isDisjoint(with: uses) {
                    working[i].reasons.insert(kind.reason)
                } else if working[i].bindings[kind] == project[kind] {
                    working[i].bindings[kind] = change.revision   // nothing it uses changed: carried forward
                }
            }
            project[kind] = change.revision
            current[change.projectId] = project
        }

        var byHash: [String: Working] = [:]
        for w in working { byHash[w.dep.editPlanSha256] = w }
        var filmStatuses: [FilmStatus] = []
        for film in films {
            guard let plan = byHash[film.editPlanSha256] else {
                throw Rejection(.unknownPlan, "film \(film.artifactId): no listed plan has its edit-plan hash")
            }
            guard plan.dep.projectId == film.projectId else {
                throw Rejection(.unknownPlan, "film \(film.artifactId): plan of another project")
            }
            let stale = film.stale || !plan.reasons.isEmpty
            filmStatuses.append(FilmStatus(artifactId: film.artifactId, projectId: film.projectId, planId: plan.dep.planId,
                                           status: stale ? .stale : .current, label: stale ? filmLabel : nil,
                                           reasons: plan.reasons.sorted(), keptAsVersion: true))
        }
        let planStatuses = working.map {
            PlanStatus(planId: $0.dep.planId, projectId: $0.dep.projectId, status: $0.reasons.isEmpty ? .current : .stale,
                       reasons: $0.reasons.sorted(), bindings: $0.bindings)
        }
        return Result(current: current, plans: planStatuses, films: filmStatuses,
                      stalePlanIds: planStatuses.filter { $0.status == .stale }.map(\.planId).sorted(by: codePointPrecedes),
                      staleFilmIds: filmStatuses.filter { $0.status == .stale }.map(\.artifactId).sorted(by: codePointPrecedes))
    }

    private static func requireRevision(_ value: Int, _ what: String) throws {
        guard value >= 1 else { throw Rejection(.badRevision, "\(what) must be a revision (an integer from 1)") }
    }
}
