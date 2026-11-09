import Foundation

public enum LabelScoringError: Error, Equatable, CustomStringConvertible {
    case invalidLabels([String])
    case invalidObservations([String])

    public var description: String {
        switch self {
        case .invalidLabels(let problems): "the labels cannot be scored: " + problems.joined(separator: "; ")
        case .invalidObservations(let problems): "the observations cannot be scored: " + problems.joined(separator: "; ")
        }
    }
}

/// Task `labelScoring` 1.0.0: scores what a stage observed against a person's labels, separately for the
/// tuning and the held-out windows. The rule, with the reasons, is the docstring of
/// `spec/reference/jovra_ref/labels.py`; `spec/fixtures/labels/L*.json` are the hand-computed vectors both
/// implementations reproduce.
///
/// In short: each kind is matched over the whole recording with the eventTimes rule (nearest unmatched
/// observation within the tolerance, the earlier one on a tie). A matched pair belongs to the split of its
/// label, an unmatched observation to the split of its own time. A bounce label that is not in play absorbs
/// its observation without reward or penalty. A kind the stage omits is not scored.
public enum LabelScorer {
    public static let taskId = "labelScoring"
    public static let version = "1.0.0"

    static let splits: [GroundTruth.Split] = [.tuning, .heldOut]

    public static func score(labels: BenchmarkLabels, observations: StageObservations,
                             tolerances: LabelScoringTolerances = .standard) throws -> LabelScoreReport {
        let labelProblems = labels.problems()
        guard labelProblems.isEmpty else { throw LabelScoringError.invalidLabels(labelProblems) }
        let observationProblems = observations.problems(against: labels)
        guard observationProblems.isEmpty else { throw LabelScoringError.invalidObservations(observationProblems) }

        var rows: [GroundTruth.Split: [LabelScoreRow]] = [.tuning: [], .heldOut: []]
        let split = labels.split
        if let observed = observations.hits {
            let scored = try hits(labels: labels, observed: observed, tolerance: Rational(tolerances.hit))
            for name in splits { rows[name, default: []] += scored[name] ?? [] }
        }
        if let observed = observations.bounces {
            let scored = try bounces(labels: labels, observed: observed, tolerance: Rational(tolerances.bounce))
            for name in splits { rows[name, default: []] += scored[name] ?? [] }
        }
        if let observed = observations.rallies {
            let scored = try rallyBoundaries(labels: labels, observed: observed, tolerance: Rational(tolerances.rallyBoundary))
            for name in splits { rows[name, default: []] += scored[name] ?? [] }
        }
        if let observed = observations.courtCorners {
            let scored = courtCorners(labels: labels, observed: observed)
            for name in splits { rows[name, default: []] += scored[name] ?? [] }
        }

        func result(_ name: GroundTruth.Split) throws -> LabelScoreReport.SplitResult {
            let ranges = split.windows(in: name).map(split.range(ofWindow:))
            let total = try ranges.reduce(Rational.zero) { try $0.adding($1.end.subtracting($1.start)) }
            var mine = rows[name] ?? []
            if let analysed = observations.analysed {
                var covered = Rational.zero
                for window in ranges {
                    for range in analysed {
                        let from = max(window.start, Rational(range.start)), to = min(window.end, Rational(range.end))
                        if from < to { covered = try covered.adding(to.subtracting(from)) }
                    }
                }
                mine.append(try ratio("coverage", "analysed share", exact: total == .zero ? nil : covered.divided(by: total)))
            }
            let milliseconds = try total.multiplied(by: Rational(1000))
            return LabelScoreReport.SplitResult(windows: ranges.count, durationMs: Int(milliseconds.numerator / milliseconds.denominator), rows: mine)
        }
        return LabelScoreReport(tuning: try result(.tuning), heldOut: try result(.heldOut))
    }

    // MARK: Matching

    struct Matching {
        /// (label index, observation index), in label order.
        let pairs: [(label: Int, observation: Int)]
        /// Observation indexes no label took.
        let unmatched: [Int]
    }

    /// The eventTimes rule (`EventTimesTask.match`), keeping which observation each label took. Labels must be
    /// in time order, which a valid label document guarantees.
    static func match(labels: [Rational], observed: [Rational], tolerance: Rational) throws -> Matching {
        let order = observed.indices.sorted { (observed[$0], $0) < (observed[$1], $1) }
        var used = [Bool](repeating: false, count: order.count)
        var pairs: [(label: Int, observation: Int)] = []
        var first = 0
        for (index, time) in labels.enumerated() {
            let low = try time.subtracting(tolerance), high = try time.adding(tolerance)
            while first < order.count, observed[order[first]] < low { first += 1 }
            var best: (position: Int, delta: Rational)?
            var position = first
            while position < order.count, observed[order[position]] <= high {
                if !used[position] {
                    let delta = try observed[order[position]].subtracting(time).magnitude
                    if best == nil || delta < best!.delta { best = (position, delta) }
                }
                position += 1
            }
            if let best {
                used[best.position] = true
                pairs.append((index, order[best.position]))
            }
        }
        return Matching(pairs: pairs, unmatched: order.indices.filter { !used[$0] }.map { order[$0] })
    }

    // MARK: Kinds

    private static func hits(labels: BenchmarkLabels, observed: [StageObservations.Hit],
                             tolerance: Rational) throws -> [GroundTruth.Split: [LabelScoreRow]] {
        let group = "hits", split = labels.split
        let labelTimes = labels.hits.map { Rational($0.time) }, observedTimes = observed.map { Rational($0.time) }
        let matching = try RationalOverflow.naming("hit matches") { try match(labels: labelTimes, observed: observedTimes, tolerance: tolerance) }
        var out: [GroundTruth.Split: [LabelScoreRow]] = [:]
        for name in splits {
            let mine = matching.pairs.filter { split.split(of: labels.hits[$0.label].time) == name }
            let inSplit = labels.hits.indices.filter { split.split(of: labels.hits[$0].time) == name }
            let extra = matching.unmatched.filter { split.split(of: observed[$0].time) == name }.count
            let deltas = try mine.map { try observedTimes[$0.observation].subtracting(labelTimes[$0.label]) }
            let compared = mine.compactMap { pair -> (BenchmarkLabels.Stroke, BenchmarkLabels.Stroke)? in
                guard let labelled = labels.hits[pair.label].stroke, let seen = observed[pair.observation].stroke else { return nil }
                return (labelled, seen)
            }
            var rows = [count(group, "labels", inSplit.count), count(group, "observations", mine.count + extra),
                        count(group, "matched", mine.count),
                        try ratio(group, "precision", mine.count, mine.count + extra), try ratio(group, "recall", mine.count, inSplit.count)]
            for player in BenchmarkLabels.Player.allCases {
                let total = inSplit.filter { labels.hits[$0].player == player }.count
                let found = mine.filter { labels.hits[$0.label].player == player }.count
                rows.append(try ratio(group, "recall \(player.rawValue)", found, total))
            }
            rows += [try milliseconds(group, "timing MAE", sum: try sum(deltas.map(\.magnitude)), count: deltas.count, signed: false),
                     try milliseconds(group, "timing bias", sum: try sum(deltas), count: deltas.count, signed: true),
                     count(group, "strokes compared", compared.count),
                     try ratio(group, "stroke accuracy", compared.filter { $0.0 == $0.1 }.count, compared.count)]
            out[name] = rows
        }
        return out
    }

    private static func bounces(labels: BenchmarkLabels, observed: [StageObservations.Bounce],
                                tolerance: Rational) throws -> [GroundTruth.Split: [LabelScoreRow]] {
        let group = "bounces", split = labels.split
        let labelTimes = labels.bounces.map { Rational($0.time) }, observedTimes = observed.map { Rational($0.time) }
        let matching = try RationalOverflow.naming("bounce matches") { try match(labels: labelTimes, observed: observedTimes, tolerance: tolerance) }
        var out: [GroundTruth.Split: [LabelScoreRow]] = [:]
        for name in splits {
            let inSplit = labels.bounces.indices.filter { split.split(of: labels.bounces[$0].time) == name }
            let inPlay = inSplit.filter { labels.bounces[$0].inPlay }
            let mine = matching.pairs.filter { split.split(of: labels.bounces[$0.label].time) == name }
            let scored = mine.filter { labels.bounces[$0.label].inPlay }
            let extra = matching.unmatched.filter { split.split(of: observed[$0].time) == name }.count
            let deltas = try scored.map { try observedTimes[$0.observation].subtracting(labelTimes[$0.label]).magnitude }
            let distances = scored.compactMap { pair in
                observed[pair.observation].imagePoint.map { distance($0, labels.bounces[pair.label].imagePoint, in: labels.recording) }
            }
            out[name] = [
                count(group, "labels in play", inPlay.count), count(group, "labels not in play", inSplit.count - inPlay.count),
                count(group, "observations", scored.count + extra), count(group, "matched", scored.count),
                count(group, "dropped on a label not in play", mine.count - scored.count),
                try ratio(group, "precision", scored.count, scored.count + extra), try ratio(group, "recall", scored.count, inPlay.count),
                try milliseconds(group, "timing MAE", sum: try sum(deltas), count: deltas.count, signed: false),
                count(group, "placed", distances.count),
                pixels(group, "placement error median", median(distances)), pixels(group, "placement error mean", mean(distances)),
            ]
        }
        return out
    }

    private static func rallyBoundaries(labels: BenchmarkLabels, observed: [StageObservations.Range],
                                        tolerance: Rational) throws -> [GroundTruth.Split: [LabelScoreRow]] {
        let group = "rally boundaries", split = labels.split
        var tally: [GroundTruth.Split: (labels: Int, matched: Int, extra: Int)] = [.tuning: (0, 0, 0), .heldOut: (0, 0, 0)]
        let sides: [(labels: [RationalTime], observed: [RationalTime])] = [
            (labels.rallies.map(\.start), observed.map(\.start)),
            (labels.rallies.compactMap(\.end), observed.map(\.end)),
        ]
        for side in sides {
            let matching = try RationalOverflow.naming("rally boundary matches") {
                try match(labels: side.labels.map(Rational.init), observed: side.observed.map(Rational.init), tolerance: tolerance)
            }
            for time in side.labels { tally[split.split(of: time)]!.labels += 1 }
            for pair in matching.pairs { tally[split.split(of: side.labels[pair.label])]!.matched += 1 }
            for index in matching.unmatched { tally[split.split(of: side.observed[index])]!.extra += 1 }
        }
        var out: [GroundTruth.Split: [LabelScoreRow]] = [:]
        for name in splits {
            let t = tally[name]!
            out[name] = [
                count(group, "labels", t.labels), count(group, "observations", t.matched + t.extra), count(group, "matched", t.matched),
                try ratio(group, "precision", t.matched, t.matched + t.extra), try ratio(group, "recall", t.matched, t.labels),
                try ratio(group, "F1", 2 * t.matched, 2 * t.matched + t.extra + (t.labels - t.matched)),
            ]
        }
        return out
    }

    private static func courtCorners(labels: BenchmarkLabels, observed: [StageObservations.CourtCorners]) -> [GroundTruth.Split: [LabelScoreRow]] {
        let group = "court corners", split = labels.split
        var errors: [GroundTruth.Split: [Double]] = [.tuning: [], .heldOut: []]
        var unlabelled: [GroundTruth.Split: Int] = [.tuning: 0, .heldOut: 0]
        for observation in observed {
            let name = split.split(of: observation.time)
            guard let position = labels.cameraPositions.last(where: { $0.from <= observation.time }) else {
                unlabelled[name, default: 0] += 1
                continue
            }
            for (mine, theirs) in zip(position.corners.points, observation.points) {
                if let mine, let theirs { errors[name, default: []].append(distance(theirs, mine, in: labels.recording)) }
            }
        }
        var out: [GroundTruth.Split: [LabelScoreRow]] = [:]
        for name in splits {
            let found = errors[name] ?? []
            out[name] = [count(group, "corners compared", found.count),
                         count(group, "observations before any labelled camera position", unlabelled[name] ?? 0),
                         pixels(group, "corner error mean", mean(found)), pixels(group, "corner error max", found.max())]
        }
        return out
    }

    // MARK: Rows

    private static func count(_ group: String, _ name: String, _ value: Int) -> LabelScoreRow {
        LabelScoreRow(group: group, name: name, value: "\(value)")
    }

    private static func ratio(_ group: String, _ name: String, _ n: Int, _ d: Int) throws -> LabelScoreRow {
        try ratio(group, name, exact: d == 0 ? nil : Rational(Int64(n), Int64(d)))
    }

    private static func ratio(_ group: String, _ name: String, exact: Rational?) throws -> LabelScoreRow {
        let value = try RationalOverflow.naming("\(group) \(name)") { try exact?.decimalString(places: 4) }
        return LabelScoreRow(group: group, name: name, value: value, exact: .some(exact))
    }

    private static func milliseconds(_ group: String, _ name: String, sum: Rational, count: Int, signed: Bool) throws -> LabelScoreRow {
        guard count > 0 else { return LabelScoreRow(group: group, name: name, unit: "ms", value: nil, exact: .some(nil)) }
        return try RationalOverflow.naming("\(group) \(name)") {
            let exact = try sum.multiplied(by: Rational(1000)).divided(by: Rational(Int64(count)))
            let digits = try exact.magnitude.decimalString(places: 3)
            let value = signed ? (exact < .zero ? "-" : "+") + digits : digits
            return LabelScoreRow(group: group, name: name, unit: "ms", value: value, exact: .some(exact))
        }
    }

    private static func pixels(_ group: String, _ name: String, _ value: Double?) -> LabelScoreRow {
        LabelScoreRow(group: group, name: name, unit: "px", value: value.map(pixelsText))
    }

    /// floor(x * 100 + 0.5) / 100 as text: the same arithmetic as the Python reference.
    static func pixelsText(_ value: Double) -> String {
        let hundredths = Int((value * 100 + 0.5).rounded(.down))
        let cents = hundredths % 100
        return "\(hundredths / 100)." + (cents < 10 ? "0\(cents)" : "\(cents)")
    }

    private static func sum(_ values: [Rational]) throws -> Rational {
        try values.reduce(Rational.zero) { try $0.adding($1) }
    }

    /// Distance between two image points in display pixels: subtract, scale, square, add, sqrt, in that order.
    static func distance(_ a: ImagePoint, _ b: ImagePoint, in recording: BenchmarkLabels.Recording) -> Double {
        let dx = (a.x - b.x) * Double(recording.width)
        let dy = (a.y - b.y) * Double(recording.height)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let ordered = values.sorted(), middle = ordered.count / 2
        return ordered.count % 2 == 1 ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var total = 0.0
        for value in values { total += value }
        return total / Double(values.count)
    }
}
