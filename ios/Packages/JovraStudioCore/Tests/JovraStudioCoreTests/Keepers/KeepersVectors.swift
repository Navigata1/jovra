import Foundation
import JovraCore
import JovraStudioCore

/// The `keepers` and `staleness` vectors in Swift (S35): each case's input is turned into the Swift types, run through
/// KeeperSelector or StudioStaleness, written back in the reference's JSON shape and compared canonically with the
/// stored `expect` (spec/reference/studio/keepers.py, staleness.py). The hand-derived `assert` block of each case is
/// then checked on its own, so a case passes only when Swift agrees with both the reference and the hand values.
enum KeepersVectors {
    struct Mismatch: Error, CustomStringConvertible { let description: String }

    // MARK: JSON reading

    static func string(_ v: StudioJSONValue?, _ what: String) throws -> String {
        guard case .string(let s)? = v else { throw Mismatch(description: "\(what) is not a string") }
        return s
    }

    static func optionalString(_ v: StudioJSONValue?) -> String? { if case .string(let s)? = v { s } else { nil } }

    static func int(_ v: StudioJSONValue?, _ what: String) throws -> Int {
        guard case .number(let n)? = v, let i = n.int64 else { throw KeeperRejection(.badInput, "\(what) must be an integer") }
        return Int(i)
    }

    static func optionalInt(_ v: StudioJSONValue?, _ what: String) throws -> Int? {
        if v == nil || v == .null { return nil }
        return try int(v, what)
    }

    static func bool(_ v: StudioJSONValue?) -> Bool { v == .bool(true) }

    static func array(_ v: StudioJSONValue?) -> [StudioJSONValue] { if case .array(let a)? = v { a } else { [] } }

    static func members(_ v: StudioJSONValue?) -> [StudioJSONMember] { if case .object(let m)? = v { m } else { [] } }

    static func provenance(_ v: StudioJSONValue?) throws -> Provenance {
        guard let p = Provenance(rawValue: try string(v, "provenance")) else { throw KeeperRejection(.badInput, "provenance") }
        return p
    }

    // MARK: JSON writing

    static func number(_ value: Int) -> StudioJSONValue { try! StudioJSONParser.parse(Data(String(value).utf8)) }
    static func number(_ value: Int?) -> StudioJSONValue { value.map { number($0) } ?? .null }
    static func text(_ value: String?) -> StudioJSONValue { value.map { .string($0) } ?? .null }
    static func strings(_ values: [String]) -> StudioJSONValue { .array(values.map { .string($0) }) }
    static func object(_ pairs: [(String, StudioJSONValue)]) -> StudioJSONValue {
        .object(pairs.map { StudioJSONMember(key: $0.0, value: $0.1) })
    }
    static func interval(_ i: StudioIntervalUs) -> StudioJSONValue {
        object([("startUs", number(i.startUs)), ("endUs", number(i.endUs))])
    }

    static func canonical(_ value: StudioJSONValue) -> Data {
        (try? CanonicalJSON.canonicalize(value.serialized())) ?? value.serialized()
    }

    static func show(_ value: StudioJSONValue) -> String { String(decoding: canonical(value), as: UTF8.self) }

    static func reject(_ code: String) -> StudioJSONValue { object([("rejectCode", .string(code))]) }
}

// MARK: - keepers

extension KeepersVectors {
    /// The core fold a `coreFold` input names: a core session file of the repository or an inline setup and log,
    /// folded by the Swift core (JovraCore.ScoringEngine), not by the reference.
    static func coreFoldPoints(_ fold: StudioJSONValue) throws -> [KeeperPoint] {
        let start = try int(fold["sessionStartUs"], "sessionStartUs")
        var input: [(String, StudioJSONValue)]
        if let path = optionalString(fold["session"]) {
            let session = try StudioJSONParser.parse(Data(contentsOf: StudioFixtures.repositoryRoot().appendingPathComponent(path)))
            guard let match = session["match"] else { throw Mismatch(description: "\(path) has no match") }
            input = [("format", match["format"]!), ("players", session["players"]!), ("sides", session["sides"]!),
                     ("toss", match["toss"]!), ("log", match["log"]!)]
        } else {
            let setup = fold["setup"]
            input = [("format", setup!["format"]!), ("players", setup!["players"]!), ("sides", setup!["sides"]!),
                     ("toss", setup!["toss"]!), ("log", fold["log"]!)]
        }
        let scoring = try ScoringInput.decode(object(input).serialized())
        return KeeperSelector.points(from: try ScoringEngine.fold(scoring), sessionStartUs: start)
    }

    static func project(_ p: StudioJSONValue) throws -> KeeperProject {
        let sources = try array(p["sources"]).map { s in
            let t = s["transform"]
            return KeeperSource(sourceId: try string(s["sourceId"], "sourceId"), isPrimary: bool(s["isPrimary"]),
                                syncState: try string(s["syncState"], "syncState"), offsetUs: try int(t?["offsetUs"], "offsetUs"),
                                rate: KeeperSyncRate(num: try int(t?["rate"]?["num"], "rate"), den: try int(t?["rate"]?["den"], "rate")),
                                fps: StudioFrameRate(num: try int(s["fps"]?["num"], "fps"), den: try int(s["fps"]?["den"], "fps")),
                                frameCount: try int(s["frameCount"], "frameCount"))
        }
        var points = try array(p["points"]).map { x in
            KeeperPoint(eventId: try string(x["eventId"], "eventId"), index: try int(x["index"], "index"),
                        startUs: try optionalInt(x["startUs"], "startUs"), endUs: try optionalInt(x["endUs"], "endUs"),
                        rallyLength: try optionalInt(x["rallyLength"], "rallyLength"), provenance: try provenance(x["provenance"]),
                        breakPoint: bool(x["breakPoint"]), setPoint: bool(x["setPoint"]), matchPoint: bool(x["matchPoint"]),
                        sourceId: optionalString(x["sourceId"]))
        }
        if let fold = p["coreFold"], fold != .null { points = try coreFoldPoints(fold) + points }
        return KeeperProject(
            sessionDurationUs: try int(p["sessionDurationUs"], "sessionDurationUs"), sources: sources, points: points,
            shots: try array(p["shots"]).map {
                KeeperShot(eventId: try string($0["eventId"], "eventId"), atUs: try int($0["atUs"], "atUs"), provenance: try provenance($0["provenance"]))
            },
            marks: try array(p["marks"]).map {
                KeeperMark(markId: try string($0["markId"], "markId"), atUs: try int($0["atUs"], "atUs"), note: optionalString($0["note"]))
            },
            lessonClips: try array(p["lessonClips"]).map { c in
                let w = c["window"]
                let window = (w == nil || w == .null) ? nil
                    : StudioIntervalUs(startUs: try int(w?["startUs"], "startUs"), endUs: try int(w?["endUs"], "endUs"))
                return KeeperLessonClip(clipId: try string(c["clipId"], "clipId"), lessonId: try string(c["lessonId"], "lessonId"),
                                        eventId: optionalString(c["eventId"]), window: window)
            })
    }

    static func options(_ o: StudioJSONValue?) throws -> KeeperRankOptions {
        var dates: [String: String] = [:]
        for m in members(o?["dates"]) { dates[m.key] = try string(m.value, "date") }
        let comparable = o?["comparable"].map { $0 == .bool(true) } ?? true
        return KeeperRankOptions(
            excluded: try array(o?["excluded"]).map { try string($0, "excluded") },
            limit: try optionalInt(o?["limit"], "limit"),
            cues: try array(o?["cues"]).map {
                .init(cueId: try string($0["cueId"], "cueId"), keeperId: try string($0["keeperId"], "keeperId"),
                      provenance: try provenance($0["provenance"]))
            },
            dates: dates, comparable: comparable, selectionRule: optionalString(o?["selectionRule"]),
            count: try optionalInt(o?["count"], "count"), seed: try optionalInt(o?["seed"], "seed"),
            chosen: try array(o?["chosen"]).map { try string($0, "chosen") },
            brolls: try array(o?["brolls"]).map { .init(brollId: try string($0["brollId"], "brollId"), chapter: try string($0["chapter"], "chapter")) })
    }

    static func json(_ k: Keeper) -> StudioJSONValue {
        object([
            ("keeperId", .string(k.keeperId)), ("origin", .string(k.origin.rawValue)), ("eventRefs", strings(k.eventRefs)),
            ("markIds", strings(k.markIds)), ("lessonClipIds", strings(k.lessonClipIds)), ("session", interval(k.session)),
            ("views", .array(k.views.map { v in
                object([("sourceId", .string(v.sourceId)),
                        ("window", object([("inFrame", number(v.window.inFrame)), ("outFrame", number(v.window.outFrame))])),
                        ("primary", .bool(v.primary))])
            })),
            ("contacts", .array(k.contacts.map { c in
                object([("atUs", number(c.atUs)), ("provenance", .string(c.provenance.rawValue)), ("label", text(c.label)),
                        ("protect", interval(c.protect)),
                        ("frames", object(c.frames.map { ($0.sourceId, number($0.frame)) }))])
            })),
            ("facts", object([("index", number(k.facts.index)), ("rallyLength", number(k.facts.rallyLength)),
                              ("rallyReal", .bool(k.facts.rallyReal)), ("breakPoint", .bool(k.facts.breakPoint)),
                              ("setPoint", .bool(k.facts.setPoint)), ("matchPoint", .bool(k.facts.matchPoint)),
                              ("provenance", .string(k.facts.provenance.rawValue))])),
            ("seenFrom", strings(k.seenFrom)),
        ])
    }

    static func json(_ c: KeeperCandidates) -> StudioJSONValue {
        object([("keepers", .array(c.keepers.map(json))),
                ("unplaced", .array(c.unplaced.map { object([("id", .string($0.id)), ("origin", .string($0.origin.rawValue)),
                                                              ("reason", .string($0.reason))]) }))])
    }

    static func json(_ r: KeeperRanking) -> StudioJSONValue {
        object([("profileId", .string(r.profile.rawValue)),
                ("order", .array(r.order.map { object([("kind", .string($0.kind.rawValue)), ("id", .string($0.id)), ("chapter", text($0.chapter))]) })),
                ("label", text(r.label)), ("fallback", text(r.fallback)), ("missing", strings(r.missing))])
    }

    /// Swift's result for one keepers case, as the reference writes it (`keepers.run_vector`).
    static func runKeepers(_ item: StudioJSONValue) throws -> (StudioJSONValue, KeeperCandidates?, KeeperRanking?) {
        do {
            let found = try KeeperSelector.candidates(project(item["input"]!["project"]!))
            if try string(item["op"], "op") == "candidates" { return (json(found), found, nil) }
            let ranked = try KeeperSelector.rank(profileId: try string(item["input"]?["profileId"], "profileId"), found.keepers,
                                                 options: options(item["input"]?["options"]))
            return (json(ranked), nil, ranked)
        } catch let rejection as KeeperRejection {
            return (reject(rejection.code.rawValue), nil, nil)
        }
    }

    /// One keepers case: Swift equals the stored expectation, and the hand assertions hold.
    @discardableResult
    static func checkKeepers(_ item: StudioJSONValue) throws -> String {
        let id = try string(item["id"], "id")
        let (got, found, ranked) = try runKeepers(item)
        guard let expect = item["expect"], canonical(got) == canonical(expect) else {
            throw Mismatch(description: "keepers \(id): Swift gives \(show(got).prefix(600)), reference stored \(show(item["expect"] ?? .null).prefix(600))")
        }
        let problems = try handProblems(item["assert"] ?? .object([]), found: found, ranked: ranked)
        guard problems.isEmpty else { throw Mismatch(description: "keepers \(id): \(problems)") }
        return id
    }

    /// `keepers_cases._keeper_problems`, over the Swift types.
    static func handProblems(_ a: StudioJSONValue, found: KeeperCandidates?, ranked: KeeperRanking?) throws -> [String] {
        var p: [String] = []
        if let ranked {
            let ids = ranked.order.map(\.id)
            if let order = a["order"], order != strings(ids) { p.append("order \(ids)") }
            if let label = a["label"], label != text(ranked.label) { p.append("label \(ranked.label ?? "nil")") }
            if let fallback = a["fallback"], fallback != text(ranked.fallback) { p.append("fallback") }
            if let missing = a["missing"], missing != strings(ranked.missing) { p.append("missing \(ranked.missing)") }
            if let size = a["orderSize"], try int(size, "orderSize") != ids.count { p.append("order has \(ids.count) items") }
            if let within = a["orderWithin"], !Set(ids).isSubset(of: try array(within).map { try string($0, "id") }) { p.append("orderWithin") }
            if let byDate = a["orderByDate"] {
                let days = try ids.map { try string(byDate[$0], "date") }
                if days != days.sorted() { p.append("examples are not in date order") }
            }
            if let first = a["first"], ids.first.map({ .string($0) }) != first || ids.last.map({ .string($0) }) != a["last"] {
                p.append("first or last item differs")
            }
            if let before = a["beforeNoPressure"] {
                let pressure = try foldPressureKeeperIds()
                let cut = ids.firstIndex { !pressure.contains($0) } ?? ids.count
                let head = Set(ids[..<cut])
                let late = try array(before).map { try string($0, "id") }.filter { !head.contains($0) }
                if !late.isEmpty { p.append("\(late.count) pressure points rank after a point without pressure") }
            }
            return p
        }
        guard let found else { return ["rejected"] }
        let ks = Dictionary(uniqueKeysWithValues: found.keepers.map { ($0.keeperId, $0) })
        if let count = a["keeperCount"], try int(count, "keeperCount") != ks.count { p.append("\(ks.count) keepers") }
        if let origins = a["origins"] {
            var counts: [String: Int] = [:]
            for k in found.keepers { counts[k.origin.rawValue, default: 0] += 1 }
            var want: [String: Int] = [:]
            for m in members(origins) { want[m.key] = try int(m.value, "origin count") }
            if counts != want { p.append("origins \(counts)") }
        }
        if a["eventRefsUnique"] == .bool(true) {
            let refs = found.keepers.flatMap(\.eventRefs)
            if refs.count != Set(refs).count { p.append("an event is in two keepers") }
        }
        for m in members(a["sessions"]) {
            let want = try array(m.value).map { try int($0, "session") }
            if let k = ks[m.key], [k.session.startUs, k.session.endUs] == want { continue }
            p.append("\(m.key) session \(ks[m.key].map { "\($0.session)" } ?? "missing"), hand value \(want)")
        }
        for m in members(a["viewSources"]) where ks[m.key].map({ strings($0.views.map(\.sourceId)) }) != m.value {
            p.append("\(m.key) views differ")
        }
        for m in members(a["primary"]) where ks[m.key].map({ strings($0.views.filter(\.primary).map(\.sourceId)) }) != .array([m.value]) {
            p.append("\(m.key) primary differs")
        }
        for m in members(a["seenFrom"]) where ks[m.key].map({ strings($0.seenFrom) }) != m.value { p.append("\(m.key) seen from differs") }
        for m in members(a["views"]) {
            for want in array(m.value) {
                let w = array(want)
                let have = ks[m.key]?.views.first { .string($0.sourceId) == w.first }
                let row: StudioJSONValue? = have.map { .array([.string($0.sourceId), number($0.window.inFrame), number($0.window.outFrame), .bool($0.primary)]) }
                if row != want { p.append("\(m.key) view \(row.map(show) ?? "missing"), hand value \(show(want))") }
            }
        }
        for m in members(a["contacts"]) {
            let have: StudioJSONValue = .array((ks[m.key]?.contacts ?? []).map {
                .array([number($0.atUs), .string($0.provenance.rawValue), text($0.label), number($0.protect.startUs), number($0.protect.endUs)])
            })
            if canonical(have) != canonical(m.value) { p.append("\(m.key) contacts \(show(have))") }
        }
        for m in members(a["markOn"]) {
            if let mark = optionalString(.string(m.key)), let kid = optionalString(m.value), ks[kid]?.markIds.contains(mark) == true { continue }
            p.append("mark \(m.key) is not on \(show(m.value))")
        }
        for m in members(a["lessonOn"]) {
            if let kid = optionalString(m.value), ks[kid]?.lessonClipIds.contains(m.key) == true { continue }
            p.append("lesson clip \(m.key) is not on \(show(m.value))")
        }
        for e in array(a["absentEventIds"]) {
            let eid = try string(e, "event")
            if found.keepers.contains(where: { $0.eventRefs.contains(eid) }) { p.append("\(eid) is a keeper") }
        }
        if let unplaced = a["unplaced"], unplaced != .array(found.unplaced.map { .array([.string($0.id), .string($0.reason)]) }) {
            p.append("unplaced \(found.unplaced)")
        }
        return p
    }

    /// Keeper ids of Jon vs Alex points the Swift core fold marks as break, set or match points (the oracle for the
    /// Rally Pulse ordering assertion, independent of the keeper facts).
    static func foldPressureKeeperIds() throws -> Set<String> {
        let url = StudioFixtures.repositoryRoot().appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
        let session = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url))
        let timeline = try ScoringEngine.fold(ScoringInput(session: session))
        return Set(timeline.points.compactMap { p in
            guard let pr = p.pressure.value, pr.breakPoint || !pr.setPointFor.isEmpty || !pr.matchPointFor.isEmpty else { return nil }
            return "k-" + p.id
        })
    }
}

// MARK: - staleness

extension KeepersVectors {
    static func revisions(_ v: StudioJSONValue?) throws -> StudioStaleness.Revisions {
        StudioStaleness.Revisions(eventRevision: try int(v?["eventRevision"], "eventRevision"),
                                  syncRevision: try int(v?["syncRevision"], "syncRevision"),
                                  keeperCatalogRevision: try int(v?["keeperCatalogRevision"], "keeperCatalogRevision"))
    }

    static func planDependencies(_ d: StudioJSONValue) throws -> StudioStaleness.PlanDependencies {
        StudioStaleness.PlanDependencies(
            planId: try string(d["planId"], "planId"), planRevision: try int(d["planRevision"], "planRevision"),
            projectId: try string(d["projectId"], "projectId"), editPlanSha256: try string(d["editPlanSha256"], "sha"),
            bindings: try revisions(d["bindings"]), sourceIds: try array(d["sourceIds"]).map { try string($0, "source") },
            keeperIds: try array(d["keeperIds"]).map { try string($0, "keeper") })
    }

    static func filmDependencies(_ f: StudioJSONValue) throws -> StudioStaleness.FilmDependencies {
        StudioStaleness.FilmDependencies(artifactId: try string(f["artifactId"], "artifactId"), projectId: try string(f["projectId"], "projectId"),
                                         editPlanSha256: try string(f["editPlanSha256"], "sha"), stale: bool(f["stale"]))
    }

    static func json(_ r: StudioStaleness.Revisions) -> StudioJSONValue {
        object([("eventRevision", number(r.eventRevision)), ("syncRevision", number(r.syncRevision)),
                ("keeperCatalogRevision", number(r.keeperCatalogRevision))])
    }

    static func reasons(_ r: [StudioStaleness.Reason]) -> StudioJSONValue { strings(r.map(\.rawValue)) }

    static func json(_ r: StudioStaleness.Result) -> StudioJSONValue {
        object([
            ("current", object(r.current.map { ($0.key, json($0.value)) })),
            ("plans", .array(r.plans.map {
                object([("planId", .string($0.planId)), ("projectId", .string($0.projectId)), ("status", .string($0.status.rawValue)),
                        ("reasons", reasons($0.reasons)), ("bindings", json($0.bindings))])
            })),
            ("films", .array(r.films.map {
                object([("artifactId", .string($0.artifactId)), ("projectId", .string($0.projectId)), ("planId", .string($0.planId)),
                        ("status", .string($0.status.rawValue)), ("label", text($0.label)), ("reasons", reasons($0.reasons)),
                        ("keptAsVersion", .bool($0.keptAsVersion))])
            })),
            ("stalePlanIds", strings(r.stalePlanIds)), ("staleFilmIds", strings(r.staleFilmIds)),
        ])
    }

    static func runStaleness(_ item: StudioJSONValue) throws -> (StudioJSONValue, StudioStaleness.Result?) {
        let state = item["input"]?["state"]
        var projects: [String: StudioStaleness.Revisions] = [:]
        for m in members(state?["projects"]) { projects[m.key] = try revisions(m.value) }
        let changes = try array(item["input"]?["changes"]).map { c -> StudioStaleness.Change in
            guard let kind = StudioStaleness.ChangeKind(rawValue: try string(c["kind"], "kind")) else {
                throw StudioStaleness.Rejection(.unknownChange, "change kind")
            }
            let key = kind == .sync ? "sourceIds" : kind == .keepers ? "keeperIds" : "changedPointIds"
            return StudioStaleness.Change(kind: kind, projectId: try string(c["projectId"], "projectId"),
                                          revision: try int(c["revision"], "revision"),
                                          named: try array(c[key]).map { try string($0, "named") })
        }
        do {
            let result = try StudioStaleness.propagate(projects: projects, plans: try array(state?["plans"]).map(planDependencies),
                                                       films: try array(state?["films"]).map(filmDependencies), changes: changes)
            return (json(result), result)
        } catch let rejection as StudioStaleness.Rejection {
            return (reject(rejection.code.rawValue), nil)
        }
    }

    /// One staleness case: a `fromRecord` input is re-derived from its record by Swift; the result equals the stored
    /// expectation; the hand assertions hold.
    @discardableResult
    static func checkStaleness(_ item: StudioJSONValue) throws -> String {
        let id = try string(item["id"], "id")
        let state = item["input"]?["state"]
        for dep in array(state?["plans"]) + array(state?["films"]) {
            guard let rel = optionalString(dep["fromRecord"]) else { continue }
            let data = try StudioFixtures.data(rel)
            let derived: StudioJSONValue
            if dep["planId"] != nil {
                let d = try StudioStaleness.planDependencies(record: data)
                derived = object([("planId", .string(d.planId)), ("planRevision", number(d.planRevision)), ("projectId", .string(d.projectId)),
                                  ("editPlanSha256", .string(d.editPlanSha256)), ("bindings", json(d.bindings)),
                                  ("sourceIds", strings(d.sourceIds)), ("keeperIds", strings(d.keeperIds)), ("fromRecord", .string(rel))])
            } else {
                let d = StudioStaleness.filmDependencies(try StudioContractCodec.decode(DeliveredArtifact.self, from: data))
                derived = object([("artifactId", .string(d.artifactId)), ("projectId", .string(d.projectId)),
                                  ("editPlanSha256", .string(d.editPlanSha256)), ("stale", .bool(d.stale)), ("fromRecord", .string(rel))])
            }
            guard canonical(derived) == canonical(dep) else {
                throw Mismatch(description: "staleness \(id): Swift derives \(show(derived)) from \(rel), the vector stores \(show(dep))")
            }
        }
        let (got, result) = try runStaleness(item)
        guard let expect = item["expect"], canonical(got) == canonical(expect) else {
            throw Mismatch(description: "staleness \(id): Swift gives \(show(got).prefix(800)), reference stored \(show(item["expect"] ?? .null).prefix(800))")
        }
        let problems = try stalenessHandProblems(item, result)
        guard problems.isEmpty else { throw Mismatch(description: "staleness \(id): \(problems)") }
        return id
    }

    /// `keepers_cases._staleness_problems`, over the Swift types.
    static func stalenessHandProblems(_ item: StudioJSONValue, _ result: StudioStaleness.Result?) throws -> [String] {
        let a = item["assert"] ?? .object([])
        if let code = a["rejectCode"] {
            return result == nil && item["expect"]?["rejectCode"] == code ? [] : ["expected \(show(code))"]
        }
        guard let r = result else { return ["rejected"] }
        var p: [String] = []
        let plans = Dictionary(uniqueKeysWithValues: r.plans.map { ($0.planId, $0) })
        let films = Dictionary(uniqueKeysWithValues: r.films.map { ($0.artifactId, $0) })
        if let v = a["stalePlanIds"], v != strings(r.stalePlanIds) { p.append("stalePlanIds \(r.stalePlanIds)") }
        if let v = a["staleFilmIds"], v != strings(r.staleFilmIds) { p.append("staleFilmIds \(r.staleFilmIds)") }
        if let v = a["current"], let c = r.current["sample-court-day"], canonical(v) != canonical(json(c)) { p.append("current \(c)") }
        if let v = a["currentPlanIds"], v != strings(plans.values.filter { $0.status == .current }.map(\.planId).sorted()) { p.append("current plans differ") }
        if let v = a["currentFilmIds"], v != strings(films.values.filter { $0.status == .current }.map(\.artifactId).sorted()) { p.append("current films differ") }
        for m in members(a["bindings"]) where plans[m.key].map({ canonical(json($0.bindings)) }) != canonical(m.value) { p.append("\(m.key) bindings") }
        for m in members(a["planReasons"]) where plans[m.key].map({ reasons($0.reasons) }) != m.value { p.append("\(m.key) reasons") }
        for m in members(a["filmReasons"]) where films[m.key].map({ reasons($0.reasons) }) != m.value { p.append("\(m.key) reasons") }
        for m in members(a["filmLabels"]) where films[m.key].map({ text($0.label) }) != m.value { p.append("\(m.key) label") }
        if !r.films.allSatisfy(\.keptAsVersion) || r.films.count != array(item["input"]?["state"]?["films"]).count { p.append("a film was dropped") }
        return p
    }
}
