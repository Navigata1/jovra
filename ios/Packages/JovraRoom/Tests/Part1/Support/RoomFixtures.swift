import Foundation
import XCTest

/// Locates spec/room/fixtures from this file's #filePath and reads them in place (never copied into the package),
/// as spec/room/README.md "For the ports" requires.
enum RoomFixtures {
    /// The repository root: the first ancestor of this file that holds spec/room/fixtures.
    static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("spec/room/fixtures").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        fatalError("spec/room/fixtures not found above \(#filePath)")
    }()

    static let directory = repositoryRoot.appendingPathComponent("spec/room/fixtures")

    /// Every fixture file, relative to spec/room/fixtures (e.g. "vectors/freshness.json").
    static func allFiles() throws -> [String] {
        let base = directory.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(atPath: base) else { return [] }
        return walker.compactMap { $0 as? String }.filter { $0.hasSuffix(".json") }.sorted()
    }

    static func files(in folder: String) throws -> [String] {
        try allFiles().filter { $0.hasPrefix(folder + "/") }
    }

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(relativePath))
    }

    static func json(_ relativePath: String) throws -> JSONValue { try JSONValue.parse(data(relativePath)) }

    /// "records/room-snapshot.json" or "room-snapshot" (the reference's ctx.records key).
    static func record(_ name: String) throws -> JSONValue {
        try json(name.hasPrefix("records/") ? name : "records/\(name).json")
    }

    /// spec/contracts/capability-registry.v1.json as id -> status (read-only, as validate_room.py reads it).
    static func registryStatuses() throws -> [String: String] {
        let url = repositoryRoot.appendingPathComponent("spec/contracts/capability-registry.v1.json")
        let registry = try JSONValue.parse(Data(contentsOf: url))
        var statuses: [String: String] = [:]
        for capability in registry["capabilities"]?.array ?? [] {
            if let id = capability["id"]?.string, let status = capability["status"]?.string { statuses[id] = status }
        }
        return statuses
    }
}

/// Vector kinds (spec/room/schemas/fixture.schema.json) and who runs them. Part 1 (W01) runs its own kinds; the rest
/// Part 2 (W02,
/// #271) runs the rest, so an unknown kind, or a kind nobody owns, fails the manifest test.
enum RoomVectorKinds {
    static let part1: [String: Int] = [
        "freshness": 14, "snapshot": 14, "phone-status": 5, "display": 6, "disconnect": 1, "analysis": 7,
    ]
    /// W02 (#271): the Part 2 kinds and their case counts (Tests/Part2/Part2VectorConformanceTests).
    static let part2: [String: Int] = [
        "watch-sample": 9, "bridge": 6, "alerts": 9, "invitation": 28, "ledger": 22, "outbox": 8,
    ]
    /// Every kind with its case count: 129 cases in all.
    static let counts: [String: Int] = part1.merging(part2) { _, _ in preconditionFailure("a kind has one owner") }
    static let all: Set<String> = Set(counts.keys)
}

/// One test failure location for a fixture case, e.g. "vectors/snapshot.json#replay-and-order step 1".
struct CaseRef: CustomStringConvertible {
    let file: String
    let id: String
    var detail: String = ""
    var description: String { "\(file)#\(id)" + (detail.isEmpty ? "" : " \(detail)") }
    func step(_ index: Int) -> CaseRef { CaseRef(file: file, id: id, detail: "step \(index)") }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ ref: CaseRef,
                               file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual, expected, "\(ref)", file: file, line: line)
}
