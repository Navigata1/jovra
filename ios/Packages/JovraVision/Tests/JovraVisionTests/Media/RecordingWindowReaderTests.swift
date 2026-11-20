import Foundation
import JovraCore
import JovraVision
import Testing

/// V00 on real decoding: the synthetic sample video the simulator fixture camera streams
/// (`spec/fixtures/media/fixtureCamera`: 12 s, 1280×720 at 30 fps, 48 kHz mono AAC), read window by window.
@Suite(.serialized) struct RecordingWindowReaderTests {
    @Test func everyFrameIsReadOnceInItsWindowAtItsSessionTime() async throws {
        let reader = try await Fixture.reader(startMs: 0)
        let windows = AnalysisRunner.plan(500, over: reader.info.segments)
        #expect(windows.count == 24)
        var times: [Int64] = []
        for window in windows {
            for try await frame in reader.frames(in: window) {
                #expect(frame.time.timescale == 1_000_000)
                #expect(frame.time.value >= Int64(window.startMs) * 1000 && frame.time.value < Int64(window.endMs) * 1000)
                #expect(frame.width == 1280 && frame.height == 720)
                times.append(frame.time.value)
            }
        }
        #expect(times.count == 360, "the truth's frame count")
        #expect(times.first == 0)
        #expect(times[30] == 1_000_000, "frame 30 at 1 s")
        #expect(times == times.sorted() && Set(times).count == times.count)
    }

    @Test func framesSitOnTheSessionTimelineAfterTheSegmentStart() async throws {
        let reader = try await Fixture.reader(startMs: 4000)
        #expect(reader.info.segments == [AnalysisSegment(startMs: 4000, durationMs: 12000)])
        let window = AnalysisWindow(index: 0, segment: 0, startMs: 5000, endMs: 5100)
        var times: [Int64] = []
        for try await frame in reader.frames(in: window) { times.append(frame.time.value) }
        #expect(times == [5_000_000, 5_033_333, 5_066_667], "frames 30–32 of the clip, 4 s later")
    }

    @Test func aWindowReadOutOfOrderDecodesTheSameFramesAsInOrder() async throws {
        let sequential = try await Fixture.reader(startMs: 0)
        let windows = AnalysisRunner.plan(500, over: sequential.info.segments)
        var inOrder: [Int64: Int] = [:]
        for window in windows.prefix(10) {
            for try await frame in sequential.frames(in: window) { inOrder[frame.time.value] = frame.meanLuma() }
        }
        let jumping = try await Fixture.reader(startMs: 0)
        var outOfOrder: [Int64: Int] = [:]
        for window in [windows[7], windows[2], windows[9], windows[0]] {
            for try await frame in jumping.frames(in: window) { outOfOrder[frame.time.value] = frame.meanLuma() }
        }
        #expect(outOfOrder.count == 60, "\(outOfOrder.keys.sorted())")
        for (time, luma) in outOfOrder { #expect(inOrder[time] == luma, "frame at \(time) µs") }
    }

    @Test func audioIsMonoFloatTrimmedToTheWindow() async throws {
        let reader = try await Fixture.reader(startMs: 0)
        let audio = try #require(try await reader.audio(in: AnalysisWindow(index: 2, segment: 0, startMs: 1000, endMs: 1500)))
        #expect(audio.sampleRate == 48_000)
        #expect(audio.start == (try MediaTime(value: 1_000_000, timescale: 1_000_000)))
        #expect(audio.samples.count == 24_000)
        #expect(audio.samples.allSatisfy { $0.isFinite && abs($0) <= 1.0001 })
    }

    @Test func theFixturePipelineKilledMidRunOnTheSampleVideoResumesToByteIdenticalOutputs() async throws {
        let reference = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: try await Fixture.reader(startMs: 0),
                                                 workspace: Workspace.make()).run()
        let luma = try JSONDecoder().decode(AnalysisStageOutput<FrameLuma>.self, from: try #require(reference.outputs["fixture.luma"]))
        #expect(luma.observations.count == 360)
        #expect(luma.coverage.analysed == [AnalysisRange(startMs: 0, endMs: 12000)])

        let workspace = Workspace.make()
        let dying = KillingReader(base: try await Fixture.reader(startMs: 0), killOnRequest: 9)
        await #expect(throws: SimulatedKill.self) {
            try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: dying, workspace: workspace).run()
        }
        // A new process: a new reader over the same file, the same workspace.
        let resumed = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: try await Fixture.reader(startMs: 0),
                                               workspace: workspace).run()
        #expect(resumed.resumes == [AnalysisResume(stage: "fixture.luma", fromWindow: 8, windows: 24)])
        #expect(resumed.outputs == reference.outputs)
    }

    @Test func theFingerprintChangesWithTheFile() async throws {
        let original = try await Fixture.reader(startMs: 0)
        let copy = Workspace.make().appendingPathExtension("mp4")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = try Data(contentsOf: Fixture.url())
        bytes.append(0)   // one more byte (an mp4 ignores trailing data)
        try bytes.write(to: copy)
        let changed = try await RecordingWindowReader.open([.init(url: copy, startMs: 0, durationMs: 12000)])
        #expect(changed.info.fingerprint != original.info.fingerprint)
        #expect(original.info.fingerprint == (try await Fixture.reader(startMs: 0)).info.fingerprint)
    }
}

/// Dies on its `killOnRequest`-th frame request, like a process killed in the middle of a window.
struct KillingReader: AnalysisWindowReader {
    var base: any AnalysisWindowReader
    var killOnRequest: Int
    let requests = Counter()
    var info: AnalysisMediaInfo { base.info }

    func frames(in window: AnalysisWindow) -> AsyncThrowingStream<AnalysisFrame, any Error> {
        guard requests.increment() != killOnRequest else {
            return AsyncThrowingStream { $0.finish(throwing: SimulatedKill()) }
        }
        return base.frames(in: window)
    }

    func audio(in window: AnalysisWindow) async throws -> AnalysisAudio? { try await base.audio(in: window) }
}

enum Fixture {
    /// The rendered fixture-camera clip. Rendered by `python3 scripts/media/render.py` (CI renders it first).
    static func url(filePath: String = #filePath) throws -> URL {
        var root = URL(fileURLWithPath: filePath)
        while root.path != "/", !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/media").path) {
            root.deleteLastPathComponent()
        }
        let truth = root.appendingPathComponent("spec/fixtures/media/fixtureCamera/fixture-camera.truth.json")
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: truth)) as? [String: Any]
        let path = try #require((document?["media"] as? [String: Any])?["path"] as? String)
        let url = root.appendingPathComponent(path)
        try #require(FileManager.default.fileExists(atPath: url.path),
                     "\(path) is not rendered. Run: python3 scripts/media/render.py --set fixtureCamera")
        return url
    }

    static func reader(startMs: Int) async throws -> RecordingWindowReader {
        try await RecordingWindowReader.open([.init(url: try url(), startMs: startMs, durationMs: 12000)])
    }
}
