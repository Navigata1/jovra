/// Where a client may connect (invitation.py `check_endpoint` / `check_resolved_endpoint`): an IP literal on a
/// private or link-local LAN (RFC 1918, IPv4 link-local, IPv6 unique-local and link-local), port 1024-65535. Never
/// loopback, CGNAT, multicast or a public address. The TLS pin still authenticates the host; this list limits where
/// a client connects.
public enum EndpointAllowList {
    public static func allows(address: String, port: Int) -> Bool {
        guard (1024...65535).contains(port), let bytes = IPAddressLiteral.parse(address) else { return false }
        if bytes.count == 4 {
            let (a, b) = (bytes[0], bytes[1])
            return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        return bytes[0] & 0xFE == 0xFC || (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80)
    }
}

/// A strict IP literal parser with Python `ipaddress` semantics for the forms the schema admits: dotted-quad IPv4
/// (no leading zeros, each octet 0-255) and colon-hex IPv6 (one `::` at most, 1-4 hex digits per group).
enum IPAddressLiteral {
    static func parse(_ text: String) -> [UInt8]? {
        text.contains(":") ? ipv6(text) : ipv4(text)
    }

    private static func ipv4(_ text: String) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard (1...3).contains(part.count), part.allSatisfy(\.isASCIIDigitCharacter),
                  part.count == 1 || part.first != "0", let value = Int(part), value <= 255 else { return nil }
            bytes.append(UInt8(value))
        }
        return bytes
    }

    private static func ipv6(_ text: String) -> [UInt8]? {
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        func groups(_ s: String) -> [UInt16]? {
            if s.isEmpty { return [] }
            var out: [UInt16] = []
            for g in s.split(separator: ":", omittingEmptySubsequences: false) {
                guard (1...4).contains(g.count), let value = UInt16(g, radix: 16) else { return nil }
                out.append(value)
            }
            return out
        }
        guard let head = groups(halves[0]) else { return nil }
        var all = head
        if halves.count == 2 {
            guard let tail = groups(halves[1]), head.count + tail.count <= 7 else { return nil }
            all += Array(repeating: 0, count: 8 - head.count - tail.count) + tail
        }
        guard all.count == 8 else { return nil }
        return all.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }
}

private extension Character {
    var isASCIIDigitCharacter: Bool { ("0"..."9").contains(self) }
}
