import AppKit

/// The document view: the desk, with zones beneath the tiles and magnets beside them.
///
/// Planes stack bottom to top: desk surface, zones, tiles, magnets, then an overlay
/// for the lasso and the selection outline. A tile is always grabbed before the zone
/// under it, and the empty part of a zone drags the zone. Dragging on the bare desk
/// draws a lasso; a plain click on it leaves the canvas.
final class TabCanvasBoardView: NSView {
    var onActivate: ((Tab, CGRect) -> Void)?
    var onDismiss: (() -> Void)?
    var onMove: ((Tab.ID, CGRect) -> Void)?
    var onTileDropped: ((Tab.ID) -> Void)?
    var onTileFellOffDesk: ((Tab.ID) -> Void)?
    var onZoneMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetActivated: ((UUID) -> Void)?
    var onLasso: ((Set<Tab.ID>) -> Void)?
    var onClearSelection: (() -> Void)?
    var isInteractionEnabled = true

    private let deskSize: CGSize
    private let deskLayer = CALayer()
    private let zonePlane = CanvasPlaneView()
    private let tilePlane = CanvasPlaneView()
    private let magnetPlane = CanvasPlaneView()
    private let overlayPlane = CanvasPlaneView()
    private let lassoLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()

    private var tiles: [Tab.ID: CanvasTileView] = [:]
    private var zoneViews: [UUID: CanvasZoneView] = [:]
    private var magnetViews: [UUID: CanvasMagnetView] = [:]
    private var hasSelection = false

    private var lassoPoints: [CGPoint] = []
    private var isLassoing = false
    private lazy var motion = CanvasMotion(host: self)

    private enum Constants {
        static let deskCornerRadius: CGFloat = 40
        static let lassoThreshold: CGFloat = 4
        static let lassoDash: [NSNumber] = [8, 6]
        static let selectionInset: CGFloat = 12
        static let selectionCornerRadius: CGFloat = 18
        static let antsPeriod: CFTimeInterval = 0.6
        /// Below this speed a released tile just settles where it is.
        static let flingSpeed: CGFloat = 500
        static let fallDuration: TimeInterval = 0.25
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(deskSize: CGSize) {
        self.deskSize = deskSize
        super.init(frame: CGRect(origin: .zero, size: deskSize))
        wantsLayer = true

        deskLayer.cornerRadius = Constants.deskCornerRadius
        deskLayer.borderWidth = 1
        layer?.addSublayer(deskLayer)

        for plane in [zonePlane, tilePlane, magnetPlane, overlayPlane] {
            plane.frame = bounds
            plane.autoresizingMask = [.width, .height]
            addSubview(plane)
        }
        overlayPlane.wantsLayer = true
        overlayPlane.layer?.addSublayer(selectionLayer)
        overlayPlane.layer?.addSublayer(lassoLayer)

        for shape in [lassoLayer, selectionLayer] {
            shape.fillColor = nil
            shape.lineWidth = 2
            shape.lineDashPattern = Constants.lassoDash
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.isHidden = true
        }
        lassoLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
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
        deskLayer.frame = bounds
        CATransaction.commit()
    }

    override func updateLayer() {
        applyColors()
    }

    private func applyColors() {
        deskLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        deskLayer.borderColor = NSColor.separatorColor.cgColor
        lassoLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
    }

    // MARK: - Content

    func reload(_ content: CanvasBoardContent) {
        reloadTiles(content)
        reloadZones(content.zones)
        reloadMagnets(content.magnets)
        reloadSelection(content)
    }

    private func reloadTiles(_ content: CanvasBoardContent) {
        let ids = Set(content.tabs.map(\.id))
        for (id, tile) in tiles where !ids.contains(id) {
            motion.stop(tile)
            tile.removeFromSuperview()
            tiles[id] = nil
        }
        for tab in content.tabs {
            let frame = content.frames[tab.id] ?? CGRect(origin: .zero, size: content.tileSize)
            let tile = tiles[tab.id] ?? makeTile(for: tab)
            tile.tab = tab
            tile.snapshot = content.snapshots[tab.id]
            tile.isSelected = content.selectedTabIDs.contains(tab.id)
            if !tile.isDragging, !motion.isMoving(tile), tile.frame != frame {
                tile.frame = frame
            }
        }
    }

    private func reloadZones(_ zones: [CanvasZone]) {
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
                zonePlane.addSubview(view)
            }
        }
    }

    private func reloadMagnets(_ magnets: [CanvasMagnet]) {
        let ids = Set(magnets.map(\.id))
        for (id, view) in magnetViews where !ids.contains(id) {
            view.removeFromSuperview()
            magnetViews[id] = nil
        }
        for magnet in magnets {
            let view = magnetViews[magnet.id] ?? makeMagnetView(for: magnet)
            view.magnet = magnet
            if !view.isDragging {
                view.center = magnet.anchor
            }
        }
    }

    private func reloadSelection(_ content: CanvasBoardContent) {
        hasSelection = !content.selectedTabIDs.isEmpty
        let frames = content.selectedTabIDs.compactMap { tiles[$0]?.frame }
        guard let first = frames.first else {
            selectionLayer.isHidden = true
            selectionLayer.removeAllAnimations()
            return
        }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
            .insetBy(dx: -Constants.selectionInset, dy: -Constants.selectionInset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.path = CGPath(roundedRect: union, cornerWidth: Constants.selectionCornerRadius, cornerHeight: Constants.selectionCornerRadius, transform: nil)
        selectionLayer.isHidden = false
        CATransaction.commit()
        if selectionLayer.animation(forKey: "ants") == nil {
            let ants = CABasicAnimation(keyPath: "lineDashPhase")
            ants.fromValue = 0
            ants.toValue = Constants.lassoDash.reduce(0) { $0 + $1.doubleValue }
            ants.duration = Constants.antsPeriod
            ants.repeatCount = .infinity
            selectionLayer.add(ants, forKey: "ants")
        }
    }

    // MARK: - Factories

    private func makeTile(for tab: Tab) -> CanvasTileView {
        let tile = CanvasTileView(tab: tab)
        tile.onClick = { [weak self] tile in
            guard let self, isInteractionEnabled else { return }
            onActivate?(tile.tab, tile.frame)
        }
        tile.onRelease = { [weak self] tile, velocity in
            guard let self else { return }
            if hypot(velocity.x, velocity.y) >= Constants.flingSpeed {
                motion.launch(tile, velocity: velocity)
            } else {
                settle(tile)
            }
        }
        tilePlane.addSubview(tile)
        tiles[tab.id] = tile
        return tile
    }

    private func makeZoneView(for zone: CanvasZone) -> CanvasZoneView {
        let view = CanvasZoneView(zone: zone)
        view.onDrag = { [weak self] view, delta in
            // Members follow live; the model is told once, on drop.
            self?.shiftTiles(view.zone.memberTabIDs, by: delta)
        }
        view.onDragEnd = { [weak self] view, delta in
            self?.onZoneMoved?(view.zone.id, delta)
        }
        zonePlane.addSubview(view)
        zoneViews[zone.id] = view
        return view
    }

    private func makeMagnetView(for magnet: CanvasMagnet) -> CanvasMagnetView {
        let view = CanvasMagnetView(magnet: magnet)
        view.onDrag = { [weak self] view, delta in
            self?.shiftTiles(view.magnet.memberTabIDs, by: delta)
        }
        view.onDragEnd = { [weak self] view, delta in
            self?.onMagnetMoved?(view.magnet.id, delta)
        }
        view.onActivate = { [weak self] view in
            self?.onMagnetActivated?(view.magnet.id)
        }
        magnetPlane.addSubview(view)
        magnetViews[magnet.id] = view
        return view
    }

    private func shiftTiles(_ tabIDs: [Tab.ID], by delta: CGPoint) {
        for tabID in tabIDs {
            if let tile = tiles[tabID] {
                tile.frame = tile.frame.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
    }

    // MARK: - Settling and Falling

    /// A released tile either lands on the desk or, past its edge, falls off.
    fileprivate func settle(_ tile: CanvasTileView) {
        let center = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
        if bounds.contains(center) {
            tile.frame = tile.frame.integral
            onMove?(tile.tab.id, tile.frame)
            onTileDropped?(tile.tab.id)
        } else {
            fall(tile)
        }
    }

    private func fall(_ tile: CanvasTileView) {
        let tabID = tile.tab.id
        tiles[tabID] = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.fallDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            tile.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                tile.removeFromSuperview()
            }
        })
        onTileFellOffDesk?(tabID)
    }

    // MARK: - Lasso

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        lassoPoints = [convert(event.locationInWindow, from: nil)]
        isLassoing = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled, let start = lassoPoints.first else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !isLassoing {
            guard hypot(point.x - start.x, point.y - start.y) >= Constants.lassoThreshold else { return }
            isLassoing = true
            lassoLayer.isHidden = false
        }
        lassoPoints.append(point)
        let path = CGMutablePath()
        path.addLines(between: lassoPoints)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lassoLayer.path = path
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        defer {
            lassoPoints = []
            isLassoing = false
            lassoLayer.isHidden = true
        }
        guard isLassoing, lassoPoints.count > 2 else {
            if hasSelection {
                onClearSelection?()
            } else if event.clickCount == 1 {
                onDismiss?()
            }
            return
        }
        let path = CGMutablePath()
        path.addLines(between: lassoPoints)
        path.closeSubpath()
        let caught = tiles.values
            .filter { path.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .map(\.tab.id)
        if caught.isEmpty {
            onClearSelection?()
        } else {
            onLasso?(Set(caught))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            if hasSelection {
                onClearSelection?()
            } else {
                onDismiss?()
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Plane

/// A transparent, flipped layer of the board; clicks on its empty parts fall through.
private final class CanvasPlaneView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

// MARK: - Motion

/// Moves flung tiles on a display link with friction, until they stop or leave the desk.
///
/// This is the seed of the canvas physics: velocity, damping, and the desk edge.
/// Collisions, stacking, and magnet attraction forces belong here too.
private final class CanvasMotion {
    private unowned let host: TabCanvasBoardView
    private var moving: [ObjectIdentifier: (tile: CanvasTileView, velocity: CGPoint)] = [:]
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0

    private enum Constants {
        /// Velocity decay per second: v · e^(−damping · dt).
        static let damping: CGFloat = 4.5
        /// Below this speed the tile settles.
        static let restSpeed: CGFloat = 40
    }

    init(host: TabCanvasBoardView) {
        self.host = host
    }

    func launch(_ tile: CanvasTileView, velocity: CGPoint) {
        moving[ObjectIdentifier(tile)] = (tile, velocity)
        startIfNeeded()
    }

    func stop(_ tile: CanvasTileView) {
        moving[ObjectIdentifier(tile)] = nil
    }

    func isMoving(_ tile: CanvasTileView) -> Bool {
        moving[ObjectIdentifier(tile)] != nil
    }

    private func startIfNeeded() {
        guard displayLink == nil else { return }
        lastTime = CACurrentMediaTime()
        let link = host.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc
    private func step() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTime, 1.0 / 30))
        lastTime = now

        for (key, entry) in moving {
            let tile = entry.tile
            var velocity = entry.velocity
            tile.frame = tile.frame.offsetBy(dx: velocity.x * dt, dy: velocity.y * dt)
            let decay = exp(-Constants.damping * dt)
            velocity = CGPoint(x: velocity.x * decay, y: velocity.y * decay)

            let center = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
            let offDesk = !host.bounds.contains(center)
            if offDesk || hypot(velocity.x, velocity.y) < Constants.restSpeed {
                moving[key] = nil
                host.settle(tile)
            } else {
                moving[key] = (tile, velocity)
            }
        }

        if moving.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}
