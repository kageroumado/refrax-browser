import SwiftUI

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    let highlightedItemId: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            // MARK: - Window Appearance

            Section {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(AppearanceTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .highlightable(id: "appearance.theme", highlightedItemId: highlightedItemId)

                SettingsColorPicker(
                    label: "Accent color",
                    selectedColor: $settings.customAccentColor,
                    systemColor: .accentColor,
                )
                .highlightable(id: "appearance.accentColor", highlightedItemId: highlightedItemId)

                SettingsColorPicker(
                    label: "Window background",
                    selectedColor: $settings.customWindowBackgroundColor,
                    systemColor: Color(.windowBackgroundColor),
                )
                .highlightable(id: "appearance.windowBackground", highlightedItemId: highlightedItemId)
            } header: {
                Text("Window Appearance")
            } footer: {
                Text("Accent color applies to buttons and links. Window background is the base color when no dynamic color applies.")
            }

            // MARK: - Reset

            Section {
                Button("Reset Window Appearance to Defaults") {
                    settings.customAccentColorHex = BrowserSettings.Defaults.accentColorHex
                    settings.customWindowBackgroundColor = Color.Components(encoded: BrowserSettings.Defaults.windowBackgroundColorHex)
                    settings.windowBackgroundMixAmount = BrowserSettings.Defaults.windowBackgroundMixAmount
                    settings.windowBackgroundMixMode = BrowserSettings.Defaults.windowBackgroundMixMode
                    settings.windowBackgroundFillOpacity = BrowserSettings.Defaults.windowBackgroundFillOpacity
                    settings.enableSpaceWindowColoring = false
                    settings.enableWebsiteWindowColoring = false
                    settings.websiteColorUseSolidBlend = true
                }
            }

            // MARK: - Color Blending

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Blend strength")
                        Spacer()
                        Slider(value: $settings.windowBackgroundMixAmount, in: 0 ... 1)
                            .frame(width: 200)
                    }
                    Text("\(Int(settings.windowBackgroundMixAmount * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .highlightable(id: "appearance.mixAmount", highlightedItemId: highlightedItemId)

                Picker("Blend mode", selection: $settings.windowBackgroundMixMode) {
                    ForEach(blendModeOptions, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .highlightable(id: "appearance.mixMode", highlightedItemId: highlightedItemId)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fill opacity")
                        Spacer()
                        Slider(value: $settings.windowBackgroundFillOpacity, in: 0 ... 1)
                            .frame(width: 200)
                    }
                    Text("\(Int(settings.windowBackgroundFillOpacity * 100))% — \(settings.windowBackgroundFillOpacity < 0.3 ? "Transparent glass" : settings.windowBackgroundFillOpacity < 0.7 ? "Semi-transparent" : "Opaque")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .highlightable(id: "appearance.fillOpacity", highlightedItemId: highlightedItemId)
            } header: {
                Text("Color Blending")
            } footer: {
                Text("Controls how dynamic colors blend with the base color. Fill opacity controls how much of the desktop shows through the window background.")
            }

            // MARK: - Dynamic Colors

            Section {
                Toggle("Use space colors", isOn: $settings.enableSpaceWindowColoring)
                    .highlightable(id: "appearance.spaceColoring", highlightedItemId: highlightedItemId)

                Toggle("Use website theme colors", isOn: $settings.enableWebsiteWindowColoring)
                    .highlightable(id: "appearance.websiteColoring", highlightedItemId: highlightedItemId)

                if settings.enableWebsiteWindowColoring {
                    Toggle("Use solid color for websites", isOn: $settings.websiteColorUseSolidBlend)
                        .highlightable(id: "appearance.websiteSolidBlend", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Dynamic Colors")
            } footer: {
                Text("Tint the window based on the active space or current website's theme color.")
            }

            // MARK: - Sidebar

            Section {
                Picker("Default collapsed mode", selection: $settings.defaultSidebarMode) {
                    ForEach(SidebarMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .highlightable(id: "appearance.sidebarMode", highlightedItemId: highlightedItemId)
            } header: {
                Text("Sidebar")
            } footer: {
                Text("Use View menu to temporarily switch modes for individual windows.")
            }

            // MARK: - Page Appearance

            Section {
                Picker("Dark mode", selection: $settings.webpageDarkMode) {
                    ForEach(DarkModePreference.allCases, id: \.self) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .highlightable(id: "appearance.webpageDarkMode", highlightedItemId: highlightedItemId)

                Picker("Color filter", selection: $settings.pageFilter) {
                    ForEach(PageFilter.allCases, id: \.self) { filter in
                        Label(filter.displayName, systemImage: filter.iconName).tag(filter)
                    }
                }
                .highlightable(id: "appearance.pageFilter", highlightedItemId: highlightedItemId)

                Picker("Background removal", selection: $settings.backgroundRemovalMode) {
                    ForEach(BackgroundRemovalMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .highlightable(id: "appearance.backgroundRemoval", highlightedItemId: highlightedItemId)

                if settings.webpageDarkMode != .off || settings.pageFilter != .none {
                    Toggle("Preserve images and videos", isOn: $settings.preserveMediaInFilter)
                        .highlightable(id: "appearance.preserveMedia", highlightedItemId: highlightedItemId)
                }
            } header: {
                Text("Page Appearance")
            } footer: {
                Text("Apply visual transformations to web pages for accessibility or preference.")
            }
        }
        .formStyle(.grouped)
    }

    /// Blend mode options excluding "solid" (which is only used internally for websites)
    private var blendModeOptions: [ColorMixMode] {
        ColorMixMode.allCases.filter { $0 != .solid }
    }
}

// MARK: - Settings Color Picker

/// A labeled color picker with preset swatches and custom color option.
private struct SettingsColorPicker: View {
    let label: String
    @Binding var selectedColor: Color.Components?
    let systemColor: Color

    @State private var hoveredLabel: String?

    private enum Layout {
        static let swatchSize: CGFloat = 20
        static let swatchRingSize: CGFloat = 27
        static let swatchSpacing: CGFloat = 3
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: Layout.swatchSpacing) {
                systemSwatch

                ForEach(GroupColor.allCases, id: \.self) { groupColor in
                    colorSwatch(for: groupColor)
                }

                CustomColorSwatch(
                    selectedColor: $selectedColor,
                    hoveredLabel: $hoveredLabel,
                )
            }
        }
    }

    // MARK: - System Swatch

    private var systemSwatch: some View {
        let isSelected = selectedColor == nil
        let swatchLabel = "System"

        return Button {
            selectedColor = nil
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 2)
                    .frame(width: Layout.swatchSize, height: Layout.swatchSize)
                    .background {
                        Image(systemName: "gear.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary, systemColor)
                    }

                if isSelected {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 2)
                        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
                }
            }
            .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
            .overlay(alignment: .bottom) {
                if hoveredLabel == swatchLabel {
                    hoverLabel(swatchLabel)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLabel = hovering ? swatchLabel : nil
        }
        .accessibilityLabel("System default")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Color Swatch

    private func colorSwatch(for groupColor: GroupColor) -> some View {
        let isSelected = selectedColor?.color.approximatelyEquals(groupColor.color) ?? false
        let swatchLabel = groupColor.rawValue

        return Button {
            selectedColor = groupColor.color.components
        } label: {
            ZStack {
                Circle()
                    .fill(groupColor.color)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 2)
                    .frame(width: Layout.swatchSize, height: Layout.swatchSize)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 2)
                        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
                }
            }
            .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
            .overlay(alignment: .bottom) {
                if hoveredLabel == swatchLabel {
                    hoverLabel(swatchLabel)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLabel = hovering ? swatchLabel : nil
        }
        .accessibilityLabel(swatchLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Hover Label

    private func hoverLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .offset(y: 12)
    }

}

// MARK: - Custom Color Swatch

private struct CustomColorSwatch: View {
    @Binding var selectedColor: Color.Components?
    @Binding var hoveredLabel: String?

    @State private var showPopover = false

    private var isCustom: Bool {
        guard let selectedColor else { return false }
        return !GroupColor.allCases.contains(where: { selectedColor.color.approximatelyEquals($0.color) })
    }

    private enum Layout {
        static let swatchSize: CGFloat = 20
        static let swatchRingSize: CGFloat = 27
    }

    private let label = "Custom"

    var body: some View {
        Button {
            showPopover = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center,
                        ),
                    )
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 2)
                    .frame(width: Layout.swatchSize, height: Layout.swatchSize)

                if isCustom {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 2)
                        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
                }
            }
            .contentShape(Circle())
            .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
        }
        .buttonStyle(.plain)
        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
        .overlay(alignment: .bottom) {
            if hoveredLabel == label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: 12)
            }
        }
        .popover(isPresented: $showPopover) {
            ColorWheelPopoverContent(
                selectedColor: Binding(
                    get: { selectedColor?.color ?? .blue },
                    set: { selectedColor = $0.components },
                ),
            )
        }
        .onHover { hovering in
            hoveredLabel = hovering ? label : nil
        }
        .accessibilityLabel(isCustom ? "Custom color selected" : "Choose custom color")
    }
}
