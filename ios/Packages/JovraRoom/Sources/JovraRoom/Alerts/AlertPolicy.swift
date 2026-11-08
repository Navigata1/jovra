/// One alert the policy raised, as the bridge forwards it to the watch.
public struct RaisedAlert: Equatable, Hashable, Sendable {
    public let alertId: String
    public let kind: WatchBridgeSnapshot.Alert.Kind
    public let deviceId: String?
    public let severity: WatchBridgeSnapshot.Alert.Severity
}

/// The haptic a watch plays: one deferred haptic for every pending non-critical alert, or a critical one at once.
public enum AlertHapticPattern: String, Equatable, Sendable { case deferred, critical }

/// What the policy did, in order, at the phone's monotonic time `t`.
public enum AlertEvent: Equatable, Sendable {
    case raise(t: Int, RaisedAlert)
    /// The camera has been Fresh for 4 s: the outage is over.
    case clear(t: Int, RaisedAlert)
    case ack(t: Int, RaisedAlert)
    /// One haptic for these alert ids (sorted).
    case haptic(t: Int, alertIds: [String], pattern: AlertHapticPattern)
}

/// The phone-side single source of watch alerts (watch spec "Haptics and alerts"; ADR-0026 §8 as amended;
/// spec/room/reference/jovra_room/alerts.py). Times are the phone's monotonic milliseconds.
///
/// - `cameraUnknown` is raised only for a camera that was freshly Recording and has then been Unknown for at least
///   3 s without interruption; a shorter blip, or a camera that never freshly recorded, raises nothing.
/// - One alert per camera per outage; the outage ends after 4 s Fresh (clear). An acknowledged alert stays closed for
///   the rest of that outage. The same camera raises at most once per 5 min.
/// - `cameraUnknown` is never critical: its haptic waits for the next accepted point or 45 s after the oldest pending
///   alert, and every pending alert collapses into one haptic. A cleared or acknowledged alert drops out of it.
/// - `ownRecordingFailed` and `ownStorageCritical` are critical: raised and vibrated at once.
/// - No alert ever issues a command (`commandsIssued` is always empty).
public struct AlertPolicy: Equatable, Sendable {
    public static let raiseAfterMs = 3000
    public static let clearAfterMs = 4000
    public static let realertMinMs = 300_000
    public static let deferMaxMs = 45_000

    public enum PolicyError: Error, Equatable, Sendable { case notOwnCriticalKind(WatchBridgeSnapshot.Alert.Kind) }

    private struct Camera: Equatable, Sendable {
        var armed = false
        var unknownSince: Int?
        var freshSince: Int?
        var alertId: String?
        var outageAcked = false
        var lastRaisedAt: Int?
    }

    private var cameras: [String: Camera] = [:]
    private var open: [String: (seq: Int, alert: RaisedAlert)] = [:]
    private var pending: [(raisedAt: Int, alertId: String)] = []
    private var seq = 0
    public private(set) var events: [AlertEvent] = []
    /// Always empty: no alert, however urgent, stops or starts anything.
    public let commandsIssued: [RoomCommand] = []

    public init() {}

    /// Alerts raised and not yet cleared or acknowledged, in the order they were raised.
    public var openAlerts: [RaisedAlert] { open.values.sorted { $0.seq < $1.seq }.map(\.alert) }

    /// A camera's receiver-derived freshness and its own last capture state, observed at `t`. Delayed interrupts both
    /// the Unknown and the Fresh run.
    public mutating func status(at t: Int, deviceId: String, freshness: Freshness, captureState: CaptureState) {
        var c = cameras[deviceId] ?? Camera()
        switch freshness {
        case .fresh:
            if captureState == .recording { c.armed = true }
            c.unknownSince = nil
            c.freshSince = c.freshSince ?? t
        case .unknown:
            c.freshSince = nil
            c.unknownSince = c.unknownSince ?? t
        case .delayed:
            c.freshSince = nil
            c.unknownSince = nil
        }
        cameras[deviceId] = c
        evaluate(t)
    }

    public mutating func tick(at t: Int) { evaluate(t) }

    /// The next accepted point event delivers every pending deferred haptic.
    public mutating func pointAccepted(at t: Int) {
        evaluate(t)
        if !pending.isEmpty { haptic(t, .deferred, nil) }
    }

    /// The watch owner's own recording failed or its storage is critical: raised and vibrated at once.
    public mutating func own(at t: Int, kind: WatchBridgeSnapshot.Alert.Kind, deviceId: String?) throws(PolicyError) {
        guard kind.isOwnCapture else { throw .notOwnCriticalKind(kind) }
        let alert = raise(t, kind, deviceId, .critical)
        haptic(t, .critical, [alert.alertId])
        evaluate(t)
    }

    /// The wearer acknowledged an alert; it stays closed for the rest of its camera's outage.
    public mutating func acknowledge(at t: Int, alertId: String) {
        guard let entry = open[alertId] else { return }
        close(t, alertId, ack: true)
        if let device = entry.alert.deviceId, var c = cameras[device], c.alertId == alertId {
            c.alertId = nil
            c.outageAcked = true
            cameras[device] = c
        }
        evaluate(t)
    }

    private mutating func raise(_ t: Int, _ kind: WatchBridgeSnapshot.Alert.Kind, _ deviceId: String?,
                                _ severity: WatchBridgeSnapshot.Alert.Severity) -> RaisedAlert {
        seq += 1
        let alert = RaisedAlert(alertId: "alert-\(seq)", kind: kind, deviceId: deviceId, severity: severity)
        open[alert.alertId] = (seq, alert)
        events.append(.raise(t: t, alert))
        return alert
    }

    private mutating func close(_ t: Int, _ alertId: String, ack: Bool) {
        guard let entry = open.removeValue(forKey: alertId) else { return }
        pending.removeAll { $0.alertId == alertId }
        events.append(ack ? .ack(t: t, entry.alert) : .clear(t: t, entry.alert))
    }

    private mutating func evaluate(_ t: Int) {
        for deviceId in cameras.keys.sorted() {
            guard var c = cameras[deviceId] else { continue }
            if c.alertId == nil, !c.outageAcked, c.armed, let since = c.unknownSince {
                let due = t - since >= Self.raiseAfterMs
                let capped = c.lastRaisedAt.map { t - $0 < Self.realertMinMs } ?? false
                if due && !capped {
                    let alert = raise(t, .cameraUnknown, deviceId, .deferred)
                    c.alertId = alert.alertId
                    c.lastRaisedAt = t
                    pending.append((t, alert.alertId))
                }
            }
            if let since = c.freshSince, t - since >= Self.clearAfterMs {
                if let alertId = c.alertId {
                    close(t, alertId, ack: false)
                    c.alertId = nil
                }
                c.outageAcked = false
            }
            cameras[deviceId] = c
        }
        if let oldest = pending.map(\.raisedAt).min(), t - oldest >= Self.deferMaxMs { haptic(t, .deferred, nil) }
    }

    private mutating func haptic(_ t: Int, _ pattern: AlertHapticPattern, _ ids: [String]?) {
        let alertIds = ids ?? pending.map(\.alertId).sorted()
        if pattern == .deferred { pending.removeAll() }
        if !alertIds.isEmpty { events.append(.haptic(t: t, alertIds: alertIds, pattern: pattern)) }
    }

    public static func == (lhs: AlertPolicy, rhs: AlertPolicy) -> Bool {
        lhs.cameras == rhs.cameras && lhs.events == rhs.events && lhs.seq == rhs.seq
            && lhs.openAlerts == rhs.openAlerts && lhs.pending.map(\.alertId) == rhs.pending.map(\.alertId)
            && lhs.pending.map(\.raisedAt) == rhs.pending.map(\.raisedAt)
    }
}
