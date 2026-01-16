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
                            if dynamicSizingEnabled {
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
            opacityMenu
            Divider()
            settingsCommands
            Divider()
            noteOptionsMenu
            Divider()
            windowActionsMenu
            Divider()
            Button(action: { appDelegate.presentTipJar(from: resolveWindow()) }) {
                Label("Leave a Tip", systemImage: "cup.and.saucer.fill")
            }
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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.gray.opacity(0.6))
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
    private var opacityMenu: some View {
        Menu {
            Button {
                noteOpacity = 1.0
            } label: {
                if noteOpacity == 1.0 {
                    Label("100%", systemImage: "checkmark")
                } else {
                    Text("100%")
                }
            }

            Button {
                noteOpacity = 0.8
            } label: {
                if noteOpacity == 0.8 {
                    Label("80%", systemImage: "checkmark")
                } else {
                    Text("80%")
                }
            }

            Button {
                noteOpacity = 0.6
            } label: {
                if noteOpacity == 0.6 {
                    Label("60%", systemImage: "checkmark")
                } else {
                    Text("60%")
                }
            }

            Button {
                noteOpacity = 0.4
            } label: {
                if noteOpacity == 0.4 {
                    Label("40%", systemImage: "checkmark")
                } else {
                    Text("40%")
                }
            }

            Button {
                noteOpacity = 0.2
            } label: {
                if noteOpacity == 0.2 {
                    Label("20%", systemImage: "checkmark")
                } else {
                    Text("20%")
                }
            }
        } label: {
            Label("Opacity (\(Int(noteOpacity * 100))%)", systemImage: "circle.lefthalf.filled")
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

        Button("Hide All Notes", systemImage: "eye.slash") {
            appDelegate.hideAllNotes()
        }

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
        // Copy the note content to clipboard (this preserves all formatting exactly)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(noteContent, forType: .string)

        let script = """
        tell application "Notes"
            activate

            -- Ensure CoolQuickNote folder exists
            set folderExists to false
            repeat with aFolder in folders
                if name of aFolder is "CoolQuickNote" then
                    set folderExists to true
                    exit repeat
                end if
            end repeat

            if folderExists is false then
                make new folder with properties {name:"CoolQuickNote"}
            end if
        end tell

        delay 0.5

        -- Use System Events to create new note and paste
        tell application "System Events"
            tell process "Notes"
                -- Create new note with Cmd+N
                keystroke "n" using command down
                delay 0.5
                -- Press Enter to move from title to body
                keystroke return
                delay 0.3
                -- Paste clipboard content
                keystroke "v" using command down
            end tell
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

    private func escapeForAppleScript(_ text: String) -> String {
        // Escape special characters and convert newlines to AppleScript's 'return' constant
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")  // Escape backslashes first
            .replacingOccurrences(of: "\"", with: "\\\"")  // Escape quotes

        // Split by newlines and join with AppleScript's return constant
        let lines = escaped.components(separatedBy: "\n")
        if lines.count == 1 {
            return "\"\(escaped)\""
        }

        // Build AppleScript concatenation: "line1" & return & "line2" & return & "line3"
        let quotedLines = lines.map { "\"\($0)\"" }
        return quotedLines.joined(separator: " & return & ")
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

    private let minFontSize: CGFloat = 11.0
    private let maxFontSize: CGFloat = 200.0

    private func measureTextHeight(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }

        let textStorage = NSTextStorage(string: text)
        let textContainer = NSTextContainer(containerSize: CGSize(width: width, height: .greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()

        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textStorage.addAttributes([.font: font], range: NSRange(location: 0, length: text.count))

        layoutManager.glyphRange(for: textContainer)
        return layoutManager.usedRect(for: textContainer).height
    }

    private func calculateOptimalFontSize(for text: String, in size: CGSize) -> Double {
        guard !text.isEmpty else { return Double(maxFontSize) }

        let padding: CGFloat = 24
        let availableWidth = max(size.width - padding, 10)
        let availableHeight = max(size.height - padding, 10)

        let fontForSize: (CGFloat) -> NSFont = { fontSize in
            switch self.selectedFont {
            case "handwritten":
                return NSFont(name: "Bradley Hand", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            default:
                return NSFont.systemFont(ofSize: fontSize)
            }
        }

        var low = minFontSize
        var high = maxFontSize
        var bestFit = minFontSize

        while high - low > 0.5 {
            let mid = (low + high) / 2
            let font = fontForSize(mid)
            let textHeight = measureTextHeight(for: text, font: font, width: availableWidth)

            if textHeight <= availableHeight {
                bestFit = mid
                low = mid + 0.5
            } else {
                high = mid - 0.5
            }
        }

        return Double(max(minFontSize, bestFit))
    }

    private func updateDynamicSizing(for size: CGSize) {
        windowSize = size
        guard dynamicSizingEnabled else { return }

        effectiveFontSize = calculateOptimalFontSize(for: noteContent, in: size)
    }

    var currentNSFont: NSFont {
        let size: CGFloat = dynamicSizingEnabled ? CGFloat(effectiveFontSize) : CGFloat(fontSize)

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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle Command+A for Select All
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "a" {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
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

                    Divider()
                        .padding(.vertical, 4)

                    VStack(spacing: 8) {
                        Text("Enjoying CoolQuickNote?")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Button(action: {
                            appDelegate.presentTipJar(from: appDelegate.settingsPanels[noteId])
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "cup.and.saucer.fill")
                                Text("Leave a Tip")
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .frame(maxWidth: .infinity)

                        Text("Tipping is greatly appreciated but not necessary")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
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

// MARK: - StoreKit Manager

@MainActor
class StoreKitManager: ObservableObject {
    // Published properties for UI updates
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    @Published var errorMessage: String?

    // Product identifiers
    private let productIdentifiers: Set<String> = [
        "com.coolquicknote.tip.small",
        "com.coolquicknote.tip.medium",
        "com.coolquicknote.tip.large"
    ]

    // Transaction listener
    private var updateListenerTask: Task<Void, Error>?

    // Purchase states
    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case purchased
        case failed(Error)
        case cancelled

        static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.loading, .loading),
                 (.purchasing, .purchasing),
                 (.purchased, .purchased),
                 (.cancelled, .cancelled):
                return true
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Load products on initialization
        Task {
            await loadProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Load Products

    /// Loads available products from the App Store
    func loadProducts() async {
        purchaseState = .loading

        do {
            // Request products from App Store
            let storeProducts = try await Product.products(for: productIdentifiers)

            // Sort products by price (lowest to highest)
            self.products = storeProducts.sorted { $0.price < $1.price }

            purchaseState = .idle
            print("✅ Loaded \(products.count) products")
        } catch {
            purchaseState = .failed(error)
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("❌ Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase Product

    /// Purchases a product
    func purchase(_ product: Product) async {
        purchaseState = .purchasing

        do {
            // Attempt purchase
            let result = try await product.purchase()

            // Handle purchase result
            switch result {
            case .success(let verification):
                // Verify the transaction
                let transaction = try checkVerified(verification)

                // Deliver content to the user
                await deliverPurchase(transaction: transaction)

                // Mark transaction as finished
                await transaction.finish()

                purchaseState = .purchased
                print("✅ Purchase successful: \(product.displayName)")

            case .userCancelled:
                purchaseState = .cancelled
                print("ℹ️ User cancelled purchase")

            case .pending:
                purchaseState = .idle
                errorMessage = "Purchase is pending approval"
                print("⏳ Purchase pending approval")

            @unknown default:
                purchaseState = .idle
                print("⚠️ Unknown purchase result")
            }

        } catch {
            purchaseState = .failed(error)
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            print("❌ Purchase failed: \(error)")
        }
    }

    // MARK: - Transaction Verification

    /// Verifies a transaction to ensure it's legitimate
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            // Transaction failed verification
            throw error
        case .verified(let safe):
            // Transaction is verified
            return safe
        }
    }

    // MARK: - Deliver Purchase

    /// Delivers the purchased content to the user
    private func deliverPurchase(transaction: StoreKit.Transaction) async {
        // For consumable products (tips), we just need to acknowledge the purchase
        // No need to persist anything since it's a one-time tip
        print("✅ Delivered purchase: \(transaction.productID)")
    }

    // MARK: - Transaction Listener

    /// Listens for transaction updates from the App Store
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through transaction updates
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // Deliver the purchase
                    await self.deliverPurchase(transaction: transaction)

                    // Finish the transaction
                    await transaction.finish()
                } catch {
                    print("❌ Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Resets the purchase state
    func resetPurchaseState() {
        purchaseState = .idle
        errorMessage = nil
    }

    /// Gets a product by its identifier
    func product(for identifier: String) -> Product? {
        products.first { $0.id == identifier }
    }

    /// Checks if products are loaded
    var hasLoadedProducts: Bool {
        !products.isEmpty
    }
}

// MARK: - Tip Jar View

import StoreKit

struct TipJarView: View {
    @Binding var isPresented: Bool
    @StateObject private var storeKit = StoreKitManager()
    @State private var selectedProduct: Product?
    @State private var showThankYou = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.pink.opacity(0.7))

                Text("Support Development")
                    .font(.title2.bold())

                Text("Your tips help keep this app free, ad-free, and constantly improving")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)

            Divider()
                .padding(.horizontal)

            // Loading or Product Options
            if storeKit.hasLoadedProducts {
                VStack(spacing: 12) {
                    Text("Choose an amount")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        ForEach(storeKit.products, id: \.id) { product in
                            ProductTipButton(
                                product: product,
                                isSelected: selectedProduct?.id == product.id,
                                isDisabled: storeKit.purchaseState == .purchasing
                            ) {
                                selectedProduct = product
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                ProgressView("Loading options...")
                    .padding()
            }

            // Error Message
            if let errorMessage = storeKit.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Purchase Button
            if let product = selectedProduct {
                Button(action: {
                    Task {
                        await purchaseProduct(product)
                    }
                }) {
                    HStack {
                        if storeKit.purchaseState == .purchasing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "heart.fill")
                        }
                        Text(storeKit.purchaseState == .purchasing ? "Processing..." : "Tip \(product.displayPrice)")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(storeKit.purchaseState == .purchasing ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(storeKit.purchaseState == .purchasing)
                .padding(.horizontal)
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Footer note
            VStack(spacing: 8) {
                Text("100% optional – no pressure at all")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("The app will always remain free\nwith all features")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 20)

            // Close button
            Button("Not Now") {
                isPresented = false
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 400, maxHeight: 500)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.3), value: selectedProduct)
        .alert("Thank You! 💙", isPresented: $showThankYou) {
            Button("You're Welcome!") {
                isPresented = false
            }
        } message: {
            Text("Your support means everything! Thanks for helping keep this app free and awesome.")
        }
        .onChange(of: storeKit.purchaseState) { newState in
            if case .purchased = newState {
                showThankYou = true
                storeKit.resetPurchaseState()
            }
        }
        .onAppear {
            print("📱 TipJarView appeared")
            print("📱 Products loaded: \(storeKit.hasLoadedProducts)")
            print("📱 Product count: \(storeKit.products.count)")
            print("📱 Purchase state: \(storeKit.purchaseState)")
            if let error = storeKit.errorMessage {
                print("📱 Error: \(error)")
            }
        }
    }

    private func purchaseProduct(_ product: Product) async {
        await storeKit.purchase(product)
    }
}

// MARK: - Product Tip Button Component
struct ProductTipButton: View {
    let product: Product
    let isSelected: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Text(product.displayPrice)
                    .font(.title3.bold())
                    .foregroundColor(isSelected ? .white : .primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)

                Text(descriptionForProduct(product))
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .opacity(isDisabled ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func descriptionForProduct(_ product: Product) -> String {
        // Map product IDs to friendly descriptions
        if product.id.contains("small") {
            return "Coffee"
        } else if product.id.contains("medium") {
            return "Generous"
        } else if product.id.contains("large") {
            return "Amazing!"
        } else {
            return "Tip"
        }
    }
}
