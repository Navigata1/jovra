import Foundation
import JovraBenchmark

/// `jovra-benchmark score` and `jovra-benchmark labels ...`: the label scorer and the label set (V01).
enum LabelCommands {
    struct Failure: Error {
        let message: String
    }

    static let usage = """
      jovra-benchmark score --labels FILE --observations FILE [--hit-tolerance V/T] [--bounce-tolerance V/T] [--boundary-tolerance V/T] [--json]
      jovra-benchmark labels seal FILE [--repo PATH]
      jovra-benchmark labels status [--repo PATH]
    """

    /// Runs one command and returns the exit status (0, or 4 when the label set is still founder-pending).
    static func run(_ arguments: [String]) throws -> Int32 {
        switch arguments.first {
        case "score":
            return try score(Array(arguments.dropFirst()))
        case "labels":
            switch arguments.dropFirst().first {
            case "seal": return try seal(Array(arguments.dropFirst(2)))
            case "status": return try status(Array(arguments.dropFirst(2)))
            default: throw Failure(message: "usage:\n" + usage)
            }
        default:
            throw Failure(message: "usage:\n" + usage)
        }
    }

    private struct Options {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var positional: [String] = []

        init(_ arguments: [String], flags known: Set<String> = []) throws {
            var iterator = arguments.makeIterator()
            while let argument = iterator.next() {
                guard argument.hasPrefix("--") else {
                    positional.append(argument)
                    continue
                }
                let name = String(argument.dropFirst(2))
                if known.contains(name) {
                    flags.insert(name)
                } else if let value = iterator.next() {
                    values[name] = value
                } else {
                    throw Failure(message: "\(argument) needs a value")
                }
            }
        }
    }

    private static func tolerance(_ text: String?, default fallback: RationalTime, flag: String) throws -> RationalTime {
        guard let text else { return fallback }
        let parts = text.split(separator: "/").compactMap { Int64($0) }
        guard parts.count == 2, parts[0] >= 0, parts[1] > 0 else { throw Failure(message: "--\(flag) must be VALUE/TIMESCALE, e.g. 100/1000") }
        return RationalTime(value: parts[0], timescale: parts[1])
    }

    private static func read<T: Decodable>(_ type: T.Type, _ path: String, what: String) throws -> (T, Data) {
        guard let data = FileManager.default.contents(atPath: path) else { throw Failure(message: "cannot read the \(what) at \(path)") }
        do {
            return (try JSONDecoder().decode(type, from: data), data)
        } catch {
            throw Failure(message: "\(path) is not a valid \(what): \(error)")
        }
    }

    private static func repository(_ options: Options) throws -> URL {
        do {
            return try MediaFixtureCatalog.locate(from: URL(fileURLWithPath: options.values["repo"] ?? FileManager.default.currentDirectoryPath)).root
        } catch {
            throw Failure(message: "\(error)")
        }
    }

    private static func score(_ arguments: [String]) throws -> Int32 {
        let options = try Options(arguments, flags: ["json"])
        guard let labelsPath = options.values["labels"], let observationsPath = options.values["observations"] else {
            throw Failure(message: "score needs --labels FILE and --observations FILE")
        }
        let (labels, labelData) = try read(BenchmarkLabels.self, labelsPath, what: "label file")
        let (observations, _) = try read(StageObservations.self, observationsPath, what: "observations file")
        let standard = LabelScoringTolerances.standard
        let tolerances = LabelScoringTolerances(
            hit: try tolerance(options.values["hit-tolerance"], default: standard.hit, flag: "hit-tolerance"),
            bounce: try tolerance(options.values["bounce-tolerance"], default: standard.bounce, flag: "bounce-tolerance"),
            rallyBoundary: try tolerance(options.values["boundary-tolerance"], default: standard.rallyBoundary, flag: "boundary-tolerance"))
        let report: LabelScoreReport
        do {
            report = try LabelScorer.score(labels: labels, observations: observations, tolerances: tolerances)
        } catch {
            throw Failure(message: "\(error)")
        }
        if options.flags.contains("json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
            return 0
        }
        print("task          \(LabelScorer.taskId) \(LabelScorer.version)")
        print("recording     sha256 \(labels.recording.sha256)")
        print("labels        sha256 \(BenchmarkLabels.sha256(of: labelData)) (\(labels.labelledBy.method.rawValue), \(labels.labelledBy.tool))")
        print("observations  \(observations.producer)")
        print("split         \(labels.split.summary)")
        func shown(_ time: RationalTime) -> String {
            let ms = Rational(time.value * 1000, time.timescale)
            return ms.denominator == 1 ? "\(ms.numerator) ms" : "\(time) s"
        }
        print("tolerances    hit \(shown(tolerances.hit)), bounce \(shown(tolerances.bounce)), rally boundary \(shown(tolerances.rallyBoundary))")
        print("")
        print(report.text())
        return 0
    }

    private static func seal(_ arguments: [String]) throws -> Int32 {
        let options = try Options(arguments)
        guard let path = options.positional.first, options.positional.count == 1 else { throw Failure(message: "labels seal needs one label file") }
        let root = try repository(options)
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        do {
            let sealed = try BenchmarkLabelSet.load(repository: root).sealing(labelFile: url, repository: root)
            try sealed.encoded().write(to: root.appendingPathComponent(BenchmarkLabelSet.path), options: .atomic)
            let entry = sealed.labelFiles.first { $0.path.hasSuffix(url.lastPathComponent) }
            print("sealed \(entry?.path ?? url.lastPathComponent)")
            print("  labels sha256  \(entry?.labelsSha256 ?? "")")
            print("  split          \(entry?.split.summary ?? "")")
            printProgress(sealed)
            return sealed.status == .complete ? 0 : 4
        } catch let error as LabelSetError {
            throw Failure(message: error.description)
        }
    }

    private static func status(_ arguments: [String]) throws -> Int32 {
        let options = try Options(arguments)
        let root = try repository(options)
        let set: BenchmarkLabelSet
        do {
            set = try BenchmarkLabelSet.load(repository: root)
        } catch {
            throw Failure(message: "cannot read \(BenchmarkLabelSet.path): \(error)")
        }
        printProgress(set)
        return set.status == .complete ? 0 : 4
    }

    private static func printProgress(_ set: BenchmarkLabelSet) {
        for item in set.progress {
            print("  \(item.met ? "met    " : "pending") \(item.role): \(item.labelled) of \(item.wanted) \(item.target)")
        }
        print("label set: \(set.status == .complete ? "complete" : "founder-pending (the V02-V07 gates stay closed)")")
    }
}
