import CoreGraphics
import JovraCore
import SwiftUI

// MARK: - Stat tiles

/// Three tiles computed from stored sessions: sessions and time on court over the window, first serves in for the
/// latest match with its fraction one tap away. Side by side, sharing one height; stacked at accessibility sizes.
struct HomeStatTiles: View {
    var overview: HomeDashboard.Overview
    var windowCaption: String
    @State private var showsFraction = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Space.x1))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.x1))
        let firstServes = FractionPresentation(ratio: overview.firstServes.ratio, provenance: overview.firstServes.provenance,
                                               isSample: overview.isSample)
        VStack(alignment: .leading, spacing: Space.x1) {
            // One Sample badge for the row: in a three-up row a badge inside each ~110 pt tile cannot follow Dynamic Type
            // (the audit's "Dynamic Type partially unsupported"); every tile still says "sample data" to VoiceOver.
            if overview.isSample {
                SampleBadge(text: String(localized: "Sample data", table: "Home", comment: "Badge over the demo's stat tiles"))
                    .accessibilityIdentifier("home.tiles.sample")
            }
            layout {
                StatTile(value: JovraFormat.count(overview.sessionCount),
                         label: String(localized: "Sessions", table: "Home", comment: "Stat tile label"),
                         symbol: "tennisball", scope: windowCaption,
                         spokenValue: spokenCount(JovraFormat.count(overview.sessionCount), sample: overview.isSample))
                    .accessibilityIdentifier("home.tile.sessions")
                StatTile(value: JovraFormat.duration(seconds: Double(overview.onCourtSeconds)),
                         label: String(localized: "On court", table: "Home", comment: "Stat tile label"),
                         symbol: "clock", scope: windowCaption,
                         spokenValue: spokenCount(spokenDuration, sample: overview.isSample))
                    .accessibilityIdentifier("home.tile.onCourt")
                StatTile(value: firstServes.value,
                         label: String(localized: "First serves in", table: "Home", comment: "Stat tile label"),
                         symbol: "scope", scope: firstServesScope,
                         spokenValue: firstServes.spokenValue,
                         onTap: overview.firstServes.ratio.d > 0 ? { showsFraction = true } : nil)
                    .accessibilityIdentifier("home.tile.firstServes")
                    .fractionPopover(isPresented: $showsFraction) {
                        FractionPopover(
                            label: String(localized: "First serves in · Latest match", table: "Home", comment: "Fraction popover title"),
                            fraction: firstServes,
                            definition: String(localized: "Points you served in your latest match where the first serve went in, out of every point you served.",
                                               table: "Home", comment: "Fraction popover definition of first serves in"))
                    }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.tiles")
    }

    private var firstServesScope: String {
        overview.firstServes.matchID == nil
            ? String(localized: "No match yet", table: "Home", comment: "First-serves tile scope when no match is stored")
            : String(localized: "Latest match", table: "Home", comment: "First-serves tile scope")
    }

    private var spokenDuration: String {
        let minutes = overview.onCourtSeconds / 60
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private func spokenCount(_ value: String, sample: Bool) -> String {
        sample ? String(localized: "\(value), sample data", table: "Home", comment: "VoiceOver: a tile value that is demo data") : value
    }
}

// MARK: - Latest session

/// The compact SessionCard of S03: a frame of the session's own video (court lines when there is none), players,
/// score, length and type, and a status line only when something needs attention.
struct HomeLatestSessionCard: View {
    var latest: HomeDashboard.LatestSession
    var thumbnail: CGImage?
    var open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Space.x2))
            layout {
                poster
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(verbatim: latest.title)
                        .font(.jovraLabel)
                        .foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    if let scoreline = latest.scoreline {
                        Text(verbatim: scoreline.replacingOccurrences(of: " ", with: "   "))
                            .font(.jovraScore)
                            .foregroundStyle(.jovra(.textPrimary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: details)
                        .font(.jovraCaption)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if latest.needsReview > 0 {
                        Label {
                            Text("Needs review · \(latest.needsReview) points", tableName: "Home", comment: "Session card status line")
                        } icon: {
                            Image(systemName: "circle.dashed").foregroundStyle(.jovra(.clay))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.jovra(.attentionInk))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if latest.isSample { SampleBadge(size: .small) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.jovra(.textSecondary))
                        .accessibilityHidden(true)
                }
            }
            .jovraCard(padding: Space.x1 + Space.half)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(HomeCardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityHint(Text("Opens the session", tableName: "Home", comment: "VoiceOver hint on the latest session card"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.latestSession")
    }

    private var poster: some View {
        Color.jovra(.courtSurface)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
                } else {
                    CourtLinesBackdrop().stroke(Color.jovra(.courtLine), lineWidth: 1.5)
                }
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 118, height: 80)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    private var minutesText: String {
        Duration.seconds(latest.durationSeconds / 60 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private var kindText: String {
        switch (latest.kind, latest.format) {
        case (_, .doubles?): String(localized: "Doubles", table: "Home", comment: "Session type on the latest session card")
        case (_, .singles?): String(localized: "Singles", table: "Home", comment: "Session type on the latest session card")
        case (.servePractice, _): String(localized: "Serve practice", table: "Home", comment: "Session type")
        case (.strokePractice, _): String(localized: "Stroke practice", table: "Home", comment: "Session type")
        case (.rally, _): String(localized: "Rally", table: "Home", comment: "Session type")
        case (.lesson, _): String(localized: "Lesson", table: "Home", comment: "Session type")
        case (.drill, _): String(localized: "Drill", table: "Home", comment: "Session type")
        case (.tiebreakOnly, _): String(localized: "Tie-break", table: "Home", comment: "Session type")
        case (.practiceSet, _): String(localized: "Practice set", table: "Home", comment: "Session type")
        case (.match, _): String(localized: "Match", table: "Home", comment: "Session type")
        }
    }

    private var details: String { [minutesText, kindText].joined(separator: " · ") }

    private var spoken: String {
        var parts = [latest.title]
        if let scoreline = latest.scoreline {
            let sets = scoreline.split(separator: " ").joined(separator: ", ")
            parts.append(latest.winnerNames.map {
                String(localized: "\($0) won \(sets)", table: "Home", comment: "VoiceOver: who won and the set scores, e.g. “Jon won 6–4, 6–3”")
            } ?? sets)
        }
        parts.append(Duration.seconds(latest.durationSeconds / 60 * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
        parts.append(kindText)
        if let startedAt = latest.startedAt {
            parts.append(startedAt.formatted(.dateTime.month(.wide).day()))
        }
        if latest.needsReview > 0 {
            parts.append(String(localized: "Needs review · \(latest.needsReview) points", table: "Home"))
        }
        if latest.isSample {
            parts.append(String(localized: "sample data", table: "Home", comment: "VoiceOver suffix: demo data"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Next steps

/// One next useful action: symbol, title, detail and chevron; the whole row is one 44 pt+ button.
struct HomeNextStepRow: View {
    var step: HomeNextStep
    var perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(alignment: .center, spacing: Space.x2) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.jovra(.onAccent))
                    .frame(width: 40, height: 40)
                    .background(Color.jovra(.accent), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.jovraLabel)
                        .foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.jovraCaption)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.jovra(.textSecondary))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: HitTarget.minimum)
            .jovraCard(padding: Space.x1 + Space.half)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(HomeCardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: detail))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.nextStep.\(step.id.split(separator: ".").first ?? "")")
    }

    private var symbol: String {
        switch step {
        case .resume: "arrow.uturn.forward"
        case .finishReviewing: "checklist"
        case .backUp: "icloud.and.arrow.up"
        }
    }

    private var title: String {
        switch step {
        case .resume:
            String(localized: "Pick up your interrupted session", table: "Home", comment: "Next step title: open a recording that stopped early")
        case .finishReviewing:
            String(localized: "Finish reviewing", table: "Home", comment: "Next step title")
        case .backUp(_, let title, let count):
            count == 1
                ? String(localized: "Back up \(title)", table: "Home", comment: "Next step title, one session, e.g. “Back up Jon vs Alex”")
                : String(localized: "Back up \(count) sessions", table: "Home", comment: "Next step title, several sessions")
        }
    }

    private var detail: String {
        switch step {
        case .resume(_, let title, let seconds):
            String(localized: "\(title) stopped early. \(JovraFormat.clock(seconds: Double(seconds))) is saved.",
                   table: "Home", comment: "Next step detail, e.g. “Jon vs Alex stopped early. 41:12 is saved.”")
        case .finishReviewing(_, let title, let points):
            String(localized: "Review \(points) flagged points in \(title)", table: "Home", comment: "Next step detail")
        case .backUp:
            String(localized: "Saved only on this iPhone. Keep a copy in your archive.", table: "Home", comment: "Next step detail")
        }
    }
}

// MARK: - Empty state

/// A fresh install: one inviting card instead of zero-filled tiles (story 35).
struct HomeEmptyState: View {
    var record: () -> Void
    var importVideo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            ZStack {
                Circle().fill(Color.jovra(.accent))
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.jovra(.onAccent))
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
            Text("Your first session shows up here.", tableName: "Home", comment: "Home empty state title")
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Record a match or practice, or import a video you already have. Your sessions, time on court and first serves appear here once there is something to count.",
                 tableName: "Home", comment: "Home empty state message")
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: record) {
                Label(String(localized: "Record a session", table: "Home"), systemImage: "record.circle")
            }
            .buttonStyle(JovraButtonStyle(kind: .primary, fullWidth: true))
            .accessibilityIdentifier("home.empty.record")
            Button(action: importVideo) {
                Label(String(localized: "Import a video", table: "Home", comment: "Empty state action"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(JovraButtonStyle(kind: .secondary, fullWidth: true))
            .accessibilityIdentifier("home.empty.import")
        }
        .jovraCard(padding: Space.x3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.empty")
    }
}

/// A pressed card dims (and, without Reduce Motion, settles slightly).
struct HomeCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(Motion.standard.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
