import Foundation
import JovraCore

/// A test-only JSON value: fixtures are read in place and patched (spec/room/reference/jovra_room/core.py
/// `apply_patch`) before being handed to the package's strict decoders as bytes. The package itself never decodes
/// into an untyped JSON value.
enum JSONValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    static func parse(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }

    /// Canonical bytes (sorted keys, no whitespace), the form handed to the package decoders.
    func data() throws -> Data { try CanonicalJSON.encode(self) }

    var description: String { (try? data()).map { String(decoding: $0, as: UTF8.self) } ?? "<unencodable>" }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var int: Int? { if case .int(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var isNull: Bool { self == .null }

    /// Decodes a JSON value into a typed vector input (plain Codable, not a contract record).
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: data()) }
}

enum JSONPatchError: Error, CustomStringConvertible {
    case badPointer(String), missing(String), unsupported(String)
    var description: String {
        switch self {
        case .badPointer(let path): "bad JSON pointer \(path)"
        case .missing(let path): "patch target missing at \(path)"
        case .unsupported(let op): "unsupported patch op \(op)"
        }
    }
}

/// The JSON-patch subset of spec/room/reference/jovra_room/core.py: replace, add (object key or list index/'-'),
/// remove. Applied to a copy.
enum JSONPatch {
    static func apply(_ patch: JSONValue, to document: JSONValue) throws -> JSONValue {
        guard let ops = patch.array else { throw JSONPatchError.unsupported("patch is not an array") }
        var doc = document
        for op in ops {
            guard let kind = op["op"]?.string, let path = op["path"]?.string else {
                throw JSONPatchError.unsupported("\(op)")
            }
            let tokens = try pointer(path)
            guard !tokens.isEmpty else { throw JSONPatchError.badPointer(path) }
            doc = try apply(kind, tokens[...], op["value"], path, to: doc)
        }
        return doc
    }

    private static func pointer(_ path: String) throws -> [String] {
        if path.isEmpty { return [] }
        guard path.hasPrefix("/") else { throw JSONPatchError.badPointer(path) }
        return path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    private static func apply(_ kind: String, _ tokens: ArraySlice<String>, _ value: JSONValue?, _ path: String,
                              to node: JSONValue) throws -> JSONValue {
        let head = tokens.first!
        if tokens.count > 1 {
            switch node {
            case .object(var object):
                guard let child = object[head] else { throw JSONPatchError.missing(path) }
                object[head] = try apply(kind, tokens.dropFirst(), value, path, to: child)
                return .object(object)
            case .array(var array):
                guard let index = Int(head), array.indices.contains(index) else { throw JSONPatchError.missing(path) }
                array[index] = try apply(kind, tokens.dropFirst(), value, path, to: array[index])
                return .array(array)
            default: throw JSONPatchError.missing(path)
            }
        }
        switch (kind, node) {
        case ("replace", .object(var object)):
            guard object[head] != nil, let value else { throw JSONPatchError.missing(path) }
            object[head] = value
            return .object(object)
        case ("replace", .array(var array)):
            guard let index = Int(head), array.indices.contains(index), let value else {
                throw JSONPatchError.missing(path)
            }
            array[index] = value
            return .array(array)
        case ("add", .object(var object)):
            guard let value else { throw JSONPatchError.missing(path) }
            object[head] = value
            return .object(object)
        case ("add", .array(var array)):
            guard let value else { throw JSONPatchError.missing(path) }
            if head == "-" { array.append(value) }
            else if let index = Int(head), index <= array.count { array.insert(value, at: index) }
            else { throw JSONPatchError.missing(path) }
            return .array(array)
        case ("remove", .object(var object)):
            guard object.removeValue(forKey: head) != nil else { throw JSONPatchError.missing(path) }
            return .object(object)
        case ("remove", .array(var array)):
            guard let index = Int(head), array.indices.contains(index) else { throw JSONPatchError.missing(path) }
            array.remove(at: index)
            return .array(array)
        default:
            throw JSONPatchError.unsupported(kind)
        }
    }
}
