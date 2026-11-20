import SwiftUI

#if DEBUG
/// UI-test evidence for story 17 (onboarding never asks for camera, microphone or Photos). With the launch harness's
/// injected permissions (`-permissions camera=notDetermined,...`), every request goes to the fake center and is
/// recorded there; this probe shows how many, as one accessibility element, only when the test sets
/// `JOVRA_PERMISSION_PROBE=1`. Never compiled into a release build.
struct PermissionRequestProbe: View {
    static let isEnabled = ProcessInfo.processInfo.environment["JOVRA_PERMISSION_PROBE"] == "1"

    var body: some View {
        if Self.isEnabled {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(verbatim: "\(requestCount)")
                    .font(.caption2)
                    .foregroundStyle(.jovra(.textSecondary))
                    .accessibilityLabel(Text(verbatim: "Permission requests"))
                    .accessibilityValue(Text(verbatim: "\(requestCount)"))
                    .accessibilityIdentifier("harness.permissionRequests")
            }
        }
    }

    /// Requests made to the injected center, plus any system prompt the live center started.
    private var requestCount: Int {
        let injected = (PermissionsCenterKey.defaultValue as? InjectedPermissionsCenter)?.injected.requests.count ?? 0
        return injected + PermissionRequestLog.all.count
    }
}
#endif
