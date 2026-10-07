import SwiftUI

/// A single metric: large monospaced value, a label and an optional symbol and provenance badge.
/// The value must come from stored events (CLAUDE.md rule 1); callers pass it already formatted.
struct StatTile: View {
    var value: String
    var label: String
    var symbol: String?
    var badge: ProvenanceBadge.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            HStack(alignment: .top) {
                Spacer(minLength: 0)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.callout)
                        .foregroundStyle(.jovra(.textPrimary))
                        .frame(width: 32, height: 32)
                        .background(Color.jovra(.surfaceSunken), in: Circle())
                        .accessibilityHidden(true)
                }
            }
            Text(value)
                .font(.jovraMetric)
                .foregroundStyle(.jovra(.textPrimary))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.jovraCaption)
                .foregroundStyle(.jovra(.textSecondary))
            if let badge { ProvenanceBadge(kind: badge) }
        }
        .jovraCard(padding: Space.x2 - 2)
        .accessibilityElement(children: .combine)
    }
}

/// A row of selectable pills (segmented filter). Each segment is a ≥44 pt button that reports
/// its selected state to VoiceOver.
struct FilterPills<Option: Hashable & Identifiable>: View {
    var options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String

    var body: some View {
        HStack(spacing: Space.half) {
            ForEach(options) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.jovraLabel)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        .foregroundStyle(.jovra(selected ? .onPrimaryFill : .textPrimary))
                        .background(selected ? Color.jovra(.primaryFill) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Space.half)
        .background(Color.jovra(.surfaceSunken), in: Capsule())
    }
}
