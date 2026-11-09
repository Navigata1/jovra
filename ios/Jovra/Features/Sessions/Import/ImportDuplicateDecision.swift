import JovraMedia

enum FilesImportIntent {
    case practice(playerName: String)
    case match(FilesImportMatchSetup)

    var isMatch: Bool {
        if case .match = self { return true }
        return false
    }
}

/// One native picker invocation. Its permission carries only the copied fingerprint, never a provider URL.
struct FilesImportRequest {
    let intent: FilesImportIntent
    var duplicatePermission: FilesImportFingerprint? = nil
}

struct ImportDuplicateDecision {
    let intent: FilesImportIntent
    let fingerprint: FilesImportFingerprint
    var existing: FilesImportDuplicate?
    var confirmsFullMatch = false

    var canRetry: Bool { !intent.isMatch || confirmsFullMatch }

    mutating func makeRetryRequest() -> FilesImportRequest? {
        guard canRetry else { return nil }
        confirmsFullMatch = false
        return FilesImportRequest(intent: intent, duplicatePermission: fingerprint)
    }
}
