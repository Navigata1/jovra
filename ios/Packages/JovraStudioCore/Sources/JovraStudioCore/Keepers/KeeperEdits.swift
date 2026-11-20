import Foundation
import JovraCore

/// A short real clip the player marked as B-roll (story 105): arrival, racket, bag, handshake. Whether it is from this
/// match is the player's own statement (story 106); a clip that is not never stands in for match footage.
public struct KeeperBroll: Equatable, Sendable {
    public var brollId: String
    public var sourceId: String
    /// Render-proxy frames of the B-roll source.
    public var window: StudioFrameWindow
    public var depictsThisMatch: Bool
    /// The participants seen in the clip.
    public var peopleVisible: [String]
    /// True when the clip shows where the match was played.
    public var locationVisible: Bool
    /// The chapter the player marked it for: `arrival`, `preparation` or `after`.
    public var chapter: String
    public var origin: BrollCatalogItemOrigin
    public var description: String?

    public init(brollId: String, sourceId: String, window: StudioFrameWindow, depictsThisMatch: Bool,
                peopleVisible: [String] = [], locationVisible: Bool = false, chapter: String,
                origin: BrollCatalogItemOrigin = .capturedToday, description: String? = nil) {
        self.brollId = brollId
        self.sourceId = sourceId
        self.window = window
        self.depictsThisMatch = depictsThisMatch
        self.peopleVisible = peopleVisible
        self.locationVisible = locationVisible
        self.chapter = chapter
        self.origin = origin
        self.description = description
    }
}

/// The player's edits of a keeper catalog (spec KeeperSelector: `select`, `exclude`, `annotate(note)`,
/// `markBroll(window, depictsThisMatch, peopleVisible, locationVisible)`). Each keeper edit returns the keeper ids it
/// changed, which is what a keeper-revision change names (`StudioStaleness.Change.keepers`), so only the plans that use
/// one of them go stale.
///
/// Exclusion (story 108) removes a keeper, a person or a location from every later plan: `planInput` and `catalog`
/// never offer an excluded keeper, nor a B-roll clip showing an excluded person, nor (once the location is excluded) a
/// clip that shows where the match was played.
public struct KeeperEdits: Equatable, Sendable {
    public private(set) var selected: Set<String> = []
    public private(set) var excludedKeepers: Set<String> = []
    public private(set) var excludedPeople: Set<String> = []
    public private(set) var locationExcluded = false
    public private(set) var notes: [String: String] = [:]
    public private(set) var brolls: [KeeperBroll] = []

    public init() {}

    /// The player keeps this keeper (its catalog selection becomes `manual`); a selected keeper is no longer excluded.
    @discardableResult
    public mutating func select(_ keeperId: String) -> [String] {
        let changed = !selected.contains(keeperId) || excludedKeepers.contains(keeperId)
        selected.insert(keeperId)
        excludedKeepers.remove(keeperId)
        return changed ? [keeperId] : []
    }

    /// The keeper is never offered by any profile or written to a later catalog.
    @discardableResult
    public mutating func exclude(keeper keeperId: String) -> [String] {
        let changed = !excludedKeepers.contains(keeperId)
        excludedKeepers.insert(keeperId)
        selected.remove(keeperId)
        return changed ? [keeperId] : []
    }

    /// No later plan shows this participant: B-roll that shows them is withheld.
    public mutating func exclude(person participantId: String) {
        excludedPeople.insert(participantId)
    }

    /// No later plan shows where the match was played: B-roll that reveals the location is withheld.
    public mutating func excludeLocation() {
        locationExcluded = true
    }

    /// The player's note on a keeper (story 103); an empty or nil note removes it. Annotating also selects it.
    @discardableResult
    public mutating func annotate(_ keeperId: String, note: String?) -> [String] {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = notes[keeperId]
        notes[keeperId] = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let selectedNow = select(keeperId)
        return before != notes[keeperId] || !selectedNow.isEmpty ? [keeperId] : []
    }

    /// Marks a real clip as B-roll. Refuses an empty window, a repeated id, stock or generated material (not the
    /// player's real day), and another day's footage claimed as this match.
    public mutating func markBroll(_ broll: KeeperBroll) throws {
        guard !broll.brollId.isEmpty, !broll.sourceId.isEmpty else { throw KeeperRejection(.badInput, "a B-roll clip needs ids") }
        guard broll.window.inFrame >= 0, broll.window.inFrame < broll.window.outFrame else {
            throw KeeperRejection(.badInterval, "B-roll \(broll.brollId) window")
        }
        guard !brolls.contains(where: { $0.brollId == broll.brollId }) else {
            throw KeeperRejection(.duplicateId, "B-roll \(broll.brollId) is already marked")
        }
        guard broll.origin != .stock, broll.origin != .generated else {
            throw KeeperRejection(.brollMisrepresented, "B-roll is the player's own real footage, never stock or generated")
        }
        if broll.origin == .capturedOtherDay, broll.depictsThisMatch {
            throw KeeperRejection(.brollMisrepresented, "only today's footage depicts this match")
        }
        brolls.append(broll)
    }

    /// Whether a later plan may use this B-roll clip at all (exclusions of people and location).
    public func allows(_ broll: KeeperBroll) -> Bool {
        !(locationExcluded && broll.locationVisible) && excludedPeople.isDisjoint(with: broll.peopleVisible)
    }
}

/// What a later plan is offered (the planning context's `keepers` and `brolls`, spec/studio/modules/planner.md).
public struct KeeperPlanInput: Equatable, Sendable {
    /// Match footage: keepers only, never B-roll, never an excluded keeper.
    public var keepers: [Keeper]
    /// B-roll a plan may use, each with whether it depicts this match. A clip that does not is labelled
    /// "label.not-match-footage" wherever it is shown and is never in a match chapter.
    public var brolls: [KeeperBroll]
    /// Keeper id -> the player's note.
    public var notes: [String: String]

    /// Ids of everything offered as match footage.
    public var matchFootageIds: [String] { keepers.map(\.keeperId) }

    /// The Court Memories chapter B-roll: only clips from this match, so the film never passes other footage off as
    /// the player's real day (story 106).
    public var courtMemoriesBrolls: [KeeperRankOptions.Broll] {
        brolls.filter(\.depictsThisMatch).map { .init(brollId: $0.brollId, chapter: $0.chapter) }
    }
}

extension KeeperSelector {
    /// The keepers and B-roll a later plan is offered after the player's edits.
    public static func planInput(_ candidates: KeeperCandidates, edits: KeeperEdits) -> KeeperPlanInput {
        KeeperPlanInput(keepers: candidates.keepers.filter { !edits.excludedKeepers.contains($0.keeperId) },
                        brolls: edits.brolls.filter(edits.allows), notes: edits.notes)
    }

    /// A profile's ranking over the plan input: excluded keepers are never offered, and Court Memories' chapters only
    /// take B-roll from this match.
    public static func rank(_ profile: KeeperProfile, _ input: KeeperPlanInput,
                            options: KeeperRankOptions = KeeperRankOptions()) throws -> KeeperRanking {
        var options = options
        if profile == .courtMemories {
            let offered = Set(input.courtMemoriesBrolls.map(\.brollId))
            options.brolls = options.brolls.isEmpty ? input.courtMemoriesBrolls : options.brolls.filter { offered.contains($0.brollId) }
        }
        return try rank(profile, input.keepers, options: options)
    }

    /// `candidates(project, eventVersion) -> KeeperCatalog`: the stored `jovra.keeper-catalog/1` record of a project at
    /// one event revision. Excluded keepers are left out, and so is a keeper no angle can show (a catalog keeper needs a
    /// view); each contact lists its frame on every view. Selection is `manual` for a keeper the player selected or
    /// annotated, else `heuristic`.
    public static func catalog(_ project: KeeperProject, eventVersion: Int, projectId: String, revision: Int, sample: Bool,
                               syncRevision: Int?, edits: KeeperEdits = KeeperEdits()) throws -> KeeperCatalog {
        catalog(try candidates(project), eventVersion: eventVersion, projectId: projectId, revision: revision, sample: sample,
                syncRevision: syncRevision, edits: edits)
    }

    public static func catalog(_ candidates: KeeperCandidates, eventVersion: Int, projectId: String, revision: Int,
                               sample: Bool, syncRevision: Int?, edits: KeeperEdits = KeeperEdits()) -> KeeperCatalog {
        let keepers = candidates.keepers.filter { !edits.excludedKeepers.contains($0.keeperId) && !$0.views.isEmpty }.map { k in
            KeeperCatalogKeeper(
                keeperId: k.keeperId, eventRefs: k.eventRefs, session: k.session,
                views: k.views.map { KeeperCatalogKeeperView(sourceId: $0.sourceId, window: $0.window, primary: $0.primary) },
                contacts: k.contacts.flatMap { c in c.frames.map { KeeperCatalogKeeperContact(sourceId: $0.sourceId, frame: $0.frame) } },
                selection: edits.selected.contains(k.keeperId) ? .manual : .heuristic, provenance: k.facts.provenance)
        }
        return KeeperCatalog(projectId: projectId, revision: revision, sample: sample, eventRevision: eventVersion,
                             syncRevision: ContractNullable(syncRevision), keepers: keepers)
    }

    /// The `jovra.broll-catalog/1` record of the marked B-roll. A clip that does not depict this match carries the
    /// "label.not-match-footage" disclosure.
    public static func brollCatalog(_ edits: KeeperEdits, projectId: String, revision: Int, sample: Bool) -> BrollCatalog {
        BrollCatalog(projectId: projectId, revision: revision, sample: sample, items: edits.brolls.map { b in
            BrollCatalogItem(brollId: b.brollId, sourceId: b.sourceId, window: b.window, depictsThisMatch: b.depictsThisMatch,
                             origin: b.origin, rights: BrollCatalogItemRights(holder: .user, scope: [.privateFilm], rightsRecordId: .null),
                             disclosureTemplateId: b.depictsThisMatch ? .null : .value(.value),
                             revealsLocation: b.locationVisible, participantIds: b.peopleVisible,
                             description: ContractNullable(b.description))
        })
    }
}
