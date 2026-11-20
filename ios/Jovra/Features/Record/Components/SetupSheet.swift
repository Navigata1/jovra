import SwiftUI

/// The frame every setup sheet shares: a 44 pt Close control at top leading ("Close players"), the
/// sheet's name as its title, scrolling content, and a Done button. Changes apply as they are made, so
/// Close and Done both keep them; Done is the obvious way out after the last field.
struct SetupSheet<Content: View>: View {
    var route: SheetRoute
    var subtitle: String? = nil
    var doneIsEnabled = true
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let info = AppDestination.sheet(route).info
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: info.closeLabel ?? info.title, identifier: "sheet.close") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, Space.x2)
            .padding(.top, Space.x1)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    VStack(alignment: .leading, spacing: Space.half) {
                        Text(info.title)
                            .jovraDisplayTitle()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("screen.title")
                        if let subtitle {
                            Text(subtitle)
                                .font(.jovraBody)
                                .foregroundStyle(.jovra(.textSecondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content
                    Button(String(localized: "Done", table: "Record", comment: "Closes a setup sheet")) { dismiss() }
                        .buttonStyle(.jovraPrimary)
                        .disabled(!doneIsEnabled)
                        .accessibilityIdentifier("sheet.done")
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.x1)
                .padding(.bottom, Space.x4)
                .frame(maxWidth: ReadableColumn.maximumWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("setupSheet.scroll")
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.container")
    }
}

/// A titled block inside a setup sheet.
struct SetupSection<Content: View>: View {
    var title: String
    var footnote: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            SectionHeader(title: title)
            // The footnote sits inside the card: on the page it would fall in the card's shadow.
            VStack(alignment: .leading, spacing: Space.x1) {
                content
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.half)
                }
            }
            .padding(Space.x2)
            .jovraCard(padding: 0)
        }
    }
}

/// A labelled segmented choice over `FilterPills`.
struct SegmentField<Option: Hashable & Identifiable>: View {
    var label: String
    var options: [Option]
    @Binding var selection: Option
    var identifier: String
    var title: (Option) -> String

    /// The visible label is not a separate VoiceOver stop: the group, label included, is one container
    /// named by it, so the label's text lies inside an element that carries the same words.
    var body: some View {
        VStack(alignment: .leading, spacing: Space.half + 2) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            FilterPills(options: options, selection: $selection, title: title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityIdentifier(identifier)
    }
}

/// Wraps any hashable value so it can be a `FilterPills` option.
struct Pick<Value: Hashable>: Hashable, Identifiable {
    var value: Value
    var id: Value { value }
}

extension SegmentField {
    /// A segmented choice over plain values.
    init<Value: Hashable>(_ label: String, values: [Value], selection: Binding<Value>, identifier: String,
                          title: @escaping (Value) -> String) where Option == Pick<Value> {
        self.init(label: label, options: values.map(Pick.init),
                  selection: Binding(get: { Pick(value: selection.wrappedValue) }, set: { selection.wrappedValue = $0.value }),
                  identifier: identifier, title: { title($0.value) })
    }
}

/// A labelled text field at least 56 pt tall. `showsLabel` false when the section title above already
/// says the same words (VoiceOver still reads the label on the field). As with `SegmentField`, the
/// label and field form one container named by the label, so the visible label is never text without
/// an accessibility element, even when scrolling cuts it at the sheet's edge.
struct SetupTextField: View {
    var label: String
    @Binding var text: String
    var identifier: String
    var showsLabel = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.half + 2) {
            if showsLabel {
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            JovraTextInput(text: $text, title: label, identifier: identifier)
                .padding(.horizontal, Space.x2)
                .frame(minHeight: 56)
                .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
    }
}
