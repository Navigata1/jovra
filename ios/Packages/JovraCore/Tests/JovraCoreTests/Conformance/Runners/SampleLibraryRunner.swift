// fixture-kind: jovra.fixture.sampleLibrary
import Foundation
import Testing
import JovraCore

/// The shipped library documents load as a Sample library and summarise to the reference oracle.
struct SampleLibraryRunner: FixtureRunner {
    let kind = "jovra.fixture.sampleLibrary"
    private struct Fixture: Decodable { let mediaManifest: String; let expected: LibrarySummary }
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let folder = path.deletingLastPathComponent()
        let library = try SampleLibrary.load(from: folder, mediaManifest: folder.appendingPathComponent(fixture.mediaManifest))
        let summary = try LibrarySummary.compute(sessions: library.sessions, equipment: [library.equipment])
        #expect(summary == fixture.expected, "\(path.lastPathComponent)")
    }
}
