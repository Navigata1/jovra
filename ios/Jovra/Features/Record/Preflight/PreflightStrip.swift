import SwiftUI

/// The compact pre-flight strip (N8): one chip per check, each with a symbol and words; tone is never
/// carried by colour alone. Chips wrap onto new lines as text grows.
struct PreflightStrip: View {
    var checks: [PreflightCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text("Before you record", tableName: "Record", comment: "Pre-flight strip heading")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.jovra(.textSecondary))
                .accessibilityAddTraits(.isHeader)
            ChipFlow(spacing: Space.x1) {
                ForEach(checks) { check in
                    PreflightChip(check: check)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("record.preflight")
    }
}

private struct PreflightChip: View {
    var check: PreflightCheck

    var body: some View {
        Label {
            Text(check.text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: check.symbol).foregroundStyle(.jovra(iconInk))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.jovra(check.tone == .warn || check.tone == .fail ? .attentionInk : .textPrimary))
        .padding(.horizontal, Space.x1 + 4)
        .padding(.vertical, Space.x1)
        .frame(minHeight: HitTarget.minimum)
        .background(Color.jovra(fill), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: check.kindTitle))
        .accessibilityValue(Text(verbatim: "\(check.text), \(check.detail) \(check.toneTitle)"))
        .accessibilityIdentifier("record.preflight.\(check.kind.rawValue)")
    }

    private var iconInk: ColorRole {
        switch check.tone {
        case .pass: .positiveInk
        case .warn, .fail: .attentionInk
        case .unknown: .textSecondary
        }
    }

    private var fill: ColorRole {
        switch check.tone {
        case .pass: .positiveFill
        case .warn, .fail: .attentionFill
        case .unknown: .surfaceSunken
        }
    }
}

/// Lays children left to right and wraps to a new line when the next one does not fit.
struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !current.indices.isEmpty, current.width + spacing + itemWidth > width {
                rows.append(current); current = Row()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
