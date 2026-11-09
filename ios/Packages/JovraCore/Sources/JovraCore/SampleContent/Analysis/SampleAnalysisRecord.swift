import Foundation

/// One sample session's analysis records (spec/fixtures/sample/analysis/sessions, schema sample-analysis): per-shot
/// stroke tags and placements, calibrations, serve marks, studied swings and comparison projects. They ship apart
/// from the library documents, and `SampleLibrary` appends them to the named session, so the installed sample is the
/// library plus its analysis while no library byte changes (T40).
public struct SampleAnalysisRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case value = "jovra.sampleAnalysis" }

    public static let sessionsFolder = "sessions"
    public static let fileSuffix = ".analysis.json"

    public var schemaVersion: SchemaVersion
    public var kind: Kind
    public var sessionId: String
    public var sample: SessionSampleInfo?
    public var shots: [SessionShot]
    public var calibrations: [SessionCalibration]
    public var serveMarks: [SessionServeMark]
    public var swings: [SessionSwing]
    public var comparisons: [SessionComparison]

    /// Reads every `sessions/*.analysis.json` under `directory`, in file-name order.
    public static func loadAll(from directory: URL) throws -> [SampleAnalysisRecord] {
        let folder = directory.appendingPathComponent(sessionsFolder, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(fileSuffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try ContractCodec.decode(SampleAnalysisRecord.self, from: Data(contentsOf: $0)) }
    }

    /// The session with these records appended after its own. Refuses a record that is not Sample, belongs to
    /// another session or repeats an id the session already holds, so applying can never shadow a record.
    func applied(to session: SessionDocument) throws -> SessionDocument {
        guard sample != nil else { throw SampleContentError.notSample("analysis \(sessionId)") }
        guard session.id == sessionId, session.sample != nil else {
            throw SampleContentError.invalidLibrary("analysis \(sessionId) does not belong to \(session.id)")
        }
        var out = session
        out.shots = try Self.merge(session.shots, shots, \.id, "shot")
        out.calibrations = try Self.merge(session.calibrations, calibrations, \.id, "calibration")
        out.serveMarks = try Self.merge(session.serveMarks, serveMarks, \.id, "serve mark")
        out.swings = try Self.merge(session.swings, swings, \.id, "swing")
        out.comparisons = try Self.merge(session.comparisons, comparisons, \.id, "comparison")
        return out
    }

    private static func merge<T>(_ existing: [T]?, _ added: [T], _ id: KeyPath<T, String>, _ what: String) throws -> [T]? {
        guard existing != nil || !added.isEmpty else { return nil }
        var seen = Set((existing ?? []).map { $0[keyPath: id] })
        for item in added where !seen.insert(item[keyPath: id]).inserted {
            throw SampleContentError.invalidLibrary("analysis repeats \(what) id \(item[keyPath: id])")
        }
        return (existing ?? []) + added
    }
}
