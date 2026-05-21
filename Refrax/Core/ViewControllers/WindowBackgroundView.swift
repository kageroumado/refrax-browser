import AppKit

/// Custom window background view that replicates NSVisualEffectView's internal
/// layer hierarchy with user-controllable parameters.
///
/// ## Layer Stack (bottom to top)
///
/// 1. **Backdrop** (`CABackdropLayer`): Samples content behind the window with
///    gaussian blur and color saturation — the "frosted glass" effect.
/// 2. **Fill**: Semi-opaque white overlay. Controls how much of the desktop
///    shows through (84% = macOS default, 0% = full Aero transparency).
/// 3. **Tone**: Darkening blend that adds depth to the glass material.
/// 4. **Chameleon** (`CAChameleonLayer`): Adaptive tint at 5% opacity that
///    subtly matches content behind the window, adding life to the glass.
/// 5. **Tint**: User-controlled color overlay with configurable blend mode.
///
/// ## Why Not NSVisualEffectView
///
/// VEV's internal fill layer is fixed at 84% opacity with no API to control it.
/// Adding a compositing filter as a sublayer breaks VEV's material pipeline
/// (CIMultiplyCompositing requires two inputs but gets one as a compositingFilter,
/// destroying the material stack). By building the layer hierarchy ourselves,
/// we get identical visual results with full customization.
final class WindowBackgroundView: NSView {
    private let backdropLayer = CABackdropLayer()
    private let fillLayer = CALayer()
    private let toneLayer = CALayer()
    private let chameleonLayer = CAChameleonLayer()
    private let tintLayer = CALayer()

    private var blurFilter: CAFilter?
    private var saturationFilter: CAFilter?
    private var sdrNormalizeFilter: CAFilter?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layer Setup

    private func setupLayers() {
        wantsLayer = true

        guard let rootLayer = layer else { return }

        let autoresize: CAAutoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // 1. Backdrop — samples behind-window content
        backdropLayer.frame = bounds
        backdropLayer.autoresizingMask = autoresize
        backdropLayer.windowServerAware = true

        let sdrNormalize = CAFilter(name: "sdrNormalize")
        let blur = CAFilter(name: "gaussianBlur")
        blur?.setValue(30.0, forKey: "inputRadius")
        blur?.setValue(true, forKey: "inputNormalizeEdges")
        let saturate = CAFilter(name: "colorSaturate")
        saturate?.setValue(1.7, forKey: "inputAmount")

        sdrNormalizeFilter = sdrNormalize
        blurFilter = blur
        saturationFilter = saturate
        backdropLayer.filters = [sdrNormalize, blur, saturate].compactMap(\.self)

        rootLayer.addSublayer(backdropLayer)

        // 2. Fill — semi-opaque overlay (controls glass transparency)
        fillLayer.frame = bounds
        fillLayer.autoresizingMask = autoresize
        fillLayer.backgroundColor = NSColor(white: 0.965, alpha: 0.84).cgColor

        rootLayer.addSublayer(fillLayer)

        // 3. Tone — darkening blend for depth
        toneLayer.frame = bounds
        toneLayer.autoresizingMask = autoresize
        toneLayer.backgroundColor = NSColor(white: 0.914, alpha: 1.0).cgColor
        toneLayer.compositingFilter = CAFilter(name: "darkenBlendMode")

        rootLayer.addSublayer(toneLayer)

        // 4. Chameleon — adaptive content-matching tint
        chameleonLayer.frame = bounds
        chameleonLayer.autoresizingMask = autoresize
        chameleonLayer.opacity = 0.05

        rootLayer.addSublayer(chameleonLayer)

        // 5. Tint — user color + blend mode
        tintLayer.frame = bounds
        tintLayer.autoresizingMask = autoresize

        rootLayer.addSublayer(tintLayer)
    }

    // MARK: - Update Methods

    /// Updates the fill layer's background color, controlling glass opacity.
    ///
    /// - Parameter color: The fill color. Adjust alpha to control transparency:
    ///   - `alpha = 0.84`: macOS default (nearly opaque)
    ///   - `alpha = 0.0`: Full Aero mode (desktop visible through glass)
    func updateFill(color: NSColor) {
        fillLayer.backgroundColor = color.cgColor
    }

    /// Updates the fill layer opacity from a normalized 0–1 value.
    ///
    /// Adjusts the alpha of the default fill color (white 0.965).
    func updateFillOpacity(_ opacity: CGFloat) {
        fillLayer.backgroundColor = NSColor(white: 0.965, alpha: opacity).cgColor
    }

    /// Updates the user tint layer.
    ///
    /// - Parameters:
    ///   - color: The tint color (alpha controls intensity).
    ///   - compositingFilter: The CIFilter for blending, or nil for solid overlay.
    func updateTint(color: CGColor?, compositingFilter: CIFilter?) {
        tintLayer.backgroundColor = color
        tintLayer.compositingFilter = compositingFilter
    }

    /// Updates the backdrop blur radius.
    func updateBlur(radius: CGFloat) {
        blurFilter?.setValue(radius, forKey: "inputRadius")
        rebuildBackdropFilters()
    }

    /// Updates the backdrop color saturation.
    func updateSaturation(_ amount: CGFloat) {
        saturationFilter?.setValue(amount, forKey: "inputAmount")
        rebuildBackdropFilters()
    }

    /// Reassigns the filters array to trigger Core Animation to re-read filter values.
    private func rebuildBackdropFilters() {
        backdropLayer.filters = [sdrNormalizeFilter, blurFilter, saturationFilter].compactMap(\.self)
    }
}
