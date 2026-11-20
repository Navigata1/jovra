import SwiftUI

/// How the pre-shell moves (screens.md §1, pre-shell row: "cross-fade; no animation with Reduce Motion"), the one
/// source for both the transition and the animation, so what the app does is what `PreShellMotionTests` checks.
///
/// - Root swap (pre-shell ⇄ shell, read by `AppRoot`): a 0.3 s cross-fade; with Reduce Motion an instant swap.
/// - Onboarding step change (read by `OnboardingScreen`): the step slides in with `Motion.standard`; with Reduce
///   Motion an instant swap. Nothing moves or fades under Reduce Motion.
enum PreShellMotion: Equatable {
    case slide(Edge)
    case crossFade
    /// No animation and no transition: the new view replaces the old one in the same frame.
    case instant

    static func rootSwap(reduceMotion: Bool) -> PreShellMotion {
        reduceMotion ? .instant : .crossFade
    }

    static func stepChange(forward: Bool, reduceMotion: Bool) -> PreShellMotion {
        reduceMotion ? .instant : .slide(forward ? .trailing : .leading)
    }

    var transition: AnyTransition {
        switch self {
        case .slide(let edge): .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .opacity)
        case .crossFade: .opacity
        case .instant: .identity
        }
    }

    /// nil means the change is not animated at all.
    var animation: Animation? {
        switch self {
        case .slide: Motion.standard.animation(reduceMotion: false)
        case .crossFade: .easeInOut(duration: 0.3)
        case .instant: nil
        }
    }
}
