import CoreMedia
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

/// The synthetic sample media (T11) as the app's own media stack sees it: every entry of the sample media
/// manifest is rendered with its stated duration, frame rate and size, and AVFoundation decodes the burned-in
/// "Sample video (synthetic)" label on frames spread across every clip.
@Suite("Sample media: rendered per the manifest and visibly labelled")
struct SampleMediaTests {
    static let catalog = MediaFixtureCatalog.repository()

    static var manifest: SampleMediaManifest? {
        let url = catalog.root.appendingPathComponent("spec/fixtures/sample/media-manifest.json")
        return (try? Data(contentsOf: url)).flatMap { try? ContractCodec.decode(SampleMediaManifest.self, from: $0) }
    }

    static var mediaIDs: [String] { manifest?.media.map(\.mediaId) ?? [] }

    static func truth(for mediaId: String) throws -> GroundTruth {
        let truths = try catalog.truths(inSet: "sample").filter { $0.sampleMedia?.mediaId == mediaId }
        guard truths.count == 1, let truth = truths.first else {
            throw MediaFixtureError.unknownTruth("sample media \(mediaId)")
        }
        return truth
    }

    @Test("every manifest media id has a rendered file of the stated duration, frame rate and size", arguments: mediaIDs)
    func renderedAsStated(mediaId: String) async throws {
        let entry = try #require(Self.manifest?.media.first { $0.mediaId == mediaId })
        let truth = try Self.truth(for: mediaId)
        let url = try Self.catalog.mediaURL(for: truth)
        #expect(url.lastPathComponent == entry.fileName)
        let info = try await MediaProbe.probe(url)
        let video = try #require(info.video)
        let expectedRate = FrameRate(frames: entry.frameRate.num, perSeconds: entry.frameRate.den)
        #expect(video.frameRate == expectedRate)
        #expect(!video.isVariableFrameRate)
        #expect(video.codedWidth == entry.width && video.codedHeight == entry.height)
        #expect(video.isDecodable)
        #expect((info.audio != nil) == entry.hasAudio)
        // The video track's duration is exactly frameCount / rate; the container may round to its timescale.
        let durationMs = CMTimeGetSeconds(info.duration) * 1000
        #expect(abs(durationMs - Double(entry.durationMs)) <= 1000 / Double(entry.frameRate.num) + 1)
        #expect(truth.video.frameCount * 1000 * entry.frameRate.den == entry.durationMs * entry.frameRate.num)
    }

    @Test("the manifest's media ids and the rendered sample set are the same", .enabled(if: manifest != nil))
    func setCoversManifest() throws {
        let rendered = try Self.catalog.truths(inSet: "sample").compactMap { $0.sampleMedia?.mediaId }
        #expect(rendered.sorted() == Self.mediaIDs.sorted())
    }

    @Test("AVFoundation decodes the burned-in label on frames spread across every clip", arguments: mediaIDs)
    func labelOnSampledFrames(mediaId: String) async throws {
        let truth = try Self.truth(for: mediaId)
        let label = try #require(truth.label)
        #expect(label.text == "Sample video (synthetic)")
        let url = try Self.catalog.mediaURL(for: truth)
        let count = truth.video.frameCount
        let frames = Array(Set([0, count - 1] + (1...6).map { count * $0 / 7 })).sorted()
        var regionMeans: [Int] = []
        for frame in frames {
            let plane = try await DecodedFrameReader.lumaPlane(of: url, frame: frame, rate: truth.video.frameRate)
            let r = label.region
            // The keyline, the text band and the whole banner.
            let text = plane.mean(x0: r.x + r.width / 8, x1: r.x + r.width * 7 / 8, y0: r.y, y1: r.y + r.height)
            regionMeans.append(plane.mean(x0: r.x, x1: r.x + r.width, y0: r.y, y1: r.y + r.height))
            // Ink covers a good share of the text band, the dark banner the rest: legible, not blank, not covered.
            #expect(text > label.background.y + 15, "frame \(frame): no ink in the label")
            #expect(text < label.ink.y - 60, "frame \(frame): label covered by something bright")
        }
        // The label is on top of everything: the same on every frame, whatever moves underneath it (within
        // a code value or two of lossy coding).
        #expect((regionMeans.max() ?? 0) - (regionMeans.min() ?? 0) <= 2, "label region means \(regionMeans)")
    }
}
