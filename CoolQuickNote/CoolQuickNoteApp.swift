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
    var dynamicSizingEnabled: Bool
    var noteOpacity: Double
    var windowFrame: CGRect?

    init(id: UUID = UUID(),
         content: String = "",
         selectedFont: String = "regular",
         fontSize: Double = 24,
         fontColorName: String = "blue",
         backgroundColorName: String = "yellow",
         alwaysOnTop: Bool = true,
         dynamicSizingEnabled: Bool = true,
         noteOpacity: Double = 1.0,
         windowFrame: CGRect? = nil) {
        self.id = id
        self.content = content
        self.selectedFont = selectedFont
        self.fontSize = fontSize
        self.fontColorName = fontColorName
        self.backgroundColorName = backgroundColorName
        self.alwaysOnTop = alwaysOnTop
        self.dynamicSizingEnabled = dynamicSizingEnabled
        self.noteOpacity = noteOpacity
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

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var notePanels: [UUID: NSPanel] = [:]
    private let notesKey = "savedNotes"
    private var statusItem: NSStatusItem?
    @Published var noteCount: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up menu bar icon
        setupMenuBarIcon()

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

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "CoolQuickNote")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "New Note", action: #selector(createNewNote), keyEquivalent: "n"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CoolQuickNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func createNewNote() {
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
        noteCount = notePanels.count
    }

    func closeNote(id: UUID) {
        if let panel = notePanels[id] {
            // Save window frame before closing
            saveNoteWindowFrame(id: id, frame: panel.frame)
            panel.close()
            notePanels.removeValue(forKey: id)
            noteCount = notePanels.count
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows - create a new note when dock icon is clicked
            createNewNote()
        }
        return true
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
                dynamicSizingEnabled: UserDefaults.standard.object(forKey: "note_\(id.uuidString)_dynamicSizing") as? Bool ?? true,
                noteOpacity: UserDefaults.standard.object(forKey: "note_\(id.uuidString)_opacity") as? Double ?? 1.0,
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
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            makeKeyAndOrderFront(nil)  // Keep the clicked panel key in the current space without hopping spaces
            if !isKeyWindow {
                makeKey()  // Ensure window becomes key so traffic lights reappear after returning to the app
            }
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)  // Ensure app becomes active so traffic lights can appear
            }
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
