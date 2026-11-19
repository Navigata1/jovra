import AVFoundation

/// AVFoundation's completion-handler calls, wrapped by hand.
///
/// This package builds in the Swift 5 language mode and links JovraMedia, which builds in Swift 6 mode. With the
/// Swift 6.0 compiler, both modules emitting the compiler's own `async` bridge for the same Objective-C call
/// (`loadTracks(withMediaType:)`, for one) end up sharing a single copy of it, and the copy made for one mode
/// crashes when the other mode's code resumes through it (seen on the hosted Mac as a bad access inside
/// `CheckedContinuation.resume`). Calling the completion-handler form and resuming a continuation ourselves
/// emits no such bridge here, so there is nothing to share.
enum AssetLoading {
    static func tracks(of asset: AVAsset, mediaType: AVMediaType) async throws -> [AVAssetTrack] {
        try await withCheckedThrowingContinuation { continuation in
            asset.loadTracks(withMediaType: mediaType) { tracks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: tracks ?? [])
                }
            }
        }
    }

    @MainActor
    static func seek(_ player: AVPlayer, to time: CMTime) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in continuation.resume() }
        }
    }
}
