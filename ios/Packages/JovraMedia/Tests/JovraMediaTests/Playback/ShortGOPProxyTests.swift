@preconcurrency import AVFoundation
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
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
