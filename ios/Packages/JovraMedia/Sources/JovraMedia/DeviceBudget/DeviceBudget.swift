import Foundation
import JovraCore
#if canImport(UIKit)
import UIKit
#endif

public struct DeviceBudgetSnapshot: Equatable, Sendable {
    public var freeBytes: Int64
    public var batteryFraction: Double?
    public var lowPowerMode: Bool
    public var thermalState: SessionCaptureEventThermalState
    public init(freeBytes: Int64, batteryFraction: Double?, lowPowerMode: Bool, thermalState: SessionCaptureEventThermalState) {
        self.freeBytes = freeBytes; self.batteryFraction = batteryFraction; self.lowPowerMode = lowPowerMode; self.thermalState = thermalState
    }
}
public protocol DeviceBudget: Sendable { func snapshot() async throws -> DeviceBudgetSnapshot }
public final class FakeDeviceBudget: DeviceBudget, @unchecked Sendable {
    private let lock = NSLock()
    private var current: DeviceBudgetSnapshot
    public init(_ snapshot: DeviceBudgetSnapshot) { current = snapshot }
    public func set(_ snapshot: DeviceBudgetSnapshot) { lock.withLock { current = snapshot } }
    public func snapshot() async throws -> DeviceBudgetSnapshot { lock.withLock { current } }
}
public struct LiveDeviceBudget: DeviceBudget {
    public var volume: URL
    public init(volume: URL = FileManager.default.temporaryDirectory) { self.volume = volume }
    public func snapshot() async throws -> DeviceBudgetSnapshot {
        let resources = try volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let fallback = try FileManager.default.attributesOfFileSystem(forPath: volume.path)[.systemFreeSize] as? NSNumber
        let free = resources.volumeAvailableCapacityForImportantUsage ?? fallback?.int64Value ?? 0
        let thermal: SessionCaptureEventThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .serious
        }
        #if canImport(UIKit)
        let battery: Double? = await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level >= 0 ? Double(level) : nil
        }
        #else
        let battery: Double? = nil
        #endif
        return DeviceBudgetSnapshot(freeBytes: free, batteryFraction: battery,
                                    lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, thermalState: thermal)
    }
}
public enum CaptureWarning: String, Sendable { case lowStorage, lowBattery, lowPowerMode, phoneWarming }
public struct PreflightReport: Sendable {
    public let format: CaptureSourceFormat
    public let supportedPresets: [CapturePreset]
    public let budget: DeviceBudgetSnapshot
    public let estimatedStorageRange: ClosedRange<Int64>
    public let warnings: [CaptureWarning]
}
