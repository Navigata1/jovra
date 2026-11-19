import JovraMedia
import SwiftUI

/// The framing phase around T23's slot: the preview, the singles draft that will be recorded, and Start.
/// The session document is created only when recording starts, so the draft stays editable here.
struct CaptureFramingPhase: View {
    var coordinator: NativeCaptureCoordinator
    var choices: CaptureSetupChoices
    var fixture: URL?
    var editDetails: () -> Void
    var start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if coordinator.isFixture {
                FixtureBadge()
                SampleBadge(onForest: true).accessibilityIdentifier("capture.sample")
            }
            CapturePreview(session: coordinator.previewSession, fixture: coordinator.isFixture ? fixture : nil)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            if coordinator.isFixture {
                Text("Sample footage preview", tableName: "Capture")
                    .font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
            }
            CaptureFramingSlot()
            draftSummary
            Button(action: start) {
                Label(String(localized: "Start recording", table: "Capture"), systemImage: "record.circle")
                    .frame(maxWidth: .infinity, minHeight: HitTarget.capture)
            }
            .buttonStyle(JovraButtonStyle(kind: .accent, fullWidth: true))
            .disabled(coordinator.isWorking || coordinator.status?.phase != .ready)
            .accessibilityIdentifier("capture.start")
            Label {
                Text("No sound · Video records without microphone access", tableName: "Capture")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "mic.slash").accessibilityHidden(true)
            }
            .font(.jovraLabel)
            .foregroundStyle(.jovra(.textSecondary))
            if coordinator.isWorking || coordinator.status == nil {
                ProgressView(String(localized: "Preparing your recording", table: "Capture"))
                    .tint(.jovra(.textPrimary)).foregroundStyle(.jovra(.textPrimary))
            }
        }
    }

    /// What will be recorded: the default singles draft, or the setup the Record tab passed in.
    private var draftSummary: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(verbatim: choices.title.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("capture.draft.title")
            Text("\(choices.playerA) vs \(choices.playerB)", tableName: "Capture")
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            Text(choices.format == .bestOfOne ? String(localized: "Best of one set", table: "Capture")
                 : String(localized: "Best of three sets", table: "Capture"))
                .font(.jovraLabel)
                .foregroundStyle(.jovra(.textSecondary))
            Button(String(localized: "Edit match details", table: "Capture"), action: editDetails)
                .buttonStyle(.jovraCompact)
                .disabled(coordinator.sessionID != nil)
                .accessibilityIdentifier("capture.editDetails")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jovraCard()
    }
}
