import SwiftUI
import UIKit

/// The in-app explanation JOVRA shows before Apple's permission prompt, and the consequence of the
/// answer after it (stories 17, 333, 346). It is a JOVRA sheet in JOVRA's own style and never looks
/// like a system alert; the only system UI is Apple's prompt, started by "Continue", and iOS Settings,
/// opened by "Open iOS Settings".
///
/// Present it at the moment of need: `router.present(sheet: .permission(.camera))`, or embed it in
/// any sheet. `onDecision` receives the state after the player chose.
struct PermissionExplanationSheet: View {
    var permission: Permission
    var onDecision: (PermissionState) -> Void = { _ in }

    @Environment(\.permissionsCenter) private var center
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: PermissionState?
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CloseControl(label: String(localized: "Close", table: "Platform.Permissions"), identifier: "sheet.close") { finish() }
                Spacer()
            }
            .padding(.horizontal, Space.x2)
            .padding(.top, Space.x1)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    header
                    if let state {
                        content(for: PermissionGuidance(permission, state))
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.x2)
                .padding(.bottom, Space.x4)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            // The player may have changed the permission in iOS Settings.
            if phase == .active { Task { await refresh() } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.container")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.jovra(.onAccent))
                .frame(width: 52, height: 52)
                .background(Color.jovra(.accent), in: Circle())
                .accessibilityHidden(true)
            Text(PermissionGuidance.name(of: permission))
                .jovraDisplayTitle()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen.title")
        }
    }

    @ViewBuilder
    private func content(for guidance: PermissionGuidance) -> some View {
        Label {
            Text("Status: \(guidance.status)", tableName: "Platform.Permissions", comment: "Permission status line")
        } icon: {
            Image(systemName: statusSymbol(guidance.state))
        }
        .font(.jovraLabel)
        .foregroundStyle(.jovra(guidance.state == .denied ? .attentionInk : .textPrimary))
        .accessibilityIdentifier("permission.status")

        // Before Apple's prompt: why JOVRA asks. After it: what the answer means.
        if guidance.action == .explainThenRequest {
            Text(guidance.explanation)
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("permission.explanation")
        } else {
            Text(guidance.consequence)
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("permission.consequence")
        }

        VStack(spacing: Space.x1) {
            switch guidance.action {
            case .explainThenRequest:
                Button(String(localized: "Continue", table: "Platform.Permissions", comment: "Shows Apple's permission prompt next")) {
                    Task { await request() }
                }
                .buttonStyle(.jovraPrimary)
                .disabled(isRequesting)
                .accessibilityHint(Text("Shows the iOS permission prompt", tableName: "Platform.Permissions"))
                .accessibilityIdentifier("permission.continue")
                Button(String(localized: "Not now", table: "Platform.Permissions")) { finish() }
                    .buttonStyle(.jovraSecondary)
                    .accessibilityIdentifier("permission.notNow")
            case .openSettings:
                Button(String(localized: "Open iOS Settings", table: "Platform.Permissions")) { openSettings() }
                    .buttonStyle(.jovraPrimary)
                    .accessibilityIdentifier("permission.openSettings")
                Button(String(localized: "Not now", table: "Platform.Permissions")) { finish() }
                    .buttonStyle(.jovraSecondary)
                    .accessibilityIdentifier("permission.notNow")
            case .none:
                Button(String(localized: "Done", table: "Platform.Permissions")) { finish() }
                    .buttonStyle(.jovraPrimary)
                    .accessibilityIdentifier("permission.done")
            }
        }
    }

    private var symbol: String {
        switch permission {
        case .camera: "camera"
        case .microphone: "mic"
        case .photosAdd: "photo.badge.plus"
        case .notifications: "bell"
        case .health: "heart.text.square"
        }
    }

    private func statusSymbol(_ state: PermissionState) -> String {
        switch state {
        case .notDetermined: "questionmark.circle"
        case .denied: "xmark.circle"
        case .restricted: "lock"
        case .authorized: "checkmark.circle"
        }
    }

    private func refresh() async {
        state = await center.status(of: permission)
    }

    private func request() async {
        isRequesting = true
        state = await center.request(permission)
        isRequesting = false
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func finish() {
        if let state { onDecision(state) }
        dismiss()
    }
}
