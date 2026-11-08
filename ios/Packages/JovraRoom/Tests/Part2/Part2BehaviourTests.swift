import Foundation
import JovraCore
import JovraRoom
import XCTest

/// Behaviour the package adds around the reference's rules, at the public seams the watch and phone apps call. The
/// expected values come from the spec text and the Sample fixtures, not from the code under test.
final class Part2BehaviourTests: XCTestCase {
    private func sampleBridge() throws -> WatchBridgeSnapshot {
        try Part2Runners.bridgeRecord(RoomFixtures.record("watch-bridge.sample"))
    }

    /// A payload the watch never stamped with its own receiver observation has no bounded age: every camera reads
    /// Unknown and nothing is claimed as recording, whatever the bridge's ages say.
    func test_healthSummaryOfAnUnstampedPayloadIsAllUnknown() throws {
        var bridge = try sampleBridge()
        bridge.receiverObservation = nil
        let summary = try HealthSummary.watch(bridge, nowMonoMs: 0, currentBaselineId: "sample-watch-boot-1")
        XCTAssertEqual(summary.enrolled, 6)
        XCTAssertEqual(summary.fresh, 0)
        XCTAssertEqual(summary.freshRecording, 0)
        XCTAssertFalse(summary.canClaimAllRecording)
        XCTAssertTrue(summary.rows.allSatisfy { $0.freshness == .unknown && $0.lastHeardAgeMs == nil })
    }

    /// The design sample's c3 row: Unknown, frozen at 12:26 and "may still be recording", never advanced.
    func test_healthSummaryRowsShowElapsedExactlyAsLastReported() throws {
        let summary = try HealthSummary.watch(sampleBridge(), nowMonoMs: 3500, currentBaselineId: "sample-watch-boot-1")
        let c3 = try XCTUnwrap(summary.rows.first { $0.deviceId == "c3" })
        XCTAssertEqual(c3.elapsedText, "12:26")
        XCTAssertTrue(c3.mayStillBeRecording)
        XCTAssertFalse(c3.extrapolated)
        XCTAssertEqual("\(summary.freshRecording)/\(summary.enrolled)", "3/6")
    }

    /// On the live clock in a new process (the payload was accepted under another baseline) every age is Unknown.
    func test_healthSummaryOnTheLiveClockTreatsAnotherProcessAsUnknown() throws {
        let summary = try HealthSummary.watch(sampleBridge(), clock: .live)
        XCTAssertEqual(summary.counts.unknown, 6)
    }

    /// The QR round trip through the public text API, and a strictly canonical payload that is not a valid record is
    /// refused before any joiner check can run on it.
    func test_qrDecodeRefusesACanonicalButInvalidRecord() throws {
        guard case .invitationPayload(let payload) = try Part2Runners.record(RoomFixtures.record("invitation-payload")) else {
            return XCTFail("not a payload")
        }
        let text = try InvitationQR.encode(payload)
        XCTAssertTrue(text.hasPrefix("jovra-room:1:"))
        XCTAssertEqual(try InvitationQR.decode(text), payload)
        let notARecord = "jovra-room:1:" + Data(#"{"schemaVersion":"jovra.room.invitation-payload/1"}"#.utf8)
            .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertNoThrow(try InvitationQR.decodeCanonicalBytes(notARecord))
        XCTAssertThrowsError(try InvitationQR.decode(notARecord)) { error in
            XCTAssertEqual((error as? InvitationQRError)?.code, "invalidRecord")
        }
    }

    /// A host nonce drawn by `validateJoin(_:now:)` is fresh per attempt and has the nonce pattern.
    func test_validateJoinDrawsAFreshHostNonce() throws {
        guard case .invitation(let record) = try Part2Runners.record(RoomFixtures.record("invitation")),
              case .joinRequest(let request) = try Part2Runners.record(RoomFixtures.record("join-request")) else {
            return XCTFail("fixtures")
        }
        let secrets = try XCTUnwrap(RoomFixtures.json("vectors/invitation.json")["secrets"])
        func host() throws -> HostInvitations {
            HostInvitations(sessionId: "sample-jon-alex", hostEpoch: 3, hostKey: record.hostKeySha256, records: [record],
                            tokens: try Part2Runners.stringMap(secrets["tokens"]),
                            nonces: try Part2Runners.stringMap(secrets["nonces"]))
        }
        var first = try host(), second = try host()
        let now = try XCTUnwrap(RoomTimestamp("2026-10-07T21:12:00Z"))
        let a = first.validateJoin(request, now: now), b = second.validateJoin(request, now: now)
        XCTAssertEqual(a.result, .challenge)
        XCTAssertNotEqual(a.hostNonce, b.hostNonce)
        XCTAssertNotNil(a.hostNonce?.range(of: #"^[A-Za-z0-9_-]{22}$"#, options: .regularExpression))
    }

    /// The outbox persists its drafts across a process death and still recomputes the send age afterwards.
    func test_outboxStateSurvivesARestart() throws {
        guard case .command(let command) = try Part2Runners.record(RoomFixtures.record("command.point-won")) else {
            return XCTFail("fixture")
        }
        var box = Outbox(hostEpoch: command.hostEpoch, knownRevision: 0)
        _ = box.submitOffline(command, nowMonoMs: 10_000)
        let restored = Outbox(restoring: try JSONDecoder().decode(Outbox.State.self, from: CanonicalJSON.encode(box.state)))
        XCTAssertEqual(restored, box)
        let entry = try XCTUnwrap(restored.queue.first)
        XCTAssertEqual(try Outbox.outgoing(entry, nowMonoMs: 70_000).expiry.ageAtSendMs,
                       command.expiry.ageAtSendMs + 60_000)
        XCTAssertThrowsError(try Outbox.outgoing(entry, nowMonoMs: entry.issuedAtMonoMs - 1))
    }

    /// No alert, however urgent, issues a command, and only the owner's own kinds can be critical.
    func test_alertPolicyRefusesANonOwnCriticalKind() {
        var policy = AlertPolicy()
        XCTAssertThrowsError(try policy.own(at: 0, kind: .cameraUnknown, deviceId: "c3"))
        XCTAssertNoThrow(try policy.own(at: 0, kind: .ownStorageCritical, deviceId: "c1"))
        XCTAssertEqual(policy.openAlerts.map(\.severity), [.critical])
        XCTAssertTrue(policy.commandsIssued.isEmpty)
    }
}
