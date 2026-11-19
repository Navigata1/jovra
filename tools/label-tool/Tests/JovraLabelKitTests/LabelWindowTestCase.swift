import AppKit
import JovraBenchmark
@testable import JovraLabelKit
import SwiftUI
import XCTest

/// Drives the real label window in-process: key-down and mouse-down events take the same route as in the
/// running app (`LabelWindow.sendEvent` and `performKeyEquivalent`); nothing calls the session's commands.
@MainActor
class LabelWindowTestCase: XCTestCase {
    var scratch: URL!
    var controller: LabelWindowController!
    var session: LabelSession { controller.session }

    override func setUp() async throws {
        scratch = try SampleVideo.scratchDirectory()
        _ = NSApplication.shared
    }

    override func tearDown() async throws {
        controller?.window.orderOut(nil)
        controller = nil
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: Driving the window

    func openSample(autosave: Bool = false, findCandidates: Bool = true) async throws {
        try await open(try SampleVideo.url(), autosave: autosave, findCandidates: findCandidates)
    }

    /// Opens a recording in a fresh window. With `settled` false it returns as soon as the first frame is up,
    /// while the search for hit candidates is still running.
    func open(_ url: URL, autosave: Bool = false, findCandidates: Bool = true, settled: Bool = true) async throws {
        var configuration = LabelSession.Configuration(labelsDirectory: scratch)
        configuration.autosave = autosave
        configuration.muted = true
        configuration.findCandidates = findCandidates
        controller = LabelWindowController(session: LabelSession(configuration: configuration))
        controller.window.layoutIfNeeded()
        await session.open(video: url)
        XCTAssertEqual(session.phase, .ready)
        guard settled else { return }
        try await wait("the first frame") { self.session.frame != nil }
        await session.candidatesSettled()
        controller.window.contentView?.layoutSubtreeIfNeeded()
    }

    func wait(_ what: String, timeout: TimeInterval = 30, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what); frame time is \(session.displayedTime)")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    static let keyCodes: [KeyStroke.Key: UInt16] = [.space: 49, .left: 123, .right: 124, .down: 125, .up: 126, .delete: 51, .escape: 53]

    /// Sends one key-down the way AppKit routes it: a Command shortcut to `performKeyEquivalent`, any other key
    /// to `sendEvent`.
    func press(_ key: KeyStroke.Key, shift: Bool = false, command: Bool = false, option: Bool = false) {
        var flags: NSEvent.ModifierFlags = []
        if shift { flags.insert(.shift) }
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        let characters: String
        if case .character(let c) = key { characters = String(c) } else { characters = key == .space ? " " : "\u{F700}" }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: controller.window.windowNumber, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: Self.keyCodes[key] ?? 0)!
        if command {
            XCTAssertTrue(controller.window.performKeyEquivalent(with: event), "⌘\(characters) is handled")
        } else {
            controller.window.sendEvent(event)
        }
    }

    func press(_ character: Character) {
        press(.character(character))
    }

    /// Steps and waits for the frame that lands on screen.
    func step(_ frames: Int64, shift: Bool = false, to expected: Int64) async throws {
        press(frames > 0 ? .right : .left, shift: shift)
        try await wait("frame \(expected)") { self.session.displayedTime == SampleVideo.frame(expected) }
    }

    /// Clicks the picture at a normalized image point with a real mouse-down event sent to the window.
    func click(x: Double, y: Double) throws {
        controller.window.contentView?.layoutSubtreeIfNeeded()
        let picture = try XCTUnwrap(controller.window.picture, "the picture is in the window")
        XCTAssertGreaterThan(picture.bounds.width, 100)
        let inWindow = picture.convert(NSPoint(x: picture.bounds.width * x, y: picture.bounds.height * y), to: nil)
        controller.window.sendEvent(mouse(.leftMouseDown, at: inWindow))
    }

    func mouse(_ type: NSEvent.EventType, at location: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: controller.window.windowNumber, context: nil, eventNumber: 0, clickCount: type == .mouseMoved ? 0 : 1,
                           pressure: type == .mouseMoved ? 0 : 1)!
    }

    /// Moves the pointer over the picture (or, outside 0...1, off it).
    func hover(x: Double, y: Double) throws {
        let picture = try XCTUnwrap(controller.window.picture)
        let inWindow = picture.convert(NSPoint(x: picture.bounds.width * x, y: picture.bounds.height * y), to: nil)
        controller.window.sendEvent(mouse(.mouseMoved, at: inWindow))
    }

    func savedLabels() throws -> BenchmarkLabels {
        let url = try XCTUnwrap(session.labelsURL)
        return try JSONDecoder().decode(BenchmarkLabels.self, from: Data(contentsOf: url))
    }
}
