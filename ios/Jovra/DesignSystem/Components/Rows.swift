import SwiftUI

/// Section heading with an optional trailing action ("Latest session · View all").
struct SectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.x1)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A round avatar: the player's initial, or the JV mark when there is no profile yet.
struct AvatarInitial: View {
    var initial: String?
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(Color.jovra(.editorial))
            if let initial {
                Text(initial.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.jovra(.textOnEditorial))
            } else {
                CourtArcMark(letters: .jovra(.textOnEditorial))
                    .padding(size * 0.22)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A settings-style row: symbol, title, optional subtitle and trailing content.
struct SettingsRow<Trailing: View>: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var titleRole: ColorRole = .textPrimary
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Space.x2) {
            // At accessibility text sizes the decorative symbol gives its width to the text.
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.jovra(titleRole))
                    .frame(width: 32)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(.jovra(titleRole))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.x1)
            trailing
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == SettingsChevron {
    init(symbol: String, title: String, subtitle: String? = nil, titleRole: ColorRole = .textPrimary) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, titleRole: titleRole) { SettingsChevron() }
    }
}

struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.jovra(.textSecondary))
            .accessibilityHidden(true)
    }
}
