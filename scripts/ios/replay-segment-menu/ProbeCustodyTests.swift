import Foundation

enum ControlError: Error { case expectedCondition, unexpectedSuccess }

@main
struct ProbeCustodyTests {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw ControlError.expectedCondition }
        let seed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let media = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        try ProbeFixture.verify(session: seed, media: media)
        try refuses("changed session bytes") { try ProbeFixture.verify(session: seed + Data([0]), media: media) }
        try refuses("changed media bytes") { try ProbeFixture.verify(session: seed, media: media + Data([0])) }

        let files = FileManager.default
        let scratch = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: scratch) }
        let home = scratch.resolvingSymlinksInPath()
        let library = home.appendingPathComponent("Library", isDirectory: true)
        try files.createDirectory(at: library, withIntermediateDirectories: false)
        let name = "JOVRA-SegmentMenu-tests"
        let root = try ProbeRoot.create(home: home, name: name)
        defer { root.close() }

        let originals = root.url.appendingPathComponent("originals", isDirectory: true)
        try files.createDirectory(at: originals, withIntermediateDirectories: false)
        try root.requireAbsent(folders: ["originals"], leaf: "segment-0.mp4")
        try root.write(media, folders: ["originals"], leaf: "segment-1.mp4")
        let stored = originals.appendingPathComponent("segment-1.mp4")
        try check("later original exact and earlier original still absent") {
            try root.requireAbsent(folders: ["originals"], leaf: "segment-0.mp4")
            return try Data(contentsOf: stored) == media
        }
        try refuses("existing original cannot be overwritten") {
            try root.write(Data([1]), folders: ["originals"], leaf: "segment-1.mp4")
        }
        try check("existing original remains exact") { try Data(contentsOf: stored) == media }
        try refuses("present original cannot be reported absent") {
            try root.requireAbsent(folders: ["originals"], leaf: "segment-1.mp4")
        }
        try refuses("existing root cannot be reinitialized") {
            let reopened = try ProbeRoot.create(home: home, name: name)
            reopened.close()
        }
        try refuses("parent traversal cannot write outside the root") {
            try root.write(Data([2]), folders: [".."], leaf: "unexpected")
        }

        let foreign = home.appendingPathComponent("foreign", isDirectory: true)
        try files.createDirectory(at: foreign, withIntermediateDirectories: false)
        let sentinel = foreign.appendingPathComponent("sentinel")
        try Data([3]).write(to: sentinel)
        try files.createSymbolicLink(at: root.url.appendingPathComponent("alias"), withDestinationURL: foreign)
        try refuses("linked descendant cannot receive writes") {
            try root.write(Data([4]), folders: ["alias"], leaf: "sentinel")
        }
        try check("foreign target remains exact") {
            try files.contentsOfDirectory(atPath: foreign.path) == ["sentinel"] && Data(contentsOf: sentinel) == Data([3])
        }

        let detached = home.appendingPathComponent("detached", isDirectory: true)
        try files.moveItem(at: root.url, to: detached)
        try files.moveItem(at: foreign, to: root.url)
        try refuses("ordinary replacement root cannot receive writes") {
            try root.write(Data([5]), folders: [], leaf: "unexpected")
        }
        try check("replacement and detached root remain untouched") {
            try files.contentsOfDirectory(atPath: root.url.path) == ["sentinel"]
                && Data(contentsOf: root.url.appendingPathComponent("sentinel")) == Data([3])
                && !files.fileExists(atPath: detached.appendingPathComponent("unexpected").path)
        }

        try files.moveItem(at: library, to: home.appendingPathComponent("detached-Library"))
        try files.createSymbolicLink(at: library, withDestinationURL: root.url.deletingLastPathComponent().deletingLastPathComponent())
        try refuses("linked Library cannot receive a new root") {
            let unsafe = try ProbeRoot.create(home: home, name: "unexpected")
            unsafe.close()
        }
        try check("linked Library target remains untouched") { !files.fileExists(atPath: home.appendingPathComponent("unexpected").path) }
    }

    private static func check(_ name: String, _ condition: () throws -> Bool) throws {
        guard try condition() else { throw ControlError.expectedCondition }
        print("PASS \(name)")
    }

    private static func refuses(_ name: String, _ action: () throws -> Void) throws {
        do { try action() }
        catch is ProbeCustodyError {
            print("PASS \(name)")
            return
        }
        throw ControlError.unexpectedSuccess
    }
}
