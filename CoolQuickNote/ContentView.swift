import SwiftUI
import AppKit

struct ContentView: View {
    let noteId: UUID
    @ObservedObject var appDelegate: AppDelegate

    @AppStorage var noteContent: String
    @AppStorage var selectedFont: String
    @AppStorage var fontSize: Double
    @AppStorage var fontColorName: String
    @AppStorage var backgroundColorName: String
    @AppStorage var alwaysOnTop: Bool
    @AppStorage var dynamicSizingEnabled: Bool

    @State private var showSettings = false
    @State private var windowSize: CGSize = .zero
    @State private var effectiveFontSize: Double = 24.0
    @State private var shouldUseScrollMode: Bool = false
    @FocusState private var isTextEditorFocused: Bool
    @State private var isHoveringWindow = false
    @State private var currentWindow: NSWindow?
    @State private var isAppActive = true
    @State private var isWindowKey = false

    init(noteId: UUID, appDelegate: AppDelegate) {
        self.noteId = noteId
        self.appDelegate = appDelegate

        // Initialize @AppStorage with note-specific keys
        _noteContent = AppStorage(wrappedValue: "", "note_\(noteId.uuidString)_content")
        _selectedFont = AppStorage(wrappedValue: "regular", "note_\(noteId.uuidString)_font")
        _fontSize = AppStorage(wrappedValue: 24, "note_\(noteId.uuidString)_fontSize")
        _fontColorName = AppStorage(wrappedValue: "blue", "note_\(noteId.uuidString)_fontColor")
        _backgroundColorName = AppStorage(wrappedValue: "yellow", "note_\(noteId.uuidString)_backgroundColor")
        _alwaysOnTop = AppStorage(wrappedValue: true, "note_\(noteId.uuidString)_alwaysOnTop")
        _dynamicSizingEnabled = AppStorage(wrappedValue: true, "note_\(noteId.uuidString)_dynamicSizing")
    }

    // Format current date and time for note header
    private func formatCurrentDateTime() -> String {
        let formatter = DateFormatter()

        // Date format: "Jan 03, 2026 Sat"
        formatter.dateFormat = "MMM dd, yyyy EEE"
        let dateString = formatter.string(from: Date())

        // Time format: "9:10 PM"
        formatter.dateFormat = "h:mm a"
        let timeString = formatter.string(from: Date())

        return "\(dateString)\n\(timeString)\n"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Settings bar
            HStack {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button(action: { appDelegate.createNewNote() }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("New Note")

                Spacer()

                // Close button - only show if more than one note is open
                if appDelegate.noteCount > 1 {
                    Button(action: { appDelegate.closeNote(id: noteId) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Close Note")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Text editor with GeometryReader for dynamic sizing
            GeometryReader { geometry in
                TextEditor(text: $noteContent)
                    .font(dynamicFont)
                    .foregroundColor(currentFontColor)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isTextEditorFocused)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: geometry.size) { newSize in
                        updateDynamicSizing(for: newSize)
                    }
                    .onChange(of: noteContent) { _ in
                        if dynamicSizingEnabled && !shouldUseScrollMode {
                            updateDynamicSizing(for: windowSize)
                        }
                    }
                    .onAppear {
                        updateDynamicSizing(for: geometry.size)
                    }
            }
        }
        .frame(minWidth: 100, minHeight: 60)
        .background(currentBackgroundColor)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .onHover { hovering in
            isHoveringWindow = hovering
        }
        .background(WindowAccessor(window: $currentWindow))
        .sheet(isPresented: $showSettings) {
            SettingsView(
                selectedFont: $selectedFont,
                fontSize: $fontSize,
                fontColorName: $fontColorName,
                backgroundColorName: $backgroundColorName,
                alwaysOnTop: $alwaysOnTop,
                dynamicSizingEnabled: $dynamicSizingEnabled,
                noteId: noteId,
                appDelegate: appDelegate
            )
        }
        .onAppear {
            // Insert date/time if note is blank
            if noteContent.isEmpty {
                noteContent = formatCurrentDateTime()
            }

            // Focus the text editor on launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextEditorFocused = true
            }

            // Sync initial app/window state for button visibility
            isAppActive = NSApp.isActive
            isWindowKey = currentWindow?.isKeyWindow ?? false

            // Ensure buttons are visible on initial appearance
            DispatchQueue.main.async {
                currentWindow = resolveWindow()
                updateTrafficLightButtons(visible: shouldShowButtons)
            }
        }
        .onChange(of: currentWindow) { window in
            if window != nil {
                // Start with buttons visible, then update based on state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    updateTrafficLightButtons(visible: shouldShowButtons)
                }
            }

            isWindowKey = window?.isKeyWindow ?? false
        }
        .onChange(of: isHoveringWindow) { _ in
            updateTrafficLightButtons(visible: shouldShowButtons)
        }
        .onChange(of: isTextEditorFocused) { _ in
            updateTrafficLightButtons(visible: shouldShowButtons)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAppActive = true
            // Refresh window reference and update buttons with a small delay to ensure window is ready
            DispatchQueue.main.async {
                currentWindow = resolveWindow()
                updateTrafficLightButtons(visible: shouldShowButtons)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isAppActive = false
            updateTrafficLightButtons(visible: shouldShowButtons)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow {
                currentWindow = window
            }
            isWindowKey = true
            // Update buttons immediately and again after a short delay to handle timing issues
            updateTrafficLightButtons(visible: shouldShowButtons)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                updateTrafficLightButtons(visible: shouldShowButtons)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow {
                currentWindow = window
            }
            isWindowKey = false
            updateTrafficLightButtons(visible: shouldShowButtons)
        }
    }

    var shouldShowButtons: Bool {
        // Make traffic lights full opacity when app is active; dimmed when inactive
        isAppActive
    }

    func updateTrafficLightButtons(visible: Bool) {
        guard let window = resolveWindow() else { return }

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for buttonType in buttons {
            if let button = window.standardWindowButton(buttonType) {
                // Instead of hiding, dim the buttons when inactive
                button.alphaValue = visible ? 1.0 : 0.3
            }
        }
    }

    private func resolveWindow() -> NSWindow? {
        if let window = currentWindow {
            return window
        }
        if let key = NSApp?.keyWindow {
            currentWindow = key
            return key
        }
        if let main = NSApp?.mainWindow {
            currentWindow = main
            return main
        }
        if let first = NSApp?.windows.first {
            currentWindow = first
            return first
        }
        return nil
    }

    var currentFont: Font {
        let size = CGFloat(fontSize)
        switch selectedFont {
        case "handwritten":
            return Font.custom("Bradley Hand", size: size)
        default:
            return Font.system(size: size)
        }
    }

    // MARK: - Dynamic Sizing

    // Constants for dynamic sizing
    private let baseWindowSize = CGSize(width: 300, height: 300)
    private let baseFontSize: CGFloat = 24.0
    private let minFontSize: CGFloat = 10.0
    private let maxFontSize: CGFloat = 72.0

    // Calculate scale factor based on window size
    private func calculateScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / baseWindowSize.width
        let heightScale = size.height / baseWindowSize.height
        // Use minimum to ensure content fits
        return min(widthScale, heightScale)
    }

    // Calculate optimal font size based on content and available space
    private func calculateOptimalFontSize(for text: String, in size: CGSize) -> Double {
        guard !text.isEmpty else { return Double(baseFontSize) }

        let scale = calculateScale(for: size)

        // Character density heuristic: more text = smaller font
        let characterCount = text.count
        let availableArea = size.width * size.height
        let characterDensity = Double(characterCount) / Double(availableArea)

        // Density thresholds (tuned for readability)
        let lowDensity: Double = 0.001  // Very little text
        let highDensity: Double = 0.01  // Lots of text

        var densityFactor: CGFloat = 1.0
        if characterDensity < lowDensity {
            // Sparse text: scale up more aggressively
            densityFactor = 1.5
        } else if characterDensity > highDensity {
            // Dense text: scale down to fit more
            densityFactor = 0.6
        } else {
            // Linear interpolation between thresholds
            let normalizedDensity = (characterDensity - lowDensity) / (highDensity - lowDensity)
            densityFactor = 1.5 - (0.9 * CGFloat(normalizedDensity))
        }

        // Calculate font size with scale and density adjustments
        let calculatedSize = baseFontSize * scale * densityFactor

        // Clamp to reasonable bounds
        let clampedSize = max(minFontSize, min(maxFontSize, calculatedSize))

        return Double(clampedSize)
    }

    // Determine if we should be in scroll mode (window too small)
    private func shouldEnterScrollMode(windowSize: CGSize) -> Bool {
        return windowSize.width < 200 || windowSize.height < 200
    }

    // Update dynamic sizing based on window size
    private func updateDynamicSizing(for size: CGSize) {
        guard dynamicSizingEnabled else { return }

        windowSize = size
        shouldUseScrollMode = shouldEnterScrollMode(windowSize: size)

        if !shouldUseScrollMode {
            effectiveFontSize = calculateOptimalFontSize(for: noteContent, in: size)
        }
    }

    // The font to use based on dynamic sizing state
    var dynamicFont: Font {
        let size: CGFloat

        if dynamicSizingEnabled {
            if shouldUseScrollMode {
                // In scroll mode, use a fixed readable size
                size = 14.0
            } else {
                // Use dynamically calculated size
                size = CGFloat(effectiveFontSize)
            }
        } else {
            // Manual mode: use user's slider value
            size = CGFloat(fontSize)
        }

        switch selectedFont {
        case "handwritten":
            return Font.custom("Bradley Hand", size: size)
        default:
            return Font.system(size: size)
        }
    }

    var currentFontColor: Color {
        switch fontColorName {
        case "blue":
            return Color(red: 0.0, green: 0.4, blue: 0.8) // Standard blue pen
        case "red":
            return Color(red: 0.8, green: 0.0, blue: 0.0) // Red pen
        case "black":
            return Color.black
        default:
            return Color(red: 0.0, green: 0.4, blue: 0.8) // Default blue
        }
    }

    var currentBackgroundColor: Color {
        switch backgroundColorName {
        case "yellow":
            return Color(red: 1.0, green: 0.98, blue: 0.7) // Classic sticky note yellow
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

struct SettingsView: View {
    @Binding var selectedFont: String
    @Binding var fontSize: Double
    @Binding var fontColorName: String
    @Binding var backgroundColorName: String
    @Binding var alwaysOnTop: Bool
    @Binding var dynamicSizingEnabled: Bool

    let noteId: UUID
    let appDelegate: AppDelegate

    @Environment(\.dismiss) var dismiss

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
            // Title at the top
            HStack {
                Text("Settings")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Font selection
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

                    // Dynamic Text Sizing toggle
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

                    // Font size (conditionally shown)
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

                    // Pen color
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

                    // Background color
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

                    // Always on top toggle
                    Toggle("Always on Top", isOn: $alwaysOnTop)
                        .onChange(of: alwaysOnTop) { newValue in
                            appDelegate.updateWindowLevel(for: noteId, alwaysOnTop: newValue)
                        }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Done button at the bottom
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
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

// Helper to access the window from SwiftUI
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

#Preview {
    ContentView(noteId: UUID(), appDelegate: AppDelegate())
}
