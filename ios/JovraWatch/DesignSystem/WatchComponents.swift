import JovraRoom
import SwiftUI

/// A camera's freshness drawn as a shape (watch spec "Accessibility": meaning never by colour alone): Fresh and Local
/// are a filled dot, Delayed a half ring, Unknown an open clay ring.
struct FreshnessMark: View {
    let freshness: RowFreshness
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 9

    var body: some View {
        Group {
            switch freshness {
            case .fresh, .local:
                Circle().fill(WatchPalette.chartreuse)
            case .delayed:
                ZStack {
                    Circle().stroke(WatchPalette.ivory, lineWidth: size * 0.22)
                    Circle().trim(from: 0.25, to: 0.75).fill(WatchPalette.ivory).rotationEffect(.degrees(180))
                }
            case .unknown:
                Circle().strokeBorder(WatchPalette.clay, lineWidth: size * 0.26)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Sample" on every surface fed from a `sample: true` record (hard rule 1).
struct SampleTag: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text("Sample", tableName: "Watch")
            .font(.watchTag)
            .foregroundStyle(WatchPalette.secondaryText(contrast))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(WatchPalette.panel))
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("Sample data", tableName: "Watch"))
            .accessibilityIdentifier("watch.sample")
    }
}

/// A raised row or card on the forest background.
struct WatchCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WatchPalette.panel))
    }
}

/// The one chartreuse action on a surface: full width, at least 44 pt tall, forest text.
struct WatchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.watchReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.watchBody.weight(.semibold))
            .foregroundStyle(WatchPalette.onChartreuse)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(Capsule().fill(WatchPalette.chartreuse.opacity(isEnabled ? 1 : 0.4)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

/// A quieter action (Acknowledge, Keep): panel fill, ivory text, the same 44 pt height.
struct WatchSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.watchBody.weight(.medium))
            .foregroundStyle(WatchPalette.ivory)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(Capsule().fill(configuration.isPressed ? WatchPalette.panelRaised : WatchPalette.panel))
            .contentShape(Capsule())
    }
}

/// A designed empty, waiting or error state: a symbol in a ring, a short title and one sentence.
struct WatchStatePanel: View {
    let symbol: String
    let title: Text
    let message: Text
    var tint: Color = WatchPalette.ivory
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 2))
                .accessibilityHidden(true)
            title
                .font(.watchTitle)
                .foregroundStyle(WatchPalette.ivory)
                .multilineTextAlignment(.center)
            message
                .font(.watchCaption)
                .foregroundStyle(WatchPalette.secondaryText(contrast))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The shared page chrome: forest background behind the page, the brand in the top-leading toolbar slot.
    func watchPageChrome() -> some View {
        containerBackground(WatchPalette.background, for: .tabView)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { WatchBrandHeader() }
            }
    }
}

extension EnvironmentValues {
    /// Reduce Motion as the watch app applies it: the system setting, or the `-reduceMotion` launch override. Views
    /// read this instead of `accessibilityReduceMotion` so the harness can force it for screenshots and audits.
    @Entry var watchReduceMotion: Bool = false
}
