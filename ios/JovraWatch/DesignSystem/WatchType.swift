import SwiftUI

/// Watch type styles. All are system text styles (SF Compact) so they follow Dynamic Type; numbers use monospaced
/// digits so values do not jitter. The hero number scales with `.title` but steps down rather than truncating
/// (`WatchHeroNumber`).
extension Font {
    /// Surface titles ("Latest serve", "Mark for review").
    static let watchTitle = Font.headline
    /// Body copy and row labels.
    static let watchBody = Font.body
    /// Row values ("12:34") and secondary numbers.
    static let watchValue = Font.body.weight(.semibold).monospacedDigit()
    /// Basis lines, ages and footnotes.
    static let watchCaption = Font.footnote
    /// The "Sample" tag.
    static let watchTag = Font.caption2.weight(.medium)
}

/// The large number at the top of a surface ("5/6", "30–15", "74 mph"). It scales with Dynamic Type relative to
/// `.title` and, at the largest sizes, shrinks by steps (never below 60 %) instead of truncating.
struct WatchHeroNumber: View {
    /// Digits and score symbols only ("5/6", "30–15", "74"); words go in the surrounding labels.
    let value: String
    var color: Color = WatchPalette.chartreuse
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 44

    var body: some View {
        Text(verbatim: value)
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
