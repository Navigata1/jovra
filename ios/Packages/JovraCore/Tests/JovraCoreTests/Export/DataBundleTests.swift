import Foundation
import Testing
@testable import JovraCore

private let app = AppInfo(version: "1.0", build: "42", platform: .ios)
private let exportedAt = "2026-10-07T01:30:00Z"

private func sample() throws -> SessionDocument {
    let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
    return try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: path))
}
private func golden(_ name: String) throws -> Data {
    try Data(contentsOf: FixtureManifest.repository().appendingPathComponent("spec/fixtures/sample/" + name))
}
/// The reference export manifest (spec/fixtures/sample/export.json), hashed by Python's hashlib at generation.
private func referenceHashes() throws -> [String: String] {
    let manifest = try ContractCodec.decode(ExportManifest.self, from: golden("export.json"))
    return Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.role.rawValue, $0.sha256) })
}

private func emit(_ bundle: ExportBundle, folder: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["JOVRA_DATA_BUNDLE_OUTPUT_DIR"] else { return }
    let root = URL(fileURLWithPath: directory).appendingPathComponent(folder)
    for (path, data) in [(ExportBundle.manifestPath, bundle.manifestJSON)] + bundle.files.map({ ($0.path, $0.data) }) {
        let target = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }
}

@Test func sha256MatchesPublishedVectorsAndTheReferenceManifest() throws {
    #expect(SHA256.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(SHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    let hashes = try referenceHashes()
    #expect(SHA256.hex(try golden("jon-vs-alex.points.csv")) == hashes["pointsCsv"])
    #expect(SHA256.hex(try golden("jon-vs-alex.stats.csv")) == hashes["statsCsv"])
}

@Test func exportMyDataLaysOutEverySessionWithHashedFiles() throws {
    let document = try sample()
    var practice = document
    practice.id = "6f0c3d1e-1c55-4b8e-9a3f-1d6e8f0a2b44"
    practice.match = nil
    practice.sessionKind = .servePractice
    var rematch = document
    rematch.id = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
    let bundle = try DataExporter.exportMyData([document, practice, rematch], exportedAt: exportedAt, app: app)
    let paths = bundle.files.map(\.path)
    #expect(paths.first == "README.txt")
    let folder = "sessions/2026-10-06 Jon vs Alex"
    #expect(paths.contains(folder + "/session.json") && paths.contains(folder + "/points.csv") && paths.contains(folder + "/stats.csv"))
    #expect(Set(paths).count == paths.count, "same title and date never collide: \(paths)")
    #expect(paths.filter { $0.hasSuffix("/points.csv") }.count == 2, "the practice session has no score, so no CSV")
    let manifest = bundle.manifest
    #expect(manifest.scope == .allData && manifest.contact == .value && !manifest.includesAudio && !manifest.includesOriginals)
    #expect(manifest.sessions.count == 3 && manifest.sessions.allSatisfy { $0.sample == true })
    #expect(manifest.files.map(\.path) == paths)
    for (entry, file) in zip(manifest.files, bundle.files) {
        #expect(entry.bytes == file.data.count && entry.sha256 == SHA256.hex(file.data) && entry.role == file.role)
    }
    let points = try #require(bundle.files.first { $0.path == folder + "/points.csv" })
    let stats = try #require(bundle.files.first { $0.path == folder + "/stats.csv" })
    let goldenPoints = try golden("jon-vs-alex.points.csv"), goldenStats = try golden("jon-vs-alex.stats.csv")
    #expect(points.data == goldenPoints && stats.data == goldenStats)
    let hashes = try referenceHashes()
    #expect(manifest.files.first { $0.path == folder + "/stats.csv" }?.sha256 == hashes["statsCsv"])
    #expect(try ContractCodec.decode(ExportManifest.self, from: bundle.manifestJSON) == manifest)
    let readme = String(decoding: try #require(bundle.files.first?.data), as: UTF8.self)
    #expect(readme.contains("hello@islanddevcrew.com") && !readme.contains("mailto:"))
    #expect(throws: DataBundleError.noSessions) { try DataExporter.exportMyData([], exportedAt: exportedAt, app: app) }
    try emit(try DataExporter.exportMyData([document], exportedAt: exportedAt, app: app), folder: "export-my-data")
}

@Test func folderNamesStayInsideTheManifestPathAlphabet() throws {
    var document = try sample()
    document.title = "../Jon / Alex: 6–4 🎾 final.."
    let name = DataExporter.folderName(document)
    #expect(name == "2026-10-06 Jon - Alex- 6-4 - final")
    #expect(DataExporter.isSafe("sessions/" + name + "/session.json"))
    #expect(!DataExporter.isSafe("../escape.json") && !DataExporter.isSafe("/abs.json") && !DataExporter.isSafe("a/é.csv"))
}

@Test func sharePackDataHoldsMatchJSONPointsAndAStaticViewer() throws {
    let document = try sample()
    let bundle = try DataExporter.sharePackData(document, audience: .coach, selection: .fullCopy,
        clips: [SharePackClip(path: "clips/point-42.mp4", title: "Point 42 · 15–30", note: "Watch the split step")],
        exportedAt: exportedAt, app: app)
    #expect(bundle.files.map(\.path) == ["index.html", "match.json", "points.csv"])
    #expect(bundle.manifest.scope == .sharePack && bundle.manifest.sharePack == .init(audience: .coach, selection: .fullCopy))
    #expect(bundle.files.first { $0.path == "index.html" }?.role == .viewerHtml)
    #expect(bundle.files.first { $0.path == "points.csv" }?.data == (try golden("jon-vs-alex.points.csv")))
    #expect(try ContractCodec.decode(SessionDocument.self, from: #require(bundle.files.first { $0.path == "match.json" }).data) == document)
    let html = String(decoding: try #require(bundle.files.first?.data), as: UTF8.self)
    for needle in ["Sample · demo data", "Jon won 6-4 6-3", "58%", "72 / 124", "67%", "40 / 60", "28 / 40", "386",
                   "Racket contacts in live play", "Points after a 1st-serve fault", "8 of 124 points are not yet reviewed",
                   "clips/point-42.mp4", "Watch the split step", "hello@islanddevcrew.com"] {
        #expect(html.contains(needle), "viewer is missing \(needle)")
    }
    for forbidden in ["<script", "http://", "https://", "mailto:", "<link", "@import"] {
        #expect(!html.contains(forbidden), "viewer must not contain \(forbidden)")
    }
    try emit(bundle, folder: "share-pack")
}

@Test func selectedPointsPackKeepsOnlyChosenRowsAndEscapesUserText() throws {
    var document = try sample()
    document.title = "Jon <script>alert(1)</script> & \"Alex\""
    let timeline = try ScoringEngine.fold(ScoringInput(session: document))
    let chosen = [timeline.points[41].id, timeline.points[0].id]
    let bundle = try DataExporter.sharePackData(document, audience: .opponent, selection: .selectedPoints,
                                                selectedPointIDs: chosen, exportedAt: exportedAt, app: app)
    let csv = String(decoding: try #require(bundle.files.first { $0.path == "points.csv" }).data, as: UTF8.self)
    let rows = csv.split(separator: "\n")
    #expect(rows.count == 3, "header plus two chosen points, in match order")
    #expect(rows[1].hasPrefix("1,") && rows[2].hasPrefix("42,"))
    let html = String(decoding: try #require(bundle.files.first?.data), as: UTF8.self)
    #expect(!html.contains("<script") && html.contains("Jon &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;Alex&quot;"))
    #expect(html.contains("2 points chosen for you"))
    #expect(throws: DataBundleError.unknownPoint("nope")) {
        try DataExporter.sharePackData(document, audience: .coach, selection: .selectedPoints, selectedPointIDs: ["nope"],
                                       exportedAt: exportedAt, app: app)
    }
    #expect(throws: DataBundleError.emptySelection) {
        try DataExporter.sharePackData(document, audience: .coach, selection: .selectedPoints, exportedAt: exportedAt, app: app)
    }
}

@Test func manifestRefusesUnsafeOrDuplicatePaths() throws {
    let file = ExportBundleFile(path: "../x.csv", role: .pointsCsv, mimeType: "text/csv", data: Data(), sessionId: nil)
    #expect(throws: DataBundleError.unsafePath("../x.csv")) {
        try DataExporter.manifest(listing: [file], scope: .session, sessions: [], exportedAt: exportedAt, app: app, sharePack: nil)
    }
    let a = ExportBundleFile(path: "a.csv", role: .pointsCsv, mimeType: "text/csv", data: Data(), sessionId: nil)
    #expect(throws: DataBundleError.duplicatePath("a.csv")) {
        try DataExporter.manifest(listing: [a, a], scope: .session, sessions: [], exportedAt: exportedAt, app: app, sharePack: nil)
    }
    let manifest = ExportBundleFile(path: "export.json", role: .readme, mimeType: "text/plain", data: Data(), sessionId: nil)
    #expect(throws: DataBundleError.unsafePath("export.json")) {
        try DataExporter.manifest(listing: [manifest], scope: .session, sessions: [], exportedAt: exportedAt, app: app, sharePack: nil)
    }
}

@Test func viewerNamesAnEstimatedInputInsideTheStatsItFeeds() throws {
    var document = try sample()
    var match = try #require(document.match)
    let index = try #require(match.log.firstIndex { $0.seq == 1 })
    guard case .point(var point) = match.log[index] else { Issue.record("Sample seq1 must be a point"); return }
    var outcome = try #require(point.reviewed)
    outcome.provenance = .estimated
    point.detected = outcome; point.reviewed = nil; point.reviewState = .unreviewed
    match.log[index] = .point(point)
    document.match = match
    let bundle = try DataExporter.sharePackData(document, audience: .coach, selection: .fullCopy, exportedAt: exportedAt, app: app)
    let html = String(decoding: try #require(bundle.files.first?.data), as: UTF8.self)
    // Points won now rests on 9 unreviewed points (8 flagged plus the estimate), so it must say Estimated.
    #expect(html.contains("Estimated · includes 9 unreviewed points"))
    #expect(html.contains("9 of 124 points are not yet reviewed"))
}
