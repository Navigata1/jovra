import JovraMedia
import SwiftUI
import UIKit

/// The screen stays awake only while a recording is running (user story 77): paused, interrupted, framing,
/// saved or a closed route all hand the idle timer back to iOS. The system call is injected for tests.
@MainActor
final class CaptureKeepAwake {
    private let apply: (Bool) -> Void
    private(set) var isHoldingScreenAwake = false

    init(apply: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.apply = apply
    }

    func update(for phase: CapturePhase?) {
        set(phase == .recording)
    }

    /// The route is closing or the scene left the foreground.
    func release() { set(false) }

    private func set(_ awake: Bool) {
        guard awake != isHoldingScreenAwake else { return }
        isHoldingScreenAwake = awake
        apply(awake)
    }
}

/// VoiceOver announcements that wait for current speech instead of cutting it off ("politely"): a saved
/// segment or an interruption is news, not an alarm.
struct PoliteAnnouncer: AccessibilityAnnouncing {
    static func announcement(_ message: String) -> AttributedString {
        var text = AttributedString(message)
        text.accessibilitySpeechAnnouncementPriority = .low
        return text
    }

    func announce(_ message: String) {
        AccessibilityNotification.Announcement(Self.announcement(message)).post()
    }
}
