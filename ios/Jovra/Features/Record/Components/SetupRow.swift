import SwiftUI

/// A setup row (S04): symbol, small label, value, optional detail line and a chevron when it opens
/// something. VoiceOver reads label, value and detail as one element. At accessibility sizes the symbol
/// gives its width to the words, which wrap rather than clip.
struct SetupRow<Accessory: View>: View {
    var symbol: String
    var label: String
    var value: String
    var detail: String? = nil
    var detailIsAttention = false
    /// Words VoiceOver reads after the value that the row shows another way (a badge).
    var spokenNote: String? = nil
    var identifier: String
    var action: (() -> Void)? = nil
    @ViewBuilder var accessory: Accessory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let action {
            Button(action: action) { content(chevron: true) }
                .buttonStyle(SetupRowButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityValue(Text(verbatim: spokenValue))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(identifier)
        } else {
            content(chevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityValue(Text(verbatim: spokenValue))
                .accessibilityIdentifier(identifier)
        }
    }

    private var spokenValue: String { [value, spokenNote, detail].compactMap { $0 }.joined(separator: ", ") }

    private func content(chevron: Bool) -> some View {
        HStack(alignment: .center, spacing: Space.x2) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.jovra(.textPrimary))
                    .frame(width: 32)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(.body)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                accessory
                if let detail {
                    Label {
                        Text(detail).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        if detailIsAttention { Image(systemName: "exclamationmark.triangle.fill") }
                    }
                    .labelStyle(DetailLabelStyle(showsIcon: detailIsAttention))
                    .font(.subheadline)
                    .foregroundStyle(.jovra(detailIsAttention ? .attentionInk : .textSecondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron { SettingsChevron() }
        }
        .padding(.vertical, Space.x1 + Space.half)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

extension SetupRow where Accessory == EmptyView {
    init(symbol: String, label: String, value: String, detail: String? = nil, detailIsAttention: Bool = false,
         identifier: String, action: (() -> Void)? = nil) {
        self.init(symbol: symbol, label: label, value: value, detail: detail, detailIsAttention: detailIsAttention,
                  spokenNote: nil, identifier: identifier, action: action) { EmptyView() }
    }
}

private struct DetailLabelStyle: LabelStyle {
    var showsIcon: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.half + 2) {
            if showsIcon { configuration.icon.accessibilityHidden(true) }
            configuration.title
        }
    }
}

/// Pressed rows dim slightly; no scale, so a list never wobbles.
struct SetupRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A selectable option in a sheet: radio, title and optional detail; disabled options say why.
struct ChoiceRow: View {
    var title: String
    var detail: String? = nil
    var isSelected: Bool
    var isEnabled = true
    var identifier: String
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: Space.x2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.jovra(isEnabled ? .textPrimary : .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.jovra(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isEnabled { RadioMark(isSelected: isSelected) }
            }
            .padding(.vertical, Space.x1 + Space.half)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(SetupRowButtonStyle())
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: detail ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// Rows inside one card, separated by hairlines.
struct SetupRowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().overlay(Color.jovra(.separator)) }
                    row
                }
            }
        }
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.half)
        .jovraCard(padding: 0)
    }
}
