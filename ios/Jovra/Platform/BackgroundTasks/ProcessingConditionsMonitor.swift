import Foundation
import JovraCore
import JovraMedia
import Network
import UIKit

extension CaptureActivity {
    /// The app's one capture activity signal: every capture engine reports through it and the processing
    /// scheduler reads it, so no stage starts while a recording is in progress.
    static let app = CaptureActivity()
}

/// Reads what the processing queue needs to know about the device (capture activity, heat, power,
/// Low Power Mode, the archive and Wi-Fi) and reports every change on the main actor.
@MainActor
final class ProcessingConditionsMonitor {
    private(set) var conditions: ProcessingConditions
    var onChange: (@MainActor (ProcessingConditions) -> Void)?
    /// Called when the app moves to the background (true) or returns (false).
    var onBackground: (@MainActor (Bool) -> Void)?

    private let archiveState: LaunchConfiguration.ArchiveState?
    private var onWiFi = false
    private var observers: [NSObjectProtocol] = []
    private var captureObserver: UUID?
    private let path = NWPathMonitor()

    init(launch: LaunchConfiguration) {
        archiveState = launch.archiveState
        conditions = ProcessingConditions(captureActive: CaptureActivity.app.isActive, thermal: .nominal,
                                          externalPower: false, lowPowerMode: false, backup: .awaitingSetup)
    }

    func start() {
        guard observers.isEmpty else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange,
                     UIDevice.batteryStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onBackground?(true) }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onBackground?(false) }
        })
        captureObserver = CaptureActivity.app.observe { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        path.pathUpdateHandler = { [weak self] update in
            let wifi = update.status == .satisfied && update.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                self?.onWiFi = wifi
                self?.refresh()
            }
        }
        path.start(queue: DispatchQueue(label: "com.islanddevcrew.jovra.processing.path"))
        refresh()
    }

    func refresh() {
        let battery = UIDevice.current.batteryState
        let next = ProcessingConditions(
            captureActive: CaptureActivity.app.isActive,
            thermal: Self.thermal(ProcessInfo.processInfo.thermalState),
            externalPower: battery == .charging || battery == .full,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            backup: backupReadiness
        )
        guard next != conditions else { return }
        conditions = next
        onChange?(next)
    }

    /// Only a connected archive can take a backup, and only on Wi-Fi (the v1 default). Until the archive
    /// service exists every backup waits for setup.
    private var backupReadiness: ProcessingConditions.BackupReadiness {
        guard archiveState == .connected else { return .awaitingSetup }
        return onWiFi ? .ready : .waitingForWiFi
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> ProcessingConditions.Thermal {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .critical
        }
    }
}
