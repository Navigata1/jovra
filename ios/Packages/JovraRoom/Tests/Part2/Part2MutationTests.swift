import Foundation
import JovraRoom
import XCTest

/// The room mutation set the issue names must fail: a forged issuer, a replayed bridge payload and a frozen send age.
/// Each test hands the fixture runners a deliberately broken seam and requires the named cases to catch it.
/// (Source-level mutations of the package itself are run by scripts/ios/room-mutations.sh.)
final class Part2MutationTests: XCTestCase {
    /// A carrier that "authenticates" a frame by looking up the member the command claims, instead of passing the TLS
    /// peer: the D1 forgery. A viewer's phone could then stop every camera as the capture controller.
    func test_forgedIssuerIsCaught() throws {
        let trustClaimedMember: Part2Runners.PeerBinding = { _, command, members in
            members[command.issuer.memberId].map { AuthenticatedPeer(deviceId: $0.deviceId) }
        }
        let (_, failures) = try Part2Runners.ledger(peerBinding: trustClaimedMember)
        XCTAssertTrue(failures.contains { $0.contains("#forged-issuer") }, "\(failures)")
    }

    /// A carrier that drops the peer entirely is refused on every frame, so the honest vectors fail broadly.
    func test_aLedgerCallWithoutThePeerFailsTheVectors() throws {
        let (_, failures) = try Part2Runners.ledger(peerBinding: { _, _, _ in nil })
        XCTAssertTrue(failures.contains { $0.contains("#duplicate-identical") }, "\(failures)")
    }

    /// A watch whose replay marks do not survive a restart takes an old payload back.
    func test_replayedBridgePayloadAfterRestartIsCaught() throws {
        let (_, failures) = try Part2Runners.bridge(restart: { BridgeReceiver(pairedPhoneId: $0.pairedPhoneId) })
        XCTAssertTrue(failures.contains { $0.contains("#watch-restart-keeps-marks") }, "\(failures)")
    }

    /// A watch that keeps no replay marks at all treats a re-delivery as a refresh.
    func test_replayedBridgePayloadIsCaught() throws {
        let (_, failures) = try Part2Runners.bridge(accept: { receiver, env in
            receiver = BridgeReceiver(pairedPhoneId: receiver.pairedPhoneId)
            return receiver.accept(env)
        })
        XCTAssertTrue(failures.contains { $0.contains("#replayed-payload") }, "\(failures)")
    }

    /// An outbox that resends the exact bytes it queued (age frozen at its offline value) lets a start request
    /// flushed ten minutes later through: D4.
    func test_frozenSendAgeIsCaught() throws {
        let frozen: Part2Runners.SendRewrite = { command, ageWhenQueued in
            var sent = command
            if let ageWhenQueued { sent.expiry.ageAtSendMs = ageWhenQueued }
            return sent
        }
        let (_, failures) = try Part2Runners.outbox(send: frozen)
        XCTAssertTrue(failures.contains { $0.contains("#queued-capture-expires") }, "\(failures)")
    }
}
