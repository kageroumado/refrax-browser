import AppKit

/// A magnifiable scroll view whose document is the desk.
///
/// Zoom transitions are the canvas's whole trick: opening zooms out from the tile of
/// the current tab until every tile is visible, choosing a tile zooms into it until
/// it fills the clip view, and only then does the live page take over underneath.
final class TabCanvasScrollView: NSScrollView {
    var onActivate: ((Tab) -> Void)?
    var onDismiss: (() -> Void)?
    var onSettle: (([Tab.ID: CGRect]) -> Void)?
    var onTileDropped: ((Tab.ID) -> Void)?
    var onTileFellOffDesk: ((Tab.ID) -> Void)?
    var onZoneMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetMoved: ((UUID, CGPoint) -> Void)?
    var onMagnetActivated: ((UUID) -> Void)?
    var onLasso: ((Set<Tab.ID>) -> Void)?
    var onClearSelection: (() -> Void)?

    private let board: TabCanvasBoardView
    private var isTransitioning = false
    private var focusedTileFrame: CGRect?
    private var zoomFlight: ZoomFlight?

    private enum Constants {
        static let zoomDuration: TimeInterval = 0.4
        static let minMagnification: CGFloat = 0.05
        static let maxMagnification: CGFloat = 4
    }

    init(deskSize: CGSize) {
        board = TabCanvasBoardView(deskSize: deskSize)
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
        board.onSettle = { [weak self] frames in self?.onSettle?(frames) }
        board.onTileDropped = { [weak self] tabID in self?.onTileDropped?(tabID) }
        board.onTileFellOffDesk = { [weak self] tabID in self?.onTileFellOffDesk?(tabID) }
        board.onZoneMoved = { [weak self] groupID, delta in self?.onZoneMoved?(groupID, delta) }
        board.onMagnetMoved = { [weak self] groupID, delta in self?.onMagnetMoved?(groupID, delta) }
        board.onMagnetActivated = { [weak self] groupID in self?.onMagnetActivated?(groupID) }
        board.onLasso = { [weak self] tabIDs in self?.onLasso?(tabIDs) }
        board.onClearSelection = { [weak self] in self?.onClearSelection?() }
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

    /// Flies the camera so `rect` fits, without leaving the canvas.
    func fly(toFit rect: CGRect) {
        guard !isTransitioning else { return }
        animateZoom(toFit: rect, completion: nil)
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

// MARK: - Driver

extension TabCanvasScrollView: CanvasBoardDriver {
    var isSimulating: Bool {
        board.isSimulating
    }

    func drag(_ tabID: Tab.ID, to origin: CGPoint, duration: TimeInterval, fling: Bool) async {
        await board.drag(tabID, to: origin, duration: duration, fling: fling)
    }
}
