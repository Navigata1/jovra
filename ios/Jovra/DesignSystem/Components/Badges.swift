import JovraCore
import SwiftUI

/// Labels where a number came from (ADR-0004). Meaning is carried by text and a distinct
/// symbol/outline, never by colour alone; sample data always says "Sample".
struct ProvenanceBadge: View {
    enum Size { case regular, small }
    enum Kind: Hashable {
        case sample
        case provenance(Provenance)
    }

    var kind: Kind
    var size: Size = .regular
    var onForest = false

    private var ink: ColorRole { onForest ? .textOnEditorial : .textPrimary }

    var body: some View {
        HStack(spacing: Space.half) {
            Image(systemName: symbol)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.jovra(ink))
        .padding(.horizontal, size == .small ? Space.x1 : Space.x1 + 2)
        .padding(.vertical, Space.half)
        .background(Color.jovra(onForest ? .editorial : .surfaceSunken), in: Capsule())
        .overlay {
            if kind == .sample {
                Capsule().strokeBorder(Color.jovra(ink), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        // Reserve the label's natural width, so a compact section header never splits “Sam-ple”.
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isStaticText)
    }

    var title: String {
        switch kind {
        case .sample: String(localized: "Sample", table: "DesignSystem.Components")
        case .provenance(.manual): String(localized: "Manual", table: "DesignSystem.Components")
        case .provenance(.estimated): String(localized: "Estimated", table: "DesignSystem.Components")
        case .provenance(.reviewed): String(localized: "Reviewed", table: "DesignSystem.Components")
        case .provenance(.validated): String(localized: "Validated", table: "DesignSystem.Components")
        }
    }

    private var symbol: String {
        switch kind {
        case .sample: "square.dashed"
        case .provenance(.manual): "hand.point.up.left"
        case .provenance(.estimated): "plusminus"
        case .provenance(.reviewed): "checkmark"
        case .provenance(.validated): "checkmark.seal"
        }
    }

    private var accessibilityText: String {
        switch kind {
        case .sample: String(localized: "Sample data", table: "DesignSystem.Components")
        default: String(localized: "\(title) value", table: "DesignSystem.Components", comment: "VoiceOver: a provenance badge, e.g. “Estimated value”")
        }
    }
}

/// Demo origin is distinct from measurement provenance; it always spells out Sample.
struct SampleBadge: View {
    var size: ProvenanceBadge.Size = .regular
    var onForest = false
    var body: some View { ProvenanceBadge(kind: .sample, size: size, onForest: onForest) }
}

/// Only the camera adapter chooses when this badge is shown (ADR-0012).
struct FixtureBadge: View {
    var body: some View {
        Text(String(localized: "Simulator fixture camera", table: "DesignSystem.Components"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.jovra(.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.x1)
            .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Color.jovra(.textPrimary), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
    }
}

/// A short status with an icon and text ("On device · Backed up", "Needs review").
struct StatusPill: View {
    enum Tone {
        case positive, attention, neutral
    }

    var text: String
    var tone: Tone

    var body: some View {
        Label {
            Text(text).foregroundStyle(.jovra(tone == .attention ? .attentionInk : .textPrimary))
        } icon: {
            Image(systemName: symbol).foregroundStyle(iconColor)
        }
        .font(.subheadline.weight(.medium))
    }

    private var symbol: String {
        switch tone {
        case .positive: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .neutral: "circle.dotted"
        }
    }

    private var iconColor: Color {
        switch tone {
        case .positive: .jovra(.positiveInk)
        case .attention: .jovra(.attentionInk)
        case .neutral: .jovra(.textSecondary)
        }
    }
}
