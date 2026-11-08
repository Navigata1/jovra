import AVFoundation
import JovraCore
import XCTest

/// The bundling step (T11, scripts/ios/bundle-sample-media.sh) puts every sample media file of the manifest
/// into the app bundle, playable by AVFoundation with the duration and frame rate the manifest states.
final class SampleMediaBundleTests: XCTestCase {
    private var folder: URL { Bundle.main.bundleURL.appendingPathComponent("SampleMedia", isDirectory: true) }

    private func status() throws -> String {
        struct Status: Decodable { let status: String }
        let data = try Data(contentsOf: folder.appendingPathComponent("bundle-status.json"))
        return try JSONDecoder().decode(Status.self, from: data).status
    }

    func testEveryManifestMediaFileIsBundledAndPlaysForItsStatedDuration() async throws {
        if try status() == "skipped" { throw XCTSkip("built with JOVRA_SKIP_SAMPLE_MEDIA=YES") }
        let data = try Data(contentsOf: folder.appendingPathComponent("media-manifest.json"))
        let manifest = try ContractCodec.decode(SampleMediaManifest.self, from: data)
        XCTAssertEqual(manifest.media.count, 11)
        var bytes = 0
        for entry in manifest.media {
            let url = folder.appendingPathComponent(entry.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(entry.fileName) is not bundled")
            bytes += try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first, entry.fileName)
            let (duration, rate, size) = try await track.load(.timeRange, .nominalFrameRate, .naturalSize)
            XCTAssertEqual(duration.duration.seconds * 1000, Double(entry.durationMs),
                           accuracy: 1000 / Double(entry.frameRate.num) + 1, entry.fileName)
            XCTAssertEqual(Double(rate), Double(entry.frameRate.num) / Double(entry.frameRate.den), accuracy: 0.01)
            XCTAssertEqual(size, CGSize(width: entry.width, height: entry.height))
            XCTAssertEqual(entry.label.rawValue, "Sample video (synthetic)")
        }
        XCTAssertLessThanOrEqual(bytes, 60_000_000, "bundled sample media over its 60 MB budget")
    }

}
