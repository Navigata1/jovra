import Foundation

/// Locates the shared Studio conformance fixtures (`spec/studio/fixtures`, owned by the spec, shared with Android)
/// from this file's own path, so tests read the one copy in the repository and never a copy bundled into the package.
///
/// The repository root is a fixed number of folders above this file
/// (`ios/Packages/JovraStudioMedia/Tests/JovraStudioMediaTests/Support/StudioFixtures.swift`); the locator never searches
/// upwards, so a renamed or missing fixtures folder fails loudly instead of finding some other checkout.
enum StudioFixtures {
    enum LocatorError: Error, CustomStringConvertible {
        case fixturesFolderMissing(expectedAt: String)
        case fixtureMissing(path: String)

        var description: String {
            switch self {
            case .fixturesFolderMissing(let path):
                "spec/studio/fixtures not found at \(path) (located from #filePath; was the folder moved or renamed?)"
            case .fixtureMissing(let path):
                "Studio fixture not found: \(path)"
            }
        }
    }

    /// Folders between this file and the repository root: Support, JovraStudioMediaTests, Tests, JovraStudioMedia,
    /// Packages, ios.
    private static let foldersBelowRoot = 6

    /// The repository checkout this test source belongs to.
    static func repositoryRoot(filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0..<foldersBelowRoot { url.deleteLastPathComponent() }
        return url.standardizedFileURL
    }

    /// `spec/studio/fixtures`, or an error when that folder does not exist.
    static func root(filePath: String = #filePath) throws -> URL {
        let fixtures = repositoryRoot(filePath: filePath).appendingPathComponent("spec/studio/fixtures", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fixtures.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocatorError.fixturesFolderMissing(expectedAt: fixtures.path)
        }
        return fixtures
    }

    /// A fixture by its path relative to `spec/studio/fixtures`, for example `records/project-lock.json`.
    static func url(_ relativePath: String) throws -> URL {
        let url = try root().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocatorError.fixtureMissing(path: url.path)
        }
        return url
    }

    /// The bytes of a fixture.
    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }
}
