import AppKit

/// A magnet on the desk: a disc in the group's color with its name beneath.
///
/// Drag it and its members follow; double-click it to pull in similar tabs again.
final class CanvasMagnetView: NSView {
    var magnet: CanvasMagnet {
        didSet {
            guard magnet != oldValue else { return }
            apply()
        }
    }

    var onDrag: ((CanvasMagnetView, CGPoint) -> Void)?
    var onDragEnd: ((CanvasMagnetView, CGPoint) -> Void)?
    var onActivate: ((CanvasMagnetView) -> Void)?
    private(set) var isDragging = false

    /// The anchor, in the superview's coordinates.
    var center: CGPoint {
        get { CGPoint(x: frame.midX, y: frame.midY) }
        set { frame = CGRect(x: newValue.x - Constants.discSize / 2, y: newValue.y - Constants.discSize / 2, width: Constants.discSize, height: Constants.discSize) }
    }

    private let disc = CALayer()
    private let countLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private var dragOrigin: CGPoint = .zero
    private var frameAtDragStart: CGRect = .zero
    private var lastDragPoint: CGPoint = .zero

    private enum Constants {
        static let discSize: CGFloat = 72
        static let dragThreshold: CGFloat = 3
        static let nameWidth: CGFloat = 220
    }

    init(magnet: CanvasMagnet) {
        self.magnet = magnet
        super.init(frame: .zero)
        wantsLayer = true
        center = magnet.anchor

        disc.cornerRadius = Constants.discSize / 2
        disc.shadowOpacity = 0.25
        disc.shadowRadius = 10
        disc.shadowOffset = CGSize(width: 0, height: -4)
        layer?.addSublayer(disc)

        countLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        countLabel.textColor = .white
        countLabel.alignment = .center
        addSubview(countLabel)

        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        apply()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func apply() {
        disc.backgroundColor = magnet.color.cgColor
        countLabel.stringValue = "\(magnet.memberTabIDs.count)"
        nameLabel.stringValue = magnet.name
        nameLabel.textColor = magnet.color
    }

    override func updateLayer() {
        apply()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.frame = bounds
        CATransaction.commit()
        countLabel.frame = bounds.insetBy(dx: 0, dy: (bounds.height - 30) / 2)
        // Below the disc: the superview is flipped, this view is not.
        nameLabel.frame = CGRect(x: (bounds.width - Constants.nameWidth) / 2, y: -26, width: Constants.nameWidth, height: 20)
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

    override func mouseUp(with event: NSEvent) {
        guard isDragging else {
            if event.clickCount == 2 {
                onActivate?(self)
            }
            return
        }
        isDragging = false
        let delta = CGPoint(x: frame.minX - frameAtDragStart.minX, y: frame.minY - frameAtDragStart.minY)
        onDragEnd?(self, delta)
    }
}
