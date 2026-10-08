import Foundation
import JovraCore
import JovraMedia
import Testing

/// MediaProbe on Jon's private phone originals and excerpts (docs/fixtures/real-footage.md). The files are
/// never in the repository or CI; each test is skipped, with the reason, when its file is absent. Set
/// JOVRA_REAL_MEDIA_DIR (originals) and JOVRA_EXCERPTS_DIR (excerpts) to point elsewhere.
@Suite("MediaProbe on private real footage (skipped when absent)")
struct RealFootageProbeTests {
    static let environment = ProcessInfo.processInfo.environment
    static let originals = URL(fileURLWithPath: environment["JOVRA_REAL_MEDIA_DIR"] ?? "/Volumes/Backup Plus/JOVRA-media/old-match")
    static let excerpts = URL(fileURLWithPath: environment["JOVRA_EXCERPTS_DIR"] ?? "/Users/IDC2.5/JOVRA-media/excerpts")

    static func present(_ url: URL) -> Bool { FileManager.default.isReadableFile(atPath: url.path) }

    static let sep29 = originals.appendingPathComponent("20260929_170141.mp4")
    static let oct04 = originals.appendingPathComponent("20261004_125549.mp4")
    static let excerpt = excerpts.appendingPathComponent("match-feb2024-14m00s-2min-720p30.mp4")

    /// Android 13 HEVC originals: ~30 fps variable frame rate (ffprobe r_frame_rate 30/1, average 29.98).
    @Test("Sep 29 phone original: 30 fps, variable frame rate",
          .enabled(if: present(sep29), "real footage absent: 20260929_170141.mp4 (set JOVRA_REAL_MEDIA_DIR)"))
    func sep29Original() async throws {
        let video = try #require(try await MediaProbe.probe(Self.sep29).video)
        #expect(video.codec == .hevc)
        #expect(video.frameRate == .fps30)
        #expect(video.isVariableFrameRate)
    }

    @Test("Oct 4 phone original: 30 fps, variable frame rate",
          .enabled(if: present(oct04), "real footage absent: 20261004_125549.mp4 (set JOVRA_REAL_MEDIA_DIR)"))
    func oct04Original() async throws {
        let video = try #require(try await MediaProbe.probe(Self.oct04).video)
        #expect(video.codec == .hevc)
        #expect(video.frameRate == .fps30)
        #expect(video.isVariableFrameRate)
    }

    @Test("constant-frame-rate excerpt: 30 fps, constant",
          .enabled(if: present(excerpt), "real footage absent: match-feb2024-14m00s-2min-720p30.mp4 (set JOVRA_EXCERPTS_DIR)"))
    func cfrExcerpt() async throws {
        let video = try #require(try await MediaProbe.probe(Self.excerpt).video)
        #expect(video.frameRate == .fps30)
        #expect(!video.isVariableFrameRate)
    }
}
