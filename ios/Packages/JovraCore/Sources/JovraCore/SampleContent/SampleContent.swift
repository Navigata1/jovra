import Foundation

/// Installs, resets and removes the demo library (ios-v1-spec SampleContent). Every installed object carries
/// isSample: sessions their `sample` block, the equipment its Sample label, the plan `sample: true`. Sample
/// media is not copied: sessions name it by `sample.mediaIds` and `SampleMediaCatalog` resolves the bundled
/// files, so a missing render is the missing-media state, never an install error.
public struct SampleContent: Sendable {
    public let library: SampleLibrary
    public init(library: SampleLibrary) { self.library = library }

    /// Installs whatever is missing. Sample sessions the player already edited are kept as they are; a real
    /// session that happens to use a sample id is never touched (`idInUse`).
    public func install(into store: SessionStore) async throws {
        try await store.installSampleContent(library, replacing: false)
    }

    /// Restores every sample object to its shipped bytes: edits, Trash and exports of sample sessions go.
    public func reset(in store: SessionStore) async throws {
        try await store.installSampleContent(library, replacing: true)
    }

    /// Deletes the sample sessions, equipment and plan. Real sessions, including one sharing a sample id, stay.
    public func remove(from store: SessionStore) async throws {
        try await store.removeSampleContent(sessionIDs: library.sessions.map(\.id))
    }

    public func isInstalled(in store: SessionStore) async throws -> Bool {
        let installed = Set(try await store.list(.init(sample: true, includeTrashed: true)).map(\.id))
        return library.sessions.contains { installed.contains($0.id) }
    }

    public static func installedEquipment(in store: SessionStore) async throws -> EquipmentDocument? {
        try await store.sampleRecord(SampleLibrary.equipmentFile).map { try ContractCodec.decode(EquipmentDocument.self, from: $0) }
    }

    public static func installedPracticePlan(in store: SessionStore) async throws -> PracticePlanDocument? {
        try await store.sampleRecord(SampleLibrary.practicePlanFile).map { try ContractCodec.decode(PracticePlanDocument.self, from: $0) }
    }
}

extension SessionStore {
    /// Sample equipment and plan live apart from the player's own documents, so removing them can never touch
    /// real equipment or a real plan.
    static let sampleContentFolder = "sample-content"

    func installSampleContent(_ library: SampleLibrary, replacing: Bool) throws {
        for session in library.sessions {
            let exists = FileManager.default.fileExists(atPath: try folder(session.id).path)
            if exists {
                guard (try? load(session.id))?.sample != nil else { throw SampleContentError.idInUse(session.id) }
            }
        }
        if replacing { try removeSampleContent(sessionIDs: library.sessions.map(\.id)) }
        for session in library.sessions where !FileManager.default.fileExists(atPath: try folder(session.id).path) {
            try create(session)
        }
        let records = try auxiliaryFolder(Self.sampleContentFolder)
        for (name, bytes) in [(SampleLibrary.equipmentFile, try CanonicalJSON.encode(library.equipment)),
                              (SampleLibrary.practicePlanFile, try CanonicalJSON.encode(library.practicePlan))]
        where !FileManager.default.fileExists(atPath: records.appendingPathComponent(name).path) {
            try writeAtomically(bytes, named: name, in: records, temporaryPrefix: ".sample-")
        }
    }

    func removeSampleContent(sessionIDs: [String]) throws {
        for id in sessionIDs where FileManager.default.fileExists(atPath: try folder(id).path) {
            // Only a document that is itself Sample goes; an unreadable folder is left for quarantine.
            guard (try? load(id))?.sample != nil else { continue }
            purgeTokens[id] = nil
            try removeSessionFolder(id)
        }
        let records = try auxiliaryFolder(Self.sampleContentFolder)
        for name in [SampleLibrary.equipmentFile, SampleLibrary.practicePlanFile] {
            let url = records.appendingPathComponent(name)
            try Self.refuseSymbolicLink(url)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    func sampleRecord(_ name: String) throws -> Data? {
        let url = try auxiliaryFolder(Self.sampleContentFolder).appendingPathComponent(name)
        try Self.refuseSymbolicLink(url)
        return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
}
