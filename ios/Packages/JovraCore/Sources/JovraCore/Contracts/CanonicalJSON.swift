import Foundation

public enum ContractError: Error, Equatable, Sendable {
    case unsupportedSchemaMajor(Int)
    case invalidSchemaVersion(String)
    case malformedJSON
    case duplicateJSONKey(String)
    case numericPrecisionExceeded(String)
    case invalidMediaTime
    case documentWouldLoseData
}

/// Sorted compact UTF-8 JSON (ADR-0029). Number tokens are normalized as exact decimal text;
/// they never pass through binary floating point. Source fixture whitespace is not canonical.
public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try canonicalize(encoder.encode(value))
    }

    public static func canonicalize(_ data: Data) throws -> Data {
        var parser = CanonicalParser(bytes: Array(data))
        let result = try parser.value()
        parser.whitespace()
        guard parser.position == parser.bytes.count else { throw ContractError.malformedJSON }
        return Data(result.utf8)
    }
}

public enum ContractCodec {
    public static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        // Also refuses duplicate keys; JSONDecoder alone silently keeps one of them.
        var parser = CanonicalParser(bytes: Array(data), requireRepresentableDecimal: true)
        let canonical = Data(try parser.value().utf8)
        parser.whitespace()
        guard parser.position == parser.bytes.count else { throw ContractError.malformedJSON }
        let decoded = try JSONDecoder().decode(type, from: canonical)
        guard try CanonicalJSON.encode(decoded) == canonical else { throw ContractError.documentWouldLoseData }
        return decoded
    }
}

private struct CanonicalParser {
    let bytes: [UInt8]
    var position = 0
    var depth = 0
    var requireRepresentableDecimal = false

    mutating func whitespace() {
        while position < bytes.count, [9, 10, 13, 32].contains(bytes[position]) { position += 1 }
    }

    mutating func value() throws -> String {
        whitespace()
        guard position < bytes.count, depth < 512 else { throw ContractError.malformedJSON }
        depth += 1
        defer { depth -= 1 }
        switch bytes[position] {
        case 123: return try object()
        case 91: return try array()
        case 34: return escape(try string())
        case 116: return try literal("true")
        case 102: return try literal("false")
        case 110: return try literal("null")
        default: return try number()
        }
    }

    mutating func take(_ byte: UInt8) -> Bool {
        whitespace()
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    mutating func literal(_ text: String) throws -> String {
        let expected = Array(text.utf8)
        guard position + expected.count <= bytes.count,
              Array(bytes[position..<position + expected.count]) == expected else {
            throw ContractError.malformedJSON
        }
        position += expected.count
        return text
    }

    mutating func string() throws -> String {
        guard take(34) else { throw ContractError.malformedJSON }
        let start = position - 1
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == 92 {
                guard position < bytes.count else { throw ContractError.malformedJSON }
                position += 1
            } else if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position])) }
                catch { throw ContractError.malformedJSON }
            } else if byte < 32 { throw ContractError.malformedJSON }
        }
        throw ContractError.malformedJSON
    }

    mutating func object() throws -> String {
        position += 1
        if take(125) { return "{}" }
        var properties: [(String, [UInt8], String)] = []
        var keys = Set<Data>() // Unicode normalization must not conflate distinct JSON key bytes.
        repeat {
            let key = try string()
            let utf8 = Array(key.utf8)
            guard keys.insert(Data(utf8)).inserted else { throw ContractError.duplicateJSONKey(key) }
            guard take(58) else { throw ContractError.malformedJSON }
            properties.append((key, utf8, try value()))
            if take(125) { break }
            guard take(44) else { throw ContractError.malformedJSON }
        } while true
        properties.sort { $0.1.lexicographicallyPrecedes($1.1) }
        return "{" + properties.map { escape($0.0) + ":" + $0.2 }.joined(separator: ",") + "}"
    }

    mutating func array() throws -> String {
        position += 1
        if take(93) { return "[]" }
        var items: [String] = []
        repeat {
            items.append(try value())
            if take(93) { break }
            guard take(44) else { throw ContractError.malformedJSON }
        } while true
        return "[" + items.joined(separator: ",") + "]"
    }

    mutating func number() throws -> String {
        let start = position
        while position < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[position]) {
            position += 1
        }
        let token = String(decoding: bytes[start..<position], as: UTF8.self)
        guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#,
                          options: .regularExpression) != nil else { throw ContractError.malformedJSON }
        let normalized = try normalizeNumber(token)
        if requireRepresentableDecimal {
            guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
                  !decimal.isNaN,
                  try normalizeNumber(NSDecimalNumber(decimal: decimal).stringValue) == normalized else {
                throw ContractError.numericPrecisionExceeded(token)
            }
        }
        return normalized
    }
}

private func normalizeNumber(_ token: String) throws -> String {
    let negative = token.hasPrefix("-")
    let unsigned = negative ? String(token.dropFirst()) : token
    let parts = unsigned.lowercased().split(separator: "e", omittingEmptySubsequences: false)
    let exponent = parts.count == 2 ? Int(parts[1]) : 0
    guard let exponent, exponent >= -10000, exponent <= 10000 else { throw ContractError.numericPrecisionExceeded(token) }
    let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    var digits = String(mantissa[0]) + (mantissa.count == 2 ? String(mantissa[1]) : "")
    var decimalIndex = mantissa[0].count + exponent
    while digits.hasPrefix("0"), digits.count > 1 { digits.removeFirst(); decimalIndex -= 1 }
    if digits.allSatisfy({ $0 == "0" }) { return "0" }
    let body: String
    if decimalIndex <= 0 { body = "0." + String(repeating: "0", count: -decimalIndex) + digits }
    else if decimalIndex >= digits.count { body = digits + String(repeating: "0", count: decimalIndex - digits.count) }
    else {
        let split = digits.index(digits.startIndex, offsetBy: decimalIndex)
        body = String(digits[..<split]) + "." + String(digits[split...])
    }
    var result = body
    if result.contains(".") {
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
    }
    return (negative ? "-" : "") + result
}

private func escape(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 34: result += "\\\""
        case 92: result += "\\\\"
        case 8: result += "\\b"
        case 12: result += "\\f"
        case 10: result += "\\n"
        case 13: result += "\\r"
        case 9: result += "\\t"
        case 0..<32: result += String(format: "\\u%04x", scalar.value)
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}
