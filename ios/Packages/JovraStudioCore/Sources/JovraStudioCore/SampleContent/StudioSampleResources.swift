import Foundation

/// The app bundles a copy of the Studio sample records (`ios/Jovra/Resources/StudioSample`) that must be
/// byte-identical to the shared fixtures (`spec/studio/fixtures/records`); `scripts/studio/sync-sample-resources.sh`
/// refreshes it. This compares the two folders by SHA-256 of every `.json` file.
public enum StudioSampleResources {
    public enum Difference: Equatable, Sendable, CustomStringConvertible {
        /// In the fixtures, not in the bundled copy.
        case missing(String)
        /// In the bundled copy, not in the fixtures.
        case extra(String)
        /// In both, with different bytes.
        case changed(String, bundled: String, fixture: String)

        public var description: String {
            switch self {
            case .missing(let name): "\(name): missing from the bundled copy"
            case .extra(let name): "\(name): not in spec/studio/fixtures/records"
            case .changed(let name, let bundled, let fixture): "\(name): sha256 \(bundled) != fixture \(fixture)"
            }
        }
    }

    /// Every difference between the bundled copy and the fixtures; empty when they are byte-identical.
    public static func differences(bundled: URL, fixtures: URL) throws -> [Difference] {
        let mine = try hashes(in: bundled)
        let theirs = try hashes(in: fixtures)
        var result: [Difference] = []
        for name in Set(mine.keys).union(theirs.keys).sorted() {
            switch (mine[name], theirs[name]) {
            case (nil, _?): result.append(.missing(name))
            case (_?, nil): result.append(.extra(name))
            case (let a?, let b?) where a != b: result.append(.changed(name, bundled: a, fixture: b))
            default: break
            }
        }
        return result
    }

    /// SHA-256 of every `.json` file directly in `folder`, by name.
    public static func hashes(in folder: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix(".json") {
            result[name] = StudioSHA256.hex(try Data(contentsOf: folder.appendingPathComponent(name)))
        }
        return result
    }
}
