@preconcurrency import AVFoundation
import Foundation
import JovraBenchmark
import JovraCore
@testable import JovraMedia
import Testing
import XCTest

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("jovra-proxy-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Short-GOP proxy", .serialized)
struct ShortGOPProxyTests {
    let catalog = MediaFixtureCatalog.repository()

    /// Every proxy frame keeps the original's presentation time and shows the original's frame code,
    /// and every sample is a sync sample, so a backward step never decodes a run of earlier frames.
    @Test
    func theProxyIsIntraOnlyAndFrameForFrameTheOriginal() async throws {
        let truth = try catalog.truth(id: "frameCounter/fc-240")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let proxy = try await ShortGOPProxy.build(from: catalog.mediaURL(for: truth),
                                                  into: directory, frameRate: .fps240)
        #expect(proxy.frameCount == truth.video.frameCount)
        let asset = AVURLAsset(url: proxy.url)
        let reader = try AVAssetReader(asset: asset)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        reader.add(output)
        #expect(reader.startReading())
        var index = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            #expect(CMSampleBufferGetPresentationTimeStamp(sample).frameIndex(at: .fps240) == index)
            #expect(try FrameCode.read(from: LumaPlane(pixelBuffer: buffer), truth: truth) == index)
            index += 1
        }
        #expect(index == truth.video.frameCount)
        let rawAsset = AVURLAsset(url: proxy.url)
        let raw = try AVAssetReader(asset: rawAsset)
        let rawTrack = try #require(try await rawAsset.loadTracks(withMediaType: .video).first)
        let rawOutput = AVAssetReaderTrackOutput(track: rawTrack, outputSettings: nil)
        raw.add(rawOutput)
        #expect(raw.startReading())
        var nonSync = 0
        while let sample = rawOutput.copyNextSampleBuffer() {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
            if attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool == true { nonSync += 1 }
        }
        #expect(nonSync == 0)
    }

    /// Decoding through the stepper (AVAssetImageGenerator on the proxy file) must give back the asked-for frame
    /// for every frame, not only the reader's timestamps: the movie timescale is part of the contract.
    @Test(arguments: ["frameCounter/fc-060", "frameCounter/fc-240"])
    func everyProxyFrameDecodesAsItself(id: String) async throws {
        let truth = try catalog.truth(id: id)
        let rate = truth.video.frameRate.frameRate
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stepper = try await ProxyBackwardStepper.prepare(original: catalog.mediaURL(for: truth), frameRate: rate,
                                                             proxyDirectory: directory, expectedFrameCount: truth.video.frameCount)
        for index in stride(from: truth.video.frameCount - 1, through: 0, by: -1) {
            let frame = try await stepper.frame(at: index)
            #expect(frame.index == index)
            #expect(try FrameCode.read(from: LumaPlane(image: frame.image), truth: truth) == index)
        }
    }

    @Test
    @MainActor
    func aSlowBackwardStepStartsTheProxyAndLaterBackwardStepsUseIt() async throws {
        let truth = try catalog.truth(id: "frameCounter/fc-240")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try await PlaybackController.open(url: catalog.mediaURL(for: truth), proxyDirectory: directory,
                                                           slowBackwardStep: .zero)
        defer { controller.close() }
        #expect(controller.proxyState == .none)
        await controller.seek(toFrame: 400, precision: .exact)
        await controller.step(byCount: -1)
        await controller.waitForProxy()
        #expect(controller.proxyState == .ready, "a backward step slower than the threshold builds the proxy")
        await controller.step(byCount: -1)
        #expect(controller.currentFrame == 398)
        let still = try #require(controller.still, "with the proxy ready a backward step shows its exact proxy frame")
        #expect(still.index == 398)
        #expect(try FrameCode.read(from: LumaPlane(image: still.image), truth: truth) == 398)
        await controller.settle()
        for _ in 0..<100 where controller.still != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.still == nil, "the still clears once the original has caught up on the same frame")
        let cached = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try #require(cached.count == 1)
        let published = try Data(contentsOf: cached[0])
        controller.close()
        #expect(try Data(contentsOf: cached[0]) == published, "Closing after handoff retains the committed proxy")
    }

    @Test(arguments: [false, true])
    @MainActor
    func aNewPositionNeverShowsTheOldBackwardStepStill(scrub: Bool) async throws {
        let truth = try catalog.truth(id: "frameCounter/fc-240")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try await PlaybackController.open(url: catalog.mediaURL(for: truth), proxyDirectory: directory)
        defer { controller.close() }
        let displayed = DisplayedFrame(controller, truth: truth)
        await controller.buildProxy()
        try #require(controller.proxyState == .ready)
        await controller.seek(toFrame: 400)
        await controller.step(byCount: -1)
        let oldStill = try #require(controller.still)
        #expect(try FrameCode.read(from: LumaPlane(image: oldStill.image), truth: truth) == 399)

        let expected = scrub ? 410 : 400
        if scrub {
            controller.scrub(toFrame: expected)
            await controller.endScrub(atFrame: expected)
        } else {
            await controller.step(byCount: 1)
        }
        await controller.settle()
        #expect(controller.readout.frame == expected)
        #expect(controller.still == nil, "The old proxy still must not cover the newly selected frame")
        #expect(try await displayed.code(controller) == expected)
    }

    @Test
    @MainActor
    func closingDuringProxyBuildDoesNotPublishOrLeaveTemporaryMedia() async throws {
        let truth = try catalog.truth(id: "frameCounter/fc-240")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try await PlaybackController.open(url: catalog.mediaURL(for: truth), proxyDirectory: directory)
        defer { controller.close() }
        let build = Task { await controller.buildProxy() }
        for _ in 0..<100 where controller.proxyState == .none { try await Task.sleep(for: .milliseconds(1)) }
        try #require(controller.proxyState == .building, "Close while the actual proxy encoder is pending")
        controller.close()
        await build.value
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty,
                "Closing before publication must leave neither a final proxy nor a partial copy")
    }

    @Test
    @MainActor
    func closingBeforeProxyHandoffDiscardsEvenAFinishedEncode() async throws {
        let truth = try catalog.truth(id: "frameCounter/fc-240")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try await PlaybackController.open(url: catalog.mediaURL(for: truth), proxyDirectory: directory)
        defer { controller.close() }
        let gate = ProxyHandoffGate()
        controller.beforeProxyHandoff = { await gate.hold($0) }
        defer { gate.release() }
        let build = Task { await controller.buildProxy() }
        let deadline = ContinuousClock.now + .seconds(5)
        while gate.partial == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let partial = try #require(gate.partial, "The real detached encode reached its handoff")
        let writerDirectory = partial.deletingLastPathComponent()
        let systemTemporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        #expect(writerDirectory.deletingLastPathComponent().path == systemTemporary.path)
        try #require(try hasCompleteMovieAtom(in: partial))
        #expect(controller.proxyState == .building)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        controller.close()
        gate.release()
        await build.value
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(!FileManager.default.fileExists(atPath: writerDirectory.path))
    }

    /// The same budget measured end to end on the controller (readout and displayed still updated).
    @Test
    @MainActor
    func controllerBackwardStepsWithTheProxyAverageUnder100ms() async throws {
        let truth = try catalog.truth(id: "frameCounter/fc-240")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = try await PlaybackController.open(url: catalog.mediaURL(for: truth), proxyDirectory: directory)
        defer { controller.close() }
        let displayed = DisplayedFrame(controller, truth: truth)
        await controller.buildProxy()
        #expect(controller.proxyState == .ready)
        await controller.seek(toFrame: 470, precision: .exact)
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            for _ in 0..<50 { await controller.step(byCount: -1) }
        }
        let average = elapsed / 50
        print("controller proxy backward step average:", average)
        #expect(average < .milliseconds(100))
        #expect(controller.currentFrame == 420)
        #expect(controller.proxyState == .ready, "every step used the proxy; none fell back")
        if let still = controller.still { #expect(try FrameCode.read(from: LumaPlane(image: still.image), truth: truth) == 420) }
        await controller.settle()
        #expect(try await displayed.code(controller) == 420, "the original caught up on the same frame")
    }
}

/// AVAssetWriter finishes this MOV by appending a complete top-level movie atom.
private func hasCompleteMovieAtom(in url: URL) throws -> Bool {
    let bytes = try Data(contentsOf: url)
    var offset = 0
    while bytes.count - offset >= 8 {
        let size = bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        guard size >= 8, size <= bytes.count - offset else { return false }
        if bytes[(offset + 4)..<(offset + 8)].elementsEqual("moov".utf8) { return true }
        offset += size
    }
    return false
}

@MainActor
private final class ProxyHandoffGate {
    private(set) var partial: URL?
    private var pending: CheckedContinuation<Void, Never>?

    func hold(_ partial: URL) async {
        self.partial = partial
        await withCheckedContinuation { pending = $0 }
    }

    func release() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}

/// The AC's timing gate: XCTClockMetric over 50 backward steps on the 240 fps fixture, after the proxy is built.
/// The measured path is the stepper PlaybackController uses for every backward step once its proxy is ready.
final class ProxyBackwardStepTimingTests: XCTestCase {
    static let budget: Duration = .milliseconds(100)

    func testBackwardStepsWithTheProxyAverageUnder100ms() throws {
        let catalog = MediaFixtureCatalog.repository()
        let truth = try catalog.truth(id: "frameCounter/fc-240")
        let url = try catalog.mediaURL(for: truth)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stepper = try runBlocking { try await ProxyBackwardStepper.prepare(original: url, frameRate: .fps240,
                                                                               proxyDirectory: directory) }
        var averages: [Duration] = []
        var landed: [Int] = []
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            let outcome = Result { try runBlocking({ () async throws -> (Duration, Int) in
                let clock = ContinuousClock()
                var frame: PlaybackFrame?
                let elapsed = try await clock.measure {
                    for index in stride(from: 469, through: 420, by: -1) { frame = try await stepper.frame(at: index) }
                }
                return (elapsed, try FrameCode.read(from: LumaPlane(image: frame!.image), truth: truth))
            }) }
            guard case .success(let (elapsed, last)) = outcome else { XCTFail("\(outcome)"); return }
            averages.append(elapsed / 50)
            landed.append(last)
        }
        XCTAssertEqual(averages.count, 6, "XCTest runs one warm-up plus five measured iterations")
        let milliseconds = averages.map { Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15 }
        print("proxy backward step average per iteration (ms):", milliseconds.map { String(format: "%.2f", $0) })
        XCTAssertLessThan(averages.max() ?? .seconds(1), Self.budget)
        XCTAssertEqual(Set(landed), [420], "50 steps back from 470 decode frame 420")
    }
}

/// Runs async work from a synchronous XCTest `measure` block (never on the main actor, so nothing deadlocks).
func runBlocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, any Error>!
    Task.detached {
        do { result = .success(try await work()) } catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}
