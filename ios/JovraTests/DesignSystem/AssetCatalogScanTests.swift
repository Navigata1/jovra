import Foundation
import Testing
@testable import Jovra

/// Hero and editorial art is vector only (screens.md §6 open question 2): the asset catalog holds no
/// photographs and no third-party marks (CLAUDE.md rule 6).
@Suite("Asset catalog scan")
struct AssetCatalogScanTests {
    static let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Jovra/Resources/Assets.xcassets")

    @Test("the shipped asset catalog has no photographic assets and no third-party marks")
    func shippedCatalogIsClean() throws {
        #expect(FileManager.default.fileExists(atPath: Self.catalog.path))
        #expect(try AssetCatalogScan.findings(in: Self.catalog) == [])
    }

    @Test("the built app bundle carries no loose photographs")
    func bundleHasNoPhotos() throws {
        #expect(AssetCatalogScan.photographs(inBundleAt: Bundle.main.bundleURL) == [])
    }

    @Test("a seeded photograph and a seeded manufacturer mark are both found")
    func seededFindingsFail() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString).xcassets")
        defer { try? FileManager.default.removeItem(at: root) }
        let hero = root.appendingPathComponent("HeroCourt.imageset")
        let logo = root.appendingPathComponent("WilsonLogo.imageset")
        for folder in [hero, logo] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try Data([0xFF, 0xD8, 0xFF]).write(to: hero.appendingPathComponent("court.jpg"))
        try Data("<svg/>".utf8).write(to: logo.appendingPathComponent("logo.svg"))
        let findings = try AssetCatalogScan.findings(in: root)
        #expect(findings.contains { $0.contains("HeroCourt.imageset/court.jpg") && $0.contains("raster") })
        #expect(findings.contains { $0.contains("WilsonLogo.imageset") && $0.contains("wilson") })
    }

    @Test("the app icon is the one raster allowed: it is rendered from the vector brand mark")
    func appIconAllowed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("icon-\(UUID().uuidString).xcassets")
        defer { try? FileManager.default.removeItem(at: root) }
        let icon = root.appendingPathComponent("AppIcon.appiconset")
        try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
        try Data([0x89, 0x50]).write(to: icon.appendingPathComponent("AppIcon-1024.png"))
        #expect(try AssetCatalogScan.findings(in: root) == [])
    }
}
