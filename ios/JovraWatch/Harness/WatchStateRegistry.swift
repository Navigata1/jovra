import Foundation

/// The watch surfaces (watch spec "Surface rules"). The first four are the vertical pages in this order; the
/// connection alert is a full-screen sheet over them.
enum WatchSurface: String, CaseIterable, Sendable {
    case health, score, serve, mark, alert

    /// The pages of the vertical TabView, top to bottom.
    static let pages: [WatchSurface] = [.health, .score, .serve, .mark]

    /// The accessibility identifier of the surface's root view; UI tests find a surface by it.
    var identifier: String { "watch.surface.\(rawValue)" }
}

/// `<surface>.<state>`, the value of `-watchState`.
struct WatchStateID: Hashable, Sendable, CustomStringConvertible {
    let surface: WatchSurface
    let state: String

    init(surface: WatchSurface, state: String) {
        self.surface = surface
        self.state = state
    }

    /// Parses `<surface>.<state>`; nil when the surface is not a `WatchSurface` or the state is empty.
    init?(_ rawValue: String) {
        let parts = rawValue.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let surface = WatchSurface(rawValue: String(parts[0])), !parts[1].isEmpty else {
            return nil
        }
        self.init(surface: surface, state: String(parts[1]))
    }

    var rawValue: String { "\(surface.rawValue).\(state)" }
    var description: String { rawValue }
}

/// One thing the harness does to the fake bridge or the watch process, in order. Records are spec/room record file
/// names without `.json` (spec/room/fixtures/records, bundled in place).
enum HarnessStep: Equatable, Sendable {
    /// The phone answers interactively (an echo bounded transit by `transitMs`): rows can be Fresh.
    case deliverNow(record: String, transitMs: Int)
    /// The payload waits in the queued path (application context): transit is unbounded.
    case queue(record: String)
    /// The queued payloads arrive, oldest first.
    case flushQueue
    /// The watch app process restarts: the cached snapshot stays, its monotonic baseline does not.
    case restartWatchProcess
    /// The wearer already acknowledged every alert in the current snapshot (keeps a page state free of the sheet).
    case acknowledgeAlerts
}

/// A registered `-watchState`: what it opens and how it gets there.
struct WatchHarnessState: Sendable {
    let id: WatchStateID
    /// What the state shows, for reviewers and the self-test output.
    let summary: String
    let steps: [HarnessStep]
}

/// Every `-watchState` value the app accepts. Surface tickets (W04 to W06) add their states here; each state is fed
/// from spec/room records through `FakeWatchBridge`, so screenshots and accessibility audits cover what a real
/// snapshot would show, labelled Sample when the record says `sample: true`.
struct WatchStateRegistry: Sendable {
    let states: [WatchHarnessState]

    static let sampleRecord = "watch-bridge.sample"
    static let serveRecord = "watch-bridge.with-serve"

    static let shared = WatchStateRegistry(states: [
        WatchHarnessState(id: .init(surface: .health, state: "fresh"),
                          summary: "Sample snapshot delivered interactively: 5 of 6 fresh, C3 Unknown",
                          steps: [.deliverNow(record: sampleRecord, transitMs: 0)]),
        WatchHarnessState(id: .init(surface: .health, state: "queued"),
                          summary: "The same snapshot by the queued path: every camera Unknown",
                          steps: [.queue(record: sampleRecord), .flushQueue]),
        WatchHarnessState(id: .init(surface: .health, state: "restarted"),
                          summary: "Watch app restarted after a fresh delivery: cached rows Unknown",
                          steps: [.deliverNow(record: sampleRecord, transitMs: 0), .restartWatchProcess]),
        WatchHarnessState(id: .init(surface: .health, state: "waiting"),
                          summary: "No snapshot from the phone yet",
                          steps: []),
        WatchHarnessState(id: .init(surface: .score, state: "sample"),
                          summary: "Sample manual score 30-15, games 5-4",
                          steps: [.deliverNow(record: sampleRecord, transitMs: 0)]),
        WatchHarnessState(id: .init(surface: .serve, state: "notMeasured"),
                          summary: "No post-capture estimate: Not measured live",
                          steps: [.deliverNow(record: sampleRecord, transitMs: 0)]),
        WatchHarnessState(id: .init(surface: .serve, state: "estimate"),
                          summary: "A post-capture serve estimate, labelled Estimated",
                          steps: [.deliverNow(record: serveRecord, transitMs: 0), .acknowledgeAlerts]),
        WatchHarnessState(id: .init(surface: .mark, state: "sample"),
                          summary: "Mark for review with the last accepted mark receipt",
                          steps: [.deliverNow(record: sampleRecord, transitMs: 0)]),
        WatchHarnessState(id: .init(surface: .alert, state: "cameraUnknown"),
                          summary: "Connection alert sheet for a camera gone Unknown",
                          steps: [.deliverNow(record: serveRecord, transitMs: 0)]),
    ])

    func state(_ id: WatchStateID) -> WatchHarnessState? { states.first { $0.id == id } }

    /// Every registered value, sorted, as the unknown-value error lists them.
    var registeredValues: [String] { states.map(\.id.rawValue).sorted() }
}
