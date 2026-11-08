import Foundation

/// A JSON number exactly as it was written. Studio contracts keep integers and decimals apart: `744` is an integer and
/// `744.0` is not, so an integral float can never stand in for a frame count, a time in microseconds or a revision.
public struct StudioJSONNumber: Hashable, Sendable, CustomStringConvertible {
    /// The token as written (RFC 8259 number grammar).
    public let text: String

    /// True when the token has neither a fraction nor an exponent.
    public var isIntegerToken: Bool { !text.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) }

    /// The value when it is an integer token that fits in an Int64.
    public var int64: Int64? { isIntegerToken ? Int64(text) : nil }

    /// The exact decimal value (Foundation Decimal holds 38 significant digits; longer tokens are refused by the parser).
    public var decimal: Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan }

    public var description: String { text }

    init(validated text: String) { self.text = text }
}

/// A parsed JSON document that keeps what Foundation's JSONSerialization loses: the order of object members and the
/// exact number tokens. Studio's strict decoder works on this tree.
public indirect enum StudioJSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(StudioJSONNumber)
    case string(String)
    case array([StudioJSONValue])
    case object([StudioJSONMember])

    /// The JSON Schema type name of this value. A number is `integer` only when written without fraction or exponent.
    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number(let n): n.isIntegerToken ? "integer" : "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    /// The member `key` of an object, or nil.
    public subscript(key: String) -> StudioJSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first(where: { $0.key == key })?.value
    }

    /// Compact JSON with object members in their stored order and numbers exactly as written (not canonical; use
    /// CanonicalJSON.canonicalize for that).
    public func serialized() -> Data {
        var out = ""
        write(to: &out)
        return Data(out.utf8)
    }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n.text
        case .string(let s): StudioJSONValue.quote(s, into: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(to: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, member) in members.enumerated() {
                if i > 0 { out += "," }
                StudioJSONValue.quote(member.key, into: &out)
                out += ":"
                member.value.write(to: &out)
            }
            out += "}"
        }
    }

    private static func quote(_ text: String, into out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0..<0x20:
                let hex = String(scalar.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

public struct StudioJSONMember: Hashable, Sendable {
    public let key: String
    public let value: StudioJSONValue

    public init(key: String, value: StudioJSONValue) {
        self.key = key
        self.value = value
    }
}

/// Strict RFC 8259 parsing: one value, no trailing bytes, no duplicate member names, no lone surrogates, numbers
/// that Decimal holds exactly, and nesting at most 512 deep.
public enum StudioJSONParser {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case malformed(offset: Int)
        case duplicateKey(String)
        case numberTooPrecise(String)
        case tooDeep

        public var description: String {
            switch self {
            case .malformed(let offset): "malformed JSON at byte \(offset)"
            case .duplicateKey(let key): "duplicate member name \"\(key)\""
            case .numberTooPrecise(let token): "number \(token) cannot be held exactly"
            case .tooDeep: "JSON nested deeper than 512 levels"
            }
        }
    }

    public static func parse(_ data: Data) throws -> StudioJSONValue {
        var reader = Reader(bytes: Array(data))
        let value = try reader.value(depth: 0)
        reader.skipWhitespace()
        guard reader.position == reader.bytes.count else { throw ParseError.malformed(offset: reader.position) }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0

        mutating func skipWhitespace() {
            while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) { position += 1 }
        }

        func fail() -> ParseError { .malformed(offset: position) }

        mutating func value(depth: Int) throws -> StudioJSONValue {
            guard depth < 512 else { throw ParseError.tooDeep }
            skipWhitespace()
            guard position < bytes.count else { throw fail() }
            switch bytes[position] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func literal(_ text: String) throws {
            let expected = Array(text.utf8)
            guard position + expected.count <= bytes.count, Array(bytes[position..<position + expected.count]) == expected
            else { throw fail() }
            position += expected.count
        }

        mutating func expect(_ byte: UInt8) -> Bool {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == byte else { return false }
            position += 1
            return true
        }

        mutating func object(depth: Int) throws -> StudioJSONValue {
            position += 1
            var members: [StudioJSONMember] = []
            var seen = Set<[UInt8]>()   // exact UTF-8 bytes: Unicode-equivalent but distinct names stay distinct
            if expect(UInt8(ascii: "}")) { return .object(members) }
            repeat {
                skipWhitespace()
                guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw fail() }
                let key = try string()
                guard seen.insert(Array(key.utf8)).inserted else { throw ParseError.duplicateKey(key) }
                guard expect(UInt8(ascii: ":")) else { throw fail() }
                members.append(StudioJSONMember(key: key, value: try value(depth: depth + 1)))
                if expect(UInt8(ascii: "}")) { return .object(members) }
            } while expect(UInt8(ascii: ","))
            throw fail()
        }

        mutating func array(depth: Int) throws -> StudioJSONValue {
            position += 1
            var items: [StudioJSONValue] = []
            if expect(UInt8(ascii: "]")) { return .array(items) }
            repeat {
                items.append(try value(depth: depth + 1))
                if expect(UInt8(ascii: "]")) { return .array(items) }
            } while expect(UInt8(ascii: ","))
            throw fail()
        }

        mutating func hex4() throws -> UInt32 {
            guard position + 4 <= bytes.count, let value = UInt32(String(decoding: bytes[position..<position + 4], as: UTF8.self), radix: 16)
            else { throw fail() }
            position += 4
            return value
        }

        mutating func string() throws -> String {
            position += 1  // opening quote
            var scalars = String.UnicodeScalarView()
            var run = position
            func flush(_ end: Int) throws {
                guard run < end else { return }
                guard let text = String(bytes: bytes[run..<end], encoding: .utf8) else { throw fail() }
                scalars.append(contentsOf: text.unicodeScalars)
            }
            while position < bytes.count {
                let byte = bytes[position]
                if byte == UInt8(ascii: "\"") {
                    try flush(position)
                    position += 1
                    return String(scalars)
                }
                if byte < 0x20 { throw fail() }
                guard byte == UInt8(ascii: "\\") else { position += 1; continue }
                try flush(position)
                position += 1
                guard position < bytes.count else { throw fail() }
                let escape = bytes[position]
                position += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800..<0xDC00).contains(code) {
                        guard position + 2 <= bytes.count, bytes[position] == UInt8(ascii: "\\"), bytes[position + 1] == UInt8(ascii: "u")
                        else { throw fail() }
                        position += 2
                        let low = try hex4()
                        guard (0xDC00..<0xE000).contains(low) else { throw fail() }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw fail() }  // a lone low surrogate
                    scalars.append(scalar)
                default: throw fail()
                }
                run = position
            }
            throw fail()
        }

        mutating func number() throws -> StudioJSONNumber {
            let start = position
            func digits() -> Int {
                let from = position
                while position < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[position]) { position += 1 }
                return position - from
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: "-") { position += 1 }
            guard position < bytes.count else { throw fail() }
            if bytes[position] == UInt8(ascii: "0") { position += 1 } else if digits() == 0 { throw fail() }
            if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
                position += 1
                guard digits() > 0 else { throw fail() }
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
                position += 1
                if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") { position += 1 }
                guard digits() > 0 else { throw fail() }
            }
            let token = String(decoding: bytes[start..<position], as: UTF8.self)
            let significant = token.drop(while: { $0 == "-" }).prefix(while: { $0 != "e" && $0 != "E" })
                .filter { $0 != "." }.drop(while: { $0 == "0" })
            guard significant.count <= 38 else { throw ParseError.numberTooPrecise(token) }
            return StudioJSONNumber(validated: token)
        }
    }
}
