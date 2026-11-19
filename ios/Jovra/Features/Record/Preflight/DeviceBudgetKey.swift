import Foundation
import JovraCore
import JovraMedia
import SwiftUI

/// Registers the device budget the pre-flight strip reads (the ServiceKey seam). A DEBUG launch can
/// inject a budget with `JOVRA_DEVICE_BUDGET=<name>` (see `InjectedDeviceBudget`), so UI tests can show
/// low space, low battery or a warm phone on the simulator.
struct DeviceBudgetKey: ServiceKey {
    static let defaultValue: any DeviceBudget = resolve(.current)

    static func usesFake(_ configuration: LaunchConfiguration) -> Bool {
        #if DEBUG
        InjectedDeviceBudget.fromEnvironment() != nil
        #else
        false
        #endif
    }

    static func fake(for configuration: LaunchConfiguration) -> any DeviceBudget {
        #if DEBUG
        FakeDeviceBudget(InjectedDeviceBudget.fromEnvironment()?.snapshot ?? InjectedDeviceBudget.roomy.snapshot)
        #else
        live()
        #endif
    }

    static func live() -> any DeviceBudget {
        let volume = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return LiveDeviceBudget(volume: volume)
    }
}

/// Named budgets for UI tests and screenshots. Values are synthetic and never shown as measurements.
enum InjectedDeviceBudget: String, CaseIterable {
    case roomy, lowStorage, almostFull, lowBattery, warm

    static let gigabyte: Int64 = 1_000_000_000

    var snapshot: DeviceBudgetSnapshot {
        switch self {
        case .roomy: .init(freeBytes: 231 * Self.gigabyte, batteryFraction: 0.78, lowPowerMode: false, thermalState: .nominal)
        // 800 MB at the simulator fixture's 4 Mb/s, judged at the 120 % end, fits about 22 minutes of a planned hour.
        case .lowStorage: .init(freeBytes: 800_000_000, batteryFraction: 0.78, lowPowerMode: false, thermalState: .nominal)
        case .almostFull: .init(freeBytes: 300_000_000, batteryFraction: 0.78, lowPowerMode: false, thermalState: .nominal)
        case .lowBattery: .init(freeBytes: 231 * Self.gigabyte, batteryFraction: 0.18, lowPowerMode: true, thermalState: .nominal)
        case .warm: .init(freeBytes: 231 * Self.gigabyte, batteryFraction: 0.78, lowPowerMode: false, thermalState: .serious)
        }
    }

    static func fromEnvironment() -> InjectedDeviceBudget? {
        ProcessInfo.processInfo.environment["JOVRA_DEVICE_BUDGET"].flatMap(InjectedDeviceBudget.init(rawValue:))
    }
}

extension EnvironmentValues {
    var deviceBudget: any DeviceBudget {
        get { self[DeviceBudgetKey.self] }
        set { self[DeviceBudgetKey.self] = newValue }
    }
}
