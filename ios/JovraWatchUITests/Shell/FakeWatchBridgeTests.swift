import JovraRoom
import XCTest

/// The fake bridge against the app's receiver and JovraRoom's freshness rules (W03 acceptance: the queue path marks
/// rows Unknown and the deliver-now path marks them Fresh). No app launch: these run the app's own Bridge and Model
/// sources compiled into this bundle.
@MainActor
final class FakeWatchBridgeTests: XCTestCase {
    private var clock: ManualMonotonicClock!
    private var receiver: WatchSnapshotReceiver!
    private var bridge: FakeWatchBridge!

    override func setUp() async throws {
        clock = ManualMonotonicClock(nowMs: 1_000_000)
        receiver = WatchSnapshotReceiver(clock: clock, baselineId: "pb-test-1", pairedPhoneId: "sample-bridge-phone")
        bridge = FakeWatchBridge(sink: receiver)
    }

    private func freshness() throws -> [String: RowFreshness] {
        let board = try XCTUnwrap(receiver.board, "no snapshot accepted")
        return Dictionary(uniqueKeysWithValues: board.rows.map { ($0.deviceId, $0.freshness) })
    }

    func testDeliverNowMarksHeardCamerasFresh() throws {
        bridge.deliverNow(try WatchTestRecords.sample(), transitMs: 0)

        // spec/room vectors/watch-sample.json "design-sample-raw": 5 of 6 fresh; c3 was last heard 18 s before the
        // bridge forwarded it, so it stays Unknown however the snapshot arrived.
        XCTAssertEqual(try freshness(), ["c1": .fresh, "c2": .fresh, "c3": .unknown, "c4": .fresh, "c5": .fresh,
                                          "c6": .fresh])
        let counts = try XCTUnwrap(receiver.board).counts
        XCTAssertEqual(counts.enrolled, 6)
        XCTAssertEqual(counts.freshRecording, 5)
        XCTAssertEqual(receiver.lastOutcome, .accepted)
        XCTAssertFalse(receiver.isAwaitingLiveUpdate)
    }

    func testQueuePathMarksEveryRowUnknown() throws {
        bridge.queue(try WatchTestRecords.sample())
        XCTAssertNil(receiver.board, "a queued payload has not arrived yet")

        bridge.flushQueue()

        XCTAssertEqual(Set(try freshness().values), [.unknown])
        let board = try XCTUnwrap(receiver.board)
        XCTAssertEqual(board.counts.freshRecording, 0)
        XCTAssertEqual(board.counts.unknown, 6)
        // Unknown never rewrites what the camera last reported: c1's elapsed time is still 12:34.
        XCTAssertEqual(board.rows.first { $0.deviceId == "c1" }?.elapsedText, "12:34")
        XCTAssertTrue(board.rows.allSatisfy(\.mayStillBeRecording))
        XCTAssertTrue(receiver.isAwaitingLiveUpdate)
    }

    func testAnInteractiveDeliveryAfterAQueuedOneRenewsFreshness() throws {
        bridge.queue(try WatchTestRecords.sample())
        bridge.flushQueue()
        bridge.deliverNow(try WatchTestRecords.sample(bridgeSeq: 9), transitMs: 40)

        XCTAssertEqual(try freshness()["c1"], .fresh)
        XCTAssertEqual(receiver.lastOutcome, .accepted)
        XCTAssertFalse(receiver.isAwaitingLiveUpdate)
    }

    func testAgesKeepGrowingOnTheWatchClock() throws {
        bridge.deliverNow(try WatchTestRecords.sample(), transitMs: 0)
        // c1: 1,000 ms at the bridge + 1,000 ms snapshot age = 2,000 ms; Fresh up to 5,000 ms.
        clock.advance(byMs: 3000)
        XCTAssertEqual(try freshness()["c1"], .fresh)
        clock.advance(byMs: 1)
        XCTAssertEqual(try freshness()["c1"], .delayed)
        XCTAssertEqual(receiver.board?.rows.first { $0.deviceId == "c1" }?.elapsedText, "12:34",
                       "a remote elapsed time is frozen at its last report, never advanced by the watch clock")
    }

    func testRestartKeepsTheCachedSnapshotButEveryRowBecomesUnknown() throws {
        bridge.deliverNow(try WatchTestRecords.sample(), transitMs: 0)
        bridge.restartReceiver()

        XCTAssertEqual(Set(try freshness().values), [.unknown])
        XCTAssertEqual(receiver.board?.rows.count, 6, "the cached rows are still shown")
        XCTAssertNil(receiver.board?.rows.first?.lastHeardAgeMs, "after a restart the last-heard age is not known")
        XCTAssertTrue(receiver.isAwaitingLiveUpdate)
    }

    func testDuplicateIsAReplayNotARefresh() throws {
        bridge.duplicate(try WatchTestRecords.sample(), transitMs: 0)
        XCTAssertEqual(receiver.outcomes, [.accepted, .replayOrOutOfOrder])
    }

    func testReorderedDeliveryKeepsTheNewestSnapshot() throws {
        bridge.queue(try WatchTestRecords.sample(bridgeSeq: 9))
        bridge.queue(try WatchTestRecords.sample(bridgeSeq: 10))
        bridge.flushQueueReordered()

        XCTAssertEqual(receiver.outcomes, [.accepted, .replayOrOutOfOrder])
        XCTAssertEqual(receiver.snapshot?.bridge.bridgeSeq, 10)
    }

    func testDropNeverArrives() throws {
        bridge.drop(try WatchTestRecords.sample())
        XCTAssertNil(receiver.board)
        XCTAssertEqual(receiver.outcomes, [])
        XCTAssertEqual(bridge.dropped.count, 1)
    }

    func testANewBridgeInstanceIsAcceptedFromItsFirstSequence() throws {
        bridge.deliverNow(try WatchTestRecords.sample(bridgeSeq: 20))
        var restartedPhone = try WatchTestRecords.sample(bridgeSeq: 1)
        restartedPhone.bridge.bridgeInstanceId = "sample-bridge-run-2"
        bridge.deliverNow(restartedPhone)

        XCTAssertEqual(receiver.outcomes, [.accepted, .accepted])
        XCTAssertEqual(receiver.snapshot?.bridge.bridgeInstanceId, "sample-bridge-run-2")
    }

    func testLateRetiredBridgeDoesNotRefreshBeforeOrAfterWatchRestart() throws {
        var retired = try WatchTestRecords.sample(bridgeSeq: 20)
        bridge.deliverNow(retired)
        var current = try WatchTestRecords.sample(bridgeSeq: 1)
        current.bridge.bridgeInstanceId = "sample-bridge-run-2"
        bridge.deliverNow(current)
        XCTAssertEqual(receiver.snapshot, current)

        retired.bridge.bridgeSeq = 21
        clock.advance(byMs: 3_001)
        assertRefusedWithoutRefresh(retired, expecting: .bridgeInstanceRetired)
        bridge.restartReceiver()
        XCTAssertTrue(receiver.isAwaitingLiveUpdate)
        retired.bridge.bridgeSeq += 1
        assertRefusedWithoutRefresh(retired, expecting: .bridgeInstanceRetired)
        XCTAssertTrue(receiver.isAwaitingLiveUpdate)
    }

    func testWrongPhoneCannotEstablishOrReplaceThePairedSnapshot() throws {
        let paired = try WatchTestRecords.sample()
        var foreign = try WatchTestRecords.sample(bridgeSeq: 999)
        foreign.bridge.bridgeDeviceId = "foreign-phone"
        assertRefusedWithoutRefresh(foreign, expecting: .notPairedBridge)
        XCTAssertNil(receiver.snapshot)

        bridge.deliverNow(paired)
        XCTAssertEqual(receiver.snapshot, paired)
        foreign.bridge.bridgeInstanceId = "foreign-bridge"
        assertRefusedWithoutRefresh(foreign, expecting: .notPairedBridge)
    }

    func testAnUnboundReceiverCannotAcceptAFirstPayload() throws {
        let unbound = WatchSnapshotReceiver(clock: clock, baselineId: "pb-unbound", pairedPhoneId: nil)
        let unboundBridge = FakeWatchBridge(sink: unbound)
        unboundBridge.deliverNow(try WatchTestRecords.sample())
        XCTAssertNil(unbound.snapshot)
        XCTAssertNil(unbound.observation)
        XCTAssertEqual(unbound.lastOutcome, .notPairedBridge)
    }

    func testHigherBridgeSequenceCannotRegressTheHostEpoch() throws {
        try assertRegressionRefused(.staleEpoch) { $0.hostEpoch -= 1 }
    }

    func testHigherBridgeSequenceCannotRegressTheSessionSnapshot() throws {
        try assertRegressionRefused(.snapshotSeqRegressed) { $0.snapshotSeq -= 1 }
    }

    func testHigherBridgeSequenceCannotRegressTheEventRevision() throws {
        try assertRegressionRefused(.eventRevisionRegressed) { $0.eventRevision -= 1 }
    }

    func testSessionMarksSurviveSwitchingRoomsAndANewerEpochCanResetThem() throws {
        let first = try WatchTestRecords.sample()
        bridge.deliverNow(first)
        var other = try WatchTestRecords.sample(bridgeSeq: 9)
        other.sessionId = "sample-other-session"
        other.hostEpoch = 1
        other.snapshotSeq = 1
        other.eventRevision = 0
        bridge.deliverNow(other)
        XCTAssertEqual(receiver.snapshot, other)

        var old = try WatchTestRecords.sample(bridgeSeq: 10)
        old.snapshotSeq -= 1
        assertRefusedWithoutRefresh(old, expecting: .snapshotSeqRegressed)
        var newEpoch = old
        newEpoch.hostEpoch += 1
        newEpoch.snapshotSeq = 1
        newEpoch.eventRevision = 0
        bridge.deliverNow(newEpoch)
        XCTAssertEqual(receiver.lastOutcome, .accepted)
        XCTAssertEqual(receiver.snapshot, newEpoch)
    }

    private func assertRegressionRefused(_ verdict: BridgeVerdict, regress: (inout WatchBridgeSnapshot) -> Void) throws {
        bridge.deliverNow(try WatchTestRecords.sample())
        var older = try WatchTestRecords.sample(bridgeSeq: 9)
        regress(&older)
        clock.advance(byMs: 3_001)
        assertRefusedWithoutRefresh(older, expecting: verdict)

        let valid = try WatchTestRecords.sample(bridgeSeq: 9)
        bridge.deliverNow(valid)
        XCTAssertEqual(receiver.lastOutcome, .accepted, "a refusal must not consume the valid successor's sequence")
        XCTAssertEqual(receiver.snapshot, valid)
    }

    private func assertRefusedWithoutRefresh(_ payload: WatchBridgeSnapshot, expecting verdict: BridgeVerdict,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let cached = receiver.snapshot
        let observation = receiver.observation
        let board = receiver.board
        bridge.deliverNow(payload)
        XCTAssertEqual(receiver.lastOutcome, verdict, file: file, line: line)
        XCTAssertTrue(receiver.snapshot == cached, "a refusal must preserve the last snapshot", file: file, line: line)
        XCTAssertEqual(receiver.observation, observation, "a refusal must not stamp a new clock observation",
                       file: file, line: line)
        XCTAssertTrue(receiver.board == board, "a refusal must preserve the visible board", file: file, line: line)
    }
}
