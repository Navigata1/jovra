import AVFoundation
import HealthKit
import Photos
import UserNotifications

/// The system's permission APIs. Requests are logged in `PermissionRequestLog` before the system
/// prompt starts. JOVRA never reads Health data: it asks only to save workouts (Info.plist has
/// `NSHealthUpdateUsageDescription` and no share-read string).
struct LivePermissionsCenter: PermissionsCenter {
    func status(of permission: Permission) async -> PermissionState {
        switch permission {
        case .camera: Self.state(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: Self.state(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photosAdd: Self.state(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        case .notifications: Self.state(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        case .health: Self.healthState()
        }
    }

    func request(_ permission: Permission) async -> PermissionState {
        let current = await status(of: permission)
        guard current == .notDetermined else { return current }
        PermissionRequestLog.record(permission)
        switch permission {
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .photosAdd:
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        case .health:
            if HKHealthStore.isHealthDataAvailable() {
                try? await HKHealthStore().requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            }
        }
        return await status(of: permission)
    }

    private static func state(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// `.limited` cannot occur for add-only access; it would still allow saving, so it reads as authorized.
    private static func state(_ status: PHAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized, .limited: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// Provisional and ephemeral delivery are permissions to notify, so they read as authorized.
    private static func state(_ status: UNAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// Without Health data on the device (some iPads) saving workouts is impossible: `restricted`.
    private static func healthState() -> PermissionState {
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        switch HKHealthStore().authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
