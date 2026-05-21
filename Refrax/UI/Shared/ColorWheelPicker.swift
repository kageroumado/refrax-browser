import AppKit
import SwiftUI

/// A popover content view containing a color wheel with brightness slider.
///
/// Provides an interactive HSB color picker using the system's private
/// `NSColorPickerWheelView` for a native look and feel.
struct ColorWheelPopoverContent: View {
    @Binding var selectedColor: Color
    @State private var brightness: Double = 1.0

    var body: some View {
        VStack(spacing: 12) {
            ColorWheelView(color: $selectedColor, brightness: $brightness)
                .frame(width: 200, height: 200)

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: $brightness, in: 0 ... 1)
                    .controlSize(.small)
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .onAppear {
            brightness = Self.extractBrightness(from: selectedColor)
        }
    }

    private static func extractBrightness(from color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        let r = Double(resolved.red)
        let g = Double(resolved.green)
        let b = Double(resolved.blue)
        return max(r, g, b)
    }
}

// MARK: - Color Wheel View

/// An NSViewRepresentable wrapper around the system's private color wheel picker.
///
/// Uses `NSColorPickerWheelView` to provide a native color wheel experience.
/// The brightness is controlled separately via a slider in the parent view.
struct ColorWheelView: NSViewRepresentable {
    @Binding var color: Color
    @Binding var brightness: Double

    func makeNSView(context: Context) -> NSView {
        guard let wheelViewClass = NSClassFromString("NSColorPickerWheelView") as? NSView.Type else {
            return NSView()
        }

        let wheelView = wheelViewClass.init(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        let colorPanel = NSColorPanel.shared
        let nsColor = colorToNSColor(color)
        colorPanel.color = nsColor
        _ = wheelView.perform(Selector(("storeColorPanel:")), with: colorPanel)

        let proxy = ColorPickerProxy()
        let coordinator = context.coordinator
        proxy.onColorChange = { newColor in
            coordinator.handleColorChange(newColor)
        }
        wheelView.setValue(proxy, forKey: "controllingPicker")
        coordinator.proxy = proxy

        wheelView.setValue(nsColor, forKey: "color")
        wheelView.setValue(brightness, forKey: "brightness")

        return wheelView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setValue(brightness, forKey: "brightness")
        nsView.needsDisplay = true

        if let adjustedColor = nsView.value(forKey: "color") as? NSColor {
            DispatchQueue.main.async {
                context.coordinator.handleColorChange(adjustedColor)
            }
        }
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color, brightness: $brightness)
    }

    private func colorToNSColor(_ color: Color) -> NSColor {
        let resolved = color.resolve(in: EnvironmentValues())
        return NSColor(
            srgbRed: CGFloat(resolved.red),
            green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue),
            alpha: CGFloat(resolved.opacity),
        )
    }

    final class Coordinator: NSObject {
        var color: Binding<Color>
        var brightness: Binding<Double>
        var proxy: ColorPickerProxy?

        init(color: Binding<Color>, brightness: Binding<Double>) {
            self.color = color
            self.brightness = brightness
        }

        func handleColorChange(_ newColor: NSColor) {
            guard let rgbColor = newColor.usingColorSpace(.sRGB) else { return }
            let r = rgbColor.redComponent
            let g = rgbColor.greenComponent
            let b = rgbColor.blueComponent
            guard !r.isNaN, !g.isNaN, !b.isNaN else { return }
            color.wrappedValue = Color(nsColor: rgbColor)
        }

        func cleanup() {
            proxy?.onColorChange = nil
            proxy = nil
        }
    }
}

// MARK: - Color Picker Proxy

/// A proxy object that receives color change callbacks from the private color wheel.
final class ColorPickerProxy: NSObject {
    var onColorChange: ((NSColor) -> Void)?

    @objc
    func setColor(_ color: NSColor) {
        onColorChange?(color)
    }
}
