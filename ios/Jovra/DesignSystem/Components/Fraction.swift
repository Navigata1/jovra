import JovraCore
import SwiftUI

/// How a rate is shown and spoken: the value, its fraction one tap away and where it came from
/// (user stories 138, 357). Built from the engine's `RateRatio`, so the percentage uses the one
/// shared rounding rule (ADR-0011) and a zero denominator is an em dash, never "0%".
struct FractionPresentation: Equatable {
    /// What a rate with nothing to divide by shows: an em dash, never "0%".
    static let noData = "—"
    /// "67%", or "—" when there is nothing to divide by.
    let value: String
    /// "40 of 60"; nil when there is no data.
    let fraction: String?
    let provenance: Provenance?
    let isSample: Bool
    /// What VoiceOver reads: "67 percent, 40 of 60, manual", or "no data".
    let spokenValue: String

    init(ratio: RateRatio, provenance: Provenance?, isSample: Bool = false) {
        self.provenance = provenance
        self.isSample = isSample
        guard let percent = ratio.pct.value, ratio.d > 0 else {
            value = Self.noData
            fraction = nil
            spokenValue = String(localized: "no data", table: "DesignSystem.Components",
                                 comment: "VoiceOver: a rate with a zero denominator")
            return
        }
        value = ratio.display
        let fraction = String(localized: "\(ratio.n) of \(ratio.d)", table: "DesignSystem.Components",
                              comment: "A fraction under a percentage, e.g. “40 of 60”")
        self.fraction = fraction
        var spoken = String(localized: "\(percent) percent, \(fraction)", table: "DesignSystem.Components",
                            comment: "VoiceOver: a percentage and its fraction, e.g. “67 percent, 40 of 60”")
        if let provenance { spoken += ", " + Self.spokenProvenance(provenance) }
        if isSample {
            spoken += ", " + String(localized: "sample data", table: "DesignSystem.Components",
                                    comment: "VoiceOver suffix: the value is demo data")
        }
        spokenValue = spoken
    }

    /// The badge for this value: Sample wins, because demo origin matters more than method.
    var badge: ProvenanceBadge.Kind? {
        if isSample { return .sample }
        return provenance.map { .provenance($0) }
    }

    private static func spokenProvenance(_ provenance: Provenance) -> String {
        switch provenance {
        case .manual: String(localized: "manual", table: "DesignSystem.Components", comment: "VoiceOver: provenance, lower case")
        case .estimated: String(localized: "estimated", table: "DesignSystem.Components", comment: "VoiceOver: provenance, lower case")
        case .reviewed: String(localized: "reviewed", table: "DesignSystem.Components", comment: "VoiceOver: provenance, lower case")
        case .validated: String(localized: "validated", table: "DesignSystem.Components", comment: "VoiceOver: provenance, lower case")
        }
    }
}

/// The "fraction one tap away" card: value, fraction, a plain definition, provenance and an optional
/// "Show points" action (screens.md §5.2). Presented with `fractionPopover(isPresented:...)`.
struct FractionPopover: View {
    var label: String
    var fraction: FractionPresentation
    var definition: String
    var showPoints: (() -> Void)?
    /// Presented (a sheet at accessibility sizes) the content scrolls; inline (a gallery card) it grows.
    var scrollsAtAccessibilitySizes = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Sized to its content so nothing is cropped; at accessibility sizes the content scrolls.
        Group {
            if dynamicTypeSize.isAccessibilitySize, scrollsAtAccessibilitySizes {
                ScrollView { content }
            } else {
                content.fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(idealWidth: 320)
        .background(Color.jovra(.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fraction.popover")
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: Space.x2) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(label)
                        .font(.jovraLabel)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Space.half) {
                        Text(verbatim: fraction.value)
                            .font(.jovraMetricLarge)
                            .foregroundStyle(.jovra(.textPrimary))
                        Text(verbatim: fraction.fraction ?? fraction.spokenValue.capitalizedFirst)
                            .font(.title3.monospacedDigit().weight(.medium))
                            .foregroundStyle(.jovra(.textSecondary))
                    }
                }
                // One element: the stat's name, then value, fraction and provenance in words.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityValue(Text(verbatim: fraction.spokenValue))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fraction.value")
                Text(definition)
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                if let badge = fraction.badge { ProvenanceBadge(kind: badge) }
                if let showPoints {
                    Button(String(localized: "Show points", table: "DesignSystem.Components"), action: showPoints)
                        .buttonStyle(JovraButtonStyle(kind: .secondary, size: .compact))
                }
            }
            .padding(Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FractionPopoverModifier: ViewModifier {
    @Binding var isPresented: Bool
    var popover: () -> FractionPopover
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, arrowEdge: .top) {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes a popover anchored mid-screen has no room; on iPhone it becomes
                // a sheet whose content scrolls, so nothing is clipped and the action stays reachable.
                popover()
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.jovra(.surface))
            } else {
                popover().presentationCompactAdaptation(.popover)
            }
        }
    }
}

extension View {
    func fractionPopover(isPresented: Binding<Bool>, content: @escaping () -> FractionPopover) -> some View {
        modifier(FractionPopoverModifier(isPresented: isPresented, popover: content))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
