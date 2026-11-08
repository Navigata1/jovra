import Foundation

/// Why bytes were refused before any record rule ran: the schema layer of spec/room (61 invalid cases) plus
/// malformed JSON, duplicate keys and unknown record kinds.
public enum RoomDecodingError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Not one JSON document, a duplicate key, or a number that cannot be represented exactly.
    case malformed(String)
    /// No `schemaVersion`, or one that is not a jovra.room.*/1 record.
    case unknownSchemaVersion(String)
    /// The document breaks its schema: the JSON pointer of the offending value and why.
    case schema(path: String, reason: String)

    public var description: String {
        switch self {
        case .malformed(let detail): "malformed: \(detail)"
        case .unknownSchemaVersion(let version): "unknown schemaVersion \(version)"
        case .schema(let path, let reason): "schema \(path): \(reason)"
        }
    }
}

/// The lexical rules of spec/room/schemas/room-common.schema.json and the record schemas. Patterns are anchored as
/// in ECMA-262 (no trailing newline is accepted) and counted in Unicode scalars, as the reference validator counts.
enum LexicalRule: Sendable {
    case id, sha256, secretToken, nonce, dateTime, displayCode, userText, decimal
    case capabilityId, modelVersion, dnssdInstanceName, addressLiteral, ssid, passphrase

    func accepts(_ text: String) -> Bool {
        let s = Array(text.unicodeScalars)
        switch self {
        case .id: // ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$
            return (1...64).contains(s.count) && s[0].isASCIIAlphanumeric && s.dropFirst().allSatisfy(\.isIdTail)
        case .sha256: // ^[0-9a-f]{64}$
            return s.count == 64 && s.allSatisfy(\.isLowerHex)
        case .secretToken: // ^[A-Za-z0-9_-]{22,43}$
            return (22...43).contains(s.count) && s.allSatisfy(\.isBase64URL)
        case .nonce: // ^[A-Za-z0-9_-]{22}$
            return s.count == 22 && s.allSatisfy(\.isBase64URL)
        case .dateTime:
            return RoomTimestamp(text) != nil
        case .displayCode: // ^JVR-[0-9]{3}$
            return s.count == 7 && text.hasPrefix("JVR-") && s.dropFirst(4).allSatisfy(\.isASCIIDigit)
        case .userText: // ^[^\u0000-\u001f\u007f]{1,80}$
            return (1...80).contains(s.count) && s.allSatisfy { !$0.isControl }
        case .decimal: // ^(0|[1-9][0-9]{0,5})(\.[0-9]{1,3})?$
            let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let whole = Array(parts[0].unicodeScalars)
            guard !whole.isEmpty, whole.count <= 6, whole.allSatisfy(\.isASCIIDigit),
                  whole.count == 1 || whole[0] != "0" else { return false }
            guard parts.count == 2 else { return true }
            let fraction = Array(parts[1].unicodeScalars)
            return (1...3).contains(fraction.count) && fraction.allSatisfy(\.isASCIIDigit)
        case .capabilityId: // ^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)*$
            return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
                let p = Array(part.unicodeScalars)
                return !p.isEmpty && ("a"..."z").contains(p[0]) && p.allSatisfy(\.isASCIIAlphanumeric)
            }
        case .modelVersion: // ^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$
            return (1...64).contains(s.count) && s[0].isASCIIAlphanumeric
                && s.dropFirst().allSatisfy { $0.isASCIIAlphanumeric || "._/-".unicodeScalars.contains($0) }
        case .dnssdInstanceName: // ^[A-Za-z0-9][A-Za-z0-9 _-]{0,62}$
            return (1...63).contains(s.count) && s[0].isASCIIAlphanumeric
                && s.dropFirst().allSatisfy { $0.isASCIIAlphanumeric || " _-".unicodeScalars.contains($0) }
        case .addressLiteral: // ^([0-9]{1,3}(\.[0-9]{1,3}){3}|[0-9A-Fa-f:]{2,39})$
            let groups = text.split(separator: ".", omittingEmptySubsequences: false)
            if groups.count == 4, groups.allSatisfy({ (1...3).contains($0.count) && $0.unicodeScalars.allSatisfy(\.isASCIIDigit) }) {
                return true
            }
            return (2...39).contains(s.count) && s.allSatisfy { $0.isHex || $0 == ":" }
        case .ssid: // ^[^\u0000-\u001f\u007f]{1,32}$
            return (1...32).contains(s.count) && s.allSatisfy { !$0.isControl }
        case .passphrase: // ^[ -~]{8,63}$
            return (8...63).contains(s.count) && s.allSatisfy { (0x20...0x7e).contains($0.value) }
        }
    }
}

extension Unicode.Scalar {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
    var isASCIIAlphanumeric: Bool { isASCIIDigit || ("a"..."z").contains(self) || ("A"..."Z").contains(self) }
    var isIdTail: Bool { isASCIIAlphanumeric || self == "_" || self == "-" }
    var isBase64URL: Bool { isIdTail }
    var isLowerHex: Bool { isASCIIDigit || ("a"..."f").contains(self) }
    var isHex: Bool { isLowerHex || ("A"..."F").contains(self) }
    var isControl: Bool { value < 0x20 || value == 0x7f }
}

/// Any JSON object key, used to refuse properties a schema does not list (`additionalProperties: false`).
struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(_ string: String) { stringValue = string; intValue = nil }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

func jsonPointer(_ codingPath: [CodingKey], _ key: CodingKey? = nil) -> String {
    let keys = codingPath + (key.map { [$0] } ?? [])
    return "/" + keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: "/")
}

extension Decoder {
    /// A keyed container that refuses any property outside `Keys` (the schema's `additionalProperties: false`).
    func strictContainer<Keys: CodingKey & CaseIterable>(_ keys: Keys.Type) throws -> KeyedDecodingContainer<Keys> {
        let all = try container(keyedBy: AnyCodingKey.self)
        let allowed = Set(Keys.allCases.map(\.stringValue))
        if let extra = all.allKeys.map(\.stringValue).sorted().first(where: { !allowed.contains($0) }) {
            throw RoomDecodingError.schema(path: jsonPointer(codingPath, AnyCodingKey(extra)),
                                           reason: "property not allowed")
        }
        return try container(keyedBy: Keys.self)
    }

    func schemaError(_ reason: String) -> RoomDecodingError {
        .schema(path: jsonPointer(codingPath), reason: reason)
    }
}

/// Integer bounds from room-common.schema.json.
enum Bound {
    static let seq = 0...Int.max
    static let revision = 0...Int.max
    static let hostEpoch = 1...Int.max
    static let durationMs = 0...172_800_000
}

extension KeyedDecodingContainer {
    func schemaError(_ key: Key, _ reason: String) -> RoomDecodingError {
        .schema(path: jsonPointer(codingPath, key), reason: reason)
    }

    /// Required and not null.
    func required<T: Decodable>(_ type: T.Type = T.self, _ key: Key) throws -> T {
        guard contains(key) else { throw schemaError(key, "required property missing") }
        guard try !decodeNil(forKey: key) else { throw schemaError(key, "null not allowed") }
        return try decode(T.self, forKey: key)
    }

    /// Required; null allowed (`oneOf: [{type: null}, ...]`).
    func nullable<T: Decodable>(_ type: T.Type = T.self, _ key: Key) throws -> T? {
        guard contains(key) else { throw schemaError(key, "required property missing") }
        return try decodeNil(forKey: key) ? nil : decode(T.self, forKey: key)
    }

    /// May be absent; when present it is not null.
    func optional<T: Decodable>(_ type: T.Type = T.self, _ key: Key) throws -> T? {
        guard contains(key) else { return nil }
        guard try !decodeNil(forKey: key) else { throw schemaError(key, "null not allowed") }
        return try decode(T.self, forKey: key)
    }

    func text(_ key: Key, _ rule: LexicalRule) throws -> String {
        try checked(required(String.self, key), key, rule)
    }

    func nullableText(_ key: Key, _ rule: LexicalRule) throws -> String? {
        try nullable(String.self, key).map { try checked($0, key, rule) }
    }

    func optionalText(_ key: Key, _ rule: LexicalRule) throws -> String? {
        try optional(String.self, key).map { try checked($0, key, rule) }
    }

    func int(_ key: Key, _ bounds: ClosedRange<Int>) throws -> Int {
        try checked(required(Int.self, key), key, bounds)
    }

    func nullableInt(_ key: Key, _ bounds: ClosedRange<Int>) throws -> Int? {
        try nullable(Int.self, key).map { try checked($0, key, bounds) }
    }

    func optionalInt(_ key: Key, _ bounds: ClosedRange<Int>) throws -> Int? {
        try optional(Int.self, key).map { try checked($0, key, bounds) }
    }

    /// A `const` property that must be present.
    func constant<T: Decodable & Equatable>(_ key: Key, _ value: T) throws {
        guard try required(T.self, key) == value else { throw schemaError(key, "must be \(value)") }
    }

    /// An optional `const` property: absent, or exactly `value`.
    func optionalConstant<T: Decodable & Equatable>(_ key: Key, _ value: T) throws -> Bool {
        guard let found = try optional(T.self, key) else { return false }
        guard found == value else { throw schemaError(key, "must be \(value)") }
        return true
    }

    /// An array of ids with item, count and uniqueness constraints.
    func ids(_ key: Key, count: ClosedRange<Int>, unique: Bool) throws -> [String] {
        let values = try array(String.self, key, count: count, unique: unique)
        for value in values where !LexicalRule.id.accepts(value) { throw schemaError(key, "item is not an id") }
        return values
    }

    func array<T: Decodable & Hashable>(_ type: T.Type, _ key: Key, count: ClosedRange<Int>, unique: Bool) throws -> [T] {
        let values = try required([T].self, key)
        guard count.contains(values.count) else { throw schemaError(key, "item count \(values.count) outside \(count)") }
        if unique, Set(values).count != values.count { throw schemaError(key, "items must be unique") }
        return values
    }

    func objects<T: Decodable>(_ type: T.Type, _ key: Key, count: ClosedRange<Int>) throws -> [T] {
        let values = try required([T].self, key)
        guard count.contains(values.count) else { throw schemaError(key, "item count \(values.count) outside \(count)") }
        return values
    }

    /// A required enum narrowed by the schema to a subset of its cases (`enum: ["camera", "none"]`).
    func required<T: Decodable & Equatable>(_ type: T.Type, _ key: Key, in allowed: [T]) throws -> T {
        let value = try required(T.self, key)
        guard allowed.contains(value) else { throw schemaError(key, "value not allowed here") }
        return value
    }

    /// An array of closed-vocabulary values with count and uniqueness constraints.
    func values<T: Decodable & Hashable>(_ type: T.Type, _ key: Key, count: ClosedRange<Int>) throws -> [T] {
        try array(T.self, key, count: count, unique: true)
    }

    private func checked(_ value: String, _ key: Key, _ rule: LexicalRule) throws -> String {
        guard rule.accepts(value) else { throw schemaError(key, "does not match the \(rule) pattern") }
        return value
    }

    private func checked(_ value: Int, _ key: Key, _ bounds: ClosedRange<Int>) throws -> Int {
        guard bounds.contains(value) else { throw schemaError(key, "\(value) outside \(bounds)") }
        return value
    }
}

extension KeyedEncodingContainer {
    /// Writes an explicit JSON null for nil (a required, nullable property).
    mutating func encodeNullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}
