#if DEBUG
import Foundation
import JovraMedia
import Observation

@MainActor
@Observable
final class VideoLabPlayback {
    typealias Open = @MainActor (URL, URL?) async throws -> PlaybackController

    @ObservationIgnored private let open: Open
    @ObservationIgnored private var generation = UUID()
    private(set) var requestedSource: URL?
    private(set) var controller: PlaybackController?
    private(set) var error: PlaybackOpenError?

    init(open: @escaping Open = { try await PlaybackController.open(url: $0, proxyDirectory: $1) }) {
        self.open = open
    }

    func load(_ source: URL, proxyDirectory: URL? = nil) async {
        guard !Task.isCancelled else { return }
        close()
        requestedSource = source
        let request = generation

        do {
            let opened = try await open(source, proxyDirectory)
            guard request == generation, !Task.isCancelled else {
                opened.close()
                return
            }
            controller = opened
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = (error as? PlaybackOpenError) ?? .unreadable
        }
    }

    func close() {
        generation = UUID()
        controller?.close()
        controller = nil
        error = nil
        requestedSource = nil
    }
}
#endif
