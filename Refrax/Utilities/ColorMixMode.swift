import CoreImage.CIFilterBuiltins

/// Modes for compositing a view with overlapping content.
enum ColorMixMode: String, CaseIterable, RawRepresentable {
    /// Solid color overlay without blending.
    ///
    /// This mode renders the color as a fully opaque layer that completely
    /// covers the vibrancy material. Best for website-provided colors where
    /// the site already chose an appropriate color.
    case solid

    case overlay
    case softLight
    case multiply
    case screen
    case linear
    case addition
    case color
    case colorBurn
    case colorDodge
    case darken
    case difference
    case divide
    case exclusion
    case hardLight
    case hue
    case lighten
    case linearBurn
    case linearDodge
    case luminosity
    case maximum
    case minimum
    case multiplyCompositing
    case pinLight
    case saturation
    case sourceAtop
    case sourceIn
    case sourceOut
    case sourceOver
    case subtract
    
    // swiftlint:disable:next cyclomatic_complexity
    func makeCIFilter() -> CIFilter? {
        switch self {
        case .solid:
            nil
        case .overlay:
            CIFilter.overlayBlendMode()
        case .softLight:
            CIFilter.softLightBlendMode()
        case .multiply:
            CIFilter.multiplyBlendMode()
        case .screen:
            CIFilter.screenBlendMode()
        case .linear:
            CIFilter.linearLightBlendMode()
        case .addition:
            CIFilter.additionCompositing()
        case .color:
            CIFilter.colorBlendMode()
        case .colorBurn:
            CIFilter.colorBurnBlendMode()
        case .colorDodge:
            CIFilter.colorDodgeBlendMode()
        case .darken:
            CIFilter.darkenBlendMode()
        case .difference:
            CIFilter.differenceBlendMode()
        case .divide:
            CIFilter.divideBlendMode()
        case .exclusion:
            CIFilter.exclusionBlendMode()
        case .hardLight:
            CIFilter.hardLightBlendMode()
        case .hue:
            CIFilter.hueBlendMode()
        case .lighten:
            CIFilter.lightenBlendMode()
        case .linearBurn:
            CIFilter.linearBurnBlendMode()
        case .linearDodge:
            CIFilter.linearDodgeBlendMode()
        case .luminosity:
            CIFilter.luminosityBlendMode()
        case .maximum:
            CIFilter.maximumCompositing()
        case .minimum:
            CIFilter.minimumCompositing()
        case .multiplyCompositing:
            CIFilter.multiplyCompositing()
        case .pinLight:
            CIFilter.pinLightBlendMode()
        case .saturation:
            CIFilter.saturationBlendMode()
        case .sourceAtop:
            CIFilter.sourceAtopCompositing()
        case .sourceIn:
            CIFilter.sourceInCompositing()
        case .sourceOut:
            CIFilter.sourceOutCompositing()
        case .sourceOver:
            CIFilter.sourceOverCompositing()
        case .subtract:
            CIFilter.subtractBlendMode()
        }
    }
    
    var displayName: String {
        switch self {
        case .solid: "Solid"
        case .overlay: "Overlay"
        case .softLight: "Soft Light"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .linear: "Linear Light"
        case .addition: "Addition"
        case .color: "Color"
        case .colorBurn: "Color Burn"
        case .colorDodge: "Color Dodge"
        case .darken: "Darken"
        case .difference: "Difference"
        case .divide: "Divide"
        case .exclusion: "Exclusion"
        case .hardLight: "Hard Light"
        case .hue: "Hue"
        case .lighten: "Lighten"
        case .linearBurn: "Linear Burn"
        case .linearDodge: "Linear Dodge"
        case .luminosity: "Luminosity"
        case .maximum: "Maximum"
        case .minimum: "Minimum"
        case .multiplyCompositing: "Multiply (Compositing)"
        case .pinLight: "Pin Light"
        case .saturation: "Saturation"
        case .sourceAtop: "Source Atop"
        case .sourceIn: "Source In"
        case .sourceOut: "Source Out"
        case .sourceOver: "Source Over"
        case .subtract: "Subtract"
        }
    }
    
    var description: String {
        switch self {
        case .solid: "Fully opaque color covering the background"
        case .overlay: "Enhances contrast while keeping detail"
        case .softLight: "Subtle modulation of tone"
        case .multiply: "Darkens by combining densities"
        case .screen: "Lightens by combining inverse values"
        case .linear: "Boosts highlights and shadows"
        case .addition: "Adds pixel values from both inputs"
        case .color: "Applies hue and saturation from the source"
        case .colorBurn: "Intensifies shadows using the source"
        case .colorDodge: "Brightens highlights using the source"
        case .darken: "Keeps the darker pixel at each point"
        case .difference: "Shows contrast by subtracting values"
        case .divide: "Divides background by source values"
        case .exclusion: "Soft contrast inversion"
        case .hardLight: "Combines multiply and screen depending on brightness"
        case .hue: "Applies source hue to the background"
        case .lighten: "Keeps the lighter pixel at each point"
        case .linearBurn: "Darkens by subtracting brightness"
        case .linearDodge: "Lightens by adding brightness"
        case .luminosity: "Applies source lightness to the background"
        case .maximum: "Chooses the maximum value per pixel"
        case .minimum: "Chooses the minimum value per pixel"
        case .multiplyCompositing: "Multiplies source over background with compositing rules"
        case .pinLight: "Switches between darken and lighten based on source"
        case .saturation: "Applies source saturation to the background"
        case .sourceAtop: "Draws source over background where background is opaque"
        case .sourceIn: "Keeps source only where background exists"
        case .sourceOut: "Keeps source only where background is absent"
        case .sourceOver: "Places source over background using standard alpha rules"
        case .subtract: "Subtracts source from background"
        }
    }
}
