import AppKit

/// A magnifiable scroll view whose document is the desk.
///
/// Zoom transitions are the canvas's whole trick, and they all travel one path. A tile is
/// *aligned* when it sits exactly where the live page sits in the window. Opening starts
/// with the focused tile aligned, the canvas transparent over the page it matches, and
/// flies out to the whole desk while the canvas fades in. Entering a tile flies back
/// until that tile is aligned, fading out as it lands, and the live page takes over.
/// Both directions can be driven by a pinch instead of a timer.
final class TabCanvasScrollView: NSScrollView {
    /// A tile is being entered: its tab becomes the active one beneath the canvas.
    var onWillEnter: ((Tab) -> Void)?
    /// The canvas has finished closing over the live page.
    var onDismiss: (() -> Void)?
    var onSettle: (([Tab.ID: CGRect]) -> Void)?
    var onTileDropped: ((Tab.ID) -> Void)?
    var onZoneMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetActivated: ((UUID) -> Void)?
    var onLasso: ((Set<Tab.ID>) -> Void)?
    var onClearSelection: (() -> Void)?
    var onTogglePreview: ((Tab.ID, CGRect) -> Void)?
    var impactSoundsEnabled = false {
        didSet { board.impactSoundsEnabled = impactSoundsEnabled }
    }

    private let board: TabCanvasBoardView
    private let canvasClip = CanvasClipView()
    private var isTransitioning = false
    private var flight: ProgressFlight?
    private var isPeeking = false
    private var pinchIntent: CanvasPinchIntent?
    private var pinchTargetID: Tab.ID?
    private var pendingLayoutActions: [() -> Void] = []
    /// The opening's path, from the focused tile aligned on the page to the whole desk.
    private var openingPath: (from: CGRect, to: CGRect)?
    private var openingProgress: CGFloat = 0
    private var pendingOpeningScale: CGFloat?

    /// Where the live page sits, in window coordinates; tiles align to it.
    var livePageFrameInWindow: CGRect?

    private enum Constants {
        static let zoomDuration: TimeInterval = 0.4
        /// Shortest flight, for a pinch released close to where it is headed.
        static let minimumFlightDuration: TimeInterval = 0.15
        /// Share of the path over which the canvas fades between transparent and opaque.
        static let revealSpan: CGFloat = 0.12
        /// How hard a pinch drives the opening: the camera zooms out this many times
        /// faster than the fingers close.
        static let pinchGain: CGFloat = 1.6
        /// How far ⌃ zooms out from the page, enough to see it is one tile among others.
        static let peekZoomOut: CGFloat = 1.15
        static let compactPeekZoomOut: CGFloat = 3
        static let peekDuration: TimeInterval = 0.18
        /// How much faster than the fingers a trackpad scroll moves the desk; a desk is many
        /// screens wide, so following the fingers exactly crawls. Drags stay under the pointer.
        static let scrollGain: CGFloat = 2
        /// A little room beyond the table at the widest camera position.
        static let maximumZoomOut: CGFloat = 1.1
        /// A pinch released with the tile under the fingers at least this fraction of its
        /// page size enters the tile.
        static let enterThreshold: CGFloat = 0.5
        /// Room kept clear when fitting tiles: the traffic lights above, the floating
        /// controls below.
        static let fitInsets = NSEdgeInsets(top: 56, left: 40, bottom: 88, right: 40)
        static let minMagnification: CGFloat = 0.05
        static let maxMagnification: CGFloat = 4
        static let targetHysteresis: CGFloat = 18
        static let focusDuration: TimeInterval = 0.18
        static let reducedMotionDuration: TimeInterval = 0.12
    }

    init(deskSize: CGSize) {
        self.board = TabCanvasBoardView(deskSize: deskSize)
        super.init(frame: .zero)
        drawsBackground = true
        backgroundColor = .underPageBackgroundColor
        hasHorizontalScroller = false
        hasVerticalScroller = false
        allowsMagnification = true
        minMagnification = Constants.minMagnification
        maxMagnification = Constants.maxMagnification
        contentView = canvasClip
        documentView = board
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsetsZero

        board.onActivate = { [weak self] tab, frame in self?.enter(frame, tab: tab) }
        canvasClip.centerRegion = { [weak board] in board?.bounds }
        board.onPanCamera = { [weak self] delta in self?.pan(by: delta) }
        board.onDismiss = { [weak self] in self?.dismissZoomingIntoFocusedTile() }
        board.onSettle = { [weak self] frames in self?.onSettle?(frames) }
        board.onTileDropped = { [weak self] tabID in self?.onTileDropped?(tabID) }
        board.onZoneMoved = { [weak self] groupID, delta in self?.onZoneMoved?(groupID, delta) }
        board.onMagnetMoved = { [weak self] groupID, delta in self?.onMagnetMoved?(groupID, delta) }
        board.onMagnetActivated = { [weak self] groupID in self?.onMagnetActivated?(groupID) }
        board.onLasso = { [weak self] tabIDs in self?.onLasso?(tabIDs) }
        board.onClearSelection = { [weak self] in self?.onClearSelection?() }
        board.onTogglePreview = { [weak self] id, frame in self?.onTogglePreview?(id, frame) }
        board.onRevealTile = { [weak self] frame in self?.revealTile(frame) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload(_ content: CanvasBoardContent) {
        board.reload(content)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(board)
        if window == nil {
            flight?.cancel()
            flight = nil
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        guard !pendingLayoutActions.isEmpty, contentView.frame.width > 0 else { return }
        let actions = pendingLayoutActions
        pendingLayoutActions = []
        for action in actions {
            action()
        }
    }

    /// Runs `action` once the clip view has a size, in the order requested; camera math
    /// needs the size.
    private func whenLaidOut(_ action: @escaping () -> Void) {
        if contentView.frame.width > 0 {
            let waiting = pendingLayoutActions
            pendingLayoutActions = []
            for earlier in waiting {
                earlier()
            }
            action()
        } else {
            Logger.debug("queued until layout (\(pendingLayoutActions.count) waiting)", category: Logger.canvas)
            pendingLayoutActions.append(action)
            needsLayout = true
        }
    }

    // MARK: - Opening

    /// Places the camera at the start of the opening: `tile` aligned on the live page, or
    /// the whole desk when there is no tile, with the canvas still transparent.
    ///
    /// The opening reveals all four edges of the table, preserving each tile's position.
    func beginOpening(focusedTile tile: CGRect?, desk: CGRect, from visible: CGRect? = nil) {
        alphaValue = 0
        whenLaidOut { [weak self] in
            guard let self else { return }
            let fit = fittedRect(for: desk, insets: Constants.fitInsets)
            guard let tile else {
                openingPath = (from: fit, to: fit)
                applyOpening(openingProgress)
                return
            }
            let preview = board.originTabID.flatMap { board.previewFrame(for: $0) } ?? tile
            let aligned = alignedRect(for: preview)
            openingPath = (from: visible ?? aligned, to: fit)
            if let scale = pendingOpeningScale {
                pendingOpeningScale = nil
                setOpeningScale(scale)
            }
            applyOpening(openingProgress)
        }
    }

    /// Follows a pinch: the page shrinks exactly as much as the fingers close.
    func setOpeningScale(_ scale: CGFloat) {
        guard let path = openingPath, scale > 0 else {
            Logger.debug("opening scale \(scale) queued: no path yet", category: Logger.canvas)
            pendingOpeningScale = scale
            return
        }
        Logger.debug("opening scale \(scale) flight \(flight != nil)", category: Logger.canvas)
        let ratio = path.to.width / path.from.width
        guard ratio > 1 else { return setOpeningProgress(1) }
        setOpeningProgress(min(1, max(0, Constants.pinchGain * log(1 / scale) / log(ratio))))
    }

    /// `rect` grown by `factor` about `point`, which stays where it is on screen.
    private static func scale(_ rect: CGRect, by factor: CGFloat, about point: CGPoint) -> CGRect {
        var camera = TabSpatialCamera(origin: rect.origin)
        camera.zoom(to: 1 / factor, at: CGPoint(x: point.x - rect.minX, y: point.y - rect.minY))
        return camera.unproject(CGRect(origin: .zero, size: rect.size))
    }

    // MARK: - Panning from a Page

    /// Brings the desk up around the page for ⌃: the focused tile starts on the page and
    /// the camera eases back a little, so the page shows as one tile among others.
    func beginPanning(focusedTile tile: CGRect?) {
        isPeeking = true
        alphaValue = 0
        whenLaidOut { [weak self] in
            guard let self else { return }
            guard let tile else {
                alphaValue = 1
                return
            }
            let preview = board.originTabID.flatMap { board.previewFrame(for: $0) } ?? tile
            let from = alignedRect(for: preview)
            let compactOrigin = board.originTabID.flatMap { board.tile(withID: $0).map { $0.frame.height < FloatingCardShape.live.minimumSize.height } } ?? false
            let to = Self.scale(from, by: compactOrigin ? Constants.compactPeekZoomOut : Constants.peekZoomOut, about: CGPoint(x: tile.midX, y: tile.midY))
            setVisibleRect(from)
            let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            run(from: 0, to: 1, duration: Constants.peekDuration, frame: { [weak self] t in
                self?.setVisibleRect(reducedMotion ? to : Self.interpolate(from: from, to: to, t: t))
                if let self, let id = board.originTabID {
                    board.revealPreview(of: id, progress: reducedMotion ? 0 : 1 - t)
                }
                self?.alphaValue = Self.reveal(t)
            }, completion: nil)
        }
    }

    /// Slides the desk with the wheel; `delta` is in screen points.
    func pan(by delta: CGPoint) {
        whenLaidOut { [weak self] in
            guard let self, !isTransitioning, magnification > 0, delta != .zero else { return }
            if flight != nil {
                finishCameraFlight()
            }
            var visible = contentView.bounds
            visible.origin.x -= delta.x / magnification
            visible.origin.y -= delta.y / magnification
            setVisibleRect(canvasClip.keepingCenterNearDesk(visible))
        }
    }

    /// Zooms by `factor` around the pointer, keeping the arrangement open for navigation.
    func zoom(by factor: CGFloat, aboutWindowPoint windowPoint: CGPoint) {
        applyZoom(by: factor, aboutWindowPoint: windowPoint)
    }

    private func applyZoom(by factor: CGFloat, aboutWindowPoint windowPoint: CGPoint) {
        whenLaidOut { [weak self] in
            guard let self, !isTransitioning, openingPath == nil, factor > 0, factor.isFinite else { return }
            if flight != nil {
                finishCameraFlight()
            }
            let anchor = board.convert(windowPoint, from: nil)
            let visible = contentView.bounds
            var width = visible.width / factor
            let fit = fittedRect(for: board.bounds, insets: Constants.fitInsets)
            let clipWidth = contentView.frame.width
            let minimumWidth = clipWidth / maxMagnification
            let maximumWidth = min(fit.width * Constants.maximumZoomOut, clipWidth / minMagnification)
            width = min(max(width, minimumWidth), max(minimumWidth, maximumWidth))
            let zoomed = Self.scale(visible, by: width / visible.width, about: anchor)
            setVisibleRect(canvasClip.keepingCenterNearDesk(zoomed))
        }
    }

    /// Moves the desk for a trackpad scroll of `delta` points, faster than the fingers.
    func scroll(by delta: CGPoint) {
        pan(by: CGPoint(x: delta.x * Constants.scrollGain, y: delta.y * Constants.scrollGain))
    }

    /// Settles into a tile, and the page takes over.
    func settle(on place: CanvasPanSettle) {
        whenLaidOut { [weak self] in
            guard let self, !isTransitioning else { return }
            Logger.debug("settle on \(place)", category: Logger.canvas)
            finishCameraFlight()
            let point: CGPoint
            switch place {
            case .origin:
                dismissZoomingIntoFocusedTile()
                return
            case .nearest:
                updatePeekTarget()
                if let id = board.navigationTabID, let tile = board.tile(withID: id) {
                    enter(tile.frame, tab: tile.tab)
                    return
                }
                let visible = contentView.bounds
                point = CGPoint(x: visible.midX, y: visible.midY)
            case let .tile(windowPoint):
                point = board.convert(windowPoint, from: nil)
            }
            guard let (tab, frame) = board.tile(near: point) else {
                onDismiss?()
                return
            }
            enter(frame, tab: tab)
        }
    }

    /// Moves the opening to `progress`, 0 on the page and 1 on the whole desk.
    func setOpeningProgress(_ progress: CGFloat) {
        openingProgress = progress
        if openingPath != nil {
            applyOpening(progress)
        }
    }

    /// Completes the opening from wherever it is, or takes it back to the page and closes.
    func finishOpening(commit: Bool) {
        Logger.debug("finish opening commit \(commit) at \(openingProgress)", category: Logger.canvas)
        whenLaidOut { [weak self] in
            guard let self, openingPath != nil else { return }
            let target: CGFloat = commit ? 1 : 0
            run(from: openingProgress, to: target, frame: { [weak self] t in
                self?.openingProgress = t
                self?.applyOpening(t)
            }, completion: { [weak self] in
                guard let self else { return }
                openingPath = nil
                if !commit {
                    onDismiss?()
                }
            })
        }
    }

    private func applyOpening(_ t: CGFloat) {
        guard let path = openingPath else { return }
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let id = board.originTabID {
            board.revealPreview(of: id, progress: reducedMotion ? 0 : 1 - t)
        }
        setVisibleRect(reducedMotion ? path.to : Self.interpolate(from: path.from, to: path.to, t: t))
        alphaValue = Self.reveal(t)
    }

    // MARK: - Entering a Tile

    /// Flies the camera so `rect` fits, without leaving the canvas.
    func fly(toFit rect: CGRect) {
        guard !isTransitioning else { return }
        finishCameraFlight()
        let from = contentView.bounds
        let to = fittedRect(for: rect, insets: Constants.fitInsets)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setVisibleRect(to)
            return
        }
        run(from: 0, to: 1, frame: { [weak self] t in
            self?.setVisibleRect(Self.interpolate(from: from, to: to, t: t))
        }, completion: nil)
    }

    /// Goes back into the tab the canvas was opened from.
    func dismissZoomingIntoFocusedTile() {
        if let id = board.originTabID, let tile = board.tile(withID: id) {
            enter(tile.frame, tab: tile.tab)
        } else {
            onDismiss?()
        }
    }

    /// Flies until `tile` is aligned on the live page, fading the canvas out as it lands.
    /// With a `tab`, that tab becomes the active one first, so its page is the one revealed.
    private func enter(_ tile: CGRect, tab: Tab?) {
        Logger.debug("enter tile \(tile) transitioning \(isTransitioning)", category: Logger.canvas)
        guard !isTransitioning else { return }
        finishCameraFlight()
        isTransitioning = true
        isPeeking = false
        board.isInteractionEnabled = false
        if let tab {
            onWillEnter?(tab)
        }
        let from = contentView.bounds
        let preview = tab.flatMap { board.previewFrame(for: $0.id) } ?? tile
        let to = alignedRect(for: preview)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        run(from: 0, to: 1, frame: { [weak self] t in
            if let tab {
                self?.board.revealPreview(of: tab.id, progress: reducedMotion ? 0 : t)
            }
            if !reducedMotion {
                self?.setVisibleRect(Self.interpolate(from: from, to: to, t: t))
            }
            self?.alphaValue = reducedMotion ? 1 - t : Self.reveal(1 - t)
        }, completion: { [weak self] in
            Logger.debug("entered tile", category: Logger.canvas)
            self?.isTransitioning = false
            self?.onDismiss?()
        })
    }

    /// A pinch released with a tile near its page size enters that tile.
    private func enterIfZoomedIn() {
        guard !isTransitioning, openingPath == nil, let page = pageRectInClip,
              pinchIntent?.shouldEnter == true, let id = pinchTargetID,
              let (tab, frame) = board.tile(withID: id), frame.width > 0 else { return }
        let alignedMagnification = page.width / (board.previewFrame(for: id)?.width ?? frame.width)
        if magnification >= alignedMagnification * Constants.enterThreshold {
            enter(frame, tab: tab)
        }
    }

    // MARK: - Camera

    /// The live page's rectangle in the clip view, origin at its top left.
    private var pageRectInClip: CGRect? {
        guard let windowRect = livePageFrameInWindow, window != nil else { return nil }
        let local = convert(windowRect, from: nil)
        let clip = contentView.frame
        let y = isFlipped ? local.minY - clip.minY : clip.maxY - local.maxY
        return CGRect(x: local.minX - clip.minX, y: y, width: local.width, height: local.height)
    }

    /// The visible rectangle that shows `tile` exactly where the live page is; centered
    /// in the clip view when the page's place is unknown.
    private func alignedRect(for tile: CGRect) -> CGRect {
        let clip = contentView.frame.size
        guard let page = pageRectInClip, page.width > 0, page.height > 0, tile.width > 0, tile.height > 0 else {
            return fittedRect(for: tile)
        }
        let scale = min(page.width / tile.width, page.height / tile.height)
        return CGRect(
            x: tile.minX - page.minX / scale,
            y: tile.minY - page.minY / scale,
            width: clip.width / scale,
            height: clip.height / scale,
        )
    }

    /// The visible rectangle that fits `rect` into the clip view, inside `insets`.
    private func fittedRect(for rect: CGRect, insets: NSEdgeInsets = NSEdgeInsetsZero) -> CGRect {
        let clip = contentView.frame.size
        let available = CGRect(
            x: insets.left,
            y: insets.top,
            width: clip.width - insets.left - insets.right,
            height: clip.height - insets.top - insets.bottom,
        )
        guard available.width > 0, available.height > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let magnification = min(available.width / rect.width, available.height / rect.height)
        return CGRect(
            x: rect.midX - available.midX / magnification,
            y: rect.midY - available.midY / magnification,
            width: clip.width / magnification,
            height: clip.height / magnification,
        )
    }

    /// Shows exactly `visible` (a rectangle in document coordinates) in the clip view.
    /// The camera goes where it is placed; only the user's own scrolling is kept near tiles.
    private func setVisibleRect(_ visible: CGRect) {
        let clip = contentView.frame.size
        guard clip.width > 0, visible.isUsableCamera else { return }
        canvasClip.isPlacingCamera = true
        defer { canvasClip.isPlacingCamera = false }
        magnification = clip.width / visible.width
        contentView.setBoundsOrigin(visible.origin)
        reflectScrolledClipView(contentView)
        updatePeekTarget()
    }

    private func updatePeekTarget() {
        guard isPeeking, magnification > 0 else { return }
        let visible = contentView.bounds
        board.target(near: CGPoint(x: visible.midX, y: visible.midY), hysteresis: Constants.targetHysteresis / magnification)
    }

    /// Keeps keyboard navigation at the current scale, moving only far enough to reveal the tile.
    private func revealTile(_ tile: CGRect) {
        guard !isTransitioning else { return }
        finishCameraFlight()
        isPeeking = false
        let from = contentView.bounds
        let inset = Constants.fitInsets
        let safe = CGRect(
            x: from.minX + inset.left / magnification,
            y: from.minY + inset.top / magnification,
            width: from.width - (inset.left + inset.right) / magnification,
            height: from.height - (inset.top + inset.bottom) / magnification,
        )
        let footprint = tile.insetBy(dx: -12, dy: -TabCanvasManager.Layout.tileTitleHeight)
        func shift(_ low: CGFloat, _ high: CGFloat, _ safeLow: CGFloat, _ safeHigh: CGFloat) -> CGFloat {
            if high - low > safeHigh - safeLow {
                return (low + high - safeLow - safeHigh) / 2
            }
            if low < safeLow {
                return low - safeLow
            }
            return max(0, high - safeHigh)
        }
        let to = from.offsetBy(
            dx: shift(footprint.minX, footprint.maxX, safe.minX, safe.maxX),
            dy: shift(footprint.minY, footprint.maxY, safe.minY, safe.maxY),
        )
        guard from != to else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setVisibleRect(to)
        } else {
            run(from: 0, to: 1, duration: Constants.focusDuration, frame: { [weak self] t in
                self?.setVisibleRect(Self.interpolate(from: from, to: to, t: t))
            }, completion: nil)
        }
    }

    private func finishCameraFlight() {
        flight?.abandon()
        flight = nil
        alphaValue = 1
        if let id = board.originTabID {
            board.revealPreview(of: id, progress: 0)
        }
    }

    /// Animates a progress value, shortening the flight when it has less of the way to go.
    private func run(
        from start: CGFloat,
        to end: CGFloat,
        duration fixedDuration: TimeInterval? = nil,
        frame: @escaping (CGFloat) -> Void,
        completion: (() -> Void)?,
    ) {
        // A replaced flight still finishes its work, so no transition is left half done.
        flight?.abandon()
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? Constants.reducedMotionDuration
            : fixedDuration ?? max(Constants.minimumFlightDuration, Constants.zoomDuration * Double(abs(end - start)))
        let next = ProgressFlight(from: start, to: end, duration: duration)
        flight = next
        next.start(in: contentView, frame: frame) { [weak self] in
            self?.flight = nil
            completion?()
        }
    }

    /// The camera between two visible rectangles at `t`: the center travels in a straight
    /// line and the scale changes exponentially, so the target stays on a straight path
    /// toward the middle of the screen. Interpolating magnification and origin separately
    /// zooms about the current center first and slides afterwards, which reads as two moves.
    private static func interpolate(from start: CGRect, to end: CGRect, t: CGFloat) -> CGRect {
        guard start.isUsableCamera, end.isUsableCamera else {
            return end.isUsableCamera ? end : start
        }
        let width = start.width * pow(end.width / start.width, t)
        let height = width * end.height / end.width
        let center = CGPoint(
            x: start.midX + (end.midX - start.midX) * t,
            y: start.midY + (end.midY - start.midY) * t,
        )
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// The canvas's opacity at `t` along a path from the page (0) to the desk (1).
    private static func reveal(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t / Constants.revealSpan))
        return x * x * (3 - 2 * x)
    }

    // MARK: - Input

    /// The wheel traverses the same neighbors at every scale; Option-wheel zooms at the pointer.
    override func scrollWheel(with event: NSEvent) {
        handleWheel(CanvasWheelInput.action(for: event), at: event.locationInWindow)
    }

    func handleWheel(_ action: CanvasWheelInput.Action, at point: CGPoint) {
        switch action {
        case let .step(direction): step(direction)
        case let .pan(delta): scroll(by: delta)
        case let .zoom(factor): zoom(by: factor, aboutWindowPoint: point)
        case .none: break
        }
    }

    func step(_ direction: TableDirection) {
        whenLaidOut { [weak self] in
            guard let self, !isTransitioning, openingPath == nil else { return }
            board.moveFocus(direction.canvasDirection)
        }
    }

    func zoom(by factor: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        zoom(by: factor, aboutWindowPoint: convert(center, to: nil))
    }

    override func magnify(with event: NSEvent) {
        guard !isTransitioning, openingPath == nil else { return }
        finishCameraFlight()
        if event.phase == .began || pinchIntent == nil {
            pinchIntent = CanvasPinchIntent()
            let point = board.convert(event.locationInWindow, from: nil)
            pinchTargetID = board.tile(near: point).flatMap { CanvasPhysics.collisionBox($0.frame).contains(point) ? $0.tab.id : nil }
            if let pinchTargetID {
                board.target(pinchTargetID)
            }
        }
        if event.phase != .ended, event.phase != .cancelled {
            pinchIntent?.update(by: event.magnification)
            applyZoom(by: max(0.05, 1 + event.magnification), aboutWindowPoint: event.locationInWindow)
        }
        if event.phase == .ended {
            enterIfZoomedIn()
        }
        if event.phase == .ended || event.phase == .cancelled {
            pinchIntent = nil
            pinchTargetID = nil
        }
    }
}

// MARK: - Clip View

/// A clip view whose camera may show beyond the desk's edges. The default clamps the
/// visible rectangle to the document, which pins a fitted or aligned camera against the
/// desk's corner instead of where it was placed.
///
/// When the user scrolls or zooms, the middle of the view stays within the table.
private final class CanvasClipView: NSClipView {
    /// The table surface; nil leaves the camera free.
    var centerRegion: (() -> CGRect?)?
    /// The camera is being placed by a flight or alignment rather than moved by the user.
    var isPlacingCamera = false

    /// A non-finite camera, which AppKit traps on, keeps the current bounds.
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        guard proposedBounds.isUsableCamera else { return bounds }
        return isPlacingCamera ? proposedBounds : keepingCenterNearDesk(proposedBounds)
    }

    /// `visible` moved so its middle lies within the table.
    func keepingCenterNearDesk(_ visible: CGRect) -> CGRect {
        guard let region = centerRegion?() else { return visible }
        let center = CGPoint(
            x: min(max(visible.midX, region.minX), region.maxX),
            y: min(max(visible.midY, region.minY), region.maxY),
        )
        return visible.offsetBy(dx: center.x - visible.midX, dy: center.y - visible.midY)
    }
}

private extension CGRect {
    /// Finite, with a positive size: something the camera can show.
    var isUsableCamera: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
    }
}

// MARK: - Progress Flight

/// A display-link-driven animation of one value, eased in and out.
private final class ProgressFlight {
    private let startValue: CGFloat
    private let endValue: CGFloat
    private let duration: TimeInterval
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var frame: ((CGFloat) -> Void)?
    private var completion: (() -> Void)?

    init(from start: CGFloat, to end: CGFloat, duration: TimeInterval) {
        self.startValue = start
        self.endValue = end
        self.duration = duration
    }

    func start(in view: NSView, frame: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
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

    /// Stops moving and runs the completion now, leaving the camera where it is.
    func abandon() {
        let done = completion
        cancel()
        done?()
    }

    @objc
    private func tick() {
        let elapsed = CACurrentMediaTime() - startTime
        let progress = min(1, elapsed / duration)
        let eased = CGFloat(Self.easeInOut(progress))
        frame?(startValue + (endValue - startValue) * eased)
        if progress >= 1 {
            let done = completion
            cancel()
            done?()
        }
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}

// MARK: - Driver

extension TabCanvasScrollView: CanvasBoardDriver {
    var navigationTabID: Tab.ID? {
        board.navigationTabID
    }
    var isSimulating: Bool {
        board.isSimulating
    }

    func drag(_ tabID: Tab.ID, to origin: CGPoint, duration: TimeInterval, fling: Bool) async {
        await board.drag(tabID, to: origin, duration: duration, fling: fling)
    }
}
