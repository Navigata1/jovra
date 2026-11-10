import CoreMedia
import JovraMedia
import Testing

/// A fake seek that suspends until the test lets it finish, so the in-flight/queued behaviour is observable.
@MainActor
private final class GatedSeeks {
    var log: [ChaseSeeker.Request] = []
    private var gates: [CheckedContinuation<Bool, Never>] = []

    func perform(_ time: CMTime, _ precision: SeekPrecision) async -> Bool {
        log.append(.init(time: time, precision: precision))
        return await withCheckedContinuation { gates.append($0) }
    }

    var pending: Int { gates.count }

    func finishOne(succeeded: Bool = true) {
        guard !gates.isEmpty else { return }
        gates.removeFirst().resume(returning: succeeded)
    }
}

@MainActor
@Suite("Chase-time seeking")
struct ChaseSeekerTests {
    private func t(_ value: Int64) -> CMTime { CMTime(value: value, timescale: 60) }

    private func drain() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test
    func keepsOneSeekInFlightAndOnlyTheLatestQueuedTargetRuns() async {
        let seeks = GatedSeeks()
        let seeker = ChaseSeeker { await seeks.perform($0, $1) }
        seeker.submit(t(10), precision: .coarse)
        await drain()
        seeker.submit(t(20), precision: .coarse)
        seeker.submit(t(30), precision: .coarse)
        seeker.submit(t(40), precision: .exact)
        await drain()
        #expect(seeks.log.count == 1, "a second seek never starts while one is in flight")
        #expect(seeks.pending == 1)
        seeks.finishOne()
        await drain()
        #expect(seeks.log.map(\.time) == [t(10), t(40)], "intermediate drag targets are dropped, the last one runs")
        #expect(seeks.log.last?.precision == .exact)
        #expect(!seeker.isIdle)
        seeks.finishOne()
        await drain()
        #expect(seeker.isIdle)
        #expect(seeker.lastCompleted == .init(time: t(40), precision: .exact))
        #expect(seeker.issuedCount == 2)
    }

    @Test
    func failedExactSeekDoesNotLandOrSuppressAnIdenticalRetry() async {
        let time = t(5)
        var outcomes = [false, true]
        let playerSeek: ChaseSeeker.Perform = { _, _ in outcomes.removeFirst() }
        let seeker = ChaseSeeker(perform: playerSeek)
        let failed = await seeker.request(time, precision: .exact)
        #expect(!failed)
        #expect(seeker.isIdle)
        #expect(seeker.lastCompleted == nil)
        #expect(seeker.issuedCount == 1)

        let retried = await seeker.request(time, precision: .exact)
        #expect(retried)
        #expect(seeker.lastCompleted == .init(time: time, precision: .exact))
        #expect(seeker.issuedCount == 2)
        await seeker.request(time, precision: .exact)
        #expect(seeker.issuedCount == 2, "A successful identical seek is still deduplicated")
    }

    @Test
    func aQueuedIdenticalRequestIsIssuedAfterAnInterruptedSeek() async {
        let seeks = GatedSeeks()
        let seeker = ChaseSeeker { await seeks.perform($0, $1) }
        seeker.submit(t(7), precision: .exact)
        await drain()
        seeker.submit(t(7), precision: .exact)
        seeks.finishOne(succeeded: false)
        await drain()
        #expect(seeks.log.count == 2)
        #expect(seeker.lastCompleted == nil)
        #expect(!seeker.isIdle)
        seeks.finishOne()
        await seeker.settled()
        #expect(seeker.lastCompleted == .init(time: t(7), precision: .exact))
    }

    @Test
    func failureInvalidatesAPreviousLanding() async {
        var outcomes = [true, false, true]
        let seeker = ChaseSeeker { _, _ in outcomes.removeFirst() }
        let first = await seeker.request(t(7), precision: .exact)
        let interrupted = await seeker.request(t(8), precision: .exact)
        #expect(first)
        #expect(!interrupted)
        #expect(seeker.lastCompleted == nil)
        let restored = await seeker.request(t(7), precision: .exact)
        #expect(restored)
        #expect(seeker.issuedCount == 3)
    }

    @Test
    func requestReturnsOnlyAfterTheSeekerSettles() async {
        let seeks = GatedSeeks()
        let seeker = ChaseSeeker { await seeks.perform($0, $1) }
        var settled = false
        let waiter = Task { @MainActor in
            let landed = await seeker.request(t(5), precision: .exact)
            settled = true
            return landed
        }
        await drain()
        #expect(!settled)
        seeker.submit(t(6), precision: .exact)
        seeks.finishOne()
        await drain()
        #expect(!settled, "a request waits for the chased target too")
        seeks.finishOne()
        #expect(!(await waiter.value), "The superseded request cannot claim the later landing")
        #expect(settled)
        #expect(seeker.lastCompleted == .init(time: t(6), precision: .exact))
        #expect(seeks.log.map(\.time) == [t(5), t(6)])
    }

    @Test
    func closingBeforeDispatchNeverCallsTheBackend() async {
        var calls = 0
        let seeker = ChaseSeeker { _, _ in
            calls += 1
            return true
        }
        seeker.submit(t(5), precision: .exact)
        seeker.close()
        seeker.close()
        let landed = await seeker.request(t(6), precision: .exact)
        await drain()
        #expect(!landed)
        #expect(seeker.isIdle)
        #expect(seeker.lastCompleted == nil)
        #expect(seeker.issuedCount == 0)
        #expect(calls == 0)
    }

    @Test
    func anExactReleaseAfterACoarseDragToTheSameTimeStillRuns() async {
        let seeks = GatedSeeks()
        let seeker = ChaseSeeker { await seeks.perform($0, $1) }
        seeker.submit(t(7), precision: .coarse)
        seeker.submit(t(7), precision: .exact)
        await drain()
        seeks.finishOne()
        await drain()
        seeks.finishOne()
        await drain()
        #expect(seeks.log == [.init(time: t(7), precision: .coarse), .init(time: t(7), precision: .exact)])
        // Re-asking for a target that already landed exactly is a no-op.
        seeker.submit(t(7), precision: .exact)
        await drain()
        #expect(seeks.log.count == 2)
        #expect(seeker.isIdle)
    }
}

@Suite("Playback values")
struct PlaybackValueTests {
    @Test
    func ratesAreTheFourStudyRates() {
        #expect(PlaybackRate.allCases.map(\.value) == [0.25, 0.5, 1, 2])
        #expect(PlaybackRate.allCases.filter(\.isSlow) == [.quarter, .half])
    }

    @Test
    func loopNeedsTwoOrderedFramesInsideTheClip() {
        #expect(FrameLoop(start: 10, end: 20, frameCount: 120) != nil)
        #expect(FrameLoop(start: 20, end: 10, frameCount: 120)?.start == 10, "A and B are put in order")
        #expect(FrameLoop(start: 10, end: 10, frameCount: 120) == nil, "a one-frame loop is not a loop")
        #expect(FrameLoop(start: -1, end: 10, frameCount: 120) == nil)
        #expect(FrameLoop(start: 0, end: 120, frameCount: 120) == nil)
    }

    @Test
    func readoutCarriesFrameExactTimeRateAndFps() {
        let readout = PlaybackReadout(frame: 46_000, frameRate: .fps60, rate: .half)
        #expect(readout.time == CMTime(value: 46_000, timescale: 60))
        #expect(readout.seconds == 46_000.0 / 60)
        #expect(readout.rate == .half)
    }
}
