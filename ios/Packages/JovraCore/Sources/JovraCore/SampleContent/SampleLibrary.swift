import Foundation

public enum SampleContentError: Error, Equatable, Sendable {
    /// A library document is not flagged Sample; nothing from it may be installed (CLAUDE.md hard rule 1).
    case notSample(String)
    /// A session names media the sample media manifest does not have, or another session's media.
    case unknownMedia(String)
    /// A real session already uses a sample id; installing would overwrite it.
    case idInUse(String)
    case invalidLibrary(String)
}

/// The demo library as shipped (spec/fixtures/sample/library, bundled by the app): eight Sample sessions, the
/// sample equipment and the sample practice plan, validated against the sample media manifest. With the analysis
/// overlays (spec/fixtures/sample/analysis, T40) the sessions carry their stroke tags, placements, calibrations,
/// serve marks, swings and comparisons, and that is what SampleContent installs and resets to.
public struct SampleLibrary: Equatable, Sendable {
    public static let sessionsFolder = "sessions"
    public static let equipmentFile = "equipment.json"
    public static let practicePlanFile = "practice-plan.json"

    public let sessions: [SessionDocument]
    public let equipment: EquipmentDocument
    public let practicePlan: PracticePlanDocument
    public let mediaManifest: SampleMediaManifest

    public init(sessions: [SessionDocument], equipment: EquipmentDocument, practicePlan: PracticePlanDocument,
                mediaManifest: SampleMediaManifest, analysis: [SampleAnalysisRecord] = []) throws {
        guard !sessions.isEmpty, Set(sessions.map(\.id)).count == sessions.count else {
            throw SampleContentError.invalidLibrary("sessions must be non-empty with unique ids")
        }
        for session in sessions {
            guard session.sample != nil else { throw SampleContentError.notSample(session.id) }
            for mediaID in session.sample?.mediaIds ?? [] {
                guard mediaManifest.media.contains(where: { $0.mediaId == mediaID && $0.sessionId == session.id }) else {
                    throw SampleContentError.unknownMedia(mediaID)
                }
            }
        }
        guard equipment.sample != nil else { throw SampleContentError.notSample("equipment") }
        guard practicePlan.sample == true else { throw SampleContentError.notSample(practicePlan.id) }
        self.sessions = try Self.applying(analysis, to: sessions)
        self.equipment = equipment
        self.practicePlan = practicePlan
        self.mediaManifest = mediaManifest
    }

    /// Reads `sessions/*.session.json`, `equipment.json` and `practice-plan.json` from `directory`, and the analysis
    /// overlays `sessions/*.analysis.json` from `analysis` when given.
    public static func load(from directory: URL, mediaManifest: URL, analysis: URL? = nil) throws -> SampleLibrary {
        let folder = directory.appendingPathComponent(sessionsFolder, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".session.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let sessions = try files.map { try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: $0)) }
        return try SampleLibrary(
            sessions: sessions,
            equipment: ContractCodec.decode(EquipmentDocument.self,
                                            from: Data(contentsOf: directory.appendingPathComponent(equipmentFile))),
            practicePlan: ContractCodec.decode(PracticePlanDocument.self,
                                               from: Data(contentsOf: directory.appendingPathComponent(practicePlanFile))),
            mediaManifest: ContractCodec.decode(SampleMediaManifest.self, from: Data(contentsOf: mediaManifest)),
            analysis: try analysis.map(SampleAnalysisRecord.loadAll(from:)) ?? [])
    }

    /// Each overlay applied to its session; one naming no library session, or a comparison side naming none, is
    /// refused so an installed comparison can always open both recordings.
    private static func applying(_ analysis: [SampleAnalysisRecord], to sessions: [SessionDocument]) throws -> [SessionDocument] {
        var out = sessions
        for record in analysis {
            guard let index = out.firstIndex(where: { $0.id == record.sessionId }) else {
                throw SampleContentError.invalidLibrary("analysis names no library session: \(record.sessionId)")
            }
            out[index] = try record.applied(to: out[index])
        }
        let ids = Set(out.map(\.id))
        for side in out.flatMap({ $0.comparisons ?? [] }).flatMap({ [$0.left, $0.right] }) where !ids.contains(side.sessionId) {
            throw SampleContentError.invalidLibrary("comparison names no library session: \(side.sessionId)")
        }
        return out
    }
}
