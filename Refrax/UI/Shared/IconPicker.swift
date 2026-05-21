import SwiftUI

/// A picker for selecting space icons from curated emojis or SF Symbols.
///
/// Provides two modes of selection:
/// - **Emoji**: Curated emojis with access to full system emoji picker
/// - **Symbol**: Curated SF Symbols with option to enter custom symbol names
struct IconPicker: View {
    @Binding var selectedIcon: String
    var accentColor: Color = .blue

    @State private var selectedTab: IconTab = .sfSymbol
    @State private var showFullEmojiPicker = false
    @State private var showCustomSymbolInput = false

    var body: some View {
        VStack(alignment: .center, spacing: Layout.sectionSpacing) {
            tabPicker
            gridContent
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Icon Type", selection: $selectedTab) {
            Text("Symbol").tag(IconTab.sfSymbol)
            Text("Emoji").tag(IconTab.emoji)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: Layout.tabPickerWidth)
    }

    // MARK: - Grid Content

    @ViewBuilder
    private var gridContent: some View {
        VStack(alignment: .leading, spacing: Layout.gridSpacing) {
            switch selectedTab {
            case .emoji:
                emojiGrid
            case .sfSymbol:
                sfSymbolGrid
            }
        }
        .frame(height: Layout.gridHeight)
        .padding(.vertical, 8) // Prevent selection indicator clipping
    }

    // MARK: - Emoji Grid

    private var emojiGrid: some View {
        LazyVGrid(columns: Layout.gridColumns, spacing: Layout.gridSpacing) {
            ForEach(CuratedIcons.emojis, id: \.self) { emoji in
                Button {
                    selectedIcon = emoji
                } label: {
                    Text(emoji)
                        .font(.system(size: Layout.emojiFontSize))
                        .frame(width: Layout.itemSize, height: Layout.itemSize)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.itemCornerRadius)
                                .fill(selectedIcon == emoji ? accentColor.opacity(0.2) : Color.clear),
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.itemCornerRadius)
                                .strokeBorder(
                                    selectedIcon == emoji ? accentColor.opacity(0.5) : Color.clear,
                                    lineWidth: 1.5,
                                ),
                        )
                }
                .buttonStyle(.plain)
            }

            // More button as grid item
            moreEmojiButton
        }
    }

    private var moreEmojiButton: some View {
        Button {
            showFullEmojiPicker = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: Layout.symbolFontSize))
                .foregroundStyle(.secondary)
                .frame(width: Layout.itemSize, height: Layout.itemSize)
                .background(
                    RoundedRectangle(cornerRadius: Layout.itemCornerRadius)
                        .fill(Color.secondary.opacity(0.1)),
                )
        }
        .buttonStyle(.plain)
        .help("More emojis")
        .popover(isPresented: $showFullEmojiPicker) {
            EmojiPickerPopover(selectedEmoji: $selectedIcon, isPresented: $showFullEmojiPicker)
        }
    }

    // MARK: - SF Symbol Grid

    private var sfSymbolGrid: some View {
        LazyVGrid(columns: Layout.gridColumns, spacing: Layout.gridSpacing) {
            ForEach(CuratedIcons.sfSymbols, id: \.self) { symbol in
                Button {
                    selectedIcon = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: Layout.symbolFontSize, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: Layout.itemSize, height: Layout.itemSize)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.itemCornerRadius)
                                .fill(selectedIcon == symbol ? accentColor.opacity(0.2) : Color.clear),
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.itemCornerRadius)
                                .strokeBorder(
                                    selectedIcon == symbol ? accentColor.opacity(0.5) : Color.clear,
                                    lineWidth: 1.5,
                                ),
                        )
                }
                .buttonStyle(.plain)
            }

            // More button as grid item
            moreSymbolButton
        }
    }

    private var moreSymbolButton: some View {
        Button {
            showCustomSymbolInput = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: Layout.symbolFontSize))
                .foregroundStyle(.secondary)
                .frame(width: Layout.itemSize, height: Layout.itemSize)
                .background(
                    RoundedRectangle(cornerRadius: Layout.itemCornerRadius)
                        .fill(Color.secondary.opacity(0.1)),
                )
        }
        .buttonStyle(.plain)
        .help("Custom symbol")
        .popover(isPresented: $showCustomSymbolInput) {
            CustomSymbolPopover(
                selectedSymbol: $selectedIcon,
                isPresented: $showCustomSymbolInput,
                accentColor: accentColor,
            )
        }
    }
}

// MARK: - Icon Tab

private enum IconTab: Hashable {
    case emoji
    case sfSymbol
}

// MARK: - Layout Constants

private extension IconPicker {
    enum Layout {
        static let sectionSpacing: CGFloat = 12
        static let gridSpacing: CGFloat = 8
        static let itemSize: CGFloat = 36
        static let itemCornerRadius: CGFloat = 8
        static let emojiFontSize: CGFloat = 20
        static let symbolFontSize: CGFloat = 16
        static let tabPickerWidth: CGFloat = 160
        static let gridHeight: CGFloat = 140

        static let gridColumns = [GridItem(.adaptive(minimum: itemSize), spacing: gridSpacing)]
    }
}

// MARK: - Curated Icons

private enum CuratedIcons {
    /// Emojis suitable for browser space categories.
    static let emojis: [String] = [
        // Productivity & Work
        "💼", "📁", "📊", "💻", "📝",
        // Personal & Home
        "🏠", "👤", "❤️", "⭐️", "🎯",
        // Learning & Research
        "📚", "🔬", "🎓", "💡", "🧠",
        // Creative & Media
        "🎨", "🎵", "📷", "🎬", "✏️",
        // Communication & Social
        "💬", "📧", "🌐", "👥", "📱",
        // Finance & Shopping
        "💰", "🛒", "💳", "📈", "🏦",
    ]

    /// SF Symbols suitable for browser space categories.
    static let sfSymbols: [String] = [
        // Productivity & Work
        "briefcase.fill", "folder.fill", "doc.text.fill", "calendar", "chart.bar.fill",
        // Personal & Home
        "house.fill", "person.fill", "heart.fill", "star.fill", "bookmark.fill",
        // Learning & Research
        "book.fill", "graduationcap.fill", "lightbulb.fill", "magnifyingglass", "brain.head.profile",
        // Creative & Media
        "paintbrush.fill", "music.note", "camera.fill", "play.circle.fill", "pencil",
        // Communication & Social
        "bubble.left.fill", "envelope.fill", "globe", "person.2.fill", "phone.fill",
        // Finance & Shopping
        "dollarsign.circle.fill", "cart.fill", "creditcard.fill", "building.columns.fill", "bag.fill",
    ]
}

// MARK: - Emoji Picker Popover

/// A popover that displays the system emoji picker via a text field.
private struct EmojiPickerPopover: View {
    @Binding var selectedEmoji: String
    @Binding var isPresented: Bool

    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Select Emoji")
                .font(.headline)

            Text("Use the emoji picker or press Control+Command+Space")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            EmojiTextField(text: $inputText) { emoji in
                selectedEmoji = emoji
                isPresented = false
            }
            .frame(width: 60, height: 44)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 240)
    }
}

// MARK: - Custom Symbol Popover

/// A popover for entering a custom SF Symbol name with live preview.
private struct CustomSymbolPopover: View {
    @Binding var selectedSymbol: String
    @Binding var isPresented: Bool
    let accentColor: Color

    @State private var symbolName: String = ""
    @State private var debouncedName: String = ""
    @State private var debounceTask: Task<Void, any Error>?
    @FocusState private var isTextFieldFocused: Bool

    private var isValidSymbol: Bool {
        !debouncedName.isEmpty && NSImage(systemSymbolName: debouncedName, accessibilityDescription: nil) != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Custom Symbol")
                .font(.headline)

            symbolPreview

            VStack(alignment: .leading, spacing: 4) {
                TextField("SF Symbol name", text: $symbolName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onChange(of: symbolName) { _, newValue in
                        scheduleDebounce(for: newValue)
                    }

                Text("e.g., star.fill, folder, airplane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Use Symbol") {
                    selectedSymbol = debouncedName
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidSymbol)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    private var symbolPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(accentColor.opacity(0.15))
                .frame(width: 64, height: 64)

            if isValidSymbol {
                Image(systemName: debouncedName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accentColor)
            } else if !debouncedName.isEmpty {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "square.dashed")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func scheduleDebounce(for value: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try await Task.sleep(for: .milliseconds(300))
            debouncedName = value
        }
    }
}

// MARK: - Emoji Text Field (AppKit)

/// A text field wrapper that shows the emoji picker and captures single emoji input.
private struct EmojiTextField: NSViewRepresentable {
    @Binding var text: String
    var onEmojiSelected: (String) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.alignment = .center
        textField.font = .systemFont(ofSize: 28)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.placeholderString = "😀"

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            NSApp.orderFrontCharacterPalette(nil)
        }

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context _: Context) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEmojiSelected: onEmojiSelected)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onEmojiSelected: (String) -> Void

        init(text: Binding<String>, onEmojiSelected: @escaping (String) -> Void) {
            _text = text
            self.onEmojiSelected = onEmojiSelected
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            let newValue = textField.stringValue

            if let firstEmoji = newValue.first, firstEmoji.isEmoji {
                let emoji = String(firstEmoji)
                // Defer SwiftUI state mutations to next runloop
                DispatchQueue.main.async {
                    self.text = emoji
                    self.onEmojiSelected(emoji)
                }
            }
        }
    }
}

// MARK: - Character Extension

private extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
