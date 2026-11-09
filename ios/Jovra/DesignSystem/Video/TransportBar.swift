import JovraMedia
import SwiftUI

/// The transport row (screens.md S10 §5): rate menu, previous frame, play/pause, next frame and a fifth slot
/// the screen owns (Rally only on Replay, the A–B loop in the video lab). Frame buttons repeat while held.
/// Keyboard: space plays and pauses, ← and → step one frame.
struct TransportBar<Trailing: View>: View {
    var isPlaying: Bool
    var rate: PlaybackRate
    var canPlaySlow: Bool
    /// The playhead time, spoken with Play/Pause ("Play, 0:12.50").
    var timeText: String
    var onRate: (PlaybackRate) -> Void
    var onStep: (Int) -> Void
    var onPlayPause: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @State private var showsRates = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.x2) {
                rateMenu
                frameButton(-1)
                playButton
                frameButton(1)
                trailing()
            }
            VStack(spacing: Space.x2) {
                HStack(spacing: Space.x2) {
                    frameButton(-1)
                    playButton
                    frameButton(1)
                }
                HStack(spacing: Space.x2) {
                    rateMenu
                    trailing()
                }
            }
            // Narrow columns at the largest text sizes (the landscape side panel): play on its own row.
            VStack(spacing: Space.x2) {
                playButton
                HStack(spacing: Space.x2) {
                    frameButton(-1)
                    frameButton(1)
                }
                HStack(spacing: Space.x2) {
                    rateMenu
                    trailing()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The rate control: a disc showing the current rate that opens a small anchored list of the four rates.
    /// (A system `Menu` label does not follow Dynamic Type, so this is a button and a popover.)
    private var rateMenu: some View {
        Button { showsRates = true } label: {
            Text(verbatim: ReadoutFormat.rate(rate))
                .font(.headline.monospacedDigit())
                .fixedSize()
                .transportDisc(.secondary)
        }
        .buttonStyle(TransportPressStyle())
        .accessibilityLabel(Text("Playback speed", tableName: "DesignSystem.Video"))
        .accessibilityValue(Text(verbatim: ReadoutFormat.rate(rate)))
        .accessibilityIdentifier("transport.rate")
        .popover(isPresented: $showsRates) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(PlaybackRate.allCases, id: \.self) { option in
                    let unavailable = option.isSlow && !canPlaySlow
                    Button {
                        onRate(option)
                        showsRates = false
                    } label: {
                        HStack(spacing: Space.x2) {
                            Text(verbatim: ReadoutFormat.rate(option))
                                .font(.body.monospacedDigit().weight(option == rate ? .semibold : .regular))
                            Spacer(minLength: Space.x2)
                            if option == rate { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                        .foregroundStyle(.jovra(unavailable ? .textSecondary : .textPrimary))
                        .padding(.horizontal, Space.x2)
                        .frame(minWidth: 160, minHeight: HitTarget.minimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(unavailable)
                    .accessibilityAddTraits(option == rate ? .isSelected : [])
                    .accessibilityIdentifier("transport.rate.\(option.value)")
                }
                if !canPlaySlow {
                    Text("This video can't play slower than 1×", tableName: "DesignSystem.Video")
                        .font(.jovraCaption)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Space.x2)
                }
            }
            .padding(.vertical, Space.x1)
            .background(Color.jovra(.surface))
            .presentationCompactAdaptation(.popover)
        }
    }

    private func frameButton(_ direction: Int) -> some View {
        let title = direction < 0 ? String(localized: "Previous frame", table: "DesignSystem.Video")
                                  : String(localized: "Next frame", table: "DesignSystem.Video")
        return Button { onStep(direction) } label: {
            Image(systemName: direction < 0 ? "backward.frame.fill" : "forward.frame.fill")
                .font(.title2.weight(.semibold))
                .transportDisc(.secondary)
        }
        .buttonStyle(TransportPressStyle(onRepeat: { onStep(direction) }))
        .keyboardShortcut(direction < 0 ? .leftArrow : .rightArrow, modifiers: [])
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text("Hold to keep stepping.", tableName: "DesignSystem.Video"))
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: direction < 0 ? "backward.frame.fill" : "forward.frame.fill") }
        .accessibilityIdentifier(direction < 0 ? "transport.previousFrame" : "transport.nextFrame")
    }

    private var playButton: some View {
        let title = isPlaying ? String(localized: "Pause", table: "DesignSystem.Video") : String(localized: "Play", table: "DesignSystem.Video")
        return Button(action: onPlayPause) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title.weight(.bold))
                .transportDisc(.primary)
        }
        .buttonStyle(TransportPressStyle())
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: timeText))
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: isPlaying ? "pause.fill" : "play.fill") }
        .accessibilityIdentifier("transport.playPause")
    }
}

extension TransportBar where Trailing == EmptyView {
    init(isPlaying: Bool, rate: PlaybackRate, canPlaySlow: Bool, timeText: String, onRate: @escaping (PlaybackRate) -> Void,
         onStep: @escaping (Int) -> Void, onPlayPause: @escaping () -> Void) {
        self.init(isPlaying: isPlaying, rate: rate, canPlaySlow: canPlaySlow, timeText: timeText, onRate: onRate,
                  onStep: onStep, onPlayPause: onPlayPause, trailing: { EmptyView() })
    }
}

/// A round transport button face: 56 pt secondary discs, a 72 pt forest primary disc. Both grow with Dynamic
/// Type, and a label wider than the disc stretches it into a capsule rather than shrinking the text.
struct TransportDisc: ViewModifier {
    enum Kind { case primary, secondary }
    var kind: Kind
    var isSelected = false
    @ScaledMetric(relativeTo: .title3) private var secondarySize: CGFloat = 56
    @ScaledMetric(relativeTo: .title3) private var primarySize: CGFloat = 72
    static let secondaryCap: CGFloat = 84
    static let primaryCap: CGFloat = 104

    func body(content: Content) -> some View {
        // Grow with Dynamic Type, but stop where three discs no longer fit a phone's width.
        let size = kind == .primary ? min(primarySize, Self.primaryCap) : min(secondarySize, Self.secondaryCap)
        let filled = kind == .primary || isSelected
        content
            .foregroundStyle(.jovra(filled ? .onPrimaryFill : .textPrimary))
            .padding(.horizontal, Space.x2 - Space.half)
            .frame(minWidth: size, minHeight: size)
            .background(Capsule().fill(Color.jovra(filled ? .primaryFill : .surfaceSunken)))
            .overlay { if !filled { Capsule().strokeBorder(Color.jovra(.separator), lineWidth: 1) } }
            .contentShape(Capsule())
    }
}

extension View {
    func transportDisc(_ kind: TransportDisc.Kind, isSelected: Bool = false) -> some View {
        modifier(TransportDisc(kind: kind, isSelected: isSelected))
    }
}

/// Dims (and, without Reduce Motion, gently shrinks) a pressed transport disc. With `onRepeat`, holding the
/// button repeats it: after 0.4 s, about twelve times a second, until the finger lifts (user story 155).
struct TransportPressStyle: ButtonStyle {
    var onRepeat: (() -> Void)?

    static let repeatDelay: Duration = .milliseconds(400)
    static let repeatInterval: Duration = .milliseconds(80)

    func makeBody(configuration: Configuration) -> some View {
        PressedFace(configuration: configuration, onRepeat: onRepeat)
    }

    private struct PressedFace: View {
        let configuration: Configuration
        let onRepeat: (() -> Void)?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .opacity(!isEnabled ? 0.45 : (configuration.isPressed ? 0.78 : 1))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .animation(Motion.standard.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
                .task(id: configuration.isPressed) {
                    guard configuration.isPressed, isEnabled, let onRepeat else { return }
                    do {
                        try await Task.sleep(for: TransportPressStyle.repeatDelay)
                        while !Task.isCancelled {
                            onRepeat()
                            try await Task.sleep(for: TransportPressStyle.repeatInterval)
                        }
                    } catch {}
                }
        }
    }
}
