import AVFoundation
import CoreGraphics
import Foundation
import JovraBenchmark
import Observation

/// One labelling session: a recording, its label document, the frame on screen and the undo history.
/// The window renders this object and every key, click and menu item calls into it.
@MainActor
@Observable
public final class LabelSession {
    public nonisolated static let tool = "jovra-label@1.0.0"

    public struct Configuration: Sendable {
        /// Where label files live. The launch script points this at `spec/benchmarks/labels`.
        public var labelsDirectory: URL
        /// Write the label file after every edit, so a crash never costs more than one label.
        public var autosave = true
        public var muted = false
        /// Look for hit candidates in the audio when a recording has none yet.
        public var findCandidates = true

        public init(labelsDirectory: URL = Configuration.defaultLabelsDirectory) {
            self.labelsDirectory = labelsDirectory
        }

        public static var defaultLabelsDirectory: URL {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
            return support.appendingPathComponent("JovraLabel/labels", isDirectory: true)
        }
    }

    public enum Phase: Equatable, Sendable {
        case empty
        case opening(String)
        case ready
        case failed(String)
    }

    public enum CandidateSearch: Equatable, Sendable {
        case idle
        case searching
        case found(Int)
        case noAudio
        case failed(String)
    }

    public enum Placement: Equatable, Sendable {
        case bounce
        case corner
    }

    public struct Notice: Equatable, Sendable {
        public enum Kind: Sendable { case info, warning, error }
        public let kind: Kind
        public let text: String
    }

    // MARK: State the window renders

    public private(set) var phase: Phase = .empty
    public private(set) var document: LabelDocument?
    public private(set) var selection: LabelSelection?
    public private(set) var placement: Placement?
    public private(set) var notice: Notice?
    public private(set) var isDirty = false
    public private(set) var lastSaved: Date?
    public private(set) var labelsURL: URL?
    public private(set) var candidateSearch: CandidateSearch = .idle
    /// The presentation time of the frame on screen.
    public private(set) var displayedTime = RationalTime(value: 0, timescale: 1)
    public private(set) var frame: CGImage?
    public private(set) var isPlaying = false
    public private(set) var rate: Float = 1
    /// The pointer's position over the picture, or nil when it is elsewhere. Set by the video canvas.
    public var pointer: ImagePoint?
    /// Called for `LabelCommand.open`: the app shows its open panel.
    @ObservationIgnored public var onOpenRequested: (() -> Void)?

    @ObservationIgnored public let configuration: Configuration
    @ObservationIgnored private let player: FramePlayer
    @ObservationIgnored private var undoStack: [LabelDocument] = []
    @ObservationIgnored private var redoStack: [LabelDocument] = []
    @ObservationIgnored private var candidateTask: Task<Void, Never>?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var videoURL: URL?

    static let rates: [Float] = [0.25, 0.5, 1, 2]

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.player = FramePlayer(muted: configuration.muted)
        player.onFrame = { [weak self] frame in self?.show(frame) }
        player.onPlayingChanged = { [weak self] playing in self?.isPlaying = playing }
    }

    public var labels: BenchmarkLabels? { document?.labels }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var isReady: Bool { phase == .ready }

    // MARK: Opening

    /// Opens a recording: fingerprints it, loads its label file if one exists (or starts an empty one with
    /// the hash-fixed split), shows the first frame, and starts looking for hit candidates in the background.
    public func open(video url: URL) async {
        candidateTask?.cancel()
        player.stop()
        document = nil
        selection = nil
        placement = nil
        frame = nil
        undoStack = []
        redoStack = []
        isDirty = false
        lastSaved = nil
        candidateSearch = .idle
        phase = .opening("Reading the recording and computing its SHA-256…")
        do {
            let fingerprint = try await RecordingFingerprint.read(url)
            let target = configuration.labelsDirectory.appendingPathComponent(BenchmarkLabels.fileName(recordingSha256: fingerprint.recording.sha256))
            let loaded: BenchmarkLabels
            let existed = FileManager.default.fileExists(atPath: target.path)
            if existed {
                loaded = try Self.load(target, for: fingerprint.recording)
            } else {
                loaded = try BenchmarkLabels(recording: fingerprint.recording, labelledBy: .init(method: .human, tool: Self.tool))
            }
            phase = .opening("Preparing the first frame…")
            let length = fingerprint.recording.duration
            await player.load(url, duration: CMTime(value: length.value, timescale: CMTimeScale(clamping: length.timescale)),
                              rotationDegrees: fingerprint.rotationDegrees)
            videoURL = url
            labelsURL = target
            document = LabelDocument(labels: loaded)
            displayedTime = RationalTime(value: 0, timescale: 1)
            phase = .ready
            let counts = loaded.counts
            notice = Notice(kind: .info, text: existed
                ? "Opened with \(counts.hits) hits, \(counts.bounces) bounces and \(counts.rallies) rallies already labelled."
                : "New label file. Step with the arrow keys and mark with one key each; the keys are listed on the right.")
            if loaded.hitCandidates == nil, configuration.findCandidates {
                findCandidates(in: url, hasAudio: fingerprint.hasAudio)
            } else if let candidates = loaded.hitCandidates {
                candidateSearch = .found(candidates.items.count)
            }
        } catch {
            phase = .failed((error as? RecordingError)?.description ?? (error as? LoadError)?.description ?? error.localizedDescription)
        }
    }

    enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case otherRecording
        case inconsistent([String])

        var description: String {
            switch self {
            case .unreadable(let reason): "The label file for this recording could not be read (\(reason)). It was left untouched."
            case .otherRecording: "The label file with this recording's name was made on a different recording. It was left untouched."
            case .inconsistent(let problems): "The label file for this recording is not consistent: \(problems.joined(separator: "; ")). It was left untouched."
            }
        }
    }

    private static func load(_ url: URL, for recording: BenchmarkLabels.Recording) throws -> BenchmarkLabels {
        let labels: BenchmarkLabels
        do {
            labels = try JSONDecoder().decode(BenchmarkLabels.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.unreadable(error.localizedDescription)
        }
        guard labels.recording.sha256 == recording.sha256 else { throw LoadError.otherRecording }
        let problems = labels.problems()
        guard problems.isEmpty else { throw LoadError.inconsistent(problems) }
        return labels
    }

    private func findCandidates(in url: URL, hasAudio: Bool) {
        guard hasAudio else {
            candidateSearch = .noAudio
            return
        }
        candidateSearch = .searching
        candidateTask = Task { [weak self] in
            do {
                let outcome = try await OnsetCandidateFinder.find(in: url)
                guard !Task.isCancelled, let self, self.videoURL == url, let document = self.document else { return }
                switch outcome {
                case .noAudio:
                    self.candidateSearch = .noAudio
                case .found(let times):
                    let end = document.labels.recording.duration
                    // Not an edit the labeller made, so it does not enter the undo history.
                    self.document = document.offering(candidates: times.filter { $0 <= end }, method: OnsetCandidateFinder.method)
                    self.candidateSearch = .found(self.document?.labels.hitCandidates?.items.count ?? 0)
                    self.changed()
                }
            } catch is CancellationError {
            } catch {
                self?.candidateSearch = .failed(error.localizedDescription)
            }
        }
    }

    /// Waits for the background candidate search to finish (tests).
    public func candidatesSettled() async {
        await candidateTask?.value
    }

    // MARK: Commands

    public func perform(_ command: LabelCommand) {
        if command == .open {
            onOpenRequested?()
            return
        }
        guard phase == .ready, let document else { return }
        let time = displayedTime
        switch command {
        case .open:
            break
        case .playPause:
            if isPlaying { player.pause() } else { player.play() }
        case .step(let frames):
            player.step(by: frames)
        case .jump(let seconds):
            seek(toSeconds: time.seconds + Double(seconds))
        case .slower, .faster:
            let index = Self.rates.firstIndex(of: rate) ?? 2
            rate = Self.rates[max(min(index + (command == .faster ? 1 : -1), Self.rates.count - 1), 0)]
            player.setRate(rate)
            notice = Notice(kind: .info, text: "Playback speed \(Self.rateText(rate)).")
        case .markHit(let player):
            edit("Hit, \(player.rawValue) player, at \(time.clock). Press 1 to 6 for the stroke type.") { try $0.markingHit(at: time, player: player) }
                .ifDone { self.selection = .hit(time: time, player: player) }
        case .setStroke(let stroke):
            guard case .hit(let hitTime, let player) = selection else {
                notice = Notice(kind: .warning, text: "Select a hit first: mark one with H or J, or move to one with , and .")
                return
            }
            edit(stroke.map { "\($0.rawValue.capitalized) at \(hitTime.clock)." } ?? "Stroke type cleared at \(hitTime.clock).") {
                $0.settingStroke(stroke, at: hitTime, player: player)
            }
        case .markBounce:
            if let pointer {
                placeBounce(at: pointer)
            } else {
                placement = .bounce
                notice = Notice(kind: .info, text: "Click where the ball touches the ground. Esc cancels.")
            }
        case .toggleInPlay:
            guard case .bounce(let bounceTime) = selection, let bounce = document.labels.bounces.first(where: { $0.time == bounceTime }) else {
                notice = Notice(kind: .warning, text: "Select a bounce first: mark one with B, or move to one with , and .")
                return
            }
            edit(bounce.inPlay ? "Bounce at \(bounceTime.clock) marked as a dead ball." : "Bounce at \(bounceTime.clock) marked as in play.") {
                $0.togglingInPlay(at: bounceTime)
            }
        case .markCorner:
            if let pointer {
                placeCorner(at: pointer)
            } else {
                placement = .corner
                notice = Notice(kind: .info, text: "Click the \(Self.cornerName(document.nextCorner)) corner of the doubles court. Esc cancels.")
            }
        case .skipCorner:
            placeCorner(at: nil)
        case .newCameraPosition:
            edit("Camera position from \(time.clock). Mark its four corners with C.") { try $0.startingCameraPosition(at: time) }
                .ifDone { self.selection = .cameraPosition(from: time) }
        case .rallyStart:
            edit("Rally starts at \(time.clock). Press ] where it ends.") { try $0.openingRally(at: time) }
        case .rallyEnd:
            let start = document.openRallyStart
            edit("Rally from \(start?.clock ?? "") to \(time.clock).") { try $0.closingRally(at: time) }
                .ifDone { if let start { self.selection = .rally(start: start) } }
        case .nextCandidate, .previousCandidate:
            jumpToCandidate(forward: command == .nextCandidate)
        case .rejectCandidate:
            edit("Candidate rejected.") { try $0.rejectingCandidate(near: time) }
                .ifDone { self.jumpToCandidate(forward: true, quietly: true) }
        case .nextLabel, .previousLabel:
            jumpToLabel(forward: command == .nextLabel)
        case .deleteSelected:
            guard let selection, document.contains(selection) else {
                notice = Notice(kind: .warning, text: "Nothing is selected. Move to a label with , and . first.")
                return
            }
            edit("Deleted the \(Self.name(of: selection)) at \(selection.time.clock). ⌘Z brings it back.") { $0.deleting(selection) }
                .ifDone { self.selection = nil }
        case .cancelPlacement:
            if placement != nil {
                placement = nil
                notice = Notice(kind: .info, text: "Placing cancelled.")
            }
        case .undo:
            guard let previous = undoStack.popLast() else {
                notice = Notice(kind: .warning, text: "Nothing to undo.")
                return
            }
            redoStack.append(document)
            restore(previous, saying: "Undone.")
        case .redo:
            guard let next = redoStack.popLast() else {
                notice = Notice(kind: .warning, text: "Nothing to redo.")
                return
            }
            undoStack.append(document)
            restore(next, saying: "Redone.")
        case .save:
            save()
        }
    }

    /// A click on the picture: finishes a bounce or corner that is waiting for its point.
    public func pointerClicked(at point: ImagePoint) {
        guard phase == .ready else { return }
        switch placement {
        case .bounce: placeBounce(at: point)
        case .corner: placeCorner(at: point)
        case nil: notice = Notice(kind: .info, text: "Press B for a bounce or C for a court corner, then click the picture.")
        }
    }

    /// Shows the frame at a media time (the timeline calls this).
    public func seek(to time: RationalTime) {
        seek(toSeconds: time.seconds)
    }

    /// Waits until the last requested seek has reached the player (tests).
    public func seekSettled() async {
        await seekTask?.value
    }

    // MARK: Saving

    /// Writes the label file. Returns whether it worked; the reason is in `notice` when it did not.
    @discardableResult
    public func save() -> Bool {
        guard let document, let labelsURL else { return false }
        do {
            try FileManager.default.createDirectory(at: labelsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try document.stored.encoded().write(to: labelsURL, options: .atomic)
            isDirty = false
            lastSaved = Date()
            notice = Notice(kind: .info, text: "Saved \(labelsURL.lastPathComponent).")
            return true
        } catch {
            notice = Notice(kind: .error, text: "Could not save the labels: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Private

    private struct EditOutcome {
        let done: Bool
        func ifDone(_ body: () -> Void) { if done { body() } }
    }

    @discardableResult
    private func edit(_ message: String, _ change: (LabelDocument) throws -> LabelDocument) -> EditOutcome {
        guard let document else { return EditOutcome(done: false) }
        do {
            let updated = try change(document)
            guard updated != document else { return EditOutcome(done: false) }
            undoStack.append(document)
            redoStack = []
            self.document = updated
            notice = Notice(kind: .info, text: message)
            changed(keepingNotice: true)
            return EditOutcome(done: true)
        } catch LabelDocument.Refusal.because(let reason) {
            notice = Notice(kind: .warning, text: reason)
        } catch {
            notice = Notice(kind: .error, text: error.localizedDescription)
        }
        return EditOutcome(done: false)
    }

    private func restore(_ document: LabelDocument, saying message: String) {
        self.document = document
        if let selection, !document.contains(selection) { self.selection = nil }
        placement = nil
        notice = Notice(kind: .info, text: message)
        changed(keepingNotice: true)
    }

    private func changed(keepingNotice: Bool = false) {
        isDirty = true
        guard configuration.autosave else { return }
        let message = notice
        if save(), keepingNotice { notice = message }
    }

    private func placeBounce(at point: ImagePoint) {
        let time = displayedTime
        placement = nil
        edit("Bounce at \(time.clock). X marks it as a dead ball.") { $0.markingBounce(at: time, point: point) }
            .ifDone { self.selection = .bounce(time: time) }
    }

    private func placeCorner(at point: ImagePoint?) {
        guard let document else { return }
        let time = displayedTime, index = document.nextCorner
        placement = nil
        let next = Self.cornerName((index + 1) % 4)
        let message = point == nil
            ? "\(Self.cornerName(index).capitalized) corner marked as not visible. Next: \(next)."
            : (index == 3 ? "Near left corner placed. All four corners are marked; C starts again at far left."
                          : "\(Self.cornerName(index).capitalized) corner placed. Next: \(next).")
        edit(message) { $0.placingCorner(point, at: time) }
            .ifDone { if let position = self.document?.cameraPosition(at: time) { self.selection = .cameraPosition(from: position.from) } }
    }

    private func jumpToCandidate(forward: Bool, quietly: Bool = false) {
        guard let document else { return }
        let pending = (document.labels.hitCandidates?.items ?? []).filter { $0.decision == .pending }
        let now = displayedTime.seconds, margin = 0.02
        let target = forward ? pending.first { $0.time.seconds > now + margin } : pending.last { $0.time.seconds < now - margin }
        guard let target else {
            if !quietly || pending.isEmpty {
                notice = Notice(kind: .info, text: pending.isEmpty ? Self.noCandidatesText(candidateSearch) : "No more pending candidates \(forward ? "after" : "before") this frame.")
            }
            return
        }
        seek(to: target.time)
        if !quietly { notice = Notice(kind: .info, text: "Candidate at \(target.time.clock). H or J confirms it as a hit; R rejects it.") }
    }

    private func jumpToLabel(forward: Bool) {
        guard let document else { return }
        let now = displayedTime
        let target = forward ? document.landmarks.first { $0.time > now } : document.landmarks.last { $0.time < now }
        guard let target else {
            notice = Notice(kind: .info, text: "No label \(forward ? "after" : "before") this frame.")
            return
        }
        selection = target
        seek(to: target.time)
        notice = Notice(kind: .info, text: "\(Self.name(of: target).capitalized) at \(target.time.clock).")
    }

    private func seek(toSeconds seconds: Double) {
        let total = document?.labels.recording.duration.seconds ?? 0
        let clamped = min(max(seconds, 0), total)
        let previous = seekTask
        seekTask = Task { [player] in
            await previous?.value
            await player.seek(to: CMTime(seconds: clamped, preferredTimescale: 90_000))
        }
    }

    private func show(_ frame: FramePlayer.Frame) {
        self.frame = frame.image
        let time = frame.time
        displayedTime = RationalTime(value: max(time.value, 0), timescale: Int64(max(time.timescale, 1)))
        guard let document else { return }
        // Arriving on a labelled frame selects its label, so the stroke and delete keys act on what is shown.
        if let hit = document.labels.hits.first(where: { $0.time == displayedTime }) {
            selection = .hit(time: hit.time, player: hit.player)
        } else if let bounce = document.labels.bounces.first(where: { $0.time == displayedTime }) {
            selection = .bounce(time: bounce.time)
        }
    }

    // MARK: Words

    static func cornerName(_ index: Int) -> String {
        BenchmarkLabels.Corners.names[index].lowercased()
    }

    static func name(of selection: LabelSelection) -> String {
        switch selection {
        case .hit(_, let player): "hit by the \(player.rawValue) player"
        case .bounce: "bounce"
        case .rally: "rally"
        case .cameraPosition: "camera position"
        }
    }

    static func rateText(_ rate: Float) -> String {
        rate == 1 ? "1×" : (rate < 1 ? String(format: "%.2g×", rate) : String(format: "%.0f×", rate))
    }

    static func noCandidatesText(_ search: CandidateSearch) -> String {
        switch search {
        case .searching: "Still listening for hit candidates. You can label while it runs."
        case .noAudio: "This recording has no sound, so there are no hit candidates. Mark hits with H and J."
        case .failed(let reason): "The sound could not be read for hit candidates (\(reason)). Mark hits with H and J."
        case .idle, .found: "No pending candidates are left."
        }
    }
}
