import CoreMedia

/// How closely a seek must land. Dragging asks for `coarse` (the decoder may stop at a nearby sync frame);
/// releasing, stepping and skipping ask for `exact` (zero tolerance either side).
public enum SeekPrecision: Sendable, Equatable {
    case coarse, exact
}

/// Chase-time seeking (Apple QA1820). At most one seek is in flight. A request made while one runs replaces
/// whatever was queued, so a fast drag never builds a backlog. An interrupted seek is not a landing.
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

    public typealias Perform = @MainActor (CMTime, SeekPrecision) async -> Bool

    private let perform: Perform
    private var inFlight: Request?
    private var queued: Request?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// The last successful landing, invalidated by an unsuccessful attempt or playback movement.
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

    /// Waits for idle and reports whether this exact request is the acknowledged landing.
    @discardableResult
    public func request(_ time: CMTime, precision: SeekPrecision) async -> Bool {
        submit(time, precision: precision)
        await settled()
        return isIdle && lastCompleted == Request(time: time, precision: precision)
    }

    /// The player has moved by itself (playback): a request for the last landed time must run again.
    public func playheadMoved() {
        lastCompleted = nil
    }

    /// Waits for the queue to drain. Idle alone does not establish a successful landing.
    public func settled() async {
        guard inFlight != nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func start(_ request: Request) {
        inFlight = request
        issuedCount += 1
        Task { @MainActor in
            let succeeded = await perform(request.time, request.precision)
            finish(request, succeeded: succeeded)
        }
    }

    private func finish(_ request: Request, succeeded: Bool) {
        lastCompleted = succeeded ? request : nil
        if let next = queued {
            queued = nil
            if next != lastCompleted {
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
