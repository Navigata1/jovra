import Foundation
import Testing
@testable import JovraCore

protocol FixtureRunner: Sendable {
    var kind: String { get }
    func run(_ data: Data, path: URL) throws
}
enum FixtureManifestError: Error, Equatable { case repositoryMissing, duplicateRunner(String), unconsumedKind(String) }
enum FixtureManifest {
    static let pending: Set<String> = ["jovra.fixture.stats", "jovra.fixture.sample"]
    static func repository() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("spec/schemas/session.schema.json").path) {
            let parent = url.deletingLastPathComponent()
            guard parent != url else { throw FixtureManifestError.repositoryMissing }
            url = parent
        }
        return url
    }
    static func discover(root: URL, runnerKinds: [String]) throws -> [String: [URL]] {
        var seen = Set<String>()
        for kind in runnerKinds { guard seen.insert(kind).inserted else { throw FixtureManifestError.duplicateRunner(kind) } }
        var grouped: [String: [URL]] = [:]
        for directory in ["spec/fixtures", "spec/contracts"] {
            let urls = FileManager.default.enumerator(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)?.allObjects.compactMap { $0 as? URL } ?? []
            for path in urls.sorted(by: { $0.path < $1.path }) where path.pathExtension == "json" {
                let header = try JSONDecoder().decode(Header.self, from: Data(contentsOf: path))
                guard seen.contains(header.kind) || pending.contains(header.kind) else { throw FixtureManifestError.unconsumedKind(header.kind) }
                grouped[header.kind, default: []].append(path)
            }
        }
        return grouped
    }
    private struct Header: Decodable { var kind: String }
}

func roundTripRecord<T: Codable>(_ type: T.Type, data: Data, path: URL) throws {
    let value = try ContractCodec.decode(type, from: data)
    let encoded = try CanonicalJSON.encode(value)
    #expect(encoded == (try CanonicalJSON.canonicalize(data)), "Record loses fields: \(path.lastPathComponent)")
    if let directory = ProcessInfo.processInfo.environment["JOVRA_REENCODED_DIR"] {
        let root = try FixtureManifest.repository()
        let relative = String(path.path.dropFirst(root.path.count + 1))
        let target = URL(fileURLWithPath: directory).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: target, options: .atomic)
    }
}

@Test func allDiscoveredRunnerFixturesPass() throws {
    let inventory = try FixtureManifest.discover(root: FixtureManifest.repository(), runnerKinds: generatedFixtureRunners.map(\.kind))
    for runner in generatedFixtureRunners {
        let paths = inventory[runner.kind] ?? []
        #expect(!paths.isEmpty, "No fixtures for declared kind \(runner.kind)")
        for path in paths { try runner.run(Data(contentsOf: path), path: path) }
        print("Consumed \(runner.kind): \(paths.count) fixtures")
    }
    print("Pending fixture kinds: \(FixtureManifest.pending.sorted().joined(separator: ", "))")
}
