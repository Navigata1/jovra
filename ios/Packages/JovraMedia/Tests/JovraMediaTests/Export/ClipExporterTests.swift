import AVFoundation
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

@Suite("Local clip export", .serialized)
struct ClipExporterTests {
    static let catalog = MediaFixtureCatalog.repository()

    @Test(arguments: ["frameCounter/fc-060", "frameCounter/fc-240"])
    func decodedRangeMatchesChosenFrames(id: String) async throws {
        let truth = try Self.catalog.truth(id: id)
        let rate = truth.video.frameRate.frameRate
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("clip.mp4")
        let start = CMTime(frame: 17, at: rate), end = CMTime(frame: 47, at: rate)
        let result = try await ClipExporter.exportClip(source: Self.catalog.mediaURL(for: truth),
            range: CMTimeRange(start: start, end: end), destination: target)
        let frames = try await DecodedFrameReader.frames(of: target, truth: truth)
        #expect(frames.first?.code == 17)
        #expect(frames.last?.code == 46)
        #expect(frames.count == 30)
        #expect(result.videoFrames == frames.count)
        #expect(abs(result.duration.seconds - CMTimeSubtract(end, start).seconds) <= 1 / rate.framesPerSecond)
        #expect(try await AVURLAsset(url: target).loadTracks(withMediaType: .audio).isEmpty)
        try retain(target, name: id.replacingOccurrences(of: "/", with: "-") + ".mp4")
    }

    @Test(arguments: [false, true])
    func audioIsOmittedUnlessExplicitlyIncluded(include: Bool) async throws {
        let truth = try Self.catalog.truth(id: "fixtureCamera/fixture-camera")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("clip.mp4")
        let result = try await ClipExporter.exportClip(source: Self.catalog.mediaURL(for: truth),
            range: CMTimeRange(start: CMTime(value: 1, timescale: 1), duration: CMTime(value: 1, timescale: 1)),
            destination: target, includeAudio: include)
        let audio = try await AVURLAsset(url: target).loadTracks(withMediaType: .audio)
        #expect(audio.isEmpty == !include)
        #expect(result.includesAudio == !audio.isEmpty)
        try retain(target, name: include ? "audio-on.mp4" : "audio-off.mp4")
    }

    @Test func capturedFragmentedVideoExportsACompleteLocalRange() async throws {
        let truth = try Self.catalog.truth(id: "fixtureCamera/fixture-camera")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: try Self.catalog.mediaURL(for: truth), duration: CMTime(value: 2, timescale: 1), clock: clock)
        let engine = CaptureEngine(source: camera, clock: clock, sink: ClipCaptureSink())
        _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .granted)
        try await engine.start(sessionID: "clip-offset", folder: directory)
        try await camera.waitUntilFinished()
        let recording = try await engine.stop()
        let source = directory.appendingPathComponent(try #require(recording.segments.first).file.path)
        // AVFoundation applies the source edit list: its track start can be zero even when
        // ffprobe reports a positive mux timestamp. Assert the exported media, not that assumption.
        let target = directory.appendingPathComponent("offset-clip.mp4")
        let result = try await ClipExporter.exportClip(source: source,
            range: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), destination: target)
        #expect(result.videoFrames == 30)
        #expect(abs(result.duration.seconds - 1) <= 1.0 / 30)
        try retain(source, name: "captured-offset-source.mp4")
        try retain(target, name: "captured-offset-clip.mp4")
    }

    @Test func invalidRangeAndExistingDestinationPreserveBytes() async throws {
        let truth = try Self.catalog.truth(id: "fixtureCamera/fixture-camera")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("existing.mp4")
        let original = Data("existing export stays intact".utf8)
        try original.write(to: target)
        await #expect(throws: (any Error).self) {
            _ = try await ClipExporter.exportClip(source: Self.catalog.mediaURL(for: truth),
                range: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), destination: target)
        }
        #expect(try Data(contentsOf: target) == original)
        let missing = directory.appendingPathComponent("invalid.mp4")
        await #expect(throws: (any Error).self) {
            _ = try await ClipExporter.exportClip(source: Self.catalog.mediaURL(for: truth),
                range: CMTimeRange(start: .zero, duration: .zero), destination: missing)
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["existing.mp4"])
    }

    private func retain(_ url: URL, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["JOVRA_CLIP_OUTPUT_DIR"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
    }
}

private actor ClipCaptureSink: RecordingSink {
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {}
}
