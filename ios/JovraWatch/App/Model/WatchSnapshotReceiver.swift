import Foundation
import JovraRoom
import Observation

/// The camera rows and roster counts the watch derives from its last accepted snapshot.
struct WatchHealthBoard: Equatable, Sendable {
    let rows: [StatusRow]
    let counts: RoomCounts
}

/// The watch's receiving end: accepts bridge deliveries, stamps each with this process's monotonic baseline and
/// derives camera freshness with JovraRoom's receiver-owned rules (ADR-0026 §4).
@MainActor
@Observable
final class WatchSnapshotReceiver: WatchBridgeSink {
    enum Outcome: Equatable, Sendable {
        case accepted
        case replayOrOutOfOrder
    }

    private(set) var snapshot: WatchBridgeSnapshot?
    private(set) var observation: ReceiverObservation?
    private(set) var outcomes: [Outcome] = []
    var lastOutcome: Outcome? { outcomes.last }

    @ObservationIgnored private let clock: any MonotonicClock
    private(set) var baselineId: String

    init(clock: any MonotonicClock, baselineId: String) {
        self.clock = clock
        self.baselineId = baselineId
    }

    /// True while the cached snapshot cannot make anything fresh: it came by the queued path (unbounded transit) or
    /// was accepted by an earlier process. Only the next interactive delivery clears it.
    var isAwaitingLiveUpdate: Bool {
        guard let observation else { return false }
        return !observation.transitBounded || observation.processBaselineId != baselineId
    }

    /// Rows and counts read now on the watch's own clock, or nil before any snapshot. Each camera's age is chained:
    /// the bridge's age for the row, plus the snapshot's age at the bridge, plus the bounded transit, plus the time
    /// since this watch accepted it. A queued delivery or a restarted process makes every row Unknown.
    var board: WatchHealthBoard? {
        guard let snapshot, let observation else { return nil }
        let policy = snapshot.freshnessPolicy.policy
        let now = clock.nowMs()
        var entries: [(StatusRow, RowFreshness)] = []
        for device in snapshot.devices {
            let report = device.report
            let senderAge = device.ageAtBridgeMs.addingReportingOverflow(snapshot.bridge.snapshotAgeAtBridgeMs)
            // Decoding bounds both ages, so neither the sum nor `observe` can fail; if either ever did, the row is
            // Unknown rather than a crash or a guess.
            let reading = senderAge.overflow ? nil : try? FreshnessRule.observe(
                senderAgeMs: senderAge.partialValue, observation, nowMonoMs: now, currentBaselineId: baselineId,
                policy: policy)
            let row = StatusRow.remote(report, freshness: reading?.freshness ?? .unknown, ageMs: reading?.ageMs)
            entries.append((row, row.freshness))
        }
        let rows = entries.map(\.0)
        let reports = zip(snapshot.devices, entries).map { ($0.report, $1.1) }
        guard let counts = try? RoomCounts(rows: reports, enrolled: snapshot.roster.cameraDeviceIds) else {
            // A row for a camera that is not enrolled breaks the contract; count nothing as fresh.
            return WatchHealthBoard(rows: rows, counts: RoomCounts(
                enrolled: snapshot.roster.cameraDeviceIds.count, fresh: 0, delayed: 0,
                unknown: snapshot.roster.cameraDeviceIds.count, reportedRecording: 0, freshRecording: 0,
                canClaimAllRecording: false))
        }
        return WatchHealthBoard(rows: rows, counts: counts)
    }

    /// Accepts the delivery unless it is a replay or arrives out of order within the same bridge instance (a
    /// re-delivered payload is never a refresh). A new bridge instance (the phone app restarted) starts its own
    /// sequence. The full BridgeReceiver rules (paired phone, retired instances, epochs) arrive with W02.
    func bridge(didDeliver delivery: BridgeDelivery) {
        let incoming = delivery.snapshot.bridge
        if let current = snapshot?.bridge, current.bridgeInstanceId == incoming.bridgeInstanceId,
           incoming.bridgeSeq <= current.bridgeSeq {
            outcomes.append(.replayOrOutOfOrder)
            return
        }
        snapshot = delivery.snapshot
        observation = ReceiverObservation(transitBounded: delivery.path.transitBoundMs != nil,
                                          transitMs: delivery.path.transitBoundMs, processBaselineId: baselineId,
                                          acceptedAtMonoMs: clock.nowMs())
        outcomes.append(.accepted)
    }

    /// A restarted watch process keeps the cached snapshot (shown with every row Unknown) but measures on a new
    /// baseline, so nothing it cached can read as fresh until the phone answers again.
    func bridgeReceiverDidRestart() {
        baselineId = "pb-" + UUID().uuidString.lowercased()
    }
}
