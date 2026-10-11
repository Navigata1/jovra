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
    var frameStatus = String(localized: "Reading frames…", table: "Replay")
    @ObservationIgnored private var library: LocalCaptureLibrary?
    @ObservationIgnored private var session: SessionID?
    @ObservationIgnored private var playback: FramePlayback?
    @ObservationIgnored private var frameRate: FrameRate?
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
                error = String(localized: "The original isn't available on this iPhone.", table: "Replay"); return
            }
            await selectSegment(first.id)
        } catch {
            guard generation == token else { return }
            self.error = String(localized: "Couldn't open the session. Try again.", table: "Replay")
        }
    }

    func selectSegment(_ id: String) async {
        guard !isWorking, let library, let session, let segment = segments.first(where: { $0.id == id }) else { return }
        player?.pause(); player = nil; playback = nil; frameRate = nil; frame = nil; frameCount = 0; showStill = false
        selectedSegmentID = id; error = nil; frameStatus = String(localized: "Reading frames…", table: "Replay"); isWorking = true
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
                    frameStatus = String(localized: "Exact frame stepping is unavailable for this source. Video still plays.", table: "Replay"); return
                }
                let decoded = try await decodeCaptureToEnd(url)
                try Task.checkCancellation()
                let adapter = try FramePlayback(url: url, rate: rate, frameCount: decoded.videoFrames)
                let first = try await adapter.frame(at: 0)
                guard generation == token else { return }
                playback = adapter; frameRate = rate; frameCount = decoded.videoFrames; frame = first
                let rateLabel = JovraFormat.count(rate.frames) + (rate.perSeconds == 1 ? "" : "/" + JovraFormat.count(rate.perSeconds))
                frameStatus = String(localized: "\(rateLabel) fps · \(JovraFormat.count(decoded.videoFrames)) decoded frames", table: "Replay")
            } catch {
                guard generation == token else { return }
                frameStatus = String(localized: "Couldn't read exact frames. Video playback remains available.", table: "Replay")
            }
        } catch {
            guard generation == token else { return }
            self.error = String(localized: "The original isn't available on this iPhone.", table: "Replay")
        }
    }

    func step(_ delta: Int) async {
        guard !isWorking, delta == 1 || delta == -1, let playback, let frame, let frameRate else { return }
        player?.pause()
        var origin = frame.index
        if let current = player?.currentTime(), current.isNumeric, current.seconds.isFinite {
            if current.seconds <= 0 { origin = 0 }
            else if current.seconds >= Double(frameCount) / frameRate.framesPerSecond { origin = frameCount - 1 }
            else { origin = min(frameCount - 1, max(0, current.frameIndex(at: frameRate))) }
        }
        let next = min(frameCount - 1, max(0, origin + delta))
        isWorking = true
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
            frameStatus = String(localized: "Couldn't read this frame. Try another frame.", table: "Replay")
        }
    }

    func play() { showStill = false; player?.play() }
    func pause() { player?.pause() }
    func close() {
        generation = UUID(); player?.pause(); player = nil; playback = nil; frameRate = nil
        frame = nil; frameCount = 0; isWorking = false; showStill = false
        selectedSegmentID = nil; error = nil; document = nil
    }
}
