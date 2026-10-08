import AVFoundation
import JovraBenchmark
import Testing

/// The committed `decodedFramesSha256` was computed by the renderer from ffmpeg's decode. AVFoundation must
/// decode every supported clip to the same frame signatures, frame for frame: no dropped, repeated or
/// reordered frames, and the same picture in every cell.
@Suite("AVFoundation decodes every supported fixture to its committed signature hash")
struct DecodedFrameHashTests {
    static let catalog = MediaFixtureCatalog.repository()

    static var supportedIDs: [String] {
        ((try? catalog.allTruths()) ?? []).filter(\.video.supported).map(\.id)
    }

    @Test("decoded-frame signature hash equals the ground truth", arguments: supportedIDs)
    func signatureMatches(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let decoded = try await DecodedFrameReader.signatureHash(of: try Self.catalog.mediaURL(for: truth), truth: truth)
        #expect(decoded.frames == truth.signature.frameCount)
        #expect(decoded.sha256 == truth.signature.decodedFramesSha256)
    }

    @Test("every clip burns in its own frame index", arguments: supportedIDs)
    func frameCodesCount(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let frames = try await DecodedFrameReader.frames(of: try Self.catalog.mediaURL(for: truth), truth: truth)
        #expect(frames.map(\.code) == Array(0..<truth.video.frameCount))
    }

    @Test("the fixture set covers capture, playback, import and the harness")
    func setsPresent() throws {
        let sets = Set(try Self.catalog.allTruths().map(\.set))
        #expect(sets.isSuperset(of: ["fixtureCamera", "frameCounter", "harness", "import"]))
    }
}
