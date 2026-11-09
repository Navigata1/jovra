import Foundation
import JovraRoom
import Observation

/// Pushed screens inside the page stack.
enum WatchRoute: Hashable, Sendable {
    /// "View all n": every camera row.
    case cameras
}

/// An alert the full-screen sheet is showing.
struct PresentedAlert: Identifiable, Equatable, Sendable {
    let alert: WatchBridgeSnapshot.Alert
    var id: String { alert.alertId }
}

/// The app's state: how it was launched, the receiver holding the last accepted snapshot, the visible page and the
/// alerts the wearer has dealt with.
@MainActor
@Observable
final class WatchAppModel {
    enum Mode: Equatable, Sendable {
        /// No harness: waits for the phone (the live WatchConnectivity bridge is W07).
        case live
        case harness(WatchStateID)
        /// The launch arguments could not be used; the app shows why instead of guessing.
        case launchProblems([String])
    }

    let mode: Mode
    let receiver: WatchSnapshotReceiver
    let reduceMotionOverride: Bool?
    @ObservationIgnored private(set) var bridge: (any WatchBridgeClient)?

    var page: WatchSurface = .health
    var path: [WatchRoute] = []
    /// Acknowledged by the wearer. Sending `ackAlert` to the phone arrives with the alert policy (W18).
    private(set) var acknowledgedAlertIds: Set<String> = []
    /// Closed without acknowledging; shown again only when the phone raises a new alert.
    private(set) var dismissedAlertIds: Set<String> = []

    init(mode: Mode, receiver: WatchSnapshotReceiver, bridge: (any WatchBridgeClient)? = nil,
         reduceMotionOverride: Bool? = nil) {
        self.mode = mode
        self.receiver = receiver
        self.bridge = bridge
        self.reduceMotionOverride = reduceMotionOverride
        bridge?.sink = receiver
    }

    var snapshot: WatchBridgeSnapshot? { receiver.snapshot }
    var isSample: Bool { receiver.snapshot?.sample ?? false }

    /// The first alert in the snapshot the wearer has neither acknowledged nor closed.
    var presentedAlert: PresentedAlert? {
        guard let alerts = receiver.snapshot?.alerts else { return nil }
        return alerts.first { !acknowledgedAlertIds.contains($0.alertId) && !dismissedAlertIds.contains($0.alertId) }
            .map(PresentedAlert.init)
    }

    func acknowledge(_ alertId: String) { acknowledgedAlertIds.insert(alertId) }

    func acknowledgeAllAlerts() {
        acknowledgedAlertIds.formUnion(receiver.snapshot?.alerts.map(\.alertId) ?? [])
    }

    func dismiss(_ alertId: String) { dismissedAlertIds.insert(alertId) }

    /// The row the watch shows for one camera, if the snapshot has one.
    func row(for deviceId: String?) -> StatusRow? {
        guard let deviceId else { return nil }
        return receiver.board?.rows.first { $0.deviceId == deviceId }
    }
}

extension WatchAppModel {
    /// The model for this process's launch arguments: the harness state they name, the problems that stop it, or
    /// live behaviour.
    static func launch(arguments: [String], bundle: Bundle = .main) -> WatchAppModel {
        let configuration = WatchLaunchConfiguration(arguments: arguments)
        if !configuration.problems.isEmpty {
            return WatchAppModel(mode: .launchProblems(configuration.problems.map(\.description)),
                                 receiver: .live(), reduceMotionOverride: configuration.reduceMotion)
        }
        guard let id = configuration.watchState, let state = WatchStateRegistry.shared.state(id) else {
            return WatchAppModel(mode: .live, receiver: .live(), reduceMotionOverride: configuration.reduceMotion)
        }
        do {
            return try WatchHarness.open(state, bundle: bundle, reduceMotionOverride: configuration.reduceMotion)
        } catch {
            return WatchAppModel(mode: .launchProblems(["\(id): \(error)"]), receiver: .live(),
                                 reduceMotionOverride: configuration.reduceMotion)
        }
    }
}

extension WatchSnapshotReceiver {
    /// The production receiver: the continuous clock (keeps counting in sleep) and this process's baseline.
    static func live() -> WatchSnapshotReceiver {
        WatchSnapshotReceiver(clock: ContinuousMonotonicClock(), baselineId: ProcessBaseline.current,
                              pairedPhoneId: nil)
    }
}
