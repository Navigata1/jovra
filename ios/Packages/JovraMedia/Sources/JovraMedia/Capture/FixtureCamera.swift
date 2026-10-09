@preconcurrency import AVFoundation
import Foundation
import JovraCore

/// Clearly labelled synthetic capture. Decoded video and PCM audio are retimed and streamed into the
/// same writer callback as CameraSource; no source movie is copied into a captured session.
public final class FixtureCamera: CaptureSource, @unchecked Sendable {
    public let mode = SessionRecordingMode.simulatorFixture
    public let label = "Simulator fixture camera"
    private let url: URL
    private let duration: CMTime
    private let clock: any CaptureClock
    private let lock = NSLock()
    private var includeAudio = false
    private var running: Task<Void, any Error>?
    private var injectedFailure: (CMTime, CaptureSourceFailure)?
    public init(url: URL, duration: CMTime = CMTime(value: 60, timescale: 1), clock: any CaptureClock) {
        self.url = url; self.duration = duration; self.clock = clock
    }
    public func prepare(preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws -> CaptureSourceFormat {
        let info = try await MediaProbe.probe(url)
        guard let video = info.video, video.codedWidth == preset.width, video.codedHeight == preset.height,
              let fps = video.frameRate, fps.frames == preset.frameRate.num, fps.perSeconds == preset.frameRate.den else {
            throw CaptureError.unsupportedPreset
        }
        let audio = microphone == .granted && info.audio != nil
        lock.withLock { includeAudio = audio }
        return CaptureSourceFormat(width: video.codedWidth, height: video.codedHeight, frameRate: preset.frameRate,
                                   hasAudio: audio, sampleRate: info.audio?.sampleRate ?? 48_000, channels: info.audio?.channels ?? 1)
    }
    public func injectFailure(at mediaTime: CMTime, failure: CaptureSourceFailure) { lock.withLock { injectedFailure = (mediaTime, failure) } }
    private func takeFailure(at time: CMTime) -> CaptureSourceFailure? {
        lock.withLock {
            guard let (at, failure) = injectedFailure, CMTimeCompare(time, at) >= 0 else { return nil }
            injectedFailure = nil; return failure
        }
    }
    public func start(at sessionTime: CMTime, onSample: @escaping @Sendable (CaptureSample) throws -> Void,
                      onFailure: @escaping @Sendable (any Error) -> Void) async throws {
        let audio = lock.withLock { includeAudio }
        let task = Task.detached { [self, url, duration, clock] in
            do {
                let clockStart = clock.now()
                let asset = AVURLAsset(url: url)
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                guard let videoTrack = videoTracks.first else { throw CaptureError.noVideo }
                let loopDuration = try await videoTrack.load(.timeRange).duration
                guard loopDuration.isNumeric, CMTimeCompare(loopDuration, .zero) > 0 else { throw CaptureError.noVideo }
                var loopOffset = CMTime.zero
                while CMTimeCompare(loopOffset, duration) < 0 {
                    try Task.checkCancellation()
                    let reader = try AVAssetReader(asset: asset)
                    let video = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                    reader.add(video)
                    var audioOutput: AVAssetReaderTrackOutput?
                    if audio, let track = audioTracks.first {
                        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
                            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                            AVLinearPCMIsNonInterleaved: false])
                        reader.add(output); audioOutput = output
                    }
                    guard reader.startReading() else { throw CaptureError.sourceFailed(reader.error?.localizedDescription ?? "reader") }
                    var nextVideo = video.copyNextSampleBuffer(), nextAudio = audioOutput?.copyNextSampleBuffer()
                    while nextVideo != nil || nextAudio != nil {
                        try Task.checkCancellation()
                        let isVideo = nextAudio == nil || (nextVideo != nil && CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(nextVideo!), CMSampleBufferGetPresentationTimeStamp(nextAudio!)) <= 0)
                        let buffer = isVideo ? nextVideo! : nextAudio!
                        let localTime = CMTimeAdd(loopOffset, CMSampleBufferGetPresentationTimeStamp(buffer))
                        if let failure = self.takeFailure(at: localTime) { throw failure }
                        if CMTimeCompare(localTime, duration) < 0 {
                            try await clock.wait(until: CMTimeAdd(clockStart, localTime))
                            let retimed = try retimeCaptureSample(buffer, offset: CMTimeAdd(sessionTime, loopOffset))
                            try onSample(CaptureSample(buffer: retimed, mediaType: isVideo ? .video : .audio))
                        }
                        if isVideo { nextVideo = video.copyNextSampleBuffer() } else { nextAudio = audioOutput?.copyNextSampleBuffer() }
                    }
                    guard reader.status == .completed else { throw CaptureError.sourceFailed(reader.error?.localizedDescription ?? "reader ended") }
                    loopOffset = CMTimeAdd(loopOffset, loopDuration)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { onFailure(error); throw error }
        }
        lock.withLock { running = task }
    }
    public func waitUntilFinished() async throws { let task = lock.withLock { running }; try await task?.value }
    public func stop() async {
        let task = lock.withLock { let task = running; running = nil; return task }
        task?.cancel(); _ = try? await task?.value
    }
}
