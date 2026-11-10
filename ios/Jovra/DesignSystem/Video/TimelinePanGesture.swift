import SwiftUI
import UIKit

/// Refuses vertical movement before the timeline can claim the pan from its enclosing scroll view.
struct TimelinePanGesture: UIGestureRecognizerRepresentable {
    let width: CGFloat
    let frameCount: Int
    let onScrub: (Int) -> Void
    let onScrubEnded: (Int) -> Void

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var interaction = TimelineScrubInteraction()

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            return TimelineScrubInteraction.hasHorizontalIntent(pan.translation(in: pan.view))
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer(target: nil, action: nil)
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began:
            coordinator.interaction.cancel()
            fallthrough
        case .changed:
            if let target = coordinator.interaction.change(x: context.converter.localLocation.x,
                                                            width: width, frameCount: frameCount) {
                onScrub(target)
            }
        case .ended:
            if let target = coordinator.interaction.end(x: context.converter.localLocation.x,
                                                         width: width, frameCount: frameCount) {
                onScrubEnded(target)
            }
        case .cancelled, .failed:
            if let target = coordinator.interaction.cancel() {
                onScrubEnded(target)
            }
        default:
            break
        }
    }
}
