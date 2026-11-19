import AppKit
import SwiftUI

extension KeyStroke {
    /// The shortcut a key-down event stands for, or nil for a key the tool has no name for.
    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.control) else { return nil }
        let key: Key
        switch event.keyCode {
        case 49: key = .space
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 51, 117: key = .delete
        case 53: key = .escape
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
            key = .character(character)
        }
        self.init(key, shift: flags.contains(.shift), command: flags.contains(.command), option: flags.contains(.option))
    }
}

/// The labelling window. Every key goes to the keymap first, wherever the keyboard focus happens to be, so
/// one key always does one thing; only a text field being edited keeps its keys.
public final class LabelWindow: NSWindow {
    public var session: LabelSession?

    private var isEditingText: Bool { firstResponder is NSText }

    public override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if !isEditingText, let stroke = KeyStroke(event: event), !stroke.command,
               let command = LabelKeymap.command(for: stroke), let session {
                MainActor.assumeIsolated { session.perform(command) }
                return
            }
        case .leftMouseDown:
            // A click on the picture is a label point, whatever is laid out around the picture.
            if attachedSheet == nil, let session, let point = picture?.imagePoint(atWindowLocation: event.locationInWindow) {
                if !isKeyWindow, isVisible { makeKeyAndOrderFront(nil) }
                MainActor.assumeIsolated { session.pointerClicked(at: point) }
                return
            }
        case .mouseMoved, .mouseEntered, .mouseExited:
            if let session {
                let point = picture?.imagePoint(atWindowLocation: event.locationInWindow)
                MainActor.assumeIsolated { if session.pointer != point { session.pointer = point } }
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private weak var cachedPicture: PointerCatcherView?

    /// The view that marks the picture's place, once a frame is on screen.
    var picture: PointerCatcherView? {
        if let cachedPicture, cachedPicture.window === self { return cachedPicture }
        func find(_ view: NSView) -> PointerCatcherView? {
            if let found = view as? PointerCatcherView { return found }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        cachedPicture = contentView.flatMap(find)
        return cachedPicture
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, let stroke = KeyStroke(event: event), stroke.command,
           let command = LabelKeymap.command(for: stroke), let session {
            MainActor.assumeIsolated { session.perform(command) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the window and the session, and asks before closing with unsaved labels.
@MainActor
public final class LabelWindowController: NSObject, NSWindowDelegate {
    public let session: LabelSession
    public let window: LabelWindow

    public init(session: LabelSession, colorScheme: ColorScheme? = nil) {
        self.session = session
        window = LabelWindow(contentRect: NSRect(origin: .zero, size: Self.initialContentSize()),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.session = session
        window.title = "JOVRA Label"
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.contentMinSize = Self.minimumContentSize
        let hosting = NSHostingView(rootView: LabelToolView(session: session).preferredColorScheme(colorScheme))
        // The window owns its size: without this the hosting view grows it to fit the whole key legend.
        hosting.sizingOptions = []
        hosting.setAccessibilityLabel("Labelling workspace")
        window.contentView = hosting
        window.delegate = self
        window.center()
        session.onOpenRequested = { [weak self] in self?.chooseRecording() }
    }

    public static let minimumContentSize = NSSize(width: 1040, height: 640)

    /// 1320 x 820 where the screen has room, and never larger than the screen.
    public static func initialContentSize(screen: NSSize? = NSScreen.main?.visibleFrame.size) -> NSSize {
        let room = screen ?? NSSize(width: 1440, height: 900)
        return NSSize(width: min(1320, max(minimumContentSize.width, room.width - 40)),
                      height: min(820, max(minimumContentSize.height, room.height - 60)))
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func chooseRecording() {
        let panel = NSOpenPanel()
        panel.title = "Open a recording"
        panel.message = "The recording is read on this Mac. Only labels (times and points) are saved."
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.session.open(video: url) }
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard session.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save your labels before closing?"
        alert.informativeText = "Labels you marked since the last save will be lost if you do not save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return session.save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
