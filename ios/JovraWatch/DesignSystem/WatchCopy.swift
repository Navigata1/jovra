import Foundation

/// Watch copy rules (watch spec "Layouts"): no line longer than ~18 characters at the default size. Names that may be
/// longer (a camera slot, a player) are clipped on screen with an ellipsis and spoken in full by VoiceOver.
enum WatchCopy {
    static let lineLimit = 18

    /// `text` clipped to `limit` characters, the last one an ellipsis; unchanged when it fits.
    static func clip(_ text: String, limit: Int = lineLimit) -> String {
        guard limit > 1, text.count > limit else { return text }
        return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
