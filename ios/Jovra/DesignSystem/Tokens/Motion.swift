import SwiftUI

/// Named motion (screens.md §5.3). Every animation in the app goes through `animation(reduceMotion:)`,
/// the one place Reduce Motion is honoured: with it on there is no animation at all, and views that
/// need a change of state to be noticed use an opacity transition instead (user story 360).
enum Motion: CaseIterable {
    /// Snappy 0.25 s: selection, toggles, sheets of content swapping in place.
    case standard
    /// Ease-out 0.2 s: something appearing (a toast, a popover's content, a banner).
    case reveal

    func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return switch self {
        case .standard: .snappy(duration: 0.25)
        case .reveal: .easeOut(duration: 0.2)
        }
    }

    /// Slides and scales become a plain fade under Reduce Motion.
    static func transition(edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

/// Reads Reduce Motion from the system and from the launch harness (`-reduceMotion yes`), as AppRoot does.
struct MotionPreference: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.launchConfiguration) private var launch
    var motion: Motion
    var value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(motion.animation(reduceMotion: systemReduceMotion || launch.reduceMotion), value: value)
    }
}

extension View {
    /// `animation(_:value:)` for a named motion, resolving to none under Reduce Motion.
    func jovraAnimation(_ motion: Motion, value: some Hashable) -> some View {
        modifier(MotionPreference(motion: motion, value: AnyHashable(value)))
    }
}

/// The haptic set (screens.md §5.3), used with `.sensoryFeedback(_:trigger:)`.
enum Haptic: CaseIterable {
    /// Mode and segment changes.
    case selection
    /// Mark point, Save.
    case success
    /// A heat rung, low storage.
    case warning

    var feedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .success: .success
        case .warning: .warning
        }
    }
}

extension View {
    func jovraHaptic(_ haptic: Haptic, trigger: some Equatable) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }
}
