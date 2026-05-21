import AppKit
import SwiftUI

/// A compact inline color picker with preset swatches and a custom color option.
///
/// Displays palette colors as circular swatches plus a rainbow gradient button
/// that opens a color wheel popover for custom color selection.
struct InlineColorPicker: View {
    @Binding var selectedColor: Color

    var body: some View {
        HStack(spacing: Layout.swatchSpacing) {
            ForEach(GroupColor.allCases, id: \.self) { groupColor in
                colorSwatch(for: groupColor)
            }

            CustomColorButton(selectedColor: $selectedColor)
        }
    }

    // MARK: - Color Swatch

    private func colorSwatch(for groupColor: GroupColor) -> some View {
        let isSelected = selectedColor.approximatelyEquals(groupColor.color)

        return Button {
            selectedColor = groupColor.color
        } label: {
            ZStack {
                Circle()
                    .fill(groupColor.color)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 2)
                    .frame(width: Layout.swatchSize, height: Layout.swatchSize)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.appAccentColor, lineWidth: 3)
                        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
                }
            }
            .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(groupColor.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Custom Color Button

/// A button that shows a rainbow gradient and opens a color wheel popover.
private struct CustomColorButton: View {
    @Binding var selectedColor: Color

    private var isCustom: Bool {
        !GroupColor.allCases.contains(where: { selectedColor.approximatelyEquals($0.color) })
    }

    var body: some View {
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
                    .strokeBorder(Color.appAccentColor, lineWidth: 3)
                    .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
            }

            // Invisible color well that shows popover on click
            ColorPopoverTrigger(selectedColor: $selectedColor)
                .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
        }
        .frame(width: Layout.swatchRingSize, height: Layout.swatchRingSize)
        .accessibilityLabel(isCustom ? "Custom color selected" : "Choose custom color")
    }
}

// MARK: - Color Wheel Popover

/// A button trigger that shows a color wheel popover when clicked.
private struct ColorPopoverTrigger: View {
    @Binding var selectedColor: Color
    @State private var showPopover = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                showPopover = true
            }
            .popover(isPresented: $showPopover) {
                ColorWheelPopoverContent(selectedColor: $selectedColor)
            }
    }
}

// MARK: - Layout Constants

private extension InlineColorPicker {
    enum Layout {
        static let swatchSize: CGFloat = 20
        static let swatchRingSize: CGFloat = 26
        static let swatchSpacing: CGFloat = 4
    }
}

private extension CustomColorButton {
    enum Layout {
        static let swatchSize: CGFloat = 20
        static let swatchRingSize: CGFloat = 26
    }
}

// MARK: - Color Comparison Extension

extension Color {
    /// Compares colors approximately since Color equality can fail due to color space differences.
    ///
    /// Resolves through NSColor which uses the current app appearance, unlike
    /// `resolve(in: EnvironmentValues())` which defaults to light mode and
    /// causes adaptive asset catalog colors to resolve to the wrong variant.
    @MainActor
    func approximatelyEquals(_ other: Color) -> Bool {
        guard let selfSRGB = NSColor(self).usingColorSpace(.sRGB),
              let otherSRGB = NSColor(other).usingColorSpace(.sRGB)
        else {
            return false
        }

        let tolerance: CGFloat = 0.02
        return abs(selfSRGB.redComponent - otherSRGB.redComponent) < tolerance
            && abs(selfSRGB.greenComponent - otherSRGB.greenComponent) < tolerance
            && abs(selfSRGB.blueComponent - otherSRGB.blueComponent) < tolerance
    }
}
