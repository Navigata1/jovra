/// A record-level rule refused a record that passed strict decoding (spec/room/reference/jovra_room/records.py).
/// `code` is the stable, language-neutral code the invalid fixtures pin; it never carries a token, proof or nonce.
public struct RoomRuleViolation: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, CaseIterable, Sendable {
        // Invitations and the QR payload.
        case inviteLifetime, cameraCannotControl, usedFields, revokedFields, usedAfterExpiry, slotWithoutCamera
        case endpointNotAllowed, guestKeyEqualsHostKey
        // Device status, snapshots and the watch bridge.
        case senderAssertedAge, duplicateDevice, deviceNotInRoster, primaryCount, sessionMismatch
        case scoreRevisionMismatch, duplicateReceipt, watchCaptureCommand, watchExceedsGrant, duplicateAlert
        case alertSeverity, capabilityAbsent, notServeResult
        // Commands and receipts.
        case ttlTooLong, watchIsItsOwnBridge, markWithoutReference, conflictFields, pendingRevision
        case duplicateDeviceResult, missingDeviceResults, unexpectedDeviceResults, acceptedWithoutRecord
        case recordWithoutAcceptance
        // Analysis results.
        case valueOrReason, unitsWithoutValue, uncertaintyMissing, unknownCapability, capabilityUnsupported
        case labelExceedsCapability, frameRange, uncertaintyExcludesValue
    }

    public let code: Code
    public let detail: String

    public init(_ code: Code, _ detail: String = "") {
        self.code = code
        self.detail = detail
    }

    public var description: String { detail.isEmpty ? code.rawValue : "\(code.rawValue): \(detail)" }
}

/// The capability registry statuses (spec/contracts/capability-registry.v1.json) an analysis result is judged
/// against. Statuses are kept as their wire strings so a newer status (for example `validated`) is still compared
/// exactly, never coerced.
public struct RoomCapabilityRegistry: Equatable, Sendable {
    public let statuses: [String: String]

    public init(statuses: [String: String]) { self.statuses = statuses }

    public func status(of capabilityId: String) -> String? { statuses[capabilityId] }

    /// Unsupported and disabled capabilities never carry a value.
    public func isDelivering(_ capabilityId: String) -> Bool {
        guard let status = statuses[capabilityId] else { return false }
        return status != "unsupported" && status != "disabled"
    }
}

func requireUnique<S: Sequence>(_ values: S, _ code: RoomRuleViolation.Code) throws where S.Element: Hashable {
    var seen = Set<S.Element>()
    for value in values where !seen.insert(value).inserted { throw RoomRuleViolation(code) }
}
