import Foundation

/// One file of an export folder, at its path relative to the folder root.
public struct ExportBundleFile: Equatable, Sendable {
    public let path: String
    public let role: ExportManifestFilesItemRole
    public let mimeType: String
    public let data: Data
    public let sessionId: String?
}

/// An export folder held in memory: `export.json` (the manifest, spec/schemas/export.schema.json) plus the files it
/// lists with their sizes and SHA-256. Writing it to disk, zipping and adding video are the caller's job; video files
/// are added by the media layer, which then rebuilds the manifest with `manifest(listing:)`.
public struct ExportBundle: Sendable {
    public static let manifestPath = "export.json"
    public let manifest: ExportManifest
    public let manifestJSON: Data
    public let files: [ExportBundleFile]
}

/// Share Pack video choices live in the media layer; a clip listed here is only a title and a note for the viewer.
public struct SharePackClip: Equatable, Sendable {
    public let path: String
    public let title: String
    public let note: String?
    public init(path: String, title: String, note: String? = nil) { self.path = path; self.title = title; self.note = note }
}

public enum DataBundleError: Error, Equatable, Sendable {
    case noSessions, unsafePath(String), duplicatePath(String), unknownPoint(String), emptySelection
}

extension DataExporter {
    /// "Export my data": every session's JSON, and for match sessions its points and stats CSV.
    /// Layout: `export.json`, `README.txt`, then `sessions/<YYYY-MM-DD> <title>/session.json|points.csv|stats.csv`.
    public static func exportMyData(_ sessions: [SessionDocument], exportedAt: String, app: AppInfo) throws -> ExportBundle {
        guard !sessions.isEmpty else { throw DataBundleError.noSessions }
        var folders: Set<String> = [], files: [ExportBundleFile] = [], items: [ExportManifestSessionsItem] = []
        for document in sessions.sorted(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }) {
            let base = "sessions/" + folderName(document)
            var folder = base, copy = 2
            while !folders.insert(folder).inserted { folder = "\(base) (\(copy))"; copy += 1 }
            if document.match != nil {
                let data = try exportSession(document)
                files += [file(folder + "/session.json", .sessionJson, "application/json", data.sessionJSON, document.id),
                          file(folder + "/points.csv", .pointsCsv, "text/csv", data.pointsCSV, document.id),
                          file(folder + "/stats.csv", .statsCsv, "text/csv", data.statsCSV, document.id)]
            } else {
                files.append(file(folder + "/session.json", .sessionJson, "application/json", try CanonicalJSON.encode(document), document.id))
            }
            items.append(.init(id: document.id, title: document.title, path: folder + "/session.json",
                               sample: document.sample == nil ? nil : true, eventLogVersion: logVersion(document)))
        }
        let readme = file("README.txt", .readme, "text/plain", Data(readmeText(sessionCount: sessions.count).utf8), nil)
        return try bundle(scope: .allData, sessions: items, files: [readme] + files, exportedAt: exportedAt, app: app, sharePack: nil)
    }

    /// The data part of a Share Pack: `match.json` (session schema), `points.csv` and a static `index.html` viewer.
    /// `selectedPoints` keeps only the chosen points in points.csv; the viewer's stats always cover the whole match.
    public static func sharePackData(_ document: SessionDocument, audience: ExportManifestSharePackAudience,
                                     selection: ExportManifestSharePackSelection, selectedPointIDs: [String] = [],
                                     clips: [SharePackClip] = [], exportedAt: String, app: AppInfo) throws -> ExportBundle {
        let rendered = try render(document)
        var rows = rendered.pointRows
        if selection == .selectedPoints {
            guard !selectedPointIDs.isEmpty else { throw DataBundleError.emptySelection }
            let known = Set(rows.map(\.id))
            if let missing = selectedPointIDs.first(where: { !known.contains($0) }) { throw DataBundleError.unknownPoint(missing) }
            let chosen = Set(selectedPointIDs)
            rows = rows.filter { chosen.contains($0.id) }
        }
        let points = CSV.render(rows.map(\.cells), contract: rendered.pointsContract)
        let viewer = try SharePackViewer.html(document: document, rendered: rendered, clips: clips,
                                              selectedCount: selection == .selectedPoints ? rows.count : nil)
        let files = [file("index.html", .viewerHtml, "text/html", Data(viewer.utf8), nil),
                     file("match.json", .sessionJson, "application/json", rendered.export.sessionJSON, document.id),
                     file("points.csv", .pointsCsv, "text/csv", points, document.id)]
        let item = ExportManifestSessionsItem(id: document.id, title: document.title, path: "match.json",
                                              sample: document.sample == nil ? nil : true, eventLogVersion: logVersion(document))
        return try bundle(scope: .sharePack, sessions: [item], files: files, exportedAt: exportedAt, app: app,
                          sharePack: .init(audience: audience, selection: selection))
    }

    /// Builds the manifest over a complete file list (for example after the media layer adds clips).
    public static func manifest(listing files: [ExportBundleFile], scope: ExportManifestScope, sessions: [ExportManifestSessionsItem],
                                exportedAt: String, app: AppInfo, sharePack: ExportManifestSharePack?) throws -> ExportManifest {
        var seen: Set<String> = []
        for entry in files {
            guard isSafe(entry.path), entry.path != ExportBundle.manifestPath else { throw DataBundleError.unsafePath(entry.path) }
            guard seen.insert(entry.path).inserted else { throw DataBundleError.duplicatePath(entry.path) }
        }
        return ExportManifest(exportedAt: exportedAt, app: app, scope: scope, includesAudio: false,
            includesOriginals: files.contains { $0.role == .original }, sessions: sessions,
            files: files.map { .init(path: $0.path, role: $0.role, mimeType: $0.mimeType, bytes: $0.data.count,
                                     sha256: SHA256.hex($0.data), sessionId: $0.sessionId) },
            csvContracts: [.init(name: .points, version: 1), .init(name: .stats, version: 1)],
            contact: .value, sharePack: sharePack)
    }

    private static func bundle(scope: ExportManifestScope, sessions: [ExportManifestSessionsItem], files: [ExportBundleFile],
                               exportedAt: String, app: AppInfo, sharePack: ExportManifestSharePack?) throws -> ExportBundle {
        let manifest = try manifest(listing: files, scope: scope, sessions: sessions, exportedAt: exportedAt, app: app, sharePack: sharePack)
        return ExportBundle(manifest: manifest, manifestJSON: try CanonicalJSON.encode(manifest), files: files)
    }

    private static func file(_ path: String, _ role: ExportManifestFilesItemRole, _ mime: String, _ data: Data, _ id: String?) -> ExportBundleFile {
        ExportBundleFile(path: path, role: role, mimeType: mime, data: data, sessionId: id)
    }

    private static func logVersion(_ document: SessionDocument) -> Int? { document.match.map { $0.log.map(\.seq).max() ?? 0 } }

    /// "<YYYY-MM-DD> <title>" with only manifest-safe characters (spec relativePath).
    static func folderName(_ document: SessionDocument) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._()-")
        var title = String(document.title.map { allowed.contains($0) ? $0 : "-" })
        while title.contains("--") { title = title.replacingOccurrences(of: "--", with: "-") }
        while title.contains("..") { title = title.replacingOccurrences(of: "..", with: ".") }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        let name = String(document.createdAt.prefix(10)) + " " + (title.isEmpty ? "Session" : String(title.prefix(80)))
        return name.trimmingCharacters(in: .whitespaces)
    }

    static func isSafe(_ path: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._()/-")
        return (1...255).contains(path.count) && !path.hasPrefix("/") && !path.contains("..") && path.allSatisfy(allowed.contains)
    }

    private static func readmeText(sessionCount: Int) -> String {
        """
        JOVRA data export

        This folder holds \(sessionCount == 1 ? "1 session" : "\(sessionCount) sessions") exported from JOVRA.

        export.json lists every file with its size and SHA-256 so you can check nothing changed.
        Each session has its own folder under sessions/:
          session.json  the complete session record (the same format JOVRA saves next to your video)
          points.csv    one row per point: score before, server, winner, how the point ended, review state
          stats.csv     every stat as numerator, denominator and percentage

        CSV files are UTF-8 with a header row, comma separated, LF line endings. Percentages are whole numbers
        rounded half up; an empty denominator shows as a dash, never as 0%.
        Sessions marked "sample" are JOVRA's demo content, not your play.

        Contact: hello@islanddevcrew.com

        """
    }
}
