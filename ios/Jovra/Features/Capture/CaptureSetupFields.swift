import SwiftUI

struct CaptureSetupFields: View {
    @Binding var choices: CaptureSetupChoices

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            field(String(localized: "Session title", table: "Capture"), text: $choices.title, id: "capture.setup.title")
            field(String(localized: "Your name", table: "Capture"), text: $choices.playerA, id: "capture.setup.playerA")
            field(String(localized: "Opponent's name", table: "Capture"), text: $choices.playerB, id: "capture.setup.playerB")
            selection(String(localized: "Match format", table: "Capture"),
                      value: choices.format == .bestOfOne ? String(localized: "Best of one set", table: "Capture") : String(localized: "Best of three sets", table: "Capture")) {
                Picker(String(localized: "Match format", table: "Capture"), selection: $choices.format) {
                    Text("Best of one set", tableName: "Capture").tag(CaptureSetupChoices.Format.bestOfOne)
                    Text("Best of three sets", tableName: "Capture").tag(CaptureSetupChoices.Format.bestOfThree)
                }
            }
            Toggle(isOn: $choices.noAd) {
                HStack {
                    Image(systemName: choices.noAd ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                    Text("No-ad scoring", tableName: "Capture").fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 64)
            }
            .toggleStyle(.button).buttonStyle(.jovraSecondary)
            .accessibilityIdentifier("capture.setup.noAd")
            selection(String(localized: "First server", table: "Capture"), value: playerName(choices.firstServer)) {
                Picker(String(localized: "First server", table: "Capture"), selection: $choices.firstServer) { players }
            }
            selection(String(localized: "Starting near the camera", table: "Capture"), value: playerName(choices.nearPlayer)) {
                Picker(String(localized: "Starting near the camera", table: "Capture"), selection: $choices.nearPlayer) { players }
            }
            Text("Six-game sets · Tiebreak at 6–6 · Let serves", tableName: "Capture")
                .font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.jovraBody)
        .jovraCard(padding: Space.x2)
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title).foregroundStyle(.jovra(.textSecondary)).fixedSize(horizontal: false, vertical: true)
            JovraTextInput(text: text, title: title, identifier: id)
                .padding(.horizontal, Space.x2).frame(minHeight: 64)
                .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control))
        }
    }

    private func selection<Options: View>(_ title: String, value: String, @ViewBuilder options: () -> Options) -> some View {
        Menu { options() } label: {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title).font(.jovraLabel)
                Text(value).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }.buttonStyle(.jovraSecondary).accessibilityLabel(title).accessibilityValue(value)
    }

    private func playerName(_ player: CaptureSetupChoices.Player) -> String {
        player == .a ? (choices.playerA.isEmpty ? String(localized: "Player A", table: "Capture") : choices.playerA)
            : (choices.playerB.isEmpty ? String(localized: "Player B", table: "Capture") : choices.playerB)
    }

    @ViewBuilder private var players: some View {
        Text(choices.playerA.isEmpty ? String(localized: "Player A", table: "Capture") : choices.playerA)
            .tag(CaptureSetupChoices.Player.a)
        Text(choices.playerB.isEmpty ? String(localized: "Player B", table: "Capture") : choices.playerB)
            .tag(CaptureSetupChoices.Player.b)
    }
}
