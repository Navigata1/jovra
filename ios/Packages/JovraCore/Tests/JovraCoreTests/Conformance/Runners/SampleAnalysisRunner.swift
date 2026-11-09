// fixture-kind: jovra.fixture.sampleAnalysis
import Foundation
import Testing
import JovraCore

/// The shipped library with the analysis overlays applied summarises to the reference analysis oracle.
struct SampleAnalysisRunner: FixtureRunner {
    let kind = "jovra.fixture.sampleAnalysis"
    private struct Fixture: Decodable { let libraryFixture: String; let mediaManifest: String; let expected: SampleAnalysisSummary }
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let folder = path.deletingLastPathComponent()
        let library = try SampleLibrary.load(from: folder.appendingPathComponent(fixture.libraryFixture).deletingLastPathComponent(),
                                             mediaManifest: folder.appendingPathComponent(fixture.mediaManifest),
                                             analysis: folder)
        let summary = try SampleAnalysisSummary.compute(sessions: library.sessions, mediaManifest: library.mediaManifest)
        #expect(summary == fixture.expected, "\(path.lastPathComponent)")
    }
}
