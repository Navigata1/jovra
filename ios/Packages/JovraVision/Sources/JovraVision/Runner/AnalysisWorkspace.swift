import Foundation

/// The files of one recording's analysis, under one folder:
///
///     run.json                    resumes recorded by earlier runs (evidence; never part of an output)
///     <stage>.output.json         a finished stage output (canonical JSON)
///     <stage>/checkpoint.json     where an unfinished stage stands: next window and its carried state
///     <stage>/w-<index>.json      one finished window's result
///
/// Every file is replaced atomically, window part before checkpoint, so a process killed at any point leaves
/// either the previous checkpoint or the next one. A file that cannot be read (a power loss before the data
/// reached the disk) is treated as absent: that stage starts again rather than resuming from a guess.
struct AnalysisWorkspace {
    let root: URL

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    func outputURL(_ stage: AnalysisStageID) -> URL { root.appendingPathComponent("\(stage.rawValue).output.json") }
    func stageFolder(_ stage: AnalysisStageID) -> URL { root.appendingPathComponent(stage.rawValue, isDirectory: true) }
    func checkpointURL(_ stage: AnalysisStageID) -> URL { stageFolder(stage).appendingPathComponent("checkpoint.json") }
    func partURL(_ stage: AnalysisStageID, window: Int) -> URL {
        stageFolder(stage).appendingPathComponent(String(format: "w-%06d.json", window))
    }
    var runLogURL: URL { root.appendingPathComponent("run.json") }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data { try encoder.encode(value) }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func read<Value: Decodable>(_ type: Value.Type, at url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Empties the workspace (a restart from the beginning).
    func clear() throws {
        try remove(root)
    }
}

/// Where an unfinished stage stands.
struct AnalysisCheckpoint<State: Codable & Equatable & Sendable>: Codable, Equatable {
    var kind = "jovra.analysisCheckpoint"
    var stage: AnalysisStageID
    var version: String
    var media: AnalysisMediaIdentity
    var windowMs: Int
    var windows: Int
    /// The first window not yet written.
    var nextWindow: Int
    var state: State
}

/// One finished window of one stage.
struct AnalysisWindowPart<Observation: Codable & Equatable & Sendable>: Codable, Equatable {
    var window: AnalysisWindow
    var result: AnalysisWindowResult<Observation>
}

/// A stage that continued from a checkpoint instead of starting at its first window.
public struct AnalysisResume: Codable, Equatable, Sendable {
    public var stage: AnalysisStageID
    /// The first window this run analysed.
    public var fromWindow: Int
    /// The stage's window count.
    public var windows: Int
    public init(stage: AnalysisStageID, fromWindow: Int, windows: Int) {
        self.stage = stage; self.fromWindow = fromWindow; self.windows = windows
    }
}

/// `run.json`: every resume of this recording's analysis since it last started from the beginning.
struct AnalysisRunLog: Codable, Equatable {
    var kind = "jovra.analysisRunLog"
    var resumes: [AnalysisResume] = []
}
