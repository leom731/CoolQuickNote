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
    var settingsPanels: [UUID: NSPanel] = [:]
    fileprivate var settingsPanelDelegates: [UUID: SettingsPanelDelegate] = [:]
    private let notesKey = "savedNotes"
    private var statusItem: NSStatusItem?
    @Published var noteCount: Int = 0
    @Published var activeNoteId: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up menu bar icon
        setupMenuBarIcon()

        // Set up notification observer to track active note
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

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

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = window as? ActivatingPanel,
              let noteId = panel.noteId else { return }
        activeNoteId = noteId
    }

    @objc func createNewNote() {
        // Get properties from active note if it exists
        var windowFrame: CGRect? = nil
        var opacity: Double = 1.0

        if let sourceId = activeNoteId,
           let sourcePanel = notePanels[sourceId] {
            // Copy size and position from source note, placing the new note beside it without overlap
            let targetSize = sourcePanel.frame.size
            windowFrame = nextWindowFrame(beside: sourcePanel, targetSize: targetSize)

            // Copy opacity from UserDefaults
            if let storedOpacity = UserDefaults.standard.object(forKey: "note_\(sourceId.uuidString)_opacity") as? Double {
                opacity = storedOpacity
            }
        }

        let noteData = NoteData(noteOpacity: opacity, windowFrame: windowFrame)
        createNotePanel(with: noteData)
        saveNotes()
    }

    private func nextWindowFrame(beside sourcePanel: NSPanel, targetSize: CGSize) -> CGRect {
        let spacing: CGFloat = 24
        let sourceFrame = sourcePanel.frame
        let visibleFrame = sourcePanel.screen?.visibleFrame ??
            NSScreen.main?.visibleFrame ??
            NSScreen.screens.first?.visibleFrame ??
            NSRect(origin: sourceFrame.origin, size: targetSize)

        func clampedY(_ proposedY: CGFloat) -> CGFloat {
            min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - targetSize.height)
        }

        func clampedX(_ proposedX: CGFloat) -> CGFloat {
            min(max(proposedX, visibleFrame.minX), visibleFrame.maxX - targetSize.width)
        }

        // First try to the right of the source note
        if sourceFrame.maxX + spacing + targetSize.width <= visibleFrame.maxX {
            let origin = CGPoint(x: sourceFrame.maxX + spacing, y: clampedY(sourceFrame.origin.y))
            let candidate = CGRect(origin: origin, size: targetSize)
            return candidate
        }

        // If it won't fit, try to the left
        if sourceFrame.minX - spacing - targetSize.width >= visibleFrame.minX {
            let origin = CGPoint(x: sourceFrame.minX - spacing - targetSize.width, y: clampedY(sourceFrame.origin.y))
            let candidate = CGRect(origin: origin, size: targetSize)
            if visibleFrame.contains(candidate) {
                return candidate
            }
        }

        // Finally, try below the source note
        let belowY = sourceFrame.minY - spacing - targetSize.height
        if belowY >= visibleFrame.minY {
            let origin = CGPoint(x: clampedX(sourceFrame.origin.x), y: belowY)
            let candidate = CGRect(origin: origin, size: targetSize)
            if visibleFrame.contains(candidate) {
                return candidate
            }
        }

        // Try above the source note if there is space
        let aboveY = sourceFrame.maxY + spacing
        if aboveY + targetSize.height <= visibleFrame.maxY {
            let origin = CGPoint(x: clampedX(sourceFrame.origin.x), y: aboveY)
            let candidate = CGRect(origin: origin, size: targetSize)
            if visibleFrame.contains(candidate) {
                return candidate
            }
        }

        // Fallback: keep the window visible, even if we can't avoid overlap entirely
        let origin = CGPoint(x: clampedX(sourceFrame.origin.x + spacing), y: clampedY(sourceFrame.origin.y))
        return CGRect(origin: origin, size: targetSize)
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

    func toggleSettingsPanel(for noteId: UUID, selectedFont: Binding<String>, fontSize: Binding<Double>, fontColorName: Binding<String>, backgroundColorName: Binding<String>, alwaysOnTop: Binding<Bool>, dynamicSizingEnabled: Binding<Bool>, noteOpacity: Binding<Double>) {
        // If settings panel already exists for this note, close it
        if let existingPanel = settingsPanels[noteId] {
            // Remove child window relationship before closing
            if let notePanel = notePanels[noteId] {
                notePanel.removeChildWindow(existingPanel)
            }
            existingPanel.close()
            settingsPanels.removeValue(forKey: noteId)
            settingsPanelDelegates.removeValue(forKey: noteId)
            return
        }

        // Create a new settings panel using ActivatingPanel for fullscreen compatibility
        let settingsPanel = ActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 550),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        // Configure the panel
        settingsPanel.title = "Settings"
        settingsPanel.isFloatingPanel = true
        settingsPanel.level = .floating
        settingsPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        settingsPanel.isMovableByWindowBackground = true
        settingsPanel.hidesOnDeactivate = false
        settingsPanel.isReleasedWhenClosed = false

        // Create the settings view
        let settingsView = SettingsView(
            selectedFont: selectedFont,
            fontSize: fontSize,
            fontColorName: fontColorName,
            backgroundColorName: backgroundColorName,
            alwaysOnTop: alwaysOnTop,
            dynamicSizingEnabled: dynamicSizingEnabled,
            noteOpacity: noteOpacity,
            noteId: noteId,
            appDelegate: self
        )

        let hostingView = NSHostingView(rootView: settingsView)
        settingsPanel.contentView = hostingView

        // Position the panel near the note window on the same screen/space
        if let notePanel = notePanels[noteId] {
            // Position relative to the note
            let noteFrame = notePanel.frame
            let xOffset: CGFloat = noteFrame.maxX + 20
            settingsPanel.setFrameTopLeftPoint(NSPoint(x: xOffset, y: noteFrame.maxY))

            // Make settings panel a child of note panel to keep them on same space
            notePanel.addChildWindow(settingsPanel, ordered: .above)
        } else {
            settingsPanel.center()
        }

        // Handle panel close - store delegate to prevent deallocation
        let delegate = SettingsPanelDelegate(noteId: noteId, appDelegate: self)
        settingsPanel.delegate = delegate
        settingsPanelDelegates[noteId] = delegate

        // Show panel on current workspace, even in fullscreen mode
        settingsPanel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        settingsPanels[noteId] = settingsPanel
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

// Delegate to handle settings panel close
fileprivate class SettingsPanelDelegate: NSObject, NSWindowDelegate {
    let noteId: UUID
    weak var appDelegate: AppDelegate?

    init(noteId: UUID, appDelegate: AppDelegate) {
        self.noteId = noteId
        self.appDelegate = appDelegate
    }

    func windowWillClose(_ notification: Notification) {
        // Remove child window relationship
        if let settingsPanel = appDelegate?.settingsPanels[noteId],
           let notePanel = appDelegate?.notePanels[noteId] {
            notePanel.removeChildWindow(settingsPanel)
        }

        appDelegate?.settingsPanels.removeValue(forKey: noteId)
        appDelegate?.settingsPanelDelegates.removeValue(forKey: noteId)
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
            // Dispatch window activation asynchronously to avoid priority inversion
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.makeKeyAndOrderFront(nil)  // Keep the clicked panel key in the current space without hopping spaces
                if !self.isKeyWindow {
                    self.makeKey()  // Ensure window becomes key so traffic lights reappear after returning to the app
                }
                if !NSApp.isActive {
                    NSApp.activate(ignoringOtherApps: true)  // Ensure app becomes active so traffic lights can appear
                }
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
