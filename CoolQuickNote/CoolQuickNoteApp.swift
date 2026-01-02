import SwiftUI

@main
struct CoolQuickNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notePanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showNotePanel()
    }

    func showNotePanel() {
        // Create a floating panel - exact copy from CoolClockPresence
        let panel = ActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure panel to appear on all spaces including full screen (copied from CoolClock)
        panel.title = "CoolQuickNote"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isRestorable = false

        // Set size constraints
        panel.contentMinSize = CGSize(width: 200, height: 200)

        // Set SwiftUI content
        let hostingView = NSHostingView(rootView: ContentView())
        panel.contentView = hostingView

        // Apply corner radius
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 8
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        panel.center()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        notePanel = panel

        // Update level based on alwaysOnTop setting
        updateWindowLevel(alwaysOnTop: UserDefaults.standard.bool(forKey: "alwaysOnTop"))
    }

    func updateWindowLevel(alwaysOnTop: Bool) {
        guard let panel = notePanel else { return }
        // Use high window level for full screen compatibility when always on top
        panel.level = alwaysOnTop ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow))) : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// Custom panel class copied from CoolClockPresence for full screen compatibility
private final class ActivatingPanel: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            NSApp.activate(ignoringOtherApps: true)
        default:
            break
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool {
        true
    }

    override var acceptsMouseMovedEvents: Bool {
        get { true }
        set { }
    }
}
