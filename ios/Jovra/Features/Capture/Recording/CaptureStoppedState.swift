import SwiftUI

/// What the recording phase says once the engine has stopped without a saved recording: that it is not
/// recording, what failed, and what is still on this iPhone (screen spec, Error state). Nothing here
/// claims a save the library did not acknowledge.
struct CaptureStoppedStatus: View {
    var failure: CaptureStopFailure
    var savedThroughMs: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            CaptureNotRecordingBanner.stopped
            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.jovra(.attentionInk))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(verbatim: CaptureRecordingCopy.stopFailureTitle(failure))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.jovra(.textOnEditorial))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: CaptureRecordingCopy.stopFailureMessage(failure, savedThroughMs: savedThroughMs))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.jovra(.textSecondaryOnEditorial))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture.stopFailure")
        }
    }
}

/// The ways out of a stopped recording. Close is always there; a failed deletion can be tried again
/// without asking a second time, because the player already confirmed it.
struct CaptureStoppedExits: View {
    var failure: CaptureStopFailure
    var isWorking: Bool
    var retryDelete: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: Space.x1 + Space.half) {
            if failure == .deleteFailed {
                Button(String(localized: "Try deleting again", table: "Capture"), action: retryDelete)
                    .buttonStyle(.jovraPrimary)
                    .disabled(isWorking)
                    .accessibilityIdentifier("capture.retryDelete")
            }
            Button(String(localized: "Close", table: "Capture"), action: close)
                .buttonStyle(failure == .deleteFailed ? JovraButtonStyle(kind: .onForestSecondary, fullWidth: true) : .jovraPrimary)
                .disabled(isWorking)
                .accessibilityIdentifier("capture.close")
        }
    }
}
