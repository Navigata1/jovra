import Foundation
import JovraRoom

/// How a snapshot reached the watch (ADR-0026 §4). Arrival is not freshness: only an interactive delivery whose
/// transit an echo bounded can make a row Fresh; a queued delivery (application context, delivered on wake) has
/// unbounded transit, so its rows are Unknown until the next bounded exchange.
enum BridgeDeliveryPath: Equatable, Sendable {
    case interactive(transitMs: Int)
    case queued

    /// The transit bound to record on acceptance, or nil when transit cannot be bounded.
    var transitBoundMs: Int? {
        switch self {
        case .interactive(let transitMs): transitMs
        case .queued: nil
        }
    }
}

/// One payload handed from the bridge to the watch.
struct BridgeDelivery: Equatable, Sendable {
    let snapshot: WatchBridgeSnapshot
    let path: BridgeDeliveryPath
}

/// Where a bridge delivers. The watch app's model is the production sink; tests record deliveries.
@MainActor
protocol WatchBridgeSink: AnyObject {
    func bridge(didDeliver delivery: BridgeDelivery)
    /// The watch app process restarted: cached state stays, the monotonic baseline it was measured under does not.
    func bridgeReceiverDidRestart()
}

/// The watch end of its own paired phone's bridge (watch spec "Bridges per platform"). The live adapter over
/// WatchConnectivity is W07; until then the app runs on `FakeWatchBridge` under the `-watchState` harness and shows
/// "waiting for your phone" otherwise. Commands (marks, points) join this protocol with their tickets (W06, W16).
@MainActor
protocol WatchBridgeClient: AnyObject {
    var sink: (any WatchBridgeSink)? { get set }
}
