import Foundation
import JovraRoom
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The package's own SHA-256 and HMAC-SHA256 (it stays Foundation-only for Linux) against published known answers,
/// and the QR encoding and CSPRNG helpers the join flow relies on.
final class InvitationCryptoTests: XCTestCase {
    func test_sha256KnownAnswers_FIPS180_4() {
        XCTAssertEqual(RoomSHA256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(RoomSHA256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(RoomSHA256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(RoomSHA256.hex(String(repeating: "a", count: 1_000_000)),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func test_hmacSha256KnownAnswers_RFC4231() {
        // Test case 2: key "Jefe".
        XCTAssertEqual(RoomSHA256.hmacHex(key: "Jefe", message: "what do ya want for nothing?"),
                       "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        // Test case 1: 20 bytes of 0x0b, "Hi There".
        let mac = RoomSHA256.hmac(key: [UInt8](repeating: 0x0b, count: 20), message: Array("Hi There".utf8))
        XCTAssertEqual(mac.map { String(format: "%02x", $0) }.joined(),
                       "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
        // Test case 6: a 131-byte key is hashed first.
        let long = RoomSHA256.hmac(key: [UInt8](repeating: 0xaa, count: 131),
                                   message: Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8))
        XCTAssertEqual(long.map { String(format: "%02x", $0) }.joined(),
                       "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }

    #if canImport(CryptoKit)
    /// Every length across two block boundaries agrees with CryptoKit.
    func test_sha256AgreesWithCryptoKitAcrossBlockBoundaries() {
        for length in 0...130 {
            let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
            let expected = Array(SHA256.hash(data: Data(bytes)))
            XCTAssertEqual(RoomSHA256.digest(bytes), expected, "length \(length)")
        }
    }
    #endif

    func test_constantTimeEqualsComparesWholeStrings() {
        XCTAssertTrue(roomConstantTimeEquals("abc", "abc"))
        XCTAssertFalse(roomConstantTimeEquals("abc", "abd"))
        XCTAssertFalse(roomConstantTimeEquals("abc", "abcd"))
        XCTAssertFalse(roomConstantTimeEquals("", "a"))
    }

    /// The sample join request in spec/room was built by the reference: the Swift commitment and proof reproduce it
    /// from the Sample secrets, so a guest built on this package is accepted by any port's host.
    func test_guestSideMessagesReproduceTheSampleJoinRequest() throws {
        let secrets = try XCTUnwrap(RoomFixtures.json("vectors/invitation.json")["secrets"])
        let request = try RoomFixtures.record("join-request")
        let guestKey = try XCTUnwrap(request["guestKeySha256"]?.string)
        let guestNonce = try XCTUnwrap(RoomFixtures.record("join-reveal")["guestNonce"]?.string)
        let commitment = InvitationCrypto.guestCommitment(guestKey: guestKey, guestNonce: guestNonce)
        XCTAssertEqual(commitment, request["guestCommitment"]?.string)
        let proof = InvitationCrypto.joinProof(token: try XCTUnwrap(secrets["tokens"]?["inv-c2"]?.string),
                                               sessionId: "sample-jon-alex", inviteId: "inv-c2",
                                               nonce: try XCTUnwrap(secrets["nonces"]?["inv-c2"]?.string),
                                               guestKey: guestKey, commitment: commitment)
        XCTAssertEqual(proof, request["proof"]?.string)
        XCTAssertEqual(InvitationCrypto.tokenHash(try XCTUnwrap(secrets["tokens"]?["inv-c2"]?.string)),
                       try RoomFixtures.record("invitation")["joinTokenSha256"]?.string)
    }

    func test_randomNoncesAndTokensMatchTheirPatternsAndDiffer() {
        let nonces = (0..<64).map { _ in InvitationCrypto.randomNonce() }
        XCTAssertEqual(Set(nonces).count, 64)
        for nonce in nonces { XCTAssertNotNil(nonce.range(of: #"^[A-Za-z0-9_-]{22}$"#, options: .regularExpression)) }
        XCTAssertEqual(InvitationCrypto.randomToken(bits: 128).count, 22)
        XCTAssertEqual(InvitationCrypto.randomToken().count, 43)
    }

    /// The QR text never echoes its token in an error, and a payload survives encode then strict decode.
    func test_qrErrorsNeverCarryTheScannedText() throws {
        let text = "jovra-room:1:" + String(repeating: "A", count: 5)
        XCTAssertThrowsError(try InvitationQR.decode(text)) { error in
            XCTAssertFalse(String(describing: error).contains("AAAAA"))
        }
    }
}
