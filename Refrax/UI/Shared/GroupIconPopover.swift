import SwiftUI

/// A compact popover for selecting tab group icons.
///
/// Provides quick selection from curated SF Symbols with a preview of the current selection.
/// More compact than `IconPicker`, optimized for popup presentation rather than sheet.
struct GroupIconPopover: View {
    @Binding var selectedIcon: String?
    var accentColor: Color = .blue
    @Binding var isPresented: Bool

    @State private var showCustomSymbolInput = false
    @State private var customSymbolName: String = ""
    @State private var debouncedSymbolName: String = ""
    @State private var debounceTask: Task<Void, any Error>?
    @FocusState private var isTextFieldFocused: Bool

    private var displayIcon: String {
        selectedIcon ?? "folder.fill"
    }

    var body: some View {
        VStack(spacing: SelectionPopoverLayout.sectionSpacing) {
            header
            symbolGrid
            customSymbolButton
        }
        .padding(SelectionPopoverLayout.padding)
        .frame(width: Layout.popoverWidth)
        .popover(isPresented: $showCustomSymbolInput) {
            CustomSymbolInput(
                selectedSymbol: Binding(
                    get: { selectedIcon ?? "" },
                    set: { selectedIcon = $0.isEmpty ? nil : $0 },
                ),
                isPresented: $showCustomSymbolInput,
                accentColor: accentColor,
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Group Icon")
                .font(.headline)

            Spacer()

            previewIcon
        }
    }

    private var previewIcon: some View {
        SelectionPreviewContainer(accentColor: accentColor) {
            Image(systemName: displayIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Symbol Grid

    private var symbolGrid: some View {
        LazyVGrid(columns: SelectionPopoverLayout.gridColumns, spacing: SelectionPopoverLayout.gridSpacing) {
            ForEach(CuratedIcons.groupSymbols, id: \.self) { symbol in
                iconButton(for: symbol)
            }
        }
    }

    private func iconButton(for symbol: String) -> some View {
        let isSelected = selectedIcon == symbol || (selectedIcon == nil && symbol == "folder.fill")

        return SelectionItemButton(isSelected: isSelected, accentColor: accentColor) {
            selectedIcon = symbol
        } content: {
            Image(systemName: symbol)
                .font(.system(size: SelectionPopoverLayout.symbolFontSize, weight: .medium))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Custom Symbol

    private var customSymbolButton: some View {
        Button {
            showCustomSymbolInput = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                Text("Custom Symbol...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
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

// MARK: - Layout Constants

private extension GroupIconPopover {
    enum Layout {
        static let popoverWidth: CGFloat = 240
    }
}

// MARK: - Curated Icons

private enum CuratedIcons {
    /// SF Symbols suitable for tab groups - focused on organizational concepts.
    static let groupSymbols: [String] = [
        // Core folder variants
        "folder.fill", "folder.badge.plus", "folder.badge.gear",
        // Work & productivity
        "briefcase.fill", "tray.fill", "archivebox.fill",
        // Categories
        "tag.fill", "bookmark.fill", "flag.fill",
        // Personal
        "heart.fill", "star.fill", "bolt.fill",
        // Media & content
        "photo.fill", "play.circle.fill", "book.fill",
        // Communication
        "bubble.left.fill", "envelope.fill", "globe",
        // Shopping & finance
        "cart.fill", "bag.fill", "creditcard.fill",
        // Tools
        "wrench.fill", "gear", "terminal.fill",
    ]
}
