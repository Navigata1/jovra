import SwiftUI

/// Type styles. Everything is the system font and scales with Dynamic Type; metric numbers use
/// monospaced digits so values do not jitter as they change.
extension Font {
    /// Section and card headings ("Latest session").
    static let jovraHeadline = Font.title3.weight(.semibold)
    /// Editorial card titles ("Ready for your next session?").
    static let jovraEditorial = Font.title.weight(.bold)
    /// Screen subtitles under the display title ("Your game, in focus.").
    static let jovraSubtitle = Font.title3
    static let jovraBody = Font.body
    static let jovraLabel = Font.subheadline.weight(.medium)
    static let jovraCaption = Font.footnote
    /// Large metric values on stat tiles ("6h 42m").
    static let jovraMetric = Font.system(.title, weight: .bold).monospacedDigit()
    /// Hero metrics ("67%").
    static let jovraMetricLarge = Font.system(.largeTitle, weight: .bold).monospacedDigit()
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
}
