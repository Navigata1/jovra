@preconcurrency import AVFoundation
import Foundation
import JovraCore
import Observation

/// The one player behind every video screen (screens 10, 12, 13, 14). It wraps `AVPlayer` over a
/// constant-rate original and keeps the playhead as a whole frame index on the clip's rational clock:
///
/// - chase-time seeking with one seek in flight: coarse while dragging, exact on release;
/// - `step(byCount:)` exact frame steps, clamped to the clip;
/// - rates 0.25×–2×, a 10 s skip, and an A–B loop enforced by the item's forward end time;
/// - a short-GOP proxy, built when backward steps are slow and used for every backward step once ready:
///   the proxy's exact frame is shown at once (`still`) while the original chases to the same frame.
///
/// Video stays playable when exact stepping is unavailable; that is the caller's fallback (`open` throws
/// `.variableFrameRate`, and a plain `AVPlayer` can still play the file).
@MainActor
@Observable
public final class PlaybackController {
    public let url: URL
    public let frameRate: FrameRate
    public let frameCount: Int
    /// Exposed for video rendering. Direct mutations bypass the controller's lifecycle.
    @ObservationIgnored public let player: AVPlayer

    /// The frame the playhead is on (while dragging: the frame under the finger).
    public private(set) var currentFrame = 0
    /// The player's intent: true from `play()` until `pause()` or the natural end.
    public private(set) var isPlaying = false
    public private(set) var rate: PlaybackRate = .normal
    public private(set) var loop: FrameLoop?
    /// Every repeat of the current loop, for the readout's honesty and for tests.
    public private(set) var loopWraps: [LoopWrap] = []
    /// The proxy's exact frame, shown over the video until the original lands on the same frame.
    public private(set) var still: PlaybackFrame?
    public private(set) var proxyState: ProxyState = .none
    /// False when the item cannot play slower than 1× (the slow rates are then disabled, never faked).
    public private(set) var canPlaySlowForward = true

    public var readout: PlaybackReadout { PlaybackReadout(frame: currentFrame, frameRate: frameRate, rate: rate) }
    public var seeksIssued: Int { seeker.issuedCount }
    public var duration: CMTime { CMTime(frame: frameCount, at: frameRate) }

    /// A backward step slower than this (without the proxy) starts building the proxy.
    @ObservationIgnored public let slowBackwardStep: Duration
    @ObservationIgnored private let proxyDirectory: URL?
    @ObservationIgnored private let videoStart: CMTime
    @ObservationIgnored private var stepper: ProxyBackwardStepper?
    @ObservationIgnored private var proxyTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var stillRequest = 0
    @ObservationIgnored private var pendingLoopResume: Int?
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored var seekPlayer: @MainActor (AVPlayer, CMTime, CMTime) async -> Bool = { player, time, tolerance in
        await player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }
    @ObservationIgnored var decodeProxyFrame: @MainActor (ProxyBackwardStepper, Int) async throws -> PlaybackFrame = {
        try await $0.frame(at: $1)
    }
    @ObservationIgnored var beforeProxyHandoff: (@MainActor (Data, URL) async -> Void)?
    @ObservationIgnored private lazy var seeker = ChaseSeeker { [weak self] time, precision in
        await self?.performSeek(to: time, precision: precision) ?? false
    }

    /// Tolerance either side of a dragging seek.
    public static let coarseTolerance = CMTime(value: 1, timescale: 4)
    public static let defaultSlowBackwardStep: Duration = .milliseconds(100)

    // MARK: Opening

    /// Opens a local original. Missing files, files without video and variable-rate files are typed errors.
    public static func open(url: URL, proxyDirectory: URL? = nil,
                            slowBackwardStep: Duration = defaultSlowBackwardStep) async throws -> PlaybackController {
        try await open(url: url, proxyDirectory: proxyDirectory, slowBackwardStep: slowBackwardStep) {
            try await $0.waitUntilReady()
        }
    }

    static func open(url: URL, proxyDirectory: URL? = nil,
                     slowBackwardStep: Duration = defaultSlowBackwardStep,
                     awaitReadiness: @MainActor (PlaybackController) async throws -> Void) async throws -> PlaybackController {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { throw PlaybackOpenError.missingFile }
        let info: MediaInfo
        do { info = try await MediaProbe.probe(url) } catch { throw PlaybackOpenError.unreadable }
        guard let video = info.video, video.isDecodable else { throw PlaybackOpenError.noVideo }
        guard !video.isVariableFrameRate, let rate = video.frameRate else { throw PlaybackOpenError.variableFrameRate }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let range = try? await track.load(.timeRange) else { throw PlaybackOpenError.noVideo }
        // A leading empty edit belongs to the item timeline, not the clip's video-frame clock.
        let edits = try? await track.load(.segments)
        let firstVideoTime = edits?.first(where: { !$0.isEmpty })?.timeMapping.target.start ?? range.start
        let frames = Self.frameCount(of: CMTimeSubtract(range.end, firstVideoTime), at: rate)
        guard frames > 0 else { throw PlaybackOpenError.noVideo }
        let controller = PlaybackController(url: url, asset: asset, frameRate: rate, frameCount: frames, videoStart: firstVideoTime,
                                            proxyDirectory: proxyDirectory, slowBackwardStep: slowBackwardStep)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await awaitReadiness(controller)
                try Task.checkCancellation()
                if firstVideoTime > .zero, !(await controller.landOriginal(at: 0, precision: .exact)) {
                    try Task.checkCancellation()
                    throw PlaybackOpenError.unreadable
                }
                try Task.checkCancellation()
                controller.observePlayback()
                return controller
            } catch {
                controller.close()
                throw error
            }
        } onCancel: {
            Task { @MainActor in controller.close() }
        }
    }

    /// Whole frames in a constant-rate track's duration (rounded: containers round durations to their timescale).
    static func frameCount(of duration: CMTime, at rate: FrameRate) -> Int {
        guard duration.isNumeric, duration.value > 0 else { return 0 }
        return Int((duration.seconds * rate.framesPerSecond).rounded())
    }

    private init(url: URL, asset: AVURLAsset, frameRate: FrameRate, frameCount: Int, videoStart: CMTime,
                 proxyDirectory: URL?, slowBackwardStep: Duration) {
        self.url = url
        self.frameRate = frameRate
        self.frameCount = frameCount
        self.videoStart = videoStart.isNumeric ? videoStart : .zero
        self.proxyDirectory = proxyDirectory
        self.slowBackwardStep = slowBackwardStep
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
    }

    private func observePlayback() {
        guard let item = player.currentItem else { return }
        let interval = CMTime(frame: 1, at: frameRate)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playerTimeChanged(time) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachedEnd() }
        }
    }

    private func waitUntilReady() async throws {
        guard let item = player.currentItem else { throw PlaybackOpenError.unreadable }
        let deadline = ContinuousClock.now + .seconds(10)
        while item.status == .unknown, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard item.status == .readyToPlay else { throw PlaybackOpenError.unreadable }
        canPlaySlowForward = item.canPlaySlowForward
    }

    /// Permanently closes this controller. An already published proxy stays for next time.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        seeker.close()
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        isPlaying = false
        invalidateStill()
        proxyTask?.cancel()
        if proxyState == .building { proxyState = .none }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
    }

    // MARK: Transport

    public func play() {
        guard !isClosed else { return }
        invalidateStill()
        let restartFrame: Int?
        if let loop, !loop.contains(currentFrame)
            || (seeker.isIdle && !loop.contains(frame(at: player.currentTime()))) {
            restartFrame = loop.start
        } else if loop == nil, currentFrame >= frameCount - 1 {
            restartFrame = 0
        } else {
            restartFrame = nil
        }
        if let restartFrame {
            currentFrame = restartFrame
            seeker.submit(time(of: restartFrame), precision: .exact)
        }
        isPlaying = true
        player.defaultRate = rate.value
        Task { @MainActor in
            await seeker.settled()
            guard !isClosed, isPlaying else { return }
            if let loop {
                guard loop.contains(frame(at: player.currentTime())) else { pause(); return }
            } else if restartFrame != nil, seeker.lastCompleted == nil {
                pause()
                return
            }
            seeker.playheadMoved()
            player.rate = rate.value
        }
    }

    public func pause() {
        guard !isClosed else { return }
        pendingLoopResume = nil
        isPlaying = false
        player.pause()
        if seeker.isIdle { currentFrame = clamp(frame(at: player.currentTime())) }
    }

    public func togglePlayPause() { isPlaying ? pause() : play() }

    /// Changes the rate; a slow rate on an item that cannot play slow forward is refused.
    @discardableResult
    public func setRate(_ newRate: PlaybackRate) -> Bool {
        guard !isClosed, !newRate.isSlow || canPlaySlowForward else { return false }
        rate = newRate
        player.defaultRate = newRate.value
        if player.rate != 0 { player.rate = newRate.value }
        return true
    }

    // MARK: Seeking

    /// Requests `frame` and waits for the seek queue to drain. A failed latest seek restores the playhead readout.
    public func seek(toFrame frame: Int, precision: SeekPrecision = .exact) async {
        guard !isClosed else { return }
        invalidateStill()
        let target = clamp(frame)
        currentFrame = target
        await landOriginal(at: target, precision: precision)
    }

    /// A drag position: the readout follows at once, the player chases with a coarse seek.
    public func scrub(toFrame frame: Int) {
        guard !isClosed else { return }
        if isPlaying { pause() }
        invalidateStill()
        currentFrame = clamp(frame)
        seeker.submit(time(of: currentFrame), precision: .coarse)
    }

    /// The finger lifted: land exactly.
    public func endScrub(atFrame frame: Int) async {
        await seek(toFrame: frame, precision: .exact)
    }

    /// Steps whole frames (negative is backward), pausing playback first. Clamped to the clip.
    public func step(byCount count: Int) async {
        guard !isClosed else { return }
        if isPlaying { pause() }
        let target = clamp(currentFrame + count)
        guard count != 0, target != currentFrame else { return }
        invalidateStill()
        currentFrame = target
        if count < 0, proxyState == .ready, let stepper {
            let request = stillRequest
            seeker.submit(time(of: target), precision: .exact)
            do {
                let frame = try await decodeProxyFrame(stepper, target)
                if request == stillRequest, currentFrame == target {
                    still = frame
                    clearStillWhenLanded(request: request, target: target)
                }
                return
            } catch {
                guard request == stillRequest else { return }
                if !(error is CancellationError) {
                    // A proxy that cannot decode the frame is never used again.
                    proxyState = .failed
                    self.stepper = nil
                }
                await seeker.settled()
                guard request == stillRequest else { return }
                if seeker.lastCompleted != .init(time: time(of: target), precision: .exact) {
                    currentFrame = clamp(frame(at: player.currentTime()))
                }
                return
            }
        }
        let started = ContinuousClock.now
        let landed = await landOriginal(at: target, precision: .exact)
        if landed, count < 0, ContinuousClock.now - started > slowBackwardStep { startProxyIfNeeded() }
    }

    /// Skips by whole seconds (negative is back), clamped to the clip.
    public func skip(seconds: Int) async {
        guard !isClosed else { return }
        if isPlaying { pause() }
        let frames = seconds * frameRate.frames / frameRate.perSeconds
        await seek(toFrame: currentFrame + frames, precision: .exact)
    }

    /// Waits for the seek queue to drain or close.
    public func settle() async { await seeker.settled() }

    // MARK: Loop

    /// Sets or clears the A–B loop. A playhead outside the new loop moves to A.
    public func setLoop(_ newLoop: FrameLoop?) {
        guard !isClosed else { return }
        if pendingLoopResume != nil { currentFrame = clamp(frame(at: player.currentTime())) }
        pendingLoopResume = nil
        loop = newLoop
        loopWraps = []
        player.currentItem?.forwardPlaybackEndTime = newLoop.map { itemTime(time(of: $0.end + 1)) } ?? .invalid
        if let newLoop, !newLoop.contains(currentFrame) || !newLoop.contains(frame(at: player.currentTime())) {
            let resume = isPlaying
            if resume { pause() }
            invalidateStill()
            currentFrame = newLoop.start
            let generation = stillRequest
            if resume { pendingLoopResume = generation }
            seeker.submit(time(of: newLoop.start), precision: .exact)
            Task { @MainActor in
                await seeker.settled()
                guard !isClosed else { return }
                let shouldResume = pendingLoopResume == generation
                if shouldResume { pendingLoopResume = nil }
                guard stillRequest == generation else { return }
                let actual = clamp(frame(at: player.currentTime()))
                currentFrame = actual
                if shouldResume, self.loop == newLoop, newLoop.contains(actual) { play() }
            }
        }
    }

    // MARK: Proxy

    /// Builds the short-GOP proxy now (no-op without a proxy folder, or when it exists or is building).
    public func buildProxy() async {
        startProxyIfNeeded()
        await proxyTask?.value
    }

    /// Returns when proxy work that has started has finished.
    public func waitForProxy() async { await proxyTask?.value }

    private func startProxyIfNeeded() {
        guard !isClosed, let proxyDirectory, proxyState == .none, proxyTask == nil else { return }
        proxyState = .building
        let url = url, rate = frameRate, expected = frameCount
        proxyTask = Task { @MainActor [weak self] in
            let encoder = Task.detached(priority: .utility) {
                try await ShortGOPProxy.encode(from: url, into: proxyDirectory, frameRate: rate)
            }
            let result = await withTaskCancellationHandler {
                await encoder.result
            } onCancel: {
                encoder.cancel()
            }
            let staged = try? result.get()
            guard let self else { return }
            defer { self.proxyTask = nil }
            guard !self.isClosed else { return }
            guard let staged else {
                self.proxyState = .failed
                return
            }
            do {
                if let beforeProxyHandoff = self.beforeProxyHandoff {
                    await beforeProxyHandoff(try staged.movie.evidenceBytes(), staged.retiredWriter)
                }
                // Accept and publish on the same actor as close(), with no suspension between them.
                guard !self.isClosed else { return }
                let proxy = try staged.publish(expectedFrameCount: expected)
                self.stepper = try ProxyBackwardStepper(proxy: proxy, frameRate: rate)
                self.proxyState = .ready
            } catch {
                self.proxyState = .failed
            }
        }
    }

    // MARK: Player callbacks

    private func performSeek(to time: CMTime, precision: SeekPrecision) async -> Bool {
        guard !isClosed else { return false }
        let tolerance = precision == .exact ? CMTime.zero : Self.coarseTolerance
        return await seekPlayer(player, itemTime(time), tolerance)
    }

    @discardableResult
    private func landOriginal(at target: Int, precision: SeekPrecision) async -> Bool {
        let generation = stillRequest
        let landed = await seeker.request(time(of: target), precision: precision)
        guard !isClosed, stillRequest == generation else { return false }
        if !landed { currentFrame = clamp(frame(at: player.currentTime())) }
        return landed
    }

    private func invalidateStill() {
        pendingLoopResume = nil
        stillRequest &+= 1
        still = nil
    }

    private func clearStillWhenLanded(request: Int, target: Int) {
        // Completion is recorded by the seeker after the player callback returns.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await seeker.settled()
            if stillRequest == request, still?.index == target,
               seeker.lastCompleted == .init(time: time(of: target), precision: .exact) { still = nil }
        }
    }

    private func playerTimeChanged(_ time: CMTime) {
        guard !isClosed, isPlaying, seeker.isIdle, player.rate != 0 else { return }
        currentFrame = clamp(frame(at: time))
    }

    private func reachedEnd() {
        guard !isClosed else { return }
        let ended = clamp(frame(at: player.currentTime()))
        guard let loop, isPlaying else {
            isPlaying = false
            currentFrame = ended
            return
        }
        currentFrame = loop.start
        let generation = stillRequest
        Task { @MainActor in
            guard !isClosed, isPlaying, self.loop == loop, stillRequest == generation else { return }
            let landed = await landOriginal(at: loop.start, precision: .exact)
            guard !isClosed, isPlaying, self.loop == loop, stillRequest == generation else { return }
            guard landed else { pause(); return }
            loopWraps.append(LoopWrap(endedAt: ended, restartedAt: frame(at: player.currentTime())))
            seeker.playheadMoved()
            player.rate = rate.value
        }
    }

    // MARK: Clock

    private func time(of frame: Int) -> CMTime { CMTime(frame: frame, at: frameRate) }
    private func itemTime(_ clipTime: CMTime) -> CMTime { CMTimeAdd(videoStart, clipTime) }

    private func frame(at playerTime: CMTime) -> Int {
        CMTimeSubtract(playerTime, videoStart).frameIndex(at: frameRate)
    }

    private func clamp(_ frame: Int) -> Int { min(max(frame, 0), frameCount - 1) }
}
