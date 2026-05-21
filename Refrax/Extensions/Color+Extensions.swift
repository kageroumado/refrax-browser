import AppKit
import SwiftUI

extension Color {
    /// The color space a ``Components`` value is expressed in.
    nonisolated enum ColorSpace: String, Codable, Sendable, Hashable {
        case sRGB = "srgb"
        case displayP3 = "p3"
    }

    /// A portable, codable representation of a color's Red, Green, Blue, and Alpha components.
    ///
    /// This struct serves as a bridge between SwiftUI's `Color` and raw data, allowing for:
    /// - **Persistence**: Safely supports `Codable` and `@AppStorage` via tagged color strings (`p3:R,G,B[,A]`).
    /// - **Manipulation**: Provides direct access to RGBA values.
    /// - **Platform Interop**: Converts easily between `Color`, `CGColor`, and `NSColor`.
    ///
    /// ## Usage Example
    /// ```swift
    /// // Tagged format (lossless)
    /// let data = Color.Components(red: 1, green: 0, blue: 0, colorSpace: .displayP3)
    /// print(data.taggedString) // "p3:1.0000,0.0000,0.0000"
    ///
    /// // Hex format (sRGB-lossy, for CSS/clipboard)
    /// print(data.hexString) // "#FF0000"
    ///
    /// // Decoding supports both tagged and legacy hex
    /// let blue = Color.Components(encoded: "#0000FF")
    /// let p3 = Color.Components(encoded: "p3:0.2706,0.0196,0.8745")
    /// ```
    nonisolated struct Components: Codable, RawRepresentable, Hashable, Equatable {
        // MARK: - Properties
        
        /// The red component of the color (0.0 to 1.0).
        let red: Double
        
        /// The green component of the color (0.0 to 1.0).
        let green: Double
        
        /// The blue component of the color (0.0 to 1.0).
        let blue: Double
        
        /// The alpha (opacity) component of the color (0.0 to 1.0).
        let alpha: Double

        /// The color space these component values are expressed in.
        let colorSpace: ColorSpace

        // MARK: - Initializers
        
        /// Creates a new component instance with specific RGBA values.
        /// - Parameters:
        ///   - red: The red value (0.0 - 1.0).
        ///   - green: The green value (0.0 - 1.0).
        ///   - blue: The blue value (0.0 - 1.0).
        ///   - alpha: The opacity value (0.0 - 1.0).
        ///   - colorSpace: The color space these values are expressed in.
        init(red: Double, green: Double, blue: Double, alpha: Double = 1, colorSpace: ColorSpace = .sRGB) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
            self.colorSpace = colorSpace
        }
        
        /// Initializes components by converting a SwiftUI `Color` through `NSColor`.
        ///
        /// Going through `NSColor` preserves the original color space (e.g. Display P3),
        /// whereas `Color.resolve(in:)` always returns extended linear sRGB, losing P3 info.
        ///
        /// - Parameter color: The SwiftUI Color to extract components from.
        init(color: Color) {
            // Go through NSColor to detect and preserve the color space.
            // Color.resolve(in:) always returns extended linear sRGB, losing P3 info.
            self.init(nsColor: NSColor(color))
        }
        
        /// Initializes components from an `NSColor`, preserving Display P3 when the source is wide-gamut.
        ///
        /// The color space is detected from the source `NSColor`. Wide-gamut spaces (Display P3, Adobe RGB)
        /// are tagged as `.displayP3`; everything else is tagged as `.sRGB`.
        /// - Parameter nsColor: The AppKit color instance.
        init(nsColor: NSColor) {
            // Detect wide-gamut from component-based colors. Catalog/dynamic colors
            // (e.g. .systemBlue, .controlAccentColor) crash on .colorSpace access,
            // so for those we try P3 first since it's a superset of sRGB and
            // preserves gamut for our P3 asset catalog colors.
            let preferP3: Bool
            if nsColor.type == .componentBased {
                let sourceSpace = nsColor.colorSpace
                preferP3 = sourceSpace == .displayP3
                    || sourceSpace == .adobeRGB1998
                    || (sourceSpace.colorSpaceModel == .rgb && sourceSpace != .sRGB && sourceSpace != .genericRGB)
            } else {
                // Catalog colors: try P3 first to preserve wide gamut from asset catalog
                preferP3 = true
            }

            if preferP3, let p3 = nsColor.usingColorSpace(.displayP3) {
                self.red = p3.redComponent
                self.green = p3.greenComponent
                self.blue = p3.blueComponent
                self.alpha = p3.alphaComponent
                self.colorSpace = .displayP3
            } else if let srgb = nsColor.usingColorSpace(.sRGB) {
                self.red = srgb.redComponent
                self.green = srgb.greenComponent
                self.blue = srgb.blueComponent
                self.alpha = srgb.alphaComponent
                self.colorSpace = .sRGB
            } else {
                // Last resort: extract whatever components are available
                self.red = nsColor.redComponent
                self.green = nsColor.greenComponent
                self.blue = nsColor.blueComponent
                self.alpha = nsColor.alphaComponent
                self.colorSpace = .sRGB
            }
        }
        
        /// Initializes components from a Hexadecimal string.
        ///
        /// Supports the following formats (with or without `#` prefix):
        /// - **RGB (12-bit):** `#F00` (Expands to `#FF0000`)
        /// - **RGBA (16-bit):** `#F008` (Expands to `#FF000088`)
        /// - **RGB (24-bit):** `#FF0000`
        /// - **RGBA (32-bit):** `#FF000080`
        ///
        /// - Parameter hex: The hex string to parse.
        init?(hex: String) {
            var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if hexString.hasPrefix("#") {
                hexString = String(hexString.dropFirst())
            }
            
            guard let hexNumber = UInt64(hexString, radix: 16) else {
                return nil
            }
            
            switch hexString.count {
            case 3: // RGB (12-bit)
                self.red = Double((hexNumber >> 8) & 0xF) / 15.0
                self.green = Double((hexNumber >> 4) & 0xF) / 15.0
                self.blue = Double(hexNumber & 0xF) / 15.0
                self.alpha = 1.0
                self.colorSpace = .sRGB

            case 4: // RGBA (16-bit)
                self.red = Double((hexNumber >> 12) & 0xF) / 15.0
                self.green = Double((hexNumber >> 8) & 0xF) / 15.0
                self.blue = Double((hexNumber >> 4) & 0xF) / 15.0
                self.alpha = Double(hexNumber & 0xF) / 15.0
                self.colorSpace = .sRGB

            case 6: // RGB (24-bit)
                self.red = Double((hexNumber >> 16) & 0xFF) / 255.0
                self.green = Double((hexNumber >> 8) & 0xFF) / 255.0
                self.blue = Double(hexNumber & 0xFF) / 255.0
                self.alpha = 1.0
                self.colorSpace = .sRGB

            case 8: // RGBA (32-bit)
                self.red = Double((hexNumber >> 24) & 0xFF) / 255.0
                self.green = Double((hexNumber >> 16) & 0xFF) / 255.0
                self.blue = Double((hexNumber >> 8) & 0xFF) / 255.0
                self.alpha = Double(hexNumber & 0xFF) / 255.0
                self.colorSpace = .sRGB

            default:
                return nil
            }
        }

        /// Parses a tagged color string (`p3:R,G,B[,A]`) or legacy hex (`#RRGGBB`).
        init?(encoded: String) {
            let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)

            // Legacy hex format
            if trimmed.hasPrefix("#") {
                self.init(hex: trimmed)
                return
            }

            // Tagged format: colorspace:r,g,b[,a]
            guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }
            let csString = String(trimmed[trimmed.startIndex..<colonIndex])
            guard let colorSpace = ColorSpace(rawValue: csString) else { return nil }

            let valuesPart = String(trimmed[trimmed.index(after: colonIndex)...])
            let parts = valuesPart.split(separator: ",")
            guard parts.count == 3 || parts.count == 4,
                  let r = Double(parts[0]),
                  let g = Double(parts[1]),
                  let b = Double(parts[2]) else { return nil }

            let a = parts.count == 4 ? (Double(parts[3]) ?? 1.0) : 1.0
            self.init(red: r, green: g, blue: b, alpha: a, colorSpace: colorSpace)
        }

        // MARK: - Computed Outputs
        
        /// A Core Graphics representation of the color.
        var cgColor: CGColor {
            switch colorSpace {
            case .sRGB:
                return CGColor(
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)],
                )!
            case .displayP3:
                return CGColor(
                    colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                    components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)],
                )!
            }
        }
        
        /// A SwiftUI representation of the color.
        var color: Color {
            switch colorSpace {
            case .sRGB:
                return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
            case .displayP3:
                return Color(.displayP3, red: red, green: green, blue: blue, opacity: alpha)
            }
        }
        
        /// An AppKit representation of the color.
        var nsColor: NSColor {
            switch colorSpace {
            case .sRGB:
                return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
            case .displayP3:
                return NSColor(displayP3Red: red, green: green, blue: blue, alpha: alpha)
            }
        }
        
        // MARK: - Serialization
        
        /// The backing string for `RawRepresentable` and `Codable`.
        var rawValue: String {
            taggedString
        }
        
        /// Returns a Hexadecimal string representation of the color.
        ///
        /// - Note: This is inherently sRGB-lossy — Display P3 values are clamped to the sRGB gamut.
        ///   Intended for CSS output, debugging, and clipboard operations. For lossless persistence,
        ///   use ``taggedString`` instead.
        ///
        /// - Returns: A string formatted as `#RRGGBB` (if opaque) or `#RRGGBBAA` (if transparent).
        var hexString: String {
            // Clamping ensures invalid doubles (e.g. 1.1, -0.1, NaN) don't break the Hex logic.
            // NaN must be handled explicitly: IEEE 754 NaN comparisons always return false,
            // so min(max(NaN, 0), 1) still yields NaN, and Int(NaN) is a fatal error.
            let r = Int((min(max(red.isNaN ? 0 : red, 0), 1) * 255).rounded())
            let g = Int((min(max(green.isNaN ? 0 : green, 0), 1) * 255).rounded())
            let b = Int((min(max(blue.isNaN ? 0 : blue, 0), 1) * 255).rounded())
            let a = Int((min(max(alpha.isNaN ? 0 : alpha, 0), 1) * 255).rounded())
            
            if a == 255 {
                return String(format: "#%02X%02X%02X", r, g, b)
            } else {
                return String(format: "#%02X%02X%02X%02X", r, g, b, a)
            }
        }

        /// Encodes as a tagged color string: `<colorspace>:<r>,<g>,<b>[,<a>]`.
        ///
        /// Uses 4 decimal places. Alpha is omitted when 1.0.
        var taggedString: String {
            let cs = colorSpace.rawValue
            let r = String(format: "%.4f", red)
            let g = String(format: "%.4f", green)
            let b = String(format: "%.4f", blue)
            if (alpha - 1.0).magnitude < 0.0001 {
                return "\(cs):\(r),\(g),\(b)"
            }
            return "\(cs):\(r),\(g),\(b),\(String(format: "%.4f", alpha))"
        }

        // MARK: - Protocol Conformance
        
        /// Decodes the components from a single string container (tagged or legacy hex format).
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            guard let components = Color.Components(encoded: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid color string: \(string)",
                )
            }
            self = components
        }
        
        /// Initializes components from a raw string value.
        /// - Parameter rawValue: A tagged string (e.g., `p3:1.0000,0.0000,0.0000`) or legacy hex.
        init?(rawValue: String) {
            self.init(encoded: rawValue)
        }
        
        /// Encodes the components as a tagged color string.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(taggedString)
        }
    }
    
    // MARK: - Extensions
    
    /// Extracts the RGBA components from this color.
    ///
    /// - Returns: A `Color.Components` struct containing the resolved values.
    nonisolated var components: Color.Components {
        Color.Components(color: self)
    }
    
    /// Initializes a SwiftUI Color from a raw components struct.
    init(components: Color.Components) {
        self = components.color
    }
}

extension Color {
    /// The app's custom accent color, or the system accent color if none is set.
    ///
    /// Reads directly from `RefraxAppDelegate.settings`. Use this instead of `Color.appAccentColor`
    /// when you want to respect the user's custom accent color preference.
    static var appAccentColor: Color {
        NSApp.typedDelegate.settings.customAccentColor?.color ?? .accentColor
    }
}

// MARK: - Palette Color Resolution

extension Color {
    /// Known palette color names for O(1) lookup.
    private static let paletteColorNames: Set<String> = Set(GroupColor.allCases.map(\.rawValue))

    /// Resolves a stored color string to a SwiftUI Color.
    ///
    /// Tries ``GroupColor`` name lookup first (adaptive asset catalog color),
    /// then falls back to ``Components`` parsing for custom colors.
    static func resolveStoredColor(_ string: String) -> Color {
        if paletteColorNames.contains(string) {
            return Color(string)
        }
        return Components(encoded: string)?.color ?? .steel
    }

    /// Resolves a stored color string to ``Components``.
    ///
    /// For palette colors, resolves the adaptive color to P3 components at the current appearance.
    /// For custom colors, parses the tagged/hex string directly.
    @MainActor static func resolveStoredColorComponents(_ string: String) -> Components? {
        if paletteColorNames.contains(string) {
            return Components(color: Color(string))
        }
        return Components(encoded: string)
    }
}

extension Color {
    init?(cssColor: String) {
        let trimmed = cssColor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Handle hsl() and hsla()
        if trimmed.hasPrefix("hsl") {
            let pattern = #"hsla?\(([^)]+)\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
                  let range = Range(match.range(at: 1), in: trimmed) else { return nil }
            
            let components = trimmed[range]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            
            guard components.count >= 3 else { return nil }
            
            // Parse hue (0-360, no unit or deg)
            let hueStr = components[0].replacingOccurrences(of: "deg", with: "").trimmingCharacters(in: .whitespaces)
            guard let h = Double(hueStr) else { return nil }
            
            // Parse saturation (0-100%)
            let satStr = components[1].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            guard let s = Double(satStr) else { return nil }
            
            // Parse lightness (0-100%)
            let lightStr = components[2].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            guard let l = Double(lightStr) else { return nil }
            
            // Parse alpha if present
            let alpha = components.count == 4 ? (Double(components[3].trimmingCharacters(in: .whitespaces)) ?? 1.0) : 1.0
            
            // Convert HSL to RGB
            let hue = h / 360.0
            let saturation = s / 100.0
            let lightness = l / 100.0
            
            let rgb = Color.hslToRgb(h: hue, s: saturation, l: lightness)
            self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: alpha)
            return
        }
        
        // Handle rgb() and rgba()
        if trimmed.hasPrefix("rgb") {
            let pattern = #"rgba?\(([^)]+)\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
                  let range = Range(match.range(at: 1), in: trimmed) else { return nil }
            
            let components = trimmed[range]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            
            guard components.count >= 3,
                  let r = Double(components[0].replacingOccurrences(of: "%", with: "")),
                  let g = Double(components[1].replacingOccurrences(of: "%", with: "")),
                  let b = Double(components[2].replacingOccurrences(of: "%", with: "")) else { return nil }
            
            let alpha = (components.count == 4 ? Double(components[3]) ?? 1.0 : 1.0)
            let div: Double = components[0].contains("%") ? 100.0 : 255.0
            
            self.init(.sRGB, red: r / div, green: g / div, blue: b / div, opacity: alpha)
            return
        }
        
        // Handle color(display-p3 ...)
        if trimmed.hasPrefix("color(display-p3") {
            let pattern = #"color\(display-p3\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)(?:\s*/\s*([0-9.]+))?\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) else { return nil }
            
            func value(_ i: Int) -> Double {
                if let range = Range(match.range(at: i), in: trimmed),
                   let num = Double(trimmed[range]) { return num }
                return 1.0
            }
            
            let r = value(1), g = value(2), b = value(3), a = value(4)
            self.init(.displayP3, red: r, green: g, blue: b, opacity: a)
            return
        }
        
        return nil
    }
    
    /// Helper function to convert HSL to RGB
    private static func hslToRgb(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        if s == 0 {
            // Achromatic (gray)
            return (l, l, l)
        }
        
        func hueToRgb(p: Double, q: Double, t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        
        let r = hueToRgb(p: p, q: q, t: h + 1 / 3)
        let g = hueToRgb(p: p, q: q, t: h)
        let b = hueToRgb(p: p, q: q, t: h - 1 / 3)
        
        return (r, g, b)
    }
}
