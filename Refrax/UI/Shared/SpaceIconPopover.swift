import SwiftUI

/// A compact popover for selecting space icons (emojis or SF Symbols).
///
/// Similar to `GroupIconPopover` but supports both emoji and SF Symbol selection
/// via a segmented picker. Optimized for popup presentation from context menus.
struct SpaceIconPopover: View {
    @Binding var selectedIcon: String
    var accentColor: Color = .blue
    @Binding var isPresented: Bool

    @State private var selectedTab: IconTab = .emoji
    @State private var showCustomSymbolInput = false
    @State private var showEmojiPicker = false

    private enum IconTab: Hashable {
        case emoji
        case sfSymbol
    }

    var body: some View {
        VStack(spacing: SelectionPopoverLayout.sectionSpacing) {
            header
            tabPicker
            iconGrid
            customButton
        }
        .padding(SelectionPopoverLayout.padding)
        .frame(width: Layout.popoverWidth)
        .popover(isPresented: $showCustomSymbolInput) {
            CustomSymbolInput(
                selectedSymbol: $selectedIcon,
                isPresented: $showCustomSymbolInput,
                accentColor: accentColor,
            )
        }
        .popover(isPresented: $showEmojiPicker) {
            EmojiPickerInput(
                selectedEmoji: $selectedIcon,
                isPresented: $showEmojiPicker,
            )
        }
        .onAppear {
            // Detect if current icon is emoji or SF Symbol
            selectedTab = isEmoji(selectedIcon) ? .emoji : .sfSymbol
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Space Icon")
                .font(.headline)

            Spacer()

            previewIcon
        }
    }

    private var previewIcon: some View {
        SelectionPreviewContainer(accentColor: accentColor) {
            if isEmoji(selectedIcon) {
                Text(selectedIcon)
                    .font(.system(size: 18))
            } else {
                Image(systemName: selectedIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accentColor)
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Icon Type", selection: $selectedTab) {
            Text("Emoji").tag(IconTab.emoji)
            Text("Symbol").tag(IconTab.sfSymbol)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Icon Grid

    @ViewBuilder
    private var iconGrid: some View {
        switch selectedTab {
        case .emoji:
            emojiGrid
        case .sfSymbol:
            symbolGrid
        }
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: SelectionPopoverLayout.gridColumns, spacing: SelectionPopoverLayout.gridSpacing) {
            ForEach(CuratedIcons.emojis, id: \.self) { emoji in
                emojiButton(for: emoji)
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: SelectionPopoverLayout.gridColumns, spacing: SelectionPopoverLayout.gridSpacing) {
            ForEach(CuratedIcons.sfSymbols, id: \.self) { symbol in
                symbolButton(for: symbol)
            }
        }
    }

    private func emojiButton(for emoji: String) -> some View {
        let isSelected = selectedIcon == emoji

        return SelectionItemButton(isSelected: isSelected, accentColor: accentColor) {
            selectedIcon = emoji
        } content: {
            Text(emoji)
                .font(.system(size: SelectionPopoverLayout.emojiFontSize))
        }
    }

    private func symbolButton(for symbol: String) -> some View {
        let isSelected = selectedIcon == symbol

        return SelectionItemButton(isSelected: isSelected, accentColor: accentColor) {
            selectedIcon = symbol
        } content: {
            Image(systemName: symbol)
                .font(.system(size: SelectionPopoverLayout.symbolFontSize, weight: .medium))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Custom Button

    private var customButton: some View {
        Button {
            switch selectedTab {
            case .emoji:
                showEmojiPicker = true
            case .sfSymbol:
                showCustomSymbolInput = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                Text(selectedTab == .emoji ? "More Emojis..." : "Custom Symbol...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func isEmoji(_ string: String) -> Bool {
        guard string.count == 1,
              let scalar = string.unicodeScalars.first
        else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || string.unicodeScalars.count > 1)
    }
}

// MARK: - Custom Symbol Input

private struct CustomSymbolInput: View {
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

// MARK: - Emoji Picker Input

private struct EmojiPickerInput: View {
    @Binding var selectedEmoji: String
    @Binding var isPresented: Bool

    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Select Emoji")
                .font(.headline)

            Text("Use the emoji picker or press ⌃⌘Space")
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

// MARK: - Emoji Text Field (AppKit)

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

// MARK: - Layout Constants

private extension SpaceIconPopover {
    enum Layout {
        static let popoverWidth: CGFloat = 260
    }
}

// MARK: - Curated Icons

private enum CuratedIcons {
    /// Emojis suitable for browser spaces.
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
    ]

    /// SF Symbols suitable for browser spaces.
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
    ]
}
