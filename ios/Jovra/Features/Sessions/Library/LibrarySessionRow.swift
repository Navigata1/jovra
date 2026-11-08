import JovraCore
import SwiftUI

/// Stored document metadata. Replay separately verifies whether its original media is available.
struct LibrarySessionRow: View {
    var session: JovraCore.SessionSummary
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(session.title).font(.jovraHeadline).foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                if session.sample { SampleBadge() }
                Text(session.players.map(\.displayName).joined(separator: " · "))
                    .font(.jovraBody).foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                if let date = ISO8601DateFormatter().date(from: session.createdAt) {
                    Text(JovraFormat.date(date)).font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
                }
                Text("Stored recording status", tableName: "Sessions.Library")
                    .font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
                Label(recordingStatus, systemImage: "video")
                    .font(.jovraBody).foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .jovraCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.session.\(session.id)")
    }

    private var recordingStatus: String {
        switch session.original?.state {
        case .recording: String(localized: "Not finalized", table: "Sessions.Library")
        case .recovering: String(localized: "Recovery in progress", table: "Sessions.Library")
        case .saved: String(localized: "Saved", table: "Sessions.Library")
        case .savedWithGaps: String(localized: "Saved with gaps", table: "Sessions.Library")
        case .partial: String(localized: "Partially saved", table: "Sessions.Library")
        case .importing: String(localized: "Importing", table: "Sessions.Library")
        case .archiveOnly: String(localized: "Archived only", table: "Sessions.Library")
        case .missing: String(localized: "Video missing", table: "Sessions.Library")
        case .trashed: String(localized: "Recently deleted", table: "Sessions.Library")
        case nil: String(localized: "Recording status unavailable", table: "Sessions.Library")
        }
    }
}
