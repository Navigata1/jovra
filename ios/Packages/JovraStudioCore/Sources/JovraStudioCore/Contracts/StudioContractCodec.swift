import Foundation
import JovraCore

/// The Studio schema files this package carries (generated into `Generated/StudioSchemaSource.swift` from
/// spec/schemas/studio by `Tools/generate_contract_models.py`).
public enum StudioSchemaSource {
    /// FNV-1a 64 over each file's name, a NUL, its bytes and a NUL, in name order (the generator computes the same).
    public static func digest(of files: [String: String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for name in files.keys.sorted() {
            for byte in Array(name.utf8) + [0] + Array(files[name]!.utf8) + [0] {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The digest of the files embedded in this build.
    public static var embeddedDigest: String { digest(of: embedded) }

    /// Embedded schema files by name (each without its final newline), for drift tests.
    public static var files: [String: String] { embedded }
}

/// A Studio record or contract data file with a typed model (`Generated/StudioContractModels.swift`).
public protocol StudioContract: Codable, Equatable, Sendable {
    /// The `schemaVersion` the document states, for example `jovra.project-lock/1`.
    static var schemaVersion: String { get }
    /// The schema every document of this contract is checked against before it is decoded.
    static var schemaLocation: StudioSchemaLocation { get }
}

public enum StudioContractError: Error, Equatable, CustomStringConvertible {
    /// Not well-formed JSON (or duplicate names, or a number Decimal cannot hold).
    case unreadable(String)
    /// The document names another contract.
    case wrongSchemaVersion(expected: String, found: String?)
    /// The document breaks its schema; one line per violation.
    case schema([String])
    /// The typed model would not reproduce the document (a generator gap; never expected).
    case wouldLoseData(String)

    public var description: String {
        switch self {
        case .unreadable(let why): "unreadable Studio document: \(why)"
        case .wrongSchemaVersion(let expected, let found): "expected \(expected), found \(found ?? "no schemaVersion")"
        case .schema(let errors): "schema: " + errors.joined(separator: "; ")
        case .wouldLoseData(let why): "the model does not reproduce the document: \(why)"
        }
    }
}

/// Reads and writes Studio contracts strictly.
///
/// Reading: strict JSON (no duplicate names), the stated `schemaVersion`, then the full schema (unknown properties,
/// integral floats in integer fields, ECMA-262 patterns, ranges and every if/then rule), then the typed model through
/// core T03's `ContractCodec`, which also refuses a document the model cannot reproduce. Writing: core T03's canonical
/// writer (ADR-0029: sorted keys, compact UTF-8, exact number text), and the output is checked against the schema, so
/// this codec never writes a document it would refuse to read.
public enum StudioContractCodec {
    public static func decode<T: StudioContract>(_ type: T.Type, from data: Data, schemas: StudioSchemaSet = .studio) throws -> T {
        let value: StudioJSONValue
        do { value = try StudioJSONParser.parse(data) } catch { throw StudioContractError.unreadable("\(error)") }
        try check(value, as: type, schemas: schemas)
        do { return try ContractCodec.decode(type, from: data) } catch {
            throw StudioContractError.wouldLoseData("\(error)")
        }
    }

    /// Canonical bytes of a contract value; throws when the value breaks its schema.
    public static func encode<T: StudioContract>(_ value: T, schemas: StudioSchemaSet = .studio) throws -> Data {
        let data = try CanonicalJSON.encode(value)
        try check(StudioJSONParser.parse(data), as: T.self, schemas: schemas)
        return data
    }

    /// Decodes and re-encodes canonically (the round trip the conformance tests compare with the fixture).
    public static func roundTrip<T: StudioContract>(_ type: T.Type, _ data: Data) throws -> Data {
        try encode(decode(type, from: data))
    }

    static func check<T: StudioContract>(_ value: StudioJSONValue, as type: T.Type, schemas: StudioSchemaSet) throws {
        guard case .string(let version)? = value["schemaVersion"], version == T.schemaVersion else {
            let found: String? = if case .string(let s)? = value["schemaVersion"] { s } else { nil }
            throw StudioContractError.wrongSchemaVersion(expected: T.schemaVersion, found: found)
        }
        let errors = schemas.validate(value, against: T.schemaLocation)
        guard errors.isEmpty else { throw StudioContractError.schema(errors) }
    }
}

/// One registered decoder: the contract it reads and its strict decode-and-re-encode.
///
/// Each Swift module that owns a contract registers its decoders (this module: `StudioContracts.decoders`); the
/// conformance tests find every registered decoder through the test target's discovered consumers, so a later
/// ticket registers its own decoders in its own folder and never edits a shared list.
public struct StudioContractDecoder: Sendable {
    public let schemaVersion: String
    public let schemaLocation: StudioSchemaLocation
    private let body: @Sendable (Data) throws -> Data

    public static func of<T: StudioContract>(_ type: T.Type) -> StudioContractDecoder {
        StudioContractDecoder(schemaVersion: T.schemaVersion, schemaLocation: T.schemaLocation) {
            try StudioContractCodec.roundTrip(type, $0)
        }
    }

    private init(schemaVersion: String, schemaLocation: StudioSchemaLocation, body: @escaping @Sendable (Data) throws -> Data) {
        self.schemaVersion = schemaVersion
        self.schemaLocation = schemaLocation
        self.body = body
    }

    /// Strictly decodes `data` and returns its canonical re-encoding.
    public func roundTrip(_ data: Data) throws -> Data { try body(data) }
}

/// The contracts this folder models (STU-01): every Studio record and the three contract data files.
public enum StudioContracts {
    public static let decoders: [StudioContractDecoder] = [
        .of(ProjectLock.self), .of(SourceManifest.self), .of(SyncMap.self), .of(Observation.self),
        .of(KeeperCatalog.self), .of(BrollCatalog.self), .of(StoryProfileCatalog.self), .of(StoryBrief.self),
        .of(EditPlan.self), .of(ReferenceCatalog.self), .of(RenderJob.self), .of(Quote.self),
        .of(UsageReservation.self), .of(DeliveredArtifact.self), .of(Lesson.self), .of(CameraInvite.self),
        .of(StorageProviders.self), .of(RenderJobTransitions.self), .of(CreditClasses.self),
    ]
}
