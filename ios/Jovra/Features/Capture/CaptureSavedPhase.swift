import JovraCore
import SwiftUI

/// The saved phase: shown only after the shared library acknowledged the recording, so "saved" is a fact.
struct CaptureSavedPhase: View {
    var recording: SessionRecording
    var isFixture: Bool
    var openLibrary: () -> Void
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if isFixture { SampleBadge(onForest: true).accessibilityIdentifier("capture.sample") }
            Label {
                Text(verbatim: CaptureRecordingCopy.savedOnDevice).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.jovra(.positiveInk)).accessibilityHidden(true)
            }
            .font(.jovraHeadline)
            .foregroundStyle(.jovra(.textPrimary))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture.saved")
            VStack(alignment: .leading, spacing: Space.x1) {
                if let duration = recording.durationMs {
                    Text(verbatim: CaptureRecordingCopy.savedThrough(duration))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.jovra(.textPrimary))
                        .accessibilityIdentifier("capture.saved.duration")
                }
                Text(recording.gaps.isEmpty ? String(localized: "Saved in one piece. Nothing is missing.", table: "Capture")
                     : String(localized: "Saved with gaps. Everything outside these gaps is in your video.", table: "Capture"))
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture.saved.state")
                CaptureGapList(gaps: recording.gaps, ink: .textSecondary)
            }
            .jovraCard()
            Button(String(localized: "Open library", table: "Sessions.Library"), action: openLibrary)
                .buttonStyle(JovraButtonStyle(kind: .accent, fullWidth: true))
                .accessibilityIdentifier("capture.openLibrary")
            Button(String(localized: "Done", table: "Capture"), action: done)
                .buttonStyle(.jovraSecondary)
                .accessibilityIdentifier("capture.done")
        }
    }
}
