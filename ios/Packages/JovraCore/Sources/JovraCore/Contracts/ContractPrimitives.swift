import Foundation

/// An explicit JSON null, distinct from an absent optional property.
public enum ContractNullable<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case null
    case value(Value)
    public var value: Value? { if case .value(let value) = self { value } else { nil } }
    public init(_ value: Value?) { self = value.map(Self.value) ?? .null }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .null : .value(try container.decode(Value.self))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .null: try container.encodeNil(); case .value(let value): try container.encode(value) }
    }
}

public struct SchemaVersion: Codable, Equatable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let rawValue: String
    public static let v1 = SchemaVersion(major: 1, minor: 0, patch: 0)
    public static let v1_1 = SchemaVersion(major: 1, minor: 1, patch: 0)
    public static let v1_2 = SchemaVersion(major: 1, minor: 2, patch: 0)
    /// Current session document schema; other document kinds retain their own versions.
    public static let current = v1_2
    private init(major: Int, minor: Int, patch: Int) {
        self.major = major; self.minor = minor; self.patch = patch
        self.rawValue = "\(major).\(minor).\(patch)"
    }
    public init(_ text: String) throws {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else {
            throw ContractError.invalidSchemaVersion(text)
        }
        guard major == 1 else { throw ContractError.unsupportedSchemaMajor(major) }
        self.major = major; self.minor = minor; self.patch = patch; self.rawValue = text
    }
    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}

public struct MediaTime: Codable, Equatable, Hashable, Sendable {
    public var value: Int64
    public var timescale: Int32
    public init(value: Int64, timescale: Int32) throws {
        guard value >= 0, timescale > 0 else { throw ContractError.invalidMediaTime }
        self.value = value; self.timescale = timescale
    }
    private enum CodingKeys: String, CodingKey { case value, timescale }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(value: container.decode(Int64.self, forKey: .value), timescale: container.decode(Int32.self, forKey: .timescale))
    }
}

/// Only the scalar alternatives allowed by session.derivedValue.value, never a document escape hatch.
public enum ScalarValue: Codable, Equatable, Sendable {
    case text(String), integer(Int), decimal(Decimal), boolean(Bool)
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(String.self) { self = .text(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else { self = .decimal(try container.decode(Decimal.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .decimal(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }
}

/// The benchmark schema explicitly leaves capability output items unconstrained. This value is
/// scoped to that one field; session and other persisted documents retain typed model properties.
public enum BenchmarkOutputValue: Codable, Equatable, Sendable {
    case null, text(String), integer(Int), decimal(Decimal), boolean(Bool)
    case array([BenchmarkOutputValue]), object([String: BenchmarkOutputValue])
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(String.self) { self = .text(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode([BenchmarkOutputValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: BenchmarkOutputValue].self) { self = .object(value) }
        else { self = .decimal(try container.decode(Decimal.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .text(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .decimal(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
