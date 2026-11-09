import JovraCore
import SwiftUI

/// Labels where a number came from (ADR-0004). Meaning is carried by text and a distinct
/// symbol/outline, never by colour alone; sample data always says "Sample".
struct ProvenanceBadge: View {
    enum Size { case regular, small }
    enum Kind: Hashable {
        case sample
        case provenance(Provenance)

        /// The badge a capability's registry status earns (ADR-0004). Disabled and unsupported
        /// capabilities produce no value, so they have no provenance badge; views never hard-code one.
        init?(status: CapabilityCapabilityStatus) {
            switch status {
            case .manual: self = .provenance(.manual)
            case .estimated: self = .provenance(.estimated)
            case .validated: self = .provenance(.validated)
            case .disabled, .unsupported: return nil
            }
        }
    }

    var kind: Kind
    var size: Size = .regular
    var onForest = false
    /// A more specific caption for the same badge ("Sample video (synthetic)" on video surfaces).
    var customTitle: String? = nil

    private var ink: ColorRole { onForest ? .textOnEditorial : .textPrimary }

    var body: some View {
        HStack(spacing: Space.half) {
            Image(systemName: symbol)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(customTitle ?? title)
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
        // Reserve the label's natural width, so a compact section header never splits “Sam-ple”; a longer
        // custom caption may wrap at the largest text sizes rather than clip.
        .fixedSize(horizontal: customTitle == nil, vertical: true)
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
        if let customTitle { return customTitle }
        return switch kind {
        case .sample: String(localized: "Sample data", table: "DesignSystem.Components")
        default: String(localized: "\(title) value", table: "DesignSystem.Components", comment: "VoiceOver: a provenance badge, e.g. “Estimated value”")
        }
    }
}

/// Demo origin is distinct from measurement provenance; it always spells out Sample.
struct SampleBadge: View {
    var size: ProvenanceBadge.Size = .regular
    var onForest = false
    /// Overrides "Sample" with a caller-owned, already localized caption that still says Sample.
    var text: String? = nil
    var body: some View { ProvenanceBadge(kind: .sample, size: size, onForest: onForest, customTitle: text) }
}

/// Only the camera adapter chooses when this badge is shown (ADR-0012).
struct FixtureBadge: View {
    var body: some View {
        Label {
            Text(String(localized: "Simulator fixture camera", table: "DesignSystem.Components"))
        } icon: {
            Image(systemName: "video.badge.ellipsis").accessibilityHidden(true)
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.jovra(.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.x1)
            .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Color.jovra(.textPrimary), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Simulator fixture camera", tableName: "DesignSystem.Components"))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// A short status with an icon and text ("On device · Backed up", "Needs review", "Uploading 62%").
/// Tone is carried by the symbol and the words, the tint only reinforces it.
struct StatusPill: View {
    enum Tone {
        case positive, attention, neutral
        /// Work with real progress; pass `progress` (0...1) and say the number in `text`.
        case inProgress
    }

    var text: String
    var tone: Tone
    /// Determinate progress for `.inProgress`, drawn as a ring.
    var progress: Double?
    /// Overrides the tone's symbol ("iphone", "icloud").
    var symbol: String?

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.jovra(tone == .attention ? .attentionInk : .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            if tone == .inProgress, let progress {
                ProgressRing(progress: progress)
            } else {
                Image(systemName: symbol ?? defaultSymbol).foregroundStyle(iconColor)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Space.x1 + 2)
        .padding(.vertical, Space.half + 1)
        .background(fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var defaultSymbol: String {
        switch tone {
        case .positive: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .neutral: "circle.dotted"
        case .inProgress: "arrow.up.circle"
        }
    }

    private var iconColor: Color {
        switch tone {
        case .positive: .jovra(.positiveInk)
        case .attention: .jovra(.attentionInk)
        case .neutral, .inProgress: .jovra(.textSecondary)
        }
    }

    private var fill: Color {
        switch tone {
        case .positive: .jovra(.positiveFill)
        case .attention: .jovra(.attentionFill)
        case .neutral, .inProgress: .jovra(.surfaceSunken)
        }
    }
}

/// A small determinate ring sized to the text; decorative, because the pill's words state the number.
private struct ProgressRing: View {
    var progress: Double
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle().stroke(Color.jovra(.separator), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.jovra(.positiveInk), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
