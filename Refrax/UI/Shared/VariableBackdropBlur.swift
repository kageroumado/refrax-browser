import AppKit
import CoreGraphics
import QuartzCore
import SwiftUI

// MARK: - Variable Backdrop Blur

/// Edge for variable blur gradient direction.
enum VariableBlurEdge {
    /// Blur increases from bottom to top (for headers).
    case top
    /// Blur increases from top to bottom (for footers).
    case bottom
}

/// Pre-generated gradient data for variable blur masks.
enum VariableBlurGradient {
    /// Length of the gradient transition zone in pixels.
    static let transitionLength: Int = 32

    /// Pre-generated gradient bytes (grayscale alpha values from 0 to 255).
    /// Generated once at app launch.
    static let gradientBytes: [UInt8] = (0 ..< transitionLength).map { i in
        // Linear interpolation from 0 to 255 over transitionLength pixels
        UInt8((i * 255) / (transitionLength - 1))
    }

    // MARK: - Mask Cache

    /// Cache key combining all parameters that affect mask content.
    private struct MaskKey: Hashable {
        let width: Int
        let height: Int
        let edge: VariableBlurEdge
    }

    /// LRU cache for generated masks.
    /// Window sizes are constrained, so a small cache covers most cases.
    private static var maskCache: [MaskKey: CGImage] = [:]

    /// Maximum number of cached masks before eviction.
    private static let maxCacheSize = 10

    /// Creates a CGImage mask for variable blur.
    ///
    /// The mask uses the **alpha channel** to control blur intensity.
    /// Alpha 0 = no blur, Alpha 255 = max blur.
    /// Each row has uniform alpha, varying vertically according to the gradient.
    ///
    /// Results are cached by (width, height, edge) to avoid regeneration on every layout pass.
    ///
    /// - Parameters:
    ///   - width: Width of the mask in points.
    ///   - height: Height of the mask in points.
    ///   - edge: Which edge the blur is for (determines gradient direction).
    /// - Returns: A CGImage mask, or nil if creation fails.
    static func createMask(width: Int, height: Int, edge: VariableBlurEdge) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        // Check cache first
        let key = MaskKey(width: width, height: height, edge: edge)
        if let cached = maskCache[key] {
            return cached
        }

        // Create new mask
        guard let mask = createMaskUncached(width: width, height: height, edge: edge) else {
            return nil
        }

        // Cache with simple eviction (clear all when full)
        if maskCache.count >= maxCacheSize {
            maskCache.removeAll(keepingCapacity: true)
        }
        maskCache[key] = mask

        return mask
    }

    /// Creates a mask without caching (internal implementation).
    private static func createMaskUncached(width: Int, height: Int, edge: VariableBlurEdge) -> CGImage? {
        // Build vertical alpha values (one per row)
        // Alpha 0 = no blur, Alpha 255 = max blur
        // Default to 255 (max blur) for areas outside the transition gradient
        var rowAlphas = [UInt8](repeating: 255, count: height)

        // Apply gradient at the appropriate edge
        let gradientPixels = min(transitionLength, height)

        // Row 0 = top of view in layer coordinates
        switch edge {
        case .top:
            // Header: content enters from bottom, blur increases going up
            // Top of header = max blur (255), transition at bottom going to no blur (0)
            for i in 0 ..< gradientPixels {
                // Row (height - gradientPixels) = 255 (max blur, start of transition)
                // Row (height - 1) = 0 (no blur, bottom edge)
                let row = height - gradientPixels + i
                rowAlphas[row] = UInt8(255 - (i * 255) / max(1, gradientPixels - 1))
            }

        case .bottom:
            // Footer: content enters from top, blur increases going down
            // Bottom of footer = max blur (255), transition at top going to no blur (0)
            for i in 0 ..< gradientPixels {
                // Row 0 = 0 (no blur, top edge)
                // Row (gradientPixels - 1) = 255 (max blur, end of transition)
                rowAlphas[i] = UInt8((i * 255) / max(1, gradientPixels - 1))
            }
        }

        // Create RGBA image where alpha controls blur
        // Only set alpha channel - RGB are initialized to 0
        var imageData = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            let alpha = rowAlphas[y]
            let rowStart = y * width * 4
            // Stride by 4 to only set alpha channel (offset 3 in each RGBA pixel)
            for alphaOffset in stride(from: rowStart + 3, to: rowStart + width * 4, by: 4) {
                imageData[alphaOffset] = alpha
            }
        }

        let bitsPerComponent = 8
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: &imageData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return nil
        }

        return context.makeImage()
    }
}

/// SwiftUI view providing variable backdrop blur for scroll edge effects.
///
/// Uses CABackdropLayer with variableBlur CAFilter to create a progressive blur
/// effect that increases from the content edge into the bar.
///
/// Optionally applies a gradual color tint using the same gradient direction
/// for a frosted glass effect.
struct VariableBackdropBlurView: View {
    let edge: VariableBlurEdge
    let maxBlurRadius: CGFloat
    let tintColor: Color?
    let tintOpacity: CGFloat

    init(
        edge: VariableBlurEdge,
        maxBlurRadius: CGFloat = 8,
        tintColor: Color? = nil,
        tintOpacity: CGFloat = 0.02,
    ) {
        self.edge = edge
        self.maxBlurRadius = maxBlurRadius
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VariableBackdropBlurRepresentable(
                    edge: edge,
                    maxBlurRadius: maxBlurRadius,
                    size: geometry.size,
                )

                // Gradual tint overlay with .color blend mode
                // Affects hue/saturation only, preserving luminance
                if let tint = tintColor {
                    tint
                        .opacity(tintOpacity)
                        .blendMode(.color)
                        .mask(TintGradientMask(edge: edge, height: geometry.size.height))
                        .animation(.easeInOut(duration: 0.3), value: tint)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Gradient mask for tint overlay, cached by height via Equatable.
private struct TintGradientMask: View, Equatable {
    let edge: VariableBlurEdge
    let height: CGFloat

    @State private var cachedGradient: LinearGradient?
    @State private var lastGradientHeight: CGFloat = 0
    @State private var lastGradientEdge: VariableBlurEdge?

    var body: some View {
        gradient
    }

    private var gradient: LinearGradient {
        // Return cached gradient if inputs unchanged
        if let cached = cachedGradient, lastGradientHeight == height, lastGradientEdge == edge {
            return cached
        }

        let transitionRatio = min(1.0, CGFloat(VariableBlurGradient.transitionLength) / max(1, height))

        let newGradient = LinearGradient(
            stops: edge == .top ? [
                .init(color: .white, location: 0),
                .init(color: .white, location: 1 - transitionRatio),
                .init(color: .clear, location: 1),
            ] : [
                .init(color: .clear, location: 0),
                .init(color: .white, location: transitionRatio),
                .init(color: .white, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )

        // Update cache (deferred to avoid modifying state during view update)
        DispatchQueue.main.async {
            cachedGradient = newGradient
            lastGradientHeight = height
            lastGradientEdge = edge
        }

        return newGradient
    }

    static func == (lhs: TintGradientMask, rhs: TintGradientMask) -> Bool {
        lhs.edge == rhs.edge && lhs.height == rhs.height
    }
}

/// NSViewRepresentable wrapper that passes size to the NSView.
///
/// Conforms to Equatable so SwiftUI can skip updateNSView when parameters haven't changed.
private struct VariableBackdropBlurRepresentable: NSViewRepresentable, Equatable {
    let edge: VariableBlurEdge
    let maxBlurRadius: CGFloat
    let size: CGSize

    func makeNSView(context _: Context) -> VariableBackdropBlurNSView {
        let view = VariableBackdropBlurNSView()
        view.wantsLayer = true
        view.edge = edge
        view.maxBlurRadius = maxBlurRadius
        return view
    }

    func updateNSView(_ nsView: VariableBackdropBlurNSView, context _: Context) {
        nsView.edge = edge
        nsView.maxBlurRadius = maxBlurRadius
        // Force mask update when size changes
        nsView.updateMaskForSize(size)
    }
}

/// NSView subclass using CABackdropLayer with variable blur filter.
final class VariableBackdropBlurNSView: NSView {
    private let groupName = UUID().uuidString
    private var variableBlurFilter: CAFilter?
    private var saturateFilter: CAFilter?
    private var brightnessFilter: CAFilter?
    private var currentMaskSize: (width: Int, height: Int) = (0, 0)

    /// Whether we have a valid mask applied to the filter.
    /// Filters should not be applied to the layer until this is true,
    /// otherwise visual artifacts (moving shadows) occur.
    private var hasValidMask = false

    /// Whether the window has had time to stabilize after appearing.
    /// CABackdropLayer can produce visual artifacts (moving shadows) when sampling
    /// content before the window is fully composited. This is set to true after
    /// a brief delay when the view moves to a window.
    private var isWindowStable = false

    /// Delay before enabling filters after window appearance.
    /// This gives the window server time to composite the window content.
    private static let windowStabilizationDelay: TimeInterval = 1

    var edge: VariableBlurEdge = .top {
        didSet {
            if oldValue != edge {
                updateMask()
            }
        }
    }

    var maxBlurRadius: CGFloat = 8 {
        didSet {
            variableBlurFilter?.setValue(maxBlurRadius, forKey: "inputRadius")
        }
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func makeBackingLayer() -> CALayer {
        CABackdropLayer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupFilter()
            // Don't configure backdrop layer until we have valid bounds.
            // Applying filters without a valid mask causes visual artifacts.
            // layout() will call configureBackdropLayer once bounds are valid.

            // Delay enabling filters to avoid artifacts during window compositing.
            // CABackdropLayer can produce "moving shadow" artifacts when sampling
            // content before the window is fully composited by the window server.
            isWindowStable = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.windowStabilizationDelay) { [weak self] in
                guard let self, window != nil else { return }
                isWindowStable = true
                configureBackdropLayer()
            }
        } else {
            // Window removed - reset stability flag
            isWindowStable = false
        }
    }

    override func updateLayer() {
        configureBackdropLayer()
    }

    override func layout() {
        super.layout()
        updateMaskIfNeeded()
    }

    private func setupFilter() {
        guard variableBlurFilter == nil else { return }

        guard let blurFilter = CAFilter(type: "variableBlur") else {
            return
        }

        blurFilter.setValue(maxBlurRadius, forKey: "inputRadius")
        blurFilter.setValue(true, forKey: "inputNormalizeEdges")
        variableBlurFilter = blurFilter

        // Lighten dark content to create proper frosted glass effect.
        // Reduces contrast and adds brightness so dark text/icons become lighter.
        if let controlsFilter = CAFilter(type: "colorControls") {
            controlsFilter.setValue(0.18, forKey: "inputBrightness") // Lift overall brightness
            controlsFilter.setValue(0.75, forKey: "inputContrast") // Reduce contrast (brings blacks toward gray)
            brightnessFilter = controlsFilter
        }

        // Saturation boost for more vibrant frosted glass effect
        if let satFilter = CAFilter(type: "colorSaturate") {
            satFilter.setValue(1.2, forKey: "inputAmount")
            saturateFilter = satFilter
        }

        updateMask()
    }

    private func configureBackdropLayer() {
        guard let layer = layer as? CABackdropLayer else { return }

        layer.windowServerAware = false
        layer.groupName = groupName
        layer.scale = 1
        layer.bleedAmount = 0.0
        layer.disablesOccludedBackdropBlurs = false
        layer.ignoresOffscreenGroups = false

        layer.allowsGroupBlending = true
        layer.allowsGroupOpacity = true
        layer.allowsEdgeAntialiasing = false
        layer.allowsInPlaceFiltering = false

        // Only apply filters once we have a valid mask AND the window has stabilized.
        // Applying filters too early causes visual artifacts (moving shadows) because
        // CABackdropLayer samples content before the window is fully composited.
        guard hasValidMask, isWindowStable else {
            layer.filters = nil
            return
        }

        // Apply filters for frosted glass effect:
        // 1. Variable blur for the gradient blur
        // 2. Brightness/contrast adjustment to lighten dark content
        // 3. Saturation boost for vibrancy
        var filters: [CAFilter] = []
        if let blur = variableBlurFilter {
            filters.append(blur)
        }
        if let brightness = brightnessFilter {
            filters.append(brightness)
        }
        if let saturate = saturateFilter {
            filters.append(saturate)
        }
        layer.filters = filters
    }

    /// Called from SwiftUI when geometry changes.
    func updateMaskForSize(_ size: CGSize) {
        // Use points, not pixels - the filter scales the mask to match the layer
        let newWidth = Int(size.width)
        let newHeight = Int(size.height)

        if (newWidth, newHeight) != currentMaskSize, newWidth > 0, newHeight > 0 {
            currentMaskSize = (newWidth, newHeight)
            updateMask(width: newWidth, height: newHeight)
        }
    }

    private func updateMaskIfNeeded() {
        let newWidth = Int(bounds.width)
        let newHeight = Int(bounds.height)

        if (newWidth, newHeight) != currentMaskSize, newWidth > 0, newHeight > 0 {
            currentMaskSize = (newWidth, newHeight)
            updateMask(width: newWidth, height: newHeight)
        }
    }

    private func updateMask(width: Int? = nil, height: Int? = nil) {
        guard let filter = variableBlurFilter else { return }

        let w = width ?? Int(bounds.width)
        let h = height ?? Int(bounds.height)

        // Skip if bounds are too small - this prevents visual artifacts during window creation.
        // layout() will call us again once the view has proper dimensions.
        // A minimum of 8 pixels ensures we have a reasonable gradient transition.
        guard w >= 8, h >= 8 else {
            // Clear any existing mask and mark as invalid
            filter.setValue(nil, forKey: "inputMaskImage")
            hasValidMask = false
            return
        }

        guard let maskImage = VariableBlurGradient.createMask(width: w, height: h, edge: edge) else {
            return
        }

        let wasInvalid = !hasValidMask
        filter.setValue(maskImage, forKey: "inputMaskImage")
        hasValidMask = true

        // Configure backdrop layer once we have a valid mask for the first time.
        // This ensures filters are applied regardless of which code path triggers the update.
        if wasInvalid {
            configureBackdropLayer()
        }
    }
}
