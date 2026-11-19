import JovraCore
import JovraMedia
import SwiftUI

/// The camera preset sheet (S04): only the formats this camera supports, each with its planning size
/// and how long fits in the free space, and the planned length the storage estimate uses (stories 49, 50).
/// Unsupported formats are not shown at all.
struct CameraPresetSheet: View {
    nonisolated static let isPlaceholder = false
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        SetupSheet(route: .cameraPreset,
                   subtitle: String(localized: "Only formats this camera records are listed.", table: "Record", comment: "Camera sheet subtitle")) {
            if store.isFixtureCamera {
                VStack(alignment: .leading, spacing: Space.x1) {
                    FixtureBadge()
                    Text("The simulator records a labelled sample clip, so its one format is listed.", tableName: "Record", comment: "Camera sheet on the simulator")
                        .font(.subheadline)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            formats
            PlannedLengthSection()
            if let estimate = store.storageEstimate {
                InfoCard(symbol: estimate.verdict == .ready ? "internaldrive" : "exclamationmark.triangle",
                         title: String(localized: "Estimated space", table: "Record", comment: "Camera sheet storage card"),
                         message: SetupCopy.storageDetail(estimate))
                    .accessibilityIdentifier("camera.estimate")
            }
        }
    }

    @ViewBuilder private var formats: some View {
        switch store.cameraFormats {
        case nil:
            HStack(spacing: Space.x1) {
                ProgressView().accessibilityHidden(true)
                Text(SetupCopy.checkingCamera).font(.body).foregroundStyle(.jovra(.textSecondary))
            }
            .accessibilityElement(children: .combine)
        case let options? where options.isEmpty:
            StateCard(symbol: "video.slash", title: SetupCopy.noSupportedFormat,
                      message: String(localized: "This camera reports no format JOVRA records. You can still import a recording.", table: "Record", comment: "Camera sheet empty state"))
        case let options?:
            SetupSection(title: String(localized: "Format", table: "Record", comment: "Camera sheet section")) {
                ForEach(options) { option in
                    ChoiceRow(title: SetupCopy.cameraValue(option), detail: detail(option),
                              isSelected: store.selectedFormat?.id == option.id,
                              identifier: "camera.format.\(option.id)") {
                        store.setup.cameraFormatID = option.id
                    }
                }
            }
        }
    }

    private func detail(_ option: CaptureFormatOption) -> String {
        guard let free = store.budget?.freeBytes else { return SetupCopy.perMinute(option) }
        let fits = JovraFormat.duration(seconds: Double(StorageEstimator.fitsSeconds(bitRate: option.bitRate, freeBytes: free)))
        return String(localized: "\(SetupCopy.perMinute(option)) · about \(fits) fits", table: "Record", comment: "Camera format detail")
    }
}

/// "Planned length" from 15 minutes to 3 hours in 15-minute steps.
private struct PlannedLengthSection: View {
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        let minutes = store.setup.plannedMinutes
        let range = SessionSetup.plannedMinutesRange
        SetupSection(title: String(localized: "Planned length", table: "Record", comment: "Camera sheet section"),
                     footnote: String(localized: "Used only for the storage estimate. Recording never stops at this length.", table: "Record", comment: "Planned length footnote")) {
            // Own 44 pt controls: the system stepper's segments are 32 pt tall. VoiceOver gets one
            // adjustable element (swipe up or down) with the length as its value.
            HStack(spacing: Space.x2) {
                stepButton(symbol: "minus", enabled: minutes > range.lowerBound) { change(by: -SessionSetup.plannedMinutesStep) }
                Text(SetupCopy.plannedLength(minutes: minutes))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                stepButton(symbol: "plus", enabled: minutes < range.upperBound) { change(by: SessionSetup.plannedMinutesStep) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Planned length", tableName: "Record", comment: "Stepper name"))
            .accessibilityValue(Text(verbatim: SetupCopy.plannedLength(minutes: minutes)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: change(by: SessionSetup.plannedMinutesStep)
                case .decrement: change(by: -SessionSetup.plannedMinutesStep)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("camera.plannedLength")
        }
    }

    private func change(by step: Int) {
        let range = SessionSetup.plannedMinutesRange
        store.setup.plannedMinutes = min(max(store.setup.plannedMinutes + step, range.lowerBound), range.upperBound)
    }

    private func stepButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                .background(Color.jovra(.surfaceSunken), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.jovra(enabled ? .textPrimary : .textSecondary))
        .disabled(!enabled)
    }
}
