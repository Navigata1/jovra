import Foundation
import JovraRoom
import XCTest

/// spec/room/fixtures/vectors, Part 1 kinds: every case of freshness (14), snapshot (14), phone-status (5),
/// display (6), disconnect (1) and analysis (7) agrees with the reference.
final class VectorConformanceTests: XCTestCase {
    private func assertAllPass(_ run: () throws -> (cases: Int, failures: [String]), kind: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let (cases, failures) = try run()
        XCTAssertEqual(cases, RoomVectorKinds.part1[kind], "\(kind) case count", file: file, line: line)
        XCTAssertEqual(failures, [], "\(kind)", file: file, line: line)
    }

    func test_freshnessVectors() throws { try assertAllPass({ try VectorRunners.freshness() }, kind: "freshness") }
    func test_snapshotVectors() throws { try assertAllPass(VectorRunners.snapshot, kind: "snapshot") }
    func test_phoneStatusVectors() throws { try assertAllPass({ try VectorRunners.phoneStatus() }, kind: "phone-status") }
    func test_displayVectors() throws { try assertAllPass(VectorRunners.display, kind: "display") }
    func test_disconnectVectors() throws { try assertAllPass(VectorRunners.disconnect, kind: "disconnect") }

    func test_analysisVectors() throws {
        let registry = RoomCapabilityRegistry(statuses: try RoomFixtures.registryStatuses())
        try assertAllPass({ try VectorRunners.analysis(registry: registry) }, kind: "analysis")
    }

    /// The four thresholds the README pins, asserted directly rather than only through the fixture.
    func test_thresholdBoundaries_5000Fresh_5001Delayed_15000Delayed_15001Unknown() throws {
        func at(_ ms: Int) throws -> Freshness {
            try FreshnessRule.classify(senderAgeMs: ms, sinceAcceptMs: 0, transitBounded: true, transitMs: 0,
                                       baselineValid: true)
        }
        XCTAssertEqual(try at(5000), .fresh)
        XCTAssertEqual(try at(5001), .delayed)
        XCTAssertEqual(try at(15000), .delayed)
        XCTAssertEqual(try at(15001), .unknown)
        // The same boundaries reached by chaining sender age, transit and receiver time.
        XCTAssertEqual(try FreshnessRule.classify(senderAgeMs: 2000, sinceAcceptMs: 2960, transitBounded: true,
                                                  transitMs: 40, baselineValid: true), .fresh)
        XCTAssertEqual(try FreshnessRule.classify(senderAgeMs: 2000, sinceAcceptMs: 2961, transitBounded: true,
                                                  transitMs: 40, baselineValid: true), .delayed)
        XCTAssertEqual(try FreshnessRule.classify(senderAgeMs: 2000, sinceAcceptMs: 12960, transitBounded: true,
                                                  transitMs: 40, baselineValid: true), .delayed)
        XCTAssertEqual(try FreshnessRule.classify(senderAgeMs: 2000, sinceAcceptMs: 12961, transitBounded: true,
                                                  transitMs: 40, baselineValid: true), .unknown)
    }

    func test_aBackwardsClockIsUnknownNotACrash() throws {
        let observation = ReceiverObservation(transitBounded: true, transitMs: 0, processBaselineId: "pb-1",
                                              acceptedAtMonoMs: 10_000)
        let read = try FreshnessRule.observe(senderAgeMs: 0, observation, nowMonoMs: 9_000, currentBaselineId: "pb-1")
        XCTAssertEqual(read.freshness, .unknown)
        XCTAssertNil(read.ageMs)
    }

    func test_statusRowsAreFrozenAndFormattedWithoutRoundingUp() {
        let c3 = CameraReport(deviceId: "c3", captureState: .recording, lastReportedElapsedMs: 746_999)
        let row = StatusRow.remote(c3, freshness: .unknown, ageMs: 18_999)
        XCTAssertEqual(row.elapsedText, "12:26")
        XCTAssertEqual(row.lastHeardSeconds, 18)
        XCTAssertTrue(row.mayStillBeRecording)
        XCTAssertEqual(RoomDurationText.clock(milliseconds: 3_723_000), "1:02:03")
        XCTAssertEqual(RoomDurationText.clock(milliseconds: 59_999), "0:59")
        XCTAssertEqual(RoomDurationText.clock(milliseconds: -5), "0:00")
        XCTAssertNil(StatusRow.remote(c3, freshness: .unknown, ageMs: nil).lastHeardSeconds)
    }

    func test_countsComeFromTheRosterAndRefuseUnenrolledRows() throws {
        let c1 = CameraReport(deviceId: "c1", captureState: .recording, lastReportedElapsedMs: 1000)
        let counts = try RoomCounts(rows: [(c1, .fresh)], enrolled: ["c1", "c2"])
        XCTAssertEqual(counts.enrolled, 2)
        XCTAssertEqual(counts.unknown, 1, "an enrolled camera with no row is Unknown")
        XCTAssertFalse(counts.canClaimAllRecording)
        let stray = CameraReport(deviceId: "c9", captureState: .recording, lastReportedElapsedMs: 0)
        XCTAssertThrowsError(try RoomCounts(rows: [(stray, .fresh)], enrolled: ["c1"]))
        XCTAssertFalse(try RoomCounts(rows: [], enrolled: []).canClaimAllRecording)
    }

    func test_snapshotRefusalLeavesStateUntouched() throws {
        var receiver = SnapshotReceiver(sessionId: "sample-jon-alex", hostEpoch: 3,
                                        hostKey: "bbfbe0c66faa5f6105cdced46762eeef30997ef9279f11ffe7341c2738f13065",
                                        hostDeviceId: "c1", members: ["c1", "c2", "c3", "c4", "c5", "c6"],
                                        rosterRevision: 1)
        let snapshot = try VectorRunners.snapshotRecord(RoomFixtures.record("room-snapshot"))
        XCTAssertEqual(receiver.accept(snapshot), .accepted)
        let before = receiver.state
        XCTAssertEqual(receiver.accept(snapshot), .replayOrOutOfOrder)
        XCTAssertEqual(receiver.state, before)
    }
}
