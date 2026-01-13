import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    let noteId: UUID
    @ObservedObject var appDelegate: AppDelegate

    @AppStorage var noteContent: String
    @AppStorage var selectedFont: String
    @AppStorage var fontSize: Double
    @AppStorage var fontColorName: String
    @AppStorage var backgroundColorName: String
    @AppStorage var stayOnThisScreen: Bool
    @AppStorage var dynamicSizingEnabled: Bool
    @AppStorage var noteOpacity: Double
    @AppStorage var disappearOnHover: Bool

    @State private var windowSize: CGSize = .zero
    @State private var effectiveFontSize: Double = 11.0
    @State private var shouldUseScrollMode: Bool = false
    @State private var isTextEditorFocused: Bool = false
    @State private var currentWindow: NSWindow?
    @State private var pastedImage: NSImage?
    @State private var isHovering: Bool = false
    @State private var isCommandKeyPressed: Bool = false
    @State private var showCloseConfirmation: Bool = false
    private let persistenceQueue = DispatchQueue(label: "com.coolquicknote.image.persistence", qos: .userInitiated)

    init(noteId: UUID, appDelegate: AppDelegate) {
        self.noteId = noteId
        self.appDelegate = appDelegate

        _noteContent = AppStorage(wrappedValue: "", "note_\(noteId.uuidString)_content")
        _selectedFont = AppStorage(wrappedValue: "regular", "note_\(noteId.uuidString)_font")
        _fontSize = AppStorage(wrappedValue: 11, "note_\(noteId.uuidString)_fontSize")
        _fontColorName = AppStorage(wrappedValue: "blue", "note_\(noteId.uuidString)_fontColor")
        _backgroundColorName = AppStorage(wrappedValue: "yellow", "note_\(noteId.uuidString)_backgroundColor")
        let stayOnThisScreenKey = "note_\(noteId.uuidString)_stayOnThisScreen"
        let stayOnThisScreenDefault = appDelegate.ensureStayOnThisScreenSetting(for: noteId)
        _stayOnThisScreen = AppStorage(wrappedValue: stayOnThisScreenDefault, stayOnThisScreenKey)
        _dynamicSizingEnabled = AppStorage(wrappedValue: false, "note_\(noteId.uuidString)_dynamicSizing")
        _noteOpacity = AppStorage(wrappedValue: 1.0, "note_\(noteId.uuidString)_opacity")
        _disappearOnHover = AppStorage(wrappedValue: false, "note_\(noteId.uuidString)_disappearOnHover")
    }

    private func formatCurrentDateTime() -> String {
        let formatter = DateFormatter()

        formatter.dateFormat = "MMM dd, yyyy EEE"
        let dateString = formatter.string(from: Date())

        formatter.dateFormat = "h:mm a"
        let timeString = formatter.string(from: Date())

        return "\(dateString)\n\(timeString)\n"
    }

    private func insertCurrentDateTime() {
        let dateTime = formatCurrentDateTime()
        if let textView = resolveTextView() {
            textView.insertText(dateTime, replacementRange: textView.selectedRange())
        } else {
            noteContent.append(dateTime)
        }
    }

    private func resolveTextView() -> NSTextView? {
        if let textView = resolveWindow()?.firstResponder as? NSTextView {
            return textView
        }
        guard let contentView = resolveWindow()?.contentView else { return nil }
        return findTextView(in: contentView)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    private var imageStorageKey: String {
        "note_\(noteId.uuidString)_imageData"
    }

    private var shouldHideOnHover: Bool {
        disappearOnHover && isHovering && !isCommandKeyPressed
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geometry in
                ZStack {
                    if let image = pastedImage {
                        Color.clear
                            .overlay(
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                                    .padding(12)
                            )
                            .overlay(alignment: .topTrailing) {
                                Button(action: clearPastedImage) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray.opacity(0.7))
                                        .padding(8)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                                .help("Remove image")
                            }
                    } else {
                        NoteTextEditor(
                            text: $noteContent,
                            isFocused: $isTextEditorFocused,
                            font: currentNSFont,
                            textColor: currentFontNSColor,
                            tabSpaces: "    "
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: noteContent) { _ in
                            if dynamicSizingEnabled && !shouldUseScrollMode {
                                updateDynamicSizing(for: windowSize)
                            }
                        }
                    }
                }
                .onChange(of: geometry.size) { newSize in
                    updateDynamicSizing(for: newSize)
                }
                .onAppear {
                    updateDynamicSizing(for: geometry.size)
                }
            }
        }
        .frame(minWidth: 100, minHeight: 60)
        .background(currentBackgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .opacity(shouldHideOnHover ? 0 : noteOpacity)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .animation(.easeInOut(duration: 0.2), value: isCommandKeyPressed)
        .animation(.easeInOut(duration: 0.2), value: noteOpacity)
        .overlay(
            HoverAndWindowController(
                isHovering: $isHovering,
                isCommandKeyPressed: $isCommandKeyPressed,
                disappearOnHover: disappearOnHover
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        )
        .contextMenu {
            Button(action: pasteImageFromClipboard) {
                Label("Paste Image", systemImage: "doc.on.clipboard")
            }
            Button(action: insertCurrentDateTime) {
                Label("Insert Date & Time", systemImage: "calendar.badge.clock")
            }
            Divider()
            backgroundColorMenu
            Divider()
            settingsCommands
            Divider()
            noteOptionsMenu
            Divider()
            windowActionsMenu
        }
        .background(WindowAccessor(window: $currentWindow))
        .onAppear {
            if noteContent.isEmpty {
                noteContent = formatCurrentDateTime()
            }

            loadStoredImage()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextEditorFocused = true
            }

            applyWindowChrome()
        }
        .onChange(of: currentWindow) { _ in
            applyWindowChrome()
        }
        .onPasteCommand(of: [.image, .png, .jpeg, .tiff]) { providers in
            handleImagePaste(from: providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickNotePasteImage)) { notification in
            guard let targetId = notification.userInfo?["noteId"] as? UUID else { return }
            guard targetId == noteId else { return }
            pasteImageFromClipboard()
        }
        .alert("Save Note", isPresented: $showCloseConfirmation) {
            Button("Save to Notes", action: saveToNotesApp)
            Button("Discard", role: .destructive, action: discardNote)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Would you like to save this note to the Notes app?")
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: openSettings) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button(action: createNewNote) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("New Note")

            Button(action: pasteImageFromClipboard) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Paste image from clipboard")

            Spacer(minLength: 0)

            Menu {
                windowActionsMenu
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Window actions")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var settingsCommands: some View {
        Button(action: openSettings) {
            Label("Settings", systemImage: "gear")
        }

        Button(action: createNewNote) {
            Label("New Note", systemImage: "plus.circle")
        }
    }

    @ViewBuilder
    private var backgroundColorMenu: some View {
        Menu {
            Button {
                backgroundColorName = "yellow"
            } label: {
                if backgroundColorName == "yellow" {
                    Label("🟡 Yellow", systemImage: "checkmark")
                } else {
                    Text("🟡 Yellow")
                }
            }

            Button {
                backgroundColorName = "pink"
            } label: {
                if backgroundColorName == "pink" {
                    Label("🩷 Pink", systemImage: "checkmark")
                } else {
                    Text("🩷 Pink")
                }
            }

            Button {
                backgroundColorName = "blue"
            } label: {
                if backgroundColorName == "blue" {
                    Label("🔵 Blue", systemImage: "checkmark")
                } else {
                    Text("🔵 Blue")
                }
            }

            Button {
                backgroundColorName = "green"
            } label: {
                if backgroundColorName == "green" {
                    Label("🟢 Green", systemImage: "checkmark")
                } else {
                    Text("🟢 Green")
                }
            }

            Button {
                backgroundColorName = "purple"
            } label: {
                if backgroundColorName == "purple" {
                    Label("🟣 Purple", systemImage: "checkmark")
                } else {
                    Text("🟣 Purple")
                }
            }

            Button {
                backgroundColorName = "orange"
            } label: {
                if backgroundColorName == "orange" {
                    Label("🟠 Orange", systemImage: "checkmark")
                } else {
                    Text("🟠 Orange")
                }
            }
        } label: {
            Label("Background Color", systemImage: "paintpalette")
        }
    }

    @ViewBuilder
    private var noteOptionsMenu: some View {
        Button {
            dynamicSizingEnabled.toggle()
            if dynamicSizingEnabled {
                updateDynamicSizing(for: windowSize)
            }
        } label: {
            if dynamicSizingEnabled {
                Label("Dynamic Sizing", systemImage: "checkmark")
            } else {
                Text("Dynamic Sizing")
            }
        }

        Button {
            disappearOnHover.toggle()
        } label: {
            if disappearOnHover {
                Label("Hide on Hover", systemImage: "checkmark")
            } else {
                Text("Hide on Hover")
            }
        }
    }

    @ViewBuilder
    private var windowActionsMenu: some View {
        Button {
            stayOnThisScreen.toggle()
            appDelegate.updateStayOnThisScreen(for: noteId, stayOnThisScreen: stayOnThisScreen)
        } label: {
            if stayOnThisScreen {
                Label("Stay on This Desktop", systemImage: "checkmark")
            } else {
                Text("Stay on This Desktop")
            }
        }

        Divider()

        Button("Minimize", systemImage: "minus.square") {
            minimizeCurrentWindow()
        }
        .disabled(resolveWindow() == nil)

        Button("Zoom", systemImage: "arrow.up.left.and.arrow.down.right") {
            toggleZoomCurrentWindow()
        }
        .disabled(resolveWindow() == nil)

        Divider()

        Button("Close Note", systemImage: "xmark.circle") {
            closeNote()
        }
    }

    private func openSettings() {
        appDelegate.toggleSettingsPanel(
            for: noteId,
            selectedFont: $selectedFont,
            fontSize: $fontSize,
            fontColorName: $fontColorName,
            backgroundColorName: $backgroundColorName,
            stayOnThisScreen: $stayOnThisScreen,
            dynamicSizingEnabled: $dynamicSizingEnabled,
            noteOpacity: $noteOpacity,
            disappearOnHover: $disappearOnHover
        )
    }

    private func createNewNote() {
        appDelegate.activeNoteId = noteId
        appDelegate.createNewNote()
    }

    private func closeNote() {
        showCloseConfirmation = true
    }

    private func saveToNotesApp() {
        // Get the title from first line
        let lines = noteContent.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        let noteTitle: String
        if let firstLine = lines.first {
            noteTitle = String(String(firstLine).prefix(50))
        } else {
            noteTitle = "Quick Note"
        }

        // Build AppleScript with proper escaping for shell
        let escapedTitle = escapeForShell(noteTitle)
        let escapedBody = escapeForShell(noteContent)

        let script = """
        tell application "Notes"
            set folderExists to false
            repeat with aFolder in folders
                if name of aFolder is "CoolQuickNote" then
                    set folderExists to true
                    set targetFolder to aFolder
                    exit repeat
                end if
            end repeat

            if folderExists is false then
                set targetFolder to make new folder with properties {name:"CoolQuickNote"}
            end if

            make new note at targetFolder with properties {name:\(escapedTitle), body:\(escapedBody)}
        end tell
        """

        // Use osascript command which handles permissions better
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

                // Show error to user
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Save to Notes"
                    alert.informativeText = errorMessage
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }

            // Close the note after saving successfully
            DispatchQueue.main.async {
                self.appDelegate.closeNote(id: self.noteId)
            }
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Failed to Save to Notes"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func escapeForShell(_ text: String) -> String {
        // Convert to AppleScript string literal format
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func discardNote() {
        appDelegate.closeNote(id: noteId)
    }

    private func minimizeCurrentWindow() {
        resolveWindow()?.miniaturize(nil)
    }

    private func toggleZoomCurrentWindow() {
        resolveWindow()?.zoom(nil)
    }

    private func applyWindowChrome() {
        guard let window = resolveWindow() else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        buttons.forEach { window.standardWindowButton($0)?.isHidden = true }

        // Round the full window frame (including title bar area) to match the content view
        if let frameView = window.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.cornerRadius = 12
            frameView.layer?.cornerCurve = .continuous
            frameView.layer?.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
            frameView.layer?.masksToBounds = true
        }
    }

    private func resolveWindow() -> NSWindow? {
        currentWindow
            ?? appDelegate.notePanels[noteId]
            ?? NSApp?.keyWindow
            ?? NSApp?.mainWindow
            ?? NSApp?.windows.first
    }

    // MARK: - Image Handling

    private func handleImagePaste(from providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            return
        }

        let preferredTypes: [UTType] = [.png, .jpeg, .tiff]

        for type in preferredTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data else { return }
                persistImage(from: data)
            }
            return
        }

        provider.loadObject(ofClass: NSImage.self) { object, _ in
            guard let image = object as? NSImage else { return }
            persistImage(image)
        }
    }

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            persistImage(from: data)
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            persistImage(image)
        }
    }

    private func persistImage(from data: Data) {
        let storageKey = imageStorageKey
        persistenceQueue.async {
            autoreleasepool {
                guard let image = NSImage(data: data) else { return }
                UserDefaults.standard.set(data, forKey: storageKey)
                DispatchQueue.main.async {
                    self.pastedImage = image
                }
            }
        }
    }

    private func persistImage(_ image: NSImage) {
        let storageKey = imageStorageKey
        persistenceQueue.async {
            autoreleasepool {
                if let data = image.tiffRepresentation {
                    UserDefaults.standard.set(data, forKey: storageKey)
                }
                DispatchQueue.main.async {
                    self.pastedImage = image
                }
            }
        }
    }

    private func loadStoredImage() {
        guard let data = UserDefaults.standard.data(forKey: imageStorageKey) else { return }
        persistImage(from: data)
    }

    private func clearPastedImage() {
        pastedImage = nil
        UserDefaults.standard.removeObject(forKey: imageStorageKey)
    }

    // MARK: - Dynamic Sizing

    private let baseWindowSize = CGSize(width: 300, height: 300)
    private let baseFontSize: CGFloat = 11.0
    private let minFontSize: CGFloat = 11.0
    private let maxFontSize: CGFloat = 72.0

    private func calculateScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / baseWindowSize.width
        let heightScale = size.height / baseWindowSize.height
        return min(widthScale, heightScale)
    }

    private func calculateOptimalFontSize(for text: String, in size: CGSize) -> Double {
        guard !text.isEmpty else { return Double(baseFontSize) }

        let scale = calculateScale(for: size)

        let characterCount = text.count
        let availableArea = size.width * size.height
        let characterDensity = Double(characterCount) / Double(availableArea)

        let lowDensity: Double = 0.001
        let highDensity: Double = 0.01

        var densityFactor: CGFloat = 1.0
        if characterDensity < lowDensity {
            densityFactor = 1.5
        } else if characterDensity > highDensity {
            densityFactor = 0.6
        } else {
            let normalizedDensity = (characterDensity - lowDensity) / (highDensity - lowDensity)
            densityFactor = 1.5 - (0.9 * CGFloat(normalizedDensity))
        }

        let calculatedSize = baseFontSize * scale * densityFactor
        let clampedSize = max(minFontSize, min(maxFontSize, calculatedSize))

        return Double(clampedSize)
    }

    private func shouldEnterScrollMode(windowSize: CGSize) -> Bool {
        windowSize.width < 200 || windowSize.height < 200
    }

    private func updateDynamicSizing(for size: CGSize) {
        windowSize = size
        shouldUseScrollMode = shouldEnterScrollMode(windowSize: size)
        guard dynamicSizingEnabled else { return }

        if !shouldUseScrollMode {
            effectiveFontSize = calculateOptimalFontSize(for: noteContent, in: size)
        }
    }

    var currentNSFont: NSFont {
        let size: CGFloat

        if dynamicSizingEnabled {
            if shouldUseScrollMode {
                size = 14.0
            } else {
                size = CGFloat(effectiveFontSize)
            }
        } else {
            size = CGFloat(fontSize)
        }

        switch selectedFont {
        case "handwritten":
            return NSFont(name: "Bradley Hand", size: size) ?? NSFont.systemFont(ofSize: size)
        default:
            return NSFont.systemFont(ofSize: size)
        }
    }

    var currentFontNSColor: NSColor {
        switch fontColorName {
        case "blue":
            return NSColor(calibratedRed: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
        case "red":
            return NSColor(calibratedRed: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
        case "black":
            return NSColor.black
        default:
            return NSColor(calibratedRed: 0.0, green: 0.4, blue: 0.8, alpha: 1.0)
        }
    }

    var currentBackgroundColor: Color {
        switch backgroundColorName {
        case "yellow":
            return Color(red: 1.0, green: 0.98, blue: 0.7)
        case "pink":
            return Color(red: 1.0, green: 0.85, blue: 0.9)
        case "blue":
            return Color(red: 0.85, green: 0.95, blue: 1.0)
        case "green":
            return Color(red: 0.88, green: 0.98, blue: 0.88)
        case "purple":
            return Color(red: 0.93, green: 0.88, blue: 0.98)
        case "orange":
            return Color(red: 1.0, green: 0.92, blue: 0.8)
        default:
            return Color(red: 1.0, green: 0.98, blue: 0.7)
        }
    }
}

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: NSFont
    let textColor: NSColor
    let tabSpaces: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TabInsertionTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = textColor
        textView.string = text
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.tabSpaces = tabSpaces

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TabInsertionTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.isUpdating = false
        }

        textView.font = font
        textView.textColor = textColor

        if textView.tabSpaces != tabSpaces {
            textView.tabSpaces = tabSpaces
        }

        if isFocused, textView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        var isUpdating = false

        init(_ parent: NoteTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }
    }
}

final class TabInsertionTextView: NSTextView {
    var tabSpaces: String = "    "

    override func insertTab(_ sender: Any?) {
        if isEditable {
            insertText(tabSpaces, replacementRange: selectedRange())
        } else {
            super.insertTab(sender)
        }
    }
}

struct SettingsView: View {
    @Binding var selectedFont: String
    @Binding var fontSize: Double
    @Binding var fontColorName: String
    @Binding var backgroundColorName: String
    @Binding var stayOnThisScreen: Bool
    @Binding var dynamicSizingEnabled: Bool
    @Binding var noteOpacity: Double
    @Binding var disappearOnHover: Bool

    let noteId: UUID
    let appDelegate: AppDelegate

    let colorOptions: [(name: String, color: Color, display: String)] = [
        ("yellow", Color(red: 1.0, green: 0.98, blue: 0.7), "Yellow"),
        ("pink", Color(red: 1.0, green: 0.85, blue: 0.9), "Pink"),
        ("blue", Color(red: 0.85, green: 0.95, blue: 1.0), "Blue"),
        ("green", Color(red: 0.88, green: 0.98, blue: 0.88), "Green"),
        ("purple", Color(red: 0.93, green: 0.88, blue: 0.98), "Purple"),
        ("orange", Color(red: 1.0, green: 0.92, blue: 0.8), "Orange")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Font Style")
                            .font(.headline)

                        Picker("", selection: $selectedFont) {
                            Text("Regular").tag("regular")
                            Text("Handwritten").tag("handwritten")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dynamic Text Sizing")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $dynamicSizingEnabled)
                                .labelsHidden()
                        }

                        Text("Automatically adjusts text size to fit the window")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    if !dynamicSizingEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Font Size: \(Int(fontSize))pt")
                                .font(.headline)

                            Slider(value: $fontSize, in: 10...32, step: 1)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Font Size")
                                    .font(.headline)
                                Spacer()
                                Text("Auto")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("Disable dynamic sizing to adjust manually")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pen Color")
                            .font(.headline)

                        HStack(spacing: 16) {
                            ForEach([("blue", Color(red: 0.0, green: 0.4, blue: 0.8), "Blue"),
                                     ("red", Color(red: 0.8, green: 0.0, blue: 0.0), "Red"),
                                     ("black", Color.black, "Black")], id: \.0) { option in
                                Button(action: {
                                    fontColorName = option.0
                                }) {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(option.1)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(fontColorName == option.0 ? Color.blue : Color.gray.opacity(0.3), lineWidth: fontColorName == option.0 ? 3 : 1)
                                            )

                                        Text(option.2)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Background Color")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                            ForEach(colorOptions, id: \.name) { option in
                                Button(action: {
                                    backgroundColorName = option.name
                                }) {
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(option.color)
                                            .frame(width: 50, height: 50)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(backgroundColorName == option.name ? Color.blue : Color.gray.opacity(0.3), lineWidth: backgroundColorName == option.name ? 3 : 1)
                                            )

                                        Text(option.display)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note Opacity: \(Int(noteOpacity * 100))%")
                            .font(.headline)

                        Slider(value: $noteOpacity, in: 0.2...1.0, step: 0.05)

                        Text("Adjust transparency like the Clock app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Hide on Hover", isOn: $disappearOnHover)

                        Text("Hold Command to keep the note visible while hovering")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Toggle("Stay on This Desktop", isOn: $stayOnThisScreen)
                        .onChange(of: stayOnThisScreen) { newValue in
                            appDelegate.updateStayOnThisScreen(for: noteId, stayOnThisScreen: newValue)
                        }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            HStack {
                Spacer()
                Button("Done") {
                    if let settingsPanel = appDelegate.settingsPanels[noteId] {
                        settingsPanel.close()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 400, height: 550)
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}

struct HoverAndWindowController: NSViewRepresentable {
    @Binding var isHovering: Bool
    @Binding var isCommandKeyPressed: Bool
    let disappearOnHover: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isHovering: $isHovering, isCommandKeyPressed: $isCommandKeyPressed)
    }

    func makeNSView(context: Context) -> HoverControlView {
        let view = HoverControlView()
        view.coordinator = context.coordinator
        context.coordinator.disappearOnHover = disappearOnHover
        return view
    }

    func updateNSView(_ nsView: HoverControlView, context: Context) {
        context.coordinator.disappearOnHover = disappearOnHover
        nsView.refreshHoverState()
    }

    class Coordinator {
        @Binding var isHovering: Bool
        @Binding var isCommandKeyPressed: Bool
        var disappearOnHover: Bool = false

        private var updateWorkItem: DispatchWorkItem?

        init(isHovering: Binding<Bool>, isCommandKeyPressed: Binding<Bool>) {
            _isHovering = isHovering
            _isCommandKeyPressed = isCommandKeyPressed
        }

        func updateWindow(_ window: NSWindow?, hovering: Bool, commandPressed: Bool) {
            updateWorkItem?.cancel()

            let shouldIgnore = hovering && !commandPressed && disappearOnHover
            let workItem = DispatchWorkItem { [weak window] in
                guard let window = window else { return }
                if window.ignoresMouseEvents != shouldIgnore {
                    window.ignoresMouseEvents = shouldIgnore
                }
                let shouldAllowMove = !shouldIgnore
                if window.isMovableByWindowBackground != shouldAllowMove {
                    window.isMovableByWindowBackground = shouldAllowMove
                }
                let targetAlpha: CGFloat = shouldIgnore ? 0.0 : 1.0
                if window.alphaValue != targetAlpha {
                    window.alphaValue = targetAlpha
                }
                if window.hasShadow == shouldIgnore {
                    window.hasShadow = !shouldIgnore
                }
            }

            updateWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
    }
}

final class HoverControlView: NSView {
    weak var coordinator: HoverAndWindowController.Coordinator?
    private var flagsMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMonitors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMonitors()
    }

    deinit {
        removeMonitors()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitors()
        } else {
            setupMonitors()
            refreshHoverState()
        }
    }

    func refreshHoverState() {
        DispatchQueue.main.async { [weak self] in
            self?.updateHoverState(with: nil)
        }
    }

    private func setupMonitors() {
        if flagsMonitor == nil {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let isPressed = event.modifierFlags.contains(.command)
                self?.coordinator?.isCommandKeyPressed = isPressed
                self?.updateHoverState(with: event)
                return event
            }
        }

        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] event in
                self?.handleMouseEvent(event)
                return event
            }
        }

        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            ) { [weak self] event in
                self?.handleMouseEvent(event)
            }
        }
    }

    private func removeMonitors() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    private func handleMouseEvent(_ event: NSEvent?) {
        DispatchQueue.main.async { [weak self] in
            self?.updateHoverState(with: event)
        }
    }

    private func updateHoverState(with event: NSEvent?) {
        guard let coordinator = coordinator, let window = window else { return }

        let isHoveringNow = window.frame.contains(NSEvent.mouseLocation)
        if coordinator.isHovering != isHoveringNow {
            coordinator.isHovering = isHoveringNow
        }

        if let event = event {
            coordinator.isCommandKeyPressed = event.modifierFlags.contains(.command)
        }

        coordinator.updateWindow(window, hovering: coordinator.isHovering, commandPressed: coordinator.isCommandKeyPressed)
    }
}

#Preview {
    ContentView(noteId: UUID(), appDelegate: AppDelegate())
}
