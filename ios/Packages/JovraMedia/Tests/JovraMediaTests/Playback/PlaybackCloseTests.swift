@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import JovraBenchmark
import JovraCore
@testable import JovraMedia
import Testing

@MainActor
@Suite("Terminal playback close", .serialized)
struct PlaybackCloseTests {
    private let catalog = MediaFixtureCatalog.repository()

    private func fixtureURL() throws -> URL {
        try catalog.mediaURL(for: catalog.truth(id: "frameCounter/fc-060"))
    }

    @Test
    func closedTransportCannotRestartOrChangePosition() async throws {
        let controller = try await PlaybackController.open(url: fixtureURL())
        defer { controller.close() }
        await controller.seek(toFrame: 20)
        controller.play()
        try #require(await waitUntil { controller.player.rate > 0 }, "The real player started")
        controller.close()
        let frame = controller.readout.frame
        let issued = controller.seeksIssued
        let rate = controller.rate
        let itemTime = controller.player.currentTime()
        #expect(controller.player.rate == 0)

        controller.play()
        #expect(!controller.isPlaying)
        #expect(!controller.setRate(.double))
        await controller.seek(toFrame: 28)
        controller.scrub(toFrame: 30)
        await controller.endScrub(atFrame: 32)
        await controller.step(byCount: 1)
        await controller.skip(seconds: 1)
        let loop = try #require(FrameLoop(start: 35, end: 55, frameCount: controller.frameCount))
        controller.setLoop(loop)
        controller.togglePlayPause()
        await controller.settle()
        controller.close()

        #expect(!controller.isPlaying)
        #expect(controller.player.rate == 0)
        #expect(controller.rate == rate)
        #expect(controller.loop == nil)
        #expect(controller.readout.frame == frame)
        #expect(controller.player.currentTime() == itemTime)
        #expect(controller.seeksIssued == issued)
    }

    @Test
    func closeDropsQueuedSeekAndResolvesCallersBeforeLateCompletion() async throws {
        let controller = try await PlaybackController.open(url: fixtureURL())
        defer { controller.close() }
        let gate = HeldSeek()
        controller.seekPlayer = { _, time, _ in await gate.perform(time) }
        defer { gate.complete(true) }
        var firstReturned = false
        var queuedReturned = false
        let first = Task {
            await controller.seek(toFrame: 20)
            firstReturned = true
        }
        try #require(await waitUntil { gate.isWaiting }, "First seek issued to the system boundary")
        let queued = Task {
            await controller.seek(toFrame: 25)
            queuedReturned = true
        }
        try #require(await waitUntil { controller.readout.frame == 25 }, "Later request queued")
        let issued = controller.seeksIssued
        let itemTime = controller.player.currentTime()

        controller.close()
        #expect(await waitUntil { firstReturned && queuedReturned }, "Close releases both waiting calls")
        let closedFrame = controller.readout.frame
        gate.complete(true)
        await first.value
        await queued.value
        await controller.settle()

        #expect(gate.frames == [20])
        #expect(controller.seeksIssued == issued)
        #expect(controller.readout.frame == closedFrame)
        #expect(controller.player.currentTime() == itemTime)
        #expect(!controller.isPlaying)
    }

    @Test(arguments: [false, true])
    func failedOrCancelledReadinessLeavesAnInertController(cancelled: Bool) async throws {
        let url = try fixtureURL()
        let gate = HeldReadiness()
        defer { gate.release() }
        let opening = Task {
            try await PlaybackController.open(url: url) { controller in
                await gate.suspend(controller)
                try Task.checkCancellation()
                throw PlaybackOpenError.unreadable
            }
        }
        try #require(await waitUntil { gate.controller != nil }, "Readiness reached after controller allocation")
        let allocated = try #require(gate.controller)
        defer { allocated.close() }
        if cancelled { opening.cancel() }
        gate.release()
        switch await opening.result {
        case .success:
            Issue.record("Readiness must not yield a player")
        case .failure(let error):
            if cancelled {
                #expect(error is CancellationError)
            } else {
                #expect(error as? PlaybackOpenError == .unreadable)
            }
        }

        let frame = allocated.readout.frame
        let issued = allocated.seeksIssued
        allocated.play()
        #expect(!allocated.isPlaying)
        #expect(!allocated.setRate(.double))
        await allocated.seek(toFrame: 20)
        #expect(allocated.player.rate == 0)
        #expect(allocated.readout.frame == frame)
        #expect(allocated.seeksIssued == issued)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(300)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class HeldSeek {
    private var pending: CheckedContinuation<Bool, Never>?
    private(set) var frames: [Int] = []
    var isWaiting: Bool { pending != nil }

    func perform(_ time: CMTime) async -> Bool {
        frames.append(time.frameIndex(at: .fps60))
        guard frames.count == 1 else { return true }
        return await withCheckedContinuation { pending = $0 }
    }

    func complete(_ succeeded: Bool) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: succeeded)
    }
}


@MainActor
private final class HeldReadiness {
    private(set) var controller: PlaybackController?
    private var pending: CheckedContinuation<Void, Never>?

    func suspend(_ controller: PlaybackController) async {
        self.controller = controller
        await withCheckedContinuation { pending = $0 }
    }

    func release() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}
