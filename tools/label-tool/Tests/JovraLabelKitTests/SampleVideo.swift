import Foundation
import JovraBenchmark

/// The synthetic sample video the tool's tests label: 20 s of the rendered court scene with 7 hit clicks,
/// 7 bounces and 2 rallies (spec/fixtures/media/sample/2026-09-09-match.truth.json, 640x360 at 60 fps).
/// It is rendered by `python3 scripts/media/render.py --set sample`, never committed.
enum SampleVideo {
    static let truthId = "sample/2026-09-09-match"
    static let catalog = MediaFixtureCatalog.repository()

    static func truth() throws -> GroundTruth { try catalog.truth(id: truthId) }

    /// Throws `MediaFixtureError.notRendered`, with the command to run, when the cache lacks the clip.
    static func url() throws -> URL { try catalog.mediaURL(for: try truth()) }

    static func frame(_ index: Int64) -> RationalTime { RationalTime(value: index, timescale: 60) }

    static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jovra-label-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
