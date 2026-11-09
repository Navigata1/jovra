import Foundation

/// T10's rendered frame-counter fixtures, located from the repository's committed ground truth. Media is never
/// committed or bundled; on the simulator the app reads the rendered files from the host's git-ignored cache.
enum FrameCounterFixtures {
    /// The folder holding frame-counter-060fps.mp4 and frame-counter-240fps.mp4, or nil when they are not rendered
    /// (run `python3 scripts/media/render.py --set frameCounter`).
    static func directory(filePath: String = #filePath) -> URL? {
        var root = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/media").path) {
            root.deleteLastPathComponent()
        }
        let truth = root.appendingPathComponent("spec/fixtures/media/frameCounter/fc-060.truth.json")
        guard let data = try? Data(contentsOf: truth),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let media = json["media"] as? [String: Any], let path = media["path"] as? String else { return nil }
        let file = root.appendingPathComponent(path)
        let folder = file.deletingLastPathComponent()
        let both = ["frame-counter-060fps.mp4", "frame-counter-240fps.mp4"]
            .allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        return both ? folder : nil
    }
}
