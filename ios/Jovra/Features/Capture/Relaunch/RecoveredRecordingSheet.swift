import JovraCore
import SwiftUI

/// Shown at the launch after JOVRA stopped unexpectedly while recording: what RecoveryScanner kept, the
/// gaps it recorded ("Gap 0:07–0:08 · not saved") and, for a partial recovery, every segment it could not
/// keep with the reason (user stories 96 and 100). It never claims more than was decoded.
struct RecoveredRecordingSheet: View {
    var reports: [RecoveredCaptureReport]
    var openLibrary: () -> Void
    var done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x2) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.jovra(.textPrimary))
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.jovra(.textPrimary))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("recovery.title")
                Text("JOVRA stopped while recording. Everything it could play back to the end is saved in your library.", tableName: "Capture")
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(reports) { RecoveredRecordingCard(report: $0) }
                Button(String(localized: "Open library", table: "Sessions.Library"), action: openLibrary)
                    .buttonStyle(JovraButtonStyle(kind: .primary, fullWidth: true))
                    .accessibilityIdentifier("recovery.openLibrary")
                Button(String(localized: "Done", table: "Capture"), action: done)
                    .buttonStyle(.jovraSecondary)
                    .accessibilityIdentifier("recovery.done")
            }
            .padding(Space.x3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.jovra(.background).ignoresSafeArea())
        .interactiveDismissDisabled()
        .accessibilityIdentifier("recovery.sheet")
    }

    /// One recording that lost a part says so in the title; it is never announced as fully recovered.
    private var title: String {
        guard reports.count == 1 else { return String(localized: "Recordings recovered", table: "Capture") }
        return reports[0].outcome == .partial ? String(localized: "Recording partially recovered", table: "Capture.Recovery")
            : String(localized: "Recording recovered", table: "Capture")
    }
}

private struct RecoveredRecordingCard: View {
    var report: RecoveredCaptureReport

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            Text(verbatim: report.title)
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: CaptureRecordingCopy.savedThrough(report.savedThroughMs))
                .font(.body.monospacedDigit())
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityIdentifier("recovery.savedThrough")
            if report.truncatedSegments > 0 {
                Text("The last part was cut at its final complete second so it plays to the end.", tableName: "Capture")
                    .font(.subheadline)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(report.gaps.enumerated()), id: \.offset) { index, gap in
                CaptureGapRow(text: CaptureRecordingCopy.gap(gap), ink: .textSecondary)
                    .accessibilityIdentifier("recovery.gap.\(index)")
            }
            if report.outcome == .partial {
                partialReport
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jovraCard()
        .accessibilityElement(children: .contain)
    }

    /// The partial-recovery report: each segment that could not be kept, and why. Its file stays on disk.
    private var partialReport: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Label {
                Text("Part of this recording could not be recovered", tableName: "Capture")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.jovra(.attentionInk))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("recovery.partial")
            ForEach(Array(report.unrecoverable.enumerated()), id: \.offset) { index, item in
                Text("\(CaptureRecordingCopy.segmentName(item.path)): \(item.reason)", tableName: "Capture")
                    .font(.subheadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recovery.unrecoverable.\(index)")
            }
        }
        .padding(Space.x1 + Space.half)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jovra(.attentionFill), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}
