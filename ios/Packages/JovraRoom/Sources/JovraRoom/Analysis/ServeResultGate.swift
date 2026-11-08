/// How a phone or watch may present an analysis result (spec/room/reference/jovra_room/analysis.py `present`).
/// A result is delivered only when the room's capability is on and the registry delivers it; anything else is an
/// explicit `unavailable` with its reason, never an invented value. A result tied to an earlier point is `previous`
/// with its own point and timestamp, never the current serve. A review-needed hint is a bookmark for phone review.
/// No presentation ever changes the score (`scoreEffect` is always "none").
public struct AnalysisPresentation: Equatable, Sendable {
    public enum Show: String, Codable, CaseIterable, Sendable { case unavailable, reviewNeeded, current, previous }

    public let resultId: String
    public let label: ProvenanceLabel
    public let pointEventId: String?
    public let producedAt: String
    public let show: Show
    public let reason: AnalysisResult.UnavailableReason?
    /// A decimal string, present only for `current` and `previous`.
    public let value: String?
    public let units: AnalysisResult.Units?
    public let uncertainty: AnalysisResult.Uncertainty?

    public var scoreEffect: String { "none" }
}

public enum ServeResultGate {
    /// Which room capability a result kind needs. Bounce hints need automated line calls, which v1 never has.
    public static func roomCapabilityOn(_ kind: AnalysisResult.Kind, _ capabilities: RoomCapabilities) -> Bool {
        switch kind {
        case .serveSpeed: capabilities.deliversServeSpeedResults
        case .bounceHint: false // capabilities.automatedLineCalls is const false in v1
        }
    }

    public static func present(_ result: AnalysisResult, capabilities: RoomCapabilities,
                               registry: RoomCapabilityRegistry, currentPointEventId: String?) -> AnalysisPresentation {
        func unavailable(_ reason: AnalysisResult.UnavailableReason?) -> AnalysisPresentation {
            make(result, .unavailable, reason: reason, shown: false)
        }
        guard roomCapabilityOn(result.kind, capabilities) else { return unavailable(.capabilityAbsent) }
        guard registry.isDelivering(result.capabilityId) else { return unavailable(.capabilityUnsupported) }
        guard result.value != nil else { return unavailable(result.unavailableReason) }
        // Both kinds are calibrated: a value without its calibration is not shown.
        guard result.calibrationId != nil else { return unavailable(.calibrationMissing) }
        if result.reviewState == .reviewNeeded { return make(result, .reviewNeeded, reason: nil, shown: false) }
        let isCurrent = result.pointEventId != nil && result.pointEventId == currentPointEventId
        return make(result, isCurrent ? .current : .previous, reason: nil, shown: true)
    }

    private static func make(_ r: AnalysisResult, _ show: AnalysisPresentation.Show,
                             reason: AnalysisResult.UnavailableReason?, shown: Bool) -> AnalysisPresentation {
        AnalysisPresentation(resultId: r.resultId, label: r.label, pointEventId: r.pointEventId,
                             producedAt: r.producedAt, show: show, reason: reason, value: shown ? r.value : nil,
                             units: shown ? r.units : nil, uncertainty: shown ? r.uncertainty : nil)
    }
}
