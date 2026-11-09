import Foundation

/// An object of a plan after `fields` has checked its member names, so every named member is present.
struct EDLObject: Sendable {
    let members: [String: StudioJSONValue]

    subscript(key: String) -> StudioJSONValue { members[key] ?? .null }
}

/// The reference's small strict helpers (`edl.py`, "small strict helpers"), on the strict JSON tree so number tokens,
/// booleans and nulls keep the meaning Python gives them: an integer is an integer token (never a boolean and never
/// `744.0`), a boolean is only `true`/`false`, and an absent member is different from `null`.
enum EDLJSON {
    /// The port reads integers up to 2^53 - 1 in magnitude (the JSON interoperable range, and far beyond any frame,
    /// microsecond or revision a plan can carry). Python reads any size; a larger token is `badInteger` here, so the
    /// arithmetic on plan integers can never overflow.
    static let maxExactInteger = 9_007_199_254_740_991

    static func object(_ value: StudioJSONValue) -> [StudioJSONMember]? {
        if case .object(let members) = value { return members }
        return nil
    }

    static func array(_ value: StudioJSONValue) -> [StudioJSONValue]? {
        if case .array(let items) = value { return items }
        return nil
    }

    static func string(_ value: StudioJSONValue) -> String? {
        if case .string(let s) = value { return s }
        return nil
    }

    /// Python's `type(value) is int`: an integer token (booleans are not integers here).
    static func exactInt(_ value: StudioJSONValue) -> Int? {
        guard case .number(let n) = value, let v = n.int64, abs(v) <= Int64(maxExactInteger) else { return nil }
        return Int(v)
    }

    /// `edl.fields`: an object with exactly these member names (unknown names are reported before missing ones).
    static func fields(_ value: StudioJSONValue, _ names: String, _ label: String) throws -> EDLObject {
        guard let members = object(value) else { throw EDLFinding(.notObject, "\(label) must be an object") }
        let want = Set(names.split(separator: " ").map(String.init))
        let have = Set(members.map(\.key))
        try require(have.subtracting(want).isEmpty, .unknownField, "\(label): unknown field(s) \(have.subtracting(want).sorted())")
        try require(want.subtracting(have).isEmpty, .missingField, "\(label): missing field(s) \(want.subtracting(have).sorted())")
        return EDLObject(members: Dictionary(members.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first }))
    }

    static func integer(_ value: StudioJSONValue, _ label: String, minimum: Int = 0) throws -> Int {
        guard let v = exactInt(value), v >= minimum else {
            throw EDLFinding(.badInteger, "\(label) must be an integer >= \(minimum)")
        }
        return v
    }

    static func boolean(_ value: StudioJSONValue) -> Bool? {
        if case .bool(let b) = value { return b }
        return nil
    }

    static func identifier(_ value: StudioJSONValue, _ label: String) throws -> String {
        guard let s = string(value), isIdentifier(s) else { throw EDLFinding(.badIdentifier, "\(label): invalid id") }
        return s
    }

    static func template(_ value: StudioJSONValue, _ label: String, prefix: String = "") throws -> String {
        guard let s = string(value), isTemplate(s), s.hasPrefix(prefix) else {
            throw EDLFinding(.badTemplate, "\(label): invalid template id")
        }
        return s
    }

    /// `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`, matched in full.
    static func isIdentifier(_ s: String) -> Bool {
        let scalars = Array(s.unicodeScalars)
        guard (1...64).contains(scalars.count), isAlnum(scalars[0]) else { return false }
        return scalars.dropFirst().allSatisfy { isAlnum($0) || $0 == "_" || $0 == "-" }
    }

    /// `[a-z][a-z0-9-]{0,31}(\.[a-z0-9][a-z0-9-]{0,31}){0,3}`, matched in full.
    static func isTemplate(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return false }
        for (i, part) in parts.enumerated() {
            let scalars = Array(part.unicodeScalars)
            guard (1...32).contains(scalars.count) else { return false }
            let first = scalars[0]
            guard i == 0 ? isLower(first) : (isLower(first) || isDigit(first)) else { return false }
            guard scalars.dropFirst().allSatisfy({ isLower($0) || isDigit($0) || $0 == "-" }) else { return false }
        }
        return true
    }

    /// 64 lowercase hex digits.
    static func isHex64(_ value: StudioJSONValue) -> Bool {
        guard let s = string(value) else { return false }
        let scalars = Array(s.unicodeScalars)
        return scalars.count == 64 && scalars.allSatisfy { isDigit($0) || ("a"..."f").contains($0) }
    }

    private static func isAlnum(_ c: Unicode.Scalar) -> Bool { isLower(c) || isDigit(c) || ("A"..."Z").contains(c) }
    private static func isLower(_ c: Unicode.Scalar) -> Bool { ("a"..."z").contains(c) }
    private static func isDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }

    /// Python's `str(value)` for the scalar values a plan can carry, used where the reference matches an id pattern
    /// against `str(...)` (`keeperId`). Containers and decimals never match an id, so they give nil.
    static func pythonText(_ value: StudioJSONValue) -> String? {
        switch value {
        case .string(let s): s
        case .bool(let b): b ? "True" : "False"
        case .number(let n): n.isIntegerToken ? n.text : nil
        default: nil
        }
    }

    /// Python `==` on JSON values: numbers compare by value (`1 == 1.0`), objects by their member sets, arrays in
    /// order. A boolean is never equal to a number here (the reference never relies on `True == 1`).
    static func pythonEquals(_ a: StudioJSONValue, _ b: StudioJSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        case (.number(let x), .number(let y)): return x.text == y.text || x.decimal == y.decimal
        case (.array(let x), .array(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { pythonEquals($0, $1) }
        case (.object(let x), .object(let y)):
            guard x.count == y.count else { return false }
            let lookup = Dictionary(y.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            return x.allSatisfy { member in lookup[member.key].map { pythonEquals(member.value, $0) } ?? false }
        default: return false
        }
    }

    /// `value == n` for an integer `n`.
    static func equals(_ value: StudioJSONValue, _ n: Int) -> Bool {
        pythonEquals(value, .number(StudioJSONNumber(validated: String(n))))
    }

    static let forbiddenKeys: Set<String> = [
        "command", "cmd", "shell", "script", "path", "localpath", "file", "url", "uri", "href", "endpoint", "secret",
        "token", "apikey", "password", "credential", "signedurl", "filter", "filtergraph", "approved", "paid",
        "renderallowed", "price", "amount", "cost",
    ]

    /// Defense in depth: executable, location, credential and spend fields are refused by name anywhere, and values
    /// that look like a path or URL are refused.
    static func scanForbidden(_ value: StudioJSONValue, at path: String = "$") throws {
        switch value {
        case .object(let members):
            for member in members {
                try require(!forbiddenKeys.contains(member.key.lowercased()), .forbiddenField,
                            "\(path).\(member.key) is never allowed in an EDL")
                try scanForbidden(member.value, at: "\(path).\(member.key)")
            }
        case .array(let items):
            for (i, item) in items.enumerated() { try scanForbidden(item, at: "\(path)[\(i)]") }
        case .string(let s):
            let looksLikeLocation = s.contains("://") || s.hasPrefix("/") || s.hasPrefix("~") || s.hasPrefix("\\")
                || s.contains("..")
            try require(!looksLikeLocation, .forbiddenValue, "\(path): looks like a path or URL")
        default:
            break
        }
    }
}

extension StudioJSONValue {
    /// A JSON integer.
    static func int(_ n: Int) -> StudioJSONValue { .number(StudioJSONNumber(validated: String(n))) }

    /// An object from ordered (key, value) pairs.
    static func members(_ pairs: [(String, StudioJSONValue)]) -> StudioJSONValue {
        .object(pairs.map { StudioJSONMember(key: $0.0, value: $0.1) })
    }

    /// A copy with member `key` replaced (kept in its position) or appended.
    func setting(_ key: String, to value: StudioJSONValue) -> StudioJSONValue {
        guard case .object(var members) = self else { return self }
        if let i = members.firstIndex(where: { $0.key == key }) {
            members[i] = StudioJSONMember(key: key, value: value)
        } else {
            members.append(StudioJSONMember(key: key, value: value))
        }
        return .object(members)
    }
}
