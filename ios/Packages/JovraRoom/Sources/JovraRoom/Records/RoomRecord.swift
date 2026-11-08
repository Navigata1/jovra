import Foundation
import JovraCore

/// Any `jovra.room.*/1` record, decoded strictly from bytes. Decoding is the schema layer: malformed JSON, duplicate
/// keys, unknown properties, out-of-range values and broken patterns are refused with `RoomDecodingError`, and a
/// document that would not re-encode to its own canonical bytes is refused too. `checkRules` is the record layer
/// (spec/room/reference/jovra_room/records.py), refusing with a `RoomRuleViolation` code.
public enum RoomRecord: Equatable, Sendable {
    case invitation(RoomInvitation)
    case invitationPayload(InvitationPayload)
    case joinRequest(JoinRequest)
    case joinChallenge(JoinNonceFrame)
    case joinReveal(JoinNonceFrame)
    case deviceStatus(DeviceStatusRecord)
    case snapshot(RoomSnapshotRecord)
    case watchBridge(WatchBridgeSnapshot)
    case command(RoomCommand)
    case receipt(ReceiptRecord)
    case analysisResult(AnalysisResult)
    case watchLocal(WatchLocalMessage)

    /// Every record kind this package reads, by schemaVersion.
    public static let schemaVersions: [String] = [
        RoomInvitation.schemaVersionValue, InvitationPayload.schemaVersionValue, JoinRequest.schemaVersionValue,
        JoinNonceFrame.Kind.challenge.rawValue, JoinNonceFrame.Kind.reveal.rawValue,
        RoomDeviceStatus.schemaVersionValue, RoomSnapshotRecord.schemaVersionValue,
        WatchBridgeSnapshot.schemaVersionValue, RoomCommand.schemaVersionValue, RoomReceipt.schemaVersionValue,
        AnalysisResult.schemaVersionValue, WatchLocalMessage.schemaVersionValue,
    ]

    public static func decode(_ data: Data) throws -> RoomRecord {
        let canonical: Data
        do { canonical = try CanonicalJSON.canonicalize(data) } catch {
            throw RoomDecodingError.malformed("\(error)")
        }
        let version: String
        do { version = try JSONDecoder().decode(VersionProbe.self, from: canonical).schemaVersion ?? "" } catch {
            throw RoomDecodingError.malformed("not a JSON object with a string schemaVersion")
        }
        let record: RoomRecord
        do { record = try decode(version: version, canonical) } catch let error as DecodingError {
            throw RoomDecodingError(error)
        }
        guard try record.canonicalData() == canonical else {
            throw RoomDecodingError.malformed("the document does not re-encode to its own canonical bytes")
        }
        return record
    }

    private struct VersionProbe: Decodable { let schemaVersion: String? }

    private static func decode(version: String, _ data: Data) throws -> RoomRecord {
        let d = JSONDecoder()
        switch version {
        case RoomInvitation.schemaVersionValue: return .invitation(try d.decode(RoomInvitation.self, from: data))
        case InvitationPayload.schemaVersionValue:
            return .invitationPayload(try d.decode(InvitationPayload.self, from: data))
        case JoinRequest.schemaVersionValue: return .joinRequest(try d.decode(JoinRequest.self, from: data))
        case JoinNonceFrame.Kind.challenge.rawValue: return .joinChallenge(try d.decode(JoinNonceFrame.self, from: data))
        case JoinNonceFrame.Kind.reveal.rawValue: return .joinReveal(try d.decode(JoinNonceFrame.self, from: data))
        case RoomDeviceStatus.schemaVersionValue: return .deviceStatus(try d.decode(DeviceStatusRecord.self, from: data))
        case RoomSnapshotRecord.schemaVersionValue: return .snapshot(try d.decode(RoomSnapshotRecord.self, from: data))
        case WatchBridgeSnapshot.schemaVersionValue:
            return .watchBridge(try d.decode(WatchBridgeSnapshot.self, from: data))
        case RoomCommand.schemaVersionValue: return .command(try d.decode(RoomCommand.self, from: data))
        case RoomReceipt.schemaVersionValue: return .receipt(try d.decode(ReceiptRecord.self, from: data))
        case AnalysisResult.schemaVersionValue: return .analysisResult(try d.decode(AnalysisResult.self, from: data))
        case WatchLocalMessage.schemaVersionValue: return .watchLocal(try d.decode(WatchLocalMessage.self, from: data))
        default: throw RoomDecodingError.unknownSchemaVersion(version)
        }
    }

    public var schemaVersion: String {
        switch self {
        case .invitation: RoomInvitation.schemaVersionValue
        case .invitationPayload: InvitationPayload.schemaVersionValue
        case .joinRequest: JoinRequest.schemaVersionValue
        case .joinChallenge(let frame), .joinReveal(let frame): frame.kind.rawValue
        case .deviceStatus: RoomDeviceStatus.schemaVersionValue
        case .snapshot: RoomSnapshotRecord.schemaVersionValue
        case .watchBridge: WatchBridgeSnapshot.schemaVersionValue
        case .command: RoomCommand.schemaVersionValue
        case .receipt: RoomReceipt.schemaVersionValue
        case .analysisResult: AnalysisResult.schemaVersionValue
        case .watchLocal: WatchLocalMessage.schemaVersionValue
        }
    }

    /// Canonical bytes (sorted keys, no whitespace, UTF-8 with non-ASCII unescaped; JovraCore ADR-0029).
    public func canonicalData() throws -> Data {
        switch self {
        case .invitation(let r): try CanonicalJSON.encode(r)
        case .invitationPayload(let r): try CanonicalJSON.encode(r)
        case .joinRequest(let r): try CanonicalJSON.encode(r)
        case .joinChallenge(let r), .joinReveal(let r): try CanonicalJSON.encode(r)
        case .deviceStatus(let r): try CanonicalJSON.encode(r)
        case .snapshot(let r): try CanonicalJSON.encode(r)
        case .watchBridge(let r): try CanonicalJSON.encode(r)
        case .command(let r): try CanonicalJSON.encode(r)
        case .receipt(let r): try CanonicalJSON.encode(r)
        case .analysisResult(let r): try CanonicalJSON.encode(r)
        case .watchLocal(let r): try CanonicalJSON.encode(r)
        }
    }

    /// The record-level rules JSON Schema cannot express; throws `RoomRuleViolation`.
    public func checkRules(registry: RoomCapabilityRegistry) throws {
        switch self {
        case .invitation(let r): try RecordRules.check(r)
        case .invitationPayload(let r): try RecordRules.check(r)
        case .joinRequest(let r): try RecordRules.check(r)
        case .joinChallenge, .joinReveal, .watchLocal: return
        case .deviceStatus(let r): try RecordRules.check(r)
        case .snapshot(let r): try RecordRules.check(r)
        case .watchBridge(let r): try RecordRules.check(r, registry: registry)
        case .command(let r): try RecordRules.check(r)
        case .receipt(let r): try RecordRules.check(r.receipt)
        case .analysisResult(let r): try RecordRules.check(r, registry: registry)
        }
    }
}

extension RoomDecodingError {
    /// Maps a Foundation decoding failure (wrong JSON type, unknown enum value) onto the schema layer.
    init(_ error: DecodingError) {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context),
             .dataCorrupted(let context):
            self = .schema(path: jsonPointer(context.codingPath), reason: context.debugDescription)
        @unknown default:
            self = .schema(path: "/", reason: "\(error)")
        }
    }
}
