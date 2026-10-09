import Foundation
import Darwin
import Testing
import JovraMedia

private func layoutFile(_ bytes: [UInt8], body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(bytes).write(to: url)
    try body(url)
}

@Test func fragmentLayoutKeepsOnlyCompletePairsAndRejectsUnboundedSizes() throws {
    // Explicit container-layout bytes, not playable-video fixtures or recovery/decode evidence.
    let complete: [UInt8] = [0,0,0,8,102,116,121,112, 0,0,0,8,109,111,111,118,
                            0,0,0,8,109,111,111,102, 0,0,0,8,109,100,97,116]
    try layoutFile(complete) { url in
        let layout = try FragmentedMovieLayout.inspect(url)
        #expect(layout.completeFragmentEnds == [32])
        #expect(!layout.hasIncompleteTail)
    }
    try layoutFile(complete + [0,0,0,8,109,111,111,102, 0,0,0,20,109,100,97,116, 42]) { url in
        let layout = try FragmentedMovieLayout.inspect(url)
        #expect(layout.completeFragmentEnds == [32])
        #expect(layout.hasIncompleteTail)
    }
    for malformed in [[0,0,0,4,102,116,121,112], [0,0,0,1,102,116,121,112,255,255,255,255,255,255,255,255],
                      [0,0,0,0,102,116,121,112], [0,0,0,8,109,100,97,116]] as [[UInt8]] {
        try layoutFile(malformed) { url in
            #expect(throws: (any Error).self) { try FragmentedMovieLayout.inspect(url) }
        }
    }
}

@Test func fragmentLayoutRefusesLinksAndIncompleteHeaders() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let source = directory.appendingPathComponent("source.mp4"), link = directory.appendingPathComponent("link.mp4")
    try Data([0,0,0,8,102,116,121,112, 0,0,0,8,109,111,111,118]).write(to: source)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    #expect(throws: (any Error).self) { try FragmentedMovieLayout.inspect(link) }
    for bytes in [Data(), Data([0,0,0]), Data([0,0,0,1,102,116,121,112])] {
        try bytes.write(to: source)
        #expect(throws: (any Error).self) { try FragmentedMovieLayout.inspect(source) }
    }
}

@Test func fragmentLayoutRefusesNamedPipesWithoutWaitingForWriter() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fifo = directory.appendingPathComponent("not-a-movie.mp4")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    if let marker = ProcessInfo.processInfo.environment["JOVRA_FIFO_CONTROL_MARKER"] {
        try Data("Inspecting owned FIFO without a writer: \(fifo.path)".utf8).write(to: URL(fileURLWithPath: marker))
    }
    #expect(throws: FragmentedMovieLayoutError.unsafePath) { try FragmentedMovieLayout.inspect(fifo) }
}
