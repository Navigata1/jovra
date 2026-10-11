import Foundation

// JovraStudioCore: JOVRA Studio's Foundation-only domain layer (docs/studio/DEVELOPING.md). This file is the package's
// smoke surface (S04). Domain modules (contracts, EDL, ledger, project, cloud, room, ...) land in their own folders.

/// The contract a Studio record names in its `schemaVersion` field, for example `jovra.project-lock/1`.
///
/// Accepted exactly as `jovra.<kind>/<version>`: the kind is one or more dot-separated segments of lower-case letters,
/// digits and hyphens, each starting with a letter; the version is a positive integer without leading zeros. Anything
/// else, including a trailing newline (ECMA-262 `$` semantics, as the shared contracts use), is refused.
public struct StudioSchemaVersion: Hashable, Sendable, CustomStringConvertible {
    public let kind: String
    public let version: Int

    public init(kind: String, version: Int) {
        self.kind = kind
        self.version = version
    }

    /// Parses `jovra.<kind>/<version>`; `nil` when the text is not exactly that shape.
    public init?(_ text: String) {
        let prefix = "jovra."
        guard text.hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              Self.isKind(parts[0]),
              let version = Self.positiveInteger(parts[1])
        else { return nil }
        self.init(kind: String(parts[0]), version: version)
    }

    public var description: String { "jovra.\(kind)/\(version)" }

    private static func isKind(_ text: Substring) -> Bool {
        let segments = text.split(separator: ".", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { segment in
            guard let first = segment.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
            return segment.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }
    }

    private static func positiveInteger(_ text: Substring) -> Int? {
        guard let first = text.unicodeScalars.first, ("1"..."9").contains(first),
              text.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) })
        else { return nil }
        return Int(text)
    }
}

/// The two facts every Studio record states up front: which contract it follows and whether it is Sample data
/// (Sample data is always shown labelled "Sample", CLAUDE.md rule 1).
public struct StudioRecordHeader: Hashable, Sendable {
    public enum ReadError: Error, Equatable {
        case unreadable
        case missingSchemaVersion
        case malformedSchemaVersion(String)
    }

    public let schemaVersion: StudioSchemaVersion
    /// `true` only when the record says `"sample": true`.
    public let isSample: Bool

    public init(json data: Data) throws {
        let fields: Fields
        do {
            fields = try JSONDecoder().decode(Fields.self, from: data)
        } catch DecodingError.keyNotFound {
            throw ReadError.missingSchemaVersion
        } catch {
            throw ReadError.unreadable
        }
        guard let schemaVersion = StudioSchemaVersion(fields.schemaVersion) else {
            throw ReadError.malformedSchemaVersion(fields.schemaVersion)
        }
        self.schemaVersion = schemaVersion
        self.isSample = fields.sample == true
    }

    /// JSONDecoder rather than JSONSerialization, so `"sample": 1` is not read as `true` on Apple platforms only.
    private struct Fields: Decodable {
        let schemaVersion: String
        let sample: Bool?
    }
}
