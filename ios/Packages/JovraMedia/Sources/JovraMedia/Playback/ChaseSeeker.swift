import CoreMedia

/// How closely a seek must land. Dragging asks for `coarse` (the decoder may stop at a nearby sync frame);
/// releasing, stepping and skipping ask for `exact` (zero tolerance either side).
public enum SeekPrecision: Sendable, Equatable {
    case coarse, exact
}

/// Chase-time seeking (Apple QA1820). At most one seek is in flight. A request made while one runs replaces
/// whatever was queued, so a fast drag never builds a backlog, and the last request always lands.
@MainActor
public final class ChaseSeeker {
    public struct Request: Equatable, Sendable {
        public let time: CMTime
        public let precision: SeekPrecision

        public init(time: CMTime, precision: SeekPrecision) {
            self.time = time
            self.precision = precision
        }
    }

    public typealias Perform = @MainActor (CMTime, SeekPrecision) async -> Void

    private let perform: Perform
    private var inFlight: Request?
    private var queued: Request?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// The last request that finished, coarse or exact.
    public private(set) var lastCompleted: Request?
    /// Seeks actually handed to the player (dropped drag positions are not counted).
    public private(set) var issuedCount = 0
    public var isIdle: Bool { inFlight == nil }

    public init(perform: @escaping Perform) {
        self.perform = perform
    }

    /// Asks for a seek without waiting for it.
    public func submit(_ time: CMTime, precision: SeekPrecision) {
        let request = Request(time: time, precision: precision)
        if inFlight != nil {
            queued = request
        } else if request != lastCompleted {
            start(request)
        }
    }

    /// Asks for a seek and returns once the seeker is idle: this request, or a later one, has landed.
    public func request(_ time: CMTime, precision: SeekPrecision) async {
        submit(time, precision: precision)
        await settled()
    }

    /// The player has moved by itself (playback): a request for the last landed time must run again.
    public func playheadMoved() {
        lastCompleted = nil
    }

    /// Returns once no seek is in flight.
    public func settled() async {
        guard inFlight != nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func start(_ request: Request) {
        inFlight = request
        issuedCount += 1
        Task { @MainActor in
            await perform(request.time, request.precision)
            finish(request)
        }
    }

    private func finish(_ request: Request) {
        lastCompleted = request
        if let next = queued {
            queued = nil
            if next != request {
                start(next)
                return
            }
        }
        inFlight = nil
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }
}
