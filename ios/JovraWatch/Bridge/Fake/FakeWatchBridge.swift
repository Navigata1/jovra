import Foundation
import JovraRoom

/// A scripted bridge for the harness and tests (watch spec "Testing Decisions", seam 2): deliver now, queue, drop,
/// reorder, duplicate and restart, each exactly as a transport could misbehave. It never makes anything fresher than
/// the transport would: only `deliverNow` is interactive, and everything queued arrives with unbounded transit.
@MainActor
final class FakeWatchBridge: WatchBridgeClient {
    weak var sink: (any WatchBridgeSink)?

    /// Payloads waiting in the queued path, oldest first.
    private(set) var queued: [WatchBridgeSnapshot] = []
    /// Payloads the transport lost; kept only so tests can see they never arrived.
    private(set) var dropped: [WatchBridgeSnapshot] = []

    init(sink: (any WatchBridgeSink)? = nil) { self.sink = sink }

    /// An interactive delivery right now; an echo bounded its transit to `transitMs`.
    func deliverNow(_ snapshot: WatchBridgeSnapshot, transitMs: Int = 0) {
        precondition(transitMs >= 0, "a transit bound is a duration")
        sink?.bridge(didDeliver: BridgeDelivery(snapshot: snapshot, path: .interactive(transitMs: transitMs)))
    }

    /// Holds the payload in the queued path (`updateApplicationContext` / a DataItem delivered on wake).
    func queue(_ snapshot: WatchBridgeSnapshot) { queued.append(snapshot) }

    /// Delivers everything queued, oldest first, each with unbounded transit.
    func flushQueue() { deliverQueued(queued); queued.removeAll() }

    /// Delivers everything queued newest first: a transport that reorders.
    func flushQueueReordered() { deliverQueued(queued.reversed()); queued.removeAll() }

    /// The transport loses the payload.
    func drop(_ snapshot: WatchBridgeSnapshot) { dropped.append(snapshot) }

    /// The same payload arrives twice on the interactive path (a re-delivery is a replay, not a refresh).
    func duplicate(_ snapshot: WatchBridgeSnapshot, transitMs: Int = 0) {
        deliverNow(snapshot, transitMs: transitMs)
        deliverNow(snapshot, transitMs: transitMs)
    }

    /// The watch app process restarts.
    func restartReceiver() { sink?.bridgeReceiverDidRestart() }

    private func deliverQueued(_ snapshots: some Sequence<WatchBridgeSnapshot>) {
        for snapshot in snapshots {
            sink?.bridge(didDeliver: BridgeDelivery(snapshot: snapshot, path: .queued))
        }
    }
}
