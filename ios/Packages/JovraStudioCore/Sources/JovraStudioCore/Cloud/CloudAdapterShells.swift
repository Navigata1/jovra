import Foundation

/// The Test adapter shell (SD11). It refuses to start with "Test backend not configured" unless STUDIO_ENVIRONMENT is
/// test and the gateway URL, issuer and publishable key are all configured; with them it is still unavailable, because
/// the HTTP side is S97. It holds no network code.
public struct TestCloudClient: CloudClient {
    public let configuration: CloudConfiguration
    private let shell: UnavailableCloudClient

    public init(configuration: CloudConfiguration) {
        self.configuration = configuration
        let configured = configuration.environment == .test && configuration.testBackend != nil
        shell = UnavailableCloudClient(reason: configured ? .testClientNotInThisBuild : .testBackendNotConfigured)
    }

    public func mode() async -> CloudMode { await shell.mode() }
    public func identity() async throws(CloudError) -> CloudIdentity { .signedOut }
    public func quote(_ request: CloudQuoteRequest) async throws(CloudError) -> CloudQuote { try await shell.quote(request) }
    public func accept(_ quote: Quote, consent: QuoteConsent, capCredits: Int,
                       idempotencyKey: Ledger.Key) async throws(CloudError) -> AcceptResult {
        try await shell.accept(quote, consent: consent, capCredits: capCredits, idempotencyKey: idempotencyKey)
    }
    public func openUpload(sourceId: String) async throws(CloudError) -> UploadSession { try await shell.openUpload(sourceId: sourceId) }
    public func uploadPart(_ session: UploadSession, partNumber: Int) async throws(CloudError) -> UploadSession {
        try await shell.uploadPart(session, partNumber: partNumber)
    }
    public func completeUpload(_ session: UploadSession) async throws(CloudError) -> UploadSession { try await shell.completeUpload(session) }
    public func job(_ jobId: String) async -> AsyncStream<JobSnapshot> { await shell.job(jobId) }
    public func pause(_ jobId: String) async throws(CloudError) -> JobSnapshot { try await shell.pause(jobId) }
    public func resume(_ jobId: String) async throws(CloudError) -> JobSnapshot { try await shell.resume(jobId) }
    public func cancel(_ jobId: String) async throws(CloudError) -> JobSnapshot { try await shell.cancel(jobId) }
    public func artifacts(_ jobId: String) async throws(CloudError) -> [CloudArtifact] { try await shell.artifacts(jobId) }
    public func download(artifactId: String, resumingFrom byteOffset: Int) async -> AsyncThrowingStream<DownloadEvent, any Error> {
        await shell.download(artifactId: artifactId, resumingFrom: byteOffset)
    }
    public func shareLink(_ action: ShareLinkAction, artifactId: String) async throws(CloudError) -> ShareLinkStatus {
        try await shell.shareLink(action, artifactId: artifactId)
    }
    public func deleteCloudCopies(projectId: String) async throws(CloudError) -> DeletionRequest {
        try await shell.deleteCloudCopies(projectId: projectId)
    }
    public func exportMyData() async throws(CloudError) -> DataExportRequest { try await shell.exportMyData() }
    public func deleteAccount() async throws(CloudError) -> DeletionRequest { try await shell.deleteAccount() }
}

/// The Live adapter (SD11): compiled, and unavailable until an activation flag, its configuration and the recorded S4
/// gates all exist. No S4 gate is recorded in this build, so it is unavailable in every configuration, whatever the
/// flag says. The live gateway pins its issuer, so demo and test identities are rejected by construction.
public struct LiveCloudClient: CloudClient {
    /// The S4 gates recorded as passed for this build (backend-architecture: hosted gateway, issuer pinning, charging
    /// ADR, store review). Empty until those tickets record them.
    public static let recordedGates: [String] = []

    public let configuration: CloudConfiguration
    private let shell = UnavailableCloudClient(reason: .liveNotActivated)

    public init(configuration: CloudConfiguration) {
        self.configuration = configuration
    }

    /// True only when the flag, the configuration and the recorded gates all exist; with no gate recorded, never.
    public var isActivated: Bool {
        configuration.environment == .live && configuration.liveActivationFlag && !Self.recordedGates.isEmpty
    }

    /// Unavailable even once activated: the HTTP adapter is S97, so this build has nothing to connect with.
    public func mode() async -> CloudMode { await shell.mode() }
    public func identity() async throws(CloudError) -> CloudIdentity { .signedOut }
    public func quote(_ request: CloudQuoteRequest) async throws(CloudError) -> CloudQuote { try await shell.quote(request) }
    public func accept(_ quote: Quote, consent: QuoteConsent, capCredits: Int,
                       idempotencyKey: Ledger.Key) async throws(CloudError) -> AcceptResult {
        try await shell.accept(quote, consent: consent, capCredits: capCredits, idempotencyKey: idempotencyKey)
    }
    public func openUpload(sourceId: String) async throws(CloudError) -> UploadSession { try await shell.openUpload(sourceId: sourceId) }
    public func uploadPart(_ session: UploadSession, partNumber: Int) async throws(CloudError) -> UploadSession {
        try await shell.uploadPart(session, partNumber: partNumber)
    }
    public func completeUpload(_ session: UploadSession) async throws(CloudError) -> UploadSession { try await shell.completeUpload(session) }
    public func job(_ jobId: String) async -> AsyncStream<JobSnapshot> { await shell.job(jobId) }
    public func pause(_ jobId: String) async throws(CloudError) -> JobSnapshot { try await shell.pause(jobId) }
    public func resume(_ jobId: String) async throws(CloudError) -> JobSnapshot { try await shell.resume(jobId) }
    public func cancel(_ jobId: String) async throws(CloudError) -> JobSnapshot { try await shell.cancel(jobId) }
    public func artifacts(_ jobId: String) async throws(CloudError) -> [CloudArtifact] { try await shell.artifacts(jobId) }
    public func download(artifactId: String, resumingFrom byteOffset: Int) async -> AsyncThrowingStream<DownloadEvent, any Error> {
        await shell.download(artifactId: artifactId, resumingFrom: byteOffset)
    }
    public func shareLink(_ action: ShareLinkAction, artifactId: String) async throws(CloudError) -> ShareLinkStatus {
        try await shell.shareLink(action, artifactId: artifactId)
    }
    public func deleteCloudCopies(projectId: String) async throws(CloudError) -> DeletionRequest {
        try await shell.deleteCloudCopies(projectId: projectId)
    }
    public func exportMyData() async throws(CloudError) -> DataExportRequest { try await shell.exportMyData() }
    public func deleteAccount() async throws(CloudError) -> DeletionRequest { try await shell.deleteAccount() }
}

/// A client that reaches no cloud: every action is refused with its reason, every stream is empty, and local paths
/// stay available (story 190).
public struct UnavailableCloudClient: CloudClient {
    public let reason: CloudUnavailableReason

    public init(reason: CloudUnavailableReason) {
        self.reason = reason
    }

    private var error: CloudError { .unavailable(reason) }

    public func mode() async -> CloudMode { .unavailable(reason) }
    public func identity() async throws(CloudError) -> CloudIdentity { .signedOut }
    public func quote(_ request: CloudQuoteRequest) async throws(CloudError) -> CloudQuote { throw error }
    public func accept(_ quote: Quote, consent: QuoteConsent, capCredits: Int,
                       idempotencyKey: Ledger.Key) async throws(CloudError) -> AcceptResult { throw error }
    public func openUpload(sourceId: String) async throws(CloudError) -> UploadSession { throw error }
    public func uploadPart(_ session: UploadSession, partNumber: Int) async throws(CloudError) -> UploadSession { throw error }
    public func completeUpload(_ session: UploadSession) async throws(CloudError) -> UploadSession { throw error }
    public func job(_ jobId: String) async -> AsyncStream<JobSnapshot> { AsyncStream { $0.finish() } }
    public func pause(_ jobId: String) async throws(CloudError) -> JobSnapshot { throw error }
    public func resume(_ jobId: String) async throws(CloudError) -> JobSnapshot { throw error }
    public func cancel(_ jobId: String) async throws(CloudError) -> JobSnapshot { throw error }
    public func artifacts(_ jobId: String) async throws(CloudError) -> [CloudArtifact] { throw error }
    public func download(artifactId: String, resumingFrom byteOffset: Int) async -> AsyncThrowingStream<DownloadEvent, any Error> {
        let error = error
        return AsyncThrowingStream { $0.finish(throwing: error) }
    }
    public func shareLink(_ action: ShareLinkAction, artifactId: String) async throws(CloudError) -> ShareLinkStatus { throw error }
    public func deleteCloudCopies(projectId: String) async throws(CloudError) -> DeletionRequest { throw error }
    public func exportMyData() async throws(CloudError) -> DataExportRequest { throw error }
    public func deleteAccount() async throws(CloudError) -> DeletionRequest { throw error }
}
