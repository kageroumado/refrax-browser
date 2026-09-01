import AppKit

/// One tab on the desk: its snapshot, with the title above it. Draggable and flingable.
final class CanvasTileView: NSView {
    var tab: Tab {
        didSet { titleLabel.stringValue = tab.displayTitle }
    }

    var snapshot: NSImage? {
        didSet {
            imageLayer.contents = snapshot
            placeholderLabel.isHidden = snapshot != nil
        }
    }

    var isSelected = false {
        didSet { applyColors() }
    }

    var onClick: ((CanvasTileView) -> Void)?
    /// Called on drop with the release velocity in board points per second.
    var onRelease: ((CanvasTileView, CGPoint) -> Void)?
    private(set) var isDragging = false

    private let imageLayer = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let placeholderLabel = NSTextField(labelWithString: "")
    private var dragOrigin: CGPoint = .zero
    private var frameAtDragStart: CGRect = .zero
    private var samples: [(time: CFTimeInterval, point: CGPoint)] = []

    private enum Constants {
        static let cornerRadius: CGFloat = 12
        static let titleHeight: CGFloat = 20
        static let dragThreshold: CGFloat = 3
        /// Only samples this recent count toward the release velocity.
        static let velocityWindow: CFTimeInterval = 0.08
        static let selectedBorderWidth: CGFloat = 3
    }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.cornerRadius = Constants.cornerRadius
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -6)

        titleLabel.stringValue = tab.displayTitle
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        placeholderLabel.stringValue = tab.activePage.url.host() ?? tab.displayTitle
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.alignment = .center
        addSubview(placeholderLabel)
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
        imageLayer.frame = bounds
        CATransaction.commit()
        // Above the tile: the superview is flipped, this view is not.
        titleLabel.frame = CGRect(x: 2, y: bounds.height + 4, width: bounds.width - 4, height: Constants.titleHeight)
        placeholderLabel.frame = bounds.insetBy(dx: 12, dy: 0)
    }

    override func updateLayer() {
        applyColors()
    }

    private func applyColors() {
        imageLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageLayer.borderWidth = isSelected ? Constants.selectedBorderWidth : 1
        imageLayer.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
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
    }

    override func mouseUp(with _: NSEvent) {
        guard isDragging else {
            onClick?(self)
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
