import AppKit

/// A group on the desk: a tinted plate with the group's name, holding its member tiles.
final class CanvasZoneView: NSView {
    var zone: CanvasZone {
        didSet {
            guard zone != oldValue else { return }
            apply()
        }
    }

    var onDrag: ((CanvasZoneView, CGPoint) -> Void)?
    var onDragEnd: ((CanvasZoneView, CGPoint) -> Void)?
    private(set) var isDragging = false

    private let nameLabel = NSTextField(labelWithString: "")
    private var dragOrigin: CGPoint = .zero
    private var frameAtDragStart: CGRect = .zero
    private var lastDragPoint: CGPoint = .zero

    private enum Constants {
        static let cornerRadius: CGFloat = 20
        static let fillAlpha: CGFloat = 0.10
        static let borderAlpha: CGFloat = 0.35
        static let dragThreshold: CGFloat = 3
    }

    init(zone: CanvasZone) {
        self.zone = zone
        super.init(frame: zone.frame)
        wantsLayer = true
        layer?.cornerRadius = Constants.cornerRadius
        layer?.borderWidth = 1.5

        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        apply()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    private func apply() {
        nameLabel.stringValue = zone.name
        nameLabel.textColor = zone.color
        layer?.backgroundColor = zone.color.withAlphaComponent(Constants.fillAlpha).cgColor
        layer?.borderColor = zone.color.withAlphaComponent(Constants.borderAlpha).cgColor
    }

    override func updateLayer() {
        apply()
    }

    override func layout() {
        super.layout()
        nameLabel.frame = CGRect(x: 16, y: 9, width: bounds.width - 32, height: 20)
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        guard let superview else { return }
        dragOrigin = superview.convert(event.locationInWindow, from: nil)
        lastDragPoint = dragOrigin
        frameAtDragStart = frame
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        let total = CGPoint(x: point.x - dragOrigin.x, y: point.y - dragOrigin.y)
        if !isDragging, hypot(total.x, total.y) < Constants.dragThreshold {
            return
        }
        isDragging = true
        frame = frameAtDragStart.offsetBy(dx: total.x, dy: total.y)
        onDrag?(self, CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y))
        lastDragPoint = point
    }

    override func mouseUp(with _: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let delta = CGPoint(x: frame.minX - frameAtDragStart.minX, y: frame.minY - frameAtDragStart.minY)
        onDragEnd?(self, delta)
    }
}
