import AppKit

/// The document view: the desk, with zones beneath the tiles and magnets beside them.
///
/// Tiles are bodies in a ``CanvasPhysics`` world stepped on the display link while
/// anything moves: dragged tiles push the others, flung ones slide and collide, and
/// a tile whose center leaves the desk falls off.
///
/// Planes stack bottom to top: desk surface, zones, tiles, magnets, then an overlay
/// for the lasso and the selection outline. A tile is always grabbed before the zone
/// under it, and the empty part of a zone drags the zone. Dragging on the bare desk
/// draws a lasso; a plain click on it leaves the canvas.
final class TabCanvasBoardView: NSView {
    var onActivate: ((Tab, CGRect) -> Void)?
    var onDismiss: (() -> Void)?
    /// Tiles that came to rest somewhere new, by tab.
    var onSettle: (([Tab.ID: CGRect]) -> Void)?
    var onTileDropped: ((Tab.ID) -> Void)?
    var onTileFellOffDesk: ((Tab.ID) -> Void)?
    var onZoneMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetActivated: ((UUID) -> Void)?
    var onLasso: ((Set<Tab.ID>) -> Void)?
    var onClearSelection: (() -> Void)?
    var isInteractionEnabled = true

    private var deskSize: CGSize
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
    private var physics: CanvasPhysics
    private var displayLink: CADisplayLink?
    private var lastStepTime: CFTimeInterval = 0
    private var lastDragTimes: [Tab.ID: CFTimeInterval] = [:]
    private var scriptedDrag: ScriptedDrag?

    private enum Constants {
        static let deskCornerRadius: CGFloat = 40
        static let lassoThreshold: CGFloat = 4
        static let lassoDash: [NSNumber] = [8, 6]
        static let selectionInset: CGFloat = 12
        static let selectionCornerRadius: CGFloat = 18
        static let antsPeriod: CFTimeInterval = 0.6
        static let fallDuration: TimeInterval = 0.25
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(deskSize: CGSize) {
        self.deskSize = deskSize
        physics = CanvasPhysics(desk: CGRect(origin: .zero, size: deskSize))
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
        if content.deskSize != deskSize {
            deskSize = content.deskSize
            physics.desk = CGRect(origin: .zero, size: deskSize)
            setFrameSize(deskSize)
            needsLayout = true
        }
        reloadTiles(content)
        reloadZones(content.zones)
        reloadMagnets(content.magnets)
        reloadSelection(content)
    }

    private func reloadTiles(_ content: CanvasBoardContent) {
        let ids = Set(content.tabs.map(\.id))
        for (id, tile) in tiles where !ids.contains(id) {
            physics.remove(id)
            tile.removeFromSuperview()
            tiles[id] = nil
        }
        for tab in content.tabs {
            let frame = content.frames[tab.id] ?? CGRect(origin: .zero, size: content.tileSize)
            let tile = tiles[tab.id] ?? makeTile(for: tab)
            tile.tab = tab
            tile.snapshot = content.snapshots[tab.id]
            tile.isSelected = content.selectedTabIDs.contains(tab.id)
            // While the simulation moves a tile, it owns the position.
            if !tile.isDragging, !physics.isActive(tab.id) {
                tile.frame = frame
                physics.place(tab.id, frame: frame)
            }
        }
        startSimulationIfNeeded()
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
        tile.onDrag = { [weak self] tile in
            self?.hold(tile.tab.id, at: tile.frame)
        }
        tile.onRelease = { [weak self] tile, velocity in
            self?.release([tile.tab.id], velocity: velocity, dropped: true)
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
            self?.release(view.zone.memberTabIDs, velocity: .zero, dropped: false)
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
            self?.release(view.magnet.memberTabIDs, velocity: .zero, dropped: false)
            self?.onMagnetMoved?(view.magnet.id, delta)
        }
        view.onActivate = { [weak self] view in
            self?.onMagnetActivated?(view.magnet.id)
        }
        magnetPlane.addSubview(view)
        magnetViews[magnet.id] = view
        return view
    }

    /// Carries a zone's or magnet's members: they are held, so they push what they meet.
    private func shiftTiles(_ tabIDs: [Tab.ID], by delta: CGPoint) {
        for tabID in tabIDs {
            if let tile = tiles[tabID] {
                tile.frame = tile.frame.offsetBy(dx: delta.x, dy: delta.y)
                hold(tabID, at: tile.frame)
            }
        }
    }

    // MARK: - Simulation

    private func hold(_ tabID: Tab.ID, at frame: CGRect) {
        let now = CACurrentMediaTime()
        let elapsed = lastDragTimes[tabID].map { CGFloat(now - $0) } ?? 0
        lastDragTimes[tabID] = now
        physics.drag(tabID, to: frame, elapsed: elapsed)
        startSimulationIfNeeded()
    }

    private func release(_ tabIDs: [Tab.ID], velocity: CGPoint, dropped: Bool) {
        for tabID in tabIDs {
            lastDragTimes[tabID] = nil
            physics.release(tabID, velocity: velocity, dropped: dropped)
        }
        startSimulationIfNeeded()
    }

    /// Tiles are moving, or a scripted drag is under way.
    var isSimulating: Bool {
        displayLink != nil
    }

    /// Drags a tile along an eased path, holding it each frame as the pointer would.
    /// A plain drag eases in and out and lets go at rest; a fling only eases in and
    /// lets go at full speed.
    func drag(_ tabID: Tab.ID, to origin: CGPoint, duration: TimeInterval, fling: Bool) async {
        guard let tile = tiles[tabID] else { return }
        scriptedDrag?.finish()
        await withCheckedContinuation { continuation in
            scriptedDrag = ScriptedDrag(
                tabID: tabID,
                start: tile.frame,
                end: CGPoint(x: origin.x, y: origin.y),
                startTime: CACurrentMediaTime(),
                duration: max(duration, 0.05),
                fling: fling,
                continuation: continuation,
            )
            hold(tabID, at: tile.frame)
        }
    }

    /// Moves the scripted tile to where its path is at `now`, and lets go at the end.
    private func advanceScriptedDrag(at now: CFTimeInterval) {
        guard let drag = scriptedDrag else { return }
        guard let tile = tiles[drag.tabID] else {
            scriptedDrag = nil
            drag.finish()
            return
        }
        let progress = min(1, (now - drag.startTime) / drag.duration)
        tile.frame = drag.frame(at: progress)
        hold(drag.tabID, at: tile.frame)
        guard progress >= 1 else { return }

        scriptedDrag = nil
        let velocity = drag.fling ? drag.endVelocity : .zero
        release([drag.tabID], velocity: velocity, dropped: true)
        drag.finish()
    }

    private func startSimulationIfNeeded() {
        guard displayLink == nil, physics.isRunning else { return }
        lastStepTime = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(stepSimulation))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc
    private func stepSimulation() {
        let now = CACurrentMediaTime()
        advanceScriptedDrag(at: now)
        let events = physics.step(CGFloat(now - lastStepTime))
        lastStepTime = now

        for (tabID, body) in physics.bodies {
            if let tile = tiles[tabID], !tile.isDragging, tile.frame != body.frame {
                tile.frame = body.frame
            }
        }

        var settled: [Tab.ID: CGRect] = [:]
        var dropped: [Tab.ID] = []
        for event in events {
            switch event {
            case let .settled(tabID, frame, wasDropped):
                settled[tabID] = frame
                if wasDropped {
                    dropped.append(tabID)
                }
            case let .fell(tabID):
                if let tile = tiles[tabID] {
                    fall(tile)
                }
            }
        }
        if !settled.isEmpty {
            onSettle?(settled)
        }
        for tabID in dropped {
            onTileDropped?(tabID)
        }

        if !physics.isRunning, scriptedDrag == nil {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func fall(_ tile: CanvasTileView) {
        let tabID = tile.tab.id
        tiles[tabID] = nil
        lastDragTimes[tabID] = nil
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

// MARK: - Scripted Drag

/// A drag performed on the pointer's behalf, for agents and tests.
private final class ScriptedDrag {
    let tabID: Tab.ID
    let start: CGRect
    let end: CGPoint
    let startTime: CFTimeInterval
    let duration: TimeInterval
    let fling: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(tabID: Tab.ID, start: CGRect, end: CGPoint, startTime: CFTimeInterval, duration: TimeInterval, fling: Bool, continuation: CheckedContinuation<Void, Never>) {
        self.tabID = tabID
        self.start = start
        self.end = end
        self.startTime = startTime
        self.duration = duration
        self.fling = fling
        self.continuation = continuation
    }

    /// The tile's frame at `progress` along the path, from 0 to 1.
    func frame(at progress: Double) -> CGRect {
        let eased = CGFloat(fling ? progress * progress : progress * progress * (3 - 2 * progress))
        return CGRect(
            x: start.minX + (end.x - start.minX) * eased,
            y: start.minY + (end.y - start.minY) * eased,
            width: start.width,
            height: start.height,
        )
    }

    /// Speed at the end of a fling's ease-in path: the derivative of t² is 2t, so 2 × distance / duration.
    var endVelocity: CGPoint {
        CGPoint(
            x: 2 * (end.x - start.minX) / duration,
            y: 2 * (end.y - start.minY) / duration,
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
