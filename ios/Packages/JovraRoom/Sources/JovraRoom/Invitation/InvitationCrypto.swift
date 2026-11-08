/// The join messages both sides compute (spec/room/reference/jovra_room/invitation.py). The QR carries a join token of
/// at least 128 bits and a nonce; the guest proves possession with an HMAC instead of sending the token, commits to a
/// secret guest nonce before it sees the host's nonce, and both screens then show six digits that mix both keys and
/// all three nonces (commit, challenge, reveal: ADR-0027 §3 as amended 2026-10-07).
///
/// Secrets: generate tokens and nonces with `randomToken`/`randomNonce` (the platform CSPRNG), keep tokens in the
/// Keychain, and never log a token, proof, nonce or QR string.
public enum InvitationCrypto {
    /// `SHA-256("jovra-room-commit|" guestKey "|" guestNonce)`, sent in the join request before the challenge.
    public static func guestCommitment(guestKey: String, guestNonce: String) -> String {
        RoomSHA256.hex("jovra-room-commit|\(guestKey)|\(guestNonce)")
    }

    /// HMAC-SHA256 under the join token over `sessionId|inviteId|nonce|guestKeySha256|guestCommitment`. Binding the
    /// guest key and the commitment stops a captured proof being replayed by another device or with another commitment.
    public static func joinProof(token: String, sessionId: String, inviteId: String, nonce: String, guestKey: String,
                                 commitment: String) -> String {
        RoomSHA256.hmacHex(key: token, message: "\(sessionId)|\(inviteId)|\(nonce)|\(guestKey)|\(commitment)")
    }

    /// The six digits both screens show before the host approves. A comparison, never typed in as a secret.
    public static func verificationCode(hostKey: String, guestKey: String, qrNonce: String, hostNonce: String,
                                        guestNonce: String) -> String {
        let digest = RoomSHA256.digest(Array("jovra-room-sas|\(hostKey)|\(guestKey)|\(qrNonce)|\(hostNonce)|\(guestNonce)".utf8))
        let first32 = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let code = String(first32 % 1_000_000)
        return String(repeating: "0", count: 6 - code.count) + code
    }

    /// The host persists only this hash of the join token (`joinTokenSha256`).
    public static func tokenHash(_ token: String) -> String { RoomSHA256.hex(token) }

    /// A fresh 128-bit nonce as 22 unpadded base64url characters (the `nonce` pattern), from the system CSPRNG
    /// (`SystemRandomNumberGenerator`: arc4random on Apple platforms, getrandom on Linux).
    public static func randomNonce() -> String { randomBase64URL(byteCount: 16) }

    /// A fresh join token of `bits` (128 to 256, a multiple of 8) as unpadded base64url.
    public static func randomToken(bits: Int = 256) -> String {
        precondition((128...256).contains(bits) && bits % 8 == 0, "a join token has 128 to 256 bits")
        return randomBase64URL(byteCount: bits / 8)
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return Base64URL.encode((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// Unpadded base64url (RFC 4648 §5), strict on input: only the URL-safe alphabet, no padding, never a length that
/// leaves a single dangling character. As in the reference, unused trailing bits are ignored.
enum Base64URL {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    static func encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let chunk = Array(bytes[index..<min(index + 3, bytes.count)])
            let value = chunk.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32(16 - 8 * $1.offset) }
            for i in 0...chunk.count { out.append(alphabet[Int(value >> UInt32(18 - 6 * i) & 0x3f)]) }
            index += 3
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func decode(_ text: String) -> [UInt8]? {
        var values: [UInt8] = []
        for byte in text.utf8 {
            guard let index = alphabet.firstIndex(of: byte) else { return nil }
            values.append(UInt8(index))
        }
        guard values.count % 4 != 1 else { return nil }
        var out: [UInt8] = []
        var index = 0
        while index < values.count {
            let group = Array(values[index..<min(index + 4, values.count)])
            let value = group.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32(18 - 6 * $1.offset) }
            for i in 0..<(group.count - 1) { out.append(UInt8(truncatingIfNeeded: value >> UInt32(16 - 8 * i))) }
            index += 4
        }
        return out
    }
}
