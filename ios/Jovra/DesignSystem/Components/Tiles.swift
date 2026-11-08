import SwiftUI

/// A single metric: large monospaced value, a label and an optional symbol and provenance badge.
/// The value must come from stored events (CLAUDE.md rule 1); callers pass it already formatted.
///
/// Extensions (screens.md §5.1): a `scope` caption ("Latest match"), a `fraction` second line
/// ("40 of 60"), `onTap` to open the FractionPopover, and a `compact` variant for 4-up rows.
struct StatTile: View {
    var value: String
    var label: String
    var symbol: String?
    var badge: ProvenanceBadge.Kind?
    var scope: String?
    var fraction: String?
    /// What VoiceOver reads as the value ("67 percent, 40 of 60, manual"); defaults to value + fraction.
    var spokenValue: String?
    var compact = false
    var onTap: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let onTap {
            // A Button is already one VoiceOver element; its label and value replace the children's.
            Button(action: onTap) { tile }
                .buttonStyle(TilePressStyle())
                .accessibilityLabel(Text(verbatim: accessibilityLabel))
                .accessibilityValue(Text(verbatim: accessibilityValue))
                .accessibilityHint(Text("Shows the fraction and how it was measured", tableName: "DesignSystem.Components"))
        } else {
            tile
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityLabel))
                .accessibilityValue(Text(verbatim: accessibilityValue))
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            if let symbol {
                HStack(alignment: .top) {
                    if !compact { Spacer(minLength: 0) }
                    Image(systemName: symbol)
                        .font(compact ? .footnote : .callout)
                        .foregroundStyle(.jovra(.textPrimary))
                        .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                        .background(Color.jovra(.surfaceSunken), in: Circle())
                        .accessibilityHidden(true)
                }
            }
            Text(verbatim: value)
                .font(compact ? .jovraMetricCompact : .jovraMetric)
                .foregroundStyle(.jovra(.textPrimary))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let fraction {
                Text(verbatim: fraction)
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(label)
                .font(.jovraCaption)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            if let scope {
                Text(scope)
                    .font(.caption)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let badge { ProvenanceBadge(kind: badge, size: compact ? .small : .regular) }
        }
        // Fill the row's height so tiles side by side line up.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .jovraCard(padding: compact ? Space.x1 + Space.half : Space.x2 - 2)
        .overlay(alignment: .bottomTrailing) {
            if onTap != nil, !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.jovra(.textSecondary))
                    .padding(Space.x1 + 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var accessibilityLabel: String {
        [label, scope].compactMap { $0 }.joined(separator: ", ")
    }

    private var accessibilityValue: String {
        if let spokenValue { return spokenValue }
        var parts = [value]
        if let fraction { parts.append(fraction) }
        if let badge { parts.append(ProvenanceBadge(kind: badge).title) }
        return parts.joined(separator: ", ")
    }
}

extension StatTile {
    /// A rate tile straight from the engine's ratio: value, fraction, badge and spoken value agree.
    init(label: String, fraction: FractionPresentation, symbol: String? = nil, scope: String? = nil,
         compact: Bool = false, onTap: (() -> Void)? = nil) {
        self.init(value: fraction.value, label: label, symbol: symbol, badge: fraction.badge, scope: scope,
                  fraction: fraction.fraction, spokenValue: fraction.spokenValue, compact: compact, onTap: onTap)
    }
}

/// A pressed tile dims (and, without Reduce Motion, settles slightly).
private struct TilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.standard.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// A row of selectable pills (segmented filter). Each segment is a ≥44 pt button that reports
/// its selected state to VoiceOver.
///
/// At accessibility text sizes equal-width segments would break words mid-word ("Matc/hes"), so the
/// pills stack vertically, full width, inside a rounded panel instead.
struct FilterPills<Option: Hashable & Identifiable>: View {
    var options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(spacing: Space.half))
            : AnyLayout(HStackLayout(spacing: Space.half))
        layout {
            ForEach(options) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.jovraLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, isStacked ? Space.x2 : Space.x1)
                        .padding(.vertical, Space.half)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        .foregroundStyle(.jovra(selected ? .onPrimaryFill : .textPrimary))
                        .background(selected ? Color.jovra(.primaryFill) : .clear, in: segmentShape)
                        .contentShape(segmentShape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Space.half)
        .background(Color.jovra(.surfaceSunken), in: containerShape)
    }

    private var segmentShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isStacked ? Radius.control : HitTarget.minimum / 2, style: .continuous)
    }

    private var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isStacked ? Radius.control + Space.half : HitTarget.minimum / 2 + Space.half, style: .continuous)
    }
}
