import AppKit

/// Custom window background view: a behind-window blur with user-controllable
/// fill, tone and tint on top.
///
/// ## Layer Stack (bottom to top)
///
/// 1. **Backdrop**: a `CABackdropLayer` with gaussian blur and color saturation,
///    hosted in a cleared behind-window `NSVisualEffectView`. The effect view draws
///    nothing itself; it registers with the window so the frame opens a hole for the
///    layer to sample the content behind the window through.
/// 2. **Fill**: Semi-opaque white overlay. Controls how much of the desktop
///    shows through (84% = macOS default, 0% = full Aero transparency).
/// 3. **Tone**: Darkening blend that adds depth to the glass material.
/// 4. **Chameleon** (`CAChameleonLayer`): Adaptive tint at 5% opacity that
///    subtly matches content behind the window, adding life to the glass.
/// 5. **Tint**: User-controlled color overlay with configurable blend mode.
///
/// ## Why an NSVisualEffectView samples, and why the window keeps its background color
///
/// The window's background color stays opaque and the effect view registers itself
/// with the window, which is what lets the frame cut a hole under it. A window whose
/// background color is clear has no shape WindowServer can know in advance, so its
/// shadow is recomputed from the pixels, and WindowServer re-renders the window's
/// entire layer tree on every display frame, for any window's change, whether the
/// window is key or not. On a 5K display that costs every other app roughly as much
/// GPU as the rest of the compositing. `followsWindowActiveState` also freezes the
/// sample while the window is inactive, the way system windows lose vibrancy.
///
/// The effect view's own material is cleared because its fill is fixed at 84% with no
/// API to control it, and adding a compositing filter inside it breaks its material
/// pipeline; the backdrop layer's filters and the fill, tone, chameleon and tint layers
/// above are ours.
final class WindowBackgroundView: NSView {
    private let backdropView = NSVisualEffectView()
    private let backdropLayer = CABackdropLayer()
    private let overlayView = NSView()
    private let fillLayer = CALayer()
    private let toneLayer = CALayer()
    private let chameleonLayer = CAChameleonLayer()
    private let tintLayer = CALayer()

    private enum Constants {
        static let fillWhite: CGFloat = 0.965
        static let defaultFillOpacity: CGFloat = 0.84
        static let toneWhite: CGFloat = 0.914
        static let chameleonOpacity: Float = 0.05
        static let blurRadius: CGFloat = 30
        static let saturation: CGFloat = 1.7
    }

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

        // 1. Backdrop — samples behind-window content
        backdropView.frame = bounds
        backdropView.autoresizingMask = [.width, .height]
        backdropView.blendingMode = .behindWindow
        backdropView.material = .sidebar
        backdropView.state = .followsWindowActiveState
        backdropView._setClear(true)
        backdropView.wantsLayer = true
        addSubview(backdropView)

        backdropLayer.frame = bounds
        backdropLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdropLayer.windowServerAware = true
        let blur = CAFilter(name: "gaussianBlur")
        blur?.setValue(Constants.blurRadius, forKey: "inputRadius")
        blur?.setValue(true, forKey: "inputNormalizeEdges")
        let saturate = CAFilter(name: "colorSaturate")
        saturate?.setValue(Constants.saturation, forKey: "inputAmount")
        backdropLayer.filters = [CAFilter(name: "sdrNormalize"), blur, saturate].compactMap(\.self)
        backdropView.layer?.addSublayer(backdropLayer)

        overlayView.frame = bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.wantsLayer = true
        addSubview(overlayView)

        guard let rootLayer = overlayView.layer else { return }
        let autoresize: CAAutoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // 2. Fill — semi-opaque overlay (controls glass transparency)
        fillLayer.frame = bounds
        fillLayer.autoresizingMask = autoresize
        fillLayer.backgroundColor = NSColor(white: Constants.fillWhite, alpha: Constants.defaultFillOpacity).cgColor
        rootLayer.addSublayer(fillLayer)

        // 3. Tone — darkening blend for depth
        toneLayer.frame = bounds
        toneLayer.autoresizingMask = autoresize
        toneLayer.backgroundColor = NSColor(white: Constants.toneWhite, alpha: 1.0).cgColor
        toneLayer.compositingFilter = CAFilter(name: "darkenBlendMode")
        rootLayer.addSublayer(toneLayer)

        // 4. Chameleon — adaptive content-matching tint
        chameleonLayer.frame = bounds
        chameleonLayer.autoresizingMask = autoresize
        chameleonLayer.opacity = Constants.chameleonOpacity
        rootLayer.addSublayer(chameleonLayer)

        // 5. Tint — user color + blend mode
        tintLayer.frame = bounds
        tintLayer.autoresizingMask = autoresize
        rootLayer.addSublayer(tintLayer)
    }

    // MARK: - Update Methods

    /// Updates the fill layer opacity from a normalized 0–1 value.
    ///
    /// - `0.84`: macOS default (nearly opaque)
    /// - `0`: full Aero mode (desktop visible through glass)
    func updateFillOpacity(_ opacity: CGFloat) {
        fillLayer.backgroundColor = NSColor(white: Constants.fillWhite, alpha: opacity).cgColor
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
}
