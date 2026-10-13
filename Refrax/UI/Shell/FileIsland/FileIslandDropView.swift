import AppKit

/// The window's drop surface for things that are files, above every other view.
///
/// AppKit picks a drag's destination by geometry and registered types, not by `hitTest`, so
/// this view sees every drag of files, images, text, or links that crosses the window. It
/// decides one of three things for each position:
///
/// - Over the File Island, it keeps the drop on the shelf.
/// - Over the page, a web address dragged in from another app opens as a new tab.
/// - Anywhere else, it forwards the drag to the view AppKit would have chosen without it,
///   so pages still take uploads and text, and the browser's own drop targets still work.
///
/// Mouse events pass through: `hitTest` returns nil.
final class FileIslandDropView: NSView {
    /// The island's state, which shows the island as a drop target while a drag is over the window.
    var state: (() -> FileIslandState?)?
    /// Whether the island and the page drop are live: the floating layout, with no desk or lock over it.
    var isActive: () -> Bool = { false }
    /// Regions where drops go to what is underneath even when they carry a link: the Control Island.
    var reservedRegions: () -> [CGRect] = { [] }
    var keep: ((ShelfDrop) -> Void)?
    var openLink: ((URL) -> Void)?

    private enum Route: Equatable {
        case island
        case openLink
        case forward
    }

    /// What the current drag carries, read once as it enters.
    private struct Session {
        let sequence: Int
        let kind: ShelfDrop.Kind
        /// The drag started from one of the island's own items, which it does not keep twice.
        let isFromIsland: Bool
    }

    private var route: Route?
    private var session: Session?
    private weak var forwardTarget: NSView?
    private var forwardOperation: NSDragOperation = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ShelfDrop.acceptedTypes + [NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if session?.sequence != sender.draggingSequenceNumber {
            let startedOnIsland = state?().map { Date().timeIntervalSince($0.outgoingDragStarted) < 1 } ?? false
            session = Session(
                sequence: sender.draggingSequenceNumber,
                kind: ShelfDrop.Kind(pasteboard: sender.draggingPasteboard),
                isFromIsland: sender.draggingSource != nil && startedOnIsland,
            )
        }
        return update(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        leaveForwardTarget(sender)
        route = nil
        state?()?.setDrop(.none)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        switch route {
        case .island, .openLink: true
        case .forward: (forwardTarget as (any NSDraggingDestination)?)?.prepareForDragOperation?(sender) ?? true
        case nil: false
        }
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        switch route {
        case .island:
            let drop = ShelfDrop(pasteboard: pasteboard)
            guard !drop.isEmpty else { return false }
            keep?(drop)
            return true
        case .openLink:
            guard let url = ShelfDrop(pasteboard: pasteboard).link else { return false }
            openLink?(url)
            return true
        case .forward:
            return (forwardTarget as (any NSDraggingDestination)?)?.performDragOperation?(sender) ?? false
        case nil:
            return false
        }
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        if route == .forward {
            (forwardTarget as (any NSDraggingDestination)?)?.concludeDragOperation?(sender)
        }
        finish()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        if route == .forward {
            (forwardTarget as (any NSDraggingDestination)?)?.draggingEnded?(sender)
        }
        finish()
    }

    override func updateDraggingItemsForDrag(_ sender: (any NSDraggingInfo)?) {
        if route == .forward {
            (forwardTarget as (any NSDraggingDestination)?)?.updateDraggingItemsForDrag?(sender)
        }
    }

    // MARK: - Routing

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let next = nextRoute(for: sender)
        if next != .forward {
            leaveForwardTarget(sender)
        }
        route = next
        switch next {
        case .island:
            return .copy
        case .openLink:
            return .copy
        case .forward:
            return forward(sender)
        }
    }

    private func nextRoute(for sender: any NSDraggingInfo) -> Route {
        guard isActive(), let state = state?() else {
            return .forward
        }
        guard let session, session.sequence == sender.draggingSequenceNumber, !session.isFromIsland, session.kind.accepts else {
            state.setDrop(.none)
            return .forward
        }
        let point = topLeadingPoint(sender.draggingLocation)
        let islandTarget = state.frame.insetBy(dx: -FileIslandLayout.dropSlack, dy: -FileIslandLayout.dropSlack)
        if !state.frame.isEmpty, islandTarget.contains(point) {
            state.setDrop(.island)
            return .island
        }
        state.setDrop(.window)
        if sender.draggingSource == nil, session.kind.isLinkOnly,
           !reservedRegions().contains(where: { $0.contains(point) }) {
            return .openLink
        }
        return .forward
    }

    /// Passes the drag to the view that would receive it without this one, telling the previous
    /// target it has left when the pointer crosses from one to another.
    private func forward(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let types = Set(sender.draggingPasteboard.types ?? [])
        let target = window?.contentView.flatMap { destination(in: $0, at: sender.draggingLocation, types: types) }
        if target !== forwardTarget {
            leaveForwardTarget(sender)
            forwardTarget = target
            forwardOperation = (target as (any NSDraggingDestination)?)?.draggingEntered?(sender) ?? []
            return forwardOperation
        }
        guard let destination = target as (any NSDraggingDestination)? else { return [] }
        if let operation = destination.draggingUpdated?(sender) {
            forwardOperation = operation
        }
        return forwardOperation
    }

    private func leaveForwardTarget(_ sender: (any NSDraggingInfo)?) {
        guard let target = forwardTarget else { return }
        (target as any NSDraggingDestination).draggingExited?(sender)
        forwardTarget = nil
        forwardOperation = []
    }

    /// The frontmost visible view under `windowPoint` registered for one of `types`, found the
    /// way AppKit finds a drag destination, skipping this view.
    private func destination(in view: NSView, at windowPoint: NSPoint, types: Set<NSPasteboard.PasteboardType>) -> NSView? {
        guard view !== self, !view.isHidden else { return nil }
        let local = view.convert(windowPoint, from: nil)
        guard view.isMousePoint(local, in: view.bounds) else { return nil }
        for subview in view.subviews.reversed() {
            if let found = destination(in: subview, at: windowPoint, types: types) {
                return found
            }
        }
        return Set(view.registeredDraggedTypes).isDisjoint(with: types) ? nil : view
    }

    private func finish() {
        forwardTarget = nil
        forwardOperation = []
        route = nil
        session = nil
        state?()?.setDrop(.none)
    }

    private func topLeadingPoint(_ windowPoint: NSPoint) -> CGPoint {
        let local = convert(windowPoint, from: nil)
        return CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
    }
}
