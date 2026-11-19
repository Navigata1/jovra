import JovraMedia

/// The capture route's three phases (screen spec: framing S05 → recording S06 → saved). The container
/// derives the phase from the engine's confirmed status and the sink's acknowledgment, and nothing else:
/// a stopped engine without a saved result is still the recording phase, where the failure is shown.
enum CaptureRoutePhase: Equatable {
    case framing
    case recording
    case saved

    init(enginePhase: CapturePhase?, isSaved: Bool) {
        if isSaved { self = .saved; return }
        switch enginePhase {
        case nil, .idle?, .ready?: self = .framing
        case .recording?, .pausing?, .paused?, .stopping?, .stopped?: self = .recording
        }
    }
}
