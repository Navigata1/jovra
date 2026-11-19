import JovraCore
import SwiftUI

/// The saved phase: shown only after the shared library acknowledged the recording, so "saved" is a fact.
struct CaptureSavedPhase: View {
    var recording: SessionRecording
    var isFixture: Bool
    /// Opens the processing route for this recording (T27); nil hides the action.
    var seeProcessing: (() -> Void)? = nil
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
                // The engine stopped by itself (storage or battery): say why, from the stored capture events.
                if let reason = CaptureRecordingCopy.automaticStopReason(recording) {
                    Text(verbatim: reason)
                        .font(.jovraBody.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("capture.saved.reason")
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
            if let seeProcessing {
                Button(String(localized: "See processing", table: "Capture"), action: seeProcessing)
                    .buttonStyle(JovraButtonStyle(kind: .accent, fullWidth: true))
                    .accessibilityIdentifier("capture.processing")
            }
            Button(String(localized: "Open library", table: "Sessions.Library"), action: openLibrary)
                .buttonStyle(JovraButtonStyle(kind: seeProcessing == nil ? .accent : .secondary, fullWidth: true))
                .accessibilityIdentifier("capture.openLibrary")
            Button(String(localized: "Done", table: "Capture"), action: done)
                .buttonStyle(.jovraSecondary)
                .accessibilityIdentifier("capture.done")
        }
    }
}
