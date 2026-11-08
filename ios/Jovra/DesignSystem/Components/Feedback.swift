import SwiftUI

// MARK: - BannerView

/// An inline banner (info, positive, attention): symbol, title, message and up to two actions.
/// Used for conflicts, recovery and failures; a failure says what happened, what is safe and what
/// the player can do (user story 385). Tone is carried by the symbol and words; the tint reinforces it.
struct BannerView: View {
    enum Tone { case info, positive, attention }

    var tone: Tone
    var title: String
    var message: String?
    var primaryAction: StateCard.Action?
    var secondaryAction: StateCard.Action?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x1 + Space.half) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.jovra(ink))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.jovra(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if primaryAction != nil || secondaryAction != nil {
                // One set of buttons whose layout changes at accessibility sizes. (ViewThatFits would
                // swap in a second copy as text grows, so the first copy never scales.)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x1))
                    : AnyLayout(HStackLayout(spacing: Space.x1))
                layout { actions }
            }
        }
        .padding(Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jovra(fill), in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        .overlay(alignment: .leading) {
            // A leading rule in the tone's ink: a second, non-colour cue is the symbol's shape.
            UnevenRoundedRectangle(topLeadingRadius: Radius.control + 2, bottomLeadingRadius: Radius.control + 2)
                .fill(Color.jovra(ink))
                .frame(width: 4)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actions: some View {
        if let primaryAction {
            Button(primaryAction.title, action: primaryAction.perform)
                .buttonStyle(JovraButtonStyle(kind: .primary, size: .compact))
        }
        if let secondaryAction {
            Button(secondaryAction.title, action: secondaryAction.perform)
                .buttonStyle(JovraButtonStyle(kind: .secondary, size: .compact))
        }
    }

    private var symbol: String {
        switch tone {
        case .info: "info.circle.fill"
        case .positive: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        }
    }

    private var ink: ColorRole {
        switch tone {
        case .info: .textPrimary
        case .positive: .positiveInk
        case .attention: .attentionInk
        }
    }

    private var fill: ColorRole {
        switch tone {
        case .info: .surfaceSunken
        case .positive: .positiveFill
        case .attention: .attentionFill
        }
    }
}

// MARK: - InfoCard

/// Icon, title and body (S02, S07, N5); a positive tint for reassurance ("Your video is safe"),
/// neutral otherwise.
struct InfoCard: View {
    enum Tone { case positive, neutral }

    var symbol: String
    var title: String
    var message: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: Space.x2) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.jovra(tone == .positive ? .positiveInk : .textPrimary))
                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                .background(Color.jovra(tone == .positive ? .surface : .surfaceSunken), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.half) {
                Text(title)
                    .font(.jovraLabel.weight(.semibold))
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.jovra(tone == .positive ? .positiveFill : .surface),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Color.jovra(.separator), lineWidth: tone == .positive ? 0 : 0.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Toast and UndoBar

/// Posts VoiceOver announcements. The Toast seam: tests inject a spy.
@MainActor
protocol AccessibilityAnnouncing {
    func announce(_ message: String)
}

struct VoiceOverAnnouncer: AccessibilityAnnouncing {
    func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Transient confirmations: a Toast (4 s) or an UndoBar (8 s), one at a time, each announced to
/// VoiceOver when it appears. A toast is never the only place a result is shown.
@MainActor
@Observable
final class ToastCenter {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let duration: Duration
        let canUndo: Bool
    }

    static let toastDuration = Duration.seconds(4)
    static let undoDuration = Duration.seconds(8)

    private(set) var current: Message?
    /// The pending dismissal of `current`.
    private(set) var expiry: Task<Void, Never>?
    @ObservationIgnored private var undoAction: (() -> Void)?
    @ObservationIgnored private let announcer: any AccessibilityAnnouncing
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void

    init(announcer: any AccessibilityAnnouncing = VoiceOverAnnouncer(),
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.announcer = announcer
        self.sleep = sleep
    }

    /// Shows `text`; with `undo`, as an UndoBar whose Undo runs the action once.
    func show(_ text: String, undo: (() -> Void)? = nil) {
        let message = Message(text: text, duration: undo == nil ? Self.toastDuration : Self.undoDuration, canUndo: undo != nil)
        expiry?.cancel()
        current = message
        undoAction = undo
        announcer.announce(text)
        let sleep = sleep
        expiry = Task { [weak self] in
            await sleep(message.duration)
            guard !Task.isCancelled else { return }
            self?.expire(message.id)
        }
    }

    func undo() {
        guard let action = undoAction else { return }
        undoAction = nil
        dismiss()
        action()
    }

    func dismiss() {
        expiry?.cancel()
        current = nil
        undoAction = nil
    }

    private func expire(_ id: UUID) {
        guard current?.id == id else { return }
        current = nil
        undoAction = nil
    }
}

/// The toast or UndoBar itself: inverse fill (forest on ivory, ivory on forest) so it reads as a
/// layer above the page.
struct ToastView: View {
    var message: ToastCenter.Message
    var undo: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.x1 + Space.half) {
            Image(systemName: message.canUndo ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.jovra(.onPrimaryFill))
                .accessibilityHidden(true)
            Text(verbatim: message.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.jovra(.onPrimaryFill))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if message.canUndo {
                Button(String(localized: "Undo", table: "DesignSystem.Components"), action: undo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.jovra(.onPrimaryFill))
                    .underline()
                    .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("toast.undo")
            } else {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.jovra(.onPrimaryFill))
                .accessibilityLabel(Text("Dismiss", tableName: "DesignSystem.Components"))
            }
        }
        .padding(.leading, Space.x2)
        .padding(.trailing, Space.half)
        .padding(.vertical, Space.half)
        .background(Color.jovra(.primaryFill), in: RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(message.canUndo ? "undoBar" : "toast")
    }
}

private struct ToastHost: ViewModifier {
    var center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = center.current {
                ToastView(message: message, undo: center.undo, dismiss: center.dismiss)
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.bottom, Space.x2)
                    .frame(maxWidth: ReadableColumn.maximumWidth)
                    .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                    .id(message.id)
            }
        }
        .animation(Motion.reveal.animation(reduceMotion: reduceMotion), value: center.current)
    }
}

extension View {
    /// Shows `center`'s toast or UndoBar above this view's bottom edge.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHost(center: center))
    }
}
