import AppKit
import SwiftUI

/// A unified popover for editing tab group settings.
///
/// Combines name, icon, and color editing in a single compact interface.
/// Replaces the separate icon and color popovers and inline rename functionality.
struct GroupSettingsPopover: View {
    @Binding var name: String
    @Binding var selectedIcon: String?
    @Binding var selectedColorHex: String
    @Binding var isPresented: Bool

    @State private var editingName: String = ""
    @State private var selectedIconTab: IconTab = .emoji
    @State private var showCustomSymbolInput = false
    @State private var showEmojiPicker = false
    @State private var showCustomColorInput = false
    @FocusState private var isNameFieldFocused: Bool

    private enum IconTab: Hashable {
        case emoji
        case sfSymbol
    }

    private var displayIcon: String {
        selectedIcon ?? "folder.fill"
    }

    private var selectedColor: Color {
        Color.resolveStoredColor(selectedColorHex)
    }

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            nameSection
            Divider()
            iconSection
            Divider()
            colorSection
        }
        .padding(Layout.padding)
        .frame(width: Layout.popoverWidth)
        .onAppear {
            editingName = name
            // Detect if current icon is emoji or SF Symbol
            selectedIconTab = isEmoji(displayIcon) ? .emoji : .sfSymbol
            DispatchQueue.main.async {
                isNameFieldFocused = true
            }
        }
        .onDisappear {
            commitNameIfChanged()
        }
        .popover(isPresented: $showCustomSymbolInput) {
            CustomSymbolInput(
                selectedSymbol: Binding(
                    get: { selectedIcon ?? "" },
                    set: { selectedIcon = $0.isEmpty ? nil : $0 },
                ),
                isPresented: $showCustomSymbolInput,
                accentColor: selectedColor,
            )
        }
        .popover(isPresented: $showEmojiPicker) {
            EmojiPickerInput(
                selectedEmoji: Binding(
                    get: { selectedIcon ?? "" },
                    set: { selectedIcon = $0.isEmpty ? nil : $0 },
                ),
                isPresented: $showEmojiPicker,
            )
        }
        .if(showCustomColorInput) { view in
            view.popover(isPresented: $showCustomColorInput) {
                ColorWheelPopoverContent(
                    selectedColor: Binding(
                        get: { selectedColor },
                        set: { newColor in
                            selectedColorHex = Color.Components(color: newColor).taggedString
                        },
                    ),
                )
            }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            HStack(spacing: 10) {
                // Preview icon with color
                iconPreview
                    .frame(width: 24, height: 24)

                TextField("Group Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($isNameFieldFocused)
                    .onChange(of: editingName) { _, _ in
                        commitNameIfChanged()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1),
            )
        }
    }

    @ViewBuilder
    private var iconPreview: some View {
        if isEmoji(displayIcon) {
            Text(displayIcon)
                .font(.system(size: 16))
        } else {
            Image(systemName: displayIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selectedColor)
        }
    }

    // MARK: - Icon Section

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            iconTabPicker
            iconGrid
            customButton
        }
    }

    private var iconTabPicker: some View {
        Picker("Icon Type", selection: $selectedIconTab) {
            Text("Emoji").tag(IconTab.emoji)
            Text("Symbol").tag(IconTab.sfSymbol)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var iconGrid: some View {
        switch selectedIconTab {
        case .emoji:
            emojiGrid
        case .sfSymbol:
            symbolGrid
        }
    }

    private var emojiGrid: some View { // 264
        Grid(horizontalSpacing: Layout.gridSpacing, verticalSpacing: Layout.gridSpacing) {
            GridRow {
                ForEach(CuratedIcons.emojis[0 ..< 6], id: \.self) { emojiButton(for: $0) }
            }
            GridRow {
                ForEach(CuratedIcons.emojis[6 ..< 12], id: \.self) { emojiButton(for: $0) }
            }
            GridRow {
                ForEach(CuratedIcons.emojis[12 ..< 18], id: \.self) { emojiButton(for: $0) }
            }
            GridRow {
                ForEach(CuratedIcons.emojis[18 ..< 24], id: \.self) { emojiButton(for: $0) }
            }
        }
    }

    private var symbolGrid: some View {
        Grid(horizontalSpacing: Layout.gridSpacing, verticalSpacing: Layout.gridSpacing) {
            GridRow {
                ForEach(CuratedIcons.groupSymbols[0 ..< 6], id: \.self) { symbolButton(for: $0) }
            }
            GridRow {
                ForEach(CuratedIcons.groupSymbols[6 ..< 12], id: \.self) { symbolButton(for: $0) }
            }
            GridRow {
                ForEach(CuratedIcons.groupSymbols[12 ..< 18], id: \.self) { symbolButton(for: $0) }
            }
            GridRow {
                ForEach(CuratedIcons.groupSymbols[18 ..< 24], id: \.self) { symbolButton(for: $0) }
            }
        }
    }

    private func emojiButton(for emoji: String) -> some View {
        let isSelected = selectedIcon == emoji

        return SelectionItemButton(isSelected: isSelected, accentColor: selectedColor) {
            selectedIcon = emoji
        } content: {
            Text(emoji)
                .font(.system(size: SelectionPopoverLayout.emojiFontSize))
        }
    }

    private func symbolButton(for symbol: String) -> some View {
        let isSelected = selectedIcon == symbol || (selectedIcon == nil && symbol == "folder.fill")

        return SelectionItemButton(isSelected: isSelected, accentColor: selectedColor) {
            selectedIcon = symbol
        } content: {
            Image(systemName: symbol)
                .font(.system(size: SelectionPopoverLayout.symbolFontSize, weight: .medium))
                .foregroundStyle(selectedColor)
        }
        .frame(
            width: SelectionPopoverLayout.itemSize,
            height: SelectionPopoverLayout.itemSize,
        )
    }

    private var customButton: some View {
        Button {
            switch selectedIconTab {
            case .emoji:
                showEmojiPicker = true
            case .sfSymbol:
                showCustomSymbolInput = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                Text(selectedIconTab == .emoji ? "More Emojis..." : "Custom Symbol...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            Grid(horizontalSpacing: Layout.colorGridSpacing, verticalSpacing: Layout.colorGridSpacing) {
                GridRow {
                    ForEach(GroupColor.allCases.prefix(6), id: \.self) { colorButton(for: $0) }
                }
                GridRow {
                    ForEach(GroupColor.allCases.dropFirst(6), id: \.self) { colorButton(for: $0) }
                    customColorButton
                }
            }
        }
    }

    private func colorButton(for color: GroupColor) -> some View {
        let isSelected = selectedColorHex == color.rawValue

        return Button {
            selectedColorHex = color.rawValue
        } label: {
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(width: Layout.colorSwatchSize, height: Layout.colorSwatchSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 2),
                    )

                if isSelected {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 3)
                        .frame(width: Layout.colorRingSize, height: Layout.colorRingSize)
                }
            }
            .frame(width: Layout.colorRingSize, height: Layout.colorRingSize)
        }
        .buttonStyle(.plain)
        .help(color.rawValue)
    }

    private var customColorButton: some View {
        let isCustom = !GroupColor.allCases.contains(where: { $0.rawValue == selectedColorHex })

        return Button {
            showCustomColorInput = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center,
                        ),
                    )
                    .frame(width: Layout.colorSwatchSize, height: Layout.colorSwatchSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 2),
                    )

                if isCustom {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 3)
                        .frame(width: Layout.colorRingSize, height: Layout.colorRingSize)
                }
            }
            .frame(width: Layout.colorRingSize, height: Layout.colorRingSize)
        }
        .buttonStyle(.plain)
        .help("Custom Color")
    }

    // MARK: - Actions

    private func commitNameIfChanged() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != name {
            name = trimmed
        }
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

// MARK: - Curated Icons

private enum CuratedIcons {
    /// Emojis suitable for tab groups (4 rows × 6 columns, matching symbols).
    static let emojis: [String] = [
        // Row 1: Folders & Work (matches folder variants, briefcase, tray, archive)
        "📁", "📂", "🗂️", "💼", "📥", "🗄️",
        // Row 2: Categories & Personal (matches tag, bookmark, flag, heart, star, bolt)
        "🏷️", "🔖", "🚩", "❤️", "⭐️", "⚡️",
        // Row 3: Media & Communication (matches photo, play, book, chat, email, globe)
        "📷", "▶️", "📚", "💬", "📧", "🌐",
        // Row 4: Shopping & Tools (matches cart, bag, card, wrench, gear, terminal)
        "🛒", "👜", "💳", "🔧", "⚙️", "💻",
    ]

    /// SF Symbols suitable for tab groups (4 rows × 6 columns).
    static let groupSymbols: [String] = [
        // Row 1: Folders & Work
        "folder.fill", "folder.badge.plus", "folder.badge.gear", "briefcase.fill", "tray.fill", "archivebox.fill",
        // Row 2: Categories & Personal
        "tag.fill", "bookmark.fill", "flag.fill", "heart.fill", "star.fill", "bolt.fill",
        // Row 3: Media & Communication
        "photo.fill", "play.circle.fill", "book.fill", "bubble.left.fill", "envelope.fill", "globe",
        // Row 4: Shopping & Tools
        "cart.fill", "bag.fill", "creditcard.fill", "wrench.fill", "gear", "terminal.fill",
    ]
}

// MARK: - Layout Constants

private extension GroupSettingsPopover {
    enum Layout {
        static let padding: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static let gridSpacing: CGFloat = 8
        static let popoverWidth: CGFloat = 264

        static let colorSwatchSize: CGFloat = 24
        static let colorRingSize: CGFloat = 32
        static let colorGridSpacing: CGFloat = 8
    }
}
