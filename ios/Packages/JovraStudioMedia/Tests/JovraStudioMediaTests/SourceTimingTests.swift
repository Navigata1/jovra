import CoreMedia
import Foundation
import JovraCore
import JovraStudioCore
import JovraStudioMedia
import Testing

/// Smoke test for the package (S04): it links JovraStudioCore, JovraMedia and CoreMedia together and agrees with the
/// shared Sample source manifest. Real ingest and manifests arrive with the Studio media tickets.
@Suite("Studio source timing")
struct SourceTimingTests {
    private struct Manifest: Decodable {
        struct Source: Decodable {
            struct Original: Decodable {
                struct Rate: Decodable { let num: Int; let den: Int }
                let durationUs: Int64
                let frameCount: Int
                let nominalFps: Rate
            }
            let sourceId: String
            let original: Original
        }
        let sources: [Source]
    }

    @Test("every Sample source ends exactly at its stated duration: frameCount frames at the nominal rate, no rounding")
    func nominalEndMatchesManifestDuration() throws {
        let data = try StudioFixtures.data("records/source-manifest.json")
        #expect(try StudioRecordHeader(json: data).schemaVersion == StudioSchemaVersion(kind: "source-manifest", version: 1))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        #expect(manifest.sources.count == 5)

        for source in manifest.sources {
            let original = source.original
            let rate = FrameRate(frames: original.nominalFps.num, perSeconds: original.nominalFps.den)
            let end = StudioSourceTiming.nominalEnd(frameCount: original.frameCount, at: rate)
            let stated = CMTime(value: original.durationUs, timescale: 1_000_000)

            #expect(CMTimeCompare(end, stated) == 0, Comment(rawValue: "\(source.sourceId): \(end.seconds) s vs \(stated.seconds) s"))
        }
    }

    @Test("an NTSC source keeps its exact rational end: 30 frames at 30000/1001 fps end at 1.001 s")
    func ntscEndIsExact() {
        let end = StudioSourceTiming.nominalEnd(frameCount: 30, at: FrameRate(frames: 30000, perSeconds: 1001))

        #expect(CMTimeCompare(end, CMTime(value: 1001, timescale: 1000)) == 0)
    }
}
