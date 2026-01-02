import SwiftUI

// MARK: - Note Data Model
struct NoteData: Codable, Identifiable {
    let id: UUID
    var content: String
    var selectedFont: String
    var fontSize: Double
    var fontColorName: String
    var backgroundColorName: String
    var alwaysOnTop: Bool
    var windowFrame: CGRect?

    init(id: UUID = UUID(),
         content: String = "",
         selectedFont: String = "regular",
         fontSize: Double = 24,
         fontColorName: String = "blue",
         backgroundColorName: String = "yellow",
         alwaysOnTop: Bool = true,
         windowFrame: CGRect? = nil) {
        self.id = id
        self.content = content
        self.selectedFont = selectedFont
        self.fontSize = fontSize
        self.fontColorName = fontColorName
        self.backgroundColorName = backgroundColorName
        self.alwaysOnTop = alwaysOnTop
        self.windowFrame = windowFrame
    }
}

@main
struct CoolQuickNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Note") {
                    appDelegate.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notePanels: [UUID: NSPanel] = [:]
    private let notesKey = "savedNotes"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load existing notes or create a default one
        let savedNotes = loadNotes()

        if savedNotes.isEmpty {
            // First launch - create a default note
            createNewNote()
        } else {
            // Restore saved notes
            for noteData in savedNotes {
                createNotePanel(with: noteData)
            }
        }
    }

    func createNewNote() {
        let noteData = NoteData()
        createNotePanel(with: noteData)
        saveNotes()
    }

    private func createNotePanel(with noteData: NoteData) {
        // Create a floating panel
        let initialFrame = noteData.windowFrame ?? NSRect(x: 0, y: 0, width: 300, height: 300)
        let panel = ActivatingPanel(
            contentRect: initialFrame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure panel to appear on all spaces including full screen
        panel.title = "CoolQuickNote"
        panel.isFloatingPanel = true
        panel.level = noteData.alwaysOnTop ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow))) : .normal
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

        // Set SwiftUI content with note ID
        let hostingView = NSHostingView(rootView: ContentView(noteId: noteData.id, appDelegate: self))
        panel.contentView = hostingView

        // Apply corner radius
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 8
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        // Set up close handler
        panel.noteId = noteData.id

        if noteData.windowFrame == nil {
            panel.center()
        }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        notePanels[noteData.id] = panel
    }

    func closeNote(id: UUID) {
        if let panel = notePanels[id] {
            // Save window frame before closing
            saveNoteWindowFrame(id: id, frame: panel.frame)
            panel.close()
            notePanels.removeValue(forKey: id)
            saveNotes()
        }
    }

    func updateWindowLevel(for noteId: UUID, alwaysOnTop: Bool) {
        guard let panel = notePanels[noteId] else { return }
        panel.level = alwaysOnTop ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow))) : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        saveNotes()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save all note window positions before quitting
        for (id, panel) in notePanels {
            saveNoteWindowFrame(id: id, frame: panel.frame)
        }
        saveNotes()
    }

    // MARK: - Persistence
    private func loadNotes() -> [NoteData] {
        guard let data = UserDefaults.standard.data(forKey: notesKey),
              let notes = try? JSONDecoder().decode([NoteData].self, from: data) else {
            return []
        }
        return notes
    }

    private func saveNotes() {
        var notes: [NoteData] = []

        for (id, panel) in notePanels {
            let note = NoteData(
                id: id,
                content: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_content") ?? "",
                selectedFont: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_font") ?? "regular",
                fontSize: UserDefaults.standard.double(forKey: "note_\(id.uuidString)_fontSize") != 0 ? UserDefaults.standard.double(forKey: "note_\(id.uuidString)_fontSize") : 24,
                fontColorName: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_fontColor") ?? "blue",
                backgroundColorName: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_backgroundColor") ?? "yellow",
                alwaysOnTop: UserDefaults.standard.bool(forKey: "note_\(id.uuidString)_alwaysOnTop"),
                windowFrame: panel.frame
            )
            notes.append(note)
        }

        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: notesKey)
        }
    }

    private func saveNoteWindowFrame(id: UUID, frame: CGRect) {
        var notes = loadNotes()
        if let index = notes.firstIndex(where: { $0.id == id }) {
            notes[index].windowFrame = frame
            if let encoded = try? JSONEncoder().encode(notes) {
                UserDefaults.standard.set(encoded, forKey: notesKey)
            }
        }
    }
}

// Custom panel class copied from CoolClockPresence for full screen compatibility
private final class ActivatingPanel: NSPanel {
    var noteId: UUID?
    private var trackingArea: NSTrackingArea?

    override func awakeFromNib() {
        super.awakeFromNib()
        setupTrackingArea()
        hideWindowButtons()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        if trackingArea == nil {
            setupTrackingArea()
            hideWindowButtons()
        }
    }

    private func setupTrackingArea() {
        // Remove existing tracking area if any
        if let existingArea = trackingArea {
            contentView?.removeTrackingArea(existingArea)
        }

        // Create tracking area for the entire window to detect hover
        let area = NSTrackingArea(
            rect: NSRect(x: 0, y: 0, width: frame.width, height: frame.height),
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView?.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        showWindowButtons()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideWindowButtons()
    }

    private func hideWindowButtons() {
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func showWindowButtons() {
        standardWindowButton(.closeButton)?.isHidden = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden = false
    }

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
