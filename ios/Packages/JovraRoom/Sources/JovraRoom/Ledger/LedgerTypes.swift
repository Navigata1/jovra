import Foundation
import JovraCore

/// The channel peer the transport authenticated for this frame: the device bound at join to the TLS peer key. The
/// ledger never trusts the issuer named inside a command; it binds that issuer to this peer (D1, F-ROOM-PORTS). A
/// carrier that cannot authenticate the frame passes `nil`, and the command is refused (`unauthenticatedChannel`).
public struct AuthenticatedPeer: Codable, Equatable, Hashable, Sendable {
    public let deviceId: String
    public init(deviceId: String) { self.deviceId = deviceId }
}

/// The host's own measurement of how a command reached it. It fails closed: no observation, `transitBounded` not
/// exactly true, or a missing or negative `transitMs`/`hostHoldMs` is unbounded transit, so a negative value can
/// never extend a TTL (ledger.py `observed_extra_age`).
public struct DeliveryObservation: Codable, Equatable, Sendable {
    public var transitBounded: Bool?
    public var transitMs: Int?
    public var hostHoldMs: Int?

    public init(transitBounded: Bool?, transitMs: Int?, hostHoldMs: Int?) {
        self.transitBounded = transitBounded
        self.transitMs = transitMs
        self.hostHoldMs = hostHoldMs
    }

    /// Transit plus host holding time, or nil when it cannot be bounded.
    public var extraAgeMs: Int? {
        guard transitBounded == true, let transitMs, let hostHoldMs, transitMs >= 0, hostHoldMs >= 0 else { return nil }
        let (sum, overflow) = transitMs.addingReportingOverflow(hostHoldMs)
        return overflow ? nil : sum
    }
}

/// A room member as the host admitted it: a **set** of roles (the host typically holds scorer and
/// capture-controller), the member's authenticated phone and its registered watches. A watch acts with its member's
/// roles and gains nothing by pairing.
public struct RoomMember: Codable, Equatable, Sendable {
    public let roles: [CommandRole]
    public let deviceId: String
    public let watchDeviceIds: [String]

    public struct InvalidRoles: Error, Equatable, Sendable {}

    public init(roles: [CommandRole], deviceId: String, watchDeviceIds: [String] = []) throws(InvalidRoles) {
        guard !roles.isEmpty else { throw InvalidRoles() }
        self.roles = Set(roles).sorted { $0.rawValue < $1.rawValue }
        self.deviceId = deviceId
        self.watchDeviceIds = watchDeviceIds.sorted()
    }
}

/// What a capture target phone is doing, as the host knows it, plus the conditions that decide its answer to a
/// capture request (reachability, acknowledgement, camera permission, foreground, a failing stop).
public struct CaptureTarget: Codable, Equatable, Sendable {
    public var captureState: CaptureState
    public var reachable: Bool
    public var acknowledgementLost: Bool
    public var cameraPermissionGranted: Bool
    public var foreground: Bool
    public var stopFails: Bool

    public init(captureState: CaptureState, reachable: Bool = true, acknowledgementLost: Bool = false,
                cameraPermissionGranted: Bool = true, foreground: Bool = true, stopFails: Bool = false) {
        self.captureState = captureState
        self.reachable = reachable
        self.acknowledgementLost = acknowledgementLost
        self.cameraPermissionGranted = cameraPermissionGranted
        self.foreground = foreground
        self.stopFails = stopFails
    }

    /// How a target phone answers a capture request (the README table). Each phone decides locally; a start is
    /// `Starting` (never `Recording`: only the device's own report says Recording), and a start over a take that is
    /// still finalizing is refused.
    public mutating func answer(_ type: CommandType) -> (RoomReceipt.DeviceResult.Status, RoomReceipt.DeviceResult.Reason) {
        if !reachable { return (.timedOut, .unreachable) }
        if acknowledgementLost { return (.unknown, .noAcknowledgement) }
        if type == .startRequest {
            if !cameraPermissionGranted { return (.denied, .cameraPermissionDenied) }
            if !foreground { return (.denied, .foregroundRequired) }
            if captureState == .finalizing { return (.denied, .finalizing) }
            if [.starting, .recording, .paused].contains(captureState) { return (.accepted, .alreadyRecording) }
            captureState = .starting
            return (.accepted, .startRequested)
        }
        guard [.starting, .recording, .paused].contains(captureState) else { return (.accepted, .notRecording) }
        if stopFails { return (.failed, .finalizeFailed) }
        captureState = .finalizing
        return (.accepted, .stopRequested)
    }
}

extension RoomReceipt.DeviceResult {
    public typealias Status = DeviceResultStatus

    public init(deviceId: String, status: DeviceResultStatus, reason: Reason?) {
        self.deviceId = deviceId
        self.status = status
        self.reason = reason
    }
}

extension RoomReceipt.Conflict {
    public init(baseEventRevision: Int, currentEventRevision: Int) {
        self.baseEventRevision = baseEventRevision
        self.currentEventRevision = currentEventRevision
    }
}

extension RoomReceipt {
    /// The host's (or outbox's) answer to `command` (ledger.py `receipt`); always the standalone record form.
    public init(for command: RoomCommand, status: ReceiptStatus, reason: Reason? = nil, revision: Int?,
                appliedRecordId: String? = nil, conflict: Conflict? = nil, deviceResults: [DeviceResult] = []) {
        self.hasSchemaVersion = true
        self.commandId = command.commandId
        self.sessionId = command.sessionId
        self.hostEpoch = command.hostEpoch
        self.type = command.payload.type
        self.status = status
        self.reason = reason
        self.canonicalEventRevision = revision
        self.appliedRecordId = appliedRecordId
        self.conflict = conflict
        self.deviceResults = deviceResults
    }

    /// A final answer an issuer may not retry unchanged; the outbox keeps everything else queued.
    var isFinal: Bool { status != .pending }

    /// Rejections an issuer may retry unchanged (never cached by the host, never final for the outbox).
    var isTransient: Bool {
        guard let reason else { return false }
        return [.unauthenticatedChannel, .notMember, .issuerNotAuthenticated, .wrongSession, .staleEpoch,
                .unknownEpoch].contains(reason)
    }
}

/// The banner of a capture fan-out comes from per-device results only (ledger.py `summarize`): `allConfirmed` needs
/// every target Accepted; otherwise `partial`, or `waiting` while every target is still Pending. Never a blanket
/// success from a button press.
public struct CaptureFanOutSummary: Codable, Equatable, Sendable {
    public enum Banner: String, Codable, Sendable { case allConfirmed, waiting, partial }
    public let targets: Int
    public let byStatus: [String: Int]
    public let banner: Banner

    public init(_ receipt: RoomReceipt) {
        var tally: [String: Int] = [:]
        for result in receipt.deviceResults { tally[result.status.rawValue, default: 0] += 1 }
        let n = receipt.deviceResults.count
        targets = n
        byStatus = tally
        banner = n > 0 && tally["Accepted"] == n ? .allConfirmed : (n > 0 && tally["Pending"] == n ? .waiting : .partial)
    }
}

/// One appended score event. The log is append-only; totals are always recomputed from it.
public struct LedgerEvent: Codable, Equatable, Sendable {
    public let eventId: String
    public let revision: Int
    public let type: CommandType
    public let commandId: String
    public let winnerPlayerId: String?
    public let targetEventId: String?
}

/// A source-linked review mark. Marks never move the event revision.
public struct LedgerMark: Codable, Equatable, Sendable {
    public let markId: String
    public let commandId: String
    public let reason: RoomCommand.ReviewReason
    public let pointEventId: String?
    public let sourceRefs: [SourceRef]
    public let atEventRevision: Int
}

/// A security-relevant refusal: forged or unauthenticated issuers, non-members, ungranted roles and command-id reuse.
public struct LedgerSecurityEntry: Codable, Equatable, Sendable {
    public let commandId: String
    public let code: RoomReceipt.Reason
}

/// The idempotency fingerprint (ledger.py `command_fingerprint`): SHA-256 of the canonical JSON of the command
/// **without** the volatile `expiry.ageAtSendMs`, which the issuer recomputes on every send. A refreshed retry
/// matches its original; any other change does not.
public enum CommandFingerprint {
    public static func of(_ command: RoomCommand) throws -> String {
        let full = try CanonicalJSON.encode(command)
        guard case .object(var body) = try JSONDecoder().decode(FingerprintJSON.self, from: full),
              case .object(var expiry)? = body["expiry"], expiry.removeValue(forKey: "ageAtSendMs") != nil else {
            throw FingerprintError.unexpectedShape
        }
        body["expiry"] = .object(expiry)
        return RoomSHA256.hexString(RoomSHA256.digest(Array(try CanonicalJSON.encode(FingerprintJSON.object(body)))))
    }

    enum FingerprintError: Error { case unexpectedShape }
}

/// A minimal JSON tree for the fingerprint (integers, strings, booleans, null, arrays and objects; room commands have
/// no fractional numbers).
indirect enum FingerprintJSON: Codable, Equatable {
    case null, bool(Bool), int(Int), string(String), array([FingerprintJSON]), object([String: FingerprintJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([FingerprintJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: FingerprintJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
