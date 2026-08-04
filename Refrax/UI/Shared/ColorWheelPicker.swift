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
            Group {
                if PrivateColorWheel.isAvailable {
                    ColorWheelView(color: $selectedColor, brightness: $brightness)
                } else {
                    FallbackColorWheelView(color: $selectedColor, brightness: $brightness)
                }
            }
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

// MARK: - Private API Probe

/// Runtime gate for the private `NSColorPickerWheelView` API surface.
///
/// Every selector and KVC key the wrapper touches is probed up front. If any
/// probe fails, ``ColorWheelPopoverContent`` shows ``FallbackColorWheelView``
/// instead. Calling an unprobed private selector raises
/// `NSInvalidArgumentException` inside `makeNSView`, which AppKit escalates to
/// a process kill via `+[NSApplication _crashOnException:]` — this killed the
/// app on macOS 27 beta (26A5388g), where `storeColorPanel:` no longer exists.
enum PrivateColorWheel {
    /// The private wheel class, or `nil` when any required API is missing.
    static let wheelViewClass: NSView.Type? = {
        guard let cls = NSClassFromString("NSColorPickerWheelView") as? NSView.Type else {
            return nil
        }
        guard cls.instancesRespond(to: Selector(("storeColorPanel:"))),
              cls.instancesRespond(to: #selector(getter: NSColorPanel.color)),
              canSetKVCKey("controllingPicker", on: cls),
              canSetKVCKey("color", on: cls),
              canSetKVCKey("brightness", on: cls)
        else {
            return nil
        }
        return cls
    }()

    static var isAvailable: Bool { wheelViewClass != nil }

    /// Whether `setValue(_:forKey:)` for `key` can succeed on `cls`.
    ///
    /// Mirrors KVC's lookup order: the `set<Key>:` and `_set<Key>:` accessors,
    /// then the ivars tried via `accessInstanceVariablesDirectly` —
    /// `_<key>`, `_is<Key>`, `<key>`, `is<Key>`. On macOS 26 the wheel resolves
    /// `controllingPicker` through the bare-named ivar, so the ivar walk is
    /// load-bearing, not just completeness.
    private static func canSetKVCKey(_ key: String, on cls: NSView.Type) -> Bool {
        let capitalized = key.prefix(1).uppercased() + key.dropFirst()
        if cls.instancesRespond(to: Selector("set\(capitalized):"))
            || cls.instancesRespond(to: Selector("_set\(capitalized):")) {
            return true
        }
        for ivarName in ["_\(key)", "_is\(capitalized)", key, "is\(capitalized)"]
            where class_getInstanceVariable(cls, ivarName) != nil {
            return true
        }
        return false
    }
}

// MARK: - Color Wheel View

/// An NSViewRepresentable wrapper around the system's private color wheel picker.
///
/// Uses `NSColorPickerWheelView` to provide a native color wheel experience.
/// The brightness is controlled separately via a slider in the parent view.
/// Only instantiated when ``PrivateColorWheel/isAvailable`` — every private
/// selector and KVC key used here is covered by that probe.
struct ColorWheelView: NSViewRepresentable {
    @Binding var color: Color
    @Binding var brightness: Double

    func makeNSView(context: Context) -> NSView {
        guard let wheelViewClass = PrivateColorWheel.wheelViewClass else {
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

// MARK: - Fallback Color Wheel

/// A SwiftUI HSB color wheel shown when ``PrivateColorWheel`` is unavailable.
///
/// Hue maps to angle and saturation to radius, matching the system wheel's
/// layout. The wheel dims with the brightness slider, and brightness is
/// factored into the produced color.
struct FallbackColorWheelView: View {
    @Binding var color: Color
    @Binding var brightness: Double

    /// Twelve hue stops closing back on red, drawn by the angular gradient.
    private static let hueRing: [Color] = (0 ... 12).map {
        Color(hue: Double($0) / 12, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter / 2
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                Circle()
                    .fill(AngularGradient(colors: Self.hueRing, center: .center))
                Circle()
                    .fill(RadialGradient(
                        colors: [.white, .white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius,
                    ))
                Circle()
                    .fill(.black.opacity(1 - brightness))
                indicator(center: center, radius: radius)
            }
            .frame(width: diameter, height: diameter)
            .position(center)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { pick(at: $0.location, center: center, radius: radius) },
            )
        }
        .onChange(of: brightness) { _, newBrightness in
            let hsb = hsbComponents()
            color = Color(hue: hsb.hue, saturation: hsb.saturation, brightness: newBrightness)
        }
    }

    /// A ring marking the currently selected hue/saturation position.
    private func indicator(center: CGPoint, radius: CGFloat) -> some View {
        let hsb = hsbComponents()
        let angle = hsb.hue * 2 * .pi
        let distance = hsb.saturation * radius
        let position = CGPoint(
            x: center.x + cos(angle) * distance,
            y: center.y + sin(angle) * distance,
        )
        return Circle()
            .stroke(.white, lineWidth: 2)
            .frame(width: 12, height: 12)
            .shadow(radius: 1)
            .position(position)
            .allowsHitTesting(false)
    }

    /// Updates the bound color from a touch location on the wheel.
    private func pick(at location: CGPoint, center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        let dx = location.x - center.x
        let dy = location.y - center.y
        let saturation = min(hypot(dx, dy) / radius, 1)
        // SwiftUI's angular gradient starts at 3 o'clock and sweeps clockwise
        // in view coordinates (y down), which is exactly atan2(dy, dx).
        var hue = atan2(dy, dx) / (2 * .pi)
        if hue < 0 { hue += 1 }
        color = Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    /// The bound color's HSB components in sRGB.
    private func hsbComponents() -> (hue: Double, saturation: Double, brightness: Double) {
        guard let rgbColor = NSColor(color).usingColorSpace(.sRGB) else {
            return (0, 0, brightness)
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var colorBrightness: CGFloat = 0
        rgbColor.getHue(&hue, saturation: &saturation, brightness: &colorBrightness, alpha: nil)
        return (hue, saturation, colorBrightness)
    }
}
