/// SHA-256 (FIPS 180-4) and HMAC-SHA256 (RFC 2104) in plain Swift. JovraRoom must build and test on Linux with
/// Foundation only, so it cannot use CryptoKit, and it does not take a package dependency for two digests. The
/// known-answer tests (NIST FIPS 180-4 examples, RFC 4231) and, on Apple platforms, a CryptoKit cross-check pin it.
/// These digests authenticate join proofs and fingerprint commands; they are never used to store a secret at rest.
public enum RoomSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// The 32-byte digest of `message`.
    public static func digest<Bytes: Sequence>(_ message: Bytes) -> [UInt8] where Bytes.Element == UInt8 {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var data = Array(message)
        let bitLength = UInt64(data.count) &* 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }

        var w = [UInt32](repeating: 0, count: 64)
        for block in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let j = block + i * 4
                w[i] = UInt32(data[j]) << 24 | UInt32(data[j + 1]) << 16 | UInt32(data[j + 2]) << 8 | UInt32(data[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let choose = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ choose &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ majority
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> UInt32(24 - $0 * 8)) } }
    }

    /// Lower-case hex of the digest of the UTF-8 bytes of `text`.
    public static func hex(_ text: String) -> String { hexString(digest(Array(text.utf8))) }

    /// HMAC-SHA256 of `message` under `key`.
    public static func hmac(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var block = key.count > 64 ? digest(key) : key
        block += [UInt8](repeating: 0, count: 64 - block.count)
        let inner = digest(block.map { $0 ^ 0x36 } + message)
        return digest(block.map { $0 ^ 0x5c } + inner)
    }

    /// Lower-case hex of HMAC-SHA256 over UTF-8 key and message text.
    public static func hmacHex(key: String, message: String) -> String {
        hexString(hmac(key: Array(key.utf8), message: Array(message.utf8)))
    }

    static func hexString(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}

/// Compares two secrets (proofs, commitments, key fingerprints) without an early exit, so the time taken does not
/// reveal how many leading bytes matched (Python `hmac.compare_digest`). Unequal lengths are unequal.
public func roomConstantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8), b = Array(rhs.utf8)
    var difference = UInt8(a.count == b.count ? 0 : 1)
    for i in 0..<max(a.count, b.count) {
        difference |= (i < a.count ? a[i] : 0) ^ (i < b.count ? b[i] : 0)
    }
    return difference == 0
}
