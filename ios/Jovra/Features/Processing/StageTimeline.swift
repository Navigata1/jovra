import SwiftUI

/// The vertical stage timeline of screen 7: an indicator per stage on a connecting rail, the stage name
/// and what it is doing, and a trailing percentage. Each row is one VoiceOver element that reads its
/// state in words; the indicators are decorative.
struct StageTimeline: View {
    var rows: [StageRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                StageTimelineRow(row: row, isFirst: offset == 0, isLast: offset == rows.count - 1,
                                 previousDone: offset > 0 && rows[offset - 1].indicator == .done)
            }
        }
    }
}

private struct StageTimelineRow: View {
    var row: StageRow
    var isFirst: Bool
    var isLast: Bool
    var previousDone: Bool
    @ScaledMetric(relativeTo: .body) private var indicatorSize: CGFloat = 30
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: Space.x2) {
            rail
            VStack(alignment: .leading, spacing: Space.half) {
                if typeSize.isAccessibilitySize {
                    Text(row.title).font(.jovraBody.weight(.semibold)).foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.trailing).font(.jovraLabel.monospacedDigit()).foregroundStyle(trailingInk)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title).font(.jovraBody.weight(.semibold)).foregroundStyle(.jovra(.textPrimary))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Space.x1)
                        Text(row.trailing).font(.jovraLabel.monospacedDigit()).foregroundStyle(trailingInk)
                    }
                }
                Text(row.detail)
                    .font(.jovraCaption)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : Space.x3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.title))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityIdentifier("processing.stage.\(row.id)")
    }

    private var accessibilityValue: String {
        row.trailing == "—" ? "\(row.status), \(row.detail)" : "\(row.status), \(row.trailing), \(row.detail)"
    }

    private var trailingInk: Color {
        if case .active = row.indicator { return .jovra(.textPrimary) }
        return .jovra(.textSecondary)
    }

    /// The indicator, with the rail continuing below it to the next stage.
    private var rail: some View {
        VStack(spacing: 0) {
            StageIndicator(indicator: row.indicator)
                .frame(width: indicatorSize, height: indicatorSize)
            if !isLast {
                Rectangle()
                    .fill(row.indicator == .done ? Color.jovra(.positiveInk) : Color.jovra(.separator))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: indicatorSize)
        .accessibilityHidden(true)
    }
}

private struct StageIndicator: View {
    var indicator: StageRow.Indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch indicator {
            case .done:
                Circle().fill(Color.jovra(.positiveInk))
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.jovra(.surface))
            case .active(let progress):
                ring(progress)
                Circle().fill(Color.jovra(.accent)).padding(9)
            case .paused(let progress):
                ring(progress)
                Image(systemName: "pause.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.jovra(.textPrimary))
            case .waiting:
                Circle().strokeBorder(Color.jovra(.textSecondary).opacity(0.6), lineWidth: 1.5)
                    .background(Circle().fill(Color.jovra(.surface)))
            case .failed:
                Circle().fill(Color.jovra(.attentionFill))
                Image(systemName: "exclamationmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.jovra(.attentionInk))
            case .unavailable:
                Circle().strokeBorder(Color.jovra(.textSecondary), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .background(Circle().fill(Color.jovra(.surface)))
                Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundStyle(.jovra(.textSecondary))
            }
        }
        .jovraAnimation(.standard, value: indicator)
    }

    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle().fill(Color.jovra(.surface))
            Circle().strokeBorder(Color.jovra(.accent).opacity(0.35), lineWidth: 3)
            Circle()
                .inset(by: 1.5)
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.jovra(.accentInk), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
