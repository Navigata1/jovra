// Generated named models from spec/schemas by scripts/spec/generate_swift_models.py.
// Contract changes require a contract-fix PR; no runtime JSON dictionaries are used.
import Foundation

public struct AppInfo: Codable, Equatable, Sendable {
    public var name: AppInfoName
    public var version: String
    public var build: String?
    public var platform: AppInfoPlatform

    public init(name: AppInfoName = .value, version: String, build: String? = nil, platform: AppInfoPlatform) {
        self.name = name
        self.version = version
        self.build = build
        self.platform = platform
    }
}

public enum AppInfoName: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "JOVRA"
}

public enum AppInfoPlatform: String, Codable, CaseIterable, Hashable, Sendable {
    case ios = "ios"
    case android = "android"
    case reference = "reference"
}

public struct ArchiveArchivedFile: Codable, Equatable, Sendable {
    public var role: ArchiveArchivedFileRole
    public var eventLogVersion: Int?
    public var localPath: String
    public var mimeType: String
    public var bytes: Int
    public var md5: String?
    public var sha256: String?
    public var remote: ArchiveArchivedFileRemote
    public var upload: ArchiveUploadState
    public var verification: ArchiveArchivedFileVerification?

    public init(role: ArchiveArchivedFileRole, eventLogVersion: Int? = nil, localPath: String, mimeType: String, bytes: Int, md5: String? = nil, sha256: String? = nil, remote: ArchiveArchivedFileRemote, upload: ArchiveUploadState, verification: ArchiveArchivedFileVerification? = nil) {
        self.role = role
        self.eventLogVersion = eventLogVersion
        self.localPath = localPath
        self.mimeType = mimeType
        self.bytes = bytes
        self.md5 = md5
        self.sha256 = sha256
        self.remote = remote
        self.upload = upload
        self.verification = verification
    }
}

public struct ArchiveArchivedFileRemote: Codable, Equatable, Sendable {
    public var name: String
    public var fileId: String?
    public var appProperties: [String: String]?

    public init(name: String, fileId: String? = nil, appProperties: [String: String]? = nil) {
        self.name = name
        self.fileId = fileId
        self.appProperties = appProperties
    }
}

public enum ArchiveArchivedFileRole: String, Codable, CaseIterable, Hashable, Sendable {
    case original = "original"
    case rallyOnlyCopy = "rallyOnlyCopy"
    case spaceSaver = "spaceSaver"
    case sidecar = "sidecar"
    case clip = "clip"
    case voiceNote = "voiceNote"
    case export = "export"
}

public struct ArchiveArchivedFileVerification: Codable, Equatable, Sendable {
    public var checkedAt: String
    public var remoteBytes: Int
    public var remoteMd5: String
    public var remoteSha256: String?
    public var ok: Bool

    public init(checkedAt: String, remoteBytes: Int, remoteMd5: String, remoteSha256: String? = nil, ok: Bool) {
        self.checkedAt = checkedAt
        self.remoteBytes = remoteBytes
        self.remoteMd5 = remoteMd5
        self.remoteSha256 = remoteSha256
        self.ok = ok
    }
}

public struct ArchiveManifest: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: ArchiveManifestKind
    public var sessionId: String
    public var provider: ArchiveManifestProvider
    public var scope: ArchiveManifestScope?
    public var createdAt: String
    public var updatedAt: String
    public var sample: Bool?
    public var spaceSaver: Bool?
    public var includesAudio: Bool?
    public var remoteFolder: ArchiveManifestRemoteFolder
    public var files: [ArchiveArchivedFile]

    public init(schemaVersion: SchemaVersion = .v1_1, kind: ArchiveManifestKind = .value, sessionId: String, provider: ArchiveManifestProvider = .value, scope: ArchiveManifestScope? = nil, createdAt: String, updatedAt: String, sample: Bool? = nil, spaceSaver: Bool? = nil, includesAudio: Bool? = nil, remoteFolder: ArchiveManifestRemoteFolder, files: [ArchiveArchivedFile]) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.sessionId = sessionId
        self.provider = provider
        self.scope = scope
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sample = sample
        self.spaceSaver = spaceSaver
        self.includesAudio = includesAudio
        self.remoteFolder = remoteFolder
        self.files = files
    }
}

public enum ArchiveManifestKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.archiveManifest"
}

public enum ArchiveManifestProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "googleDrive"
}

public struct ArchiveManifestRemoteFolder: Codable, Equatable, Sendable {
    public var displayPath: String
    public var folderId: String?
    public var rootFolderId: String?

    public init(displayPath: String, folderId: String? = nil, rootFolderId: String? = nil) {
        self.displayPath = displayPath
        self.folderId = folderId
        self.rootFolderId = rootFolderId
    }
}

public enum ArchiveManifestScope: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "https://www.googleapis.com/auth/drive.file"
}

public struct ArchiveUploadState: Codable, Equatable, Sendable {
    public var state: ArchiveUploadStateState
    public var lastConfirmedOffset: Int
    public var attempts: Int
    public var wifiOnly: Bool?
    public var resumable: ArchiveUploadStateResumable?
    public var lastError: ArchiveUploadStateLastError?
    public var updatedAt: String

    public init(state: ArchiveUploadStateState, lastConfirmedOffset: Int, attempts: Int, wifiOnly: Bool? = nil, resumable: ArchiveUploadStateResumable? = nil, lastError: ArchiveUploadStateLastError? = nil, updatedAt: String) {
        self.state = state
        self.lastConfirmedOffset = lastConfirmedOffset
        self.attempts = attempts
        self.wifiOnly = wifiOnly
        self.resumable = resumable
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

public struct ArchiveUploadStateLastError: Codable, Equatable, Sendable {
    public var code: ArchiveUploadStateLastErrorCode
    public var httpStatus: Int?
    public var message: String?

    public init(code: ArchiveUploadStateLastErrorCode, httpStatus: Int? = nil, message: String? = nil) {
        self.code = code
        self.httpStatus = httpStatus
        self.message = message
    }
}

public enum ArchiveUploadStateLastErrorCode: String, Codable, CaseIterable, Hashable, Sendable {
    case network = "network"
    case rateLimited = "rateLimited"
    case serverError = "serverError"
    case sessionExpired = "sessionExpired"
    case invalidGrant = "invalidGrant"
    case storageQuotaExceeded = "storageQuotaExceeded"
    case checksumMismatch = "checksumMismatch"
    case sizeMismatch = "sizeMismatch"
    case localFileMissing = "localFileMissing"
    case cancelled = "cancelled"
    case other = "other"
}

public struct ArchiveUploadStateResumable: Codable, Equatable, Sendable {
    public var secretRef: String
    public var createdAt: String

    public init(secretRef: String, createdAt: String) {
        self.secretRef = secretRef
        self.createdAt = createdAt
    }
}

public enum ArchiveUploadStateState: String, Codable, CaseIterable, Hashable, Sendable {
    case queued = "queued"
    case hashing = "hashing"
    case sessionCreated = "sessionCreated"
    case uploading = "uploading"
    case verifying = "verifying"
    case backedUp = "backedUp"
    case failed = "failed"
    case needsReconnect = "needsReconnect"
    case quotaBlocked = "quotaBlocked"
    case waitingForNetwork = "waitingForNetwork"
    case cancelled = "cancelled"
}

public struct BenchmarkBindings: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: BenchmarkBindingsKind
    public var description: String
    public var bindings: [BenchmarkBindingsBindingsItem]

    public init(schemaVersion: SchemaVersion = .v1, kind: BenchmarkBindingsKind = .value, description: String, bindings: [BenchmarkBindingsBindingsItem]) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.description = description
        self.bindings = bindings
    }
}

public struct BenchmarkBindingsBindingsItem: Codable, Equatable, Sendable {
    public var capabilityId: String
    public var task: BenchmarkBindingsBindingsItemTask
    public var metrics: [BenchmarkBindingsBindingsItemMetricsItem]
    public var rationale: String

    public init(capabilityId: String, task: BenchmarkBindingsBindingsItemTask, metrics: [BenchmarkBindingsBindingsItemMetricsItem], rationale: String) {
        self.capabilityId = capabilityId
        self.task = task
        self.metrics = metrics
        self.rationale = rationale
    }
}

public struct BenchmarkBindingsBindingsItemMetricsItem: Codable, Equatable, Sendable {
    public var task: String
    public var gate: String

    public init(task: String, gate: String) {
        self.task = task
        self.gate = gate
    }
}

public struct BenchmarkBindingsBindingsItemTask: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var tolerance: GroundTruthRationalTime?

    public init(id: String, version: String, tolerance: GroundTruthRationalTime? = nil) {
        self.id = id
        self.version = version
        self.tolerance = tolerance
    }
}

public enum BenchmarkBindingsKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.benchmarkBindings"
}

public struct BenchmarkFloorMetric: Codable, Equatable, Sendable {
    public var name: String
    public var comparator: BenchmarkFloorMetricComparator
    public var threshold: String
    public var unit: String?

    public init(name: String, comparator: BenchmarkFloorMetricComparator, threshold: String, unit: String? = nil) {
        self.name = name
        self.comparator = comparator
        self.threshold = threshold
        self.unit = unit
    }
}

public enum BenchmarkFloorMetricComparator: String, Codable, CaseIterable, Hashable, Sendable {
    case atLeast = ">="
    case atMost = "<="
}

public struct BenchmarkFraction: Codable, Equatable, Sendable {
    public var n: Int
    public var d: Int

    public init(n: Int, d: Int) {
        self.n = n
        self.d = d
    }
}

public struct BenchmarkRecord: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: BenchmarkRecordKind
    public var runId: String
    public var at: String
    public var harness: BenchmarkRecordHarness
    public var task: BenchmarkRecordTask
    public var estimator: BenchmarkRecordEstimator
    public var capabilityId: ContractNullable<String>
    public var mode: BenchmarkRecordMode
    public var band: BenchmarkRecordBand
    public var clips: [BenchmarkRecordClipsItem]
    public var metrics: [BenchmarkRecordMetricsItem]
    public var floor: ContractNullable<BenchmarkRecordFloor>
    public var verdict: ContractNullable<BenchmarkRecordVerdict>

    public init(schemaVersion: SchemaVersion = .v1, kind: BenchmarkRecordKind = .value, runId: String, at: String, harness: BenchmarkRecordHarness, task: BenchmarkRecordTask, estimator: BenchmarkRecordEstimator, capabilityId: ContractNullable<String>, mode: BenchmarkRecordMode, band: BenchmarkRecordBand, clips: [BenchmarkRecordClipsItem], metrics: [BenchmarkRecordMetricsItem], floor: ContractNullable<BenchmarkRecordFloor>, verdict: ContractNullable<BenchmarkRecordVerdict>) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.runId = runId
        self.at = at
        self.harness = harness
        self.task = task
        self.estimator = estimator
        self.capabilityId = capabilityId
        self.mode = mode
        self.band = band
        self.clips = clips
        self.metrics = metrics
        self.floor = floor
        self.verdict = verdict
    }
}

public enum BenchmarkRecordBand: String, Codable, CaseIterable, Hashable, Sendable {
    case synthetic = "synthetic"
    case real = "real"
}

public struct BenchmarkRecordClipsItem: Codable, Equatable, Sendable {
    public var truthId: String
    public var seed: Int
    public var split: BenchmarkRecordClipsItemSplit
    public var rendererSourceHash: String
    public var decodedFramesSha256: String
    public var truthEventsSha256: String
    public var outputs: [BenchmarkOutputValue]

    public init(truthId: String, seed: Int, split: BenchmarkRecordClipsItemSplit, rendererSourceHash: String, decodedFramesSha256: String, truthEventsSha256: String, outputs: [BenchmarkOutputValue]) {
        self.truthId = truthId
        self.seed = seed
        self.split = split
        self.rendererSourceHash = rendererSourceHash
        self.decodedFramesSha256 = decodedFramesSha256
        self.truthEventsSha256 = truthEventsSha256
        self.outputs = outputs
    }
}

public enum BenchmarkRecordClipsItemSplit: String, Codable, CaseIterable, Hashable, Sendable {
    case tuning = "tuning"
    case heldOut = "heldOut"
}

public struct BenchmarkRecordEstimator: Codable, Equatable, Sendable {
    public var id: String
    public var methodVersion: String
    public var role: BenchmarkRecordEstimatorRole

    public init(id: String, methodVersion: String, role: BenchmarkRecordEstimatorRole) {
        self.id = id
        self.methodVersion = methodVersion
        self.role = role
    }
}

public enum BenchmarkRecordEstimatorRole: String, Codable, CaseIterable, Hashable, Sendable {
    case candidate = "candidate"
    case oracle = "oracle"
    case null = "null"
}

public struct BenchmarkRecordFloor: Codable, Equatable, Sendable {
    public var source: String
    public var metrics: [BenchmarkFloorMetric]

    public init(source: String, metrics: [BenchmarkFloorMetric]) {
        self.source = source
        self.metrics = metrics
    }
}

public struct BenchmarkRecordHarness: Codable, Equatable, Sendable {
    public var version: String

    public init(version: String) {
        self.version = version
    }
}

public enum BenchmarkRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.benchmarkRecord"
}

public struct BenchmarkRecordMetricsItem: Codable, Equatable, Sendable {
    public var name: String
    public var unit: String?
    public var exact: ContractNullable<BenchmarkFraction>
    public var value: ContractNullable<String>

    public init(name: String, unit: String? = nil, exact: ContractNullable<BenchmarkFraction>, value: ContractNullable<String>) {
        self.name = name
        self.unit = unit
        self.exact = exact
        self.value = value
    }
}

public enum BenchmarkRecordMode: String, Codable, CaseIterable, Hashable, Sendable {
    case gate = "gate"
    case tuning = "tuning"
}

public struct BenchmarkRecordTask: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var tolerance: GroundTruthRationalTime?

    public init(id: String, version: String, tolerance: GroundTruthRationalTime? = nil) {
        self.id = id
        self.version = version
        self.tolerance = tolerance
    }
}

public struct BenchmarkRecordVerdict: Codable, Equatable, Sendable {
    public var passed: Bool
    public var checks: [BenchmarkRecordVerdictChecksItem]

    public init(passed: Bool, checks: [BenchmarkRecordVerdictChecksItem]) {
        self.passed = passed
        self.checks = checks
    }
}

public struct BenchmarkRecordVerdictChecksItem: Codable, Equatable, Sendable {
    public var name: String
    public var comparator: BenchmarkRecordVerdictChecksItemComparator
    public var threshold: String
    public var unit: String?
    public var value: ContractNullable<String>
    public var passed: Bool

    public init(name: String, comparator: BenchmarkRecordVerdictChecksItemComparator, threshold: String, unit: String? = nil, value: ContractNullable<String>, passed: Bool) {
        self.name = name
        self.comparator = comparator
        self.threshold = threshold
        self.unit = unit
        self.value = value
        self.passed = passed
    }
}

public enum BenchmarkRecordVerdictChecksItemComparator: String, Codable, CaseIterable, Hashable, Sendable {
    case atLeast = ">="
    case atMost = "<="
}

public struct CSVContract: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: CSVContractKind
    public var name: CSVContractName
    public var version: Int
    public var description: String
    public var encoding: CSVContractEncoding
    public var byteOrderMark: Bool
    public var delimiter: CSVContractDelimiter
    public var lineEnding: CSVContractLineEnding
    public var header: Bool
    public var quoting: CSVContractQuoting
    public var null: CSVContractNull
    public var booleans: [String]
    public var columns: [CSVContractColumnsItem]
    public var rows: [CSVContractRowsItem]?

    public init(schemaVersion: SchemaVersion = .v1, kind: CSVContractKind = .value, name: CSVContractName, version: Int, description: String, encoding: CSVContractEncoding = .value, byteOrderMark: Bool = false, delimiter: CSVContractDelimiter = .value, lineEnding: CSVContractLineEnding = .value, header: Bool = true, quoting: CSVContractQuoting = .value, null: CSVContractNull = .value, booleans: [String], columns: [CSVContractColumnsItem], rows: [CSVContractRowsItem]? = nil) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.name = name
        self.version = version
        self.description = description
        self.encoding = encoding
        self.byteOrderMark = byteOrderMark
        self.delimiter = delimiter
        self.lineEnding = lineEnding
        self.header = header
        self.quoting = quoting
        self.null = null
        self.booleans = booleans
        self.columns = columns
        self.rows = rows
    }
}

public struct CSVContractColumnsItem: Codable, Equatable, Sendable {
    public var name: String
    public var type: CSVContractColumnsItemType
    public var values: [String]?
    public var nullable: Bool
    public var description: String?

    public init(name: String, type: CSVContractColumnsItemType, values: [String]? = nil, nullable: Bool, description: String? = nil) {
        self.name = name
        self.type = type
        self.values = values
        self.nullable = nullable
        self.description = description
    }
}

public enum CSVContractColumnsItemType: String, Codable, CaseIterable, Hashable, Sendable {
    case integer = "integer"
    case string = "string"
    case `enum` = "enum"
    case boolean = "boolean"
}

public enum CSVContractDelimiter: String, Codable, CaseIterable, Hashable, Sendable {
    case value = ","
}

public enum CSVContractEncoding: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "utf-8"
}

public enum CSVContractKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.csvContract"
}

public enum CSVContractLineEnding: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "\n"
}

public enum CSVContractName: String, Codable, CaseIterable, Hashable, Sendable {
    case points = "points"
    case stats = "stats"
}

public enum CSVContractNull: String, Codable, CaseIterable, Hashable, Sendable {
    case value = ""
}

public enum CSVContractQuoting: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "minimal"
}

public struct CSVContractRowsItem: Codable, Equatable, Sendable {
    public var stat: String
    public var scope: CSVContractRowsItemScope

    public init(stat: String, scope: CSVContractRowsItemScope) {
        self.stat = stat
        self.scope = scope
    }
}

public enum CSVContractRowsItemScope: String, Codable, CaseIterable, Hashable, Sendable {
    case side = "side"
    case match = "match"
}

public struct CapabilityCapability: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: CapabilityCapabilityStatus
    public var inV1: Bool
    public var method: String
    public var version: String
    public var uiLabel: String
    public var outputsNeedReview: Bool
    public var requires: CapabilityCapabilityRequires
    public var gate: ContractNullable<CapabilityCapabilityGate>
    public var lastBenchmark: ContractNullable<CapabilityCapabilityLastBenchmark>
    public var notes: String?

    public init(id: String, title: String, status: CapabilityCapabilityStatus, inV1: Bool, method: String, version: String, uiLabel: String, outputsNeedReview: Bool, requires: CapabilityCapabilityRequires, gate: ContractNullable<CapabilityCapabilityGate>, lastBenchmark: ContractNullable<CapabilityCapabilityLastBenchmark>, notes: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.inV1 = inV1
        self.method = method
        self.version = version
        self.uiLabel = uiLabel
        self.outputsNeedReview = outputsNeedReview
        self.requires = requires
        self.gate = gate
        self.lastBenchmark = lastBenchmark
        self.notes = notes
    }
}

public struct CapabilityCapabilityGate: Codable, Equatable, Sendable {
    public var promotesTo: CapabilityCapabilityGatePromotesTo
    public var metrics: [CapabilityCapabilityGateMetricsItem]
    public var minimumData: String

    public init(promotesTo: CapabilityCapabilityGatePromotesTo, metrics: [CapabilityCapabilityGateMetricsItem], minimumData: String) {
        self.promotesTo = promotesTo
        self.metrics = metrics
        self.minimumData = minimumData
    }
}

public struct CapabilityCapabilityGateMetricsItem: Codable, Equatable, Sendable {
    public var name: String
    public var comparator: CapabilityCapabilityGateMetricsItemComparator
    public var threshold: String
    public var unit: String?

    public init(name: String, comparator: CapabilityCapabilityGateMetricsItemComparator, threshold: String, unit: String? = nil) {
        self.name = name
        self.comparator = comparator
        self.threshold = threshold
        self.unit = unit
    }
}

public enum CapabilityCapabilityGateMetricsItemComparator: String, Codable, CaseIterable, Hashable, Sendable {
    case atLeast = ">="
    case atMost = "<="
}

public enum CapabilityCapabilityGatePromotesTo: String, Codable, CaseIterable, Hashable, Sendable {
    case estimated = "estimated"
    case validated = "validated"
}

public struct CapabilityCapabilityLastBenchmark: Codable, Equatable, Sendable {
    public var runId: String
    public var at: String
    public var dataset: String
    public var passed: Bool
    public var results: [CapabilityCapabilityLastBenchmarkResultsItem]

    public init(runId: String, at: String, dataset: String, passed: Bool, results: [CapabilityCapabilityLastBenchmarkResultsItem]) {
        self.runId = runId
        self.at = at
        self.dataset = dataset
        self.passed = passed
        self.results = results
    }
}

public struct CapabilityCapabilityLastBenchmarkResultsItem: Codable, Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct CapabilityCapabilityRequires: Codable, Equatable, Sendable {
    public var calibration: Bool
    public var microphone: Bool
    public var video: Bool
    public var capabilities: [String]?

    public init(calibration: Bool, microphone: Bool, video: Bool, capabilities: [String]? = nil) {
        self.calibration = calibration
        self.microphone = microphone
        self.video = video
        self.capabilities = capabilities
    }
}

public enum CapabilityCapabilityStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case manual = "manual"
    case estimated = "estimated"
    case validated = "validated"
    case disabled = "disabled"
    case unsupported = "unsupported"
}

public struct CapabilityRegistry: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: CapabilityRegistryKind
    public var registryVersion: Int
    public var updatedAt: String
    public var capabilities: [CapabilityCapability]

    public init(schemaVersion: SchemaVersion = .v1, kind: CapabilityRegistryKind = .value, registryVersion: Int, updatedAt: String, capabilities: [CapabilityCapability]) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.registryVersion = registryVersion
        self.updatedAt = updatedAt
        self.capabilities = capabilities
    }
}

public enum CapabilityRegistryKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.capabilityRegistry"
}

public struct CourtPoint2D: Codable, Equatable, Sendable {
    public var x: Decimal
    public var y: Decimal

    public init(x: Decimal, y: Decimal) {
        self.x = x
        self.y = y
    }
}

public struct EquipmentDocument: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: EquipmentDocumentKind
    public var updatedAt: String
    public var sample: EquipmentDocumentSample?
    public var frameModels: [EquipmentFrameModel]?
    public var rackets: [EquipmentRacket]
    public var stringProducts: [EquipmentStringProduct]
    public var stringInventory: [EquipmentStringInventoryItem]?
    public var stringJobs: [EquipmentStringJob]
    public var measurements: [EquipmentMeasurement]?
    public var setupRatings: [EquipmentSetupRating]?
    public var courtKit: [EquipmentKitItem]?
    public var reminders: [EquipmentReminder]?

    public init(schemaVersion: SchemaVersion = .v1, kind: EquipmentDocumentKind = .value, updatedAt: String, sample: EquipmentDocumentSample? = nil, frameModels: [EquipmentFrameModel]? = nil, rackets: [EquipmentRacket], stringProducts: [EquipmentStringProduct], stringInventory: [EquipmentStringInventoryItem]? = nil, stringJobs: [EquipmentStringJob], measurements: [EquipmentMeasurement]? = nil, setupRatings: [EquipmentSetupRating]? = nil, courtKit: [EquipmentKitItem]? = nil, reminders: [EquipmentReminder]? = nil) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.updatedAt = updatedAt
        self.sample = sample
        self.frameModels = frameModels
        self.rackets = rackets
        self.stringProducts = stringProducts
        self.stringInventory = stringInventory
        self.stringJobs = stringJobs
        self.measurements = measurements
        self.setupRatings = setupRatings
        self.courtKit = courtKit
        self.reminders = reminders
    }
}

public enum EquipmentDocumentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.equipment"
}

public struct EquipmentDocumentSample: Codable, Equatable, Sendable {
    public var label: EquipmentDocumentSampleLabel

    public init(label: EquipmentDocumentSampleLabel = .value) {
        self.label = label
    }
}

public enum EquipmentDocumentSampleLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "Sample"
}

public struct EquipmentFrameModel: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var brand: String
    public var model: String
    public var variant: String?
    public var year: Int?
    public var headSize: EquipmentFrameModelHeadSize?
    public var stringPattern: EquipmentFrameModelStringPattern?
    public var length: EquipmentFrameModelLength?
    public var recommendedTension: EquipmentFrameModelRecommendedTension?
    public var source: EquipmentFrameModelSource?

    public init(id: String, createdAt: String, updatedAt: String, deletedAt: String? = nil, brand: String, model: String, variant: String? = nil, year: Int? = nil, headSize: EquipmentFrameModelHeadSize? = nil, stringPattern: EquipmentFrameModelStringPattern? = nil, length: EquipmentFrameModelLength? = nil, recommendedTension: EquipmentFrameModelRecommendedTension? = nil, source: EquipmentFrameModelSource? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.brand = brand
        self.model = model
        self.variant = variant
        self.year = year
        self.headSize = headSize
        self.stringPattern = stringPattern
        self.length = length
        self.recommendedTension = recommendedTension
        self.source = source
    }
}

public struct EquipmentFrameModelHeadSize: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentFrameModelHeadSizeUnit

    public init(value: String, unit: EquipmentFrameModelHeadSizeUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentFrameModelHeadSizeUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case cm2 = "cm2"
    case in2 = "in2"
}

public struct EquipmentFrameModelLength: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentFrameModelLengthUnit

    public init(value: String, unit: EquipmentFrameModelLengthUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentFrameModelLengthUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case mm = "mm"
    case cm = "cm"
    case m = "m"
    case `in` = "in"
    case ft = "ft"
}

public struct EquipmentFrameModelRecommendedTension: Codable, Equatable, Sendable {
    public var min: EquipmentFrameModelRecommendedTensionMin
    public var max: EquipmentFrameModelRecommendedTensionMax

    public init(min: EquipmentFrameModelRecommendedTensionMin, max: EquipmentFrameModelRecommendedTensionMax) {
        self.min = min
        self.max = max
    }
}

public struct EquipmentFrameModelRecommendedTensionMax: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentFrameModelRecommendedTensionMaxUnit

    public init(value: String, unit: EquipmentFrameModelRecommendedTensionMaxUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentFrameModelRecommendedTensionMaxUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case lb = "lb"
    case kg = "kg"
}

public struct EquipmentFrameModelRecommendedTensionMin: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentFrameModelRecommendedTensionMinUnit

    public init(value: String, unit: EquipmentFrameModelRecommendedTensionMinUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentFrameModelRecommendedTensionMinUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case lb = "lb"
    case kg = "kg"
}

public enum EquipmentFrameModelSource: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "userEntered"
}

public struct EquipmentFrameModelStringPattern: Codable, Equatable, Sendable {
    public var mains: Int
    public var crosses: Int

    public init(mains: Int, crosses: Int) {
        self.mains = mains
        self.crosses = crosses
    }
}

public struct EquipmentKitItem: Codable, Equatable, Sendable {
    public var id: String
    public var kind: EquipmentKitItemKind
    public var label: String

    public init(id: String, kind: EquipmentKitItemKind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }
}

public enum EquipmentKitItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case bag = "bag"
    case balls = "balls"
    case shoes = "shoes"
    case grip = "grip"
    case other = "other"
}

public struct EquipmentMeasurement: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var stringJobId: String
    public var takenAt: String
    public var method: EquipmentMeasurementMethod
    public var raw: EquipmentMeasurementRaw
    public var provenance: RecordProvenance

    public init(id: String, createdAt: String, updatedAt: String, deletedAt: String? = nil, stringJobId: String, takenAt: String, method: EquipmentMeasurementMethod, raw: EquipmentMeasurementRaw, provenance: RecordProvenance) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.stringJobId = stringJobId
        self.takenAt = takenAt
        self.method = method
        self.raw = raw
        self.provenance = provenance
    }
}

public enum EquipmentMeasurementMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case ertDT = "ertDT"
    case rdc = "rdc"
    case stringmeter = "stringmeter"
    case other = "other"
}

public struct EquipmentMeasurementRaw: Codable, Equatable, Sendable {
    public var value: String
    public var unit: String

    public init(value: String, unit: String) {
        self.value = value
        self.unit = unit
    }
}

public struct EquipmentRacket: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var ownerPlayerId: String
    public var frameModelId: String?
    public var nickname: String
    public var gripSize: String?
    public var purchasedAt: String?
    public var price: EquipmentRacketPrice?
    public var measuredSpecs: [EquipmentRacketMeasuredSpecsItem]?
    public var customizations: [EquipmentRacketCustomizationsItem]?
    public var status: EquipmentRacketStatus
    public var photos: [RecordFileReference]?
    public var notes: String?

    public init(id: String, createdAt: String, updatedAt: String, deletedAt: String? = nil, ownerPlayerId: String, frameModelId: String? = nil, nickname: String, gripSize: String? = nil, purchasedAt: String? = nil, price: EquipmentRacketPrice? = nil, measuredSpecs: [EquipmentRacketMeasuredSpecsItem]? = nil, customizations: [EquipmentRacketCustomizationsItem]? = nil, status: EquipmentRacketStatus, photos: [RecordFileReference]? = nil, notes: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.ownerPlayerId = ownerPlayerId
        self.frameModelId = frameModelId
        self.nickname = nickname
        self.gripSize = gripSize
        self.purchasedAt = purchasedAt
        self.price = price
        self.measuredSpecs = measuredSpecs
        self.customizations = customizations
        self.status = status
        self.photos = photos
        self.notes = notes
    }
}

public struct EquipmentRacketCustomizationsItem: Codable, Equatable, Sendable {
    public var kind: EquipmentRacketCustomizationsItemKind
    public var position: String?
    public var mass: EquipmentRacketCustomizationsItemMass?
    public var note: String?

    public init(kind: EquipmentRacketCustomizationsItemKind, position: String? = nil, mass: EquipmentRacketCustomizationsItemMass? = nil, note: String? = nil) {
        self.kind = kind
        self.position = position
        self.mass = mass
        self.note = note
    }
}

public enum EquipmentRacketCustomizationsItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case leadTape = "leadTape"
    case grip = "grip"
    case overgrip = "overgrip"
    case dampener = "dampener"
    case other = "other"
}

public struct EquipmentRacketCustomizationsItemMass: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentRacketCustomizationsItemMassUnit

    public init(value: String, unit: EquipmentRacketCustomizationsItemMassUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentRacketCustomizationsItemMassUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case g = "g"
    case oz = "oz"
}

public struct EquipmentRacketMeasuredSpecsItem: Codable, Equatable, Sendable {
    public var kind: EquipmentRacketMeasuredSpecsItemKind
    public var value: String
    public var unit: EquipmentRacketMeasuredSpecsItemUnit
    public var measuredAt: String
    public var strung: Bool

    public init(kind: EquipmentRacketMeasuredSpecsItemKind, value: String, unit: EquipmentRacketMeasuredSpecsItemUnit, measuredAt: String, strung: Bool) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.measuredAt = measuredAt
        self.strung = strung
    }
}

public enum EquipmentRacketMeasuredSpecsItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case weight = "weight"
    case balance = "balance"
    case swingweight = "swingweight"
    case stiffnessRA = "stiffnessRA"
}

public enum EquipmentRacketMeasuredSpecsItemUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case g = "g"
    case oz = "oz"
    case mm = "mm"
    case cm = "cm"
    case `in` = "in"
    case ptsHL = "ptsHL"
    case kgcm2 = "kgcm2"
    case rA = "RA"
}

public struct EquipmentRacketPrice: Codable, Equatable, Sendable {
    public var amountMinor: Int
    public var currency: String

    public init(amountMinor: Int, currency: String) {
        self.amountMinor = amountMinor
        self.currency = currency
    }
}

public enum EquipmentRacketStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case active = "active"
    case retired = "retired"
}

public struct EquipmentReminder: Codable, Equatable, Sendable {
    public var id: String
    public var racketId: String
    public var afterLoggedHours: Int?
    public var afterDays: Int?

    public init(id: String, racketId: String, afterLoggedHours: Int? = nil, afterDays: Int? = nil) {
        self.id = id
        self.racketId = racketId
        self.afterLoggedHours = afterLoggedHours
        self.afterDays = afterDays
    }
}

public struct EquipmentSetupRating: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var stringJobId: String
    public var ratedAt: String
    public var stage: EquipmentSetupRatingStage?
    public var axes: EquipmentSetupRatingAxes
    public var note: String?

    public init(id: String, createdAt: String, updatedAt: String, deletedAt: String? = nil, stringJobId: String, ratedAt: String, stage: EquipmentSetupRatingStage? = nil, axes: EquipmentSetupRatingAxes, note: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.stringJobId = stringJobId
        self.ratedAt = ratedAt
        self.stage = stage
        self.axes = axes
        self.note = note
    }
}

public struct EquipmentSetupRatingAxes: Codable, Equatable, Sendable {
    public var control: Int?
    public var comfort: Int?
    public var spin: Int?
    public var power: Int?
    public var feel: Int?
    public var durability: Int?

    public init(control: Int? = nil, comfort: Int? = nil, spin: Int? = nil, power: Int? = nil, feel: Int? = nil, durability: Int? = nil) {
        self.control = control
        self.comfort = comfort
        self.spin = spin
        self.power = power
        self.feel = feel
        self.durability = durability
    }
}

public enum EquipmentSetupRatingStage: String, Codable, CaseIterable, Hashable, Sendable {
    case fresh = "fresh"
    case mid = "mid"
    case removal = "removal"
    case other = "other"
}

public struct EquipmentStringInventoryItem: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var stringProductId: String
    public var form: EquipmentStringInventoryItemForm
    public var initialLength: EquipmentStringInventoryItemInitialLength?
    public var remainingLength: EquipmentStringInventoryItemRemainingLength?
    public var purchasedAt: String?
    public var cost: EquipmentStringInventoryItemCost?

    public init(id: String, createdAt: String, updatedAt: String, deletedAt: String? = nil, stringProductId: String, form: EquipmentStringInventoryItemForm, initialLength: EquipmentStringInventoryItemInitialLength? = nil, remainingLength: EquipmentStringInventoryItemRemainingLength? = nil, purchasedAt: String? = nil, cost: EquipmentStringInventoryItemCost? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.stringProductId = stringProductId
        self.form = form
        self.initialLength = initialLength
        self.remainingLength = remainingLength
        self.purchasedAt = purchasedAt
        self.cost = cost
    }
}

public struct EquipmentStringInventoryItemCost: Codable, Equatable, Sendable {
    public var amountMinor: Int
    public var currency: String

    public init(amountMinor: Int, currency: String) {
        self.amountMinor = amountMinor
        self.currency = currency
    }
}

public enum EquipmentStringInventoryItemForm: String, Codable, CaseIterable, Hashable, Sendable {
    case set = "set"
    case halfSet = "halfSet"
    case reel = "reel"
}

public struct EquipmentStringInventoryItemInitialLength: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentStringInventoryItemInitialLengthUnit

    public init(value: String, unit: EquipmentStringInventoryItemInitialLengthUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentStringInventoryItemInitialLengthUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case mm = "mm"
    case cm = "cm"
    case m = "m"
    case `in` = "in"
    case ft = "ft"
}

public struct EquipmentStringInventoryItemRemainingLength: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentStringInventoryItemRemainingLengthUnit

    public init(value: String, unit: EquipmentStringInventoryItemRemainingLengthUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentStringInventoryItemRemainingLengthUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case mm = "mm"
    case cm = "cm"
    case m = "m"
    case `in` = "in"
    case ft = "ft"
}

public struct EquipmentStringJob: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var racketId: String
    public var strungOn: String
    public var timeZone: String?
    public var strungBy: EquipmentStringJobStrungBy?
    public var machine: EquipmentStringJobMachine?
    public var layout: EquipmentStringJobLayout
    public var mains: EquipmentStringSegment
    public var crosses: EquipmentStringSegment
    public var method: EquipmentStringJobMethod?
    public var clonedFromJobId: String?
    public var endedOn: String?
    public var endReason: EquipmentStringJobEndReason?
    public var breakage: EquipmentStringJobBreakage?
    public var cost: EquipmentStringJobCost?
    public var notes: String?
    public var photos: [RecordFileReference]?

    public init(id: String, createdAt: String, updatedAt: String, deletedAt: String? = nil, racketId: String, strungOn: String, timeZone: String? = nil, strungBy: EquipmentStringJobStrungBy? = nil, machine: EquipmentStringJobMachine? = nil, layout: EquipmentStringJobLayout, mains: EquipmentStringSegment, crosses: EquipmentStringSegment, method: EquipmentStringJobMethod? = nil, clonedFromJobId: String? = nil, endedOn: String? = nil, endReason: EquipmentStringJobEndReason? = nil, breakage: EquipmentStringJobBreakage? = nil, cost: EquipmentStringJobCost? = nil, notes: String? = nil, photos: [RecordFileReference]? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.racketId = racketId
        self.strungOn = strungOn
        self.timeZone = timeZone
        self.strungBy = strungBy
        self.machine = machine
        self.layout = layout
        self.mains = mains
        self.crosses = crosses
        self.method = method
        self.clonedFromJobId = clonedFromJobId
        self.endedOn = endedOn
        self.endReason = endReason
        self.breakage = breakage
        self.cost = cost
        self.notes = notes
        self.photos = photos
    }
}

public struct EquipmentStringJobBreakage: Codable, Equatable, Sendable {
    public var segment: EquipmentStringJobBreakageSegment?
    public var sessionId: String?
    public var videoTimeMs: Int?

    public init(segment: EquipmentStringJobBreakageSegment? = nil, sessionId: String? = nil, videoTimeMs: Int? = nil) {
        self.segment = segment
        self.sessionId = sessionId
        self.videoTimeMs = videoTimeMs
    }
}

public enum EquipmentStringJobBreakageSegment: String, Codable, CaseIterable, Hashable, Sendable {
    case mains = "mains"
    case crosses = "crosses"
    case unknown = "unknown"
}

public struct EquipmentStringJobCost: Codable, Equatable, Sendable {
    public var amountMinor: Int
    public var currency: String

    public init(amountMinor: Int, currency: String) {
        self.amountMinor = amountMinor
        self.currency = currency
    }
}

public enum EquipmentStringJobEndReason: String, Codable, CaseIterable, Hashable, Sendable {
    case broke = "broke"
    case cutOut = "cutOut"
    case plannedRestring = "plannedRestring"
    case retired = "retired"
    case unknown = "unknown"
}

public enum EquipmentStringJobLayout: String, Codable, CaseIterable, Hashable, Sendable {
    case fullBed = "fullBed"
    case hybrid = "hybrid"
}

public struct EquipmentStringJobMachine: Codable, Equatable, Sendable {
    public var makeModel: String?
    public var type: EquipmentStringJobMachineType?

    public init(makeModel: String? = nil, type: EquipmentStringJobMachineType? = nil) {
        self.makeModel = makeModel
        self.type = type
    }
}

public enum EquipmentStringJobMachineType: String, Codable, CaseIterable, Hashable, Sendable {
    case dropWeight = "dropWeight"
    case crankLockout = "crankLockout"
    case electronicConstantPull = "electronicConstantPull"
    case electronicLockout = "electronicLockout"
    case unknown = "unknown"
}

public enum EquipmentStringJobMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case twoPiece = "twoPiece"
    case onePiece = "onePiece"
    case onePieceATW = "onePieceATW"
    case unknown = "unknown"
}

public struct EquipmentStringJobStrungBy: Codable, Equatable, Sendable {
    public var kind: EquipmentStringJobStrungByKind
    public var displayName: String?

    public init(kind: EquipmentStringJobStrungByKind, displayName: String? = nil) {
        self.kind = kind
        self.displayName = displayName
    }
}

public enum EquipmentStringJobStrungByKind: String, Codable, CaseIterable, Hashable, Sendable {
    case `self` = "self"
    case person = "person"
    case shop = "shop"
}

public struct EquipmentStringProduct: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var deletedAt: String?
    public var brand: String
    public var model: String
    public var material: EquipmentStringProductMaterial
    public var construction: EquipmentStringProductConstruction?
    public var gaugeLabel: String?
    public var nominalDiameterMm: String?
    public var color: String?

    public init(id: String, createdAt: String, updatedAt: String, deletedAt: String? = nil, brand: String, model: String, material: EquipmentStringProductMaterial, construction: EquipmentStringProductConstruction? = nil, gaugeLabel: String? = nil, nominalDiameterMm: String? = nil, color: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.brand = brand
        self.model = model
        self.material = material
        self.construction = construction
        self.gaugeLabel = gaugeLabel
        self.nominalDiameterMm = nominalDiameterMm
        self.color = color
    }
}

public enum EquipmentStringProductConstruction: String, Codable, CaseIterable, Hashable, Sendable {
    case round = "round"
    case shaped = "shaped"
    case textured = "textured"
    case multifilament = "multifilament"
    case solidCoreWrap = "solidCoreWrap"
    case other = "other"
}

public enum EquipmentStringProductMaterial: String, Codable, CaseIterable, Hashable, Sendable {
    case naturalGut = "naturalGut"
    case syntheticGut = "syntheticGut"
    case multifilament = "multifilament"
    case polyester = "polyester"
    case aramid = "aramid"
    case hybridSet = "hybridSet"
    case other = "other"
}

public struct EquipmentStringSegment: Codable, Equatable, Sendable {
    public var stringProductId: String?
    public var productSnapshot: EquipmentStringSegmentProductSnapshot
    public var tension: EquipmentStringSegmentTension
    public var prestretch: EquipmentStringSegmentPrestretch?

    public init(stringProductId: String? = nil, productSnapshot: EquipmentStringSegmentProductSnapshot, tension: EquipmentStringSegmentTension, prestretch: EquipmentStringSegmentPrestretch? = nil) {
        self.stringProductId = stringProductId
        self.productSnapshot = productSnapshot
        self.tension = tension
        self.prestretch = prestretch
    }
}

public struct EquipmentStringSegmentPrestretch: Codable, Equatable, Sendable {
    public var method: EquipmentStringSegmentPrestretchMethod
    public var percent: Int?

    public init(method: EquipmentStringSegmentPrestretchMethod, percent: Int? = nil) {
        self.method = method
        self.percent = percent
    }
}

public enum EquipmentStringSegmentPrestretchMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case none = "none"
    case machinePercent = "machinePercent"
    case manual = "manual"
    case unknown = "unknown"
}

public struct EquipmentStringSegmentProductSnapshot: Codable, Equatable, Sendable {
    public var brand: String
    public var model: String
    public var gaugeLabel: String?
    public var nominalDiameterMm: String?

    public init(brand: String, model: String, gaugeLabel: String? = nil, nominalDiameterMm: String? = nil) {
        self.brand = brand
        self.model = model
        self.gaugeLabel = gaugeLabel
        self.nominalDiameterMm = nominalDiameterMm
    }
}

public struct EquipmentStringSegmentTension: Codable, Equatable, Sendable {
    public var value: String
    public var unit: EquipmentStringSegmentTensionUnit

    public init(value: String, unit: EquipmentStringSegmentTensionUnit) {
        self.value = value
        self.unit = unit
    }
}

public enum EquipmentStringSegmentTensionUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case lb = "lb"
    case kg = "kg"
}

public struct ExportManifest: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: ExportManifestKind
    public var exportedAt: String
    public var app: AppInfo
    public var scope: ExportManifestScope
    public var includesAudio: Bool
    public var includesOriginals: Bool
    public var sessions: [ExportManifestSessionsItem]
    public var files: [ExportManifestFilesItem]
    public var csvContracts: [ExportManifestCsvContractsItem]
    public var contact: ExportManifestContact?
    public var facesBlurred: Bool?
    public var sharePack: ExportManifestSharePack?

    public init(schemaVersion: SchemaVersion = .v1_1, kind: ExportManifestKind = .value, exportedAt: String, app: AppInfo, scope: ExportManifestScope, includesAudio: Bool, includesOriginals: Bool, sessions: [ExportManifestSessionsItem], files: [ExportManifestFilesItem], csvContracts: [ExportManifestCsvContractsItem], contact: ExportManifestContact? = nil, facesBlurred: Bool? = nil, sharePack: ExportManifestSharePack? = nil) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.exportedAt = exportedAt
        self.app = app
        self.scope = scope
        self.includesAudio = includesAudio
        self.includesOriginals = includesOriginals
        self.sessions = sessions
        self.files = files
        self.csvContracts = csvContracts
        self.contact = contact
        self.facesBlurred = facesBlurred
        self.sharePack = sharePack
    }
}

public enum ExportManifestContact: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "hello@islanddevcrew.com"
}

public struct ExportManifestCsvContractsItem: Codable, Equatable, Sendable {
    public var name: ExportManifestCsvContractsItemName
    public var version: Int

    public init(name: ExportManifestCsvContractsItemName, version: Int) {
        self.name = name
        self.version = version
    }
}

public enum ExportManifestCsvContractsItemName: String, Codable, CaseIterable, Hashable, Sendable {
    case points = "points"
    case stats = "stats"
}

public struct ExportManifestFilesItem: Codable, Equatable, Sendable {
    public var path: String
    public var role: ExportManifestFilesItemRole
    public var mimeType: String?
    public var bytes: Int
    public var sha256: String
    public var sessionId: String?

    public init(path: String, role: ExportManifestFilesItemRole, mimeType: String? = nil, bytes: Int, sha256: String, sessionId: String? = nil) {
        self.path = path
        self.role = role
        self.mimeType = mimeType
        self.bytes = bytes
        self.sha256 = sha256
        self.sessionId = sessionId
    }
}

public enum ExportManifestFilesItemRole: String, Codable, CaseIterable, Hashable, Sendable {
    case sessionJson = "sessionJson"
    case equipmentJson = "equipmentJson"
    case pointsCsv = "pointsCsv"
    case statsCsv = "statsCsv"
    case original = "original"
    case clip = "clip"
    case condensedMatch = "condensedMatch"
    case highlightReel = "highlightReel"
    case voiceNote = "voiceNote"
    case readme = "readme"
    case viewerHtml = "viewerHtml"
}

public enum ExportManifestKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.export"
}

public enum ExportManifestScope: String, Codable, CaseIterable, Hashable, Sendable {
    case session = "session"
    case allData = "allData"
    case sharePack = "sharePack"
}

public struct ExportManifestSessionsItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var path: String
    public var sample: Bool?
    public var eventLogVersion: Int?

    public init(id: String, title: String, path: String, sample: Bool? = nil, eventLogVersion: Int? = nil) {
        self.id = id
        self.title = title
        self.path = path
        self.sample = sample
        self.eventLogVersion = eventLogVersion
    }
}

public struct ExportManifestSharePack: Codable, Equatable, Sendable {
    public var audience: ExportManifestSharePackAudience
    public var selection: ExportManifestSharePackSelection
    public var source: ExportManifestSharePackSource?

    public init(audience: ExportManifestSharePackAudience, selection: ExportManifestSharePackSelection, source: ExportManifestSharePackSource? = nil) {
        self.audience = audience
        self.selection = selection
        self.source = source
    }
}

public enum ExportManifestSharePackAudience: String, Codable, CaseIterable, Hashable, Sendable {
    case coach = "coach"
    case opponent = "opponent"
    case doublesPartner = "doublesPartner"
}

public enum ExportManifestSharePackSelection: String, Codable, CaseIterable, Hashable, Sendable {
    case fullCopy = "fullCopy"
    case selectedPoints = "selectedPoints"
    case teamPoints = "teamPoints"
}

public enum ExportManifestSharePackSource: String, Codable, CaseIterable, Hashable, Sendable {
    case proxy720p = "proxy720p"
    case rallyOnly = "rallyOnly"
    case original = "original"
}

public struct GroundTruthRationalTime: Codable, Equatable, Sendable {
    public var value: Int
    public var timescale: Int

    public init(value: Int, timescale: Int) {
        self.value = value
        self.timescale = timescale
    }
}

public struct GroundTruthRecord: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: GroundTruthRecordKind
    public var id: String
    public var set: String
    public var description: String
    public var band: GroundTruthRecordBand
    public var renderer: GroundTruthRecordRenderer
    public var media: GroundTruthRecordMedia
    public var seed: ContractNullable<Int>
    public var split: ContractNullable<GroundTruthRecordSplit>
    public var duplicateOf: ContractNullable<String>
    public var video: GroundTruthRecordVideo
    public var audio: ContractNullable<GroundTruthRecordAudio>
    public var frameCode: GroundTruthRecordFrameCode
    public var signature: GroundTruthRecordSignature
    public var events: [GroundTruthRecordEventsItem]?
    public var court: GroundTruthRecordCourt?
    public var flashCell: GroundTruthRecordFlashCell?

    public init(schemaVersion: SchemaVersion = .v1, kind: GroundTruthRecordKind = .value, id: String, set: String, description: String, band: GroundTruthRecordBand, renderer: GroundTruthRecordRenderer, media: GroundTruthRecordMedia, seed: ContractNullable<Int>, split: ContractNullable<GroundTruthRecordSplit>, duplicateOf: ContractNullable<String>, video: GroundTruthRecordVideo, audio: ContractNullable<GroundTruthRecordAudio>, frameCode: GroundTruthRecordFrameCode, signature: GroundTruthRecordSignature, events: [GroundTruthRecordEventsItem]? = nil, court: GroundTruthRecordCourt? = nil, flashCell: GroundTruthRecordFlashCell? = nil) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.id = id
        self.set = set
        self.description = description
        self.band = band
        self.renderer = renderer
        self.media = media
        self.seed = seed
        self.split = split
        self.duplicateOf = duplicateOf
        self.video = video
        self.audio = audio
        self.frameCode = frameCode
        self.signature = signature
        self.events = events
        self.court = court
        self.flashCell = flashCell
    }
}

public struct GroundTruthRecordAudio: Codable, Equatable, Sendable {
    public var codec: GroundTruthRecordAudioCodec
    public var sampleRate: GroundTruthRecordAudioSampleRate
    public var channels: GroundTruthRecordAudioChannels
    public var sampleCount: Int

    public init(codec: GroundTruthRecordAudioCodec = .value, sampleRate: GroundTruthRecordAudioSampleRate = .value, channels: GroundTruthRecordAudioChannels, sampleCount: Int) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.sampleCount = sampleCount
    }
}

public enum GroundTruthRecordAudioChannels: Int, Codable, CaseIterable, Hashable, Sendable {
    case value1 = 1
    case value2 = 2
}

public enum GroundTruthRecordAudioCodec: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "aac"
}

public enum GroundTruthRecordAudioSampleRate: Int, Codable, CaseIterable, Hashable, Sendable {
    case value = 48000
}

public enum GroundTruthRecordBand: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "synthetic"
}

public struct GroundTruthRecordCourt: Codable, Equatable, Sendable {
    public var space: GroundTruthRecordCourtSpace
    public var order: GroundTruthRecordCourtOrder
    public var points: [GroundTruthRecordCourtPointsItem]

    public init(space: GroundTruthRecordCourtSpace = .value, order: GroundTruthRecordCourtOrder = .value, points: [GroundTruthRecordCourtPointsItem]) {
        self.space = space
        self.order = order
        self.points = points
    }
}

public enum GroundTruthRecordCourtOrder: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "topLeft,topRight,bottomRight,bottomLeft"
}

public struct GroundTruthRecordCourtPointsItem: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public enum GroundTruthRecordCourtSpace: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "displayPixels"
}

public struct GroundTruthRecordEventsItem: Codable, Equatable, Sendable {
    public var type: GroundTruthRecordEventsItemType
    public var time: GroundTruthRationalTime
    public var sample: Int
    public var frame: Int

    public init(type: GroundTruthRecordEventsItemType, time: GroundTruthRationalTime, sample: Int, frame: Int) {
        self.type = type
        self.time = time
        self.sample = sample
        self.frame = frame
    }
}

public enum GroundTruthRecordEventsItemType: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "hit"
}

public struct GroundTruthRecordFlashCell: Codable, Equatable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public struct GroundTruthRecordFrameCode: Codable, Equatable, Sendable {
    public var cells: GroundTruthRecordFrameCodeCells
    public var encodes: GroundTruthRecordFrameCodeEncodes

    public init(cells: GroundTruthRecordFrameCodeCells = .value, encodes: GroundTruthRecordFrameCodeEncodes = .value) {
        self.cells = cells
        self.encodes = encodes
    }
}

public enum GroundTruthRecordFrameCodeCells: Int, Codable, CaseIterable, Hashable, Sendable {
    case value = 16
}

public enum GroundTruthRecordFrameCodeEncodes: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "frameIndex"
}

public enum GroundTruthRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.groundTruth"
}

public struct GroundTruthRecordMedia: Codable, Equatable, Sendable {
    public var path: String
    public var container: GroundTruthRecordMediaContainer

    public init(path: String, container: GroundTruthRecordMediaContainer) {
        self.path = path
        self.container = container
    }
}

public enum GroundTruthRecordMediaContainer: String, Codable, CaseIterable, Hashable, Sendable {
    case mp4 = "mp4"
    case mov = "mov"
}

public struct GroundTruthRecordRenderer: Codable, Equatable, Sendable {
    public var script: GroundTruthRecordRendererScript
    public var sourceHash: String

    public init(script: GroundTruthRecordRendererScript = .value, sourceHash: String) {
        self.script = script
        self.sourceHash = sourceHash
    }
}

public enum GroundTruthRecordRendererScript: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "scripts/media/render.py"
}

public struct GroundTruthRecordSignature: Codable, Equatable, Sendable {
    public var method: GroundTruthRecordSignatureMethod
    public var columns: Int
    public var rows: Int
    public var minimumMargin: Int
    public var frameCount: Int
    public var decodedFramesSha256: String

    public init(method: GroundTruthRecordSignatureMethod = .value, columns: Int, rows: Int, minimumMargin: Int, frameCount: Int, decodedFramesSha256: String) {
        self.method = method
        self.columns = columns
        self.rows = rows
        self.minimumMargin = minimumMargin
        self.frameCount = frameCount
        self.decodedFramesSha256 = decodedFramesSha256
    }
}

public enum GroundTruthRecordSignatureMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.cellLuma.v1"
}

public enum GroundTruthRecordSplit: String, Codable, CaseIterable, Hashable, Sendable {
    case tuning = "tuning"
    case heldOut = "heldOut"
}

public struct GroundTruthRecordVideo: Codable, Equatable, Sendable {
    public var codec: GroundTruthRecordVideoCodec
    public var fourCC: GroundTruthRecordVideoFourCC
    public var bitDepth: GroundTruthRecordVideoBitDepth
    public var codedWidth: Int
    public var codedHeight: Int
    public var rotationDegrees: GroundTruthRecordVideoRotationDegrees
    public var displayWidth: Int
    public var displayHeight: Int
    public var orientation: GroundTruthRecordVideoOrientation
    public var frameRate: RecordedFrameRate
    public var variableFrameRate: Bool
    public var frameCount: Int
    public var duration: GroundTruthRationalTime
    public var hdr: ContractNullable<GroundTruthRecordVideoHdr>
    public var supported: Bool

    public init(codec: GroundTruthRecordVideoCodec, fourCC: GroundTruthRecordVideoFourCC, bitDepth: GroundTruthRecordVideoBitDepth, codedWidth: Int, codedHeight: Int, rotationDegrees: GroundTruthRecordVideoRotationDegrees, displayWidth: Int, displayHeight: Int, orientation: GroundTruthRecordVideoOrientation, frameRate: RecordedFrameRate, variableFrameRate: Bool, frameCount: Int, duration: GroundTruthRationalTime, hdr: ContractNullable<GroundTruthRecordVideoHdr>, supported: Bool) {
        self.codec = codec
        self.fourCC = fourCC
        self.bitDepth = bitDepth
        self.codedWidth = codedWidth
        self.codedHeight = codedHeight
        self.rotationDegrees = rotationDegrees
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.orientation = orientation
        self.frameRate = frameRate
        self.variableFrameRate = variableFrameRate
        self.frameCount = frameCount
        self.duration = duration
        self.hdr = hdr
        self.supported = supported
    }
}

public enum GroundTruthRecordVideoBitDepth: Int, Codable, CaseIterable, Hashable, Sendable {
    case value8 = 8
    case value10 = 10
}

public enum GroundTruthRecordVideoCodec: String, Codable, CaseIterable, Hashable, Sendable {
    case h264 = "h264"
    case hevc = "hevc"
    case ffv1 = "ffv1"
}

public enum GroundTruthRecordVideoFourCC: String, Codable, CaseIterable, Hashable, Sendable {
    case avc1 = "avc1"
    case hvc1 = "hvc1"
    case fFV1 = "FFV1"
}

public struct GroundTruthRecordVideoHdr: Codable, Equatable, Sendable {
    public var transfer: GroundTruthRecordVideoHdrTransfer
    public var primaries: GroundTruthRecordVideoHdrPrimaries
    public var matrix: GroundTruthRecordVideoHdrMatrix

    public init(transfer: GroundTruthRecordVideoHdrTransfer, primaries: GroundTruthRecordVideoHdrPrimaries = .value, matrix: GroundTruthRecordVideoHdrMatrix = .value) {
        self.transfer = transfer
        self.primaries = primaries
        self.matrix = matrix
    }
}

public enum GroundTruthRecordVideoHdrMatrix: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "bt2020nc"
}

public enum GroundTruthRecordVideoHdrPrimaries: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "bt2020"
}

public enum GroundTruthRecordVideoHdrTransfer: String, Codable, CaseIterable, Hashable, Sendable {
    case hlg = "hlg"
    case pq = "pq"
}

public enum GroundTruthRecordVideoOrientation: String, Codable, CaseIterable, Hashable, Sendable {
    case landscape = "landscape"
    case portrait = "portrait"
    case square = "square"
}

public enum GroundTruthRecordVideoRotationDegrees: Int, Codable, CaseIterable, Hashable, Sendable {
    case value0 = 0
    case value90 = 90
    case value180 = 180
    case value270 = 270
}

public struct MediaRange: Codable, Equatable, Sendable {
    public var fromMs: Int
    public var toMs: Int

    public init(fromMs: Int, toMs: Int) {
        self.fromMs = fromMs
        self.toMs = toMs
    }
}

public struct PracticeDrillLog: Codable, Equatable, Sendable {
    public var id: String
    public var itemId: String
    public var drillTitle: String?
    public var startedAt: String
    public var finishedAt: String?
    public var activeSeconds: Int?
    public var status: PracticeDrillLogStatus
    public var setsPlanned: Int?
    public var setsCompleted: Int
    public var tally: PracticeDrillLogTally?
    public var recordedSessionId: String?
    public var goalIds: [String]?
    public var sample: Bool?

    public init(id: String, itemId: String, drillTitle: String? = nil, startedAt: String, finishedAt: String? = nil, activeSeconds: Int? = nil, status: PracticeDrillLogStatus, setsPlanned: Int? = nil, setsCompleted: Int, tally: PracticeDrillLogTally? = nil, recordedSessionId: String? = nil, goalIds: [String]? = nil, sample: Bool? = nil) {
        self.id = id
        self.itemId = itemId
        self.drillTitle = drillTitle
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.activeSeconds = activeSeconds
        self.status = status
        self.setsPlanned = setsPlanned
        self.setsCompleted = setsCompleted
        self.tally = tally
        self.recordedSessionId = recordedSessionId
        self.goalIds = goalIds
        self.sample = sample
    }
}

public enum PracticeDrillLogStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case inProgress = "inProgress"
    case finished = "finished"
    case abandoned = "abandoned"
}

public struct PracticeDrillLogTally: Codable, Equatable, Sendable {
    public var `in`: Int
    public var out: Int

    public init(`in`: Int, out: Int) {
        self.`in` = `in`
        self.out = out
    }
}

public struct PracticeGoal: Codable, Equatable, Sendable {
    public var id: String
    public var stat: String
    public var target: Int
    public var sessionKind: PracticeGoalSessionKind
    public var achievedAt: String?
    public var window: PracticeGoalWindow?
    public var targetDate: String?
    public var createdAt: String?

    public init(id: String, stat: String, target: Int, sessionKind: PracticeGoalSessionKind, achievedAt: String? = nil, window: PracticeGoalWindow? = nil, targetDate: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.stat = stat
        self.target = target
        self.sessionKind = sessionKind
        self.achievedAt = achievedAt
        self.window = window
        self.targetDate = targetDate
        self.createdAt = createdAt
    }
}

public enum PracticeGoalSessionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case match = "match"
    case tiebreakOnly = "tiebreakOnly"
    case practiceSet = "practiceSet"
    case servePractice = "servePractice"
    case strokePractice = "strokePractice"
    case rally = "rally"
    case lesson = "lesson"
    case drill = "drill"
}

public enum PracticeGoalWindow: String, Codable, CaseIterable, Hashable, Sendable {
    case fourWeeks = "fourWeeks"
    case threeMonths = "threeMonths"
    case year = "year"
}

public struct PracticeItem: Codable, Equatable, Sendable {
    public var id: String
    public var focus: String
    public var drill: PracticeItemDrill
    public var origin: PracticeItemOrigin
    public var evidence: [PracticeItemEvidenceItem]
    public var status: PracticeItemStatus
    public var userEdited: Bool?

    public init(id: String, focus: String, drill: PracticeItemDrill, origin: PracticeItemOrigin, evidence: [PracticeItemEvidenceItem], status: PracticeItemStatus, userEdited: Bool? = nil) {
        self.id = id
        self.focus = focus
        self.drill = drill
        self.origin = origin
        self.evidence = evidence
        self.status = status
        self.userEdited = userEdited
    }
}

public struct PracticeItemDrill: Codable, Equatable, Sendable {
    public var title: String
    public var instructions: String
    public var durationMinutes: Int?
    public var sets: Int?
    public var reps: Int?

    public init(title: String, instructions: String, durationMinutes: Int? = nil, sets: Int? = nil, reps: Int? = nil) {
        self.title = title
        self.instructions = instructions
        self.durationMinutes = durationMinutes
        self.sets = sets
        self.reps = reps
    }
}

public struct PracticeItemEvidenceItem: Codable, Equatable, Sendable {
    public var sessionId: String
    public var stat: String
    public var side: Side?
    public var value: RateRatio
    public var text: String?
    public var pointIds: [String]?
    public var provenance: RecordProvenance
    public var availability: PracticeItemEvidenceItemAvailability

    public init(sessionId: String, stat: String, side: Side? = nil, value: RateRatio, text: String? = nil, pointIds: [String]? = nil, provenance: RecordProvenance, availability: PracticeItemEvidenceItemAvailability) {
        self.sessionId = sessionId
        self.stat = stat
        self.side = side
        self.value = value
        self.text = text
        self.pointIds = pointIds
        self.provenance = provenance
        self.availability = availability
    }
}

public enum PracticeItemEvidenceItemAvailability: String, Codable, CaseIterable, Hashable, Sendable {
    case available = "available"
    case videoUnavailable = "videoUnavailable"
    case sessionDeleted = "sessionDeleted"
}

public enum PracticeItemOrigin: Codable, Equatable, Sendable {
    case rule(PracticeItemOriginRule)
    case user(PracticeItemOriginUser)

    private enum CodingKeys: String, CodingKey { case kind }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .kind)
        switch tag {
        case "rule": self = .rule(try PracticeItemOriginRule(from: decoder))
        case "user": self = .user(try PracticeItemOriginUser(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown PracticeItemOrigin discriminator")
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .rule(let value): try value.encode(to: encoder)
        case .user(let value): try value.encode(to: encoder)
        }
    }
}

public struct PracticeItemOriginRule: Codable, Equatable, Sendable {
    public var kind: PracticeItemOriginRuleKind
    public var ruleId: String
    public var ruleVersion: String
    public var condition: String

    public init(kind: PracticeItemOriginRuleKind = .value, ruleId: String, ruleVersion: String, condition: String) {
        self.kind = kind
        self.ruleId = ruleId
        self.ruleVersion = ruleVersion
        self.condition = condition
    }
}

public enum PracticeItemOriginRuleKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "rule"
}

public struct PracticeItemOriginUser: Codable, Equatable, Sendable {
    public var kind: PracticeItemOriginUserKind

    public init(kind: PracticeItemOriginUserKind = .value) {
        self.kind = kind
    }
}

public enum PracticeItemOriginUserKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "user"
}

public enum PracticeItemStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case planned = "planned"
    case done = "done"
    case skipped = "skipped"
}

public struct PracticePlanDocument: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: PracticePlanDocumentKind
    public var id: String
    public var createdAt: String
    public var updatedAt: String
    public var title: String
    public var label: PracticePlanDocumentLabel
    public var sample: Bool?
    public var playerId: String?
    public var basedOnSessions: [String]?
    public var items: [PracticeItem]
    public var goals: [PracticeGoal]?
    public var drillLogs: [PracticeDrillLog]?

    public init(schemaVersion: SchemaVersion = .v1_1, kind: PracticePlanDocumentKind = .value, id: String, createdAt: String, updatedAt: String, title: String, label: PracticePlanDocumentLabel = .value, sample: Bool? = nil, playerId: String? = nil, basedOnSessions: [String]? = nil, items: [PracticeItem], goals: [PracticeGoal]? = nil, drillLogs: [PracticeDrillLog]? = nil) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.label = label
        self.sample = sample
        self.playerId = playerId
        self.basedOnSessions = basedOnSessions
        self.items = items
        self.goals = goals
        self.drillLogs = drillLogs
    }
}

public enum PracticePlanDocumentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.practicePlan"
}

public enum PracticePlanDocumentLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "Suggested practice"
}

public struct RateRatio: Codable, Equatable, Sendable {
    public var n: Int
    public var d: Int
    public var pct: ContractNullable<Int>
    public var display: String

    public init(n: Int, d: Int, pct: ContractNullable<Int>, display: String) {
        self.n = n
        self.d = d
        self.pct = pct
        self.display = display
    }
}

public struct RecordFileReference: Codable, Equatable, Sendable {
    public var path: String
    public var mimeType: String?
    public var bytes: Int?
    public var sha256: String?
    public var md5: String?

    public init(path: String, mimeType: String? = nil, bytes: Int? = nil, sha256: String? = nil, md5: String? = nil) {
        self.path = path
        self.mimeType = mimeType
        self.bytes = bytes
        self.sha256 = sha256
        self.md5 = md5
    }
}

public struct RecordProvenance: Codable, Equatable, Sendable {
    public var status: Provenance
    public var source: String
    public var capabilityId: String?
    public var capabilityVersion: String?
    public var confidence: Decimal?
    public var calibrationId: String?
    public var denominator: Int?
    public var computedAt: String?
    public var sample: Bool?

    public init(status: Provenance, source: String, capabilityId: String? = nil, capabilityVersion: String? = nil, confidence: Decimal? = nil, calibrationId: String? = nil, denominator: Int? = nil, computedAt: String? = nil, sample: Bool? = nil) {
        self.status = status
        self.source = source
        self.capabilityId = capabilityId
        self.capabilityVersion = capabilityVersion
        self.confidence = confidence
        self.calibrationId = calibrationId
        self.denominator = denominator
        self.computedAt = computedAt
        self.sample = sample
    }
}

public struct RecordedFrameRate: Codable, Equatable, Sendable {
    public var num: Int
    public var den: Int

    public init(num: Int, den: Int) {
        self.num = num
        self.den = den
    }
}

public struct SampleMediaManifest: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: SampleMediaManifestKind
    public var updatedAt: String
    public var sample: SampleMediaManifestSample
    public var media: [SampleMediaMedia]

    public init(schemaVersion: SchemaVersion = .v1, kind: SampleMediaManifestKind = .value, updatedAt: String, sample: SampleMediaManifestSample, media: [SampleMediaMedia]) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.updatedAt = updatedAt
        self.sample = sample
        self.media = media
    }
}

public enum SampleMediaManifestKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.sampleMediaManifest"
}

public struct SampleMediaManifestSample: Codable, Equatable, Sendable {
    public var label: SampleMediaManifestSampleLabel
    public var synthetic: Bool

    public init(label: SampleMediaManifestSampleLabel = .value, synthetic: Bool = true) {
        self.label = label
        self.synthetic = synthetic
    }
}

public enum SampleMediaManifestSampleLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "Sample"
}

public struct SampleMediaMedia: Codable, Equatable, Sendable {
    public var mediaId: String
    public var role: SampleMediaMediaRole
    public var sessionId: String
    public var sessionDate: String
    public var sessionKind: SampleMediaMediaSessionKind
    public var fileName: String
    public var durationMs: Int
    public var frameRate: RecordedFrameRate
    public var width: Int
    public var height: Int
    public var hasAudio: Bool
    public var angle: SampleMediaMediaAngle
    public var coversSessionMs: MediaRange
    public var label: SampleMediaMediaLabel
    public var purpose: String?

    public init(mediaId: String, role: SampleMediaMediaRole, sessionId: String, sessionDate: String, sessionKind: SampleMediaMediaSessionKind, fileName: String, durationMs: Int, frameRate: RecordedFrameRate, width: Int, height: Int, hasAudio: Bool, angle: SampleMediaMediaAngle, coversSessionMs: MediaRange, label: SampleMediaMediaLabel = .value, purpose: String? = nil) {
        self.mediaId = mediaId
        self.role = role
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.sessionKind = sessionKind
        self.fileName = fileName
        self.durationMs = durationMs
        self.frameRate = frameRate
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
        self.angle = angle
        self.coversSessionMs = coversSessionMs
        self.label = label
        self.purpose = purpose
    }
}

public enum SampleMediaMediaAngle: String, Codable, CaseIterable, Hashable, Sendable {
    case behindBaseline = "behindBaseline"
    case sideOn = "sideOn"
}

public enum SampleMediaMediaLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "Sample video (synthetic)"
}

public enum SampleMediaMediaRole: String, Codable, CaseIterable, Hashable, Sendable {
    case sessionVideo = "sessionVideo"
    case practiceClip = "practiceClip"
}

public enum SampleMediaMediaSessionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case match = "match"
    case servePractice = "servePractice"
    case strokePractice = "strokePractice"
}

public struct SessionAnalysis: Codable, Equatable, Sendable {
    public var state: SessionAnalysisState
    public var reason: String?
    public var excludedSide: SessionAnalysisExcludedSide?
    public var runs: [SessionAnalysisRunsItem]

    public init(state: SessionAnalysisState, reason: String? = nil, excludedSide: SessionAnalysisExcludedSide? = nil, runs: [SessionAnalysisRunsItem]) {
        self.state = state
        self.reason = reason
        self.excludedSide = excludedSide
        self.runs = runs
    }
}

public enum SessionAnalysisExcludedSide: String, Codable, CaseIterable, Hashable, Sendable {
    case left = "left"
    case right = "right"
}

public struct SessionAnalysisRunsItem: Codable, Equatable, Sendable {
    public var capabilityId: String
    public var capabilityVersion: String
    public var status: SessionAnalysisRunsItemStatus
    public var startedAt: String?
    public var finishedAt: String?
    public var error: String?

    public init(capabilityId: String, capabilityVersion: String, status: SessionAnalysisRunsItemStatus, startedAt: String? = nil, finishedAt: String? = nil, error: String? = nil) {
        self.capabilityId = capabilityId
        self.capabilityVersion = capabilityVersion
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.error = error
    }
}

public enum SessionAnalysisRunsItemStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case queued = "queued"
    case running = "running"
    case done = "done"
    case failed = "failed"
    case skipped = "skipped"
}

public enum SessionAnalysisState: String, Codable, CaseIterable, Hashable, Sendable {
    case notRequested = "notRequested"
    case queued = "queued"
    case running = "running"
    case paused = "paused"
    case done = "done"
    case partial = "partial"
    case failed = "failed"
    case unavailable = "unavailable"
}

public struct SessionAnnotation: Codable, Equatable, Sendable {
    public var id: String
    public var kind: SessionAnnotationKind
    public var fromMs: Int
    public var toMs: Int
    public var points: [CourtPoint2D]
    public var text: String?
    public var colorRole: SessionAnnotationColorRole?
    public var comparisonId: String?
    public var provenance: RecordProvenance

    public init(id: String, kind: SessionAnnotationKind, fromMs: Int, toMs: Int, points: [CourtPoint2D], text: String? = nil, colorRole: SessionAnnotationColorRole? = nil, comparisonId: String? = nil, provenance: RecordProvenance) {
        self.id = id
        self.kind = kind
        self.fromMs = fromMs
        self.toMs = toMs
        self.points = points
        self.text = text
        self.colorRole = colorRole
        self.comparisonId = comparisonId
        self.provenance = provenance
    }
}

public enum SessionAnnotationColorRole: String, Codable, CaseIterable, Hashable, Sendable {
    case accent = "accent"
    case clay = "clay"
    case ivory = "ivory"
    case charcoal = "charcoal"
}

public enum SessionAnnotationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case line = "line"
    case arrow = "arrow"
    case circle = "circle"
    case angle = "angle"
    case freehand = "freehand"
    case text = "text"
    case spotlight = "spotlight"
    case stopwatch = "stopwatch"
}

public struct SessionArchiveState: Codable, Equatable, Sendable {
    public var state: SessionArchiveStateState
    public var copy: SessionArchiveStateCopy?
    public var restoredAt: String?
    public var provider: SessionArchiveStateProvider?
    public var manifest: String?
    public var backedUpAt: String?
    public var lastError: String?

    public init(state: SessionArchiveStateState, copy: SessionArchiveStateCopy? = nil, restoredAt: String? = nil, provider: SessionArchiveStateProvider? = nil, manifest: String? = nil, backedUpAt: String? = nil, lastError: String? = nil) {
        self.state = state
        self.copy = copy
        self.restoredAt = restoredAt
        self.provider = provider
        self.manifest = manifest
        self.backedUpAt = backedUpAt
        self.lastError = lastError
    }
}

public enum SessionArchiveStateCopy: String, Codable, CaseIterable, Hashable, Sendable {
    case original = "original"
    case rallyOnlyCopy = "rallyOnlyCopy"
}

public enum SessionArchiveStateProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "googleDrive"
}

public enum SessionArchiveStateState: String, Codable, CaseIterable, Hashable, Sendable {
    case localOnly = "localOnly"
    case awaitingSetup = "awaitingSetup"
    case queued = "queued"
    case waitingForWiFi = "waitingForWiFi"
    case hashing = "hashing"
    case uploading = "uploading"
    case verifying = "verifying"
    case backedUp = "backedUp"
    case failed = "failed"
    case needsReconnect = "needsReconnect"
    case quotaBlocked = "quotaBlocked"
}

public struct SessionCalibration: Codable, Equatable, Sendable {
    public var id: String
    public var method: SessionCalibrationMethod
    public var frameMs: Int
    public var imagePoints: [CourtPoint2D]
    public var courtPoints: [CourtPoint2D]
    public var homography: [Decimal]?
    public var residualPx: Decimal?
    public var status: SessionCalibrationStatus
    public var staleFromMs: Int?
    public var camera: SessionCalibrationCamera?
    public var provenance: RecordProvenance

    public init(id: String, method: SessionCalibrationMethod, frameMs: Int, imagePoints: [CourtPoint2D], courtPoints: [CourtPoint2D], homography: [Decimal]? = nil, residualPx: Decimal? = nil, status: SessionCalibrationStatus, staleFromMs: Int? = nil, camera: SessionCalibrationCamera? = nil, provenance: RecordProvenance) {
        self.id = id
        self.method = method
        self.frameMs = frameMs
        self.imagePoints = imagePoints
        self.courtPoints = courtPoints
        self.homography = homography
        self.residualPx = residualPx
        self.status = status
        self.staleFromMs = staleFromMs
        self.camera = camera
        self.provenance = provenance
    }
}

public struct SessionCalibrationCamera: Codable, Equatable, Sendable {
    public var lens: SessionCalibrationCameraLens
    public var width: Int
    public var height: Int
    public var frameRate: RecordedFrameRate?
    public var zoomFactor: String

    public init(lens: SessionCalibrationCameraLens, width: Int, height: Int, frameRate: RecordedFrameRate? = nil, zoomFactor: String) {
        self.lens = lens
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.zoomFactor = zoomFactor
    }
}

public enum SessionCalibrationCameraLens: String, Codable, CaseIterable, Hashable, Sendable {
    case ultraWide = "ultraWide"
    case wide = "wide"
    case telephoto = "telephoto"
    case front = "front"
    case external = "external"
    case unknown = "unknown"
}

public enum SessionCalibrationMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "fourTap"
}

public enum SessionCalibrationStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case valid = "valid"
    case needsReview = "needsReview"
    case invalid = "invalid"
    case cameraMoved = "cameraMoved"
}

public struct SessionCaptureEvent: Codable, Equatable, Sendable {
    public var tMs: Int
    public var kind: SessionCaptureEventKind
    public var thermalState: SessionCaptureEventThermalState?
    public var frameRate: RecordedFrameRate?

    public init(tMs: Int, kind: SessionCaptureEventKind, thermalState: SessionCaptureEventThermalState? = nil, frameRate: RecordedFrameRate? = nil) {
        self.tMs = tMs
        self.kind = kind
        self.thermalState = thermalState
        self.frameRate = frameRate
    }
}

public enum SessionCaptureEventKind: String, Codable, CaseIterable, Hashable, Sendable {
    case thermalState = "thermalState"
    case frameRateChange = "frameRateChange"
    case courtModeOn = "courtModeOn"
    case courtModeOff = "courtModeOff"
    case lowStorageStop = "lowStorageStop"
    case lowBatteryStop = "lowBatteryStop"
}

public enum SessionCaptureEventThermalState: String, Codable, CaseIterable, Hashable, Sendable {
    case nominal = "nominal"
    case fair = "fair"
    case serious = "serious"
    case critical = "critical"
    case shutdown = "shutdown"
}

public struct SessionCheckpointEvent: Codable, Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var type: SessionCheckpointEventType
    public var setIndex: Int
    public var games: SideCounts
    public var supersedes: String?
    public var insertBefore: String?
    public var tMs: Int?
    public var at: String?
    public var source: String?

    public init(id: String, seq: Int, type: SessionCheckpointEventType = .value, setIndex: Int, games: SideCounts, supersedes: String? = nil, insertBefore: String? = nil, tMs: Int? = nil, at: String? = nil, source: String? = nil) {
        self.id = id
        self.seq = seq
        self.type = type
        self.setIndex = setIndex
        self.games = games
        self.supersedes = supersedes
        self.insertBefore = insertBefore
        self.tMs = tMs
        self.at = at
        self.source = source
    }
}

public enum SessionCheckpointEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "checkpoint"
}

public struct SessionComparison: Codable, Equatable, Sendable {
    public var id: String
    public var title: String?
    public var left: SessionComparisonSide
    public var right: SessionComparisonSide
    public var syncedAt: SessionComparisonSyncedAt
    public var createdAt: String
    public var note: String?

    public init(id: String, title: String? = nil, left: SessionComparisonSide, right: SessionComparisonSide, syncedAt: SessionComparisonSyncedAt, createdAt: String, note: String? = nil) {
        self.id = id
        self.title = title
        self.left = left
        self.right = right
        self.syncedAt = syncedAt
        self.createdAt = createdAt
        self.note = note
    }
}

public struct SessionComparisonSide: Codable, Equatable, Sendable {
    public var sessionId: String
    public var syncTimeMs: Int
    public var nudgeFrames: Int?

    public init(sessionId: String, syncTimeMs: Int, nudgeFrames: Int? = nil) {
        self.sessionId = sessionId
        self.syncTimeMs = syncTimeMs
        self.nudgeFrames = nudgeFrames
    }
}

public enum SessionComparisonSyncedAt: String, Codable, CaseIterable, Hashable, Sendable {
    case contact = "contact"
    case custom = "custom"
    case unsynced = "unsynced"
}

public struct SessionConsent: Codable, Equatable, Sendable {
    public var status: SessionConsentStatus
    public var competitionMode: Bool?
    public var note: String?
    public var juniorPlayerIds: [String]?
    public var writtenConsents: [SessionConsentWrittenConsentsItem]?
    public var withdrawnAt: String?

    public init(status: SessionConsentStatus, competitionMode: Bool? = nil, note: String? = nil, juniorPlayerIds: [String]? = nil, writtenConsents: [SessionConsentWrittenConsentsItem]? = nil, withdrawnAt: String? = nil) {
        self.status = status
        self.competitionMode = competitionMode
        self.note = note
        self.juniorPlayerIds = juniorPlayerIds
        self.writtenConsents = writtenConsents
        self.withdrawnAt = withdrawnAt
    }
}

public enum SessionConsentStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case informed = "informed"
    case writtenFormAttached = "writtenFormAttached"
    case notRequired = "notRequired"
    case notRecorded = "notRecorded"
}

public struct SessionConsentWrittenConsentsItem: Codable, Equatable, Sendable {
    public var id: String
    public var attachment: RecordFileReference
    public var coversPlayerIds: [String]?
    public var attachedAt: String

    public init(id: String, attachment: RecordFileReference, coversPlayerIds: [String]? = nil, attachedAt: String) {
        self.id = id
        self.attachment = attachment
        self.coversPlayerIds = coversPlayerIds
        self.attachedAt = attachedAt
    }
}

public struct SessionDerivedValue: Codable, Equatable, Sendable {
    public var id: String
    public var key: String
    public var value: ScalarValue
    public var unit: String?
    public var label: String?
    public var scope: SessionDerivedValueScope?
    public var provenance: SessionDerivedValueProvenance
    public var range: SessionDerivedValueRange?

    public init(id: String, key: String, value: ScalarValue, unit: String? = nil, label: String? = nil, scope: SessionDerivedValueScope? = nil, provenance: SessionDerivedValueProvenance, range: SessionDerivedValueRange? = nil) {
        self.id = id
        self.key = key
        self.value = value
        self.unit = unit
        self.label = label
        self.scope = scope
        self.provenance = provenance
        self.range = range
    }
}

public struct SessionDerivedValueProvenance: Codable, Equatable, Sendable {
    public var status: Provenance
    public var source: String
    public var capabilityId: String?
    public var capabilityVersion: String?
    public var confidence: Decimal?
    public var calibrationId: String?
    public var denominator: Int?
    public var computedAt: String?
    public var sample: Bool?

    public init(status: Provenance, source: String, capabilityId: String? = nil, capabilityVersion: String? = nil, confidence: Decimal? = nil, calibrationId: String? = nil, denominator: Int? = nil, computedAt: String? = nil, sample: Bool? = nil) {
        self.status = status
        self.source = source
        self.capabilityId = capabilityId
        self.capabilityVersion = capabilityVersion
        self.confidence = confidence
        self.calibrationId = calibrationId
        self.denominator = denominator
        self.computedAt = computedAt
        self.sample = sample
    }
}

public struct SessionDerivedValueRange: Codable, Equatable, Sendable {
    public var low: Decimal
    public var high: Decimal
    public var pct: Int?

    public init(low: Decimal, high: Decimal, pct: Int? = nil) {
        self.low = low
        self.high = high
        self.pct = pct
    }
}

public struct SessionDerivedValueScope: Codable, Equatable, Sendable {
    public var pointId: String?
    public var shotId: String?
    public var serveMarkId: String?
    public var fromMs: Int?
    public var toMs: Int?

    public init(pointId: String? = nil, shotId: String? = nil, serveMarkId: String? = nil, fromMs: Int? = nil, toMs: Int? = nil) {
        self.pointId = pointId
        self.shotId = shotId
        self.serveMarkId = serveMarkId
        self.fromMs = fromMs
        self.toMs = toMs
    }
}

public struct SessionDocument: Codable, Equatable, Sendable {
    public var schemaVersion: SchemaVersion
    public var kind: SessionDocumentKind
    public var id: String
    public var sport: SessionDocumentSport
    public var createdAt: String
    public var updatedAt: String
    public var title: String
    public var sample: SessionSampleInfo?
    public var sessionKind: SessionDocumentSessionKind
    public var capturePurpose: SessionDocumentCapturePurpose?
    public var players: [SessionPlayer]
    public var sides: SessionSides?
    public var match: SessionMatch?
    public var recording: SessionRecording
    public var marks: [SessionMark]?
    public var shots: [SessionShot]?
    public var calibrations: [SessionCalibration]?
    public var annotations: [SessionAnnotation]?
    public var voiceNotes: [SessionVoiceNote]?
    public var comparisons: [SessionComparison]?
    public var derivedValues: [SessionDerivedValue]?
    public var analysis: SessionAnalysis?
    public var review: SessionReview?
    public var archive: SessionArchiveState
    public var storage: SessionStoragePolicy
    public var equipmentUse: [SessionEquipmentUse]?
    public var consent: SessionConsent?
    public var notes: String?
    public var rallyPlayback: SessionRallyPlayback?
    public var serveMarks: [SessionServeMark]?
    public var swings: [SessionSwing]?
    public var exports: [SessionExportRecord]?
    public var original: SessionOriginalState?

    public init(schemaVersion: SchemaVersion = .v1_1, kind: SessionDocumentKind = .value, id: String, sport: SessionDocumentSport, createdAt: String, updatedAt: String, title: String, sample: SessionSampleInfo? = nil, sessionKind: SessionDocumentSessionKind, capturePurpose: SessionDocumentCapturePurpose? = nil, players: [SessionPlayer], sides: SessionSides? = nil, match: SessionMatch? = nil, recording: SessionRecording, marks: [SessionMark]? = nil, shots: [SessionShot]? = nil, calibrations: [SessionCalibration]? = nil, annotations: [SessionAnnotation]? = nil, voiceNotes: [SessionVoiceNote]? = nil, comparisons: [SessionComparison]? = nil, derivedValues: [SessionDerivedValue]? = nil, analysis: SessionAnalysis? = nil, review: SessionReview? = nil, archive: SessionArchiveState, storage: SessionStoragePolicy, equipmentUse: [SessionEquipmentUse]? = nil, consent: SessionConsent? = nil, notes: String? = nil, rallyPlayback: SessionRallyPlayback? = nil, serveMarks: [SessionServeMark]? = nil, swings: [SessionSwing]? = nil, exports: [SessionExportRecord]? = nil, original: SessionOriginalState? = nil) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.id = id
        self.sport = sport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.sample = sample
        self.sessionKind = sessionKind
        self.capturePurpose = capturePurpose
        self.players = players
        self.sides = sides
        self.match = match
        self.recording = recording
        self.marks = marks
        self.shots = shots
        self.calibrations = calibrations
        self.annotations = annotations
        self.voiceNotes = voiceNotes
        self.comparisons = comparisons
        self.derivedValues = derivedValues
        self.analysis = analysis
        self.review = review
        self.archive = archive
        self.storage = storage
        self.equipmentUse = equipmentUse
        self.consent = consent
        self.notes = notes
        self.rallyPlayback = rallyPlayback
        self.serveMarks = serveMarks
        self.swings = swings
        self.exports = exports
        self.original = original
    }
}

public enum SessionDocumentCapturePurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case match = "match"
    case sideOnTechnique = "sideOnTechnique"
}

public enum SessionDocumentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "jovra.session"
}

public enum SessionDocumentSessionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case match = "match"
    case tiebreakOnly = "tiebreakOnly"
    case practiceSet = "practiceSet"
    case servePractice = "servePractice"
    case strokePractice = "strokePractice"
    case rally = "rally"
    case lesson = "lesson"
    case drill = "drill"
}

public enum SessionDocumentSport: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "tennis"
}

public struct SessionDoublesOrderEvent: Codable, Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var type: SessionDoublesOrderEventType
    public var setIndex: Int
    public var firstServer: String
    public var secondServer: String
    public var deuceReceivers: SessionDoublesOrderEventDeuceReceivers
    public var at: String?
    public var source: String?

    public init(id: String, seq: Int, type: SessionDoublesOrderEventType = .value, setIndex: Int, firstServer: String, secondServer: String, deuceReceivers: SessionDoublesOrderEventDeuceReceivers, at: String? = nil, source: String? = nil) {
        self.id = id
        self.seq = seq
        self.type = type
        self.setIndex = setIndex
        self.firstServer = firstServer
        self.secondServer = secondServer
        self.deuceReceivers = deuceReceivers
        self.at = at
        self.source = source
    }
}

public struct SessionDoublesOrderEventDeuceReceivers: Codable, Equatable, Sendable {
    public var A: String
    public var B: String

    public init(A: String, B: String) {
        self.A = A
        self.B = B
    }
}

public enum SessionDoublesOrderEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "doublesOrder"
}

public struct SessionEndEvent: Codable, Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var type: SessionEndEventType
    public var player: String
    public var reason: SessionEndEventReason?
    public var supersedes: String?
    public var tMs: Int?
    public var at: String?
    public var source: String?

    public init(id: String, seq: Int, type: SessionEndEventType, player: String, reason: SessionEndEventReason? = nil, supersedes: String? = nil, tMs: Int? = nil, at: String? = nil, source: String? = nil) {
        self.id = id
        self.seq = seq
        self.type = type
        self.player = player
        self.reason = reason
        self.supersedes = supersedes
        self.tMs = tMs
        self.at = at
        self.source = source
    }
}

public enum SessionEndEventReason: String, Codable, CaseIterable, Hashable, Sendable {
    case injury = "injury"
    case illness = "illness"
    case personalCircumstances = "personalCircumstances"
    case pointPenaltySystem = "pointPenaltySystem"
    case late = "late"
    case noShow = "noShow"
    case other = "other"
}

public enum SessionEndEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case retirement = "retirement"
    case `default` = "default"
    case walkover = "walkover"
}

public struct SessionEquipmentUse: Codable, Equatable, Sendable {
    public var id: String
    public var playerId: String
    public var racketId: String
    public var stringJobId: String?
    public var setupLabelSnapshot: String
    public var activeMinutes: Int?
    public var fromMs: Int?
    public var toMs: Int?
    public var source: SessionEquipmentUseSource

    public init(id: String, playerId: String, racketId: String, stringJobId: String? = nil, setupLabelSnapshot: String, activeMinutes: Int? = nil, fromMs: Int? = nil, toMs: Int? = nil, source: SessionEquipmentUseSource) {
        self.id = id
        self.playerId = playerId
        self.racketId = racketId
        self.stringJobId = stringJobId
        self.setupLabelSnapshot = setupLabelSnapshot
        self.activeMinutes = activeMinutes
        self.fromMs = fromMs
        self.toMs = toMs
        self.source = source
    }
}

public enum SessionEquipmentUseSource: String, Codable, CaseIterable, Hashable, Sendable {
    case recordedVideo = "recordedVideo"
    case importedVideo = "importedVideo"
    case manualLog = "manualLog"
}

public struct SessionExportRecord: Codable, Equatable, Sendable {
    public var id: String
    public var kind: SessionExportRecordKind
    public var createdAt: String
    public var eventLogVersion: Int
    public var includesAudio: Bool
    public var facesBlurred: Bool?
    public var rallyOnly: Bool?
    public var range: MediaRange?
    public var pointIds: [String]?
    public var destination: SessionExportRecordDestination?
    public var file: RecordFileReference?
    public var status: SessionExportRecordStatus?
    public var failureReason: String?

    public init(id: String, kind: SessionExportRecordKind, createdAt: String, eventLogVersion: Int, includesAudio: Bool, facesBlurred: Bool? = nil, rallyOnly: Bool? = nil, range: MediaRange? = nil, pointIds: [String]? = nil, destination: SessionExportRecordDestination? = nil, file: RecordFileReference? = nil, status: SessionExportRecordStatus? = nil, failureReason: String? = nil) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.eventLogVersion = eventLogVersion
        self.includesAudio = includesAudio
        self.facesBlurred = facesBlurred
        self.rallyOnly = rallyOnly
        self.range = range
        self.pointIds = pointIds
        self.destination = destination
        self.file = file
        self.status = status
        self.failureReason = failureReason
    }
}

public enum SessionExportRecordDestination: String, Codable, CaseIterable, Hashable, Sendable {
    case photos = "photos"
    case files = "files"
    case share = "share"
    case app = "app"
}

public enum SessionExportRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case clip = "clip"
    case condensedMatch = "condensedMatch"
    case highlightReel = "highlightReel"
    case sharePack = "sharePack"
    case sessionData = "sessionData"
    case original = "original"
}

public enum SessionExportRecordStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case inProgress = "inProgress"
    case done = "done"
    case failed = "failed"
    case cancelled = "cancelled"
}

public struct SessionGap: Codable, Equatable, Sendable {
    public var startMs: Int
    public var endMs: Int
    public var reason: SessionGapReason

    public init(startMs: Int, endMs: Int, reason: SessionGapReason) {
        self.startMs = startMs
        self.endMs = endMs
        self.reason = reason
    }
}

public enum SessionGapReason: String, Codable, CaseIterable, Hashable, Sendable {
    case interruption = "interruption"
    case thermal = "thermal"
    case backgrounded = "backgrounded"
    case lowStorage = "lowStorage"
    case cameraError = "cameraError"
    case userPaused = "userPaused"
    case other = "other"
}

public struct SessionKeyMoment: Codable, Equatable, Sendable {
    public var name: SessionKeyMomentName
    public var time: MediaTime
    public var imagePoint: CourtPoint2D?
    public var provenance: RecordProvenance

    public init(name: SessionKeyMomentName, time: MediaTime, imagePoint: CourtPoint2D? = nil, provenance: RecordProvenance) {
        self.name = name
        self.time = time
        self.imagePoint = imagePoint
        self.provenance = provenance
    }
}

public enum SessionKeyMomentName: String, Codable, CaseIterable, Hashable, Sendable {
    case tossRelease = "tossRelease"
    case tossPeak = "tossPeak"
    case trophy = "trophy"
    case racketDrop = "racketDrop"
    case contact = "contact"
    case landing = "landing"
    case ready = "ready"
    case unitTurn = "unitTurn"
    case backswing = "backswing"
    case forwardSwing = "forwardSwing"
    case followThrough = "followThrough"
    case finish = "finish"
}

public enum SessionLogEvent: Codable, Equatable, Sendable {
    case point(SessionPointEvent)
    case void(SessionVoidEvent)
    case doublesOrder(SessionDoublesOrderEvent)
    case checkpoint(SessionCheckpointEvent)
    case penalty(SessionPenaltyEvent)
    case retirement(SessionEndEvent)
    case rallyLet(SessionRallyLetEvent)

    private enum CodingKeys: String, CodingKey { case type }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .type)
        switch tag {
        case "point": self = .point(try SessionPointEvent(from: decoder))
        case "void": self = .void(try SessionVoidEvent(from: decoder))
        case "doublesOrder": self = .doublesOrder(try SessionDoublesOrderEvent(from: decoder))
        case "checkpoint": self = .checkpoint(try SessionCheckpointEvent(from: decoder))
        case "penalty": self = .penalty(try SessionPenaltyEvent(from: decoder))
        case "retirement", "default", "walkover": self = .retirement(try SessionEndEvent(from: decoder))
        case "rallyLet": self = .rallyLet(try SessionRallyLetEvent(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown SessionLogEvent discriminator")
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .point(let value): try value.encode(to: encoder)
        case .void(let value): try value.encode(to: encoder)
        case .doublesOrder(let value): try value.encode(to: encoder)
        case .checkpoint(let value): try value.encode(to: encoder)
        case .penalty(let value): try value.encode(to: encoder)
        case .retirement(let value): try value.encode(to: encoder)
        case .rallyLet(let value): try value.encode(to: encoder)
        }
    }
    public var id: String {
        switch self {
        case .point(let value): value.id
        case .void(let value): value.id
        case .doublesOrder(let value): value.id
        case .checkpoint(let value): value.id
        case .penalty(let value): value.id
        case .retirement(let value): value.id
        case .rallyLet(let value): value.id
        }
    }
    public var seq: Int {
        switch self {
        case .point(let value): value.seq
        case .void(let value): value.seq
        case .doublesOrder(let value): value.seq
        case .checkpoint(let value): value.seq
        case .penalty(let value): value.seq
        case .retirement(let value): value.seq
        case .rallyLet(let value): value.seq
        }
    }
    public var typeString: String {
        switch self {
        case .point(let value): value.type.rawValue
        case .void(let value): value.type.rawValue
        case .doublesOrder(let value): value.type.rawValue
        case .checkpoint(let value): value.type.rawValue
        case .penalty(let value): value.type.rawValue
        case .retirement(let value): value.type.rawValue
        case .rallyLet(let value): value.type.rawValue
        }
    }
}

public struct SessionMark: Codable, Equatable, Sendable {
    public var id: String
    public var tMs: Int
    public var kind: SessionMarkKind
    public var note: String?
    public var provenance: RecordProvenance

    public init(id: String, tMs: Int, kind: SessionMarkKind, note: String? = nil, provenance: RecordProvenance) {
        self.id = id
        self.tMs = tMs
        self.kind = kind
        self.note = note
        self.provenance = provenance
    }
}

public enum SessionMarkKind: String, Codable, CaseIterable, Hashable, Sendable {
    case point = "point"
    case note = "note"
    case highlight = "highlight"
    case stringBroke = "stringBroke"
    case cameraMoved = "cameraMoved"
}

public struct SessionMatch: Codable, Equatable, Sendable {
    public var format: SessionMatchFormat
    public var toss: SessionToss
    public var log: [SessionLogEvent]

    public init(format: SessionMatchFormat, toss: SessionToss, log: [SessionLogEvent]) {
        self.format = format
        self.toss = toss
        self.log = log
    }
}

public struct SessionMatchFormat: Codable, Equatable, Sendable {
    public var presetId: SessionMatchFormatPresetId
    public var setsToWin: SessionMatchFormatSetsToWin
    public var gameScoring: SessionMatchFormatGameScoring
    public var set: SessionSetRule
    public var finalSet: SessionSetRule?
    public var lets: SessionMatchFormatLets
    public var ruleStatus: SessionMatchFormatRuleStatus?

    public init(presetId: SessionMatchFormatPresetId, setsToWin: SessionMatchFormatSetsToWin, gameScoring: SessionMatchFormatGameScoring, set: SessionSetRule, finalSet: SessionSetRule? = nil, lets: SessionMatchFormatLets, ruleStatus: SessionMatchFormatRuleStatus? = nil) {
        self.presetId = presetId
        self.setsToWin = setsToWin
        self.gameScoring = gameScoring
        self.set = set
        self.finalSet = finalSet
        self.lets = lets
        self.ruleStatus = ruleStatus
    }
}

public enum SessionMatchFormatGameScoring: String, Codable, CaseIterable, Hashable, Sendable {
    case ad = "ad"
    case noAd = "noAd"
}

public enum SessionMatchFormatLets: String, Codable, CaseIterable, Hashable, Sendable {
    case `let` = "let"
    case noLet = "noLet"
}

public enum SessionMatchFormatPresetId: String, Codable, CaseIterable, Hashable, Sendable {
    case clubBo3 = "club_bo3"
    case ustaMtb = "usta_mtb"
    case noadMtb = "noad_mtb"
    case slamBo5 = "slam_bo5"
    case slamBo3 = "slam_bo3"
    case proSet8 = "pro_set_8"
    case shortSets = "short_sets"
    case fast4 = "fast4"
    case tbOnly7 = "tb_only_7"
    case tbOnly10 = "tb_only_10"
    case bestOf1 = "best_of_1"
    case custom = "custom"
}

public enum SessionMatchFormatRuleStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case observed = "observed"
    case unverified = "unverified"
}

public enum SessionMatchFormatSetsToWin: Int, Codable, CaseIterable, Hashable, Sendable {
    case value1 = 1
    case value2 = 2
    case value3 = 3
}

public struct SessionOriginalState: Codable, Equatable, Sendable {
    public var state: SessionOriginalStateState
    public var reason: String?
    public var updatedAt: String?

    public init(state: SessionOriginalStateState, reason: String? = nil, updatedAt: String? = nil) {
        self.state = state
        self.reason = reason
        self.updatedAt = updatedAt
    }
}

public enum SessionOriginalStateState: String, Codable, CaseIterable, Hashable, Sendable {
    case recording = "recording"
    case recovering = "recovering"
    case saved = "saved"
    case savedWithGaps = "savedWithGaps"
    case partial = "partial"
    case importing = "importing"
    case archiveOnly = "archiveOnly"
    case missing = "missing"
    case trashed = "trashed"
}

public struct SessionOutcome: Codable, Equatable, Sendable {
    public var winner: SessionOutcomeWinner
    public var endType: SessionOutcomeEndType
    public var serves: [SessionServeAttempt]?
    public var strokeCount: Int?
    public var rallyLength: Int?
    public var errorDirection: SessionOutcomeErrorDirection?
    public var provenance: Provenance
    public var source: String
    public var capabilityId: String?
    public var capabilityVersion: String?
    public var confidence: Decimal?

    public init(winner: SessionOutcomeWinner, endType: SessionOutcomeEndType, serves: [SessionServeAttempt]? = nil, strokeCount: Int? = nil, rallyLength: Int? = nil, errorDirection: SessionOutcomeErrorDirection? = nil, provenance: Provenance, source: String, capabilityId: String? = nil, capabilityVersion: String? = nil, confidence: Decimal? = nil) {
        self.winner = winner
        self.endType = endType
        self.serves = serves
        self.strokeCount = strokeCount
        self.rallyLength = rallyLength
        self.errorDirection = errorDirection
        self.provenance = provenance
        self.source = source
        self.capabilityId = capabilityId
        self.capabilityVersion = capabilityVersion
        self.confidence = confidence
    }
}

public enum SessionOutcomeEndType: String, Codable, CaseIterable, Hashable, Sendable {
    case ace = "ace"
    case serviceWinner = "serviceWinner"
    case doubleFault = "doubleFault"
    case winner = "winner"
    case forcedError = "forcedError"
    case unforcedError = "unforcedError"
    case hindrance = "hindrance"
    case unknown = "unknown"
}

public enum SessionOutcomeErrorDirection: String, Codable, CaseIterable, Hashable, Sendable {
    case net = "net"
    case long = "long"
    case wide = "wide"
    case unknown = "unknown"
}

public enum SessionOutcomeWinner: String, Codable, CaseIterable, Hashable, Sendable {
    case a = "A"
    case b = "B"
    case unknown = "unknown"
}

public struct SessionPenaltyEvent: Codable, Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var type: SessionPenaltyEventType
    public var kind: SessionPenaltyEventKind
    public var player: String
    public var reason: SessionPenaltyEventReason?
    public var supersedes: String?
    public var insertBefore: String?
    public var tMs: Int?
    public var at: String?
    public var source: String?

    public init(id: String, seq: Int, type: SessionPenaltyEventType = .value, kind: SessionPenaltyEventKind, player: String, reason: SessionPenaltyEventReason? = nil, supersedes: String? = nil, insertBefore: String? = nil, tMs: Int? = nil, at: String? = nil, source: String? = nil) {
        self.id = id
        self.seq = seq
        self.type = type
        self.kind = kind
        self.player = player
        self.reason = reason
        self.supersedes = supersedes
        self.insertBefore = insertBefore
        self.tMs = tMs
        self.at = at
        self.source = source
    }
}

public enum SessionPenaltyEventKind: String, Codable, CaseIterable, Hashable, Sendable {
    case point = "point"
    case game = "game"
}

public enum SessionPenaltyEventReason: String, Codable, CaseIterable, Hashable, Sendable {
    case codeViolation = "codeViolation"
    case timeViolation = "timeViolation"
    case other = "other"
}

public enum SessionPenaltyEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "penalty"
}

public struct SessionPlayer: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var handedness: SessionPlayerHandedness
    public var backhand: SessionPlayerBackhand
    public var isSelf: Bool
    public var level: String?
    public var profileId: String?

    public init(id: String, displayName: String, handedness: SessionPlayerHandedness, backhand: SessionPlayerBackhand, isSelf: Bool, level: String? = nil, profileId: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.handedness = handedness
        self.backhand = backhand
        self.isSelf = isSelf
        self.level = level
        self.profileId = profileId
    }
}

public enum SessionPlayerBackhand: String, Codable, CaseIterable, Hashable, Sendable {
    case oneHanded = "oneHanded"
    case twoHanded = "twoHanded"
    case unknown = "unknown"
}

public enum SessionPlayerHandedness: String, Codable, CaseIterable, Hashable, Sendable {
    case right = "right"
    case left = "left"
    case unknown = "unknown"
}

public struct SessionPointEvent: Codable, Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var type: SessionPointEventType
    public var at: String?
    public var supersedes: String?
    public var insertBefore: String?
    public var recordedServer: String?
    public var decidingPointSide: SessionPointEventDecidingPointSide?
    public var tStartMs: Int?
    public var tEndMs: Int?
    public var detected: SessionOutcome?
    public var reviewed: SessionOutcome?
    public var reviewState: SessionPointEventReviewState?
    public var note: String?
    public var parentIds: [String]?

    public init(id: String, seq: Int, type: SessionPointEventType = .value, at: String? = nil, supersedes: String? = nil, insertBefore: String? = nil, recordedServer: String? = nil, decidingPointSide: SessionPointEventDecidingPointSide? = nil, tStartMs: Int? = nil, tEndMs: Int? = nil, detected: SessionOutcome? = nil, reviewed: SessionOutcome? = nil, reviewState: SessionPointEventReviewState? = nil, note: String? = nil, parentIds: [String]? = nil) {
        self.id = id
        self.seq = seq
        self.type = type
        self.at = at
        self.supersedes = supersedes
        self.insertBefore = insertBefore
        self.recordedServer = recordedServer
        self.decidingPointSide = decidingPointSide
        self.tStartMs = tStartMs
        self.tEndMs = tEndMs
        self.detected = detected
        self.reviewed = reviewed
        self.reviewState = reviewState
        self.note = note
        self.parentIds = parentIds
    }
}

public enum SessionPointEventDecidingPointSide: String, Codable, CaseIterable, Hashable, Sendable {
    case deuce = "deuce"
    case ad = "ad"
}

public enum SessionPointEventReviewState: String, Codable, CaseIterable, Hashable, Sendable {
    case unreviewed = "unreviewed"
    case needsReview = "needsReview"
    case reviewed = "reviewed"
}

public enum SessionPointEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "point"
}

public struct SessionRallyLetEvent: Codable, Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var type: SessionRallyLetEventType
    public var tStartMs: Int?
    public var tEndMs: Int?
    public var insertBefore: String?
    public var at: String?
    public var source: String?

    public init(id: String, seq: Int, type: SessionRallyLetEventType = .value, tStartMs: Int? = nil, tEndMs: Int? = nil, insertBefore: String? = nil, at: String? = nil, source: String? = nil) {
        self.id = id
        self.seq = seq
        self.type = type
        self.tStartMs = tStartMs
        self.tEndMs = tEndMs
        self.insertBefore = insertBefore
        self.at = at
        self.source = source
    }
}

public enum SessionRallyLetEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "rallyLet"
}

public struct SessionRallyPlayback: Codable, Equatable, Sendable {
    public var preRollMs: Int
    public var postRollMs: Int
    public var clips: [SessionRallyPlaybackClipsItem]?

    public init(preRollMs: Int, postRollMs: Int, clips: [SessionRallyPlaybackClipsItem]? = nil) {
        self.preRollMs = preRollMs
        self.postRollMs = postRollMs
        self.clips = clips
    }
}

public struct SessionRallyPlaybackClipsItem: Codable, Equatable, Sendable {
    public var targetId: String
    public var preRollMs: Int?
    public var postRollMs: Int?
    public var excluded: Bool?

    public init(targetId: String, preRollMs: Int? = nil, postRollMs: Int? = nil, excluded: Bool? = nil) {
        self.targetId = targetId
        self.preRollMs = preRollMs
        self.postRollMs = postRollMs
        self.excluded = excluded
    }
}

public struct SessionRecording: Codable, Equatable, Sendable {
    public var mode: SessionRecordingMode
    public var importSource: SessionRecordingImportSource?
    public var startedAt: String?
    public var timeZone: String?
    public var durationMs: Int?
    public var segments: [SessionSegment]
    public var gaps: [SessionGap]
    public var microphone: SessionRecordingMicrophone
    public var mediaAvailable: Bool
    public var device: SessionRecordingDevice?
    public var captureEvents: [SessionCaptureEvent]?
    public var recovery: SessionRecoveryReport?

    public init(mode: SessionRecordingMode, importSource: SessionRecordingImportSource? = nil, startedAt: String? = nil, timeZone: String? = nil, durationMs: Int? = nil, segments: [SessionSegment], gaps: [SessionGap], microphone: SessionRecordingMicrophone, mediaAvailable: Bool, device: SessionRecordingDevice? = nil, captureEvents: [SessionCaptureEvent]? = nil, recovery: SessionRecoveryReport? = nil) {
        self.mode = mode
        self.importSource = importSource
        self.startedAt = startedAt
        self.timeZone = timeZone
        self.durationMs = durationMs
        self.segments = segments
        self.gaps = gaps
        self.microphone = microphone
        self.mediaAvailable = mediaAvailable
        self.device = device
        self.captureEvents = captureEvents
        self.recovery = recovery
    }
}

public struct SessionRecordingDevice: Codable, Equatable, Sendable {
    public var model: String?
    public var osVersion: String?
    public var cameraPreset: String?

    public init(model: String? = nil, osVersion: String? = nil, cameraPreset: String? = nil) {
        self.model = model
        self.osVersion = osVersion
        self.cameraPreset = cameraPreset
    }
}

public enum SessionRecordingImportSource: String, Codable, CaseIterable, Hashable, Sendable {
    case photos = "photos"
    case files = "files"
    case googleDrive = "googleDrive"
}

public enum SessionRecordingMicrophone: String, Codable, CaseIterable, Hashable, Sendable {
    case granted = "granted"
    case denied = "denied"
    case notRequested = "notRequested"
    case unavailable = "unavailable"
}

public enum SessionRecordingMode: String, Codable, CaseIterable, Hashable, Sendable {
    case camera = "camera"
    case `import` = "import"
    case simulatorFixture = "simulatorFixture"
    case none = "none"
}

public struct SessionRecoveryReport: Codable, Equatable, Sendable {
    public var recoveredAt: String
    public var outcome: SessionRecoveryReportOutcome
    public var savedThroughMs: Int?
    public var truncatedSegmentIds: [String]?
    public var unrecoverable: [SessionRecoveryReportUnrecoverableItem]?

    public init(recoveredAt: String, outcome: SessionRecoveryReportOutcome, savedThroughMs: Int? = nil, truncatedSegmentIds: [String]? = nil, unrecoverable: [SessionRecoveryReportUnrecoverableItem]? = nil) {
        self.recoveredAt = recoveredAt
        self.outcome = outcome
        self.savedThroughMs = savedThroughMs
        self.truncatedSegmentIds = truncatedSegmentIds
        self.unrecoverable = unrecoverable
    }
}

public enum SessionRecoveryReportOutcome: String, Codable, CaseIterable, Hashable, Sendable {
    case complete = "complete"
    case partial = "partial"
}

public struct SessionRecoveryReportUnrecoverableItem: Codable, Equatable, Sendable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct SessionReview: Codable, Equatable, Sendable {
    public var state: SessionReviewState
    public var updatedAt: String?

    public init(state: SessionReviewState, updatedAt: String? = nil) {
        self.state = state
        self.updatedAt = updatedAt
    }
}

public enum SessionReviewState: String, Codable, CaseIterable, Hashable, Sendable {
    case notStarted = "notStarted"
    case inProgress = "inProgress"
    case complete = "complete"
}

public struct SessionSampleInfo: Codable, Equatable, Sendable {
    public var label: SessionSampleInfoLabel
    public var synthetic: Bool
    public var generator: String
    public var mediaIds: [String]?

    public init(label: SessionSampleInfoLabel = .value, synthetic: Bool, generator: String, mediaIds: [String]? = nil) {
        self.label = label
        self.synthetic = synthetic
        self.generator = generator
        self.mediaIds = mediaIds
    }
}

public enum SessionSampleInfoLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "Sample"
}

public struct SessionSegment: Codable, Equatable, Sendable {
    public var id: String
    public var index: Int
    public var file: RecordFileReference
    public var startMs: Int
    public var durationMs: Int
    public var frameRate: RecordedFrameRate
    public var width: Int
    public var height: Int
    public var codec: SessionSegmentCodec
    public var hasAudio: Bool
    public var rotationDegrees: SessionSegmentRotationDegrees?
    public var finalized: Bool
    public var recoveredAfterInterruption: Bool?

    public init(id: String, index: Int, file: RecordFileReference, startMs: Int, durationMs: Int, frameRate: RecordedFrameRate, width: Int, height: Int, codec: SessionSegmentCodec, hasAudio: Bool, rotationDegrees: SessionSegmentRotationDegrees? = nil, finalized: Bool, recoveredAfterInterruption: Bool? = nil) {
        self.id = id
        self.index = index
        self.file = file
        self.startMs = startMs
        self.durationMs = durationMs
        self.frameRate = frameRate
        self.width = width
        self.height = height
        self.codec = codec
        self.hasAudio = hasAudio
        self.rotationDegrees = rotationDegrees
        self.finalized = finalized
        self.recoveredAfterInterruption = recoveredAfterInterruption
    }
}

public enum SessionSegmentCodec: String, Codable, CaseIterable, Hashable, Sendable {
    case hevc = "hevc"
    case h264 = "h264"
    case prores = "prores"
    case other = "other"
}

public enum SessionSegmentRotationDegrees: Int, Codable, CaseIterable, Hashable, Sendable {
    case value0 = 0
    case value90 = 90
    case value180 = 180
    case value270 = 270
}

public struct SessionServeAttempt: Codable, Equatable, Sendable {
    public var result: SessionServeAttemptResult
    public var faultType: SessionServeAttemptFaultType?
    public var cause: SessionServeAttemptCause?
    public var tMs: Int?

    public init(result: SessionServeAttemptResult, faultType: SessionServeAttemptFaultType? = nil, cause: SessionServeAttemptCause? = nil, tMs: Int? = nil) {
        self.result = result
        self.faultType = faultType
        self.cause = cause
        self.tMs = tMs
    }
}

public enum SessionServeAttemptCause: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "timeViolation"
}

public enum SessionServeAttemptFaultType: String, Codable, CaseIterable, Hashable, Sendable {
    case net = "net"
    case long = "long"
    case wide = "wide"
    case footFault = "footFault"
    case hitFixture = "hitFixture"
    case other = "other"
}

public enum SessionServeAttemptResult: String, Codable, CaseIterable, Hashable, Sendable {
    case `in` = "in"
    case fault = "fault"
    case `let` = "let"
}

public struct SessionServeMark: Codable, Equatable, Sendable {
    public var id: String
    public var pointId: String?
    public var shotId: String?
    public var contactFrame: MediaTime?
    public var bounceFrame: MediaTime?
    public var bounceCourt: CourtPoint2D?
    public var bounceImage: CourtPoint2D?
    public var serverPosition: CourtPoint2D?
    public var contactDefaulted: Bool?
    public var servedTo: SessionServeMarkServedTo?
    public var calibrationId: String?
    public var outlierConfirmed: Bool?
    public var provenance: RecordProvenance

    public init(id: String, pointId: String? = nil, shotId: String? = nil, contactFrame: MediaTime? = nil, bounceFrame: MediaTime? = nil, bounceCourt: CourtPoint2D? = nil, bounceImage: CourtPoint2D? = nil, serverPosition: CourtPoint2D? = nil, contactDefaulted: Bool? = nil, servedTo: SessionServeMarkServedTo? = nil, calibrationId: String? = nil, outlierConfirmed: Bool? = nil, provenance: RecordProvenance) {
        self.id = id
        self.pointId = pointId
        self.shotId = shotId
        self.contactFrame = contactFrame
        self.bounceFrame = bounceFrame
        self.bounceCourt = bounceCourt
        self.bounceImage = bounceImage
        self.serverPosition = serverPosition
        self.contactDefaulted = contactDefaulted
        self.servedTo = servedTo
        self.calibrationId = calibrationId
        self.outlierConfirmed = outlierConfirmed
        self.provenance = provenance
    }
}

public enum SessionServeMarkServedTo: String, Codable, CaseIterable, Hashable, Sendable {
    case deuce = "deuce"
    case ad = "ad"
}

public enum SessionSetRule: Codable, Equatable, Sendable {
    case tiebreakSet(SessionSetRuleTiebreakSet)
    case advantageSet(SessionSetRuleAdvantageSet)
    case matchTiebreak(SessionSetRuleMatchTiebreak)

    private enum CodingKeys: String, CodingKey { case kind }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .kind)
        switch tag {
        case "tiebreakSet": self = .tiebreakSet(try SessionSetRuleTiebreakSet(from: decoder))
        case "advantageSet": self = .advantageSet(try SessionSetRuleAdvantageSet(from: decoder))
        case "matchTiebreak": self = .matchTiebreak(try SessionSetRuleMatchTiebreak(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown SessionSetRule discriminator")
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .tiebreakSet(let value): try value.encode(to: encoder)
        case .advantageSet(let value): try value.encode(to: encoder)
        case .matchTiebreak(let value): try value.encode(to: encoder)
        }
    }
}

public struct SessionSetRuleAdvantageSet: Codable, Equatable, Sendable {
    public var kind: SessionSetRuleAdvantageSetKind
    public var games: Int

    public init(kind: SessionSetRuleAdvantageSetKind = .value, games: Int) {
        self.kind = kind
        self.games = games
    }
}

public enum SessionSetRuleAdvantageSetKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "advantageSet"
}

public struct SessionSetRuleMatchTiebreak: Codable, Equatable, Sendable {
    public var kind: SessionSetRuleMatchTiebreakKind
    public var tiebreak: SessionTiebreakRule

    public init(kind: SessionSetRuleMatchTiebreakKind = .value, tiebreak: SessionTiebreakRule) {
        self.kind = kind
        self.tiebreak = tiebreak
    }
}

public enum SessionSetRuleMatchTiebreakKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "matchTiebreak"
}

public struct SessionSetRuleTiebreakSet: Codable, Equatable, Sendable {
    public var kind: SessionSetRuleTiebreakSetKind
    public var games: Int
    public var tiebreakAt: Int
    public var tiebreak: SessionTiebreakRule

    public init(kind: SessionSetRuleTiebreakSetKind = .value, games: Int, tiebreakAt: Int, tiebreak: SessionTiebreakRule) {
        self.kind = kind
        self.games = games
        self.tiebreakAt = tiebreakAt
        self.tiebreak = tiebreak
    }
}

public enum SessionSetRuleTiebreakSetKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "tiebreakSet"
}

public struct SessionShot: Codable, Equatable, Sendable {
    public var id: String
    public var pointId: String?
    public var tMs: Int?
    public var hitter: String
    public var shotIndex: Int?
    public var stroke: SessionShotStroke
    public var placement: SessionShotPlacement?
    public var provenance: RecordProvenance

    public init(id: String, pointId: String? = nil, tMs: Int? = nil, hitter: String, shotIndex: Int? = nil, stroke: SessionShotStroke, placement: SessionShotPlacement? = nil, provenance: RecordProvenance) {
        self.id = id
        self.pointId = pointId
        self.tMs = tMs
        self.hitter = hitter
        self.shotIndex = shotIndex
        self.stroke = stroke
        self.placement = placement
        self.provenance = provenance
    }
}

public struct SessionShotPlacement: Codable, Equatable, Sendable {
    public var court: CourtPoint2D
    public var zone: SessionShotPlacementZone?
    public var inOut: SessionShotPlacementInOut
    public var calibrationId: String?

    public init(court: CourtPoint2D, zone: SessionShotPlacementZone? = nil, inOut: SessionShotPlacementInOut, calibrationId: String? = nil) {
        self.court = court
        self.zone = zone
        self.inOut = inOut
        self.calibrationId = calibrationId
    }
}

public enum SessionShotPlacementInOut: String, Codable, CaseIterable, Hashable, Sendable {
    case `in` = "in"
    case out = "out"
    case needsReview = "needsReview"
}

public enum SessionShotPlacementZone: String, Codable, CaseIterable, Hashable, Sendable {
    case deep = "deep"
    case mid = "mid"
    case short = "short"
}

public enum SessionShotStroke: String, Codable, CaseIterable, Hashable, Sendable {
    case serve = "serve"
    case forehand = "forehand"
    case backhand = "backhand"
    case volley = "volley"
    case overhead = "overhead"
    case dropShot = "dropShot"
    case lob = "lob"
    case other = "other"
    case unknown = "unknown"
}

public struct SessionSides: Codable, Equatable, Sendable {
    public var A: [String]
    public var B: [String]

    public init(A: [String], B: [String]) {
        self.A = A
        self.B = B
    }
}

public struct SessionStoragePolicy: Codable, Equatable, Sendable {
    public var originals: SessionStoragePolicyOriginals
    public var includeInDeviceBackup: Bool
    public var removeAfterVerifiedBackup: Bool?

    public init(originals: SessionStoragePolicyOriginals, includeInDeviceBackup: Bool, removeAfterVerifiedBackup: Bool? = nil) {
        self.originals = originals
        self.includeInDeviceBackup = includeInDeviceBackup
        self.removeAfterVerifiedBackup = removeAfterVerifiedBackup
    }
}

public enum SessionStoragePolicyOriginals: String, Codable, CaseIterable, Hashable, Sendable {
    case onDevice = "onDevice"
    case archivedOnly = "archivedOnly"
    case removed = "removed"
    case none = "none"
}

public struct SessionSwing: Codable, Equatable, Sendable {
    public var id: String
    public var kind: SessionSwingKind
    public var stroke: SessionSwingStroke?
    public var shotId: String?
    public var serveMarkId: String?
    public var markId: String?
    public var clip: MediaRange?
    public var keyMoments: [SessionKeyMoment]
    public var reviewChecks: [SessionSwingReviewChecksItem]?

    public init(id: String, kind: SessionSwingKind, stroke: SessionSwingStroke? = nil, shotId: String? = nil, serveMarkId: String? = nil, markId: String? = nil, clip: MediaRange? = nil, keyMoments: [SessionKeyMoment], reviewChecks: [SessionSwingReviewChecksItem]? = nil) {
        self.id = id
        self.kind = kind
        self.stroke = stroke
        self.shotId = shotId
        self.serveMarkId = serveMarkId
        self.markId = markId
        self.clip = clip
        self.keyMoments = keyMoments
        self.reviewChecks = reviewChecks
    }
}

public enum SessionSwingKind: String, Codable, CaseIterable, Hashable, Sendable {
    case serve = "serve"
    case stroke = "stroke"
}

public struct SessionSwingReviewChecksItem: Codable, Equatable, Sendable {
    public var check: SessionSwingReviewChecksItemCheck
    public var status: SessionSwingReviewChecksItemStatus

    public init(check: SessionSwingReviewChecksItemCheck, status: SessionSwingReviewChecksItemStatus) {
        self.check = check
        self.status = status
    }
}

public enum SessionSwingReviewChecksItemCheck: String, Codable, CaseIterable, Hashable, Sendable {
    case contactTiming = "contactTiming"
    case followThrough = "followThrough"
    case balance = "balance"
}

public enum SessionSwingReviewChecksItemStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case notReviewed = "notReviewed"
    case looksGood = "looksGood"
    case workOnIt = "workOnIt"
}

public enum SessionSwingStroke: String, Codable, CaseIterable, Hashable, Sendable {
    case serve = "serve"
    case forehand = "forehand"
    case backhand = "backhand"
    case volley = "volley"
    case overhead = "overhead"
    case dropShot = "dropShot"
    case lob = "lob"
    case other = "other"
    case unknown = "unknown"
}

public struct SessionTiebreakRule: Codable, Equatable, Sendable {
    public var points: Int
    public var suddenDeathAt: Int?
    public var endChange: SessionTiebreakRuleEndChange?
    public var suddenDeathSide: SessionTiebreakRuleSuddenDeathSide?

    public init(points: Int, suddenDeathAt: Int? = nil, endChange: SessionTiebreakRuleEndChange? = nil, suddenDeathSide: SessionTiebreakRuleSuddenDeathSide? = nil) {
        self.points = points
        self.suddenDeathAt = suddenDeathAt
        self.endChange = endChange
        self.suddenDeathSide = suddenDeathSide
    }
}

public enum SessionTiebreakRuleEndChange: String, Codable, CaseIterable, Hashable, Sendable {
    case every6 = "every6"
    case coman = "coman"
    case after4 = "after4"
}

public enum SessionTiebreakRuleSuddenDeathSide: String, Codable, CaseIterable, Hashable, Sendable {
    case alternate = "alternate"
    case receiverChooses = "receiverChooses"
}

public struct SessionToss: Codable, Equatable, Sendable {
    public var firstServer: String
    public var startingEnds: SessionTossStartingEnds
    public var tossWinner: Side?
    public var tossChoice: SessionTossTossChoice?

    public init(firstServer: String, startingEnds: SessionTossStartingEnds, tossWinner: Side? = nil, tossChoice: SessionTossTossChoice? = nil) {
        self.firstServer = firstServer
        self.startingEnds = startingEnds
        self.tossWinner = tossWinner
        self.tossChoice = tossChoice
    }
}

public struct SessionTossStartingEnds: Codable, Equatable, Sendable {
    public var A: SessionTossStartingEndsA
    public var B: SessionTossStartingEndsB

    public init(A: SessionTossStartingEndsA, B: SessionTossStartingEndsB) {
        self.A = A
        self.B = B
    }
}

public enum SessionTossStartingEndsA: String, Codable, CaseIterable, Hashable, Sendable {
    case near = "near"
    case far = "far"
}

public enum SessionTossStartingEndsB: String, Codable, CaseIterable, Hashable, Sendable {
    case near = "near"
    case far = "far"
}

public enum SessionTossTossChoice: String, Codable, CaseIterable, Hashable, Sendable {
    case serve = "serve"
    case receive = "receive"
    case end = "end"
    case deferred = "deferred"
}

public struct SessionVoiceNote: Codable, Equatable, Sendable {
    public var id: String
    public var file: RecordFileReference
    public var durationMs: Int
    public var pinnedAtMs: Int?
    public var comparisonId: String?
    public var createdAt: String
    public var transcript: SessionVoiceNoteTranscript?

    public init(id: String, file: RecordFileReference, durationMs: Int, pinnedAtMs: Int? = nil, comparisonId: String? = nil, createdAt: String, transcript: SessionVoiceNoteTranscript? = nil) {
        self.id = id
        self.file = file
        self.durationMs = durationMs
        self.pinnedAtMs = pinnedAtMs
        self.comparisonId = comparisonId
        self.createdAt = createdAt
        self.transcript = transcript
    }
}

public struct SessionVoiceNoteTranscript: Codable, Equatable, Sendable {
    public var text: String
    public var provenance: RecordProvenance

    public init(text: String, provenance: RecordProvenance) {
        self.text = text
        self.provenance = provenance
    }
}

public struct SessionVoidEvent: Codable, Equatable, Sendable {
    public var id: String
    public var seq: Int
    public var type: SessionVoidEventType
    public var target: String
    public var at: String?
    public var source: String?

    public init(id: String, seq: Int, type: SessionVoidEventType = .value, target: String, at: String? = nil, source: String? = nil) {
        self.id = id
        self.seq = seq
        self.type = type
        self.target = target
        self.at = at
        self.source = source
    }
}

public enum SessionVoidEventType: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "void"
}

public enum Side: String, Codable, CaseIterable, Hashable, Sendable {
    case a = "A"
    case b = "B"
}

public struct SideCounts: Codable, Equatable, Sendable {
    public var A: Int
    public var B: Int

    public init(A: Int, B: Int) {
        self.A = A
        self.B = B
    }
}
