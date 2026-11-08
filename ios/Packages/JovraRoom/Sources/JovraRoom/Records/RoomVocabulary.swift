// The closed vocabularies of spec/room/schemas/room-common.schema.json. Raw values are the wire values.

/// A camera's own reported state. There is deliberately no Unknown: that is a receiver-derived freshness result.
public enum CaptureState: String, Codable, CaseIterable, Hashable, Sendable {
    case ready = "Ready", starting = "Starting", recording = "Recording", paused = "Paused"
    case finalizing = "Finalizing", saved = "Saved", failed = "Failed"

    /// States after which a silent camera "may still be recording" (freshness.py ACTIVE_CAPTURE).
    public var isActiveCapture: Bool { [.starting, .recording, .paused, .finalizing].contains(self) }
}

/// A device's role in the room's capture: one primary at most, cameras, or a participant that does not record.
public enum CaptureRole: String, Codable, CaseIterable, Hashable, Sendable {
    case primary, camera, none
}

/// Write privilege in the room. Pairing a watch grants nothing: a watch acts with its member's roles.
public enum CommandRole: String, Codable, CaseIterable, Hashable, Sendable {
    case viewer, marker, scorer, captureController = "capture-controller"

    /// The command types this role may issue (ledger.py ROLE_COMMANDS).
    public var permittedCommandTypes: Set<CommandType> {
        switch self {
        case .viewer: []
        case .marker: [.markForReview]
        case .scorer: [.pointWon, .undo, .markForReview]
        case .captureController: [.startRequest, .stopOne, .stopAllRequest, .markForReview]
        }
    }
}

public enum CommandType: String, Codable, CaseIterable, Hashable, Sendable {
    case pointWon = "PointWon", undo = "Undo", markForReview = "MarkForReview"
    case startRequest = "StartRequest", stopOne = "StopOne", stopAllRequest = "StopAllRequest"

    /// Capture requests (ledger.py CAPTURE_TYPES): never issued by a watch, TTL at most 30 s.
    public var isCaptureRequest: Bool { [.startRequest, .stopOne, .stopAllRequest].contains(self) }
    /// Score commands (ledger.py SCORE_TYPES): judged against baseEventRevision.
    public var isScoreCommand: Bool { [.pointWon, .undo].contains(self) }

    /// The longest TTL a capture request may carry (ledger.py CAPTURE_TTL_MAX_MS).
    public static let captureTTLMaxMs = 30_000
}

/// Receiver-derived only: no record lets a sender assert it.
public enum Freshness: String, Codable, CaseIterable, Hashable, Sendable {
    case fresh = "Fresh", delayed = "Delayed", unknown = "Unknown"
}

public enum ReceiptStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending = "Pending", accepted = "Accepted", rejected = "Rejected", expired = "Expired"
    case conflicted = "Conflicted"
}

/// Per-target outcome of a capture request; never collapsed into one success banner.
public enum DeviceResultStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending = "Pending", accepted = "Accepted", denied = "Denied", failed = "Failed"
    case timedOut = "TimedOut", unknown = "Unknown"
}

/// The core provenance values (ADR-0004), displayed as Manual / Estimated / Reviewed / Validated.
public enum ProvenanceLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case manual, estimated, reviewed, validated
}

public enum ThermalState: String, Codable, CaseIterable, Hashable, Sendable {
    case nominal, fair, serious, critical, unknown
}

/// Studio Build-your-match placement (drift-checked against Studio's placementSlot by validate_room.py).
public enum StudioSlot: String, Codable, CaseIterable, Hashable, Sendable {
    case nearBaseline = "near-baseline", farBaseline = "far-baseline"
    case nearLeftCorner = "near-left-corner", nearRightCorner = "near-right-corner"
    case farLeftCorner = "far-left-corner", farRightCorner = "far-right-corner", custom
}
