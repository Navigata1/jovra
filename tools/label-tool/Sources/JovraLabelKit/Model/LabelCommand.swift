import Foundation
import JovraBenchmark

/// Everything the labelling tool can be asked to do. Keys, menu items and tests all go through these.
public enum LabelCommand: Hashable, Sendable {
    case playPause
    case step(frames: Int)
    case jump(seconds: Int)
    case slower
    case faster
    case markHit(BenchmarkLabels.Player)
    case setStroke(BenchmarkLabels.Stroke?)
    case markBounce
    case toggleInPlay
    case markCorner
    case skipCorner
    case newCameraPosition
    case rallyStart
    case rallyEnd
    case nextCandidate
    case previousCandidate
    case rejectCandidate
    case nextLabel
    case previousLabel
    case deleteSelected
    case cancelPlacement
    case undo
    case redo
    case save
    case open
}

/// One keyboard shortcut. `key` is the character the key produces without modifiers, or a named key.
public struct KeyStroke: Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case character(Character)
        case space, left, right, up, down, delete, escape
    }

    public let key: Key
    public let shift: Bool
    public let command: Bool
    public let option: Bool

    public init(_ key: Key, shift: Bool = false, command: Bool = false, option: Bool = false) {
        self.key = key
        self.shift = shift
        self.command = command
        self.option = option
    }

    /// How the shortcut is shown on screen, e.g. "H", "⇧→", "⌘Z".
    public var display: String {
        let name: String
        switch key {
        case .character(let c): name = String(c).uppercased()
        case .space: name = "Space"
        case .left: name = "←"
        case .right: name = "→"
        case .up: name = "↑"
        case .down: name = "↓"
        case .delete: name = "⌫"
        case .escape: name = "Esc"
        }
        return (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + name
    }

    /// How VoiceOver should say it.
    public var spoken: String {
        let name: String
        switch key {
        case .character(let c): name = String(c).uppercased()
        case .space: name = "Space"
        case .left: name = "Left arrow"
        case .right: name = "Right arrow"
        case .up: name = "Up arrow"
        case .down: name = "Down arrow"
        case .delete: name = "Delete"
        case .escape: name = "Escape"
        }
        return [option ? "Option" : nil, shift ? "Shift" : nil, command ? "Command" : nil, name].compactMap { $0 }.joined(separator: " ")
    }
}

/// The one table of shortcuts: the key handler, the menu and the on-screen legend all read it, so what the
/// legend says is what the keys do.
public enum LabelKeymap {
    public struct Binding: Hashable, Sendable {
        public let stroke: KeyStroke
        public let command: LabelCommand
        public let title: String
    }

    public struct Section: Hashable, Sendable {
        public let title: String
        public let bindings: [Binding]
    }

    private static func bind(_ key: KeyStroke.Key, shift: Bool = false, command: Bool = false, option: Bool = false,
                             _ action: LabelCommand, _ title: String) -> Binding {
        Binding(stroke: KeyStroke(key, shift: shift, command: command, option: option), command: action, title: title)
    }

    public static let sections: [Section] = [
        Section(title: "Move", bindings: [
            bind(.space, .playPause, "Play or pause"),
            bind(.right, .step(frames: 1), "Next frame"),
            bind(.left, .step(frames: -1), "Previous frame"),
            bind(.right, shift: true, .step(frames: 10), "Forward 10 frames"),
            bind(.left, shift: true, .step(frames: -10), "Back 10 frames"),
            bind(.right, option: true, .jump(seconds: 1), "Forward 1 second"),
            bind(.left, option: true, .jump(seconds: -1), "Back 1 second"),
            bind(.character("-"), .slower, "Slower"),
            bind(.character("="), .faster, "Faster"),
        ]),
        Section(title: "Mark", bindings: [
            bind(.character("h"), .markHit(.near), "Hit, near player"),
            bind(.character("j"), .markHit(.far), "Hit, far player"),
            bind(.character("b"), .markBounce, "Bounce at the pointer"),
            bind(.character("x"), .toggleInPlay, "Bounce in play / dead ball"),
            bind(.character("["), .rallyStart, "Rally starts"),
            bind(.character("]"), .rallyEnd, "Rally ends"),
        ]),
        Section(title: "Stroke type of the selected hit", bindings: [
            bind(.character("1"), .setStroke(.serve), "Serve"),
            bind(.character("2"), .setStroke(.forehand), "Forehand"),
            bind(.character("3"), .setStroke(.backhand), "Backhand"),
            bind(.character("4"), .setStroke(.volley), "Volley"),
            bind(.character("5"), .setStroke(.overhead), "Overhead"),
            bind(.character("6"), .setStroke(.other), "Other"),
            bind(.character("0"), .setStroke(nil), "Clear"),
        ]),
        Section(title: "Court", bindings: [
            bind(.character("c"), .markCorner, "Next court corner at the pointer"),
            bind(.character("v"), .skipCorner, "Corner not visible"),
            bind(.character("m"), .newCameraPosition, "Camera moved: new corners from here"),
        ]),
        Section(title: "Hit candidates", bindings: [
            bind(.character("n"), .nextCandidate, "Next candidate"),
            bind(.character("p"), .previousCandidate, "Previous candidate"),
            bind(.character("r"), .rejectCandidate, "Not a hit: reject"),
        ]),
        Section(title: "Edit", bindings: [
            bind(.character("."), .nextLabel, "Next label"),
            bind(.character(","), .previousLabel, "Previous label"),
            bind(.delete, .deleteSelected, "Delete the selected label"),
            bind(.escape, .cancelPlacement, "Cancel placing"),
            bind(.character("z"), command: true, .undo, "Undo"),
            bind(.character("z"), shift: true, command: true, .redo, "Redo"),
            bind(.character("s"), command: true, .save, "Save"),
            bind(.character("o"), command: true, .open, "Open a recording"),
        ]),
    ]

    public static let bindings: [Binding] = sections.flatMap(\.bindings)

    private static let table: [KeyStroke: LabelCommand] = Dictionary(uniqueKeysWithValues: bindings.map { ($0.stroke, $0.command) })

    public static func command(for stroke: KeyStroke) -> LabelCommand? {
        table[stroke]
    }

    public static func stroke(for command: LabelCommand) -> KeyStroke? {
        bindings.first { $0.command == command }?.stroke
    }
}
