import Foundation

/// Scans an asset catalog (and a built bundle) for what the vector-only art rule forbids: raster
/// images, which would be photographs or traced logos, and names of manufacturers or tours.
enum AssetCatalogScan {
    /// Raster formats. The app icon is the one exception: it is rendered from the vector brand mark
    /// by scripts/ios/render-app-icon.sh.
    static let rasterExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "webp", "tif", "tiff", "gif", "bmp"]
    /// Third-party marks that must never be bundled (CLAUDE.md rule 6). Matched as whole words.
    static let thirdPartyMarks: Set<String> = [
        "wilson", "babolat", "head", "yonex", "prince", "tecnifibre", "dunlop", "volkl", "slazenger", "solinco",
        "luxilon", "nike", "adidas", "asics", "lacoste", "uniqlo", "rolex", "atp", "wta", "itf", "wimbledon",
        "usopen", "rolandgarros", "hawkeye", "swingvision",
    ]

    static func findings(in catalog: URL) throws -> [String] {
        let files = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        var findings: [String] = []
        for file in files {
            let relative = String(file.path.dropFirst(catalog.path.count + 1))
            let inAppIcon = relative.split(separator: "/").first?.hasSuffix(".appiconset") == true
            if rasterExtensions.contains(file.pathExtension.lowercased()), !inAppIcon {
                findings.append("\(relative): raster image (hero and editorial art is vector only)")
            }
            for word in words(in: relative) where thirdPartyMarks.contains(word) {
                findings.append("\(relative): third-party mark “\(word)”")
            }
        }
        return Array(Set(findings)).sorted()
    }

    /// Loose raster files in a built bundle, outside compiled asset catalogs and app icons.
    static func photographs(inBundleAt bundle: URL) -> [String] {
        let files = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        return files.filter { file in
            let ext = file.pathExtension.lowercased()
            return rasterExtensions.contains(ext) && ext != "png"
                || ext == "png" && !file.lastPathComponent.hasPrefix("AppIcon")
        }
        .map { String($0.path.dropFirst(bundle.path.count + 1)) }
        .filter { !$0.hasPrefix("PlugIns/") && !$0.hasPrefix("Frameworks/") }
        .sorted()
    }

    /// Lower-cased words of a path, splitting camel case and punctuation ("WilsonLogo" → wilson, logo).
    static func words(in path: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousLower = false
        for character in path {
            if character.isLetter {
                if character.isUppercase, previousLower, !current.isEmpty { words.append(current); current = "" }
                current.append(Character(character.lowercased()))
                previousLower = character.isLowercase
            } else {
                if !current.isEmpty { words.append(current); current = "" }
                previousLower = false
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
