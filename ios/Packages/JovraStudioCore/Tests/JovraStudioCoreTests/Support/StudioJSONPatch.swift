import Foundation
import JovraStudioCore

/// The RFC 6902 subset the shared invalid cases use (`spec/reference/studio/core.py` `apply_patch`): replace, add (an
/// object member, or an array index or "-") and remove, on a copy. Patch values keep their exact number tokens, so
/// `744.0` reaches the decoder as written.
enum StudioJSONPatch {
    struct PatchError: Error, CustomStringConvertible { let description: String }

    static func apply(_ operations: StudioJSONValue, to document: StudioJSONValue) throws -> StudioJSONValue {
        guard case .array(let ops) = operations else { throw PatchError(description: "patch is not an array") }
        var doc = document
        for op in ops {
            guard case .string(let kind)? = op["op"], case .string(let path)? = op["path"] else {
                throw PatchError(description: "patch operation without op and path")
            }
            let tokens = try pointer(path)
            guard !tokens.isEmpty else { throw PatchError(description: "cannot patch the document root") }
            doc = try update(doc, tokens[...], kind: kind, value: op["value"])
        }
        return doc
    }

    private static func pointer(_ path: String) throws -> [String] {
        guard path.hasPrefix("/") else { throw PatchError(description: "bad pointer \(path)") }
        return path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    private static func update(_ node: StudioJSONValue, _ tokens: ArraySlice<String>, kind: String, value: StudioJSONValue?) throws -> StudioJSONValue {
        let token = tokens.first!
        let last = tokens.count == 1
        switch node {
        case .object(var members):
            let index = members.firstIndex(where: { $0.key == token })
            if !last {
                guard let index else { throw PatchError(description: "no member \(token)") }
                members[index] = StudioJSONMember(key: token, value: try update(members[index].value, tokens.dropFirst(), kind: kind, value: value))
                return .object(members)
            }
            switch kind {
            case "replace":
                guard let index, let value else { throw PatchError(description: "replace of missing member \(token)") }
                members[index] = StudioJSONMember(key: token, value: value)
            case "add":
                guard let value else { throw PatchError(description: "add without a value") }
                if let index { members[index] = StudioJSONMember(key: token, value: value) } else { members.append(StudioJSONMember(key: token, value: value)) }
            case "remove":
                guard let index else { throw PatchError(description: "remove of missing member \(token)") }
                members.remove(at: index)
            default: throw PatchError(description: "unsupported op \(kind)")
            }
            return .object(members)
        case .array(var items):
            if last, kind == "add", token == "-" {
                guard let value else { throw PatchError(description: "add without a value") }
                return .array(items + [value])
            }
            guard let i = Int(token), i >= 0, i < items.count || (last && kind == "add" && i == items.count) else {
                throw PatchError(description: "bad array index \(token)")
            }
            if !last {
                items[i] = try update(items[i], tokens.dropFirst(), kind: kind, value: value)
                return .array(items)
            }
            switch kind {
            case "replace": guard let value else { throw PatchError(description: "replace without a value") }; items[i] = value
            case "add": guard let value else { throw PatchError(description: "add without a value") }; items.insert(value, at: i)
            case "remove": items.remove(at: i)
            default: throw PatchError(description: "unsupported op \(kind)")
            }
            return .array(items)
        default:
            throw PatchError(description: "cannot descend into a scalar at \(token)")
        }
    }
}
