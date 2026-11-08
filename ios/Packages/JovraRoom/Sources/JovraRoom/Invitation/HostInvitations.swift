/// Why the host refused a join step (invitation.py). Codes are the fixture's.
public enum JoinRejection: String, Codable, Equatable, Sendable, CaseIterable {
    case unknownInvite, wrongSession, revoked, alreadyUsed, joinInProgress, expired, hostFingerprintMismatch
    case roleMismatch, badProof, alreadyMember, noPendingJoin, commitmentMismatch, verificationNotConfirmed
}

/// One host answer in the join exchange: a challenge (the fresh `hostNonce`), the six-digit code awaiting the host's
/// confirmation, the accepted grants, or a rejection that grants nothing.
public struct JoinOutcome: Equatable, Sendable {
    public enum Result: String, Equatable, Sendable { case challenge, awaitingHostApproval, accepted, rejected }

    public let result: Result
    public let code: JoinRejection?
    /// Sorted; empty unless accepted. A rejected join grants nothing: no camera permission and no originals.
    public let grants: [String]
    public let verificationCode: String?
    public let hostNonce: String?
    public let deviceId: String?

    static func rejected(_ code: JoinRejection) -> JoinOutcome {
        JoinOutcome(result: .rejected, code: code, grants: [], verificationCode: nil, hostNonce: nil, deviceId: nil)
    }
}

/// The display-code lookup answer. It finds an invitation for on-screen approval and never authenticates anyone.
public struct InvitationLookup: Equatable, Sendable {
    public enum Result: String, Equatable, Sendable { case found, notFound, lookupThrottled }
    public let result: Result
    public let inviteId: String?
    /// Always false: a display code is lookup data, never a credential.
    public let authenticates = false
}

/// What the host logs. It never holds a token, proof, nonce, Wi-Fi passphrase or QR text: only ids and codes.
public struct InvitationLogEntry: Codable, Equatable, Sendable {
    public enum Event: String, Codable, Sendable { case joinRejected, joinChallenged, awaitingHostApproval, joined, inviteRevoked }
    public let event: Event
    public let inviteId: String?
    public let code: JoinRejection?
    public let reason: RoomInvitation.RevokedReason?
    public let deviceId: String?

    init(_ event: Event, inviteId: String? = nil, code: JoinRejection? = nil,
         reason: RoomInvitation.RevokedReason? = nil, deviceId: String? = nil) {
        (self.event, self.inviteId, self.code, self.reason, self.deviceId) = (event, inviteId, code, reason, deviceId)
    }
}

/// The capabilities an accepted join grants (invitation.py `grants_for`): `view-room-status` for everyone, the three
/// camera grants for a camera, and `command:<Type>` for each type the command role permits.
public enum InvitationGrants {
    public static func grants(captureRole: CaptureRole, commandRole: CommandRole) -> [String] {
        let camera = captureRole == .camera ? ["record-local", "upload-own-source", "view-own-preview"] : []
        let commands = commandRole.permittedCommandTypes.map { "command:\($0.rawValue)" }
        return Set(["view-room-status"] + camera + commands).sorted()
    }
}

/// Host-side invitation state (invitation.py `HostInvitations`): single use, bound to session, epoch and host key, a
/// commit-then-reveal verification code, host approval, a three-attempt limit and a throttled lookup-only display
/// code. `tokens` and `nonces` stand in for the host's secure store (Keychain); the persisted record keeps only the
/// token's hash. `members` maps already-admitted device ids to their key fingerprints, the host's own included.
public struct HostInvitations: Sendable {
    public static let maxJoinAttempts = 3
    public static let lookupMaxMisses = 5
    public static let lookupWindowMs = 600_000

    private struct Pending: Sendable {
        enum Stage: Sendable { case challenged, awaitingApproval }
        let request: JoinRequest
        let hostNonce: String
        var stage: Stage
    }

    public let sessionId: String
    public private(set) var hostEpoch: Int
    public private(set) var hostKey: String
    /// In issue order (lookup scans them in that order).
    public private(set) var records: [RoomInvitation]
    public private(set) var members: [String: String]
    public private(set) var log: [InvitationLogEntry] = []
    private let tokens: [String: String]
    private let nonces: [String: String]
    private var pending: [String: Pending] = [:]
    private var attempts: [String: Int] = [:]
    private var lookupMisses: [String: [Int]] = [:]

    public init(sessionId: String, hostEpoch: Int, hostKey: String, records: [RoomInvitation],
                tokens: [String: String], nonces: [String: String], members: [String: String] = [:]) {
        self.sessionId = sessionId
        self.hostEpoch = hostEpoch
        self.hostKey = hostKey
        self.records = records
        self.tokens = tokens
        self.nonces = nonces
        self.members = members
    }

    public func record(_ inviteId: String) -> RoomInvitation? { records.first { $0.inviteId == inviteId } }

    private func index(_ inviteId: String) -> Int? { records.firstIndex { $0.inviteId == inviteId } }

    private mutating func reject(_ code: JoinRejection) -> JoinOutcome {
        log.append(InvitationLogEntry(.joinRejected, code: code))
        return .rejected(code)
    }

    private func isMember(_ request: JoinRequest) -> Bool {
        members[request.guestDeviceId] != nil || members.values.contains(request.guestKeySha256)
    }

    private mutating func failAttempt(_ inviteId: String) {
        attempts[inviteId, default: 0] += 1
        guard let i = index(inviteId), attempts[inviteId, default: 0] >= Self.maxJoinAttempts,
              records[i].status == .issued else { return }
        records[i].status = .revoked
        records[i].revokedReason = .attemptsExhausted
        log.append(InvitationLogEntry(.inviteRevoked, inviteId: inviteId, reason: .attemptsExhausted))
    }

    /// Checks the join request on the host's own clock (exactly at `expiresAt` is still valid). On success the host
    /// answers with `hostNonce` (the challenge), which must be fresh and random per attempt: production callers use
    /// `validateJoin(_:now:)`, which draws it from the CSPRNG.
    public mutating func validateJoin(_ request: JoinRequest, now: RoomTimestamp, hostNonce: String) -> JoinOutcome {
        guard let i = index(request.inviteId) else { return reject(.unknownInvite) }
        let record = records[i]
        if request.sessionId != sessionId || record.sessionId != sessionId { return reject(.wrongSession) }
        if record.status == .revoked || record.hostEpoch != hostEpoch || request.hostEpoch != hostEpoch {
            return reject(.revoked)
        }
        if record.status == .used { return reject(.alreadyUsed) }
        if pending[record.inviteId] != nil { return reject(.joinInProgress) }
        if record.status == .expired || isAfterExpiry(now, record) {
            records[i].status = .expired
            return reject(.expired)
        }
        if !roomConstantTimeEquals(request.observedHostKeySha256, hostKey) || record.hostKeySha256 != hostKey {
            return reject(.hostFingerprintMismatch)
        }
        if request.requestedCaptureRole != record.captureRole || request.requestedCommandRole != record.commandRole {
            return reject(.roleMismatch)
        }
        guard let token = tokens[record.inviteId], let nonce = nonces[record.inviteId],
              InvitationCrypto.tokenHash(token) == record.joinTokenSha256 else { return reject(.unknownInvite) }
        let expected = InvitationCrypto.joinProof(token: token, sessionId: sessionId, inviteId: record.inviteId,
                                                  nonce: nonce, guestKey: request.guestKeySha256,
                                                  commitment: request.guestCommitment)
        if !roomConstantTimeEquals(expected, request.proof) { return reject(.badProof) }
        if isMember(request) { return reject(.alreadyMember) }
        pending[record.inviteId] = Pending(request: request, hostNonce: hostNonce, stage: .challenged)
        log.append(InvitationLogEntry(.joinChallenged, inviteId: record.inviteId))
        return JoinOutcome(result: .challenge, code: nil, grants: [], verificationCode: nil, hostNonce: hostNonce,
                           deviceId: nil)
    }

    /// `validateJoin` with a fresh CSPRNG host nonce.
    public mutating func validateJoin(_ request: JoinRequest, now: RoomTimestamp) -> JoinOutcome {
        validateJoin(request, now: now, hostNonce: InvitationCrypto.randomNonce())
    }

    /// The guest opens its commitment after seeing `hostNonce`; both screens then show the same six digits. A
    /// mismatch ends the attempt and counts towards the limit.
    public mutating func reveal(inviteId: String, guestNonce: String) -> JoinOutcome {
        guard var p = pending[inviteId], p.stage == .challenged, let qrNonce = nonces[inviteId] else {
            return reject(.noPendingJoin)
        }
        let commitment = InvitationCrypto.guestCommitment(guestKey: p.request.guestKeySha256, guestNonce: guestNonce)
        if !roomConstantTimeEquals(commitment, p.request.guestCommitment) {
            pending[inviteId] = nil
            failAttempt(inviteId)
            return reject(.commitmentMismatch)
        }
        p.stage = .awaitingApproval
        pending[inviteId] = p
        let code = InvitationCrypto.verificationCode(hostKey: hostKey, guestKey: p.request.guestKeySha256,
                                                     qrNonce: qrNonce, hostNonce: p.hostNonce, guestNonce: guestNonce)
        log.append(InvitationLogEntry(.awaitingHostApproval, inviteId: inviteId))
        return JoinOutcome(result: .awaitingHostApproval, code: nil, grants: [], verificationCode: code, hostNonce: nil,
                           deviceId: nil)
    }

    /// The host confirms the codes match (a declined comparison counts towards the attempt limit), then expiry, epoch
    /// and membership are checked again; the invitation is consumed and the grants returned.
    public mutating func approve(inviteId: String, codesMatchConfirmed: Bool, now: RoomTimestamp) -> JoinOutcome {
        guard let p = pending[inviteId], p.stage == .awaitingApproval, let i = index(inviteId) else {
            return reject(.noPendingJoin)
        }
        pending[inviteId] = nil
        if !codesMatchConfirmed {
            failAttempt(inviteId)
            return reject(.verificationNotConfirmed)
        }
        let record = records[i]
        if record.hostEpoch != hostEpoch || record.status != .issued { return reject(.revoked) }
        if isAfterExpiry(now, record) {
            records[i].status = .expired
            return reject(.expired)
        }
        if isMember(p.request) { return reject(.alreadyMember) }
        records[i].status = .used
        records[i].usedByDeviceId = p.request.guestDeviceId
        records[i].usedAt = now.text
        members[p.request.guestDeviceId] = p.request.guestKeySha256
        log.append(InvitationLogEntry(.joined, inviteId: inviteId, deviceId: p.request.guestDeviceId))
        return JoinOutcome(result: .accepted, code: nil,
                           grants: InvitationGrants.grants(captureRole: record.captureRole, commandRole: record.commandRole),
                           verificationCode: nil, hostNonce: nil, deviceId: p.request.guestDeviceId)
    }

    /// Manual entry: finds an open, unexpired invitation by its display code for on-screen approval. Misses are counted
    /// per requesting source in a sliding 10-minute window; after five, that source is throttled while everyone else
    /// can still look codes up.
    public mutating func lookup(displayCode: String, source: String, now: RoomTimestamp) -> InvitationLookup {
        let t = now.millisecondsSinceEpoch
        let recent = (lookupMisses[source] ?? []).filter { t - $0 < Self.lookupWindowMs }
        lookupMisses[source] = recent
        if recent.count >= Self.lookupMaxMisses { return InvitationLookup(result: .lookupThrottled, inviteId: nil) }
        for i in records.indices where records[i].displayCode == displayCode && records[i].status == .issued
            && records[i].hostEpoch == hostEpoch {
            if isAfterExpiry(now, records[i]) {
                records[i].status = .expired
                continue
            }
            return InvitationLookup(result: .found, inviteId: records[i].inviteId)
        }
        lookupMisses[source] = recent + [t]
        return InvitationLookup(result: .notFound, inviteId: nil)
    }

    /// A new host epoch revokes every open invitation and pending join; new invitations must be issued. Returns the
    /// revoked invitation ids, sorted.
    public mutating func transferHost(newEpoch: Int, newHostKey: String) -> [String] {
        var revoked: [String] = []
        for i in records.indices where records[i].status == .issued {
            records[i].status = .revoked
            records[i].revokedReason = .hostTransfer
            revoked.append(records[i].inviteId)
        }
        pending.removeAll()
        hostEpoch = newEpoch
        hostKey = newHostKey
        return revoked.sorted()
    }

    private func isAfterExpiry(_ now: RoomTimestamp, _ record: RoomInvitation) -> Bool {
        guard let expires = RoomTimestamp(record.expiresAt) else { return true } // fail closed
        return now > expires
    }
}
