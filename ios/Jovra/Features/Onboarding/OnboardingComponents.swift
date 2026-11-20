import JovraCore
import SwiftUI

// MARK: - StepRail

/// Three numbered nodes joined by a line (screens.md S02): done = forest fill and a check, current = chartreuse
/// fill and its number, upcoming = sunken fill and its number, labels under the nodes. One VoiceOver element:
/// "Step 2 of 3, Profile".
struct StepRail: View {
    var current: Int
    var labels: [String]

    @ScaledMetric(relativeTo: .subheadline) private var node: CGFloat = 32
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Space.x1) {
            HStack(spacing: 0) {
                ForEach(Array(labels.indices), id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.jovra(index < current ? .primaryFill : .separator))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                    nodeView(step: index + 1)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                // Three labels cannot fit at accessibility sizes: one line names the current step.
                Text(verbatim: "\(current). \(labels[max(0, min(labels.count, current) - 1)])")
                    .font(.jovraLabel.weight(.semibold))
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
            HStack(alignment: .top, spacing: Space.x1) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(verbatim: "\(index + 1). \(label)")
                        .font(.jovraLabel.weight(index + 1 == current ? .semibold : .regular))
                        .foregroundStyle(.jovra(index + 1 == current ? .textPrimary : .textSecondary))
                        .multilineTextAlignment(alignment(for: index))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: frameAlignment(for: index))
                }
            }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current) of \(labels.count), \(labels[max(0, min(labels.count, current) - 1)])",
                                 tableName: "Onboarding", comment: "Step rail, e.g. Step 2 of 3, Profile"))
        .accessibilityIdentifier("onboarding.stepRail")
    }

    private func nodeView(step: Int) -> some View {
        ZStack {
            Circle().fill(Color.jovra(step < current ? .primaryFill : step == current ? .accent : .surfaceSunken))
            if step < current {
                Image(systemName: "checkmark")
                    .font(.system(size: node * 0.42, weight: .bold))
                    .foregroundStyle(.jovra(.onPrimaryFill))
            } else {
                Text(verbatim: "\(step)")
                    .font(.system(size: node * 0.44, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.jovra(step == current ? .onAccent : .textSecondary))
            }
        }
        .frame(width: node, height: node)
    }

    private func alignment(for index: Int) -> TextAlignment {
        index == 0 ? .leading : index == labels.count - 1 ? .trailing : .center
    }

    private func frameAlignment(for index: Int) -> Alignment {
        index == 0 ? .leading : index == labels.count - 1 ? .trailing : .center
    }
}

// MARK: - ChoiceSegment

/// Two or three options in a sunken track, each an icon and text; nothing is selected until the player chooses
/// (screens.md S02). The selected option is forest with ivory text and carries the selected trait. Options stack at
/// accessibility text sizes.
struct ChoiceSegment<Option: Hashable>: View {
    var options: [Option]
    @Binding var selection: Option?
    var title: (Option) -> String
    var symbol: ((Option) -> String?)? = nil
    var mirrorsSymbols = false
    var identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.half)) : AnyLayout(HStackLayout(spacing: Space.half))
        layout {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    HStack(spacing: Space.x1 + Space.half) {
                        if let name = symbol?(option) {
                            Image(systemName: name)
                                .font(.title3)
                                .scaleEffect(x: mirrorsSymbols ? -1 : 1, y: 1)
                                .accessibilityHidden(true)
                        }
                        Text(title(option))
                            .font(.jovraLabel)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Text-only segments ("Competitive") need the room more than the inset.
                    .padding(.horizontal, symbol == nil ? Space.x1 : Space.x2)
                    .padding(.vertical, Space.x1 + Space.half)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.jovra(selected ? .onPrimaryFill : .textPrimary))
                    .background(selected ? Color.jovra(.primaryFill) : .clear, in: shape)
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(Text("\(index + 1) of \(options.count)", tableName: "Onboarding", comment: "Position of a choice, e.g. 1 of 2"))
                .accessibilityIdentifier("\(identifier).\(index)")
            }
        }
        .padding(Space.half)
        .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control + 4, style: .continuous))
        .jovraAnimation(.standard, value: selection)
        .jovraHaptic(.selection, trigger: selection)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.control, style: .continuous) }
}

// MARK: - GoalChips

/// The goals grid (S02): two columns of toggle chips, one column at accessibility sizes. A selected chip is chartreuse
/// with a filled check; the check's shape, not only the colour, says it is chosen. A fourth goal is refused with a
/// caption that is announced.
struct GoalChips: View {
    @Binding var profile: PlayerProfile
    @State private var refused = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            // Plain rows rather than a lazy grid: every chip exists, so text sizes and VoiceOver reach all six.
            let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 2
            let goals = PlayerGoal.allCases
            VStack(spacing: Space.x1) {
                ForEach(Array(stride(from: 0, to: goals.count, by: perRow)), id: \.self) { start in
                    HStack(alignment: .top, spacing: Space.x1) {
                        ForEach(goals[start..<min(start + perRow, goals.count)], id: \.self) { goal in
                            chip(goal)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if refused {
                Label {
                    Text("Up to 3 goals. Deselect one to choose another.", tableName: "Onboarding")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.jovraLabel)
                .foregroundStyle(.jovra(.attentionInk))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.goals.limit")
            }
        }
        .jovraAnimation(.reveal, value: refused)
    }

    private func chip(_ goal: PlayerGoal) -> some View {
        let selected = profile.goals.contains(goal)
        let shape = RoundedRectangle(cornerRadius: Radius.control + 4, style: .continuous)
        return Button {
            switch profile.toggleGoal(goal) {
            case .refusedLimitReached:
                refused = true
                AccessibilityNotification.Announcement(String(localized: "Up to 3 goals. Deselect one to choose another.", table: "Onboarding")).post()
            case .selected, .deselected:
                refused = false
            }
        } label: {
            HStack(spacing: Space.x1 + Space.half) {
                Image(systemName: goal.symbol)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(goal.title)
                    .font(.jovraLabel)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(.jovra(selected ? .onAccent : .textSecondary))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.x2 - Space.half)
            .padding(.vertical, Space.x1 + Space.half)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(.jovra(selected ? .onAccent : .textPrimary))
            .background(Color.jovra(selected ? .accent : .surfaceSunken), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
        .jovraHaptic(.selection, trigger: selected)
    }
}

// MARK: - Field group

/// A labelled group ("Playing hand"): the label is a VoiceOver header.
struct ProfileFieldGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(title)
                .font(.jovraLabel)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}
