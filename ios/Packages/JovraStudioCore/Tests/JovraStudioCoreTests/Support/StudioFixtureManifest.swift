import Foundation
import JovraStudioCore

/// The Swift half of the Studio fixture manifest (S10, spec/studio/README.md "Module pages").
///
/// It enumerates the kinds the shared fixtures contain (records and contract files by `schemaVersion`, invalid and
/// vector files by `schemaVersion`, vector files also by `kind`) and reads the front matter of every module page under
/// spec/studio/modules. A kind or registered schema on no page fails; a kind whose page says `swift: consumed` fails
/// unless a discovered consumer registers it; a kind whose page says `swift: pending` may be unconsumed. There is no
/// allow-list: a later Swift ticket flips only its own page's `swift:` line.
enum StudioFixtureManifest {
    struct Page: Equatable {
        let module: String
        let kinds: [String]
        let swift: String
    }

    struct Row: Equatable {
        let kind: String
        let page: String?
        let swift: String?
        let consumed: Bool
        let files: Int
    }

    struct Report {
        let rows: [Row]
        let failures: [String]
    }

    enum ManifestError: Error, CustomStringConvertible {
        case unreadable(String)

        var description: String {
            switch self { case .unreadable(let why): why }
        }
    }

    /// Front matter of every page in `modules` except the generated index (README.md).
    static func pages(in modules: URL) throws -> [Page] {
        let names = try FileManager.default.contentsOfDirectory(atPath: modules.path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }.sorted()
        return try names.map { name in
            let text = try String(contentsOf: modules.appendingPathComponent(name), encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
                throw ManifestError.unreadable("\(name): no front matter")
            }
            var fields: [String: String] = [:]
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                fields[String(line[..<colon]).trimmingCharacters(in: .whitespaces)] =
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            guard let module = fields["module"], let kinds = fields["kinds"], let swift = fields["swift"] else {
                throw ManifestError.unreadable("\(name): front matter needs module, kinds and swift")
            }
            guard kinds.hasPrefix("["), kinds.hasSuffix("]") else { throw ManifestError.unreadable("\(name): kinds is not a [list]") }
            let list = kinds.dropFirst().dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return Page(module: module, kinds: list, swift: swift)
        }
    }

    /// Kind -> number of fixture files that state it.
    static func fixtureKinds(fixtures: URL, contracts: URL?) throws -> [String: Int] {
        var kinds: [String: Int] = [:]
        func add(_ kind: String) { kinds[kind, default: 0] += 1 }
        var folders = ["records", "invalid", "vectors"].map { fixtures.appendingPathComponent($0) }
        if let contracts { folders.append(contracts) }
        for folder in folders {
            for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ $0.hasSuffix(".json") }).sorted() {
                let value = try StudioJSONParser.parse(Data(contentsOf: folder.appendingPathComponent(name)))
                guard case .string(let version)? = value["schemaVersion"] else {
                    throw ManifestError.unreadable("\(folder.lastPathComponent)/\(name): no schemaVersion")
                }
                add(version)
                if folder.lastPathComponent == "vectors" {
                    guard case .string(let kind)? = value["kind"] else {
                        throw ManifestError.unreadable("vectors/\(name): no kind")
                    }
                    add(kind)
                }
            }
        }
        return kinds
    }

    static func check(fixtures: URL, contracts: URL?, modules: URL, consumed: Set<String>) throws -> Report {
        let pages = try pages(in: modules)
        let kinds = try fixtureKinds(fixtures: fixtures, contracts: contracts)
        var failures: [String] = []
        var pageOf: [String: Page] = [:]
        for page in pages {
            if !["pending", "consumed"].contains(page.swift) {
                failures.append("page \(page.module): swift must be pending or consumed, not \(page.swift)")
            }
            for kind in page.kinds {
                if let other = pageOf[kind] {
                    failures.append("kind \(kind) is claimed by two module pages (\(other.module) and \(page.module))")
                }
                pageOf[kind] = page
            }
        }
        for kind in kinds.keys.sorted() where pageOf[kind] == nil {
            failures.append("kind \(kind) has no module page (\(kinds[kind]!) fixture file(s) state it)")
        }
        for kind in consumed.sorted() where pageOf[kind] == nil {
            failures.append("registered Swift kind \(kind) has no module page")
        }
        for page in pages where page.swift == "consumed" {
            for kind in page.kinds where !consumed.contains(kind) {
                failures.append("page \(page.module) says swift: consumed, but kind \(kind) has no registered Swift consumer")
            }
        }
        let rows = Set(kinds.keys).union(pageOf.keys).sorted().map { kind in
            Row(kind: kind, page: pageOf[kind]?.module, swift: pageOf[kind]?.swift, consumed: consumed.contains(kind),
                files: kinds[kind] ?? 0)
        }
        return Report(rows: rows, failures: failures)
    }
}
