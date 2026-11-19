import Foundation

public enum LabelSetError: Error, Equatable, CustomStringConvertible {
    case notInLabelsFolder(String)
    case wrongFileName(expected: String, actual: String)
    case invalidLabels([String])
    case notHumanLabels
    case openRally

    public var description: String {
        switch self {
        case .notInLabelsFolder(let path): "\(path) is not in \(BenchmarkLabelSet.folder): move the label file there before sealing it"
        case .wrongFileName(let expected, let actual): "a label file is named after its recording's hash: expected \(expected), got \(actual)"
        case .invalidLabels(let problems): "the label file is not consistent: " + problems.joined(separator: "; ")
        case .notHumanLabels: "only labels a person made on a recording enter the label set"
        case .openRally: "the last rally is still open: close it in the labelling tool (]) before sealing"
        }
    }
}

/// `spec/benchmarks/labels/manifest.json` (`spec/schemas/benchmark-label-set.schema.json`): the label set that
/// gates V02-V07. Each sealed label file is recorded with the SHA-256 of its bytes, its hash-fixed split and
/// its counts; the set is `complete` exactly when every recording's targets are met.
public struct BenchmarkLabelSet: Codable, Hashable, Sendable {
    public static let folder = "spec/benchmarks/labels"
    public static let path = "spec/benchmarks/labels/manifest.json"

    public enum Status: String, Codable, Hashable, Sendable {
        case founderPending
        case complete
    }

    public struct Recording: Codable, Hashable, Sendable {
        public let role: String
        public let sha256: String
        public let description: String
        /// Minimum label counts by name (`hits`, `strokes`, `bounces`, `rallies`, `cameraPositions`).
        public let targets: [String: Int]
    }

    public struct LabelFile: Codable, Hashable, Sendable {
        public let path: String
        public let recordingSha256: String
        public let labelsSha256: String
        public let split: LabelSplit
        public let counts: BenchmarkLabels.Counts
    }

    public struct Progress: Hashable, Sendable {
        public let role: String
        public let target: String
        public let wanted: Int
        public let labelled: Int
        public var met: Bool { labelled >= wanted }

        public init(role: String, target: String, wanted: Int, labelled: Int) {
            self.role = role
            self.target = target
            self.wanted = wanted
            self.labelled = labelled
        }
    }

    public let schemaVersion: String
    public let kind: String
    public let description: String
    public let status: Status
    public let recordings: [Recording]
    public let labelFiles: [LabelFile]

    public static func load(repository root: URL) throws -> BenchmarkLabelSet {
        try JSONDecoder().decode(BenchmarkLabelSet.self, from: Data(contentsOf: root.appendingPathComponent(path)))
    }

    /// Every target with what is labelled so far. Only label files made on the recording itself count.
    public var progress: [Progress] {
        recordings.flatMap { recording in
            recording.targets.sorted { $0.key < $1.key }.map { target, wanted in
                let labelled = labelFiles.filter { $0.recordingSha256 == recording.sha256 }.reduce(0) { $0 + ($1.counts[target] ?? 0) }
                return Progress(role: recording.role, target: target, wanted: wanted, labelled: labelled)
            }
        }
    }

    /// The set with one label file sealed into it: hashed, its split and counts recorded, and the status
    /// recomputed. Sealing the same file again replaces its entry.
    public func sealing(labelFile url: URL, repository root: URL) throws -> BenchmarkLabelSet {
        let folder = root.appendingPathComponent(Self.folder).standardizedFileURL.path
        guard url.standardizedFileURL.deletingLastPathComponent().path == folder else {
            throw LabelSetError.notInLabelsFolder(url.path)
        }
        let data = try Data(contentsOf: url)
        let labels = try JSONDecoder().decode(BenchmarkLabels.self, from: data)
        guard url.lastPathComponent == labels.fileName else {
            throw LabelSetError.wrongFileName(expected: labels.fileName, actual: url.lastPathComponent)
        }
        let problems = labels.problems()
        guard problems.isEmpty else { throw LabelSetError.invalidLabels(problems) }
        guard labels.labelledBy.method == .human else { throw LabelSetError.notHumanLabels }
        guard !labels.rallies.contains(where: { $0.end == nil }) else { throw LabelSetError.openRally }
        let entry = LabelFile(path: "\(Self.folder)/\(url.lastPathComponent)", recordingSha256: labels.recording.sha256,
                              labelsSha256: BenchmarkLabels.sha256(of: data), split: labels.split, counts: labels.counts)
        let files = (labelFiles.filter { $0.path != entry.path } + [entry]).sorted { $0.path < $1.path }
        let pending = BenchmarkLabelSet(schemaVersion: schemaVersion, kind: kind, description: description,
                                        status: .founderPending, recordings: recordings, labelFiles: files)
        return BenchmarkLabelSet(schemaVersion: schemaVersion, kind: kind, description: description,
                                 status: pending.progress.allSatisfy(\.met) ? .complete : .founderPending,
                                 recordings: recordings, labelFiles: files)
    }

    /// Pretty, key-sorted JSON with a trailing newline: the committed form.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}
