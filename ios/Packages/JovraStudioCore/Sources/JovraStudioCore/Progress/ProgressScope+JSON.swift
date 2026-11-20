import Foundation
import JovraCore

extension ProgressScope {
    /// The fields of a scope as the shared vectors and the story brief state them (`progress.SCOPE_FIELDS`).
    public static let jsonFields = ["date", "sessionIds", "sessionKind", "statDefinitionId", "methodId", "methodVersion",
                                    "capabilityVersion", "selectionRule", "numerator", "denominator", "provenance"]

    /// Reads a scope strictly: exactly the scope fields, a YYYY-MM-DD date, at least one session, a known selection rule
    /// and provenance, integer tokens for the fraction. Anything else is `badScope`; a numerator outside
    /// `0...denominator` is `badFraction`.
    public init(json: StudioJSONValue) throws(ProgressRejection) {
        guard case .object(let members) = json else { throw ProgressRejection(.badScope, "a scope must be an object") }
        let keys = members.map(\.key)
        let missing = Self.jsonFields.filter { !keys.contains($0) }
        let unknown = keys.filter { !Self.jsonFields.contains($0) }
        guard missing.isEmpty, unknown.isEmpty, Set(keys).count == keys.count else {
            throw ProgressRejection(.badScope, "scope fields: missing \(missing), unknown \(unknown)")
        }
        func string(_ key: String) throws(ProgressRejection) -> String {
            guard case .string(let value)? = json[key] else { throw ProgressRejection(.badScope, "\(key) must be a string") }
            return value
        }
        func integer(_ key: String) throws(ProgressRejection) -> Int {
            guard case .number(let n)? = json[key], let value = n.int64, let int = Int(exactly: value) else {
                throw ProgressRejection(.badScope, "\(key) must be an integer")
            }
            return int
        }
        let date = try string("date")
        guard ProgressDay(date) != nil else { throw ProgressRejection(.badScope, "date \(date) is not YYYY-MM-DD") }
        guard case .array(let sessions)? = json["sessionIds"], !sessions.isEmpty else {
            throw ProgressRejection(.badScope, "a scope needs a session")
        }
        var sessionIds: [String] = []
        for session in sessions {
            guard case .string(let id) = session else { throw ProgressRejection(.badScope, "session ids are strings") }
            sessionIds.append(id)
        }
        guard let rule = ProgressSelectionRule(rawValue: try string("selectionRule")) else {
            throw ProgressRejection(.badScope, "unknown selection rule")
        }
        guard let provenance = Provenance(rawValue: try string("provenance")) else {
            throw ProgressRejection(.badScope, "unknown provenance")
        }
        let capabilityVersion: String?
        switch json["capabilityVersion"] {
        case .null?: capabilityVersion = nil
        case .string(let value)?: capabilityVersion = value
        default: throw ProgressRejection(.badScope, "capabilityVersion must be a string or null")
        }
        let numerator = try integer("numerator"), denominator = try integer("denominator")
        guard numerator >= 0, numerator <= denominator else {
            throw ProgressRejection(.badFraction, "fraction \(numerator) / \(denominator)")
        }
        self.init(date: date, sessionIds: sessionIds, sessionKind: try string("sessionKind"),
                  statDefinitionId: try string("statDefinitionId"),
                  method: ProgressMethod(methodId: try string("methodId"), methodVersion: try string("methodVersion"),
                                         capabilityVersion: capabilityVersion),
                  selectionRule: rule, numerator: numerator, denominator: denominator, provenance: provenance)
    }
}
