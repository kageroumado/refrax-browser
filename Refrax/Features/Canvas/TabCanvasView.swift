import AppKit
import SwiftUI

/// The tab canvas overlay: covers the content area while `TabCanvasManager.isActive`.
struct TabCanvasView: View {
    @Environment(TabCanvasManager.self) private var manager

    var body: some View {
        TabCanvasBoard(
            tabs: manager.tabs,
            tileFrames: manager.tileFrames,
            snapshots: manager.snapshots,
            zones: manager.zones,
            tileSize: manager.tileSize,
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Board Representable

/// Hosts the zoomable AppKit board.
private struct TabCanvasBoard: NSViewRepresentable {
    @Environment(TabCanvasManager.self) private var manager

    let tabs: [Tab]
    let tileFrames: [Tab.ID: CGRect]
    let snapshots: [Tab.ID: NSImage]
    let zones: [CanvasZone]
    let tileSize: CGSize

    func makeNSView(context _: Context) -> TabCanvasScrollView {
        let view = TabCanvasScrollView()
        view.onActivate = { [weak manager] tab in manager?.dismiss(activating: tab) }
        view.onDismiss = { [weak manager] in manager?.dismiss(activating: nil) }
        view.onMove = { [weak manager] tabID, frame in manager?.moveTile(tabID, to: frame) }
        view.onTileDropped = { [weak manager] tabID in manager?.finishTileDrag(tabID) }
        view.onZoneMoved = { [weak manager] groupID, delta in manager?.moveZone(groupID, by: delta) }
        view.reload(tabs: tabs, frames: tileFrames, snapshots: snapshots, zones: zones, tileSize: tileSize)
        view.zoomOutFromFocusedTile(manager.focusedTileFrame, toFit: manager.tilesBounds)
        return view
    }

    func updateNSView(_ view: TabCanvasScrollView, context _: Context) {
        view.reload(tabs: tabs, frames: tileFrames, snapshots: snapshots, zones: zones, tileSize: tileSize)
    }
}

// MARK: - Scroll View

/// A magnifiable scroll view whose document is the board.
///
/// Zoom transitions are the canvas's whole trick: opening zooms out from the tile of
/// the current tab until every tile is visible, choosing a tile zooms into it until
/// it fills the clip view, and only then does the live page take over underneath.
final class TabCanvasScrollView: NSScrollView {
    var onActivate: ((Tab) -> Void)?
    var onDismiss: (() -> Void)?
    var onMove: ((Tab.ID, CGRect) -> Void)?
    var onTileDropped: ((Tab.ID) -> Void)?
    var onZoneMoved: ((UUID, CGPoint) -> Void)?

    private let board = TabCanvasBoardView()
    private var isTransitioning = false
    private var focusedTileFrame: CGRect?
    private var zoomFlight: ZoomFlight?

    private enum Constants {
        static let zoomDuration: TimeInterval = 0.4
        static let minMagnification: CGFloat = 0.05
        static let maxMagnification: CGFloat = 4
    }

    init() {
        super.init(frame: .zero)
        drawsBackground = true
        backgroundColor = .underPageBackgroundColor
        hasHorizontalScroller = false
        hasVerticalScroller = false
        allowsMagnification = true
        minMagnification = Constants.minMagnification
        maxMagnification = Constants.maxMagnification
        documentView = board

        board.onActivate = { [weak self] tab, frame in self?.zoom(into: frame) { self?.onActivate?(tab) } }
        board.onDismiss = { [weak self] in self?.dismissZoomingIntoFocusedTile() }
        board.onMove = { [weak self] tabID, frame in self?.onMove?(tabID, frame) }
        board.onTileDropped = { [weak self] tabID in self?.onTileDropped?(tabID) }
        board.onZoneMoved = { [weak self] groupID, delta in self?.onZoneMoved?(groupID, delta) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload(tabs: [Tab], frames: [Tab.ID: CGRect], snapshots: [Tab.ID: NSImage], zones: [CanvasZone], tileSize: CGSize) {
        board.reload(tabs: tabs, frames: frames, snapshots: snapshots, zones: zones, tileSize: tileSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(board)
    }

    // MARK: - Zoom Transitions

    /// Starts with `tile` filling the clip view, then flies out until `everything` fits.
    func zoomOutFromFocusedTile(_ tile: CGRect?, toFit everything: CGRect) {
        focusedTileFrame = tile
        guard let tile else {
            setZoom(toFit: everything)
            return
        }
        // The clip view has no size until the first layout; defer the initial placement.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            setZoom(toFit: tile)
            animateZoom(toFit: everything, completion: nil)
        }
    }

    private func dismissZoomingIntoFocusedTile() {
        if let focusedTileFrame {
            zoom(into: focusedTileFrame) { [weak self] in self?.onDismiss?() }
        } else {
            onDismiss?()
        }
    }

    private func zoom(into tile: CGRect, completion: @escaping @MainActor @Sendable () -> Void) {
        guard !isTransitioning else { return }
        isTransitioning = true
        board.isInteractionEnabled = false
        animateZoom(toFit: tile) { [weak self] in
            self?.isTransitioning = false
            completion()
        }
    }

    /// The document rectangle that fills the clip view when `rect` is fitted.
    private func fittedRect(for rect: CGRect) -> CGRect {
        let clip = contentView.frame.size
        guard clip.width > 0, clip.height > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let magnification = min(clip.width / rect.width, clip.height / rect.height)
        let visible = CGSize(width: clip.width / magnification, height: clip.height / magnification)
        return CGRect(x: rect.midX - visible.width / 2, y: rect.midY - visible.height / 2, width: visible.width, height: visible.height)
    }

    /// Shows exactly `visible` (a rectangle in document coordinates) in the clip view.
    private func setVisibleRect(_ visible: CGRect) {
        let clip = contentView.frame.size
        guard clip.width > 0, visible.width > 0 else { return }
        magnification = clip.width / visible.width
        contentView.setBoundsOrigin(visible.origin)
        reflectScrolledClipView(contentView)
    }

    private func setZoom(toFit rect: CGRect) {
        setVisibleRect(fittedRect(for: rect))
    }

    /// Flies the camera from the current view to one that fits `rect`.
    ///
    /// The center travels in a straight line and the scale changes exponentially, so
    /// the target stays on a straight path toward the middle of the screen throughout.
    /// Animating magnification and origin as two separate properties zooms about the
    /// current center first and slides afterwards, which reads as two moves.
    private func animateZoom(toFit rect: CGRect, completion: (@MainActor @Sendable () -> Void)?) {
        zoomFlight?.cancel()
        let flight = ZoomFlight(from: contentView.bounds, to: fittedRect(for: rect), duration: Constants.zoomDuration)
        zoomFlight = flight
        flight.start(in: contentView, frame: { [weak self] visible in
            self?.setVisibleRect(visible)
        }, completion: { [weak self] in
            self?.zoomFlight = nil
            completion?()
        })
    }

    /// User input takes over from an in-flight zoom-out; a zoom-in is not interruptible.
    override func scrollWheel(with event: NSEvent) {
        if !isTransitioning { zoomFlight?.cancel() }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        if !isTransitioning { zoomFlight?.cancel() }
        super.magnify(with: event)
    }
}

// MARK: - Zoom Flight

/// A display-link-driven camera move between two visible rectangles.
private final class ZoomFlight {
    private let start: CGRect
    private let end: CGRect
    private let duration: TimeInterval
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var frame: ((CGRect) -> Void)?
    private var completion: (() -> Void)?

    init(from start: CGRect, to end: CGRect, duration: TimeInterval) {
        self.start = start
        self.end = end
        self.duration = duration
    }

    func start(in view: NSView, frame: @escaping (CGRect) -> Void, completion: @escaping () -> Void) {
        self.frame = frame
        self.completion = completion
        startTime = CACurrentMediaTime()
        let link = view.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        frame = nil
        completion = nil
    }

    @objc
    private func tick() {
        let elapsed = CACurrentMediaTime() - startTime
        let progress = min(1, elapsed / duration)
        frame?(rect(at: Self.easeInOut(progress)))
        if progress >= 1 {
            let done = completion
            cancel()
            done?()
        }
    }

    /// Center interpolated linearly, width exponentially, height following the aspect.
    private func rect(at t: Double) -> CGRect {
        let width = start.width * pow(end.width / start.width, t)
        let height = width * end.height / end.width
        let center = CGPoint(
            x: start.midX + (end.midX - start.midX) * t,
            y: start.midY + (end.midY - start.midY) * t,
        )
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}

// MARK: - Board

/// The document view: a flipped plane holding one zone per group and one tile per tab.
///
/// Zones sit in a layer beneath the tiles, so a tile is always grabbed before the
/// zone under it, and the empty part of a zone drags the zone.
final class TabCanvasBoardView: NSView {
    var onActivate: ((Tab, CGRect) -> Void)?
    var onDismiss: (() -> Void)?
    var onMove: ((Tab.ID, CGRect) -> Void)?
    var onTileDropped: ((Tab.ID) -> Void)?
    var onZoneMoved: ((UUID, CGPoint) -> Void)?
    var isInteractionEnabled = true

    private let zoneLayer = CanvasPlaneView()
    private let tileLayer = CanvasPlaneView()
    private var tiles: [Tab.ID: CanvasTileView] = [:]
    private var zoneViews: [UUID: CanvasZoneView] = [:]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(zoneLayer)
        addSubview(tileLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload(tabs: [Tab], frames: [Tab.ID: CGRect], snapshots: [Tab.ID: NSImage], zones: [CanvasZone], tileSize: CGSize) {
        let ids = Set(tabs.map(\.id))
        for (id, tile) in tiles where !ids.contains(id) {
            tile.removeFromSuperview()
            tiles[id] = nil
        }

        for tab in tabs {
            let frame = frames[tab.id] ?? CGRect(origin: .zero, size: tileSize)
            let tile = tiles[tab.id] ?? makeTile(for: tab)
            tile.tab = tab
            tile.snapshot = snapshots[tab.id]
            if !tile.isDragging, tile.frame != frame {
                tile.frame = frame
            }
        }

        let zoneIDs = Set(zones.map(\.id))
        for (id, view) in zoneViews where !zoneIDs.contains(id) {
            view.removeFromSuperview()
            zoneViews[id] = nil
        }
        for zone in zones {
            let view = zoneViews[zone.id] ?? makeZoneView(for: zone)
            view.zone = zone
            if !view.isDragging, view.frame != zone.frame {
                view.frame = zone.frame
            }
        }
        // Parents first, so nested zones draw on top of the zone that holds them.
        for zone in zones {
            if let view = zoneViews[zone.id] {
                zoneLayer.addSubview(view)
            }
        }

        resizeToFitContent()
    }

    private func makeTile(for tab: Tab) -> CanvasTileView {
        let tile = CanvasTileView(tab: tab)
        tile.onClick = { [weak self] tile in
            guard let self, isInteractionEnabled else { return }
            onActivate?(tile.tab, tile.frame)
        }
        tile.onDragEnd = { [weak self] tile in
            guard let self else { return }
            onMove?(tile.tab.id, tile.frame)
            onTileDropped?(tile.tab.id)
            resizeToFitContent()
        }
        tileLayer.addSubview(tile)
        tiles[tab.id] = tile
        return tile
    }

    private func makeZoneView(for zone: CanvasZone) -> CanvasZoneView {
        let view = CanvasZoneView(zone: zone)
        view.onDrag = { [weak self] view, delta in
            // Members follow live; the model is told once, on drop.
            guard let self else { return }
            for tabID in view.zone.memberTabIDs {
                tiles[tabID]?.frame = tiles[tabID]?.frame.offsetBy(dx: delta.x, dy: delta.y) ?? .zero
            }
        }
        view.onDragEnd = { [weak self] view, delta in
            guard let self else { return }
            onZoneMoved?(view.zone.id, delta)
            resizeToFitContent()
        }
        zoneLayer.addSubview(view)
        zoneViews[zone.id] = view
        return view
    }

    /// Keeps a wide margin around everything so there is always somewhere to drag to.
    private func resizeToFitContent() {
        let frames = tiles.values.map(\.frame) + zoneViews.values.map(\.frame)
        guard let first = frames.first else { return }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let margin = TabCanvasManager.Layout.boardMargin
        let needed = union.insetBy(dx: -margin, dy: -margin)

        // The board's origin stays at zero; content left or above it is pulled back in.
        let shift = CGPoint(x: min(0, needed.minX), y: min(0, needed.minY))
        if shift != .zero {
            for tile in tiles.values {
                tile.frame = tile.frame.offsetBy(dx: -shift.x, dy: -shift.y)
                onMove?(tile.tab.id, tile.frame)
            }
            for view in zoneViews.values {
                view.frame = view.frame.offsetBy(dx: -shift.x, dy: -shift.y)
            }
        }
        let size = CGSize(width: needed.maxX - shift.x, height: needed.maxY - shift.y)
        if frame.size != size {
            setFrameSize(size)
        }
        zoneLayer.frame = bounds
        tileLayer.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        if event.clickCount == 1 {
            onDismiss?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// A transparent, flipped layer of the board; clicks on its empty parts fall through.
private final class CanvasPlaneView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

// MARK: - Zone

/// A group on the board: a tinted plate with the group's name, holding its member tiles.
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

// MARK: - Tile

/// One tab on the board: its snapshot, with the title above it. Draggable.
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

    var onClick: ((CanvasTileView) -> Void)?
    var onDragEnd: ((CanvasTileView) -> Void)?
    private(set) var isDragging = false

    private let imageLayer = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let placeholderLabel = NSTextField(labelWithString: "")
    private var dragOrigin: CGPoint = .zero
    private var frameAtDragStart: CGRect = .zero

    private enum Constants {
        static let cornerRadius: CGFloat = 12
        static let titleHeight: CGFloat = 20
        static let dragThreshold: CGFloat = 3
    }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.cornerRadius = Constants.cornerRadius
        imageLayer.masksToBounds = true
        imageLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageLayer.borderWidth = 1
        imageLayer.borderColor = NSColor.separatorColor.cgColor
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
        imageLayer.borderColor = NSColor.separatorColor.cgColor
        imageLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        guard let superview else { return }
        dragOrigin = superview.convert(event.locationInWindow, from: nil)
        frameAtDragStart = frame
        isDragging = false
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
    }

    override func mouseUp(with _: NSEvent) {
        if isDragging {
            isDragging = false
            frame = frame.integral
            onDragEnd?(self)
        } else {
            onClick?(self)
        }
    }
}
