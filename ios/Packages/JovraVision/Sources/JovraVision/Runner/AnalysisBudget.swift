import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Why the runner is holding between windows.
public enum AnalysisPause: String, Codable, CaseIterable, Sendable {
    /// The thermal state is critical: analysis waits for the iPhone to cool down.
    case criticalHeat
    /// The battery is low and not charging: analysis waits for a charger.
    case lowBattery
}

/// The device budget hook. The runner asks it before every window and, while it answers a pause, holds at
/// its last checkpoint (cancellation still ends the run at once). The processing queue already holds whole
/// stages for capture, heat and Low Power Mode; this hook also stops a long stage between windows.
public protocol AnalysisBudget: Sendable {
    func pause() async -> AnalysisPause?
}

/// The rule the device budget applies, separate from how the device is read.
public enum AnalysisBudgetPolicy {
    /// At or below this charge, on battery, analysis waits for a charger.
    public static let lowBattery = 0.10

    public static func pause(thermal: ProcessInfo.ThermalState, battery: Double?, charging: Bool) -> AnalysisPause? {
        if thermal == .critical { return .criticalHeat }
        if let battery, battery <= lowBattery, !charging { return .lowBattery }
        return nil
    }
}

/// No limit: tests and the macOS tools.
public struct UnlimitedAnalysisBudget: AnalysisBudget {
    public init() {}
    public func pause() async -> AnalysisPause? { nil }
}

/// This device's thermal state and battery.
public struct DeviceAnalysisBudget: AnalysisBudget {
    public init() {}

    public func pause() async -> AnalysisPause? {
        let thermal = ProcessInfo.processInfo.thermalState
        #if canImport(UIKit) && !os(watchOS)
        let (battery, charging) = await MainActor.run { () -> (Double?, Bool) in
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let level = device.batteryLevel
            return (level >= 0 ? Double(level) : nil, [.charging, .full].contains(device.batteryState))
        }
        #else
        let (battery, charging): (Double?, Bool) = (nil, true)
        #endif
        return AnalysisBudgetPolicy.pause(thermal: thermal, battery: battery, charging: charging)
    }
}
