import SwiftUI

/// A compact popover for quickly adjusting window background appearance.
///
/// Provides controls for color selection, blend mode, blend strength, and fill opacity
/// in a clean layout suitable for sidebar context menu access.
struct WindowBackgroundPopover: View {
    @Environment(BrowserSettings.self) private var settings

    @State private var showColorWheel = false

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            header
            Divider()
            colorSection
            Divider()
            blendModeSection
            Divider()
            slidersSection
        }
        .padding(Layout.padding)
        .frame(width: Layout.popoverWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "paintbrush.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Window Background")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                settings.customWindowBackgroundColor = Color.Components(encoded: BrowserSettings.Defaults.windowBackgroundColorHex)
                settings.windowBackgroundMixAmount = BrowserSettings.Defaults.windowBackgroundMixAmount
                settings.windowBackgroundMixMode = BrowserSettings.Defaults.windowBackgroundMixMode
                settings.windowBackgroundFillOpacity = BrowserSettings.Defaults.windowBackgroundFillOpacity
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset to Defaults")
        }
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(horizontalSpacing: Layout.colorSpacing, verticalSpacing: Layout.colorSpacing) {
                GridRow {
                    ForEach(Layout.presetColors.prefix(6), id: \.name) { preset in
                        colorSwatch(for: preset.components, name: preset.name)
                    }
                }
                GridRow {
                    ForEach(Layout.presetColors.dropFirst(6), id: \.name) { preset in
                        colorSwatch(for: preset.components, name: preset.name)
                    }
                    customColorSwatch
                }
            }
        }
    }

    private func colorSwatch(for components: Color.Components, name: String) -> some View {
        let isSelected = settings.customWindowBackgroundColor?.hexString == components.hexString

        return Button {
            settings.customWindowBackgroundColor = components
        } label: {
            ZStack {
                Circle()
                    .fill(components.color)
                    .frame(width: Layout.swatchSize, height: Layout.swatchSize)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 1))

                if isSelected {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 2.5)
                        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
                }
            }
            .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private var customColorSwatch: some View {
        let customColor = settings.customWindowBackgroundColor
        let isCustom: Bool = {
            guard let selected = customColor else { return false }
            return !Layout.presetColors.contains { $0.components.hexString == selected.hexString }
        }()

        return Button {
            showColorWheel = true
        } label: {
            ZStack {
                if isCustom, let customColor {
                    Circle()
                        .fill(customColor.color)
                        .frame(width: Layout.swatchSize, height: Layout.swatchSize)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 1))
                } else {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center,
                            ),
                        )
                        .frame(width: Layout.swatchSize, height: Layout.swatchSize)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 1))
                }

                if isCustom {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 2.5)
                        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
                }
            }
            .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
        }
        .buttonStyle(.plain)
        .help("Custom Color")
        .if(showColorWheel) { view in
            view.popover(isPresented: $showColorWheel) {
                ColorWheelPopoverContent(
                    selectedColor: Binding(
                        get: { settings.customWindowBackgroundColor?.color ?? Color.Components(encoded: BrowserSettings.Defaults.windowBackgroundColorHex)!.color },
                        set: { settings.customWindowBackgroundColor = $0.components },
                    ),
                )
            }
        }
    }

    // MARK: - Blend Mode Section

    private var blendModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blend Mode")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 5) {
                ForEach(Layout.demoBlendModes, id: \.self) { mode in
                    blendModeChip(mode)
                }
                moreBlendModesButton
            }
        }
    }

    private func blendModeChip(_ mode: ColorMixMode) -> some View {
        let isSelected = settings.windowBackgroundMixMode == mode

        return Button {
            settings.windowBackgroundMixMode = mode
        } label: {
            Text(mode.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .frame(height: Layout.chipHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.appAccentColor.opacity(0.15) : Color.primary.opacity(0.05)),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSelected ? Color.appAccentColor.opacity(0.4) : Color.clear,
                            lineWidth: 1.5,
                        ),
                )
                .foregroundStyle(isSelected ? Color.appAccentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    /// A "+" chip that opens an NSMenu of additional blend modes.
    /// When an extra mode is active, it shows the mode name instead.
    private var moreBlendModesButton: some View {
        let currentIsExtra = !Layout.demoBlendModes.contains(settings.windowBackgroundMixMode)
            && settings.windowBackgroundMixMode != .solid

        return Group {
            if currentIsExtra {
                Text(settings.windowBackgroundMixMode.displayName)
            } else {
                Image(systemName: "plus")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: Layout.chipHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    currentIsExtra
                        ? Color.appAccentColor.opacity(0.15)
                        : Color.primary.opacity(0.05),
                ),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    currentIsExtra
                        ? Color.appAccentColor.opacity(0.4)
                        : Color.clear,
                    lineWidth: 1.5,
                ),
        )
        .foregroundStyle(currentIsExtra ? Color.appAccentColor : .secondary)
        .overlay {
            BlendModeMenuButton(
                modes: Layout.extraBlendModes,
                currentMode: settings.windowBackgroundMixMode,
            ) { mode in
                settings.windowBackgroundMixMode = mode
            }
        }
    }

    // MARK: - Sliders Section

    private var slidersSection: some View {
        @Bindable var settings = settings

        return VStack(spacing: 10) {
            sliderRow(
                label: "Strength",
                value: $settings.windowBackgroundMixAmount,
            )

            sliderRow(
                label: "Opacity",
                value: $settings.windowBackgroundFillOpacity,
            )
        }
    }

    private func sliderRow(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Slider(value: value, in: 0 ... 1, step: 0.1)
                .controlSize(.small)
        }
    }
}

// MARK: - Layout Constants

private extension WindowBackgroundPopover {
    enum Layout {
        static let padding: CGFloat = 14
        static let sectionSpacing: CGFloat = 10
        static let swatchSize: CGFloat = 22
        static let swatchRingSize: CGFloat = 30
        static let colorSpacing: CGFloat = 6

        // 6 columns × 30 swatch ring + 5 × 6 spacing = 210
        // + 2 × 14 padding = 238
        static let popoverWidth: CGFloat = 238
        static let chipHeight: CGFloat = 22

        @MainActor static var presetColors: [(name: String, components: Color.Components)] {
            GroupColor.allCases.map { ($0.rawValue, Color.Components(color: $0.color)) }
        }

        /// Ordered so FlowLayout produces balanced row widths:
        /// Row 1: Soft Light + Screen + Multiply ≈ 200px
        /// Row 2: Hard Light + Color Burn + Hue ≈ 197px
        static let demoBlendModes: [ColorMixMode] = [
            .softLight, .screen, .multiply, .hardLight, .colorBurn, .hue,
        ]

        static let extraBlendModes: [ColorMixMode] = ColorMixMode.allCases.filter {
            $0 != .solid && !demoBlendModes.contains($0)
        }
    }
}

// MARK: - Blend Mode Menu Button

/// Transparent NSView overlay that shows an NSMenu of blend modes on click.
///
/// Follows the `DetailTrayTitleMenuOverlay` pattern: a zero-opacity NSView
/// that intercepts `mouseDown` and pops up an NSMenu positioned below the chip.
private struct BlendModeMenuButton: NSViewRepresentable {
    let modes: [ColorMixMode]
    let currentMode: ColorMixMode
    let onSelect: (ColorMixMode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> BlendModeMenuOverlayView {
        let view = BlendModeMenuOverlayView()
        view.modes = modes
        view.currentMode = currentMode
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: BlendModeMenuOverlayView, context: Context) {
        nsView.modes = modes
        nsView.currentMode = currentMode
        nsView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        let onSelect: (ColorMixMode) -> Void

        init(onSelect: @escaping (ColorMixMode) -> Void) {
            self.onSelect = onSelect
        }

        @objc
        func menuItemSelected(_ sender: NSMenuItem) {
            guard let box = sender.representedObject as? ColorMixModeBox else { return }
            DispatchQueue.main.async { [self] in
                onSelect(box.value)
            }
        }
    }
}

/// Box wrapper for `ColorMixMode` to use as `representedObject`.
private final class ColorMixModeBox: NSObject {
    let value: ColorMixMode
    init(_ value: ColorMixMode) {
        self.value = value
    }
}

/// Transparent NSView that shows a popup menu on click.
private final class BlendModeMenuOverlayView: NSView {
    var modes: [ColorMixMode] = []
    var currentMode: ColorMixMode = .softLight
    weak var coordinator: BlendModeMenuButton.Coordinator?

    override func mouseDown(with _: NSEvent) {
        guard let coordinator else { return }

        let menu = NSMenu()

        for mode in modes {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(BlendModeMenuButton.Coordinator.menuItemSelected(_:)),
                keyEquivalent: "",
            )
            item.target = coordinator
            item.representedObject = ColorMixModeBox(mode)

            if mode == currentMode {
                item.state = .on
            }

            menu.addItem(item)
        }

        let point = NSPoint(x: 0, y: -4)
        menu.popUp(positioning: nil, at: point, in: self)
    }
}
