import Foundation
import Testing

@Suite("Studio fixture locator")
struct FixtureLocatorTests {
    @Test("finds the shared Sample project lock in spec/studio/fixtures, not a copy inside the package")
    func findsProjectLock() throws {
        let url = try StudioFixtures.url("records/project-lock.json")

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.standardizedFileURL.path.hasSuffix("/spec/studio/fixtures/records/project-lock.json"))
        #expect(!url.standardizedFileURL.path.contains("/ios/Packages/"))
    }

    @Test("a fixture that does not exist is an error naming the path, never a silent empty read")
    func missingFixtureThrows() {
        #expect(throws: StudioFixtures.LocatorError.self) {
            try StudioFixtures.url("records/no-such-record.json")
        }
    }
}
