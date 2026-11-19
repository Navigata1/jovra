import JovraCore
import SwiftUI

/// One of the four session modes (S04): vector art, symbol, title, description and a radio. Selected is a
/// forest fill with ivory text and a chartreuse dot; the radio's shape and VoiceOver's "Selected" carry
/// the state as well, never the colour alone. The art steps aside at accessibility text sizes.
struct ModeRow: View {
    var mode: SessionSetup.Mode
    var isSelected: Bool
    var position: Int
    var count: Int
    var select: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: Space.x1 + Space.half) {
                if !dynamicTypeSize.isAccessibilitySize {
                    ModeArt(mode: mode)
                        .frame(width: 92, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .accessibilityHidden(true)
                    Image(systemName: SetupCopy.modeSymbol(mode))
                        .font(.title3)
                        .foregroundStyle(ink(.textPrimary, selected: .textOnEditorial))
                        .frame(width: 26)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(SetupCopy.modeTitle(mode))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink(.textPrimary, selected: .textOnEditorial))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SetupCopy.modeDescription(mode))
                        .font(.subheadline)
                        .foregroundStyle(ink(.textSecondary, selected: .textSecondaryOnEditorial))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioMark(isSelected: isSelected, onEditorial: isSelected)
            }
            .padding(.vertical, Space.x1 + Space.half)
            .padding(.leading, Space.x1 + Space.half)
            .padding(.trailing, Space.x2)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(SetupCopy.modeTitle(mode)), \(SetupCopy.modeDescription(mode))"))
        .accessibilityValue(Text("\(position) of \(count)", tableName: "Record", comment: "Position in the mode radio group"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("record.mode.\(mode.rawValue)")
    }

    private func ink(_ role: ColorRole, selected: ColorRole) -> Color { .jovra(isSelected ? selected : role) }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if isSelected {
            shape.fill(Color(uiColor: ColorRole.editorial.color(in: colorScheme == .dark ? .dark : .light).uiColor))
                // On a forest page the fill alone barely separates it, so the chartreuse edge is stronger in dark.
                .overlay(shape.strokeBorder(Color.jovra(.accent).opacity(colorScheme == .dark ? 0.9 : 0.55),
                                            lineWidth: colorScheme == .dark ? 2 : 1.5))
        } else {
            shape.fill(Color.jovra(.surface))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 10, x: 0, y: 4)
                .overlay(shape.strokeBorder(Color.jovra(.separator), lineWidth: colorScheme == .dark ? 1 : 0.5))
        }
    }
}

/// A radio: an empty ring, or a ring with a filled dot when selected (the shape carries the state).
struct RadioMark: View {
    var isSelected: Bool
    var onEditorial = false
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle().strokeBorder(ring, lineWidth: 2)
            if isSelected {
                Circle().fill(Color.jovra(.accent)).padding(min(size, 34) * 0.22)
            }
        }
        // Grows with text, but never so far that it takes the words' width at accessibility sizes.
        .frame(width: min(size, 34), height: min(size, 34))
        .accessibilityHidden(true)
    }

    private var ring: Color {
        if onEditorial { return .jovra(isSelected ? .accent : .textOnEditorial) }
        return .jovra(isSelected ? .positiveInk : .textSecondary)
    }
}
