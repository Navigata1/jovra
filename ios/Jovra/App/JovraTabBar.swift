import SwiftUI

/// Custom tab bar matching the reference: Home · Sessions · raised chartreuse Record · Insights ·
/// Profile, with a small chartreuse dot under the selected tab (selection is also shown by a filled
/// symbol, bolder label and the VoiceOver "selected" trait, so it never relies on colour alone).
///
/// Dynamic Type: like the system tab bar, the labels stop growing at `maxLabelSize` and every tab
/// offers the Large Content Viewer (touch and hold at accessibility sizes shows the tab enlarged).
/// Letting a five-column bar grow without limit breaks every label mid-word and eats the screen.
/// A title too long for one line (a long translation) wraps rather than being truncated; the
/// pseudo-locale UI tests check every title fits.
struct JovraTabBar: View {
    /// Largest Dynamic Type size the tab labels follow. Beyond it, the Large Content Viewer takes over.
    static let maxLabelSize = DynamicTypeSize.xxxLarge
    /// Height of the strip the bar reserves above its top edge for the Record circle's overhang.
    static let recordOverhang: CGFloat = 12
    /// Keeps neighbouring titles apart when both fill their columns.
    static let columnGap: CGFloat = 2
    /// Bar edge inset. With `columnGap` the columns are as wide as with the former 8 pt inset and no
    /// gap (an English title at the xxxLarge cap, semibold, needs 75 pt on iPhone 17 Pro).
    static let edgeInset: CGFloat = 3

    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Self.columnGap) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if reduceMotion {
                        selection = tab
                    } else {
                        withAnimation(.snappy(duration: 0.2)) { selection = tab }
                    }
                } label: {
                    TabLabel(tab: tab, isSelected: selection == tab)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityShowsLargeContentViewer {
                    Label(tab.title, systemImage: tab == .insights ? "chart.bar.fill" : tab.selectedSymbol)
                }
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .dynamicTypeSize(...Self.maxLabelSize)
        .padding(.horizontal, Self.edgeInset)
        .padding(.top, Space.x1)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background {
            Color.jovra(.tabBarBackground)
                .overlay(alignment: .top) { Color.jovra(.separator).frame(height: 0.5) }
                .shadow(color: .black.opacity(0.06), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
        // Reserved above the bar for the Record circle's overhang. It is filled with the page
        // background (scroll content would otherwise slide under it), so the circle never has
        // content behind it and the visible page ends cleanly above the bar.
        .padding(.top, Self.recordOverhang)
        .background(alignment: .top) {
            Color.jovra(.background).frame(height: Self.recordOverhang)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tabBar")
    }
}

/// One column: a 28 pt icon slot, the title and the selection dot. Every column, Record included,
/// has the same structure, so all five titles share one baseline.
private struct TabLabel: View {
    static let iconSlot: CGFloat = 28
    static let titleLineLimit = 3

    var tab: AppTab
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            icon
                .frame(height: Self.iconSlot)
            title
            SelectionDot(isVisible: isSelected)
        }
        .foregroundStyle(.jovra(isSelected ? .tabSelected : .tabUnselected))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// One line when the title fits its column. A longer title (a long translation) wraps onto up
    /// to three centred lines and only then shrinks, to 75 % at most, so it is never truncated. No
    /// single-line limit: the textClipped audit reports a tight one-line title as clipped.
    private var title: some View {
        Text(tab.title)
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .multilineTextAlignment(.center)
            .lineLimit(Self.titleLineLimit)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var icon: some View {
        switch tab {
        case .record:
            // The chartreuse circle sits on the icon slot's bottom (so the title below keeps the
            // shared baseline) and overflows upward, past the bar's top edge, into the strip the
            // bar reserves (JovraTabBar.recordOverhang): 46 - 28 - 8 pt of top padding = 10 pt.
            Color.clear
                .frame(width: Self.iconSlot)
                .overlay(alignment: .bottom) { RecordCircle() }
        case .insights:
            InsightsGlyph(isSelected: isSelected)
                .frame(width: 22, height: 21)
        default:
            Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
        }
    }
}

private struct RecordCircle: View {
    static let diameter: CGFloat = 46

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.jovra(.onAccent))
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Color.jovra(.accent), in: Circle())
            .overlay(Circle().strokeBorder(Color.jovra(.onAccent).opacity(0.08), lineWidth: 1))
    }
}

/// Three thin rounded bars rising left to right, as in the reference (SF Symbols' `chart.bar`
/// draws outlined boxes that read as "oOO" at tab size). Bolder when selected.
private struct InsightsGlyph: View {
    var isSelected: Bool

    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = isSelected ? 3.4 : 2.4
            let heights: [CGFloat] = [0.45, 0.72, 1]
            let step = (size.width - barWidth) / 2
            for (index, fraction) in heights.enumerated() {
                let height = size.height * fraction
                let rect = CGRect(x: CGFloat(index) * step, y: size.height - height, width: barWidth, height: height)
                context.fill(Capsule().path(in: rect), with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SelectionDot: View {
    var isVisible: Bool

    var body: some View {
        Circle()
            .fill(Color.jovra(.accent))
            .overlay(Circle().strokeBorder(Color.jovra(.onAccent).opacity(0.25), lineWidth: 0.5))
            .frame(width: 5, height: 5)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }
}
