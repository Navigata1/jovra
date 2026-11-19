import AppKit
import SwiftUI

/// What the tool was launched with: `--open VIDEO`, `--labels-dir DIR`, `--no-autosave`, `--mute`,
/// `--no-candidates`.
public struct LaunchOptions: Equatable, Sendable {
    public var video: URL?
    public var labelsDirectory: URL?
    public var autosave = true
    public var muted = false
    public var findCandidates = true

    public init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--open": video = iterator.next().map { URL(fileURLWithPath: $0) }
            case "--labels-dir": labelsDirectory = iterator.next().map { URL(fileURLWithPath: $0, isDirectory: true) }
            case "--no-autosave": autosave = false
            case "--mute": muted = true
            case "--no-candidates": findCandidates = false
            default: break
            }
        }
    }

    public var configuration: LabelSession.Configuration {
        var configuration = LabelSession.Configuration()
        if let labelsDirectory { configuration.labelsDirectory = labelsDirectory }
        configuration.autosave = autosave
        configuration.muted = muted
        configuration.findCandidates = findCandidates
        return configuration
    }
}

@MainActor
public final class LabelToolAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: LabelWindowController?
    private let options: LaunchOptions

    public init(options: LaunchOptions) {
        self.options = options
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let session = LabelSession(configuration: options.configuration)
        let controller = LabelWindowController(session: session)
        self.controller = controller
        NSApp.mainMenu = LabelToolMenu.build(session: session)
        controller.show()
        if let video = options.video {
            Task { await session.open(video: video) }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    public func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        guard let controller else { return false }
        Task { await controller.session.open(video: URL(fileURLWithPath: filename)) }
        return true
    }
}

/// The menu bar: the same commands as the keys, so every shortcut can be found by reading the menus.
@MainActor
public enum LabelToolMenu {
    final class Item: NSMenuItem {
        var command: LabelCommand?
        weak var session: LabelSession?

        @MainActor @objc func run() {
            if let command { session?.perform(command) }
        }
    }

    public static func build(session: LabelSession) -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "About JOVRA Label", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide JOVRA Label", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command]
        app.addItem(withTitle: "Quit JOVRA Label", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "JOVRA Label"))
        for section in LabelKeymap.sections {
            let menu = NSMenu(title: section.title)
            for binding in section.bindings {
                let item = Item(title: binding.title, action: #selector(Item.run), keyEquivalent: keyEquivalent(binding.stroke))
                item.target = item
                item.command = binding.command
                item.session = session
                var mask: NSEvent.ModifierFlags = []
                if binding.stroke.shift { mask.insert(.shift) }
                if binding.stroke.command { mask.insert(.command) }
                if binding.stroke.option { mask.insert(.option) }
                item.keyEquivalentModifierMask = mask
                menu.addItem(item)
            }
            main.addItem(submenu(menu, title: menuTitle(section.title)))
        }
        return main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    private static func menuTitle(_ section: String) -> String {
        section.hasPrefix("Stroke type") ? "Stroke" : (section == "Hit candidates" ? "Candidates" : section)
    }

    private static func keyEquivalent(_ stroke: KeyStroke) -> String {
        switch stroke.key {
        case .character(let c): String(c)
        case .space: " "
        case .left: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case .right: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case .up: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case .down: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case .delete: String(UnicodeScalar(NSBackspaceCharacter)!)
        case .escape: "\u{1b}"
        }
    }

    /// Starts the app: called from the executable's `main.swift`.
    public static func runApplication(arguments: [String] = CommandLine.arguments) {
        let app = NSApplication.shared
        let delegate = LabelToolAppDelegate(options: LaunchOptions(arguments: arguments))
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
