import SwiftUI

/// Shown instead of any surface when the launch arguments cannot be used (an unknown `-watchState`, a missing
/// value): what was wrong and every registered value, so a test or a developer sees the fix at once.
struct HarnessProblemView: View {
    let problems: [String]
    let registered: [String]
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchStatePanel(symbol: "exclamationmark.triangle",
                                title: Text("Can't open this state", tableName: "Watch"),
                                message: Text(verbatim: problems.joined(separator: "\n")),
                                tint: WatchPalette.clayInk)
                    .accessibilityIdentifier("watch.harness.problem")
                Text("Registered states", tableName: "Watch")
                    .font(.watchTitle)
                    .foregroundStyle(WatchPalette.ivory)
                    .accessibilityAddTraits(.isHeader)
                ForEach(registered, id: \.self) { value in
                    Text(verbatim: value)
                        .font(.watchCaption.monospaced())
                        .foregroundStyle(WatchPalette.secondaryText(contrast))
                        .accessibilityIdentifier("watch.harness.registered.\(value)")
                }
            }
        }
        .background(WatchPalette.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.harness.problems")
    }
}
