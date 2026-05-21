import AppKit
import QuartzCore

/// An AppKit view that renders a gradient background for the compact sidebar edge extension.
///
/// ## Overview
///
/// `EdgeExtensionBackgroundView` displays sampled colors from the webview's left edge using
/// a progressive blending approach. Multiple layers are stacked with different sampling depths:
///
/// 1. **Base Layer**: Full-width sample, heavily blurred (abstract background)
/// 2. **Mid Layer**: ~20px sample, moderately visible
/// 3. **Near Layer**: ~8px sample, more visible toward the edge
/// 4. **Edge Strip Layer**: 2px sample, fully visible at the right edge
///
/// Each layer is masked so that narrower samples dominate at the right edge (adjacent to the
/// webview), while wider samples gradually show through moving left. This creates a "progressive
/// mirror" effect that avoids picking up icons/text near the page margin.
///
/// Corner zones (top and bottom, outside the glass area) use much higher opacity for the narrow
/// samples to ensure clean color matching where the glass doesn't provide blur coverage.
final class EdgeExtensionBackgroundView: NSView {
    // MARK: - Layers

    /// Base blurred gradient layer (sampled from full width ~56px)
    private let baseLayer = CAGradientLayer()

    /// Mid gradient layer (sampled from ~20px)
    private let midLayer = CAGradientLayer()

    /// Near gradient layer (sampled from ~8px)
    private let nearLayer = CAGradientLayer()

    /// Edge strip gradient layer (sampled from narrow 2px)
    private let edgeStripLayer = CAGradientLayer()

    /// Container for corner overlays
    private let cornerContainer = CALayer()

    // MARK: - Constants

    private enum Constants {
        /// Gaussian blur radius for the base gradient
        static let blurRadius: CGFloat = 12

        /// Animation duration for color transitions
        static let colorTransitionDuration: CFTimeInterval = 0.3

        // MARK: Progressive Blend Parameters (Tunable)

        /// Width of the fully opaque edge strip region at the right edge (in points).
        static let edgeStripOpaqueWidth: CGFloat = 3

        /// Width where the edge strip transitions to near-edge blend (in points).
        static let edgeStripBlendWidth: CGFloat = 4

        /// Width where the near-edge layer is fully opaque (in points from right).
        static let nearEdgeOpaqueWidth: CGFloat = 8

        /// Width of the near-edge blend zone (in points).
        static let nearEdgeBlendWidth: CGFloat = 8

        /// Width where the mid-edge layer is fully opaque (in points from right).
        static let midEdgeOpaqueWidth: CGFloat = 16

        /// Width of the mid-edge blend zone (in points).
        static let midEdgeBlendWidth: CGFloat = 12

        // MARK: Corner Zone Parameters (Tunable)

        /// Vertical inset from view edge to where glass starts (in points).
        ///
        /// The glass overlay doesn't extend to the very top/bottom of the window.
        static let glassVerticalInset: CGFloat = 8

        /// Corner radius of the glass overlay (in points).
        ///
        /// This determines the quarter-circle shape of the exposed corner area.
        static let glassCornerRadius: CGFloat = 20

        /// Extra padding for the corner mask to ensure full coverage.
        static let cornerMaskPadding: CGFloat = 4
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Setup

    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = true

        // Base layer - full width, blurred (bottom of stack)
        baseLayer.startPoint = CGPoint(x: 0.5, y: 0)
        baseLayer.endPoint = CGPoint(x: 0.5, y: 1)
        baseLayer.masksToBounds = true

        if let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.setValue(Constants.blurRadius, forKey: kCIInputRadiusKey)
            baseLayer.filters = [blurFilter]
        }

        layer?.addSublayer(baseLayer)

        // Mid layer (~20px sample)
        midLayer.startPoint = CGPoint(x: 0.5, y: 0)
        midLayer.endPoint = CGPoint(x: 0.5, y: 1)
        midLayer.masksToBounds = true
        layer?.addSublayer(midLayer)

        // Near layer (~8px sample)
        nearLayer.startPoint = CGPoint(x: 0.5, y: 0)
        nearLayer.endPoint = CGPoint(x: 0.5, y: 1)
        nearLayer.masksToBounds = true
        layer?.addSublayer(nearLayer)

        // Edge strip layer (2px sample, topmost)
        edgeStripLayer.startPoint = CGPoint(x: 0.5, y: 0)
        edgeStripLayer.endPoint = CGPoint(x: 0.5, y: 1)
        edgeStripLayer.masksToBounds = true
        layer?.addSublayer(edgeStripLayer)

        // Corner container (for top and bottom corner overlays)
        layer?.addSublayer(cornerContainer)

        // Set initial colors to clear
        let clearColors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        baseLayer.colors = clearColors
        midLayer.colors = clearColors
        nearLayer.colors = clearColors
        edgeStripLayer.colors = clearColors
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateLayerFrames()
        updateLayerMasks()
    }

    private func updateLayerFrames() {
        // Base layer is expanded for blur overflow
        let expansion = Constants.blurRadius * 2
        baseLayer.frame = CGRect(
            x: -expansion,
            y: -expansion,
            width: bounds.width + expansion * 2,
            height: bounds.height + expansion * 2,
        )

        // All other layers cover the full view
        midLayer.frame = bounds
        nearLayer.frame = bounds
        edgeStripLayer.frame = bounds
        cornerContainer.frame = bounds
    }

    private func updateLayerMasks() {
        // Create horizontal gradient masks for progressive blending
        // Each layer fades in from transparent (left) to opaque (right)

        midLayer.mask = createHorizontalMask(
            opaqueWidth: Constants.midEdgeOpaqueWidth,
            blendWidth: Constants.midEdgeBlendWidth,
        )

        nearLayer.mask = createHorizontalMask(
            opaqueWidth: Constants.nearEdgeOpaqueWidth,
            blendWidth: Constants.nearEdgeBlendWidth,
        )

        edgeStripLayer.mask = createEdgeStripMask()
    }

    /// Creates a horizontal gradient mask: transparent on left, opaque on right.
    private func createHorizontalMask(opaqueWidth: CGFloat, blendWidth: CGFloat) -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.frame = bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)

        let totalWidth = opaqueWidth + blendWidth
        let blendStartRatio = max(0, 1 - totalWidth / bounds.width)
        let opaqueStartRatio = max(0, 1 - opaqueWidth / bounds.width)

        mask.colors = [
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.white.cgColor,
            NSColor.white.cgColor,
        ]
        mask.locations = [
            0.0,
            NSNumber(value: blendStartRatio),
            NSNumber(value: opaqueStartRatio),
            1.0,
        ]

        return mask
    }

    /// Creates the edge strip mask with extra corner coverage.
    private func createEdgeStripMask() -> CALayer {
        let container = CALayer()
        container.frame = bounds

        // Base horizontal gradient (for middle section)
        let horizontalMask = createHorizontalMask(
            opaqueWidth: Constants.edgeStripOpaqueWidth,
            blendWidth: Constants.edgeStripBlendWidth,
        )
        container.addSublayer(horizontalMask)

        // Top corner overlay - nearly fully opaque rectangle with fades
        let topCorner = createCornerOverlay(isTop: true)
        container.addSublayer(topCorner)

        // Bottom corner overlay
        let bottomCorner = createCornerOverlay(isTop: false)
        container.addSublayer(bottomCorner)

        return container
    }

    /// Creates a corner overlay with a quarter-circle radial gradient matching the glass corner shape.
    ///
    /// The glass overlay has rounded corners that don't extend to the view edges.
    /// This creates a radial mask that's opaque in the exposed corner area (outside the glass)
    /// and transparent where the glass provides blur coverage.
    private func createCornerOverlay(isTop: Bool) -> CAGradientLayer {
        let overlay = CAGradientLayer()
        overlay.type = .radial

        let inset = Constants.glassVerticalInset
        let radius = Constants.glassCornerRadius

        // Make the overlay MUCH larger than needed so its frame boundary is never visible.
        // The gradient controls where the actual effect appears.
        let overlaySize = max(bounds.width, bounds.height)

        // The actual effect radius where the glass corner ends
        let effectRadius = radius + inset

        if isTop {
            // Top-right corner (AppKit: y increases upward, so top = bounds.height)
            // Position so the radial center is at the glass corner center
            overlay.frame = CGRect(
                x: bounds.width - overlaySize,
                y: bounds.height - overlaySize,
                width: overlaySize,
                height: overlaySize,
            )
            // Radial gradient: center at bottom-left of overlay (glass corner center)
            overlay.startPoint = CGPoint(x: 0, y: 0)
            overlay.endPoint = CGPoint(x: 1, y: 1)
        } else {
            // Bottom-right corner
            overlay.frame = CGRect(
                x: bounds.width - overlaySize,
                y: 0,
                width: overlaySize,
                height: overlaySize,
            )
            // Center at top-left of overlay, radiate toward bottom-right
            overlay.startPoint = CGPoint(x: 0, y: 1)
            overlay.endPoint = CGPoint(x: 1, y: 0)
        }

        // The gradient location where the glass corner ends
        // effectRadius is the distance from center, overlaySize * sqrt(2) is the diagonal
        let diagonalDistance = overlaySize * sqrt(2)
        let glassEdgeLocation = effectRadius / diagonalDistance

        // Use a very gradual fade - the effect is subtle and contained to the corner
        overlay.colors = [
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.5).cgColor,
            NSColor.clear.cgColor,
        ]
        overlay.locations = [
            0.0,
            NSNumber(value: max(0, glassEdgeLocation * 0.7)),
            NSNumber(value: glassEdgeLocation),
            NSNumber(value: min(1.0, glassEdgeLocation * 1.5)),
        ]

        return overlay
    }

    // MARK: - Public API

    /// Updates the gradient with new colors sampled from the webview edge at multiple depths.
    ///
    /// - Parameters:
    ///   - colors: Array of colors for the base blurred gradient (full width sample).
    ///   - edgeStripColors: Array of colors for the narrow edge strip (2px sample).
    ///   - nearEdgeColors: Array of colors for the near-edge layer (~8px sample).
    ///   - midEdgeColors: Array of colors for the mid-edge layer (~20px sample).
    ///   - topCornerColor: Precise color for the top corner (pixel-perfect).
    ///   - bottomCornerColor: Precise color for the bottom corner (pixel-perfect).
    func updateColors(
        _ colors: [NSColor],
        edgeStripColors: [NSColor] = [],
        nearEdgeColors: [NSColor] = [],
        midEdgeColors: [NSColor] = [],
        topCornerColor: NSColor? = nil,
        bottomCornerColor: NSColor? = nil,
    ) {
        guard !colors.isEmpty else {
            clearColors(animated: true)
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(Constants.colorTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        applyColors(colors, to: baseLayer)
        applyColors(midEdgeColors.isEmpty ? colors : midEdgeColors, to: midLayer)
        applyColors(nearEdgeColors.isEmpty ? colors : nearEdgeColors, to: nearLayer)

        // For edge strip, use precise corner colors at the ends if available
        var adjustedEdgeStripColors = edgeStripColors.isEmpty ? colors : edgeStripColors
        if let topColor = topCornerColor, !adjustedEdgeStripColors.isEmpty {
            adjustedEdgeStripColors[0] = topColor
        }
        if let bottomColor = bottomCornerColor, adjustedEdgeStripColors.count > 1 {
            adjustedEdgeStripColors[adjustedEdgeStripColors.count - 1] = bottomColor
        }
        applyColors(adjustedEdgeStripColors, to: edgeStripLayer)

        CATransaction.commit()
    }

    private func applyColors(_ colors: [NSColor], to layer: CAGradientLayer) {
        // Colors array is top-to-bottom (index 0 = top of webpage)
        // AppKit gradient: location 0 = bottom of view, location 1 = top of view
        // Reverse so top-of-page color ends up at top-of-view
        let reversed = colors.reversed()
        layer.colors = reversed.map(\.cgColor)
        layer.locations = colors.indices.map { index in
            NSNumber(value: Double(index) / Double(max(colors.count - 1, 1)))
        }
    }

    /// Clears the gradient colors, optionally with animation.
    func clearColors(animated: Bool) {
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(Constants.colorTransitionDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }

        let clearColors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        baseLayer.colors = clearColors
        baseLayer.locations = nil
        midLayer.colors = clearColors
        midLayer.locations = nil
        nearLayer.colors = clearColors
        nearLayer.locations = nil
        edgeStripLayer.colors = clearColors
        edgeStripLayer.locations = nil

        CATransaction.commit()
    }

    /// Sets the visibility of the background view with optional animation.
    func setVisible(_ visible: Bool, animated: Bool) {
        let targetAlpha: CGFloat = visible ? 1.0 : 0.0

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.colorTransitionDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().alphaValue = targetAlpha
            }
        } else {
            alphaValue = targetAlpha
        }

        isHidden = !visible && !animated
    }
}
