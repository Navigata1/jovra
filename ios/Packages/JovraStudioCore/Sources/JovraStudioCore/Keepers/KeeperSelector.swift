import Foundation
import JovraCore

/// KeeperSelector (STU-10, spec "KeeperSelector"; reference spec/reference/studio/keepers.py): the keeper candidates of
/// a project and the deterministic per-profile ranking (`KeeperSelector+Ranking.swift`).
///
/// - One keeper per effective point of the core fold (story 102). Voided and superseded events are already resolved
///   by the fold, so a voided point is never a keeper.
/// - The same point scored from several angles is one keeper (story 107): merged by session event id, its window the
///   union, its facts from the strongest provenance, `seenFrom` listing every angle.
/// - Windows are the point plus the default pre-roll 1.5 s and post-roll 2.5 s (story 104), widened first to cover
///   every contact's protected window, then clamped to the session.
/// - Reviewed, validated and manual shots protect `[t - 0.25 s, t + 0.25 s)`; an estimated hit inside one of those is
///   absorbed, any other estimated hit is kept, labelled "Estimated", with the same protection (never less).
/// - A source offers a view only when its sync piece is `reference` or `reviewed` and its recording covers the whole
///   window. Frames use the one rule `floor(t * fps + 1/2)` in exact arithmetic.
public enum KeeperSelector {
    public static let preRollUs = 1_500_000
    public static let postRollUs = 2_500_000
    /// Each side of a contact (15 frames at 60 fps, as the Sample plans protect).
    public static let contactPadUs = 250_000
    public static let estimatedLabel = "Estimated"

    /// A rally length or contact a person entered or checked.
    static func isReal(_ provenance: Provenance) -> Bool { provenance != .estimated }

    static func strength(_ provenance: Provenance) -> Int {
        switch provenance {
        case .estimated: 0
        case .manual: 1
        case .reviewed: 2
        case .validated: 3
        }
    }

    // MARK: Core fold -> point inputs

    /// The effective points of a core fold as candidate inputs, on a session clock starting at `sessionStartUs`:
    /// every played point before the match ended (penalty points are not play), with the fold's rally length, outcome
    /// provenance and pressure flags. A point with no recorded time stays timeless and is reported as unplaced.
    public static func points(from timeline: MatchTimeline, sessionStartUs: Int = 0) -> [KeeperPoint] {
        timeline.points.compactMap { p in
            guard p.kind == .point, !p.afterMatchEnd else { return nil }
            let pressure = p.pressure.value
            let timed = p.tStartMs != nil && p.tEndMs != nil
            return KeeperPoint(eventId: p.id, index: p.index,
                               startUs: timed ? sessionStartUs + p.tStartMs! * 1000 : nil,
                               endUs: timed ? sessionStartUs + p.tEndMs! * 1000 : nil,
                               rallyLength: p.rallyLength.value, provenance: p.provenance,
                               breakPoint: pressure?.breakPoint ?? false,
                               setPoint: !(pressure?.setPointFor.isEmpty ?? true),
                               matchPoint: !(pressure?.matchPointFor.isEmpty ?? true))
        }
    }

    // MARK: Candidates

    public static func candidates(_ project: KeeperProject) throws -> KeeperCandidates {
        let duration = project.sessionDurationUs
        let sources = project.sources
        guard Set(sources.map(\.sourceId)).count == sources.count else {
            throw KeeperRejection(.duplicateId, "one entry per source")
        }
        var (points, unplaced) = try merge(project.points)
        var shotsByEvent: [String: [KeeperShot]] = [:]
        for shot in project.shots { shotsByEvent[shot.eventId, default: []].append(shot) }
        let known = Set(points.map(\.point.eventId))
        for eventId in Set(shotsByEvent.keys).subtracting(known).sorted(by: codePointPrecedes) {
            unplaced.append(KeeperUnplaced(id: eventId, origin: .shot, reason: "unknownEvent"))
        }

        var keepers: [Keeper] = []
        var keeperOfEvent: [String: Int] = [:]
        for merged in points {
            let p = merged.point
            let contacts = contacts(shotsByEvent[p.eventId] ?? [])
            var k = try keeper("k-" + p.eventId, .point, [p.eventId],
                               window(p.startUs!, p.endUs!, contacts, duration), sources, contacts, facts(of: p))
            k.seenFrom = merged.seenFrom
            keeperOfEvent[p.eventId] = keepers.count
            keepers.append(k)
        }
        // Marks: one inside a point's recorded time is that keeper (the same moment counted once).
        let byIndex = points.enumerated().sorted { a, b in
            a.element.point.index != b.element.point.index ? a.element.point.index < b.element.point.index : a.offset < b.offset
        }.map(\.element.point)
        for mark in project.marks {
            let at = mark.atUs
            if let home = byIndex.first(where: { $0.startUs! <= at && at < $0.endUs! }) {
                keepers[keeperOfEvent[home.eventId]!].markIds.append(mark.markId)
                continue
            }
            var k = try keeper("k-" + mark.markId, .mark, [mark.markId], window(at, at, [], duration), sources, [],
                               .noPoint)
            k.markIds.append(mark.markId)
            keepers.append(k)
        }
        for clip in project.lessonClips {
            if let eventId = clip.eventId, !eventId.isEmpty {
                guard let i = keeperOfEvent[eventId] else {
                    unplaced.append(KeeperUnplaced(id: clip.clipId, origin: .lessonClip, reason: "unknownEvent"))
                    continue
                }
                keepers[i].lessonClipIds.append(clip.clipId)
                continue
            }
            guard let w = clip.window else {
                unplaced.append(KeeperUnplaced(id: clip.clipId, origin: .lessonClip, reason: "noWindow"))
                continue
            }
            guard w.startUs < w.endUs else { throw KeeperRejection(.badInterval, "lesson clip \(clip.clipId)") }
            var k = try keeper("k-" + clip.clipId, .lessonClip, [clip.clipId], window(w.startUs, w.endUs, [], duration),
                               sources, [], .noPoint)
            k.lessonClipIds.append(clip.clipId)
            keepers.append(k)
        }
        let ordered = keepers.sorted { a, b in
            if a.session.startUs != b.session.startUs { return a.session.startUs < b.session.startUs }
            if a.origin != b.origin { return a.origin.order < b.origin.order }
            return codePointPrecedes(a.keeperId, b.keeperId)
        }
        return KeeperCandidates(keepers: ordered, unplaced: unplaced)
    }

    // MARK: Pieces

    struct MergedPoint {
        var point: KeeperPoint
        var seenFrom: [String]
    }

    /// Deduplicates by session event id: one entry per event, its window the union of every angle's, its facts from
    /// the strongest provenance (the first listed on a tie). Timeless points are unplaced.
    static func merge(_ points: [KeeperPoint]) throws -> ([MergedPoint], [KeeperUnplaced]) {
        var merged: [String: MergedPoint] = [:]
        var order: [String] = []
        var unplaced: [KeeperUnplaced] = []
        for p in points {
            guard !p.eventId.isEmpty else { throw KeeperRejection(.badInput, "a point needs an event id") }
            guard let start = p.startUs, let end = p.endUs else {
                unplaced.append(KeeperUnplaced(id: p.eventId, origin: .point, reason: "noTime"))
                continue
            }
            guard start < end else { throw KeeperRejection(.badInterval, "point \(p.eventId) ends before it starts") }
            guard var m = merged[p.eventId] else {
                merged[p.eventId] = MergedPoint(point: p, seenFrom: p.sourceId.flatMap { $0.isEmpty ? nil : [$0] } ?? [])
                order.append(p.eventId)
                continue
            }
            if strength(p.provenance) > strength(m.point.provenance) {
                var stronger = p
                stronger.startUs = m.point.startUs
                stronger.endUs = m.point.endUs
                m.point = stronger
            }
            m.point.startUs = min(m.point.startUs!, start)
            m.point.endUs = max(m.point.endUs!, end)
            if let source = p.sourceId, !source.isEmpty, !m.seenFrom.contains(source) { m.seenFrom.append(source) }
            merged[p.eventId] = m
        }
        return (order.map { merged[$0]! }, unplaced)
    }

    /// Real contacts protect `[t - pad, t + pad)`; an estimated hit inside one of those is absorbed; any other
    /// estimated hit is kept, labelled, with the same pad. Sorted by time, a real contact before an estimated one.
    static func contacts(_ shots: [KeeperShot]) -> [KeeperContact] {
        func protect(_ t: Int) -> StudioIntervalUs { StudioIntervalUs(startUs: t - contactPadUs, endUs: t + contactPadUs) }
        let real = stableSorted(shots.filter { isReal($0.provenance) }) { $0.atUs < $1.atUs }
        var out = real.map { KeeperContact(atUs: $0.atUs, provenance: $0.provenance, label: nil, protect: protect($0.atUs)) }
        for shot in stableSorted(shots.filter { !isReal($0.provenance) }, by: { $0.atUs < $1.atUs }) {
            let absorbed = out.contains { $0.label == nil && $0.protect.startUs <= shot.atUs && shot.atUs < $0.protect.endUs }
            if absorbed { continue }
            out.append(KeeperContact(atUs: shot.atUs, provenance: .estimated, label: estimatedLabel, protect: protect(shot.atUs)))
        }
        return stableSorted(out) { a, b in
            a.atUs != b.atUs ? a.atUs < b.atUs : (a.label == nil && b.label != nil)
        }
    }

    static func window(_ start: Int, _ end: Int, _ contacts: [KeeperContact], _ duration: Int) -> StudioIntervalUs {
        let lo = ([start] + contacts.map(\.protect.startUs)).min()!
        let hi = ([end] + contacts.map(\.protect.endUs)).max()!
        return StudioIntervalUs(startUs: max(0, lo - preRollUs), endUs: min(duration, hi + postRollUs))
    }

    static func facts(of p: KeeperPoint) -> KeeperFacts {
        KeeperFacts(index: p.index, rallyLength: p.rallyLength, rallyReal: p.rallyLength != nil && isReal(p.provenance),
                    breakPoint: p.breakPoint, setPoint: p.setPoint, matchPoint: p.matchPoint, provenance: p.provenance)
    }

    static func keeper(_ id: String, _ origin: KeeperOrigin, _ refs: [String], _ session: StudioIntervalUs,
                       _ sources: [KeeperSource], _ contacts: [KeeperContact], _ facts: KeeperFacts) throws -> Keeper {
        let views = try views(sources, session)
        let byId = Dictionary(uniqueKeysWithValues: sources.map { ($0.sourceId, $0) })
        let framed = try contacts.map { c in
            var c = c
            c.frames = try views.map { KeeperContactFrame(sourceId: $0.sourceId, frame: try frame(byId[$0.sourceId]!, c.atUs).frame) }
            return c
        }
        return Keeper(keeperId: id, origin: origin, eventRefs: refs, session: session, views: views, contacts: framed,
                      facts: facts)
    }

    static func views(_ sources: [KeeperSource], _ session: StudioIntervalUs) throws -> [KeeperView] {
        var views: [KeeperView] = []
        var primaries: [Bool] = []
        for src in sources where KeeperSource.usableSyncStates.contains(src.syncState) {
            if let v = try view(src, session) {
                views.append(v)
                primaries.append(src.isPrimary)
            }
        }
        if !views.isEmpty { views[primaries.firstIndex(of: true) ?? 0].primary = true }
        return views
    }

    /// The view of `[start, end)` on one source, or nil when its recording does not cover the whole window.
    static func view(_ src: KeeperSource, _ session: StudioIntervalUs) throws -> KeeperView? {
        let a = try frame(src, session.startUs), b = try frame(src, session.endUs)
        guard src.fps.num > 0, src.fps.den > 0 else { throw KeeperRejection(.badInput, "source \(src.sourceId) fps") }
        let length = EDLFraction(EDLInteger(src.frameCount) * EDLInteger(StudioTime.microsecondsPerSecond) * EDLInteger(src.fps.den),
                                 EDLInteger(src.fps.num))
        guard !(a.sourceUs < .zero), !(length < b.sourceUs), a.frame < b.frame else { return nil }
        return KeeperView(sourceId: src.sourceId, window: StudioFrameWindow(inFrame: a.frame, outFrame: b.frame), primary: false)
    }

    /// The exact source time and frame of a session time through the source's sync transform.
    static func frame(_ src: KeeperSource, _ sessionUs: Int) throws -> (sourceUs: EDLFraction, frame: Int) {
        guard src.rate.num > 0, src.rate.den > 0, src.fps.num > 0, src.fps.den > 0 else {
            throw KeeperRejection(.badInput, "source \(src.sourceId) needs a positive rate and frame rate")
        }
        // t_source = (t_session - offset) / (num / den)
        let sourceUs = EDLFraction(EDLInteger(sessionUs) - EDLInteger(src.offsetUs)) / EDLFraction(src.rate.num, src.rate.den)
        let scaled = sourceUs * EDLFraction(EDLInteger(src.fps.num), EDLInteger(src.fps.den) * EDLInteger(StudioTime.microsecondsPerSecond))
        guard let frame = scaled.roundedHalfUp.intValue else { throw KeeperRejection(.badInput, "frame out of range") }
        return (sourceUs, frame)
    }

    /// A sort that keeps equal elements in their input order (Python's `sorted` is stable; the reference relies on it).
    static func stableSorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
        items.enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
