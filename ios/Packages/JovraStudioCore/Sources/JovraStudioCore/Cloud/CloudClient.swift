import Foundation

/// SD11: the one boundary between Studio and any cloud (stories 17, 20, 189, 190, 193, 194).
///
/// Three adapters implement it: `DemoCloudClient` (in-process, deterministic Sample transcripts, no network, no
/// account, no charge), `TestCloudClient` (a shell here: it refuses to start without its configuration, and the HTTP
/// side is S97) and `LiveCloudClient` (compiled, always unavailable until its activation gates are recorded).
/// `CloudClients.make` picks one from configuration; nothing else constructs a cloud client.
///
/// Every money figure a client returns is the server's (or, in demo, an illustrative Sample); the client never computes
/// a price. Every percentage belongs to one named stage (`JobStageSnapshot.percent`); there is no whole-job percentage.
public protocol CloudClient: Sendable {
    /// Which cloud this build talks to, or why it talks to none.
    func mode() async -> CloudMode
    /// Who the cloud thinks the player is. The demo is the demo profile and holds no credential of any kind.
    func identity() async throws(CloudError) -> CloudIdentity

    /// A quote for the job draft, computed by the server (Sample in demo and test).
    func quote(_ request: CloudQuoteRequest) async throws(CloudError) -> CloudQuote
    /// Accept a quote with the owner's consent and cap. The same idempotency key always names the same job and
    /// reservation. In demo this never reserves: it returns `.demoDisabled`.
    func accept(_ quote: Quote, consent: QuoteConsent, capCredits: Int,
                idempotencyKey: Ledger.Key) async throws(CloudError) -> AcceptResult

    /// Open (or resume) the upload of one source; a resumed session lists the parts the server already confirmed.
    func openUpload(sourceId: String) async throws(CloudError) -> UploadSession
    /// Send one part; never called for a part the session lists as confirmed.
    func uploadPart(_ session: UploadSession, partNumber: Int) async throws(CloudError) -> UploadSession
    func completeUpload(_ session: UploadSession) async throws(CloudError) -> UploadSession

    /// The job's snapshots: the job as it is now, then each change. Finishes when the client has nothing more to
    /// report (for an unknown job or an unavailable client, at once).
    func job(_ jobId: String) async -> AsyncStream<JobSnapshot>
    func pause(_ jobId: String) async throws(CloudError) -> JobSnapshot
    func resume(_ jobId: String) async throws(CloudError) -> JobSnapshot
    func cancel(_ jobId: String) async throws(CloudError) -> JobSnapshot

    /// The job's delivered artifacts and the state of each one's share link.
    func artifacts(_ jobId: String) async throws(CloudError) -> [CloudArtifact]
    /// A resumable download: it starts at `byteOffset` (the bytes already on the device), so confirmed bytes are
    /// never fetched twice.
    func download(artifactId: String, resumingFrom byteOffset: Int) async -> AsyncThrowingStream<DownloadEvent, any Error>
    func shareLink(_ action: ShareLinkAction, artifactId: String) async throws(CloudError) -> ShareLinkStatus

    func deleteCloudCopies(projectId: String) async throws(CloudError) -> DeletionRequest
    func exportMyData() async throws(CloudError) -> DataExportRequest
    func deleteAccount() async throws(CloudError) -> DeletionRequest
}

// MARK: - Mode and identity

/// SD11 `CloudMode {demo, test, live, unavailable(reason)}`.
public enum CloudMode: Codable, Equatable, Sendable {
    case demo
    case test
    case live
    case unavailable(CloudUnavailableReason)

    /// The mode indicator (story 20), so "signed in" never means something it is not.
    public var label: String {
        switch self {
        case .demo: "Local demo"
        case .test: "Test"
        case .live: "Connected"
        case .unavailable: "Cloud unavailable"
        }
    }

    /// The reason shown on cloud rows when the mode is unavailable; nil otherwise.
    public var unavailableMessage: String? {
        if case .unavailable(let reason) = self { reason.message } else { nil }
    }
}

/// Why no cloud is reachable. Shown as a plain reason, never an error colour (studio-screens §0.3 "Cloud unavailable").
public enum CloudUnavailableReason: String, Codable, CaseIterable, Sendable {
    /// STUDIO_ENVIRONMENT is test but the gateway URL, issuer or publishable key is missing (SD11).
    case testBackendNotConfigured
    /// The Test configuration is complete, but this build has no HTTP client yet (S97).
    case testClientNotInThisBuild
    /// Live stays off until an activation flag, its configuration and the recorded S4 gates all exist.
    case liveNotActivated
    /// STUDIO_ENVIRONMENT names no known environment.
    case unknownEnvironment

    public var message: String {
        switch self {
        case .testBackendNotConfigured: "Test backend not configured"
        case .testClientNotInThisBuild: "Test backend isn't in this build yet"
        case .liveNotActivated: "Cloud production isn't available right now."
        case .unknownEnvironment: "Cloud production isn't available right now."
        }
    }
}

public enum CloudIdentity: Codable, Equatable, Sendable {
    /// The local demo profile: no account, no credential.
    case demoProfile
    /// No account: cloud actions explain that sign-in is needed while local options stay available (story 190).
    case signedOut
    /// A signed-in test or live account (S97). The reference is opaque and is never a token.
    case signedIn(accountRef: String)
}

// MARK: - Errors

public enum CloudError: Error, Codable, Equatable, Sendable {
    /// Demo mode never uploads, reserves, shares or charges.
    case demoDisabled
    case unavailable(CloudUnavailableReason)
    /// ST37 "Sign in to make films in the cloud."
    case notSignedIn
    case quoteExpired
    case aboveCap(spendingLimitCredits: Int)
    case linkExpired
    case accessRevoked
    case unknownJob(String)
    case unknownArtifact(String)
    case unknownSource(String)
    /// The job state machine refused the step (a `LedgerRejectCode` raw value and its message).
    case refused(code: String, message: String)

    /// Words for the player where the error is shown as-is.
    public var message: String {
        switch self {
        case .demoDisabled: CloudCopy.demoDoesNotUploadOrCharge
        case .unavailable(let reason): reason.message
        case .notSignedIn: "Sign in to make films in the cloud."
        case .quoteExpired: "This quote expired."
        case .aboveCap: "The estimate is above your limit."
        case .linkExpired: "This link expired."
        case .accessRevoked: "Access to this film was removed."
        case .unknownJob, .unknownArtifact, .unknownSource, .refused: "Cloud production isn't available right now."
        }
    }

    init(_ rejection: LedgerRejection) {
        self = .refused(code: rejection.code.rawValue, message: rejection.message)
    }
}

/// Cloud copy the Studio screens share.
public enum CloudCopy {
    /// Story 17: stated wherever a cloud action appears in demo (ST37 footnote).
    public static let demoDoesNotUploadOrCharge = "Demo mode does not upload or charge."
}

// MARK: - Quote and accept

public struct CloudQuoteRequest: Codable, Equatable, Sendable {
    public var projectId: String
    public var planRevision: Int

    public init(projectId: String, planRevision: Int) {
        self.projectId = projectId
        self.planRevision = planRevision
    }
}

/// A quote as the server returned it, with what the player can do with it now.
public struct CloudQuote: Equatable, Sendable {
    public enum Condition: Codable, Equatable, Sendable {
        case open
        /// A fresh quote is required; an expired quote is never auto-accepted.
        case expired
        /// The cap is over the player's spending limit; only the player raises the limit.
        case aboveCap(spendingLimitCredits: Int)
    }

    public let quote: Quote
    public let condition: Condition
    /// False in demo and test, and in live until the pricing ADR turns charging on.
    public let chargingEnabled: Bool

    public init(quote: Quote, condition: Condition, chargingEnabled: Bool) {
        self.quote = quote
        self.condition = condition
        self.chargingEnabled = chargingEnabled
    }

    /// "Sample quote" for every demo and test quote and every illustrative amount (studio-screens §0.2 rule 4).
    public var isSample: Bool { quote.sample || quote.illustrative || quote.environment != .live }

    public var title: String { isSample ? "Sample quote" : "Quote" }

    /// "$4 – $8", from the server's display amounts; nil when the server sent none.
    public var rangeText: String? {
        quote.displayAmounts.value.map { "\(Self.dollars($0.minMinor)) – \(Self.dollars($0.maxMinor))" }
    }

    /// "$12", the spending limit the quote's cap stands for.
    public var limitText: String? { quote.displayAmounts.value.map { Self.dollars($0.capMinor) } }

    /// ST37's VoiceOver reading of the QuoteCard.
    public var accessibilityLabel: String? {
        guard let amounts = quote.displayAmounts.value else { return nil }
        return "\(title). Estimated processing \(Self.spoken(amounts.minMinor)) to \(Self.spoken(amounts.maxMinor)) dollars. "
            + "Spending limit \(Self.spoken(amounts.capMinor)) dollars."
    }

    static func dollars(_ minor: Int) -> String {
        minor % 100 == 0 ? "$\(minor / 100)" : "$\(minor / 100).\(String(format: "%02d", minor % 100))"
    }

    static func spoken(_ minor: Int) -> String {
        minor % 100 == 0 ? "\(minor / 100)" : "\(minor / 100).\(String(format: "%02d", minor % 100))"
    }
}

/// A job the server accepted.
public struct JobRef: Codable, Equatable, Sendable {
    public var jobId: String
    /// The reservation the server holds for it; always nil for a Sample transcript job.
    public var reservationId: String?

    public init(jobId: String, reservationId: String?) {
        self.jobId = jobId
        self.reservationId = reservationId
    }
}

public enum AcceptResult: Codable, Equatable, Sendable {
    case accepted(JobRef)
    /// Demo: nothing was reserved, uploaded or charged. `sampleJob` is the Sample transcript job ST38 shows instead
    /// (nil when the demo scenario has none).
    case demoDisabled(sampleJob: String?)

    /// The reservation the server holds; nil for every demo result.
    public var reservationId: String? {
        if case .accepted(let ref) = self { ref.reservationId } else { nil }
    }
}

// MARK: - Upload

/// One source's upload. Parts are fixed 32 MiB (backend-architecture §7.2); per-part targets
/// (`{url, method, headers, expiresAt}`) are fetched per part by the HTTP adapter (S97) and never stored here.
public struct UploadSession: Codable, Equatable, Sendable {
    public static let partSizeBytes = 32 * 1_024 * 1_024
    private static let maximumPartCount = 10_000

    public var uploadId: String
    public var sourceId: String
    public var byteCount: Int
    public var confirmedParts: [Int]
    public var completed: Bool
    public var sample: Bool

    public init(uploadId: String, sourceId: String, byteCount: Int, confirmedParts: [Int], completed: Bool, sample: Bool) {
        self.uploadId = uploadId
        self.sourceId = sourceId
        self.byteCount = byteCount
        self.confirmedParts = confirmedParts
        self.completed = completed
        self.sample = sample
    }

    /// A size outside the multipart protocol's bounds has no resumable parts.
    public var partCount: Int {
        guard byteCount > 0 else { return 0 }
        let count = (byteCount - 1) / Self.partSizeBytes + 1
        return count <= Self.maximumPartCount ? count : 0
    }

    /// The parts still to send, in order: a resume never re-sends a confirmed part.
    public var remainingParts: [Int] {
        let count = partCount
        guard count > 0 else { return [] }
        let confirmed = Set(confirmedParts)
        return (1...count).filter { !confirmed.contains($0) }
    }

    /// Bytes the server confirmed on valid, unique parts (the last part may be short).
    public var confirmedBytes: Int {
        let count = partCount
        guard count > 0 else { return 0 }
        let validParts = 1...count
        let confirmed = Set(confirmedParts.filter(validParts.contains))
        let lastPartBytes = byteCount - (count - 1) * Self.partSizeBytes
        return confirmed.reduce(0) { sum, part in
            sum + (part == count ? lastPartBytes : Self.partSizeBytes)
        }
    }
}

// MARK: - Artifacts, download, links

public enum ShareLinkAction: String, Codable, CaseIterable, Sendable {
    case create
    case refresh
    case revoke
}

/// A private share link (D-3: 24 hours, refresh or revoke).
public enum ShareLinkStatus: Codable, Equatable, Sendable {
    case none
    case active(grantId: String, issuedAt: String, expiresAt: String)
    case expired(grantId: String, expiredAt: String)
    case revoked(grantId: String)
}

public struct CloudArtifact: Equatable, Sendable {
    public let record: DeliveredArtifact
    public let shareLink: ShareLinkStatus
    /// False once the owner's access to the cloud copy was removed; the local copy is never affected.
    public let accessible: Bool

    public init(record: DeliveredArtifact, shareLink: ShareLinkStatus, accessible: Bool) {
        self.record = record
        self.shareLink = shareLink
        self.accessible = accessible
    }

    public var artifactId: String { record.artifactId }
    public var verified: Bool { record.verification.status == .passed }
}

public enum DownloadEvent: Codable, Equatable, Sendable {
    case progress(receivedBytes: Int, totalBytes: Int)
    case finished(totalBytes: Int)
}

// MARK: - Deletion and data export

public struct DeletionRequest: Codable, Equatable, Sendable {
    public enum Status: Codable, Equatable, Sendable {
        /// Nothing of this scope is in the cloud (the demo never uploads).
        case nothingToDelete
        case running(removed: Int, total: Int)
        case completed(removed: Int)
        /// Some copies could not be removed yet; the request stays open and is retried.
        case failed(removed: Int, total: Int)
    }

    public var requestId: String
    public var scope: String
    public var status: Status
    public var sample: Bool

    public init(requestId: String, scope: String, status: Status, sample: Bool) {
        self.requestId = requestId
        self.scope = scope
        self.status = status
        self.sample = sample
    }
}

public struct DataExportRequest: Codable, Equatable, Sendable {
    public enum Status: Codable, Equatable, Sendable {
        /// No cloud data exists for this identity (demo).
        case nothingInCloud
        case preparing
        case ready(artifactId: String)
    }

    public var requestId: String
    public var status: Status
    public var sample: Bool

    public init(requestId: String, status: Status, sample: Bool) {
        self.requestId = requestId
        self.status = status
        self.sample = sample
    }
}
