import Foundation

/// Anything an outbox can flush to: the host's ledger, or a carrier adapter that relays to it. Every frame names the
/// authenticated channel peer.
public protocol RoomCommandHost {
    var hostEpoch: Int { get }
    mutating func submit(_ command: RoomCommand, delivery: DeliveryObservation?, peer: AuthenticatedPeer?) -> RoomReceipt
}

/// The host's command ledger (spec/room/reference/jovra_room/ledger.py `CommandLedger`). Order of checks:
///
/// 1. Channel authentication: the transport hands the ledger the authenticated peer for **every** frame (`peer` has no
///    default). No peer is `unauthenticatedChannel`; a peer that is no member's device is `notMember`.
/// 2. Issuer binding: `issuer.memberId` must be the peer's member; a phone issuer's `deviceId` must be the peer; a
///    watch issuer's `bridgeDeviceId` must be the peer and its `deviceId` one of that member's registered watches
///    (`issuerNotAuthenticated`). Steps 1-2 are security-logged.
/// 3. Session and epoch (`wrongSession`, `staleEpoch`, `unknownEpoch`). Rejections from steps 1-3 are never cached.
/// 4. Idempotency scoped to the authenticated member: the same `(memberId, commandId)` and fingerprint returns the
///    original receipt; different contents are `commandIdReuse` (security-logged; the stored receipt stands).
/// 5-10. Role granted, role permits the type (a watch never issues a capture request), expiry from chained
///    monotonic ages (capture TTL at most 30 s; unbounded transit expires a capture request), targets, the score's
///    base revision, then apply exactly once.
///
/// The event log is append-only and the tally is always recomputed from it. Persist `state` and restore it after a
/// process death: receipts survive, so a retry after a restart never applies twice.
public struct CommandLedger: RoomCommandHost, Equatable, Sendable {
    public static let securityCodes: Set<RoomReceipt.Reason> = [
        .commandIdReuse, .notMember, .roleNotGranted, .issuerNotAuthenticated, .unauthenticatedChannel,
    ]

    public struct StoredReceipt: Codable, Equatable, Sendable {
        public let fingerprint: String
        public var receipt: RoomReceipt
    }

    /// Everything the host persists. Restoring it reproduces every later decision.
    public struct State: Codable, Equatable, Sendable {
        public var sessionId: String
        public var hostEpoch: Int
        public var revision: Int
        public var members: [String: RoomMember]
        public var devices: [String: CaptureTarget]
        public var events: [LedgerEvent]
        public var marks: [LedgerMark]
        /// Keyed `memberId/commandId`.
        public var receipts: [String: StoredReceipt]
        public var securityLog: [LedgerSecurityEntry]
    }

    public enum LedgerError: Error, Equatable, Sendable {
        case epochNotNewer
        case noSingleReceipt(commandId: String)
    }

    public private(set) var state: State

    public var sessionId: String { state.sessionId }
    public var hostEpoch: Int { state.hostEpoch }
    /// The canonical event revision.
    public var eventRevision: Int { state.revision }
    public var events: [LedgerEvent] { state.events }
    public var marks: [LedgerMark] { state.marks }
    public var securityLog: [LedgerSecurityEntry] { state.securityLog }
    public var captureStates: [String: CaptureState] { state.devices.mapValues(\.captureState) }

    /// `members`: memberId → member; `devices`: the enrolled cameras by device id.
    public init(sessionId: String, hostEpoch: Int, eventRevision: Int, members: [String: RoomMember],
                devices: [String: CaptureTarget]) {
        state = State(sessionId: sessionId, hostEpoch: hostEpoch, revision: eventRevision, members: members,
                      devices: devices, events: [], marks: [], receipts: [:], securityLog: [])
    }

    public init(restoring state: State) { self.state = state }

    // MARK: host decisions

    public mutating func submit(_ command: RoomCommand, delivery: DeliveryObservation?,
                                peer: AuthenticatedPeer?) -> RoomReceipt {
        let commandId = command.commandId
        let memberId: String
        switch authenticate(command, peer) {
        case .failure(let code):
            state.securityLog.append(LedgerSecurityEntry(commandId: commandId, code: code))
            return RoomReceipt(for: command, status: .rejected, reason: code, revision: state.revision)
        case .success(let id):
            memberId = id
        }
        if command.sessionId != state.sessionId {
            return RoomReceipt(for: command, status: .rejected, reason: .wrongSession, revision: state.revision)
        }
        if command.hostEpoch < state.hostEpoch {
            return RoomReceipt(for: command, status: .rejected, reason: .staleEpoch, revision: state.revision)
        }
        if command.hostEpoch > state.hostEpoch {
            return RoomReceipt(for: command, status: .rejected, reason: .unknownEpoch, revision: state.revision)
        }
        let key = "\(memberId)/\(commandId)"
        // Fail closed: a command that cannot be fingerprinted never matches a stored one and is never stored.
        guard let fingerprint = try? CommandFingerprint.of(command) else {
            state.securityLog.append(LedgerSecurityEntry(commandId: commandId, code: .commandIdReuse))
            return RoomReceipt(for: command, status: .rejected, reason: .commandIdReuse, revision: state.revision)
        }
        if let stored = state.receipts[key] {
            if stored.fingerprint == fingerprint { return stored.receipt }
            state.securityLog.append(LedgerSecurityEntry(commandId: commandId, code: .commandIdReuse))
            return RoomReceipt(for: command, status: .rejected, reason: .commandIdReuse, revision: state.revision)
        }
        let receipt = decide(command, member: state.members[memberId]!, delivery: delivery)
        if let reason = receipt.reason, Self.securityCodes.contains(reason) {
            state.securityLog.append(LedgerSecurityEntry(commandId: commandId, code: reason))
        }
        state.receipts[key] = StoredReceipt(fingerprint: fingerprint, receipt: receipt)
        return receipt
    }

    private enum Authentication { case success(String), failure(RoomReceipt.Reason) }

    /// Binds the command's issuer to the authenticated channel peer.
    private func authenticate(_ command: RoomCommand, _ peer: AuthenticatedPeer?) -> Authentication {
        guard let peer else { return .failure(.unauthenticatedChannel) }
        guard let match = state.members.sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.deviceId == peer.deviceId }) else { return .failure(.notMember) }
        let (memberId, member) = (match.key, match.value)
        let issuer = command.issuer
        guard issuer.memberId == memberId else { return .failure(.issuerNotAuthenticated) }
        let bound = switch issuer.surface {
        case .phone: issuer.deviceId == peer.deviceId
        case .watch: issuer.bridgeDeviceId == peer.deviceId && member.watchDeviceIds.contains(issuer.deviceId)
        }
        return bound ? .success(memberId) : .failure(.issuerNotAuthenticated)
    }

    private mutating func decide(_ c: RoomCommand, member: RoomMember, delivery: DeliveryObservation?) -> RoomReceipt {
        let type = c.payload.type
        let revision = state.revision
        func answer(_ status: ReceiptStatus, _ reason: RoomReceipt.Reason?) -> RoomReceipt {
            RoomReceipt(for: c, status: status, reason: reason, revision: revision)
        }
        if !member.roles.contains(c.role) { return answer(.rejected, .roleNotGranted) }
        if !c.role.permittedCommandTypes.contains(type) { return answer(.rejected, .roleNotPermitted) }
        // ADR-0026 as amended: a watch never controls capture; its "stop my phone" is local to its bridge phone.
        if c.issuer.surface == .watch && type.isCaptureRequest { return answer(.rejected, .surfaceNotPermitted) }
        if type.isCaptureRequest && c.expiry.ttlMs > CommandType.captureTTLMaxMs { return answer(.rejected, .ttlTooLong) }
        if let extra = delivery?.extraAgeMs {
            let (age, overflow) = c.expiry.ageAtSendMs.addingReportingOverflow(extra)
            if overflow || age > c.expiry.ttlMs { return answer(.expired, .expired) }
        } else if type.isCaptureRequest {
            return answer(.expired, .unboundedTransit)
        }
        let targets = c.target.scope == .allCameras ? state.devices.keys.sorted() : c.target.deviceIds
        if type.isCaptureRequest && targets.isEmpty { return answer(.rejected, .noTargets) }
        if targets.contains(where: { state.devices[$0] == nil }) { return answer(.rejected, .unknownTarget) }
        switch c.payload {
        case .pointWon, .undo:
            if c.baseEventRevision != revision {
                return RoomReceipt(for: c, status: .conflicted, reason: .baseRevisionStale, revision: revision,
                                   conflict: .init(baseEventRevision: c.baseEventRevision ?? -1,
                                                   currentEventRevision: revision))
            }
            if case .undo(let target) = c.payload, !isUndoable(target) { return answer(.rejected, .undoTargetInvalid) }
            state.revision += 1
            let eventId = "evt-\(state.revision)"
            var winner: String?, undone: String?
            if case .pointWon(let w) = c.payload { winner = w }
            if case .undo(let t) = c.payload { undone = t }
            state.events.append(LedgerEvent(eventId: eventId, revision: state.revision, type: type,
                                            commandId: c.commandId, winnerPlayerId: winner, targetEventId: undone))
            return RoomReceipt(for: c, status: .accepted, revision: state.revision, appliedRecordId: eventId)
        case .markForReview(let reason, let pointEventId, let sourceRefs, _):
            let markId = "mark-\(state.marks.count + 1)"
            state.marks.append(LedgerMark(markId: markId, commandId: c.commandId, reason: reason,
                                          pointEventId: pointEventId, sourceRefs: sourceRefs, atEventRevision: revision))
            return RoomReceipt(for: c, status: .accepted, revision: revision, appliedRecordId: markId)
        case .startRequest, .stopOne, .stopAllRequest:
            // The *request* was accepted; each target answers for itself.
            return RoomReceipt(for: c, status: .accepted, revision: revision,
                               deviceResults: targets.map { .init(deviceId: $0, status: .pending, reason: nil) })
        }
    }

    private func isUndoable(_ eventId: String) -> Bool {
        let undone = Set(state.events.compactMap { $0.type == .undo ? $0.targetEventId : nil })
        return state.events.contains { $0.eventId == eventId && $0.type == .pointWon } && !undone.contains(eventId)
    }

    /// Host recovery on the same device at a higher epoch keeps the event log and cached decisions.
    public mutating func beginEpoch(_ newEpoch: Int) throws(LedgerError) {
        guard newEpoch > state.hostEpoch else { throw .epochNotNewer }
        state.hostEpoch = newEpoch
    }

    // MARK: device side of a capture request

    /// Each target answers locally; the host records what each actually answered. Final per-device results never
    /// change.
    public mutating func deliver(commandId: String) throws(LedgerError) -> RoomReceipt {
        let keys = state.receipts.keys.filter { $0.split(separator: "/", maxSplits: 1).last.map(String.init) == commandId }
        guard keys.count == 1, let key = keys.first, var stored = state.receipts[key] else {
            throw .noSingleReceipt(commandId: commandId)
        }
        let type = stored.receipt.type
        for i in stored.receipt.deviceResults.indices where stored.receipt.deviceResults[i].status == .pending {
            let deviceId = stored.receipt.deviceResults[i].deviceId
            guard var device = state.devices[deviceId] else { continue }
            let (status, reason) = device.answer(type)
            state.devices[deviceId] = device
            stored.receipt.deviceResults[i] = .init(deviceId: deviceId, status: status, reason: reason)
        }
        state.receipts[key] = stored
        return stored.receipt
    }

    /// A camera's own report of its capture state (only the device says Recording).
    public mutating func deviceReported(_ deviceId: String, captureState: CaptureState) {
        state.devices[deviceId]?.captureState = captureState
    }

    /// A lost participant or network never generates a command. Returns the (always empty) commands issued.
    public func roomLinkLost() -> [RoomCommand] { [] }

    // MARK: derived state

    /// Points per player, recomputed from the event log (an undo removes its target's effect).
    public var tally: [String: Int] {
        let undone = Set(state.events.compactMap { $0.type == .undo ? $0.targetEventId : nil })
        var out: [String: Int] = [:]
        for event in state.events where event.type == .pointWon && !undone.contains(event.eventId) {
            if let winner = event.winnerPlayerId { out[winner, default: 0] += 1 }
        }
        return out
    }
}
