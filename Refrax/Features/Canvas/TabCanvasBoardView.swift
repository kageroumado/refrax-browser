import AppKit

/// The document view: the desk, with zones beneath the tiles and magnets beside them.
///
/// Tiles are bodies in a ``CanvasPhysics`` world stepped on the display link while
/// anything moves: dragged tiles push the others, flung ones slide and collide, and
/// released tiles remain within the desk boundary.
///
/// Planes stack bottom to top: desk surface, zones, tiles, magnets, then an overlay
/// for the lasso and the selection outline. A tile is always grabbed before the zone
/// under it, and the empty part of a zone drags the zone. Dragging the bare desk moves the
/// camera, the way a map does, and ⇧-dragging draws a lasso; a plain click on it leaves
/// the canvas.
final class TabCanvasBoardView: NSView {
    var onActivate: ((Tab, CGRect) -> Void)?
    var onDismiss: (() -> Void)?
    /// Tiles that came to rest somewhere new, by tab.
    var onSettle: (([Tab.ID: CGRect]) -> Void)?
    var onTileDropped: ((Tab.ID) -> Void)?
    var onZoneMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetActivated: ((UUID) -> Void)?
    var onLasso: ((Set<Tab.ID>) -> Void)?
    var onClearSelection: (() -> Void)?
    var onTogglePreview: ((Tab.ID, CGRect) -> Void)?
    /// The bare desk was dragged by `delta` screen points.
    var onPanCamera: ((CGPoint) -> Void)?
    /// Keyboard focus moved to a tile that should be kept in view.
    var onRevealTile: ((CGRect) -> Void)?
    var isInteractionEnabled = true
    var impactSoundsEnabled = false {
        didSet { impactSound.isEnabled = impactSoundsEnabled }
    }

    private var deskSize: CGSize
    private let deskEdgeLayer = CAGradientLayer()
    private let deskLayer = CAGradientLayer()
    private let zonePlane = CanvasPlaneView()
    private let tilePlane = CanvasPlaneView()
    private let tileGlassContainer = CanvasGlassPlaneView()
    private let magnetPlane = CanvasPlaneView()
    private let overlayPlane = CanvasPlaneView()
    private let lassoLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()

    private var tiles: [Tab.ID: CanvasTileView] = [:]
    private var zoneViews: [UUID: CanvasZoneView] = [:]
    private var magnetViews: [UUID: CanvasMagnetView] = [:]
    private var hasSelection = false
    private var selectedTabIDs: Set<Tab.ID> = []
    private var orderedTabIDs: [Tab.ID] = []
    private(set) var navigationTabID: Tab.ID?
    private(set) var originTabID: Tab.ID?

    private var lasso: LassoSelection?
    /// The current drag on the bare desk moves the camera rather than drawing a lasso.
    private var isPanningCamera = false
    private var didDrag = false
    private var physics: CanvasPhysics
    private let impactSound = CanvasImpactSound()
    private var displayLink: CADisplayLink?
    private var lastStepTime: CFTimeInterval = 0
    private var lastDragTimes: [Tab.ID: CFTimeInterval] = [:]
    private var scriptedDrag: ScriptedDrag?
    private enum Constants {
        static let deskCornerRadius: CGFloat = 40
        static let deskThickness: CGFloat = 10
        static let lassoDash = LassoSelection.dash.map { NSNumber(value: Double($0)) }
        static let selectionInset: CGFloat = 12
        static let selectionCornerRadius: CGFloat = 18
        static let antsPeriod: CFTimeInterval = 0.6
    }

    override var isFlipped: Bool {
        true
    }
    override var acceptsFirstResponder: Bool {
        true
    }

    init(deskSize: CGSize) {
        self.deskSize = deskSize
        self.physics = CanvasPhysics(desk: CGRect(origin: .zero, size: deskSize))
        super.init(frame: CGRect(origin: .zero, size: deskSize))
        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false

        deskEdgeLayer.cornerRadius = Constants.deskCornerRadius
        deskEdgeLayer.shadowColor = NSColor.black.cgColor
        deskEdgeLayer.shadowOpacity = 0.24
        deskEdgeLayer.shadowRadius = 28
        deskEdgeLayer.shadowOffset = CGSize(width: 0, height: 14)
        layer?.addSublayer(deskEdgeLayer)
        deskLayer.cornerRadius = Constants.deskCornerRadius
        deskLayer.borderWidth = 1
        deskLayer.startPoint = CGPoint(x: 0, y: 0)
        deskLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(deskLayer)

        tileGlassContainer.contentView = tilePlane
        tileGlassContainer.spacing = 0
        for plane in [zonePlane, tileGlassContainer, magnetPlane, overlayPlane] as [NSView] {
            plane.clipsToBounds = false
            plane.frame = bounds
            plane.autoresizingMask = [.width, .height]
            addSubview(plane)
        }
        tilePlane.frame = bounds
        tilePlane.autoresizingMask = [.width, .height]
        overlayPlane.wantsLayer = true
        overlayPlane.layer?.addSublayer(selectionLayer)
        overlayPlane.layer?.addSublayer(lassoLayer)

        for shape in [lassoLayer, selectionLayer] {
            shape.fillColor = nil
            shape.lineWidth = LassoSelection.lineWidth
            shape.lineDashPattern = Constants.lassoDash
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.isHidden = true
        }
        lassoLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(LassoSelection.fillOpacity).cgColor
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
        deskEdgeLayer.frame = bounds.offsetBy(dx: 0, dy: Constants.deskThickness)
        deskEdgeLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Constants.deskCornerRadius, cornerHeight: Constants.deskCornerRadius, transform: nil)
        deskLayer.frame = bounds
        CATransaction.commit()
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
        let base = NSColor.windowBackgroundColor
        deskLayer.colors = [
            (base.blended(withFraction: 0.08, of: .controlAccentColor) ?? base).cgColor,
            (base.blended(withFraction: 0.04, of: .labelColor) ?? base).cgColor,
        ]
        deskEdgeLayer.colors = [
            (base.blended(withFraction: 0.18, of: .labelColor) ?? base).cgColor,
            (base.blended(withFraction: 0.28, of: .labelColor) ?? base).cgColor,
        ]
        deskLayer.borderColor = NSColor.separatorColor.cgColor
        lassoLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
    }

    // MARK: - Content

    func reload(_ content: CanvasBoardContent) {
        orderedTabIDs = content.tabs.map(\.id)
        originTabID = content.focusedTabID
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
        if navigationTabID.flatMap({ tiles[$0] }) == nil {
            target(originTabID.flatMap { tiles[$0]?.tab.id } ?? orderedTabIDs.first, showingIndicator: false)
        }
    }

    private func reloadTiles(_ content: CanvasBoardContent) {
        let ids = Set(content.tabs.map(\.id))
        for (id, tile) in tiles where !ids.contains(id) {
            physics.remove(id)
            lastDragTimes[id] = nil
            tile.removeFromSuperview()
            tiles[id] = nil
        }
        for tab in content.tabs {
            let frame = content.frames[tab.id] ?? CGRect(origin: .zero, size: content.tileSize)
            let tile = tiles[tab.id] ?? makeTile(for: tab)
            tile.tab = tab
            tile.placement = content.placements[tab.id] ?? .initial(index: 0, shape: tab.boardIsCompact ? .tab : .live)
            tile.snapshot = content.snapshots[tab.id]
            tile.isSelected = content.selectedTabIDs.contains(tab.id)
            // While the simulation moves a tile, it owns the position.
            if !tile.isDragging, !physics.isActive(tab.id) {
                tile.frame = frame
                physics.place(tab.id, frame: frame, awake: false)
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
        selectedTabIDs = content.selectedTabIDs
        hasSelection = !content.selectedTabIDs.isEmpty
        let frames = content.selectedTabIDs.compactMap { tiles[$0]?.frame }.map(CanvasPhysics.collisionBox)
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
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            selectionLayer.removeAllAnimations()
        } else if selectionLayer.animation(forKey: "ants") == nil {
            let ants = CABasicAnimation(keyPath: "lineDashPhase")
            ants.fromValue = 0
            ants.toValue = Constants.lassoDash.reduce(0) { $0 + $1.doubleValue }
            ants.duration = Constants.antsPeriod
            ants.repeatCount = .infinity
            selectionLayer.add(ants, forKey: "ants")
        }
    }

    /// The tile under `point`, or else the one whose edge is nearest to it.
    func tile(near point: CGPoint) -> (tab: Tab, frame: CGRect)? {
        CanvasNavigation.nearest(to: point, in: navigationTiles).flatMap { tile(withID: $0) }
    }

    func tile(withID id: Tab.ID) -> (tab: Tab, frame: CGRect)? {
        tiles[id].map { ($0.tab, $0.frame) }
    }

    func previewFrame(for id: Tab.ID) -> CGRect? {
        guard let tile = tiles[id] else { return nil }
        return tile.previewFrame
    }

    func revealPreview(of id: Tab.ID, progress: CGFloat) {
        tiles[id]?.revealPreview(progress)
    }

    private var navigationTiles: [CanvasNavigation.Tile] {
        orderedTabIDs.compactMap { id in
            tiles[id].map { CanvasNavigation.Tile(id: id, frame: $0.frame) }
        }
    }

    /// Marks the destination under the camera, with a stable boundary between neighbors.
    func target(near point: CGPoint, hysteresis: CGFloat) {
        target(CanvasNavigation.nearest(to: point, in: navigationTiles, retaining: navigationTabID, hysteresis: hysteresis))
    }

    func target(_ id: Tab.ID?, showingIndicator: Bool = true) {
        if id != navigationTabID {
            if let navigationTabID {
                tiles[navigationTabID]?.isTargeted = false
            }
            navigationTabID = id
        }
        if let id, let tile = tiles[id], tile.isTargeted != showingIndicator {
            tile.isTargeted = showingIndicator
            if showingIndicator {
                tilePlane.addSubview(tile)
            }
        }
    }

    func moveFocus(_ direction: CanvasNavigation.Direction) {
        guard let current = navigationTabID ?? originTabID ?? orderedTabIDs.first else { return }
        let next = CanvasNavigation.neighbor(from: current, toward: direction, in: navigationTiles) ?? current
        target(next)
        if let tile = tiles[next] {
            onRevealTile?(tile.frame)
            NSAccessibility.post(element: tile, notification: .focusedUIElementChanged)
        }
    }

    private func toggleSelection(_ id: Tab.ID) {
        if !selectedTabIDs.insert(id).inserted {
            selectedTabIDs.remove(id)
        }
        onLasso?(selectedTabIDs)
    }

    // MARK: - Factories

    private func makeTile(for tab: Tab) -> CanvasTileView {
        let tile = CanvasTileView(tab: tab)
        tile.onClick = { [weak self] tile in
            guard let self, isInteractionEnabled else { return }
            onActivate?(tile.tab, tile.frame)
        }
        tile.onSelect = { [weak self] tile in
            guard let self, isInteractionEnabled else { return }
            window?.makeFirstResponder(self)
            target(tile.tab.id)
            toggleSelection(tile.tab.id)
        }
        tile.onDrag = { [weak self] tile in
            self?.hold(tile.tab.id, at: tile.frame)
        }
        tile.onRelease = { [weak self] tile, velocity in
            self?.release([tile.tab.id], velocity: velocity, dropped: true)
        }
        tile.onTogglePreview = { [weak self] tile in
            guard let self, isInteractionEnabled else { return }
            physics.remove(tile.tab.id)
            onTogglePreview?(tile.tab.id, tile.frame)
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
        if lastDragTimes[tabID] == nil, let tile = tiles[tabID] {
            tile.isLifted = true
            tilePlane.addSubview(tile)
        }
        let now = CACurrentMediaTime()
        let elapsed = lastDragTimes[tabID].map { CGFloat(now - $0) } ?? 0
        lastDragTimes[tabID] = now
        physics.drag(tabID, to: frame, elapsed: elapsed)
        startSimulationIfNeeded()
    }

    private func release(_ tabIDs: [Tab.ID], velocity: CGPoint, dropped: Bool) {
        for tabID in tabIDs {
            tiles[tabID]?.isLifted = false
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
            if let tile = tiles[tabID] {
                if !tile.isDragging, tile.frame != body.frame {
                    tile.frame = body.frame
                }
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
            case let .impact(impact):
                if isInteractionEnabled {
                    tiles[impact.first]?.respondToImpact(impact, direction: -1)
                    tiles[impact.second]?.respondToImpact(impact, direction: 1)
                    let visible = visibleRect
                    let pan = (impact.point.x - visible.midX) / max(1, visible.width / 2)
                    if visible.contains(impact.point) {
                        impactSound.play(speed: impact.speed, pan: pan, at: now)
                    }
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

    // MARK: - Lasso

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        lasso = LassoSelection(at: convert(event.locationInWindow, from: nil))
        didDrag = false
        isPanningCamera = !event.modifierFlags.contains(.shift)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        if isPanningCamera {
            didDrag = didDrag || hypot(event.deltaX, event.deltaY) > 0
            onPanCamera?(CGPoint(x: event.deltaX, y: event.deltaY))
            return
        }
        guard var lasso, lasso.extend(to: convert(event.locationInWindow, from: nil)) else { return }
        self.lasso = lasso
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lassoLayer.isHidden = false
        lassoLayer.path = lasso.path
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        defer {
            lasso = nil
            isPanningCamera = false
            lassoLayer.isHidden = true
        }
        if isPanningCamera, didDrag {
            return
        }
        guard let lasso, lasso.canCatch else {
            if hasSelection {
                onClearSelection?()
            } else if event.clickCount == 1 {
                onDismiss?()
            }
            return
        }
        let caught = lasso.caught(tiles.values.map { (id: $0.tab.id, frame: $0.frame) })
        if caught.isEmpty {
            onClearSelection?()
        } else {
            onLasso?(caught)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty, let direction = CanvasNavigation.Direction(rawValue: event.keyCode) {
            moveFocus(direction)
        } else if modifiers.isEmpty, event.keyCode == 36 || event.keyCode == 76,
                  let id = navigationTabID, let tile = tiles[id] {
            onActivate?(tile.tab, tile.frame)
        } else if modifiers.isEmpty, event.keyCode == 49, let id = navigationTabID {
            toggleSelection(id)
        } else if event.keyCode == 53 {
            if hasSelection {
                onClearSelection?()
            } else {
                onDismiss?()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override func selectAll(_: Any?) {
        guard isInteractionEnabled else { return }
        onLasso?(Set(orderedTabIDs))
    }
}

// MARK: - Plane

/// A transparent, flipped layer of the board; clicks on its empty parts fall through.
private final class CanvasPlaneView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// Batches the tiles' glass surfaces and lets empty-desk input reach the board.
private final class CanvasGlassPlaneView: NSGlassEffectContainerView {
    override var isFlipped: Bool {
        true
    }

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
