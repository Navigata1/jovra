import Foundation
import JovraRoom

/// A receiver clock that does not move, so a harness state looks the same in every screenshot and audit: ages are
/// exactly what the record and the delivery path make them. (Ages that grow are covered by the unit tests.)
struct FrozenMonotonicClock: MonotonicClock {
    let ms: Int
    func nowMs() -> Int { ms }
}

/// Opens a registered `-watchState`: loads its spec/room records, plays its steps through `FakeWatchBridge` into a
/// fresh receiver and selects its surface.
@MainActor
enum WatchHarness {
    static func open(_ state: WatchHarnessState, bundle: Bundle,
                     reduceMotionOverride: Bool?) throws -> WatchAppModel {
        guard let library = WatchRecordLibrary(bundle: bundle) else {
            throw WatchRecordLibrary.LoadError.missing("records")
        }
        let receiver = WatchSnapshotReceiver(clock: FrozenMonotonicClock(ms: 1_000_000),
                                             baselineId: "pb-harness-\(state.id.surface.rawValue)")
        let bridge = FakeWatchBridge()
        let model = WatchAppModel(mode: .harness(state.id), receiver: receiver, bridge: bridge,
                                  reduceMotionOverride: reduceMotionOverride)
        for step in state.steps {
            switch step {
            case .deliverNow(let record, let transitMs):
                bridge.deliverNow(try library.watchBridgeSnapshot(record), transitMs: transitMs)
            case .queue(let record):
                bridge.queue(try library.watchBridgeSnapshot(record))
            case .flushQueue:
                bridge.flushQueue()
            case .restartWatchProcess:
                bridge.restartReceiver()
            case .acknowledgeAlerts:
                model.acknowledgeAllAlerts()
            }
        }
        // The alert is a sheet over the pages; it opens over Camera health, where its camera is listed.
        model.page = state.id.surface == .alert ? .health : state.id.surface
        return model
    }
}
