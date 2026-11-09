#if DEBUG
import Foundation
import JovraMedia
import Observation

@MainActor
@Observable
final class VideoLabPlayback {
    typealias Open = @MainActor (URL, URL?) async throws -> PlaybackController

    @ObservationIgnored private let open: Open
    private(set) var controller: PlaybackController?
    private(set) var error: PlaybackOpenError?

    init(open: @escaping Open = { try await PlaybackController.open(url: $0, proxyDirectory: $1) }) {
        self.open = open
    }

    func load(_ source: URL, proxyDirectory: URL? = nil) async {
        controller?.close()
        controller = nil
        error = nil
        do {
            let opened = try await open(source, proxyDirectory)
            guard !Task.isCancelled else { opened.close(); return }
            controller = opened
        } catch let error as PlaybackOpenError {
            self.error = error
        } catch {
            self.error = .unreadable
        }
    }

    func close() { controller?.close() }
}
#endif
