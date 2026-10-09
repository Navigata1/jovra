import AVFoundation
import JovraCore
import JovraMedia
import Observation

/// Reads the existing original. Exact stepping is available only after a constant-rate source
/// has been probed and fully decoded; ordinary video playback does not depend on that index.
@MainActor @Observable
final class ReplayPlaybackModel {
    var document: SessionDocument?
    var player: AVPlayer?
    var frame: PlaybackFrame?
    var frameCount = 0
    var selectedSegmentID: String?
    var isWorking = false
    var showStill = false
    var error: String?
    var frameStatus = "Reading frames…"
    @ObservationIgnored private var library: LocalCaptureLibrary?
    @ObservationIgnored private var session: SessionID?
    @ObservationIgnored private var playback: FramePlayback?
    @ObservationIgnored private var generation = UUID()

    var segments: [SessionSegment] { document?.recording.segments.filter(\.finalized).sorted { $0.index < $1.index } ?? [] }

    func open(library: LocalCaptureLibrary, session: SessionID) async {
        close()
        self.library = library; self.session = session
        let token = generation
        do {
            let loaded = try await library.load(session)
            try Task.checkCancellation()
            guard generation == token else { return }
            document = loaded
            guard let first = segments.first, loaded.recording.mediaAvailable else {
                error = "The original isn't available on this iPhone."; return
            }
            await selectSegment(first.id)
        } catch {
            guard generation == token else { return }
            self.error = "Couldn't open the session. Try again."
        }
    }

    func selectSegment(_ id: String) async {
        guard !isWorking, let library, let session, let segment = segments.first(where: { $0.id == id }) else { return }
        player?.pause(); player = nil; playback = nil; frame = nil; frameCount = 0; showStill = false
        selectedSegmentID = id; error = nil; frameStatus = "Reading frames…"; isWorking = true
        let token = generation
        defer { if generation == token { isWorking = false } }
        do {
            let url = try await library.fileURL(session, relativePath: segment.file.path)
            try Task.checkCancellation()
            guard generation == token else { return }
            player = AVPlayer(url: url)
            do {
                let info = try await MediaProbe.probe(url)
                guard let video = info.video, video.isDecodable, !video.isVariableFrameRate,
                      let rate = video.frameRate else {
                    frameStatus = "Exact frame stepping is unavailable for this source. Video still plays."; return
                }
                let decoded = try await decodeCaptureToEnd(url)
                try Task.checkCancellation()
                let adapter = try FramePlayback(url: url, rate: rate, frameCount: decoded.videoFrames)
                let first = try await adapter.frame(at: 0)
                guard generation == token else { return }
                playback = adapter; frameCount = decoded.videoFrames; frame = first
                frameStatus = "\(rate.framesPerSecond.formatted()) fps · \(decoded.videoFrames) decoded frames"
            } catch {
                guard generation == token else { return }
                frameStatus = "Couldn't read exact frames. Video playback remains available."
            }
        } catch {
            guard generation == token else { return }
            self.error = "The original isn't available on this iPhone."
        }
    }

    func step(_ delta: Int) async {
        guard !isWorking, delta == 1 || delta == -1, let playback, let frame else { return }
        let next = min(frameCount - 1, max(0, frame.index + delta))
        player?.pause(); isWorking = true
        let token = generation
        defer { if generation == token { isWorking = false } }
        do {
            let decoded = try await playback.frame(at: next)
            try Task.checkCancellation()
            guard generation == token else { return }
            self.frame = decoded; showStill = true
            await player?.seek(to: decoded.time, toleranceBefore: .zero, toleranceAfter: .zero)
        } catch {
            guard generation == token else { return }
            frameStatus = "Couldn't read this frame. Try another frame."
        }
    }

    func play() { showStill = false; player?.play() }
    func pause() { player?.pause() }
    func close() {
        generation = UUID(); player?.pause(); player = nil; playback = nil
        frame = nil; frameCount = 0; isWorking = false; showStill = false
        selectedSegmentID = nil; error = nil; document = nil
    }
}
