import Foundation

/// A schema inside the Studio schema set: a file under spec/schemas/studio and a JSON pointer into it ("" for the root).
public struct StudioSchemaLocation: Hashable, Sendable, CustomStringConvertible {
    public let file: String
    public let pointer: String

    public init(file: String, pointer: String = "") {
        self.file = file
        self.pointer = pointer
    }

    public var description: String { pointer.isEmpty ? file : "\(file)#\(pointer)" }
}

/// The JSON Schema (draft 2020-12) subset the Studio schemas use, checked exactly as the shared reference checks it
/// (`scripts/spec/jsonschema_subset.py`, with `validate_studio.py`'s ECMA-262 anchors), with one deliberate
/// difference: `"type": "integer"` accepts only a number written without fraction or exponent, so `744.0` is refused
/// where Python would accept it.
///
/// Patterns follow ECMA-262: without the multiline flag `$` matches only at the very end of the input, so
/// `^[0-9a-f]{64}$` refuses a hash followed by a newline. ICU (NSRegularExpression), like Python's `re` and
/// java.util.regex, also matches `$` before a final line terminator; every unescaped `$` outside a character class is
/// therefore rewritten as `\z`. Both engines work on UTF-16 code units, as ECMA-262 does without the `u` flag.
public final class StudioSchemaSet: @unchecked Sendable {
    // Immutable after init; NSRegularExpression is documented as safe to share between threads.
    private let files: [String: StudioJSONValue]
    private let patterns: [String: NSRegularExpression]
    /// Problems found while loading: unsupported keywords, unresolvable references, non-ECMA escapes, bad patterns.
    public let problems: [String]

    static let annotations: Set<String> = ["$schema", "$comment", "title", "description", "default", "examples",
                                           "deprecated", "format"]
    static let applicators: Set<String> = ["$ref", "$defs", "allOf", "anyOf", "oneOf", "not", "if", "then", "else",
                                           "properties", "patternProperties", "additionalProperties", "propertyNames",
                                           "items", "prefixItems", "contains"]
    static let assertions: Set<String> = ["type", "enum", "const", "required", "minProperties", "maxProperties",
                                          "dependentRequired", "minItems", "maxItems", "uniqueItems", "minimum",
                                          "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minLength",
                                          "maxLength", "pattern"]
    /// Class escapes whose meaning differs between regex engines; the shared schemas spell classes out instead.
    static let nonPortableEscapes: Set<String> = ["\\d", "\\D", "\\w", "\\W", "\\s", "\\S", "\\b", "\\B"]

    /// The Studio schemas embedded in this package (`StudioSchemaSource`).
    public static let studio: StudioSchemaSet = {
        do { return try StudioSchemaSet(files: StudioSchemaSource.embedded) } catch {
            preconditionFailure("embedded Studio schemas do not parse: \(error)")
        }
    }()

    /// Builds a set from schema file texts keyed by file name.
    public init(files texts: [String: String]) throws {
        var files: [String: StudioJSONValue] = [:]
        for (name, text) in texts { files[name] = try StudioJSONParser.parse(Data(text.utf8)) }
        self.files = files
        var problems: [String] = []
        var patterns: [String: NSRegularExpression] = [:]
        for name in files.keys.sorted() {
            Self.collect(files[name]!, file: name, at: "#", files: files, problems: &problems, patterns: &patterns)
        }
        self.problems = problems
        self.patterns = patterns
    }

    /// `pattern` rewritten for ICU with ECMA-262 end anchors.
    public static func ecmaPattern(_ pattern: String) -> String {
        var out = "", inClass = false, escaped = false
        for ch in pattern {
            if escaped { out.append(ch); escaped = false; continue }
            switch ch {
            case "\\": escaped = true; out.append(ch)
            case "[" where !inClass: inClass = true; out.append(ch)
            case "]" where inClass: inClass = false; out.append(ch)
            case "$" where !inClass: out += "\\z"
            default: out.append(ch)
            }
        }
        return out
    }

    // ----- loading ------------------------------------------------------------------------------------------

    private static func collect(_ schema: StudioJSONValue, file: String, at where_: String, files: [String: StudioJSONValue],
                                problems: inout [String], patterns: inout [String: NSRegularExpression]) {
        if case .bool = schema { return }
        guard case .object(let members) = schema else {
            problems.append("\(file)\(where_): schema must be an object or boolean")
            return
        }
        let supported = annotations.union(applicators).union(assertions)
        for member in members where !supported.contains(member.key) {
            problems.append("\(file)\(where_): unsupported keyword \"\(member.key)\"")
        }
        if case .string(let ref)? = schema["$ref"], resolve(ref, from: file, in: files) == nil {
            problems.append("\(file)\(where_): unresolvable $ref \(ref)")
        }
        var found: [String] = []
        if case .string(let p)? = schema["pattern"] { found.append(p) }
        if case .object(let props)? = schema["patternProperties"] { found += props.map(\.key) }
        for pattern in found {
            var i = pattern.startIndex
            while i < pattern.endIndex {
                if pattern[i] == "\\", pattern.index(after: i) < pattern.endIndex {
                    let escape = String(pattern[i...pattern.index(after: i)])
                    if nonPortableEscapes.contains(escape) {
                        problems.append("\(file)\(where_): pattern \(pattern) uses \(escape); spell the class out")
                    }
                    i = pattern.index(i, offsetBy: 2)
                } else {
                    i = pattern.index(after: i)
                }
            }
            do { patterns[pattern] = try NSRegularExpression(pattern: ecmaPattern(pattern)) } catch {
                problems.append("\(file)\(where_): bad pattern \(pattern)")
            }
        }
        for key in ["$defs", "properties", "patternProperties"] {
            if case .object(let subs)? = schema[key] {
                for sub in subs {
                    collect(sub.value, file: file, at: "\(where_)/\(key)/\(sub.key)", files: files, problems: &problems, patterns: &patterns)
                }
            }
        }
        for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
            if case .array(let subs)? = schema[key] {
                for (i, sub) in subs.enumerated() {
                    collect(sub, file: file, at: "\(where_)/\(key)/\(i)", files: files, problems: &problems, patterns: &patterns)
                }
            }
        }
        for key in ["not", "if", "then", "else", "additionalProperties", "propertyNames", "items", "contains"] {
            if let sub = schema[key] {
                collect(sub, file: file, at: "\(where_)/\(key)", files: files, problems: &problems, patterns: &patterns)
            }
        }
    }

    private static func resolve(_ ref: String, from file: String, in files: [String: StudioJSONValue]) -> (StudioJSONValue, String)? {
        let parts = ref.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let target = parts[0].isEmpty ? file : String(parts[0])
        guard let root = files[target] else { return nil }
        let pointer = parts.count > 1 ? String(parts[1]) : ""
        guard let node = locate(pointer, in: root) else { return nil }
        return (node, target)
    }

    private static func locate(_ pointer: String, in root: StudioJSONValue) -> StudioJSONValue? {
        var node = root
        for raw in pointer.split(separator: "/") {
            let token = raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            switch node {
            case .object: guard let next = node[token] else { return nil }; node = next
            case .array(let items): guard let i = Int(token), items.indices.contains(i) else { return nil }; node = items[i]
            default: return nil
            }
        }
        return node
    }

    // ----- validation ---------------------------------------------------------------------------------------

    /// Every way `value` breaks the schema at `location`, as `$.path: message` lines; empty when it conforms.
    public func validate(_ value: StudioJSONValue, against location: StudioSchemaLocation) -> [String] {
        guard let root = files[location.file], let schema = Self.locate(location.pointer, in: root) else {
            return ["$: no schema at \(location)"]
        }
        return validate(value, schema, file: location.file, path: "$")
    }

    private func validate(_ value: StudioJSONValue, _ schema: StudioJSONValue, file: String, path: String) -> [String] {
        if case .bool(let allowed) = schema { return allowed ? [] : ["\(path): no value is allowed here"] }
        var errors: [String] = []
        if case .string(let ref)? = schema["$ref"] {
            guard let (target, targetFile) = Self.resolve(ref, from: file, in: files) else { return ["\(path): unresolvable $ref \(ref)"] }
            errors += validate(value, target, file: targetFile, path: path)
        }
        if let type = schema["type"] {
            let names: [String]
            switch type {
            case .string(let one): names = [one]
            case .array(let many): names = many.compactMap { if case .string(let s) = $0 { s } else { nil } }
            default: names = []
            }
            if !names.contains(where: { Self.matches(value, type: $0) }) {
                return errors + ["\(path): expected type \(names), got \(value.typeName)"]
            }
        }
        if case .array(let choices)? = schema["enum"], !choices.contains(where: { Self.equal(value, $0) }) {
            errors.append("\(path): \(Self.show(value)) is not one of the allowed values")
        }
        if let constant = schema["const"], !Self.equal(value, constant) {
            errors.append("\(path): expected \(Self.show(constant)), got \(Self.show(value))")
        }
        switch value {
        case .number(let n): errors += numeric(n, schema, path: path)
        case .string(let s): errors += string(s, schema, path: path)
        case .array(let items): errors += array(items, schema, file: file, path: path)
        case .object(let members): errors += object(members, schema, file: file, path: path)
        default: break
        }
        if case .array(let subs)? = schema["allOf"] {
            for sub in subs { errors += validate(value, sub, file: file, path: path) }
        }
        if case .array(let subs)? = schema["anyOf"], !subs.contains(where: { validate(value, $0, file: file, path: path).isEmpty }) {
            errors.append("\(path): matches none of anyOf")
        }
        if case .array(let subs)? = schema["oneOf"] {
            let results = subs.map { validate(value, $0, file: file, path: path) }
            let passing = results.filter(\.isEmpty).count
            if passing != 1 {
                let closest = passing == 0 ? "; closest: " + (results.min(by: { $0.count < $1.count })?.first ?? "") : ""
                errors.append("\(path): matches \(passing) of oneOf (exactly 1 required)\(closest)")
            }
        }
        if let not = schema["not"], validate(value, not, file: file, path: path).isEmpty {
            errors.append("\(path): must not match the 'not' schema")
        }
        if let condition = schema["if"] {
            if validate(value, condition, file: file, path: path).isEmpty {
                if let then = schema["then"] { errors += validate(value, then, file: file, path: path) }
            } else if let otherwise = schema["else"] {
                errors += validate(value, otherwise, file: file, path: path)
            }
        }
        return errors
    }

    private static func matches(_ value: StudioJSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("null", .null), ("boolean", .bool), ("string", .string), ("array", .array), ("object", .object): true
        case ("number", .number): true
        case ("integer", .number(let n)): n.isIntegerToken   // stricter than Python: 744.0 is not an integer here
        default: false
        }
    }

    /// JSON equality: numbers by exact value (1 equals 1.0, as in the reference), objects regardless of member order.
    static func equal(_ a: StudioJSONValue, _ b: StudioJSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        case (.number(let x), .number(let y)): return x.decimal == y.decimal
        case (.array(let x), .array(let y)): return x.count == y.count && zip(x, y).allSatisfy { equal($0, $1) }
        case (.object(let x), .object(let y)):
            guard x.count == y.count else { return false }
            return x.allSatisfy { member in y.contains { $0.key == member.key && equal($0.value, member.value) } }
        default: return false
        }
    }

    private static func show(_ value: StudioJSONValue) -> String {
        let text = String(decoding: value.serialized(), as: UTF8.self)
        return text.count > 80 ? String(text.prefix(77)) + "..." : text
    }

    private static func bound(_ schema: StudioJSONValue, _ key: String) -> Decimal? {
        if case .number(let n)? = schema[key] { return n.decimal }
        return nil
    }

    private func numeric(_ n: StudioJSONNumber, _ schema: StudioJSONValue, path: String) -> [String] {
        let value = n.decimal
        var errors: [String] = []
        if let limit = Self.bound(schema, "minimum"), value < limit { errors.append("\(path): \(n) < minimum \(limit)") }
        if let limit = Self.bound(schema, "maximum"), value > limit { errors.append("\(path): \(n) > maximum \(limit)") }
        if let limit = Self.bound(schema, "exclusiveMinimum"), value <= limit { errors.append("\(path): \(n) <= exclusiveMinimum \(limit)") }
        if let limit = Self.bound(schema, "exclusiveMaximum"), value >= limit { errors.append("\(path): \(n) >= exclusiveMaximum \(limit)") }
        if let step = Self.bound(schema, "multipleOf") {
            var quotient = value / step, whole = Decimal()
            NSDecimalRound(&whole, &quotient, 0, .down)
            if whole != quotient { errors.append("\(path): \(n) is not a multiple of \(step)") }
        }
        return errors
    }

    private func string(_ s: String, _ schema: StudioJSONValue, path: String) -> [String] {
        var errors: [String] = []
        let length = s.unicodeScalars.count  // JSON Schema counts code points, as Python's len() does
        if case .number(let n)? = schema["minLength"], let min = n.int64, length < min { errors.append("\(path): shorter than \(min)") }
        if case .number(let n)? = schema["maxLength"], let max = n.int64, length > max { errors.append("\(path): longer than \(max)") }
        if case .string(let pattern)? = schema["pattern"], !search(pattern, in: s) {
            errors.append("\(path): \(Self.show(.string(s))) does not match \(pattern)")
        }
        return errors
    }

    private func search(_ pattern: String, in text: String) -> Bool {
        guard let regex = patterns[pattern] else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func array(_ items: [StudioJSONValue], _ schema: StudioJSONValue, file: String, path: String) -> [String] {
        var errors: [String] = []
        if case .number(let n)? = schema["minItems"], let min = n.int64, items.count < min { errors.append("\(path): fewer than \(min) items") }
        if case .number(let n)? = schema["maxItems"], let max = n.int64, items.count > max { errors.append("\(path): more than \(max) items") }
        if case .bool(true)? = schema["uniqueItems"] {
            for i in items.indices { for j in items.indices where j > i && Self.equal(items[i], items[j]) {
                errors.append("\(path): items \(i) and \(j) are equal")
            } }
        }
        var prefixCount = 0
        if case .array(let prefix)? = schema["prefixItems"] {
            prefixCount = prefix.count
            for (i, sub) in prefix.enumerated() where i < items.count {
                errors += validate(items[i], sub, file: file, path: "\(path)[\(i)]")
            }
        }
        if let itemSchema = schema["items"] {
            for i in items.indices where i >= prefixCount {
                errors += validate(items[i], itemSchema, file: file, path: "\(path)[\(i)]")
            }
        }
        if let contains = schema["contains"], !items.contains(where: { validate($0, contains, file: file, path: path).isEmpty }) {
            errors.append("\(path): no item matches 'contains'")
        }
        return errors
    }

    private func object(_ members: [StudioJSONMember], _ schema: StudioJSONValue, file: String, path: String) -> [String] {
        var errors: [String] = []
        let keys = Set(members.map(\.key))
        if case .array(let required)? = schema["required"] {
            for case .string(let key) in required where !keys.contains(key) {
                errors.append("\(path): missing required property \"\(key)\"")
            }
        }
        if case .number(let n)? = schema["minProperties"], let min = n.int64, members.count < min { errors.append("\(path): fewer than \(min) properties") }
        if case .number(let n)? = schema["maxProperties"], let max = n.int64, members.count > max { errors.append("\(path): more than \(max) properties") }
        if case .object(let dependencies)? = schema["dependentRequired"] {
            for dependency in dependencies where keys.contains(dependency.key) {
                if case .array(let needed) = dependency.value {
                    for case .string(let other) in needed where !keys.contains(other) {
                        errors.append("\(path): \"\(dependency.key)\" requires \"\(other)\"")
                    }
                }
            }
        }
        let properties: [StudioJSONMember] = { if case .object(let p)? = schema["properties"] { p } else { [] } }()
        let patternProperties: [StudioJSONMember] = { if case .object(let p)? = schema["patternProperties"] { p } else { [] } }()
        for member in members {
            var matched = false
            if let sub = properties.first(where: { $0.key == member.key }) {
                matched = true
                errors += validate(member.value, sub.value, file: file, path: "\(path).\(member.key)")
            }
            for pattern in patternProperties where search(pattern.key, in: member.key) {
                matched = true
                errors += validate(member.value, pattern.value, file: file, path: "\(path).\(member.key)")
            }
            if !matched, let additional = schema["additionalProperties"] {
                if case .bool(false) = additional {
                    errors.append("\(path).\(member.key): unknown property \"\(member.key)\" (additionalProperties is false)")
                } else {
                    errors += validate(member.value, additional, file: file, path: "\(path).\(member.key)")
                }
            }
            if let names = schema["propertyNames"] {
                errors += validate(.string(member.key), names, file: file, path: "\(path).<\(member.key)>")
            }
        }
        return errors
    }
}
