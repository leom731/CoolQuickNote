import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Note Data Model
struct NoteData: Codable, Identifiable {
    let id: UUID
    var content: String
    var selectedFont: String
    var fontSize: Double
    var fontColorName: String
    var backgroundColorName: String
    var stayOnThisScreen: Bool
    var dynamicSizingEnabled: Bool
    var noteOpacity: Double
    var isReadingAid: Bool
    var windowFrame: CGRect?
    var savedSpaceIdentifier: Int?

    init(id: UUID = UUID(),
         content: String = "",
         selectedFont: String = "regular",
         fontSize: Double = 11,
         fontColorName: String = "blue",
         backgroundColorName: String = "yellow",
         stayOnThisScreen: Bool = false,
         dynamicSizingEnabled: Bool = false,
         noteOpacity: Double = 1.0,
         isReadingAid: Bool = false,
         windowFrame: CGRect? = nil,
         savedSpaceIdentifier: Int? = nil) {
        self.id = id
        self.content = content
        self.selectedFont = selectedFont
        self.fontSize = fontSize
        self.fontColorName = fontColorName
        self.backgroundColorName = backgroundColorName
        self.stayOnThisScreen = stayOnThisScreen
        self.dynamicSizingEnabled = dynamicSizingEnabled
        self.noteOpacity = noteOpacity
        self.isReadingAid = isReadingAid
        self.windowFrame = windowFrame
        self.savedSpaceIdentifier = savedSpaceIdentifier
    }
}

extension NoteData {
    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case selectedFont
        case fontSize
        case fontColorName
        case backgroundColorName
        case stayOnThisScreen
        case alwaysOnTop
        case dynamicSizingEnabled
        case noteOpacity
        case isReadingAid
        case windowFrame
        case savedSpaceIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        selectedFont = try container.decodeIfPresent(String.self, forKey: .selectedFont) ?? "regular"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 11
        fontColorName = try container.decodeIfPresent(String.self, forKey: .fontColorName) ?? "blue"
        backgroundColorName = try container.decodeIfPresent(String.self, forKey: .backgroundColorName) ?? "yellow"
        if let stayOnThisScreen = try container.decodeIfPresent(Bool.self, forKey: .stayOnThisScreen) {
            self.stayOnThisScreen = stayOnThisScreen
        } else if let alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) {
            stayOnThisScreen = !alwaysOnTop
        } else {
            stayOnThisScreen = false
        }
        dynamicSizingEnabled = try container.decodeIfPresent(Bool.self, forKey: .dynamicSizingEnabled) ?? false
        noteOpacity = try container.decodeIfPresent(Double.self, forKey: .noteOpacity) ?? 1.0
        isReadingAid = try container.decodeIfPresent(Bool.self, forKey: .isReadingAid) ?? false
        windowFrame = try container.decodeIfPresent(CGRect.self, forKey: .windowFrame)
        savedSpaceIdentifier = try container.decodeIfPresent(Int.self, forKey: .savedSpaceIdentifier)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(selectedFont, forKey: .selectedFont)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontColorName, forKey: .fontColorName)
        try container.encode(backgroundColorName, forKey: .backgroundColorName)
        try container.encode(stayOnThisScreen, forKey: .stayOnThisScreen)
        try container.encode(dynamicSizingEnabled, forKey: .dynamicSizingEnabled)
        try container.encode(noteOpacity, forKey: .noteOpacity)
        try container.encode(isReadingAid, forKey: .isReadingAid)
        try container.encodeIfPresent(windowFrame, forKey: .windowFrame)
        try container.encodeIfPresent(savedSpaceIdentifier, forKey: .savedSpaceIdentifier)
    }
}

extension Notification.Name {
    static let quickNotePasteImage = Notification.Name("com.coolquicknote.pasteImage")
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
                Button("New Reading Aid") {
                    appDelegate.createReadingAidNote()
                }
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    appDelegate.handlePasteCommand()
                }
                .keyboardShortcut("v", modifiers: .command)
            }
            CommandMenu("Note Options") {
                Button("Stay on This Desktop") {
                    appDelegate.toggleStayOnThisDesktopForActiveNote()
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("Show All Notes on All Desktops") {
                    appDelegate.disableStayOnThisScreenForAllNotes()
                }
                .keyboardShortcut("g", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var notePanels: [UUID: NSPanel] = [:]
    var settingsPanels: [UUID: NSPanel] = [:]
    fileprivate var settingsPanelDelegates: [UUID: SettingsPanelDelegate] = [:]
    private var tipJarPanel: NSPanel?
    private var tipJarPanelDelegate: TipJarPanelDelegate?
    private let notesKey = "savedNotes"
    private var statusItem: NSStatusItem?
    private var spaceObserver: NSObjectProtocol?
    private var frontAppObserver: NSObjectProtocol?
    @Published var noteCount: Int = 0
    @Published var activeNoteId: UUID?
    @Published var areNotesHidden: Bool = false

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

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshNoteVisibilityForActiveSpace()
        }

        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshNoteVisibilityForActiveSpace()
        }
    }

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "CoolQuickNote")
            button.image?.isTemplate = true
        }

        updateMenuBarMenu()
    }

    private func updateMenuBarMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "New Note", action: #selector(createNewNote), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "New Reading Aid", action: #selector(createReadingAidNote), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let hideShowTitle = areNotesHidden ? "Show All Notes" : "Hide All Notes"
        let hideShowItem = NSMenuItem(title: hideShowTitle, action: #selector(toggleNotesVisibilityAction), keyEquivalent: "h")
        menu.addItem(hideShowItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CoolQuickNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func toggleNotesVisibilityAction() {
        toggleNotesVisibility()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = window as? ActivatingPanel,
              let noteId = panel.noteId else { return }
        activeNoteId = noteId
    }

    func handlePasteCommand() {
        let pasteboard = NSPasteboard.general
        if pasteboardHasImage(pasteboard),
           let noteId = resolveActiveNoteId() {
            NotificationCenter.default.post(
                name: .quickNotePasteImage,
                object: nil,
                userInfo: ["noteId": noteId]
            )
            return
        }

        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }

    private func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        let imageTypes = [
            UTType.image.identifier,
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.tiff.identifier
        ]

        if pasteboard.canReadItem(withDataConformingToTypes: imageTypes) {
            return true
        }

        return NSImage(pasteboard: pasteboard) != nil
    }

    private func resolveActiveNoteId() -> UUID? {
        if let panel = NSApp.keyWindow as? ActivatingPanel, let noteId = panel.noteId {
            return noteId
        }
        if let panel = NSApp.mainWindow as? ActivatingPanel, let noteId = panel.noteId {
            return noteId
        }
        return activeNoteId
    }

    private enum NoteCreationStyle {
        case standard
        case readingAid
    }

    @objc func createNewNote() {
        createNote(style: .standard)
    }

    @objc func createReadingAidNote() {
        createNote(style: .readingAid)
    }

    private func createNote(style: NoteCreationStyle) {
        let newNoteId = UUID()

        var windowFrame: CGRect? = nil
        var opacity: Double = 1.0
        var backgroundColor = "yellow"
        var isReadingAid = false

        let activePanel = activeNoteId.flatMap { notePanels[$0] }
        let placementScreen = activePanel?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let targetSize: CGSize
        switch style {
        case .standard:
            let defaultSize = CGSize(width: 300, height: 300)
            let initialSize = CGSize(width: defaultSize.width * 0.75, height: defaultSize.height * 0.75)
            targetSize = activePanel?.frame.size ?? notePanels.values.first?.frame.size ?? initialSize
        case .readingAid:
            isReadingAid = true
            targetSize = readingAidInitialSize(on: placementScreen)
        }

        let spacing: CGFloat = 24
        let preferredOrigin: CGPoint
        if let activePanel {
            preferredOrigin = CGPoint(x: activePanel.frame.maxX + spacing, y: activePanel.frame.origin.y)
        } else {
            preferredOrigin = defaultFrameForFirstLaunch(size: targetSize, on: placementScreen).origin
        }

        let existingFrames: [CGRect] = notePanels.values.compactMap { panel in
            if let placementScreen,
               let panelScreen = panel.screen,
               panelScreen !== placementScreen {
                return nil
            }
            return panel.frame
        }

        windowFrame = nextAvailableWindowFrame(
            preferredOrigin: preferredOrigin,
            targetSize: targetSize,
            on: placementScreen,
            avoiding: existingFrames
        )

        if let sourceId = activeNoteId, notePanels[sourceId] != nil {
            if let storedOpacity = UserDefaults.standard.object(forKey: "note_\(sourceId.uuidString)_opacity") as? Double {
                opacity = storedOpacity
            }
            if let storedBackgroundColor = UserDefaults.standard.string(forKey: "note_\(sourceId.uuidString)_backgroundColor") {
                backgroundColor = storedBackgroundColor
            }
        }

        if isReadingAid {
            opacity = 0.2
        }

        // Seed defaults so the new note picks up the copied appearance immediately
        UserDefaults.standard.set(opacity, forKey: "note_\(newNoteId.uuidString)_opacity")
        UserDefaults.standard.set(backgroundColor, forKey: "note_\(newNoteId.uuidString)_backgroundColor")
        UserDefaults.standard.set(isReadingAid, forKey: readingAidKey(for: newNoteId))
        if isReadingAid {
            UserDefaults.standard.set("", forKey: "note_\(newNoteId.uuidString)_content")
        }

        let noteData = NoteData(
            id: newNoteId,
            backgroundColorName: backgroundColor,
            noteOpacity: opacity,
            isReadingAid: isReadingAid,
            windowFrame: windowFrame
        )
        createNotePanel(with: noteData)
        saveNotes()
    }

    private func nextAvailableWindowFrame(
        preferredOrigin: CGPoint,
        targetSize: CGSize,
        on screen: NSScreen?,
        avoiding existingFrames: [CGRect]
    ) -> CGRect {
        let visibleFrame = screen?.visibleFrame ??
            NSScreen.main?.visibleFrame ??
            NSScreen.screens.first?.visibleFrame ??
            NSRect(origin: preferredOrigin, size: targetSize)
        let maxX = visibleFrame.maxX - targetSize.width
        let maxY = visibleFrame.maxY - targetSize.height
        let clampedX = maxX >= visibleFrame.minX
            ? min(max(preferredOrigin.x, visibleFrame.minX), maxX)
            : visibleFrame.minX
        let clampedY = maxY >= visibleFrame.minY
            ? min(max(preferredOrigin.y, visibleFrame.minY), maxY)
            : visibleFrame.minY
        let clampedPreferred = CGPoint(x: clampedX, y: clampedY)

        guard maxX >= visibleFrame.minX, maxY >= visibleFrame.minY else {
            return CGRect(origin: clampedPreferred, size: targetSize)
        }

        if existingFrames.isEmpty {
            return CGRect(origin: clampedPreferred, size: targetSize)
        }

        let spacing: CGFloat = 24
        let paddedFrames = existingFrames.map { $0.insetBy(dx: -spacing, dy: -spacing) }

        func isFree(_ origin: CGPoint) -> Bool {
            let candidate = CGRect(origin: origin, size: targetSize)
            if !visibleFrame.contains(candidate) {
                return false
            }
            for frame in paddedFrames where candidate.intersects(frame) {
                return false
            }
            return true
        }

        var bestOrigin: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var y = maxY

        while y >= visibleFrame.minY {
            var x = visibleFrame.minX
            while x <= maxX {
                let origin = CGPoint(x: x, y: y)
                if isFree(origin) {
                    let dx = origin.x - clampedPreferred.x
                    let dy = origin.y - clampedPreferred.y
                    let distance = dx * dx + dy * dy
                    if distance < bestDistance {
                        bestDistance = distance
                        bestOrigin = origin
                    }
                }
                x += spacing
            }
            y -= spacing
        }

        if let bestOrigin {
            return CGRect(origin: bestOrigin, size: targetSize)
        }

        return CGRect(origin: clampedPreferred, size: targetSize)
    }

    private func readingAidInitialSize(on screen: NSScreen?) -> CGSize {
        let fallbackFrame = CGRect(x: 0, y: 0, width: 600, height: 400)
        let visibleFrame = screen?.visibleFrame ??
            NSScreen.main?.visibleFrame ??
            NSScreen.screens.first?.visibleFrame ??
            fallbackFrame
        let targetWidth = max(visibleFrame.width * 0.5, 200)

        let font = NSFont.systemFont(ofSize: 11)
        let lineHeight = font.ascender - font.descender + font.leading
        let textHeight = lineHeight * 5
        let chromeHeight: CGFloat = 52
        let targetHeight = max(textHeight + chromeHeight, 80)

        return CGSize(width: targetWidth, height: targetHeight)
    }

    private func createNotePanel(with noteData: NoteData) {
        // Create the note panel
        let defaultSize = CGSize(width: 300, height: 300)
        let initialSize = CGSize(width: defaultSize.width * 0.75, height: defaultSize.height * 0.75)
        let initialFrame = noteData.windowFrame ?? defaultFrameForFirstLaunch(size: initialSize)
        let panel = ActivatingPanel(
            contentRect: initialFrame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure panel appearance and space behavior
        panel.title = "CoolQuickNote"
        let stayOnThisScreen = ensureStayOnThisScreenSetting(for: noteData.id, fallback: noteData.stayOnThisScreen)
        applySpaceBehavior(to: panel, stayOnThisScreen: stayOnThisScreen)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isRestorable = false
        hideStandardWindowButtons(for: panel)

        // Set size constraints
        let readingAidStorageKey = readingAidKey(for: noteData.id)
        if UserDefaults.standard.object(forKey: readingAidStorageKey) == nil {
            UserDefaults.standard.set(noteData.isReadingAid, forKey: readingAidStorageKey)
        }
        let isReadingAid = UserDefaults.standard.bool(forKey: readingAidStorageKey)
        panel.contentMinSize = isReadingAid
            ? CGSize(width: 200, height: 80)
            : CGSize(width: 200, height: 200)

        // Set SwiftUI content with note ID
        let hostingView = NSHostingView(rootView: ContentView(noteId: noteData.id, appDelegate: self))
        panel.contentView = hostingView

        // Apply corner radius
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        // Set up close handler
        panel.noteId = noteData.id

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        notePanels[noteData.id] = panel
        noteCount = notePanels.count

        // If stayOnThisScreen is enabled and we have a saved space, try to restore it
        if stayOnThisScreen, let savedSpaceID = noteData.savedSpaceIdentifier {
            // Attempt to move the window to the saved space
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.moveWindow(panel, toSpaceIdentifier: savedSpaceID)
            }
        } else if stayOnThisScreen {
            // If stayOnThisScreen is enabled but no saved space, capture current space
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, id = noteData.id] in
                guard let self = self, let panel = self.notePanels[id] else { return }
                if let spaceID = self.getCurrentSpaceIdentifier(for: panel) {
                    self.saveSpaceIdentifier(for: id, spaceID: spaceID)
                }
            }
        }

        refreshNoteVisibilityForActiveSpace()
    }

    private func defaultFrameForFirstLaunch(size: CGSize, on screen: NSScreen? = nil) -> CGRect {
        let visibleFrame = screen?.visibleFrame ??
            NSScreen.main?.visibleFrame ??
            NSScreen.screens.first?.visibleFrame ??
            NSRect(origin: .zero, size: size)
        let leftInset: CGFloat = 40
        let proposedX = visibleFrame.minX + leftInset
        let proposedY = visibleFrame.midY - (size.height / 2)
        let clampedX = min(max(proposedX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let clampedY = min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: size)
    }

    func closeNote(id: UUID) {
        if let panel = notePanels[id] {
            // Save window frame before closing
            saveNoteWindowFrame(id: id, frame: panel.frame)
            panel.close()
            notePanels.removeValue(forKey: id)
            noteCount = notePanels.count
            UserDefaults.standard.removeObject(forKey: "note_\(id.uuidString)_imageData")
            saveNotes()
        }
    }

    // MARK: - Hide/Show All Notes

    func hideAllNotes() {
        for panel in notePanels.values {
            panel.orderOut(nil)
        }
        for panel in settingsPanels.values {
            panel.orderOut(nil)
        }
        areNotesHidden = true
        updateMenuBarMenu()
    }

    func showAllNotes() {
        areNotesHidden = false

        for (id, panel) in notePanels {
            let stayOnThisScreen = ensureStayOnThisScreenSetting(for: id)

            if stayOnThisScreen {
                if panel.isOnActiveSpace {
                    panel.orderFrontRegardless()
                }
            } else {
                panel.orderFrontRegardless()
            }
        }
        for panel in settingsPanels.values {
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        updateMenuBarMenu()
    }

    func toggleNotesVisibility() {
        if areNotesHidden {
            showAllNotes()
        } else {
            hideAllNotes()
        }
    }

    func toggleStayOnThisDesktopForActiveNote() {
        guard let noteId = resolveActiveNoteId() else { return }
        let current = ensureStayOnThisScreenSetting(for: noteId)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: stayOnThisScreenKey(for: noteId))
        updateStayOnThisScreen(for: noteId, stayOnThisScreen: newValue)
    }

    private func hideStandardWindowButtons(for panel: NSPanel) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for type in buttons {
            if let button = panel.standardWindowButton(type) {
                button.isHidden = true
            }
        }
    }

    private func stayOnThisScreenKey(for noteId: UUID) -> String {
        "note_\(noteId.uuidString)_stayOnThisScreen"
    }

    private func alwaysOnTopKey(for noteId: UUID) -> String {
        "note_\(noteId.uuidString)_alwaysOnTop"
    }

    private func readingAidKey(for noteId: UUID) -> String {
        "note_\(noteId.uuidString)_readingAid"
    }

    func ensureStayOnThisScreenSetting(for noteId: UUID, fallback: Bool = false) -> Bool {
        let defaults = UserDefaults.standard
        let newKey = stayOnThisScreenKey(for: noteId)
        if defaults.object(forKey: newKey) != nil {
            return defaults.bool(forKey: newKey)
        }
        let legacyKey = alwaysOnTopKey(for: noteId)
        if defaults.object(forKey: legacyKey) != nil {
            let stayOnThisScreen = !defaults.bool(forKey: legacyKey)
            defaults.set(stayOnThisScreen, forKey: newKey)
            return stayOnThisScreen
        }
        defaults.set(fallback, forKey: newKey)
        return fallback
    }

    private func applySpaceBehavior(to panel: NSPanel, stayOnThisScreen: Bool) {
        // Always keep note windows floating on top
        panel.isFloatingPanel = true
        panel.level = .floating

        if stayOnThisScreen {
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        } else {
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }

    func updateStayOnThisScreen(for noteId: UUID, stayOnThisScreen: Bool) {
        guard let panel = notePanels[noteId] else { return }
        applySpaceBehavior(to: panel, stayOnThisScreen: stayOnThisScreen)

        if stayOnThisScreen {
            if let spaceID = getCurrentSpaceIdentifier(for: panel) {
                saveSpaceIdentifier(for: noteId, spaceID: spaceID)
            }
        } else {
            saveSpaceIdentifier(for: noteId, spaceID: nil)
        }

        panel.orderFrontRegardless()
        saveNotes()
    }

    func disableStayOnThisScreenForAllNotes() {
        let defaults = UserDefaults.standard
        for (id, panel) in notePanels {
            defaults.set(false, forKey: stayOnThisScreenKey(for: id))
            applySpaceBehavior(to: panel, stayOnThisScreen: false)
            // Show the note on all spaces
            panel.orderFrontRegardless()
        }

        saveNotes()
    }

    func toggleSettingsPanel(for noteId: UUID, selectedFont: Binding<String>, fontSize: Binding<Double>, fontColorName: Binding<String>, backgroundColorName: Binding<String>, stayOnThisScreen: Binding<Bool>, dynamicSizingEnabled: Binding<Bool>, noteOpacity: Binding<Double>, disappearOnHover: Binding<Bool>) {
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
            stayOnThisScreen: stayOnThisScreen,
            dynamicSizingEnabled: dynamicSizingEnabled,
            noteOpacity: noteOpacity,
            disappearOnHover: disappearOnHover,
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

    func presentTipJar(from window: NSWindow? = nil) {
        if let panel = tipJarPanel {
            centerTipJar(panel, relativeTo: window)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = ActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Support Development"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hasShadow = true

        let isPresented = Binding<Bool>(
            get: { true },
            set: { [weak self] newValue in
                if !newValue {
                    self?.closeTipJar()
                }
            }
        )

        let hostingView = NSHostingView(rootView: TipJarView(isPresented: isPresented))
        panel.contentView = hostingView

        let delegate = TipJarPanelDelegate(appDelegate: self)
        panel.delegate = delegate
        tipJarPanelDelegate = delegate

        tipJarPanel = panel
        centerTipJar(panel, relativeTo: window)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate func handleTipJarClosed() {
        tipJarPanel = nil
        tipJarPanelDelegate = nil
    }

    private func closeTipJar() {
        tipJarPanel?.close()
    }

    private func centerTipJar(_ panel: NSPanel, relativeTo window: NSWindow?) {
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visibleFrame.midX - (frame.size.width / 2)
        frame.origin.y = visibleFrame.midY - (frame.size.height / 2)
        let clampedX = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.size.width)
        let clampedY = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.size.height)
        panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if areNotesHidden {
            // Notes are hidden - show them when dock icon is clicked
            showAllNotes()
        } else if !flag {
            // No visible windows and notes aren't hidden - create a new note
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
            // Get the saved space identifier from existing data if available
            let existingSavedSpaceID = loadNotes().first(where: { $0.id == id })?.savedSpaceIdentifier

            let note = NoteData(
                id: id,
                content: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_content") ?? "",
                selectedFont: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_font") ?? "regular",
                fontSize: UserDefaults.standard.double(forKey: "note_\(id.uuidString)_fontSize") != 0 ? UserDefaults.standard.double(forKey: "note_\(id.uuidString)_fontSize") : 11,
                fontColorName: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_fontColor") ?? "blue",
                backgroundColorName: UserDefaults.standard.string(forKey: "note_\(id.uuidString)_backgroundColor") ?? "yellow",
                stayOnThisScreen: ensureStayOnThisScreenSetting(for: id),
                dynamicSizingEnabled: UserDefaults.standard.object(forKey: "note_\(id.uuidString)_dynamicSizing") as? Bool ?? false,
                noteOpacity: UserDefaults.standard.object(forKey: "note_\(id.uuidString)_opacity") as? Double ?? 1.0,
                isReadingAid: UserDefaults.standard.bool(forKey: readingAidKey(for: id)),
                windowFrame: panel.frame,
                savedSpaceIdentifier: existingSavedSpaceID
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

    private func saveSpaceIdentifier(for noteId: UUID, spaceID: Int?) {
        var notes = loadNotes()
        if let index = notes.firstIndex(where: { $0.id == noteId }) {
            notes[index].savedSpaceIdentifier = spaceID
            if let encoded = try? JSONEncoder().encode(notes) {
                UserDefaults.standard.set(encoded, forKey: notesKey)
            }
        }
    }

    private func refreshNoteVisibilityForActiveSpace() {
        // Don't show notes if user has hidden them
        if areNotesHidden {
            return
        }

        for (id, panel) in notePanels {
            let stayOnThisScreen = ensureStayOnThisScreenSetting(for: id)

            if stayOnThisScreen {
                if panel.isOnActiveSpace {
                    if !panel.isVisible {
                        panel.orderFrontRegardless()
                    }
                }
            } else {
                // Notes without "Stay on This Desktop" are always visible
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                }
            }
        }
    }

    private func isActiveSpaceFullscreen() -> Bool {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }

        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let tolerance: CGFloat = 2
        for screen in NSScreen.screens {
            let screenSize = screen.frame.size
            for info in windowInfo {
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                      pid == frontmostPID else { continue }
                guard let layer = info[kCGWindowLayer as String] as? Int,
                      layer == 0 else { continue }
                guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
                let width = bounds["Width"] ?? 0
                let height = bounds["Height"] ?? 0
                if abs(width - screenSize.width) <= tolerance &&
                    abs(height - screenSize.height) <= tolerance {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Space Management

    /// Gets the current space identifier for a window
    private func getCurrentSpaceIdentifier(for window: NSWindow) -> Int? {
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else {
            return nil
        }

        let cgWindowID = CGWindowID(windowNumber)

        // Get window info including spaces
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], cgWindowID) as? [[String: Any]],
              let info = windowInfo.first else {
            return nil
        }

        // Extract space information if available
        // Note: This uses the kCGWindowWorkspace key which provides the space ID
        if let spaceID = info["kCGWindowWorkspace" as String] as? Int {
            return spaceID
        }

        return nil
    }

    /// Best-effort: reapply space behavior if the window is already on the target space.
    private func moveWindow(_ window: NSWindow, toSpaceIdentifier spaceID: Int) {
        guard let panel = window as? NSPanel else { return }
        guard let currentSpaceID = getCurrentSpaceIdentifier(for: panel),
              currentSpaceID == spaceID else { return }
        applySpaceBehavior(to: panel, stayOnThisScreen: true)
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

fileprivate class TipJarPanelDelegate: NSObject, NSWindowDelegate {
    weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func windowWillClose(_ notification: Notification) {
        appDelegate?.handleTipJarClosed()
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
            // Defer activation to the next run loop to avoid QoS inversion warnings inside AppKit.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
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
