// Invitation records: the host's persisted invitation, the QR payload and the three join frames
// (invitation, invitation-payload, join-request, join-challenge and join-reveal schemas). The host-side single-use
// validation and commit-then-reveal code are W02's (#271); these are the records and their record rules only.

/// `jovra.room.invitation/1`: the host's record of one invitation. It stores the token's hash, never the token.
public struct RoomInvitation: Codable, Equatable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable { case issued, used, expired, revoked }
    public enum RevokedReason: String, Codable, CaseIterable, Sendable {
        case hostTransfer, hostRevoked, slotFilled, attemptsExhausted
    }

    static let schemaVersionValue = "jovra.room.invitation/1"

    public var sample: Bool
    public var inviteId: String
    public var sessionId: String
    public var hostDeviceId: String
    public var hostEpoch: Int
    public var hostKeySha256: String
    public var displayCode: String
    public var joinTokenSha256: String
    public var secretBits: Int
    public var issuedAt: String
    public var expiresAt: String
    /// `camera` or `none`: an invitation never makes a primary.
    public var captureRole: CaptureRole
    public var commandRole: CommandRole
    public var studioSlot: StudioSlot?
    public var status: Status
    public var usedByDeviceId: String?
    public var usedAt: String?
    public var revokedReason: RevokedReason?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sample, inviteId, sessionId, hostDeviceId, hostEpoch, hostKeySha256, displayCode
        case joinTokenSha256, secretBits, issuedAt, expiresAt, singleUse, hostApprovalRequired, captureRole
        case commandRole, studioSlot, status, usedByDeviceId, usedAt, revokedReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        sample = try c.required(Bool.self, .sample)
        inviteId = try c.text(.inviteId, .id)
        sessionId = try c.text(.sessionId, .id)
        hostDeviceId = try c.text(.hostDeviceId, .id)
        hostEpoch = try c.int(.hostEpoch, Bound.hostEpoch)
        hostKeySha256 = try c.text(.hostKeySha256, .sha256)
        displayCode = try c.text(.displayCode, .displayCode)
        joinTokenSha256 = try c.text(.joinTokenSha256, .sha256)
        secretBits = try c.int(.secretBits, 128...256)
        issuedAt = try c.text(.issuedAt, .dateTime)
        expiresAt = try c.text(.expiresAt, .dateTime)
        try c.constant(.singleUse, true)
        try c.constant(.hostApprovalRequired, true)
        captureRole = try c.required(CaptureRole.self, .captureRole, in: [.camera, .none])
        commandRole = try c.required(CommandRole.self, .commandRole)
        studioSlot = try c.nullable(StudioSlot.self, .studioSlot)
        status = try c.required(Status.self, .status)
        usedByDeviceId = try c.nullableText(.usedByDeviceId, .id)
        usedAt = try c.nullableText(.usedAt, .dateTime)
        revokedReason = try c.nullable(RevokedReason.self, .revokedReason)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(sample, forKey: .sample)
        try c.encode(inviteId, forKey: .inviteId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(hostDeviceId, forKey: .hostDeviceId)
        try c.encode(hostEpoch, forKey: .hostEpoch)
        try c.encode(hostKeySha256, forKey: .hostKeySha256)
        try c.encode(displayCode, forKey: .displayCode)
        try c.encode(joinTokenSha256, forKey: .joinTokenSha256)
        try c.encode(secretBits, forKey: .secretBits)
        try c.encode(issuedAt, forKey: .issuedAt)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(true, forKey: .singleUse)
        try c.encode(true, forKey: .hostApprovalRequired)
        try c.encode(captureRole, forKey: .captureRole)
        try c.encode(commandRole, forKey: .commandRole)
        try c.encodeNullable(studioSlot, forKey: .studioSlot)
        try c.encode(status, forKey: .status)
        try c.encodeNullable(usedByDeviceId, forKey: .usedByDeviceId)
        try c.encodeNullable(usedAt, forKey: .usedAt)
        try c.encodeNullable(revokedReason, forKey: .revokedReason)
    }
}

/// Where a guest may connect: a DNS-SD instance of `_jovra-room._tcp`, or a LAN IP literal. Never a hostname or URL.
public enum InvitationEndpoint: Codable, Equatable, Sendable {
    public static let dnssdServiceType = "_jovra-room._tcp"

    case dnssd(instanceName: String)
    case lan(address: String, port: Int)

    private enum Kind: String, CodingKey, CaseIterable { case kind }
    private enum DNSSDKeys: String, CodingKey, CaseIterable { case kind, serviceType, instanceName }
    private enum LANKeys: String, CodingKey, CaseIterable { case kind, address, port }

    public init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: Kind.self)
        switch try probe.required(String.self, .kind) {
        case "dnssd":
            let c = try decoder.strictContainer(DNSSDKeys.self)
            try c.constant(.serviceType, Self.dnssdServiceType)
            self = .dnssd(instanceName: try c.text(.instanceName, .dnssdInstanceName))
        case "lan":
            let c = try decoder.strictContainer(LANKeys.self)
            self = .lan(address: try c.text(.address, .addressLiteral), port: try c.int(.port, 1024...65535))
        default:
            throw probe.schemaError(.kind, "endpoint kind is dnssd or lan")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .dnssd(let instanceName):
            var c = encoder.container(keyedBy: DNSSDKeys.self)
            try c.encode("dnssd", forKey: .kind)
            try c.encode(Self.dnssdServiceType, forKey: .serviceType)
            try c.encode(instanceName, forKey: .instanceName)
        case .lan(let address, let port):
            var c = encoder.container(keyedBy: LANKeys.self)
            try c.encode("lan", forKey: .kind)
            try c.encode(address, forKey: .address)
            try c.encode(port, forKey: .port)
        }
    }
}

/// `jovra.room.invitation-payload/1`: what the QR carries. It holds the join token: never persist or log it.
public struct InvitationPayload: Codable, Equatable, Sendable {
    /// The court Wi-Fi an Android host created (LocalOnlyHotspot). The passphrase is a secret like the token.
    public struct Network: Codable, Equatable, Sendable {
        public enum Security: String, Codable, CaseIterable, Sendable { case wpa2PSK = "wpa2-psk", wpa3SAE = "wpa3-sae" }
        public var ssid: String
        public var passphrase: String
        public var security: Security

        enum CodingKeys: String, CodingKey, CaseIterable { case kind, ssid, passphrase, security }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            try c.constant(.kind, "wifi")
            ssid = try c.text(.ssid, .ssid)
            passphrase = try c.text(.passphrase, .passphrase)
            security = try c.required(Security.self, .security)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("wifi", forKey: .kind)
            try c.encode(ssid, forKey: .ssid)
            try c.encode(passphrase, forKey: .passphrase)
            try c.encode(security, forKey: .security)
        }
    }

    static let schemaVersionValue = "jovra.room.invitation-payload/1"

    public var sample: Bool
    public var inviteId: String
    public var sessionId: String
    public var hostEpoch: Int
    public var hostKeySha256: String
    public var joinToken: String
    public var nonce: String
    public var issuedAt: String
    public var expiresAt: String
    public var captureRole: CaptureRole
    public var commandRole: CommandRole
    public var displayCode: String
    public var network: Network?
    public var endpoints: [InvitationEndpoint]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sample, inviteId, sessionId, hostEpoch, hostKeySha256, joinToken, nonce, issuedAt
        case expiresAt, captureRole, commandRole, displayCode, network, endpoints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        sample = try c.required(Bool.self, .sample)
        inviteId = try c.text(.inviteId, .id)
        sessionId = try c.text(.sessionId, .id)
        hostEpoch = try c.int(.hostEpoch, Bound.hostEpoch)
        hostKeySha256 = try c.text(.hostKeySha256, .sha256)
        joinToken = try c.text(.joinToken, .secretToken)
        nonce = try c.text(.nonce, .nonce)
        issuedAt = try c.text(.issuedAt, .dateTime)
        expiresAt = try c.text(.expiresAt, .dateTime)
        captureRole = try c.required(CaptureRole.self, .captureRole, in: [.camera, .none])
        commandRole = try c.required(CommandRole.self, .commandRole)
        displayCode = try c.text(.displayCode, .displayCode)
        network = try c.optional(Network.self, .network)
        endpoints = try c.objects(InvitationEndpoint.self, .endpoints, count: 1...4)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(sample, forKey: .sample)
        try c.encode(inviteId, forKey: .inviteId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(hostEpoch, forKey: .hostEpoch)
        try c.encode(hostKeySha256, forKey: .hostKeySha256)
        try c.encode(joinToken, forKey: .joinToken)
        try c.encode(nonce, forKey: .nonce)
        try c.encode(issuedAt, forKey: .issuedAt)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(captureRole, forKey: .captureRole)
        try c.encode(commandRole, forKey: .commandRole)
        try c.encode(displayCode, forKey: .displayCode)
        try c.encodeIfPresent(network, forKey: .network)
        try c.encode(endpoints, forKey: .endpoints)
    }
}

/// `jovra.room.join-request/1`: the guest's first frame. An HMAC proof, never the token.
public struct JoinRequest: Codable, Equatable, Sendable {
    static let schemaVersionValue = "jovra.room.join-request/1"

    public var inviteId: String
    public var sessionId: String
    public var hostEpoch: Int
    public var guestDeviceId: String
    public var guestKeySha256: String
    public var guestCommitment: String
    public var observedHostKeySha256: String
    public var proof: String
    public var requestedCaptureRole: CaptureRole
    public var requestedCommandRole: CommandRole
    /// The guest's own claim: display only, never identity.
    public var displayName: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, inviteId, sessionId, hostEpoch, guestDeviceId, guestKeySha256, guestCommitment
        case observedHostKeySha256, proof, requestedCaptureRole, requestedCommandRole, displayName, consent
    }

    private enum ConsentKeys: String, CodingKey, CaseIterable { case shareCaptureMetadata }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        inviteId = try c.text(.inviteId, .id)
        sessionId = try c.text(.sessionId, .id)
        hostEpoch = try c.int(.hostEpoch, Bound.hostEpoch)
        guestDeviceId = try c.text(.guestDeviceId, .id)
        guestKeySha256 = try c.text(.guestKeySha256, .sha256)
        guestCommitment = try c.text(.guestCommitment, .sha256)
        observedHostKeySha256 = try c.text(.observedHostKeySha256, .sha256)
        proof = try c.text(.proof, .sha256)
        requestedCaptureRole = try c.required(CaptureRole.self, .requestedCaptureRole, in: [.camera, .none])
        requestedCommandRole = try c.required(CommandRole.self, .requestedCommandRole)
        displayName = try c.text(.displayName, .userText)
        guard c.contains(.consent) else { throw c.schemaError(.consent, "required property missing") }
        let consent = try c.superDecoder(forKey: .consent).strictContainer(ConsentKeys.self)
        try consent.constant(.shareCaptureMetadata, true)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(inviteId, forKey: .inviteId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(hostEpoch, forKey: .hostEpoch)
        try c.encode(guestDeviceId, forKey: .guestDeviceId)
        try c.encode(guestKeySha256, forKey: .guestKeySha256)
        try c.encode(guestCommitment, forKey: .guestCommitment)
        try c.encode(observedHostKeySha256, forKey: .observedHostKeySha256)
        try c.encode(proof, forKey: .proof)
        try c.encode(requestedCaptureRole, forKey: .requestedCaptureRole)
        try c.encode(requestedCommandRole, forKey: .requestedCommandRole)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(["shareCaptureMetadata": true], forKey: .consent)
    }
}

/// `jovra.room.join-challenge/1` (`nonce` = hostNonce) and `jovra.room.join-reveal/1` (`nonce` = guestNonce): the two
/// frames of commit-then-reveal. Same shape, different schemaVersion and nonce field.
public struct JoinNonceFrame: Codable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case challenge = "jovra.room.join-challenge/1", reveal = "jovra.room.join-reveal/1"
        var nonceKey: String { self == .challenge ? "hostNonce" : "guestNonce" }
    }

    public var kind: Kind
    public var inviteId: String
    public var sessionId: String
    public var hostEpoch: Int
    public var nonce: String

    public init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: AnyCodingKey.self)
        let version = try probe.required(String.self, AnyCodingKey("schemaVersion"))
        guard let kind = Kind(rawValue: version) else {
            throw probe.schemaError(AnyCodingKey("schemaVersion"), "not a join challenge or reveal")
        }
        self.kind = kind
        let keys = ["schemaVersion", "inviteId", "sessionId", "hostEpoch", kind.nonceKey]
        if let extra = probe.allKeys.map(\.stringValue).sorted().first(where: { !keys.contains($0) }) {
            throw probe.schemaError(AnyCodingKey(extra), "property not allowed")
        }
        inviteId = try probe.text(AnyCodingKey("inviteId"), .id)
        sessionId = try probe.text(AnyCodingKey("sessionId"), .id)
        hostEpoch = try probe.int(AnyCodingKey("hostEpoch"), Bound.hostEpoch)
        nonce = try probe.text(AnyCodingKey(kind.nonceKey), .nonce)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(kind.rawValue, forKey: AnyCodingKey("schemaVersion"))
        try c.encode(inviteId, forKey: AnyCodingKey("inviteId"))
        try c.encode(sessionId, forKey: AnyCodingKey("sessionId"))
        try c.encode(hostEpoch, forKey: AnyCodingKey("hostEpoch"))
        try c.encode(nonce, forKey: AnyCodingKey(kind.nonceKey))
    }
}
