import Foundation

public enum MediaFixtureError: Error, CustomStringConvertible, Equatable {
    case repositoryNotFound(start: String)
    case unknownTruth(String)
    case notRendered(path: String)

    public var description: String {
        switch self {
        case .repositoryNotFound(let start):
            "No JOVRA repository (spec/fixtures/media) above \(start)"
        case .unknownTruth(let id):
            "No ground truth with id \(id) under spec/fixtures/media"
        case .notRendered(let path):
            "Media fixture \(path) is not rendered for this renderer version. Run: python3 scripts/media/render.py"
        }
    }
}

/// Finds media fixtures by repository-relative path: ground truth under `spec/fixtures/media/<set>/` and
/// the rendered file at the truth's `media.path` inside the git-ignored `.cache/media/` folder.
public struct MediaFixtureCatalog: Sendable {
    public static let truthFolder = "spec/fixtures/media"

    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// The repository that contains `filePath` (a test passes its own `#filePath`).
    public static func repository(filePath: String = #filePath) -> MediaFixtureCatalog {
        (try? locate(from: URL(fileURLWithPath: filePath))) ?? MediaFixtureCatalog(root: URL(fileURLWithPath: filePath))
    }

    /// Walks up from `start` to the first folder that holds `spec/fixtures/media`.
    public static func locate(from start: URL) throws -> MediaFixtureCatalog {
        var url = start.standardizedFileURL
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(truthFolder).path) {
                return MediaFixtureCatalog(root: url)
            }
            url.deleteLastPathComponent()
        }
        throw MediaFixtureError.repositoryNotFound(start: start.path)
    }

    public var truthDirectory: URL { root.appendingPathComponent(Self.truthFolder, isDirectory: true) }

    /// Every ground-truth document, sorted by id.
    public func allTruths() throws -> [GroundTruth] {
        let files = FileManager.default.enumerator(at: truthDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasSuffix(".truth.json") } ?? []
        let decoder = JSONDecoder()
        return try files.map { try decoder.decode(GroundTruth.self, from: Data(contentsOf: $0)) }
            .sorted { $0.id < $1.id }
    }

    public func truths(inSet set: String) throws -> [GroundTruth] {
        try allTruths().filter { $0.set == set }
    }

    public func truth(id: String) throws -> GroundTruth {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw MediaFixtureError.unknownTruth(id) }
        let url = truthDirectory.appendingPathComponent(parts[0]).appendingPathComponent("\(parts[1]).truth.json")
        guard let data = try? Data(contentsOf: url) else { throw MediaFixtureError.unknownTruth(id) }
        return try JSONDecoder().decode(GroundTruth.self, from: data)
    }

    /// The rendered media file. Throws `notRendered` (with the command to run) when the cache lacks it.
    public func mediaURL(for truth: GroundTruth) throws -> URL {
        let url = root.appendingPathComponent(truth.media.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaFixtureError.notRendered(path: truth.media.path)
        }
        return url
    }
}
