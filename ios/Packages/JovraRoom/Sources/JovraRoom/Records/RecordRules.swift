/// Record-level rules (spec/room/reference/jovra_room/records.py), checked in the reference's order so the first
/// failing rule, and therefore the code, is the same on every platform.
enum RecordRules {
    /// An invitation lives at most 10 minutes, measured on the host's own clock (both timestamps are the host's).
    static let maxInviteLifetimeMs = 600_000

    static func checkLifetime(_ issuedAt: String, _ expiresAt: String) throws {
        guard let issued = RoomTimestamp(issuedAt), let expires = RoomTimestamp(expiresAt) else {
            throw RoomRuleViolation(.inviteLifetime, "unparseable timestamp")
        }
        let life = expires.millisecondsSinceEpoch - issued.millisecondsSinceEpoch
        if life <= 0 || life > maxInviteLifetimeMs { throw RoomRuleViolation(.inviteLifetime, "\(life / 1000) s") }
    }

    /// A camera invitation never carries host or capture controls (the Studio rule).
    static func checkRoles(_ capture: CaptureRole, _ command: CommandRole) throws {
        if capture == .camera && command == .captureController { throw RoomRuleViolation(.cameraCannotControl) }
    }

    static func check(_ r: RoomInvitation) throws {
        try checkLifetime(r.issuedAt, r.expiresAt)
        try checkRoles(r.captureRole, r.commandRole)
        let used = r.status == .used
        if used != (r.usedByDeviceId != nil) || used != (r.usedAt != nil) { throw RoomRuleViolation(.usedFields) }
        if (r.status == .revoked) != (r.revokedReason != nil) { throw RoomRuleViolation(.revokedFields) }
        if used, let usedAt = r.usedAt.flatMap(RoomTimestamp.init), let expires = RoomTimestamp(r.expiresAt),
           usedAt > expires {
            throw RoomRuleViolation(.usedAfterExpiry)
        }
        if r.captureRole == .none && r.studioSlot != nil { throw RoomRuleViolation(.slotWithoutCamera) }
    }

    static func check(_ p: InvitationPayload) throws {
        try checkLifetime(p.issuedAt, p.expiresAt)
        try checkRoles(p.captureRole, p.commandRole)
        for endpoint in p.endpoints {
            // A DNS-SD instance is checked after resolution, with the same allow-list.
            if case .lan(let address, let port) = endpoint, !EndpointAllowList.allows(address: address, port: port) {
                throw RoomRuleViolation(.endpointNotAllowed, "not a private or link-local LAN address")
            }
        }
    }

    static func check(_ r: JoinRequest) throws {
        if r.guestKeySha256 == r.observedHostKeySha256 { throw RoomRuleViolation(.guestKeyEqualsHostKey) }
    }

    static func check(_ r: DeviceStatusRecord) throws {
        if r.status.ageAtHostMs != nil {
            throw RoomRuleViolation(.senderAssertedAge, "only the host measures a device's age")
        }
    }

    private static func checkScore(_ score: ScoreSummary?, eventRevision: Int) throws {
        if let score, score.eventRevision != eventRevision { throw RoomRuleViolation(.scoreRevisionMismatch) }
    }

    private static func checkReceipts(_ receipts: [RoomReceipt]) throws {
        try requireUnique(receipts.map(\.commandId), .duplicateReceipt)
        for receipt in receipts { try check(receipt) }
    }

    private static func checkRoster(_ roster: RoomRoster, _ deviceIds: [String]) throws {
        let enrolled = Set(roster.cameraDeviceIds)
        if deviceIds.contains(where: { !enrolled.contains($0) }) { throw RoomRuleViolation(.deviceNotInRoster) }
    }

    static func check(_ env: RoomSnapshotRecord) throws {
        try requireUnique(env.devices.map(\.deviceId), .duplicateDevice)
        try checkRoster(env.roster, env.devices.map(\.deviceId))
        if env.devices.filter({ $0.captureRole == .primary }).count > 1 { throw RoomRuleViolation(.primaryCount) }
        for device in env.devices {
            if let session = device.sessionId, session != env.sessionId { throw RoomRuleViolation(.sessionMismatch) }
            if let epoch = device.hostEpoch, epoch != env.hostEpoch { throw RoomRuleViolation(.sessionMismatch) }
        }
        try checkScore(env.score, eventRevision: env.eventRevision)
        try checkReceipts(env.receipts)
    }

    static func check(_ env: WatchBridgeSnapshot, registry: RoomCapabilityRegistry) throws {
        try requireUnique(env.devices.map(\.deviceId), .duplicateDevice)
        try checkRoster(env.roster, env.devices.map(\.deviceId))
        try checkScore(env.score, eventRevision: env.eventRevision)
        try checkReceipts(env.receipts)
        let granted = env.participant.commandRoles.reduce(into: Set<CommandType>()) { $0.formUnion($1.permittedCommandTypes) }
        if env.participant.watchCommandTypes.contains(where: \.isCaptureRequest) {
            throw RoomRuleViolation(.watchCaptureCommand, "a watch never issues capture requests in v1")
        }
        if !Set(env.participant.watchCommandTypes).isSubset(of: granted) {
            throw RoomRuleViolation(.watchExceedsGrant, "watch abilities can only narrow the member's grants")
        }
        try requireUnique(env.alerts.map(\.alertId), .duplicateAlert)
        for alert in env.alerts where (alert.severity == .critical) != alert.kind.isOwnCapture {
            throw RoomRuleViolation(.alertSeverity, "critical only for the watch owner's own recording or storage")
        }
        guard let serve = env.latestServe else { return }
        if !env.capabilities.deliversServeSpeedResults {
            throw RoomRuleViolation(.capabilityAbsent, "latestServe needs capabilities.serveSpeedResults")
        }
        if serve.kind != .serveSpeed { throw RoomRuleViolation(.notServeResult) }
        if serve.sessionId != env.sessionId { throw RoomRuleViolation(.sessionMismatch) }
        try check(serve, registry: registry)
    }

    static func check(_ c: RoomCommand) throws {
        let type = c.payload.type
        if type.isCaptureRequest && c.expiry.ttlMs > CommandType.captureTTLMaxMs { throw RoomRuleViolation(.ttlTooLong) }
        if c.issuer.surface == .watch && c.issuer.bridgeDeviceId == c.issuer.deviceId {
            throw RoomRuleViolation(.watchIsItsOwnBridge)
        }
        if case .markForReview(_, let point, let refs, _) = c.payload, refs.isEmpty, point == nil {
            throw RoomRuleViolation(.markWithoutReference, "a review mark needs a point or a source reference")
        }
    }

    static func check(_ r: RoomReceipt) throws {
        let capture = r.type.isCaptureRequest
        if (r.status == .conflicted) != (r.conflict != nil) { throw RoomRuleViolation(.conflictFields) }
        if (r.status == .pending) != (r.canonicalEventRevision == nil) && r.reason != .hostEpochChanged {
            throw RoomRuleViolation(.pendingRevision)
        }
        try requireUnique(r.deviceResults.map(\.deviceId), .duplicateDeviceResult)
        if capture && r.status == .accepted && r.deviceResults.isEmpty { throw RoomRuleViolation(.missingDeviceResults) }
        if !capture && !r.deviceResults.isEmpty { throw RoomRuleViolation(.unexpectedDeviceResults) }
        if r.status == .accepted && !capture && r.appliedRecordId == nil { throw RoomRuleViolation(.acceptedWithoutRecord) }
        if r.status != .accepted && r.appliedRecordId != nil { throw RoomRuleViolation(.recordWithoutAcceptance) }
        if r.type.isScoreCommand && r.status == .accepted && r.canonicalEventRevision == nil {
            throw RoomRuleViolation(.pendingRevision)
        }
    }

    static func check(_ r: AnalysisResult, registry: RoomCapabilityRegistry) throws {
        if (r.value == nil) == (r.unavailableReason == nil) {
            throw RoomRuleViolation(.valueOrReason, "exactly one of value and unavailableReason")
        }
        if (r.value == nil) != (r.units == nil) { throw RoomRuleViolation(.unitsWithoutValue) }
        if r.value != nil && r.label == .estimated && r.uncertainty == nil { throw RoomRuleViolation(.uncertaintyMissing) }
        guard let status = registry.status(of: r.capabilityId) else {
            throw RoomRuleViolation(.unknownCapability, r.capabilityId)
        }
        if (status == "unsupported" || status == "disabled") && r.value != nil {
            throw RoomRuleViolation(.capabilityUnsupported, "\(r.capabilityId) is \(status)")
        }
        if r.label == .validated && status != "validated" { throw RoomRuleViolation(.labelExceedsCapability) }
        for ref in r.sourceRefs {
            if let range = ref.frameRange, range.endFrame < range.startFrame { throw RoomRuleViolation(.frameRange) }
        }
        if let band = r.uncertainty, let text = r.value,
           let value = Double(text), let lower = Double(band.lower), let upper = Double(band.upper),
           !(lower <= value && value <= upper) {
            throw RoomRuleViolation(.uncertaintyExcludesValue)
        }
    }
}
