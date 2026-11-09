@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import JovraBenchmark
import JovraCore
@testable import JovraMedia
import Testing

@MainActor
@Suite("Playback outcomes after an interrupted seek", .serialized)
struct PlaybackSeekOutcomeTests {
    private enum DecodeError: Error { case refused }
    private let catalog = MediaFixtureCatalog.repository()

    private func open(proxyDirectory: URL? = nil) async throws -> (PlaybackController, GroundTruth) {
        let truth = try catalog.truth(id: "frameCounter/fc-060")
        let controller = try await PlaybackController.open(url: try catalog.mediaURL(for: truth),
                                                            proxyDirectory: proxyDirectory)
        return (controller, truth)
    }

    @Test(arguments: [false, true])
    func refusedOriginalAndUnavailableProxyKeepTheActualFrame(cancelled: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (controller, truth) = try await open(proxyDirectory: directory)
        defer { controller.close() }
        let displayed = DisplayedFrame(controller, truth: truth)
        await controller.buildProxy()
        try #require(controller.proxyState == .ready)
        await controller.seek(toFrame: 30)
        try #require(try await displayed.code(controller) == 30)
        controller.seekPlayer = { _, _, _ in false }
        controller.decodeProxyFrame = { _, _ in
            if cancelled { throw CancellationError() }
            throw DecodeError.refused
        }

        await controller.step(byCount: -1)
        await controller.settle()
        #expect(controller.still == nil)
        #expect(try await displayed.code(controller) == 30)
        #expect(controller.readout.frame == 30)
        #expect(controller.proxyState == (cancelled ? .ready : .failed))
    }

    @Test
    func aLaterLandingOutsideTheLoopDoesNotAuthorizeAnInterruptedRestart() async throws {
        let (controller, _) = try await open()
        defer { controller.close() }
        await controller.seek(toFrame: 30)
        let loop = try #require(FrameLoop(start: 20, end: 40, frameCount: controller.frameCount))
        controller.setLoop(loop)
        await controller.seek(toFrame: 5)
        let gate = GatedOriginalSeek(frame: 20)
        controller.seekPlayer = { await gate.perform($0, time: $1, tolerance: $2) }
        defer { gate.finish(false) }

        controller.play()
        try await waitUntil("restart seek in flight") { gate.isWaiting }
        let later = Task { await controller.seek(toFrame: 50) }
        try await waitUntil("later target queued") { controller.currentFrame == 50 }
        gate.finish(false)
        await later.value
        try await waitUntil("restart disposition") { controller.player.rate > 0 || !controller.isPlaying }

        #expect(controller.player.rate == 0)
        #expect(!controller.isPlaying)
        #expect(controller.readout.frame == 50)
        #expect(controller.player.currentTime().frameIndex(at: .fps60) == 50)
    }

    @Test
    func failedActiveLoopPositioningStopsOutsideTheLoop() async throws {
        let (controller, _) = try await open()
        defer { controller.close() }
        await controller.seek(toFrame: 5)
        try #require(controller.setRate(.quarter))
        controller.play()
        try await waitUntil("actual AVPlayer play") { controller.player.rate > 0 }
        let gate = GatedOriginalSeek(frame: 80)
        controller.seekPlayer = { await gate.perform($0, time: $1, tolerance: $2) }
        defer { gate.finish(false) }

        let loop = try #require(FrameLoop(start: 80, end: 100, frameCount: controller.frameCount))
        controller.setLoop(loop)
        try await waitUntil("loop position seek in flight") { gate.isWaiting }
        gate.finish(false)
        await controller.settle()
        // At quarter speed the media cannot reach the loop before this bounded check.
        let deadline = ContinuousClock.now + .milliseconds(250)
        while controller.isPlaying, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(controller.player.rate == 0)
        #expect(!controller.isPlaying)
        let actual = controller.player.currentTime().frameIndex(at: .fps60)
        #expect(actual < 80)
        #expect(controller.readout.frame == actual)
    }

    @Test
    func successfulActiveLoopPositioningResumesInsideTheLoop() async throws {
        let (controller, _) = try await open()
        defer { controller.close() }
        await controller.seek(toFrame: 5)
        try #require(controller.setRate(.quarter))
        controller.play()
        try await waitUntil("actual AVPlayer play") { controller.player.rate > 0 }
        let loop = try #require(FrameLoop(start: 80, end: 100, frameCount: controller.frameCount))

        controller.setLoop(loop)
        try await waitUntil("positioned playback") {
            controller.player.rate > 0 && loop.contains(controller.player.currentTime().frameIndex(at: .fps60))
        }
        #expect(controller.isPlaying)
        #expect(loop.contains(controller.readout.frame))
    }

    @Test
    func clearingPendingLoopPositioningLeavesTruthfulPausedState() async throws {
        let (controller, gate) = try await gatedLoopPositioning()
        defer { controller.close() }
        controller.setLoop(nil)
        gate.finish(false)
        await controller.settle()
        let actual = controller.player.currentTime().frameIndex(at: .fps60)
        #expect(controller.loop == nil)
        #expect(!controller.isPlaying)
        #expect(controller.player.rate == 0)
        #expect(controller.readout.frame == actual)
    }

    @Test
    func aNewerSeekSupersedesPendingLoopResume() async throws {
        let (controller, gate) = try await gatedLoopPositioning()
        defer { gate.finish(false); controller.close() }
        let newer = Task { await controller.seek(toFrame: 60) }
        try await waitUntil("replacement target queued") { controller.readout.frame == 60 }
        gate.finish(false)
        await newer.value
        #expect(!controller.isPlaying)
        #expect(controller.player.rate == 0)
        #expect(controller.readout.frame == 60)
        #expect(controller.player.currentTime().frameIndex(at: .fps60) == 60)
    }

    @Test
    func aRateChangeWaitsForSuccessfulLoopPositioning() async throws {
        let (controller, gate) = try await gatedLoopPositioning()
        defer { gate.finish(false); controller.close() }
        #expect(controller.setRate(.half))
        #expect(controller.player.rate == 0)
        #expect(!controller.isPlaying)
        gate.finish(true)
        try await waitUntil("positioned half-speed playback") { controller.player.rate == 0.5 }
        #expect(controller.isPlaying)
        #expect((80...100).contains(controller.player.currentTime().frameIndex(at: .fps60)))
    }

    @Test
    func aFailedFinalScrubRestoresThePlayerFrameAndCanRetryTheSameTarget() async throws {
        let (controller, truth) = try await open()
        defer { controller.close() }
        await controller.seek(toFrame: 12)
        let displayed = DisplayedFrame(controller, truth: truth)
        try #require(try await displayed.code(controller) == 12)
        let gate = GatedOriginalSeek(frame: 42)
        controller.seekPlayer = { await gate.perform($0, time: $1, tolerance: $2) }
        defer { gate.finish(false) }

        controller.finishScrub(atFrame: 42)
        try await waitUntil("exact gesture target in flight") { gate.isWaiting }
        #expect(controller.readout.frame == 42)
        gate.finish(false)
        try await waitUntil("failed target reconciles") { controller.readout.frame == 12 }
        #expect(try await displayed.code(controller) == 12)

        controller.finishScrub(atFrame: 42)
        try await waitUntil("the identical exact target is retried") { gate.isWaiting }
        gate.finish(true)
        await controller.settle()
        #expect(controller.readout.frame == 42)
        #expect(try await displayed.code(controller) == 42)
    }

    @Test
    func aLaterDragSupersedesAnEarlierFinalScrubInGestureOrder() async throws {
        let (controller, truth) = try await open()
        defer { controller.close() }
        let gate = GatedOriginalSeek(frame: 25)
        var issued: [Int] = []
        controller.seekPlayer = { player, time, tolerance in
            issued.append(time.frameIndex(at: .fps60))
            return await gate.perform(player, time: time, tolerance: tolerance)
        }
        defer { gate.finish(false) }

        controller.scrub(toFrame: 25)
        try await waitUntil("coarse seek in flight") { gate.isWaiting }
        controller.finishScrub(atFrame: 40)
        #expect(controller.readout.frame == 40)
        controller.scrub(toFrame: 50)
        gate.finish(false)
        await controller.settle()
        #expect(issued == [25, 50])
        #expect(controller.readout.frame == 50)

        await controller.endScrub(atFrame: 50)
        #expect(issued == [25, 50, 50])
        #expect(try await DisplayedFrame(controller, truth: truth).code(controller) == 50)
    }

    @Test
    func terminalCloseDropsQueuedFinalScrubsAndFencesTheirCompletion() async throws {
        let (controller, _) = try await open()
        defer { controller.close() }
        await controller.seek(toFrame: 12)
        let gate = GatedOriginalSeek(frame: 42)
        var returnedFrames: [Int] = []
        controller.seekPlayer = { player, time, tolerance in
            let succeeded = await gate.perform(player, time: time, tolerance: tolerance)
            returnedFrames.append(time.frameIndex(at: .fps60))
            return succeeded
        }
        defer { gate.finish(false) }

        controller.finishScrub(atFrame: 42)
        try await waitUntil("exact gesture target in flight") { gate.isWaiting }
        controller.finishScrub(atFrame: 56)
        controller.close()
        let closedFrame = controller.readout.frame
        let closedTime = controller.player.currentTime()
        let closedIssued = controller.seeksIssued
        gate.finish(false)

        controller.finishScrub(atFrame: 74)
        await controller.endScrub(atFrame: 86)
        await controller.settle()
        try await waitUntil("the rejected original seek actually returned after close") { !returnedFrames.isEmpty }
        #expect(returnedFrames == [42])
        #expect(closedFrame == 56)
        #expect(controller.readout.frame == closedFrame)
        #expect(controller.player.currentTime() == closedTime)
        #expect(controller.seeksIssued == closedIssued)
        #expect(controller.player.rate == 0)
    }

    private func gatedLoopPositioning() async throws -> (PlaybackController, GatedOriginalSeek) {
        let (controller, _) = try await open()
        let gate = GatedOriginalSeek(frame: 80)
        do {
            await controller.seek(toFrame: 5)
            try #require(controller.setRate(.quarter))
            controller.play()
            try await waitUntil("actual AVPlayer play") { controller.player.rate > 0 }
            controller.seekPlayer = { await gate.perform($0, time: $1, tolerance: $2) }
            let loop = try #require(FrameLoop(start: 80, end: 100, frameCount: controller.frameCount))
            controller.setLoop(loop)
            try await waitUntil("loop position seek in flight") { gate.isWaiting }
            return (controller, gate)
        } catch {
            gate.finish(false)
            controller.close()
            throw error
        }
    }

    private func waitUntil(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition(), Comment(rawValue: label))
    }
}

@MainActor
private final class GatedOriginalSeek {
    let frame: Int
    private var pending: CheckedContinuation<Bool, Never>?
    var isWaiting: Bool { pending != nil }

    init(frame: Int) { self.frame = frame }

    func perform(_ player: AVPlayer, time: CMTime, tolerance: CMTime) async -> Bool {
        if time.frameIndex(at: .fps60) == frame {
            let allowed = await withCheckedContinuation { pending = $0 }
            guard allowed else { return false }
        }
        return await player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func finish(_ succeeded: Bool) {
        let gate = pending
        pending = nil
        gate?.resume(returning: succeeded)
    }
}
