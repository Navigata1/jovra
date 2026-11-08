import Foundation

/// The trusted context an edit plan is checked against (`bundle.edl_context` in the reference), built only from stored
/// records, never from the plan: the current revisions, the sources offered for cutting with the exact snapshot and
/// coverage a plan must copy, keeper and B-roll ids, every stored keeper contact by source, and the ReferenceCatalog's
/// overlay targets, notes, consents and rights. `EDLValidator` refuses to run without it (`contextMissing`), so a
/// renderer can never accept a plan's self-declared coverage, provenance, consent or rights.
public struct EDLTrustedContext: Equatable, Sendable {
    /// A source offered for cutting. `proxy` and `coverage` are kept as the JSON a plan must copy exactly.
    public struct Source: Equatable, Sendable {
        public var sha256: String
        public var role: String
        public var hasAudio: Bool
        public var proxy: StudioJSONValue
        public var coverage: StudioJSONValue

        public init(sha256: String, role: String, hasAudio: Bool, proxy: StudioJSONValue, coverage: StudioJSONValue) {
            self.sha256 = sha256
            self.role = role
            self.hasAudio = hasAudio
            self.proxy = proxy
            self.coverage = coverage
        }
    }

    /// A session window `[startUs, endUs]` of a keeper that carries a point.
    public struct SessionWindow: Equatable, Hashable, Sendable {
        public var startUs: Int
        public var endUs: Int

        public init(startUs: Int, endUs: Int) {
            self.startUs = startUs
            self.endUs = endUs
        }
    }

    /// A ReferenceCatalog entry: its stored kind and provenance, the event revision it was resolved at and, for a point
    /// event only, the session windows of the keepers that carry that point (nil for a score state, stat or note).
    public struct Reference: Equatable, Sendable {
        public var kind: String
        public var provenance: String
        public var eventRevision: Int
        public var pointWindows: [SessionWindow]?

        public init(kind: String, provenance: String, eventRevision: Int, pointWindows: [SessionWindow]?) {
            self.kind = kind
            self.provenance = provenance
            self.eventRevision = eventRevision
            self.pointWindows = pointWindows
        }
    }

    public struct Consent: Equatable, Sendable {
        public var participantId: String
        public var scope: [String]
        public var granted: Bool

        public init(participantId: String, scope: [String], granted: Bool) {
            self.participantId = participantId
            self.scope = scope
            self.granted = granted
        }
    }

    public struct Rights: Equatable, Sendable {
        public var assetId: String
        public var scope: [String]

        public init(assetId: String, scope: [String]) {
            self.assetId = assetId
            self.scope = scope
        }
    }

    /// The binding names a plan must carry at their current revision (`bindings.<key>`), in the reference's order.
    public static let currentKeys = ["sourceManifestRevision", "syncRevision", "eventRevision", "keeperCatalogRevision",
                                     "brollCatalogRevision"]

    public var projectId: String
    public var current: [String: Int]
    public var sources: [String: Source]
    public var keepers: [String]
    public var contacts: [String: [Int]]
    public var brolls: [String]
    public var references: [String: Reference]
    public var consents: [String: Consent]
    public var rights: [String: Rights]

    public init(projectId: String, current: [String: Int], sources: [String: Source], keepers: [String],
                contacts: [String: [Int]], brolls: [String], references: [String: Reference],
                consents: [String: Consent], rights: [String: Rights]) {
        self.projectId = projectId
        self.current = current
        self.sources = sources
        self.keepers = keepers
        self.contacts = contacts
        self.brolls = brolls
        self.references = references
        self.consents = consents
        self.rights = rights
    }
}

// ----- building from stored records (bundle.edl_context) ---------------------------------------------------------

extension EDLTrustedContext {
    private static let usableSyncStates: Set<SyncMapPieceState> = [.reference, .reviewed]

    /// The context for one project, from its stored records (`bundle.edl_context`). A match source is offered only
    /// when it is verified, has exactly one render proxy, exactly one recorded segment and exactly one sync piece for
    /// that segment in a reference or reviewed state; its coverage is that piece's transform over the whole proxy. A
    /// B-roll source is offered with off-clock coverage. Anything else is absent, so a plan naming it is
    /// `untrustedSource`.
    public static func build(manifest: SourceManifest, syncMap: SyncMap, keepers: KeeperCatalog, brolls: BrollCatalog,
                             references: ReferenceCatalog) -> EDLTrustedContext {
        var contacts: [String: Set<Int>] = [:]
        for keeper in keepers.keepers {
            for contact in keeper.contacts { contacts[contact.sourceId, default: []].insert(contact.frame) }
        }
        var catalog: [String: Reference] = [:]
        for ref in references.references {
            catalog[ref.refId] = Reference(kind: ref.kind.rawValue, provenance: ref.provenance.rawValue,
                                           eventRevision: ref.eventRevision, pointWindows: pointWindows(ref, keepers))
        }
        return EDLTrustedContext(
            projectId: manifest.projectId,
            current: ["sourceManifestRevision": manifest.revision, "syncRevision": syncMap.revision,
                      "eventRevision": keepers.eventRevision, "keeperCatalogRevision": keepers.revision,
                      "brollCatalogRevision": brolls.revision],
            sources: trustedSources(manifest: manifest, syncMap: syncMap),
            keepers: keepers.keepers.map(\.keeperId),
            contacts: contacts.mapValues { $0.sorted() },
            brolls: brolls.items.map(\.brollId),
            references: catalog,
            consents: Dictionary(references.consents.map {
                ($0.consentRecordId, Consent(participantId: $0.participantId, scope: $0.scope.map(\.rawValue), granted: $0.granted))
            }, uniquingKeysWith: { first, _ in first }),
            rights: Dictionary(references.rights.map {
                ($0.rightsRecordId, Rights(assetId: $0.assetId, scope: $0.scope.map(\.rawValue)))
            }, uniquingKeysWith: { first, _ in first }))
    }

    static func trustedSources(manifest: SourceManifest, syncMap: SyncMap) -> [String: Source] {
        let pieces = Dictionary(syncMap.sources.map { ($0.sourceId, $0.pieces) }, uniquingKeysWith: { first, _ in first })
        var out: [String: Source] = [:]
        for src in manifest.sources {
            let renders = src.proxies.filter { $0.class == .render }
            guard renders.count == 1, src.verification.status == .verified else { continue }
            let proxy = renders[0]
            let coverage: StudioJSONValue
            switch src.role {
            case .broll:
                coverage = .array([.members([("inFrame", .int(0)), ("outFrame", .int(proxy.frameCount)),
                                             ("sessionStartUs", .null), ("rate", .null)])])
            case .match:
                guard let mapped = pieces[src.sourceId], mapped.count == 1, src.segments.count == 1,
                      mapped[0].segmentId == src.segments[0].segmentId,
                      mapped[0].sourceDurationUs == src.segments[0].durationUs,
                      usableSyncStates.contains(mapped[0].state), let t = mapped[0].transform.value
                else { continue }
                coverage = .array([.members([("inFrame", .int(0)), ("outFrame", .int(proxy.frameCount)),
                                             ("sessionStartUs", .int(t.offsetUs)),
                                             ("rate", .members([("num", .int(t.rate.num)), ("den", .int(t.rate.den))]))])])
            }
            out[src.sourceId] = Source(
                sha256: src.original.sha256, role: src.role.rawValue, hasAudio: src.original.audio.value != nil,
                proxy: .members([("fps", .members([("num", .int(proxy.fps.num)), ("den", .int(proxy.fps.den))])),
                                 ("width", .int(proxy.width)), ("height", .int(proxy.height)),
                                 ("frameCount", .int(proxy.frameCount)), ("ptsTableSha256", .string(proxy.ptsTableSha256))]),
                coverage: coverage)
        }
        return out
    }

    /// Where a point-event overlay may be shown over play: the session windows of every keeper whose eventRefs carry
    /// that point, sorted. Nil for any other origin, which is not bound to one rally. Empty when no keeper carries it.
    static func pointWindows(_ ref: ReferenceCatalogReference, _ keepers: KeeperCatalog) -> [SessionWindow]? {
        guard ref.origin.recordKind == .pointEvent else { return nil }
        return keepers.keepers.filter { $0.eventRefs.contains(ref.origin.recordId) }
            .map { SessionWindow(startUs: $0.session.startUs, endUs: $0.session.endUs) }
            .sorted { ($0.startUs, $0.endUs) < ($1.startUs, $1.endUs) }
    }
}

// ----- the JSON form (the reference's dict), for patched vectors and tooling --------------------------------------

extension EDLTrustedContext {
    /// The reference's keys; a context missing any of them is refused whole.
    public static let jsonKeys = ["projectId", "current", "sources", "keepers", "contacts", "brolls", "references",
                                  "consents", "rights"]

    /// The context as the reference's dictionary (keys of maps sorted).
    public var json: StudioJSONValue {
        func strings(_ items: [String]) -> StudioJSONValue { .array(items.map(StudioJSONValue.string)) }
        return .members([
            ("projectId", .string(projectId)),
            ("current", .members(current.sorted { $0.key < $1.key }.map { ($0.key, .int($0.value)) })),
            ("sources", .members(sources.sorted { $0.key < $1.key }.map { id, s in
                (id, .members([("sha256", .string(s.sha256)), ("role", .string(s.role)), ("hasAudio", .bool(s.hasAudio)),
                               ("proxy", s.proxy), ("coverage", s.coverage)]))
            })),
            ("keepers", strings(keepers)),
            ("contacts", .members(contacts.sorted { $0.key < $1.key }.map { ($0.key, .array($0.value.map(StudioJSONValue.int))) })),
            ("brolls", strings(brolls)),
            ("references", .members(references.sorted { $0.key < $1.key }.map { id, r in
                (id, .members([("kind", .string(r.kind)), ("provenance", .string(r.provenance)),
                               ("eventRevision", .int(r.eventRevision)),
                               ("pointWindows", r.pointWindows.map { windows in
                                   .array(windows.map { .array([.int($0.startUs), .int($0.endUs)]) })
                               } ?? .null)]))
            })),
            ("consents", .members(consents.sorted { $0.key < $1.key }.map { id, c in
                (id, .members([("participantId", .string(c.participantId)), ("scope", strings(c.scope)),
                               ("granted", .bool(c.granted))]))
            })),
            ("rights", .members(rights.sorted { $0.key < $1.key }.map { id, r in
                (id, .members([("assetId", .string(r.assetId)), ("scope", strings(r.scope))]))
            })),
        ])
    }

    /// A context from its JSON form. Every key the reference requires must be present and well formed (including each
    /// reference's `pointWindows`), or the whole context is refused with `contextMissing`: a partial context never
    /// reaches the plan.
    public init(json: StudioJSONValue) throws {
        func missing(_ what: String) -> EDLFinding {
            EDLFinding(.contextMissing, "the trusted context has no valid \(what); a plan is never checked against itself")
        }
        func members(_ value: StudioJSONValue?, _ what: String) throws -> [StudioJSONMember] {
            guard let value, let m = EDLJSON.object(value) else { throw missing(what) }
            return m
        }
        func text(_ value: StudioJSONValue?, _ what: String) throws -> String {
            guard let value, let s = EDLJSON.string(value) else { throw missing(what) }
            return s
        }
        func int(_ value: StudioJSONValue?, _ what: String) throws -> Int {
            guard let value, let n = EDLJSON.exactInt(value) else { throw missing(what) }
            return n
        }
        func flag(_ value: StudioJSONValue?, _ what: String) throws -> Bool {
            guard let value, let b = EDLJSON.boolean(value) else { throw missing(what) }
            return b
        }
        func list(_ value: StudioJSONValue?, _ what: String) throws -> [StudioJSONValue] {
            guard let value, let items = EDLJSON.array(value) else { throw missing(what) }
            return items
        }
        func strings(_ value: StudioJSONValue?, _ what: String) throws -> [String] {
            try list(value, what).map { try text($0, what) }
        }

        guard EDLJSON.object(json) != nil else { throw missing("object") }
        for key in Self.jsonKeys where json[key] == nil { throw missing(key) }

        var current: [String: Int] = [:]
        for m in try members(json["current"], "current") { current[m.key] = try int(m.value, "current.\(m.key)") }
        var sources: [String: Source] = [:]
        for m in try members(json["sources"], "sources") {
            let s = m.value
            guard let proxy = s["proxy"], let coverage = s["coverage"] else { throw missing("sources.\(m.key)") }
            sources[m.key] = Source(sha256: try text(s["sha256"], "sources.\(m.key).sha256"),
                                    role: try text(s["role"], "sources.\(m.key).role"),
                                    hasAudio: try flag(s["hasAudio"], "sources.\(m.key).hasAudio"),
                                    proxy: proxy, coverage: coverage)
        }
        var contacts: [String: [Int]] = [:]
        for m in try members(json["contacts"], "contacts") {
            contacts[m.key] = try list(m.value, "contacts.\(m.key)").map { try int($0, "contacts.\(m.key)") }
        }
        var references: [String: Reference] = [:]
        for m in try members(json["references"], "references") {
            let r = m.value
            guard let rawWindows = r["pointWindows"] else { throw missing("references.\(m.key).pointWindows") }
            var windows: [SessionWindow]?
            if rawWindows != .null {
                windows = try list(rawWindows, "references.\(m.key).pointWindows").map { pair in
                    let bounds = try list(pair, "references.\(m.key).pointWindows")
                    guard bounds.count == 2 else { throw missing("references.\(m.key).pointWindows") }
                    return SessionWindow(startUs: try int(bounds[0], "pointWindows"), endUs: try int(bounds[1], "pointWindows"))
                }
            }
            references[m.key] = Reference(kind: try text(r["kind"], "references.\(m.key).kind"),
                                          provenance: try text(r["provenance"], "references.\(m.key).provenance"),
                                          eventRevision: try int(r["eventRevision"], "references.\(m.key).eventRevision"),
                                          pointWindows: windows)
        }
        var consents: [String: Consent] = [:]
        for m in try members(json["consents"], "consents") {
            consents[m.key] = Consent(participantId: try text(m.value["participantId"], "consents.\(m.key)"),
                                      scope: try strings(m.value["scope"], "consents.\(m.key).scope"),
                                      granted: try flag(m.value["granted"], "consents.\(m.key).granted"))
        }
        var rights: [String: Rights] = [:]
        for m in try members(json["rights"], "rights") {
            rights[m.key] = Rights(assetId: try text(m.value["assetId"], "rights.\(m.key)"),
                                   scope: try strings(m.value["scope"], "rights.\(m.key).scope"))
        }
        self.init(projectId: try text(json["projectId"], "projectId"), current: current, sources: sources,
                  keepers: try strings(json["keepers"], "keepers"), contacts: contacts,
                  brolls: try strings(json["brolls"], "brolls"), references: references, consents: consents,
                  rights: rights)
    }
}
