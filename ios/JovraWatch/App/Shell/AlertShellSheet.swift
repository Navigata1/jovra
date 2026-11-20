import JovraRoom
import SwiftUI

/// The connection alert as a full-screen sheet (reference 65): which camera, its state as a word and a shape, when it
/// was last heard and that it may still be recording. Acknowledge only; the watch never stops anything. W04 owns the
/// full surface (slots, phone-unreachable and host-lost variants), W18 the acknowledgement sync and haptics.
struct AlertShellSheet: View {
    let model: WatchAppModel
    let alert: WatchBridgeSnapshot.Alert
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let row = model.row(for: alert.deviceId)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchCard {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(WatchPalette.ivory)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(WatchPalette.clay))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: subject)
                                .font(.watchBody.weight(.semibold))
                                .foregroundStyle(WatchPalette.ivory)
                            Text(verbatim: Self.title(alert.kind))
                                .font(.watchTitle)
                                .foregroundStyle(WatchPalette.clayInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if let row, let age = WatchStatusText.shortAge(row) {
                                Text("Last heard \(age) ago.", tableName: "Watch")
                                    .font(.watchCaption)
                                    .foregroundStyle(WatchPalette.ivory)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if alert.kind == .cameraUnknown, row?.mayStillBeRecording ?? true {
                                Text("May still be recording.", tableName: "Watch")
                                    .font(.watchCaption)
                                    .foregroundStyle(WatchPalette.secondaryText(contrast))
                            }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("watch.alert.message")
                Text("Check on your phone.", tableName: "Watch")
                    .font(.watchCaption)
                    .foregroundStyle(WatchPalette.secondaryText(contrast))
                    .frame(maxWidth: .infinity)
                Button {
                    model.acknowledge(alert.alertId)
                } label: {
                    Text("Acknowledge", tableName: "Watch")
                }
                .buttonStyle(WatchPrimaryButtonStyle())
                .accessibilityIdentifier("watch.alert.acknowledge")
                if model.isSample { SampleTag() }
            }
        }
        .background(WatchPalette.background.ignoresSafeArea())
        .containerBackground(WatchPalette.background, for: .navigation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WatchSurface.alert.identifier)
    }

    private var subject: String {
        guard let deviceId = alert.deviceId else { return String(localized: "Your phone", table: "Watch") }
        return WatchStatusText.spokenName(deviceId)
    }

    static func title(_ kind: WatchBridgeSnapshot.Alert.Kind) -> String {
        switch kind {
        case .cameraUnknown: String(localized: "Status unknown", table: "Watch")
        case .ownRecordingFailed: String(localized: "Recording failed", table: "Watch")
        case .ownStorageCritical: String(localized: "Storage almost full", table: "Watch")
        case .storageLow: String(localized: "Storage low", table: "Watch")
        case .batteryLow: String(localized: "Battery low", table: "Watch")
        case .thermalWarning: String(localized: "Phone is hot", table: "Watch")
        case .reviewNeeded: String(localized: "Review needed", table: "Watch")
        }
    }
}
