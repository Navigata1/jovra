import SwiftUI

/// Custom tab bar matching the reference: Home · Sessions · raised chartreuse Record · Insights ·
/// Profile, with a small chartreuse dot under the selected tab (selection is also shown by a filled
/// symbol, bolder label and the VoiceOver "selected" trait, so it never relies on colour alone).
struct JovraTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if reduceMotion {
                        selection = tab
                    } else {
                        withAnimation(.snappy(duration: 0.2)) { selection = tab }
                    }
                } label: {
                    if tab == .record {
                        RecordTabLabel(isSelected: selection == tab)
                    } else {
                        TabLabel(tab: tab, isSelected: selection == tab)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityShowsLargeContentViewer {
                    Label(tab.title, systemImage: tab.symbol)
                }
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .padding(.horizontal, Space.x1)
        .padding(.top, Space.x1)
        .padding(.bottom, Space.half)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        // The raised Record button sits inside the bar (as in the Home reference), so no content
        // is ever drawn behind it.
        .padding(.top, RecordTabLabel.overhang)
        .background {
            Color.jovra(.tabBarBackground)
                .overlay(alignment: .top) { Color.jovra(.separator).frame(height: 0.5) }
                .shadow(color: .black.opacity(0.06), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tabBar")
    }
}

private struct TabLabel: View {
    var tab: AppTab
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                .frame(height: 28)
            Text(tab.title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
            SelectionDot(isVisible: isSelected)
        }
        .foregroundStyle(.jovra(isSelected ? .tabSelected : .tabUnselected))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct RecordTabLabel: View {
    static let overhang: CGFloat = 16
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.jovra(.onAccent))
                .frame(width: 58, height: 58)
                .background(Color.jovra(.accent), in: Circle())
                .overlay(Circle().strokeBorder(Color.jovra(.onAccent).opacity(0.08), lineWidth: 1))
                .padding(.top, -Self.overhang)
            Text(AppTab.record.title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(.jovra(isSelected ? .tabSelected : .tabUnselected))
                .fixedSize(horizontal: false, vertical: true)
            SelectionDot(isVisible: isSelected)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct SelectionDot: View {
    var isVisible: Bool

    var body: some View {
        Circle()
            .fill(Color.jovra(.accent))
            .overlay(Circle().strokeBorder(Color.jovra(.onAccent).opacity(0.25), lineWidth: 0.5))
            .frame(width: 6, height: 6)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }
}
