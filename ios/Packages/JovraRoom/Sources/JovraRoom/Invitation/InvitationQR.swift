import Foundation
import JovraCore

/// Why a scanned code is not a JOVRA room invitation (invitation.py `decode_qr`). Codes are the fixture's.
public enum InvitationQRError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Not the `jovra-room:1:` prefix: a JOVRA room QR is never a web URL or another scheme.
    case notJovraRoomCode
    /// Not unpadded base64url, not UTF-8, not one JSON object.
    case malformedPayload
    /// The JSON repeats a key (two parsers could disagree on which one wins).
    case duplicateKey
    /// The JSON is not byte-identical to its canonical re-encoding.
    case nonCanonicalPayload
    /// Strictly decoded, but not a valid `jovra.room.invitation-payload/1` record.
    case invalidRecord(RoomDecodingError)

    public var code: String {
        switch self {
        case .notJovraRoomCode: "notJovraRoomCode"
        case .malformedPayload: "malformedPayload"
        case .duplicateKey: "duplicateKey"
        case .nonCanonicalPayload: "nonCanonicalPayload"
        case .invalidRecord: "invalidRecord"
        }
    }

    // Never echoes the scanned text: it holds the join token.
    public var description: String { code }
}

/// The QR text: `jovra-room:1:` + unpadded base64url(canonical JSON of the payload). Decoding is strict so every port
/// reads the same bytes the same way: the prefix, the base64url alphabet only, no duplicate keys, and the JSON must
/// equal its canonical re-encoding byte for byte.
public enum InvitationQR {
    public static let prefix = "jovra-room:1:"

    public static func encode(_ payload: InvitationPayload) throws -> String {
        prefix + Base64URL.encode(Array(try CanonicalJSON.encode(payload)))
    }

    /// The strict layer the reference pins: returns the payload's canonical JSON bytes, or the reference's code.
    public static func decodeCanonicalBytes(_ text: String) throws(InvitationQRError) -> Data {
        guard text.hasPrefix(prefix) else { throw .notJovraRoomCode }
        guard let raw = Base64URL.decode(String(text.dropFirst(prefix.count))),
              String(bytes: raw, encoding: .utf8) != nil else { throw .malformedPayload }
        let canonical: Data
        do { canonical = try CanonicalJSON.canonicalize(Data(raw)) } catch ContractError.duplicateJSONKey {
            throw .duplicateKey
        } catch {
            throw .malformedPayload
        }
        guard canonical.first == UInt8(ascii: "{") else { throw .malformedPayload }
        guard canonical == Data(raw) else { throw .nonCanonicalPayload }
        return canonical
    }

    /// The strict layer, then the payload record's schema. Record rules (lifetime, roles, endpoints) are the joiner's
    /// checks: `InvitationJoiner.verify`.
    public static func decode(_ text: String) throws(InvitationQRError) -> InvitationPayload {
        let bytes = try decodeCanonicalBytes(text)
        let record: RoomRecord
        do { record = try RoomRecord.decode(bytes) } catch let error as RoomDecodingError {
            throw .invalidRecord(error)
        } catch {
            throw .malformedPayload
        }
        guard case .invitationPayload(let payload) = record else {
            throw .invalidRecord(.unknownSchemaVersion(record.schemaVersion))
        }
        return payload
    }
}
