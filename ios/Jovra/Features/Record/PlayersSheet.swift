import JovraCore
import SwiftUI

/// The players sheet (S04): names, handedness and backhand for everyone in play (stories 39, 40, 47),
/// previous opponents from saved sessions, who serves first and which end each side starts at (story
/// 44), and for doubles the serving order and deuce-court receivers per set (story 46). Changes apply
/// to the remembered setup as they are made.
struct PlayersSheet: View {
    nonisolated static let isPlaceholder = false
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        let setup = store.setup
        let doubles = setup.mode == .doublesMatch
        SetupSheet(route: .players, subtitle: subtitle(setup), doneIsEnabled: orderProblems(setup).isEmpty) {
            SetupSection(title: doubles ? String(localized: "Your team", table: "Record", comment: "Players sheet section")
                                        : String(localized: "You", table: "Record", comment: "Players sheet section")) {
                PlayerFields(seat: .me)
                if doubles { Divider().overlay(Color.jovra(.separator)); PlayerFields(seat: .partner) }
            }
            if setup.mode.isMatch {
                SetupSection(title: doubles ? String(localized: "Opponents", table: "Record", comment: "Players sheet section")
                                            : String(localized: "Opponent", table: "Record", comment: "Players sheet section")) {
                    RecentPlayerPicker()
                    PlayerFields(seat: .opponent)
                    if doubles { Divider().overlay(Color.jovra(.separator)); PlayerFields(seat: .opponentPartner) }
                }
                TossSection()
            }
            if doubles { DoublesOrderEditor() }
            SessionNameSection()
        }
    }

    private func subtitle(_ setup: SessionSetup) -> String {
        setup.mode.isMatch
            ? String(localized: "Names and hands label strokes and stats for both sides.", table: "Record", comment: "Players sheet subtitle")
            : String(localized: "Your name and hand label your strokes.", table: "Record", comment: "Players sheet subtitle, practice")
    }

    private func orderProblems(_ setup: SessionSetup) -> [SetupProblem] {
        setup.problems.filter { if case .doublesOrder = $0 { true } else { false } }
    }
}

/// Name, handedness and backhand for one seat.
private struct PlayerFields: View {
    var seat: SetupSeat
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Space.x2) {
            SetupTextField(label: nameLabel, text: name, identifier: "players.\(seat.rawValue).name")
            SegmentField(String(localized: "Plays", table: "Record", comment: "Handedness field label"),
                         values: [SessionPlayerHandedness.right, .left, .unknown], selection: $store.setup[seat].handedness,
                         identifier: "players.\(seat.rawValue).hand", title: SetupCopy.hand)
            SegmentField(String(localized: "Backhand", table: "Record", comment: "Backhand field label"),
                         values: [SessionPlayerBackhand.oneHanded, .twoHanded, .unknown], selection: $store.setup[seat].backhand,
                         identifier: "players.\(seat.rawValue).backhand", title: SetupCopy.backhand)
        }
        .padding(.vertical, Space.half)
    }

    private var nameLabel: String {
        switch seat {
        case .me: String(localized: "Your name", table: "Record", comment: "Name field")
        case .partner: String(localized: "Partner's name", table: "Record", comment: "Name field")
        case .opponent: String(localized: "Opponent's name", table: "Record", comment: "Name field")
        case .opponentPartner: String(localized: "Opponent's partner's name", table: "Record", comment: "Name field")
        }
    }

    /// Renaming someone picked from a previous session makes them a new person, so stats never join the
    /// wrong player.
    private var name: Binding<String> {
        Binding(get: { store.setup[seat].name }, set: { newValue in
            var player = store.setup[seat]
            let defaultID = SessionSetup()[seat].id
            if player.id != defaultID, newValue.trimmingCharacters(in: .whitespacesAndNewlines) != player.trimmedName {
                player.id = defaultID
            }
            player.name = newValue
            store.setup[seat] = player
        })
    }
}

/// Previous opponents and partners as one-tap chips (story 39).
private struct RecentPlayerPicker: View {
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text("Played before", tableName: "Record", comment: "Previous opponents heading")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.jovra(.textSecondary))
            let offered = RecentPlayers.offered(store.recentPlayers, for: store.setup)
            if offered.isEmpty {
                Text("People you record with appear here.", tableName: "Record", comment: "No previous opponents yet")
                    .font(.subheadline)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("players.recent.empty")
            } else {
                ChipFlow(spacing: Space.x1) {
                    ForEach(offered, id: \.id) { player in
                        Button { pick(player) } label: {
                            Text(player.name)
                                .font(.jovraLabel)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Space.x2)
                                .frame(minHeight: HitTarget.minimum)
                                .foregroundStyle(.jovra(.textPrimary))
                                .background(Color.jovra(.surfaceSunken), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Fills the opponent", tableName: "Record", comment: "Previous opponent chip hint"))
                        .accessibilityIdentifier("players.recent.\(player.id)")
                    }
                }
            }
        }
    }

    /// Fills the first opponent seat that is empty, else the opponent. Someone already in a seat is not
    /// offered, so one person never fills two seats.
    private func pick(_ player: SessionSetup.Player) {
        let seats: [SetupSeat] = store.setup.mode == .doublesMatch ? [.opponent, .opponentPartner] : [.opponent]
        let seat = seats.first { store.setup[$0].trimmedName.isEmpty } ?? .opponent
        store.setup[seat] = player
    }
}

/// Who serves first and which end the recording player's side starts at (story 44).
private struct TossSection: View {
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        let setup = store.setup
        SetupSection(title: String(localized: "Toss", table: "Record", comment: "Players sheet section"),
                     footnote: String(localized: "The scoreboard derives every later server and change of ends from these two answers.", table: "Record", comment: "Toss footnote")) {
            SegmentField(String(localized: "Serves first", table: "Record", comment: "First server field"),
                         values: setup.seatsInPlay, selection: firstServer, identifier: "players.firstServer") {
                SetupCopy.displayName(setup[$0], seat: $0)
            }
            SegmentField(String(localized: "Your side starts", table: "Record", comment: "Starting end field"),
                         values: [true, false], selection: startsNear, identifier: "players.startingEnd") { near in
                near ? String(localized: "Near the camera", table: "Record", comment: "Starting end")
                     : String(localized: "Far end", table: "Record", comment: "Starting end")
            }
        }
    }

    private var firstServer: Binding<SetupSeat> {
        Binding(get: { store.setup.effectiveFirstServer }, set: { seat in
            var next = store.setup
            next.firstServer = seat
            next.alignFirstOrderWithFirstServer()
            store.setup = next
        })
    }

    private var startsNear: Binding<Bool> {
        Binding(get: { store.setup.myTeamStartsNear }, set: { store.setup.myTeamStartsNear = $0 })
    }
}

/// An optional library title.
private struct SessionNameSection: View {
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        @Bindable var store = store
        SetupSection(title: String(localized: "Session name", table: "Record", comment: "Players sheet section"),
                     footnote: String(localized: "Optional. Leave it blank to call it “\(SetupCopy.defaultSessionName(store.setup))”.", table: "Record", comment: "Session name footnote")) {
            SetupTextField(label: String(localized: "Session name", table: "Record", comment: "Session name field"),
                           text: $store.setup.sessionName, identifier: "players.sessionName")
        }
    }
}
