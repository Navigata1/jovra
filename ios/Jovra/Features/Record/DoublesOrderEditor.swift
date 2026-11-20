import JovraCore
import SwiftUI

/// Doubles serving order and deuce-court receivers, one block per set (story 46, Rules §2.4). An order
/// the scoring engine would refuse is shown with its reason and blocks recording until it is fixed;
/// a valid one becomes a `doublesOrder` event for its set when the session is created.
struct DoublesOrderEditor: View {
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        let setup = store.setup
        SetupSection(title: String(localized: "Serving order", table: "Record", comment: "Doubles section"),
                     footnote: String(localized: "Set 1 is needed now. Later sets can be added here or when they start.", table: "Record", comment: "Doubles order footnote")) {
            ForEach(Array(setup.doublesOrders.enumerated()), id: \.offset) { index, _ in
                if index > 0 { Divider().overlay(Color.jovra(.separator)) }
                SetOrderFields(index: index)
            }
            HStack(spacing: Space.x1) {
                if setup.doublesOrders.count < setup.maximumRecordedSets {
                    Button(String(localized: "Add set \(setup.doublesOrders.count + 1)", table: "Record", comment: "Adds the next set's serving order")) {
                        store.setup.addDoublesOrder()
                    }
                    .buttonStyle(.jovraCompact)
                    .accessibilityIdentifier("players.order.add")
                }
                if setup.doublesOrders.count > 1 {
                    Button(String(localized: "Remove set \(setup.doublesOrders.count)", table: "Record", comment: "Removes the last set's serving order")) {
                        store.setup.removeLastDoublesOrder()
                    }
                    .buttonStyle(.jovraCompact)
                    .accessibilityIdentifier("players.order.remove")
                }
            }
            .padding(.top, Space.half)
        }
    }
}

private struct SetOrderFields: View {
    var index: Int
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        let setup = store.setup
        let order = setup.doublesOrders.indices.contains(index) ? setup.doublesOrders[index] : .standard
        let name = { (seat: SetupSeat) in SetupCopy.displayName(setup[seat], seat: seat) }
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Set \(index + 1)", tableName: "Record", comment: "Doubles order block heading")
                .font(.body.weight(.semibold))
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            if index == 0 {
                Text("\(name(order.firstServer)) serves first.", tableName: "Record", comment: "Set 1 first server follows the toss")
                    .font(.subheadline)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SegmentField(String(localized: "First server", table: "Record", comment: "Doubles order field"),
                             values: SetupSeat.allCases, selection: field(\.firstServer), identifier: "players.order.\(index + 1).first", title: name)
            }
            SegmentField(String(localized: "Second server", table: "Record", comment: "Doubles order field"),
                         values: SetupSeat.allCases.filter { $0 != order.firstServer }, selection: field(\.secondServer),
                         identifier: "players.order.\(index + 1).second", title: name)
            SegmentField(String(localized: "Deuce court, your team", table: "Record", comment: "Doubles order field"),
                         values: [SetupSeat.me, .partner], selection: field(\.deuceReceiverA),
                         identifier: "players.order.\(index + 1).receiverA", title: name)
            SegmentField(String(localized: "Deuce court, opponents", table: "Record", comment: "Doubles order field"),
                         values: [SetupSeat.opponent, .opponentPartner], selection: field(\.deuceReceiverB),
                         identifier: "players.order.\(index + 1).receiverB", title: name)
            let problems = order.problems(setIndex: index, matchFirstServer: setup.effectiveFirstServer)
            ForEach(problems, id: \.self) { problem in
                Label {
                    Text(SetupCopy.doublesProblem(problem, set: index + 1)).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.jovra(.attentionInk))
                .padding(Space.x1 + Space.half)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.jovra(.attentionFill), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("players.order.\(index + 1).problem")
            }
        }
        .padding(.vertical, Space.half)
    }

    private func field(_ keyPath: WritableKeyPath<DoublesOrder, SetupSeat>) -> Binding<SetupSeat> {
        // A block being removed can be read once more after its set is gone.
        Binding(get: { store.setup.doublesOrders.indices.contains(index) ? store.setup.doublesOrders[index][keyPath: keyPath] : .me },
                set: { if store.setup.doublesOrders.indices.contains(index) { store.setup.doublesOrders[index][keyPath: keyPath] = $0 } })
    }
}
