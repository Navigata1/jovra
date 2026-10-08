import CryptoKit
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

/// `MediaProbe` reports what import needs to know about a file. Every import fixture's probed properties
/// must equal the ground truth the renderer wrote (codec, frame rate, HDR, orientation and the rest).
@Suite("MediaProbe reports every import fixture's ground truth")
struct ImportFixtureProbeTests {
    static let catalog = MediaFixtureCatalog.repository()

    static var importIDs: [String] {
        ((try? catalog.truths(inSet: "import")) ?? []).map(\.id)
    }

    @Test("codec, fps, HDR, orientation, rotation, size, audio and decodability match", arguments: importIDs)
    func probeMatchesTruth(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let info = try await MediaProbe.probe(try Self.catalog.mediaURL(for: truth))
        let video = try #require(info.video)
        #expect(video.codec.name == truth.video.codec)
        #expect(video.fourCC == truth.video.fourCC)
        #expect(video.frameRate == truth.video.frameRate.frameRate)
        #expect(video.isHDR == (truth.video.hdr != nil))
        #expect(video.orientation.rawValue == truth.video.orientation)
        #expect(video.rotationDegrees == truth.video.rotationDegrees)
        #expect(video.codedWidth == truth.video.codedWidth && video.codedHeight == truth.video.codedHeight)
        #expect(video.displayWidth == truth.video.displayWidth && video.displayHeight == truth.video.displayHeight)
        #expect(video.bitDepth == truth.video.bitDepth)
        #expect(video.isDecodable == truth.video.supported)
        #expect((info.audio != nil) == (truth.audio != nil))
        if let audio = info.audio, let expected = truth.audio {
            #expect(audio.sampleRate == expected.sampleRate && audio.channels == expected.channels)
        }
    }

    @Test("the set has HEVC and H.264, HDR, both orientations, 24 to 240 fps and an unsupported codec")
    func setCoverage() throws {
        let truths = try Self.catalog.truths(inSet: "import")
        #expect(Set(truths.map(\.video.codec)).isSuperset(of: ["h264", "hevc"]))
        #expect(truths.contains { $0.video.hdr != nil })
        #expect(Set(truths.map(\.video.orientation)) == ["landscape", "portrait"])
        #expect(truths.contains { $0.video.rotationDegrees == 90 })
        let rates = Set(truths.map { $0.video.frameRate.frameRate })
        #expect(rates.isSuperset(of: [FrameRate(frames: 24), .fps30, .fps60, .fps240, FrameRate(frames: 30000, perSeconds: 1001)]))
        #expect(truths.contains { !$0.video.supported })
    }

    @Test("the duplicate pair is byte-identical under two names")
    func duplicatePair() throws {
        let truths = try Self.catalog.truths(inSet: "import")
        let copies = truths.filter { $0.duplicateOf != nil }
        #expect(!copies.isEmpty)
        for copy in copies {
            let original = try Self.catalog.truth(id: try #require(copy.duplicateOf))
            let a = try Data(contentsOf: try Self.catalog.mediaURL(for: original))
            let b = try Data(contentsOf: try Self.catalog.mediaURL(for: copy))
            #expect(original.media.path != copy.media.path)
            #expect(SHA256.hash(data: a) == SHA256.hash(data: b))
        }
    }
}
