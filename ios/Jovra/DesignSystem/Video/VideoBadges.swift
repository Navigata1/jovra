import SwiftUI

extension SampleBadge {
    /// The badge every sample video carries on its surface (user story 168): it spells out that the footage is
    /// synthetic, on a dark backing that stays legible over any frame.
    static var video: SampleBadge {
        SampleBadge(size: .small, onForest: true,
                    text: String(localized: "Sample video (synthetic)", table: "DesignSystem.Video",
                                 comment: "Badge on demo footage; it must always say Sample"))
    }
}
