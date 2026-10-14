import AppKit

/// The table as a scroll view: the window is the clip, the plane is the document, every slab
/// in reach is a live page view at its frame. Scrolling and magnifying are AppKit's own, so
/// the table moves 1:1 with the fingers, carries momentum, and rubber-bands at its edges.
///
/// Slab views exist for the visible rect plus one viewport of margin on each side and are
/// released beyond it, like a collection view's cells, so a long table costs what the window
/// shows. A collapsed row is one band view.
@MainActor
final class TableScrollView: NSScrollView {
    /// Makes the view for a slab; the controller's SwiftUI content, hosted.
    var makeSlabView: ((Tab) -> NSView)?
    /// Makes the band for a collapsed row.
    var makeBandView: ((TableLayout.Row) -> NSView)?
    /// The window looked somewhere else, by hand or in flight.
    var onViewportMoved: ((CGRect, CGFloat) -> Void)?
    /// Scrolling and magnifying have stopped.
    var onRest: (() -> Void)?
    /// A slab was clicked in the overview.
    var onEnter: ((UUID) -> Void)?
    /// Escape was pressed in the overview.
    var onLeaveOverview: (() -> Void)?

    let document = TableDocumentView()

    private enum Layout {
        /// Bounds changes this far apart are separate motions; quiet for this long is rest.
        static let restQuiet: TimeInterval = 0.12
        static let flightDuration: TimeInterval = 0.32
        /// How far a nudge at the table's edge moves before springing back.
        static let nudge: CGFloat = 24
    }

    private var restTimer: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var isAnimating = false
    private var lastReported: (CGRect, CGFloat) = (.zero, 1)

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
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        restTimer?.invalidate()
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
                guard let self, !self.isAnimating else { return }
                self.onRest?()
            }
        }
    }

    // MARK: - Moving

    /// Flies to `origin` at `magnification`, or jumps there.
    func scroll(to origin: CGPoint, magnification: CGFloat, animated: Bool) {
        let target = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        guard animated else {
            if self.magnification != magnification {
                self.magnification = magnification
            }
            contentView.setBoundsOrigin(target)
            reflectScrolledClipView(contentView)
            armRest()
            return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.flightDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            if self.magnification != magnification {
                animator().magnification = magnification
            }
            contentView.animator().setBoundsOrigin(target)
            reflectScrolledClipView(contentView)
        } completionHandler: {
            MainActor.assumeIsolated {
                self.isAnimating = false
                self.boundsChanged()
                self.armRest()
            }
        }
    }

    /// A short push against the table's edge, for a step with nowhere to go.
    func nudge(_ direction: TableDirection) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let origin = contentView.bounds.origin
        var pushed = origin
        switch direction {
        case .left: pushed.x -= Layout.nudge
        case .right: pushed.x += Layout.nudge
        case .up: pushed.y -= Layout.nudge
        case .down: pushed.y += Layout.nudge
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.allowsImplicitAnimation = true
            contentView.animator().setBoundsOrigin(pushed)
        } completionHandler: {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    self.contentView.animator().setBoundsOrigin(origin)
                } completionHandler: {
                    MainActor.assumeIsolated {
                        self.isAnimating = false
                        self.armRest()
                    }
                }
            }
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

/// The plane: slab and band views at their frames, mounted only within reach.
@MainActor
final class TableDocumentView: NSView {
    weak var scrollView: TableScrollView?
    /// Finds the tab for a slab about to be mounted.
    var tabProvider: ((UUID) -> Tab?)?

    private(set) var layout = TableLayout()
    private(set) var geometry = TableGeometry(viewport: .zero)
    private var slabViews: [UUID: NSView] = [:]
    private var bandViews: [UUID: NSView] = [:]
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
