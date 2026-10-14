import AppKit

/// A glass slab holding a tab's snapshot. It lifts when held and settles on release.
final class CanvasTileView: NSView {
    var tab: Tab {
        didSet {
            updateIdentity()
            needsLayout = true
        }
    }

    var placement = FloatingTabPlacement.initial(index: 0) {
        didSet { needsLayout = true }
    }

    var snapshot: NSImage? {
        didSet {
            imageLayer.contents = snapshot
            placeholderLabel.isHidden = snapshot != nil || placement.shape != .live
        }
    }

    var isSelected = false {
        didSet { applyColors() }
    }

    var isTargeted = false {
        didSet { applyColors() }
    }

    var onClick: ((CanvasTileView) -> Void)?
    var onSelect: ((CanvasTileView) -> Void)?
    var onTogglePreview: ((CanvasTileView) -> Void)?
    /// Called after each move while the tile is dragged.
    var onDrag: ((CanvasTileView) -> Void)?
    /// Called on drop with the release velocity in board points per second.
    var onRelease: ((CanvasTileView, CGPoint) -> Void)?
    private(set) var isDragging = false
    var isLifted = false {
        didSet { updateElevation() }
    }

    private let edgeLayer = CAGradientLayer()
    private let edgeMask = CAShapeLayer()
    private let glass = NSGlassEffectView()
    private let glassContent = NSView()
    private let imageLayer = CALayer()
    private let targetLayer = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let faviconView = NSImageView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    private var faviconData: Data?
    private var dragOrigin: CGPoint = .zero
    private var frameAtDragStart: CGRect = .zero
    private var samples: [(time: CFTimeInterval, point: CGPoint)] = []

    private enum Constants {
        static let cornerRadius = CanvasTileLayout.slabCornerRadius - CanvasTileLayout.glassInset
        static let glassInset = CanvasTileLayout.glassInset
        static let titleHeight: CGFloat = 20
        static let dragThreshold: CGFloat = 3
        /// Only samples this recent count toward the release velocity.
        static let velocityWindow: CFTimeInterval = 0.08
        static let selectedBorderWidth: CGFloat = 3
        static let targetInset: CGFloat = 5
        static let thickness = CanvasPhysics.Constants.slabThickness
        static let liftDuration: TimeInterval = 0.16
    }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false

        edgeLayer.cornerRadius = Constants.cornerRadius + Constants.glassInset
        edgeLayer.borderWidth = 0.5
        edgeMask.fillRule = .evenOdd
        edgeLayer.mask = edgeMask
        layer?.addSublayer(edgeLayer)
        glass.style = .regular
        glass.cornerRadius = Constants.cornerRadius + Constants.glassInset
        if #available(macOS 27, *) {
            glass.effectIsInteractive = true
        }
        glass.contentView = glassContent
        glassContent.wantsLayer = true
        addSubview(glass)
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.cornerRadius = Constants.cornerRadius
        imageLayer.masksToBounds = true
        glassContent.layer?.addSublayer(imageLayer)
        targetLayer.cornerRadius = Constants.cornerRadius + Constants.targetInset
        targetLayer.borderWidth = 2
        layer?.addSublayer(targetLayer)
        updateElevation()

        titleLabel.stringValue = tab.displayTitle
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        glassContent.addSubview(titleLabel)
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        glassContent.addSubview(faviconView)

        placeholderLabel.stringValue = tab.activePage.url.host() ?? tab.displayTitle
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.alignment = .center
        glassContent.addSubview(placeholderLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateIdentity()
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glass.frame = glassFrame
        edgeLayer.frame = glassFrame.offsetBy(dx: 0, dy: -Constants.thickness)
        let edgePath = CGMutablePath()
        edgePath.addRoundedRect(in: edgeLayer.bounds, cornerWidth: glass.cornerRadius, cornerHeight: glass.cornerRadius)
        edgePath.addRoundedRect(in: edgeLayer.bounds.offsetBy(dx: 0, dy: Constants.thickness), cornerWidth: glass.cornerRadius, cornerHeight: glass.cornerRadius)
        edgeMask.path = edgePath
        glassContent.frame = CGRect(origin: .zero, size: glassFrame.size)
        imageLayer.frame = CGRect(x: Constants.glassInset, y: Constants.glassInset, width: max(0, glassFrame.width - Constants.glassInset * 2), height: max(0, glassFrame.height - FloatingTabPlacement.headerHeight - Constants.glassInset * 2))
        imageLayer.isHidden = placement.shape != .live
        imageLayer.opacity = Float(previewVisibility)
        targetLayer.frame = glassFrame.insetBy(dx: -Constants.targetInset, dy: -Constants.targetInset)
        layer?.shadowPath = CGPath(roundedRect: edgeLayer.frame, cornerWidth: glass.cornerRadius, cornerHeight: glass.cornerRadius, transform: nil)
        CATransaction.commit()
        // Above the tile: the superview is flipped, this view is not.
        let compactTitleY = (glassFrame.height - Constants.titleHeight) / 2
        let previewTitleY = glassFrame.height - FloatingTabPlacement.headerHeight + (FloatingTabPlacement.headerHeight - Constants.titleHeight) / 2
        let titleY = compactTitleY + (previewTitleY - compactTitleY) * previewVisibility
        titleLabel.frame = CGRect(x: Constants.glassInset + 28, y: titleY, width: max(0, bounds.width - 36), height: Constants.titleHeight)
        faviconView.frame = CGRect(x: Constants.glassInset + 5, y: titleY + 2, width: 16, height: 16)
        placeholderLabel.frame = imageLayer.frame.insetBy(dx: 12, dy: 0)
        placeholderLabel.isHidden = snapshot != nil || placement.shape != .live
        titleLabel.isHidden = placement.shape == .icon
        if placement.shape == .icon {
            faviconView.frame = CGRect(x: (glassFrame.width - 20) / 2, y: (glassFrame.height - 20) / 2, width: 20, height: 20)
        }
    }

    private var glassFrame: CGRect {
        bounds
    }

    /// The page rectangle used when entering this card, centered at its table position.
    var previewFrame: CGRect {
        let size = placement.shape == .live ? frame.size : FloatingCardShape.live.fitted(
            CGSize(width: placement.previewWidth ?? .nan, height: placement.previewHeight ?? .nan),
        )
        return CanvasTileLayout.centeredFrame(size: size, on: frame)
    }

    /// The raised glass outline in the containing plane, used to position nearby cues.
    var slabFrameInSuperview: CGRect {
        convert(glassFrame, to: superview)
    }

    private var previewVisibility: CGFloat {
        placement.shape == .live ? 1 : 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, glassFrame.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    private func updateElevation() {
        guard let layer else { return }
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Constants.liftDuration
        let shadowRadius: CGFloat = isLifted ? 24 : 10
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "shadowRadius")
            animation.fromValue = layer.presentation()?.shadowRadius ?? layer.shadowRadius
            animation.toValue = shadowRadius
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "lift")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = isLifted ? 0.3 : 0.22
        layer.shadowRadius = shadowRadius
        layer.shadowOffset = CGSize(width: 0, height: isLifted ? -18 : -5)
        CATransaction.commit()
    }

    private func updateAccessibilityState() {
        setAccessibilityValue(isSelected ? "Selected" : "")
    }

    override func updateLayer() {
        applyColors()
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { applyColors() }
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { updateColors() }
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        imageLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let base = NSColor.windowBackgroundColor
        edgeLayer.colors = [
            (base.blended(withFraction: 0.12, of: .labelColor) ?? base).cgColor,
            (base.blended(withFraction: 0.32, of: .labelColor) ?? base).cgColor,
        ]
        edgeLayer.borderColor = NSColor.separatorColor.cgColor
        imageLayer.borderWidth = isSelected ? Constants.selectedBorderWidth : 1
        imageLayer.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
        targetLayer.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.keyboardFocusIndicatorColor.cgColor
        targetLayer.cornerRadius = glass.cornerRadius + Constants.targetInset
        targetLayer.isHidden = !isTargeted && !(isSelected && placement.shape != .live)
        titleLabel.textColor = isTargeted || placement.shape != .live ? .labelColor : .secondaryLabelColor
        updateAccessibilityState()
    }

    private func updateIdentity() {
        titleLabel.stringValue = tab.displayTitle
        placeholderLabel.stringValue = tab.activePage.url.host() ?? tab.displayTitle
        if faviconData != tab.activePage.faviconData || faviconView.image == nil {
            faviconData = tab.activePage.faviconData
            faviconView.image = faviconData.flatMap { NSImage(data: $0) }
                ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        }
        toolTip = tab.displayTitle
        setAccessibilityLabel(tab.displayTitle)
        setAccessibilityHelp("Open tab. Use arrow keys to move, Space to select, and the context menu to change preview size.")
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: placement.shape != .live ? "Show Preview" : "Make Compact", action: #selector(togglePreview), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc
    private func togglePreview() {
        onTogglePreview?(self)
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?(self)
        return true
    }

    /// A brief rock at contact makes the impulse visible while preserving the slab's place.
    func respondToImpact(_ impact: CanvasPhysics.Impact, direction: CGFloat) {
        guard !isLifted, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        let strength = min(1, impact.speed / 1_200)
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let angle = direction * strength * 0.012
        animation.values = [0, angle, -angle * 0.35, 0]
        animation.keyTimes = [0, 0.18, 0.5, 1]
        animation.duration = 0.22
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "contact")
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        guard let superview else { return }
        dragOrigin = superview.convert(event.locationInWindow, from: nil)
        frameAtDragStart = frame
        isDragging = false
        samples = [(CACurrentMediaTime(), dragOrigin)]
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: point.x - dragOrigin.x, y: point.y - dragOrigin.y)
        if !isDragging, hypot(delta.x, delta.y) < Constants.dragThreshold {
            return
        }
        isDragging = true
        frame = frameAtDragStart.offsetBy(dx: delta.x, dy: delta.y)
        samples.append((CACurrentMediaTime(), point))
        samples.removeAll { CACurrentMediaTime() - $0.time > Constants.velocityWindow * 4 }
        onDrag?(self)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
                onSelect?(self)
            } else {
                onClick?(self)
            }
            return
        }
        isDragging = false
        onRelease?(self, releaseVelocity())
    }

    /// Velocity over the last few samples, in board points per second.
    private func releaseVelocity() -> CGPoint {
        let now = CACurrentMediaTime()
        let recent = samples.filter { now - $0.time <= Constants.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return .zero }
        let dt = CGFloat(last.time - first.time)
        return CGPoint(x: (last.point.x - first.point.x) / dt, y: (last.point.y - first.point.y) / dt)
    }
}
