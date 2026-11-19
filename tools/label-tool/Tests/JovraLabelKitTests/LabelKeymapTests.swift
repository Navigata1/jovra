import AppKit
import JovraBenchmark
@testable import JovraLabelKit
import Testing

@Suite("Label keymap")
struct LabelKeymapTests {
    @Test("no key is bound twice and no command has two keys")
    func unique() {
        #expect(Set(LabelKeymap.bindings.map(\.stroke)).count == LabelKeymap.bindings.count)
        #expect(Set(LabelKeymap.bindings.map(\.command)).count == LabelKeymap.bindings.count)
    }

    @Test("a hit, a bounce, each stroke type and a court corner take one unmodified key each")
    func oneKeyEach() {
        var needed: [LabelCommand] = [.markHit(.near), .markHit(.far), .markBounce, .markCorner, .rallyStart, .rallyEnd]
        needed += BenchmarkLabels.Stroke.allCases.map { .setStroke($0) }
        for command in needed {
            let stroke = LabelKeymap.stroke(for: command)
            #expect(stroke != nil, "\(command)")
            #expect(stroke?.shift == false && stroke?.command == false && stroke?.option == false, "\(command)")
            if case .character = stroke?.key {} else { Issue.record("\(command) is not a character key") }
        }
        #expect(LabelKeymap.stroke(for: .undo) == KeyStroke(.character("z"), command: true))
        #expect(LabelKeymap.stroke(for: .redo) == KeyStroke(.character("z"), shift: true, command: true))
        #expect(LabelKeymap.stroke(for: .save) == KeyStroke(.character("s"), command: true))
        #expect(LabelKeymap.stroke(for: .step(frames: 1)) == KeyStroke(.right))
        #expect(LabelKeymap.stroke(for: .step(frames: -1)) == KeyStroke(.left))
    }

    @Test("the legend shows every binding with a readable key name")
    func legend() {
        #expect(LabelKeymap.sections.map(\.title) == ["Move", "Mark", "Stroke type of the selected hit", "Court", "Hit candidates", "Edit"])
        #expect(LabelKeymap.bindings.allSatisfy { !$0.title.isEmpty && !$0.stroke.display.isEmpty && !$0.stroke.spoken.isEmpty })
        #expect(KeyStroke(.character("h")).display == "H")
        #expect(KeyStroke(.right, shift: true).display == "⇧→")
        #expect(KeyStroke(.character("z"), shift: true, command: true).display == "⇧⌘Z")
        #expect(KeyStroke(.left, option: true).spoken == "Option Left arrow")
    }

    static func event(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    @Test("key events map to shortcuts: letters whatever the caps state, arrows and space by key code, control ignored")
    func events() {
        #expect(KeyStroke(event: Self.event("h", keyCode: 4)) == KeyStroke(.character("h")))
        #expect(KeyStroke(event: Self.event("H", keyCode: 4, flags: .capsLock)) == KeyStroke(.character("h")))
        #expect(KeyStroke(event: Self.event(" ", keyCode: 49)) == KeyStroke(.space))
        #expect(KeyStroke(event: Self.event("\u{F703}", keyCode: 124, flags: [.shift, .numericPad, .function])) == KeyStroke(.right, shift: true))
        #expect(KeyStroke(event: Self.event("z", keyCode: 6, flags: [.command, .shift])) == KeyStroke(.character("z"), shift: true, command: true))
        #expect(KeyStroke(event: Self.event("\u{7F}", keyCode: 51)) == KeyStroke(.delete))
        #expect(KeyStroke(event: Self.event("h", keyCode: 4, flags: .control)) == nil)
        #expect(LabelKeymap.command(for: KeyStroke(.character("h"), shift: true)) == nil)
    }

    @Test("launch options read the script's arguments")
    func launchOptions() {
        let options = LaunchOptions(arguments: ["jovra-label", "--open", "/tmp/a.mp4", "--labels-dir", "/tmp/labels", "--no-autosave", "--mute", "--no-candidates"])
        #expect(options.video?.path == "/tmp/a.mp4")
        #expect(options.configuration.labelsDirectory.path == "/tmp/labels")
        #expect(!options.configuration.autosave && options.configuration.muted && !options.configuration.findCandidates)
        let plain = LaunchOptions(arguments: ["jovra-label"])
        #expect(plain.video == nil && plain.configuration.autosave && !plain.configuration.muted && plain.configuration.findCandidates)
    }
}

@Suite("Label tool menu")
@MainActor
struct LabelToolMenuTests {
    @Test("the menu bar lists every shortcut of the keymap, and choosing an item runs its command")
    func menu() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("jovra-label-menu-\(UUID().uuidString)")
        let session = LabelSession(configuration: .init(labelsDirectory: scratch))
        let menu = LabelToolMenu.build(session: session)
        #expect(menu.items.map(\.title) == ["JOVRA Label", "Move", "Mark", "Stroke", "Court", "Candidates", "Edit"])
        let items = menu.items.dropFirst().flatMap { $0.submenu?.items ?? [] }
        #expect(items.map(\.title) == LabelKeymap.bindings.map(\.title))
        #expect(items.allSatisfy { !$0.keyEquivalent.isEmpty })
        let save = try #require(items.first { $0.title == "Save" })
        #expect(save.keyEquivalent == "s" && save.keyEquivalentModifierMask == [.command])
        let redo = try #require(items.first { $0.title == "Redo" })
        #expect(redo.keyEquivalentModifierMask == [.command, .shift])
        var asked = 0
        session.onOpenRequested = { asked += 1 }
        let open = try #require(items.first { $0.title == "Open a recording" })
        #expect(NSApplication.shared.sendAction(try #require(open.action), to: open.target, from: open))
        #expect(asked == 1)
    }
}
