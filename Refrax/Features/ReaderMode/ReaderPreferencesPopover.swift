import SwiftUI

/// Popover for customizing Reader Mode appearance.
///
/// Allows users to adjust:
/// - Color theme (auto/light/dark/sepia)
/// - Font size
/// - Font family
/// - Line height
struct ReaderPreferencesPopover: View {
    @Environment(ReaderModeManager.self) private var readerManager
    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let width: CGFloat = 280
        static let padding: CGFloat = 16
        static let spacing: CGFloat = 16
        static let labelFontSize: CGFloat = 13
    }

    var body: some View {
        @Bindable var manager = readerManager

        VStack(alignment: .leading, spacing: Layout.spacing) {
            // Theme picker
            themeSection

            Divider()

            // Font size
            fontSizeSection

            Divider()

            // Font family
            fontFamilySection

            Divider()

            // Line height
            lineHeightSection
        }
        .padding(Layout.padding)
        .frame(width: Layout.width)
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Theme")
                .font(.system(size: Layout.labelFontSize, weight: .medium))

            HStack(spacing: 8) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    ThemeButton(
                        theme: theme,
                        isSelected: readerManager.preferences.theme == theme,
                        colorScheme: colorScheme,
                    ) {
                        readerManager.preferences.theme = theme
                    }
                }
            }
        }
    }

    // MARK: - Font Size Section

    private var fontSizeSection: some View {
        HStack {
            Text("Font Size")
                .font(.system(size: Layout.labelFontSize, weight: .medium))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    decreaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(.plain)
                .disabled(readerManager.preferences.fontSize <= 12)

                Text("\(readerManager.preferences.fontSize)")
                    .font(.system(size: Layout.labelFontSize).monospacedDigit())
                    .frame(width: 24)

                Button {
                    increaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(.plain)
                .disabled(readerManager.preferences.fontSize >= 32)
            }
        }
    }

    private func decreaseFontSize() {
        let newSize = max(12, readerManager.preferences.fontSize - 2)
        readerManager.preferences.fontSize = newSize
    }

    private func increaseFontSize() {
        let newSize = min(32, readerManager.preferences.fontSize + 2)
        readerManager.preferences.fontSize = newSize
    }

    // MARK: - Font Family Section

    private var fontFamilySection: some View {
        HStack {
            Text("Font")
                .font(.system(size: Layout.labelFontSize, weight: .medium))

            Spacer()

            Picker("", selection: Binding(
                get: { readerManager.preferences.fontFamily },
                set: { readerManager.preferences.fontFamily = $0 },
            )) {
                ForEach(ReaderFont.allCases, id: \.self) { font in
                    Text(font.displayName).tag(font)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: - Line Height Section

    private var lineHeightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Line Spacing")
                    .font(.system(size: Layout.labelFontSize, weight: .medium))

                Spacer()

                Text(String(format: "%.1f", readerManager.preferences.lineHeight))
                    .font(.system(size: Layout.labelFontSize).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { readerManager.preferences.lineHeight },
                    set: { readerManager.preferences.lineHeight = $0 },
                ),
                in: 1.2 ... 2.0,
                step: 0.1,
            )
        }
    }
}

// MARK: - Theme Button

private struct ThemeButton: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(theme.backgroundColor(for: colorScheme))
                    .stroke(
                        isSelected ? Color.appAccentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1,
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        // Show icon for auto theme
                        if theme == .auto {
                            Image(systemName: theme.iconName)
                                .font(.system(size: 14))
                                .foregroundStyle(theme.textColor(for: colorScheme))
                        }
                    }

                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
