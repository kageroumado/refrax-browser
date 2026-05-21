import AppKit
import QuartzCore
import SwiftUI

// MARK: - Backdrop Blur View

/// A blur view using CABackdropLayer for true backdrop blur effects.
///
/// Blurs content visible behind the view, providing a frosted glass effect.
/// Shape clipping is handled by the SwiftUI modifier, not the layer.
///
/// Conforms to Equatable so SwiftUI can skip updateNSView when blurRadius hasn't changed.
struct BackdropBlurView: NSViewRepresentable, Equatable {
    let blurRadius: CGFloat

    init(blurRadius: CGFloat = 20) {
        self.blurRadius = blurRadius
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.blurRadius == rhs.blurRadius
    }

    func makeNSView(context _: Context) -> NSView {
        let view = BackdropBlurNSView()
        view.wantsLayer = true
        view.blurRadius = blurRadius
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? BackdropBlurNSView else { return }
        view.blurRadius = blurRadius
    }
}

/// NSView subclass that uses CABackdropLayer as its backing layer.
///
/// CABackdropLayer is a private API that captures and filters content behind the layer,
/// providing true backdrop blur effects. Configuration must be applied in `updateLayer()`
/// and `viewDidMoveToWindow()` as the layer properties get reset during view setup.
final class BackdropBlurNSView: NSView {
    private let groupName = UUID().uuidString
    private var blurFilter: CAFilter?

    var blurRadius: CGFloat = 10 {
        didSet {
            updateBlurRadius()
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CABackdropLayer()
        blurFilter = createGaussianBlurFilter()
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            configureBackdropLayer()
        }
    }

    override func updateLayer() {
        configureBackdropLayer()
    }

    private func configureBackdropLayer() {
        guard let layer = layer as? CABackdropLayer else { return }

        layer.windowServerAware = true
        layer.groupName = groupName
        layer.scale = 0.25
        layer.bleedAmount = 0.0
        layer.disablesOccludedBackdropBlurs = false
        layer.ignoresOffscreenGroups = false

        layer.allowsGroupBlending = true
        layer.allowsGroupOpacity = true
        layer.allowsEdgeAntialiasing = false
        layer.allowsInPlaceFiltering = false

        if let blur = blurFilter {
            layer.filters = [blur]
        }
    }

    private func updateBlurRadius() {
        blurFilter?.setValue(blurRadius, forKey: "inputRadius")
    }

    private func createGaussianBlurFilter() -> CAFilter? {
        guard let filter = CAFilter(name: "gaussianBlur") else { return nil }

        filter.setValue(true, forKey: "inputNormalizeEdges")
        filter.setValue(blurRadius, forKey: "inputRadius")

        return filter
    }
}
