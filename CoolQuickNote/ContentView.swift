import SwiftUI

struct ContentView: View {
    @AppStorage("noteContent") private var noteContent: String = ""
    @AppStorage("selectedFont") private var selectedFont: String = "regular"
    @AppStorage("fontSize") private var fontSize: Double = 24
    @AppStorage("fontColor") private var fontColorName: String = "blue"
    @AppStorage("backgroundColor") private var backgroundColorName: String = "yellow"
    @AppStorage("alwaysOnTop") private var alwaysOnTop: Bool = true

    @State private var showSettings = false
    @FocusState private var isTextEditorFocused: Bool

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

                Spacer()

                // Close button
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Quit")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Text editor
            TextEditor(text: $noteContent)
                .font(currentFont)
                .foregroundColor(currentFontColor)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isTextEditorFocused)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 200, minHeight: 200)
        .background(currentBackgroundColor)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                selectedFont: $selectedFont,
                fontSize: $fontSize,
                fontColorName: $fontColorName,
                backgroundColorName: $backgroundColorName,
                alwaysOnTop: $alwaysOnTop
            )
        }
        .onAppear {
            // Focus the text editor on launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextEditorFocused = true
            }
        }
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()

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

            // Font size
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size: \(Int(fontSize))pt")
                    .font(.headline)

                Slider(value: $fontSize, in: 10...32, step: 1)
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

            // Always on top toggle
            Toggle("Always on Top", isOn: $alwaysOnTop)
                .onChange(of: alwaysOnTop) { newValue in
                    updateWindowLevel(alwaysOnTop: newValue)
                }

            Spacer()

            // Close button
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400, height: 550)
    }

    func updateWindowLevel(alwaysOnTop: Bool) {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.updateWindowLevel(alwaysOnTop: alwaysOnTop)
        }
    }
}

#Preview {
    ContentView()
}
