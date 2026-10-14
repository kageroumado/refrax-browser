import AppKit
import QuartzCore

/// The table as a scroll view: the window is the clip, the plane is the document, every slab
/// in reach is a view at its frame. A trackpad gesture scrolls it natively, 1:1 with momentum
/// and rubber-banding at the edges. Every other motion, a wheel notch, a key, a lens jump,
/// the overview, is a flight: a critically damped spring driven by the display link, so it
/// is smooth, interruptible, and extends when the wheel keeps turning.
///
/// Slab views exist for the visible rect plus one viewport of margin on each side and are
/// released beyond it, like a collection view's cells. A collapsed row is one band view; the
/// empty row below the table has a hint.
@MainActor
final class TableScrollView: NSScrollView {
    /// Makes the view for a slab; the controller's SwiftUI content, hosted.
    var makeSlabView: ((Tab) -> NSView)?
    /// Makes the band for a collapsed row.
    var makeBandView: ((TableLayout.Row) -> NSView)?
    /// Makes the hint shown in the empty row below the table.
    var makeEmptyRowView: (() -> NSView)?
    /// The window looked somewhere else, by hand or in flight.
    var onViewportMoved: ((CGRect, CGFloat) -> Void)?
    /// Scrolling and magnifying have stopped.
    var onRest: (() -> Void)?
    /// A slab was clicked in the overview.
    var onEnter: ((UUID) -> Void)?
    /// Escape was pressed in the overview.
    var onLeaveOverview: (() -> Void)?

    let document = TableDocumentView()

    /// Where a flight is headed, and where it is. The spring integrates its own position:
    /// the clip view rounds whatever it is given to whole points, which would swallow the
    /// last sub-point steps and leave the flight short of its target forever.
    private struct Flight {
        var origin: CGPoint
        var magnification: CGFloat
        var position: CGPoint
        var currentMagnification: CGFloat
        var velocity: CGPoint = .zero
        var magnificationVelocity: CGFloat = 0

        init(origin: CGPoint, magnification: CGFloat, position: CGPoint, currentMagnification: CGFloat) {
            self.origin = origin
            self.magnification = magnification
            self.position = position
            self.currentMagnification = currentMagnification
        }
    }

    private enum Layout {
        /// Quiet for this long after the last bounds change is rest.
        static let restQuiet: TimeInterval = 0.12
        /// The spring: critically damped, settling in about 0.45 s.
        static let stiffness: CGFloat = 220
        static let damping: CGFloat = 2 * 14.83
        static let maximumFrameInterval: CFTimeInterval = 1.0 / 30
        /// A flight this close to its target, this slow, has arrived.
        static let arrivalDistance: CGFloat = 0.5
        static let arrivalSpeed: CGFloat = 2
        static let arrivalMagnification: CGFloat = 0.0005
        /// The speed of a nudge at the table's edge, which the spring brings straight back.
        static let nudgeSpeed: CGFloat = 300
    }

    private var restTimer: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var flight: Flight?
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var lastReported: (CGRect, CGFloat) = (.zero, 1)

    /// A flight is under way.
    var isFlying: Bool {
        flight != nil
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        documentView = document
        document.scrollView = self
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .allowed
        allowsMagnification = true
        minMagnification = TableController.Layout.minimumMagnification
        maxMagnification = 1
        scrollerStyle = .overlay
        // The window's title bar is transparent over the content; the table starts at the top.
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsetsZero
        contentView.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.boundsChanged() }
        })
        for name in [NSScrollView.didEndLiveScrollNotification, NSScrollView.didEndLiveMagnifyNotification] {
            observers.append(center.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.armRest() }
            })
        }
        // Fingers on the trackpad take over from any flight.
        observers.append(center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopFlight() }
        })
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        restTimer?.invalidate()
        displayLink?.invalidate()
    }

    // MARK: - Layout

    /// The visible part of the plane, in plane points.
    var visiblePlaneRect: CGRect {
        contentView.bounds
    }

    func apply(layout: TableLayout, geometry: TableGeometry, animated: Bool = false) {
        document.apply(layout: layout, geometry: geometry, animated: animated)
        updateBand()
    }

    private func boundsChanged() {
        updateBand()
        let report = (visiblePlaneRect, magnification)
        guard report.0 != lastReported.0 || report.1 != lastReported.1 else { return }
        lastReported = report
        onViewportMoved?(report.0, report.1)
        armRest()
    }

    private func updateBand() {
        let band = visiblePlaneRect.insetBy(dx: -visiblePlaneRect.width, dy: -visiblePlaneRect.height)
        document.mount(in: band)
    }

    private func armRest() {
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: Layout.restQuiet, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isFlying else { return }
                self.onRest?()
            }
        }
    }

    // MARK: - Flights

    /// The farthest origin the viewport may rest at for `magnification`.
    private func clamp(_ origin: CGPoint, at magnification: CGFloat) -> CGPoint {
        let visible = CGSize(width: bounds.width / magnification, height: bounds.height / magnification)
        let size = document.frame.size
        return CGPoint(
            x: min(max(origin.x, 0), max(0, size.width - visible.width)),
            y: min(max(origin.y, 0), max(0, size.height - visible.height)),
        )
    }

    /// Flies to `origin` at `magnification`, or jumps there.
    func scroll(to origin: CGPoint, magnification: CGFloat, animated: Bool) {
        let target = clamp(CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), at: magnification)
        guard animated else {
            stopFlight()
            if self.magnification != magnification {
                self.magnification = magnification
            }
            contentView.setBoundsOrigin(target)
            reflectScrolledClipView(contentView)
            armRest()
            return
        }
        var flight = flight ?? restingFlight()
        flight.origin = target
        flight.magnification = magnification
        startFlight(flight)
    }

    /// Extends the flight's target by `delta` plane points: a wheel notch. A table at rest
    /// starts a flight from where it is.
    func moveTarget(by delta: CGPoint) {
        var flight = flight ?? restingFlight()
        flight.origin = clamp(CGPoint(x: flight.origin.x + delta.x, y: flight.origin.y + delta.y), at: flight.magnification)
        startFlight(flight)
    }

    /// A short push against the table's edge, for a step with nowhere to go.
    func nudge(_ direction: TableDirection) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, flight == nil else { return }
        var flight = restingFlight()
        switch direction {
        case .left: flight.velocity.x = -Layout.nudgeSpeed
        case .right: flight.velocity.x = Layout.nudgeSpeed
        case .up: flight.velocity.y = -Layout.nudgeSpeed
        case .down: flight.velocity.y = Layout.nudgeSpeed
        }
        startFlight(flight)
    }

    /// A flight that starts, and for now ends, where the view is.
    private func restingFlight() -> Flight {
        Flight(origin: contentView.bounds.origin, magnification: magnification, position: contentView.bounds.origin, currentMagnification: magnification)
    }

    private func startFlight(_ flight: Flight) {
        self.flight = flight
        if displayLink == nil {
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTick = CACurrentMediaTime()
        }
    }

    private func stopFlight() {
        flight = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc
    private func tick(_: CADisplayLink) {
        guard var flight else {
            stopFlight()
            return
        }
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastTick, 0), Layout.maximumFrameInterval))
        lastTick = now

        func advance(_ position: inout CGFloat, _ velocity: inout CGFloat, toward target: CGFloat) {
            let acceleration = -Layout.stiffness * (position - target) - Layout.damping * velocity
            velocity += acceleration * dt
            position += velocity * dt
        }
        advance(&flight.position.x, &flight.velocity.x, toward: flight.origin.x)
        advance(&flight.position.y, &flight.velocity.y, toward: flight.origin.y)
        advance(&flight.currentMagnification, &flight.magnificationVelocity, toward: flight.magnification)

        let arrived = abs(flight.position.x - flight.origin.x) < Layout.arrivalDistance
            && abs(flight.position.y - flight.origin.y) < Layout.arrivalDistance
            && abs(flight.velocity.x) < Layout.arrivalSpeed && abs(flight.velocity.y) < Layout.arrivalSpeed
            && abs(flight.currentMagnification - flight.magnification) < Layout.arrivalMagnification
        if arrived {
            flight.position = flight.origin
            flight.currentMagnification = flight.magnification
        }
        self.flight = flight
        if magnification != flight.currentMagnification {
            magnification = flight.currentMagnification
        }
        contentView.setBoundsOrigin(clamp(flight.position, at: flight.currentMagnification))
        reflectScrolledClipView(contentView)
        if arrived {
            stopFlight()
            boundsChanged()
            armRest()
        }
    }

    // MARK: - Events

    /// Escape in the overview goes back to the page.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, magnification < 1 {
            onLeaveOverview?()
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool {
        true
    }
}

/// The plane: slab, band, and hint views at their frames, mounted only within reach.
@MainActor
final class TableDocumentView: NSView {
    weak var scrollView: TableScrollView?
    /// Finds the tab for a slab about to be mounted.
    var tabProvider: ((UUID) -> Tab?)?

    private(set) var layout = TableLayout()
    private(set) var geometry = TableGeometry(viewport: .zero)
    private var slabViews: [UUID: NSView] = [:]
    private var bandViews: [UUID: NSView] = [:]
    private var emptyRowView: NSView?
    private var band: CGRect = .zero
    private let overviewCatcher = TableOverviewCatcher()

    override var isFlipped: Bool {
        true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        overviewCatcher.isHidden = true
        addSubview(overviewCatcher)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lays the plane out again: the frame grows to the table, slab views on screen move to
    /// their new frames, slabs gone leave.
    func apply(layout: TableLayout, geometry: TableGeometry, animated: Bool) {
        self.layout = layout
        self.geometry = geometry
        let size = geometry.tableSize(of: layout)
        if frame.size != size {
            setFrameSize(size)
        }
        overviewCatcher.frame = bounds
        let present = Set(layout.tabIDs)
        for (tabID, view) in slabViews where !present.contains(tabID) {
            view.removeFromSuperview()
            slabViews.removeValue(forKey: tabID)
        }
        let rowIDs = Set(layout.rows.filter(\.isCollapsed).map(\.id))
        for (rowID, view) in bandViews where !rowIDs.contains(rowID) {
            view.removeFromSuperview()
            bandViews.removeValue(forKey: rowID)
        }
        for (tabID, view) in slabViews {
            guard let frame = geometry.frame(of: tabID, in: layout) else { continue }
            if layout.row(of: tabID)?.isCollapsed == true {
                view.removeFromSuperview()
                slabViews.removeValue(forKey: tabID)
            } else {
                place(view, at: frame, animated: animated)
            }
        }
        for (rowID, view) in bandViews {
            guard let index = layout.rows.firstIndex(where: { $0.id == rowID }) else { continue }
            place(view, at: geometry.rowFrame(index, in: layout), animated: animated)
        }
        if let emptyRowView {
            place(emptyRowView, at: geometry.emptyRowFrame(in: layout), animated: animated)
        }
        mount(in: band)
    }

    /// Creates views for the slabs and bands that `rect` touches and releases those beyond it.
    func mount(in rect: CGRect) {
        band = rect
        guard let scrollView else { return }
        let wanted = geometry.slabs(in: rect, of: layout)
        let wantedIDs = Set(wanted.map(\.tabID))
        for (tabID, view) in slabViews where !wantedIDs.contains(tabID) {
            view.removeFromSuperview()
            slabViews.removeValue(forKey: tabID)
        }
        for slab in wanted where slabViews[slab.tabID] == nil {
            guard let tab = tabProvider?(slab.tabID), let view = scrollView.makeSlabView?(tab) else { continue }
            view.frame = slab.frame
            addSubview(view, positioned: .below, relativeTo: overviewCatcher)
            slabViews[slab.tabID] = view
        }
        let rows = geometry.rows(in: rect, of: layout).filter { layout.rows[$0].isCollapsed }
        let rowIDs = Set(rows.map { layout.rows[$0].id })
        for (rowID, view) in bandViews where !rowIDs.contains(rowID) {
            view.removeFromSuperview()
            bandViews.removeValue(forKey: rowID)
        }
        for index in rows {
            let row = layout.rows[index]
            guard bandViews[row.id] == nil, let view = scrollView.makeBandView?(row) else { continue }
            view.frame = geometry.rowFrame(index, in: layout)
            addSubview(view, positioned: .below, relativeTo: overviewCatcher)
            bandViews[row.id] = view
        }
        let emptyRow = geometry.emptyRowFrame(in: layout)
        if emptyRow.intersects(rect) {
            if emptyRowView == nil, let view = scrollView.makeEmptyRowView?() {
                view.frame = emptyRow
                addSubview(view, positioned: .below, relativeTo: overviewCatcher)
                emptyRowView = view
            }
        } else if let view = emptyRowView {
            view.removeFromSuperview()
            emptyRowView = nil
        }
        overviewCatcher.isHidden = scrollView.magnification >= 1 - 0.001
        overviewCatcher.frame = bounds
    }

    private func place(_ view: NSView, at frame: CGRect, animated: Bool) {
        guard view.frame != frame else { return }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = TableController.Layout.flightDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().frame = frame
            }
        } else {
            view.frame = frame
        }
    }

    /// The slab under `point`, in the plane's coordinates.
    func tabID(at point: CGPoint) -> UUID? {
        geometry.slab(at: point, in: layout).map { layout[$0].tabID }
    }
}

/// Over the plane in the overview: a click enters the slab under it; scrolling and pinching
/// fall through to the scroll view, so the pages beneath never take them.
@MainActor
private final class TableOverviewCatcher: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let document = superview as? TableDocumentView else { return }
        let point = document.convert(event.locationInWindow, from: nil)
        if let tabID = document.tabID(at: point) {
            document.scrollView?.onEnter?(tabID)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        superview?.enclosingScrollView?.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        superview?.enclosingScrollView?.magnify(with: event)
    }
}
