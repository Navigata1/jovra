import SwiftUI

/// Type styles. Everything is the system font and scales with Dynamic Type; metric numbers use
/// monospaced digits so values do not jitter as they change.
extension Font {
    /// Section and card headings ("Latest session").
    static let jovraHeadline = Font.title3.weight(.semibold)
    /// Editorial card titles ("Ready for your next session?").
    static let jovraEditorial = Font.largeTitle.weight(.bold)
    /// Letter-spaced capitals on editorial cards ("A BETTER GAME TOMORROW").
    static let jovraKicker = Font.caption2.weight(.semibold)
    /// Screen subtitles under the display title ("Your game, in focus.").
    static let jovraSubtitle = Font.title3
    static let jovraBody = Font.body
    static let jovraLabel = Font.subheadline.weight(.medium)
    static let jovraCaption = Font.footnote
    /// Large metric values on stat tiles ("6h 42m").
    static let jovraMetric = Font.system(.title, weight: .bold).monospacedDigit()
    /// Hero metrics ("67%").
    static let jovraMetricLarge = Font.system(.largeTitle, weight: .bold).monospacedDigit()
    /// Compact metric values on 4-up tile rows ("124").
    static let jovraMetricCompact = Font.system(.title2, weight: .bold).monospacedDigit()
    /// Scoreboard games and points ("6 4").
    static let jovraScore = Font.system(.title2, weight: .bold).monospacedDigit()
    /// Time and frame readouts ("f 46,000 · 12:46.67 · 60 fps").
    static let jovraTimecode = Font.system(.callout).monospacedDigit()
    /// Drill numbers: the metric size; callers draw it in secondary ink.
    static let jovraDrillNumber = jovraMetric
}

/// Court mode's recording timer ("12:46"): 64 pt, scaling relative to `.largeTitle`, monospaced digits
/// so the time never jitters.
struct RecTimerStyle: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .bold).monospacedDigit())
    }
}

/// The large confident screen title ("Good morning, Jon."): bigger than `.largeTitle`, still
/// scaling with Dynamic Type relative to it.
struct DisplayTitleStyle: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 38

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold))
            .tracking(-0.6)
            .foregroundStyle(.jovra(.textPrimary))
    }
}

extension View {
    func jovraDisplayTitle() -> some View { modifier(DisplayTitleStyle()) }
    func jovraRecTimer() -> some View { modifier(RecTimerStyle()) }
}
