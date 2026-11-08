/// The joiner's verdict before it sends anything (invitation.py `joiner_verify` / `check_resolved_endpoint`).
public enum JoinerVerdict: String, Equatable, Sendable, CaseIterable {
    case ok
    /// A camera invitation never carries capture controls (the Studio rule).
    case cameraCannotControl
    /// `expiresAt` − `issuedAt` (both the host's clock) is not in (0, 600] s.
    case inviteLifetime
    /// Not a private or link-local LAN address, or a port below 1024.
    case endpointNotAllowed
    /// The host key pinned in the QR is not the key observed on the TLS channel.
    case hostFingerprintMismatch
}

/// Joiner-side checks. The joiner never compares its own wall clock with the host's timestamps: expiry is the host's
/// decision alone (wall clocks are never compared across devices).
public enum InvitationJoiner {
    /// Roles, lifetime, endpoints, then the pinned host key against the key observed on TLS (in constant time).
    public static func verify(_ payload: InvitationPayload, observedHostKey: String) -> JoinerVerdict {
        do {
            try RecordRules.checkRoles(payload.captureRole, payload.commandRole)
            try RecordRules.checkLifetime(payload.issuedAt, payload.expiresAt)
        } catch let violation as RoomRuleViolation {
            return violation.code == .cameraCannotControl ? .cameraCannotControl : .inviteLifetime
        } catch {
            return .inviteLifetime
        }
        for endpoint in payload.endpoints {
            // A DNS-SD instance (its service type is fixed by the schema) is checked after resolution.
            if case .lan(let address, let port) = endpoint, !EndpointAllowList.allows(address: address, port: port) {
                return .endpointNotAllowed
            }
        }
        return roomConstantTimeEquals(observedHostKey, payload.hostKeySha256) ? .ok : .hostFingerprintMismatch
    }

    /// A DNS-SD instance resolves to an address and port; the same LAN allow-list and port rule apply before
    /// connecting. The TLS pin still authenticates the host; the allow-list limits where a client connects.
    public static func checkResolvedEndpoint(address: String, port: Int) -> JoinerVerdict {
        EndpointAllowList.allows(address: address, port: port) ? .ok : .endpointNotAllowed
    }
}
