import AppKit
import Observation
import SwiftUI
import WebKit

/// A group drawn on the tab canvas as a zone that holds its member tiles.
struct CanvasZone: Identifiable, Equatable {
    let id: UUID
    let name: String
    let color: NSColor
    /// The zone's rectangle on the board.
    let frame: CGRect
    /// Nesting depth; parents are drawn first.
    let depth: Int
    /// Every tab inside the zone, including those of nested groups.
    let memberTabIDs: [Tab.ID]
}

/// A group drawn on the tab canvas as a magnet that gathers its members around a point.
struct CanvasMagnet: Identifiable, Equatable {
    let id: UUID
    let name: String
    let color: NSColor
    let anchor: CGPoint
    let memberTabIDs: [Tab.ID]
}

/// The board as seen by its manager: something that can run a gesture and report
/// whether its tiles are still moving.
@MainActor
protocol CanvasBoardDriver: AnyObject {
    /// The tab currently outlined as the navigation destination.
    var navigationTabID: Tab.ID? { get }
    /// Tiles are moving under the physics simulation.
    var isSimulating: Bool { get }
    /// Moves the opening to `progress`, 0 on the page and 1 at its end.
    func setOpeningProgress(_ progress: CGFloat)
    /// Follows a pinch at `scale` (1 at its start, smaller as the fingers close).
    func setOpeningScale(_ scale: CGFloat)
    /// Slides the desk by `delta` screen points.
    func pan(by delta: CGPoint)
    /// Settles into a tile, and the page takes over.
    func settle(on place: CanvasPanSettle)
    /// Zooms by `factor` about a point in window coordinates.
    func zoom(by factor: CGFloat, aboutWindowPoint point: CGPoint)
    /// Moves the desk for a trackpad scroll of `delta` points.
    func scroll(by delta: CGPoint)
    /// Moves the destination one visible neighbor at the current scale.
    func step(_ direction: TableDirection)
    /// Reveals a tab at the current camera scale.
    func reveal(_ id: Tab.ID)
    /// Zooms around the center of the viewport.
    func zoom(by factor: CGFloat)
    /// Completes the opening, or takes it back to the page and closes the canvas.
    func finishOpening(commit: Bool)
    /// Drags a tile along an eased path until its top-left corner reaches `origin`,
    /// through the same hold-and-release path the pointer uses. With `fling` the tile
    /// is let go at full speed and slides on.
    func drag(_ tabID: Tab.ID, to origin: CGPoint, duration: TimeInterval, fling: Bool) async
}

/// Where a desk brought up from a page settles.
enum CanvasPanSettle: Equatable {
    /// The tile nearest the middle of the window.
    case nearest
    /// The tile at a point in window coordinates, or the nearest one to it.
    case tile(atWindowPoint: CGPoint)
    /// The tab the desk came up from.
    case origin
}

/// A hint about getting into or out of the canvas, shown once ever.
enum CanvasHint: String {
    /// Shown the first time a page is pinched, while it zooms.
    case enteringCanvas
    /// Shown the first time the canvas opens.
    case leavingCanvas

    var text: String {
        switch self {
        case .enteringCanvas: "Pinch in to see all your tabs"
        case .leavingCanvas: "Scroll to move · Option-scroll to zoom · Click a tab to open · Esc to go back"
        }
    }

    var seenKey: String {
        "canvas.hint.\(rawValue).seen"
    }
}

/// A one-shot request for the board to fly its camera to a rectangle.
struct CanvasZoomRequest: Equatable {
    let serial: Int
    let rect: CGRect
}

/// Manages the tab canvas: a desk on which every tab of the active space is a
/// tile placed at a position of its own, zoomed out from and back into the live page.
///
/// The desk is finite. Tiles keep the position they were given (persisted on
/// ``Tab/floatingPlacement``). A click opens that tab's page; the camera keeps its
/// position on the table for the next visit.
///
/// Tab groups appear on the desk in one of two shapes. A **zone**
/// (``TabGroup/boardFrame``) is a region that is at least the claimed rectangle
/// and grows to hold its members; dragging it carries them, dropping a tile inside
/// joins the group. A **magnet** (``TabGroup/boardAnchor``) gathers its members in a
/// ring around a point and attracts tabs similar to them (``CanvasSimilarity``).
///
/// Tile content is a software snapshot of the page, captured whenever the tab is
/// switched away from and again when the canvas opens, and kept on disk, so a tile
/// is as fresh as the last time the page was looked at and survives relaunch.
///
/// Instantiated per window and injected via `RefraxEnvironment`.
@Observable
final class TabCanvasManager {
    // MARK: - Dependencies

    @ObservationIgnored
    unowned let tabManager: TabManager

    @ObservationIgnored
    unowned let windowState: WindowState

    @ObservationIgnored
    unowned let pagePool: WebPagePool

    @ObservationIgnored
    unowned let groupManager: TabGroupManager

    // MARK: - Public State

    var showsFloatingControls: Bool {
        !isActive && !windowState.isSpaceLocked
    }

    /// Whether the canvas covers the content area.
    private(set) var isActive = false

    /// The floating layer appears while Control is held or its toolbar button is on.
    private(set) var floatingVisibility = FloatingTabVisibility()

    /// A held reveal key previews adjacent pages while the reading page stays in place.
    var isMomentaryNavigation: Bool {
        floatingVisibility.isHeld && !floatingVisibility.isLatched && !floatingVisibility.isManipulating
    }

    private(set) var focusedFloatingTabID: Tab.ID?
    private(set) var floatingCamera = TabSpatialCamera()
    private(set) var openingCameraFrame: CGRect?
    private(set) var openingFitRect: CGRect?
    var pendingCameraZoom: (factor: CGFloat, point: CGPoint)?
    var regionSelectionError: String?
    var regionSelection: FloatingRegionSelection?
    @ObservationIgnored var regionSelectionTask: Task<Void, Never>?
    var verifiedRegionPages: [TabPage.ID: UUID] = [:]
    var retainedInputTabID: Tab.ID?
    var recentIsOpen = false
    var draggedRecentTabID: Tab.ID?
    var menuTabID: Tab.ID?
    /// The card whose title is being edited; it stays on screen until the edit ends.
    var renamingTabID: Tab.ID?
    var selectedFloatingTabIDs: Set<Tab.ID> = []
    /// The group a dragged card joins if it is let go now; its outline brightens. Setting it
    /// clears ``floatingDropCardID``: a drag has one target at a time.
    var floatingDropGroupID: UUID? {
        didSet { floatingDropCardID = nil }
    }
    /// The loose card a dragged card forms a group with if released here.
    var floatingDropCardID: Tab.ID?
    /// The visible seam between neighboring cards while a drag is ready to connect them.
    var floatingDropBridge: CGRect?
    var floatingDropMovingCardID: Tab.ID?
    var floatingDropAttachedCardID: Tab.ID?
    /// A group whose header shows its name field, as it does right after Group.
    var floatingRenamingGroupID: UUID?
    /// Group header widths as the layer drew them, for hit-testing headers.
    @ObservationIgnored var floatingHeaderWidths: [UUID: CGFloat] = [:]
    /// The selection's options capsule as the layer drew it, for hit-testing.
    @ObservationIgnored var floatingSelectionCapsuleFrame: CGRect = .zero
    /// Where each card of a moving card, group, or selection started.
    @ObservationIgnored var floatingMoveOrigins: [Tab.ID: CGPoint] = [:]
    @ObservationIgnored var floatingMoveBounds: CGRect?

    /// The side a dragged card docks to if it is let go now; the layer draws its silhouette.
    var dockTarget: FloatingDockTarget?
    /// Beams from where a page was docked or undocked to where it went.
    var dockBeams: [FloatingDockBeam] = []
    @ObservationIgnored var dockBeamRevision = 0

    /// The ray the layer draws toward a page that just left the window.
    private(set) var rayRequest: FloatingRayRequest?
    @ObservationIgnored private var rayRevision = 0

    /// Places the outgoing page, positions a linked incoming page beside it, and
    /// points toward the outgoing page when its place is new.
    func tabDisplaced(_ tab: Tab) {
        guard showsFloatingControls, !tab.isFavorite, !tab.isArchived,
              tab.space?.id == windowState.activeSpaceID, tab.id != windowState.activeTabID,
              !tabManager.isShownInAnotherWindow(tab, besides: windowState),
              windowState.pageVisit.destination == nil else { return }
        if storedFloatingPlacement(for: tab) == nil {
            let source = raySource
            let occupied = floatingTabs.filter { $0.id != tab.id && storedFloatingPlacement(for: $0) != nil }.map { floatingPlacement(for: $0) }
            guard let placement = startingPlacement(for: tab, avoiding: occupied) else { return }
            updateFloatingPlacement(placement, for: tab)
            fileIntoSiteStack(tab)
            rayRevision += 1
            rayRequest = FloatingRayRequest(source: source, tabID: tab.id, revision: rayRevision)
        }
        guard let incoming = windowState.activeTab, incoming.space?.id == tab.space?.id,
              !incoming.isFavorite, storedFloatingPlacement(for: incoming) == nil else { return }
        let occupied = floatingTabs.filter { $0.id != incoming.id && storedFloatingPlacement(for: $0) != nil }.map { floatingPlacement(for: $0) }
        let ordered = windowState.activeSpaceTabs
        let parentIndex = ordered.firstIndex { $0.id == tab.id }
        let incomingIndex = ordered.firstIndex { $0.id == incoming.id }
        let parent = parentIndex != nil && incomingIndex == parentIndex.map { $0 + 1 } ? tab : nil
        if let placement = startingPlacement(for: incoming, avoiding: occupied, beside: parent) {
            updateFloatingPlacement(placement, for: incoming)
        }
    }

    /// Clears the ray once the layer has finished drawing that revision.
    func finishRay(_ revision: Int) {
        guard rayRequest?.revision == revision else { return }
        rayRequest = nil
    }

    /// Places a new card beside a neighbor in its group, or in the first free arrange cell.
    func startingPlacement(for tab: Tab, avoiding occupied: [FloatingTabPlacement], beside preferredNeighbor: Tab? = nil) -> FloatingTabPlacement? {
        let bounds = floatingArea
        if let saved = tab.boardFrame {
            var placement = FloatingTabPlacement.initial(index: 0, shape: startingFloatingShape(for: tab))
            placement.previewWidth = saved.width
            placement.previewHeight = saved.height
            placement.tableOrigin = floatingCamera.project(saved).origin
            return placement
        }
        var placement = FloatingTabPlacement.initial(index: 0, shape: startingFloatingShape(for: tab))
        if let origin = adjacentStartingOrigin(for: tab, size: placement.size, avoiding: occupied, beside: preferredNeighbor) {
            placement.tableOrigin = origin
            return placement
        }
        let rail = showsFloatingControls ? windowState.controlIsland.railFrame : .zero
        let pageCard = showsFloatingControls ? windowState.pageCardFrame : .zero
        let arrangeArea = FloatingArrangement.arrangeArea(in: bounds, rail: rail)
        let fromTrailing = FloatingArrangement.fillsFromTrailing(bounds: bounds, rail: rail)
        let taken = occupied.map { $0.frame(in: bounds) }
        let separated = FloatingArrangement.freeCell(
            for: placement.frame(in: bounds).size,
            avoiding: taken.map { $0.insetBy(dx: -Layout.independentPlacementClearance, dy: -Layout.independentPlacementClearance) } + [pageCard],
            in: arrangeArea,
            fromTrailing: fromTrailing,
        )
        guard let origin = separated ?? FloatingArrangement.freeCell(
            for: placement.frame(in: bounds).size,
            avoiding: taken + [pageCard],
            in: arrangeArea,
            fromTrailing: fromTrailing,
        ) else { return nil }
        placement.move(to: origin, in: bounds)
        return placement
    }

    /// Places a new card beside a nearby tab in the same group, keeping every saved card still.
    private func adjacentStartingOrigin(for tab: Tab, size: CGSize, avoiding occupied: [FloatingTabPlacement], beside preferredNeighbor: Tab?) -> CGPoint? {
        let ordered = windowState.activeSpaceTabs
        guard let index = ordered.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let before = ordered[..<index].reversed()
        let after = tab.group == nil ? [] : Array(ordered[(index + 1)...])
        let neighbors = [preferredNeighbor].compactMap { $0 } + Array(before) + Array(after)
        let taken = occupied.map { $0.frame(in: floatingArea) }
        let controls = showsFloatingControls ? [windowState.controlIsland.railFrame, windowState.pageCardFrame] : []
        for neighbor in neighbors where neighbor.group?.id == tab.group?.id {
            guard storedFloatingPlacement(for: neighbor) != nil else { continue }
            let anchor = floatingFrame(for: neighbor, in: floatingArea)
            let gap = FloatingArrangement.gap
            let origins = [
                CGPoint(x: anchor.maxX + gap, y: anchor.minY),
                CGPoint(x: anchor.minX - size.width - gap, y: anchor.minY),
                CGPoint(x: anchor.minX, y: anchor.maxY + gap),
                CGPoint(x: anchor.minX, y: anchor.minY - size.height - gap),
            ]
            if let origin = origins.first(where: { origin in
                let candidate = CGRect(origin: origin, size: size)
                let clearance = gap - 0.5
                return !taken.contains { $0.insetBy(dx: -clearance, dy: -clearance).intersects(candidate) }
                    && !controls.contains { !$0.isEmpty && $0.intersects(candidate) }
            }) {
                return origin
            }
        }
        return nil
    }

    /// The control the ray leaves from: the lens while it is up, else the page card, else the rail.
    private var raySource: CGRect {
        if windowState.showsCommandLens, !windowState.commandLensFrame.isEmpty {
            return windowState.commandLensFrame
        }
        if !windowState.pageCardFrame.isEmpty {
            return windowState.pageCardFrame
        }
        return windowState.controlIsland.hitRegions.first ?? .zero
    }

    /// The window area floating tabs are placed in, in the layer's coordinates.
    var floatingArea: CGRect {
        guard let bounds = windowState.window?.contentView?.bounds, !bounds.isEmpty else { return Layout.nominalFloatingArea }
        return CGRect(origin: .zero, size: bounds.size)
    }

    /// The active space's tabs and the favorites, which keep their place in every space.
    var floatingTabs: [Tab] {
        _ = tabManager.state.tabListVersion
        return (windowState.activeSpaceTabs + tabManager.state.favoriteTabs).filter {
            !$0.isArchived && !tabManager.isShownInAnotherWindow($0, besides: windowState)
        }
    }

    var unplacedFloatingTabs: [Tab] {
        floatingTabs.filter { storedFloatingPlacement(for: $0) == nil }
    }

    func storedFloatingPlacement(for tab: Tab) -> FloatingTabPlacement? {
        windowState.floatingPlacements[tab.id] ?? (tab.space?.dataStoreMode == .private ? nil : tab.floatingPlacement)
    }

    func floatingFrame(for tab: Tab, in area: CGRect) -> CGRect {
        let placement = floatingPlacement(for: tab)
        return placement.frame(in: area)
    }

    /// The card's frame and the outer half of its resize zones: where the pointer reaches it.
    func floatingHitFrame(for tab: Tab, in area: CGRect) -> CGRect {
        let outset = FloatingCardShape.Layout.resizeOutset
        return floatingFrame(for: tab, in: area).insetBy(dx: -outset, dy: -outset)
    }

    var visibleFloatingTabs: [Tab] {
        guard !isActive, regionSelection == nil, !windowState.isSpaceLocked,
              !windowState.showsCommandLens else { return [] }
        let liveBand = floatingArea.insetBy(dx: -floatingArea.width, dy: -floatingArea.height)
        return floatingTabs.filter { tab in
            if tab.id != retainedInputTabID, tab.id != renamingTabID, tab.id != menuTabID,
               !floatingFrame(for: tab, in: floatingArea).intersects(liveBand) {
                return false
            }
            if isFolded(tab), tab.id != retainedInputTabID {
                return false
            }
            // A docked page shows in its column, never as a card.
            if storedFloatingPlacement(for: tab)?.isDocked == true {
                return false
            }
            return (floatingVisibility.isRevealed && !isMomentaryNavigation && storedFloatingPlacement(for: tab) != nil)
                || (floatingPlacement(for: tab).isPinned && tab.id != windowState.activeTabID) || tab.id == retainedInputTabID
                || (windowState.controlIsland.tabInfo.isMenuPresented && tab.id == menuTabID)
                || tab.id == renamingTabID
        }
    }

    /// The shape a card starts in: a live page for a tab the desk shows as a preview, a tab
    /// otherwise.
    func startingFloatingShape(for tab: Tab) -> FloatingCardShape {
        tab.boardFrame == nil || tab.boardIsCompact ? .tab : .live
    }

    func tablePlacement(for tab: Tab) -> FloatingTabPlacement {
        storedFloatingPlacement(for: tab) ?? .initial(
            index: floatingTabs.firstIndex(where: { $0.id == tab.id }) ?? 0,
            count: floatingTabs.count,
            shape: startingFloatingShape(for: tab),
        )
    }

    func floatingPlacement(for tab: Tab) -> FloatingTabPlacement {
        var placement = tablePlacement(for: tab)
        placement.tableOrigin = floatingCamera.project(placement.frame(in: floatingArea)).origin
        return placement
    }

    func updateFloatingPlacement(_ placement: FloatingTabPlacement, for tab: Tab) {
        var world = placement
        world.tableOrigin = floatingCamera.unproject(placement.frame(in: floatingArea)).origin
        storeTablePlacement(world, for: tab)
    }

    func storeTablePlacement(_ placement: FloatingTabPlacement, for tab: Tab) {
        windowState.floatingPlacements[tab.id] = placement
        if isActive {
            tileFrames[tab.id] = placement.frame(in: floatingArea)
        }
        windowState.window?.invalidateRestorableState()
        if tab.space?.dataStoreMode != .private {
            tab.floatingPlacement = placement
        }
        if placement.isPinned || placement.isDocked {
            tabManager.state.pipCoordinator.onTabActivated(tab, in: tabManager.state)
        }
        tabManager.state.scheduleSave()
    }

    /// Changes a card's shape where it stands, with the shape motion.
    func setFloatingShape(_ shape: FloatingCardShape, for tab: Tab, in area: CGRect) {
        var next = floatingPlacement(for: tab)
        next.setShape(shape, in: area)
        withAnimation(Self.shapeAnimation) {
            updateFloatingPlacement(next, for: tab)
        }
    }

    /// The motion of a shape change: frame and radius together on a spring with no bounce.
    /// Under Reduce Motion the frame changes at once and the card's content fades.
    static var shapeAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : FloatingCardShape.Layout.shapeSpring
    }

    func revealFloatingTabs() {
        guard !isActive, !windowState.isSpaceLocked else { return }
        UserDefaults.standard.set(true, forKey: "floatingTabs.hasRecalledPlacement")
        placeFloatingTabs()
        floatingVisibility.hold()
        windowState.controlIsland.tabInfo.hold()
        focusedFloatingTabID = windowState.activeTabID ?? floatingTabs.first?.id
        refreshFloatingSnapshots()
    }

    func releaseFloatingTabs() {
        if let page = windowState.focusedWebPage, page.isInFloatingPreview,
           let responder = windowState.window?.firstResponder as? NSView,
           responder === page.contentView || responder.isDescendant(of: page.contentView) {
            retainedInputTabID = page.tabPage.tab?.id
        }
        floatingVisibility.release()
        windowState.controlIsland.tabInfo.release()
    }
    func dismissFloatingTabs() {
        recentIsOpen = false
        selectedFloatingTabIDs = []
        floatingDropGroupID = nil
        floatingDropBridge = nil
        floatingDropMovingCardID = nil
        floatingDropAttachedCardID = nil
        floatingRenamingGroupID = nil
        retainedInputTabID = nil
        floatingVisibility.dismiss()
        windowState.controlIsland.tabInfo.dismiss()
    }

    /// Keeps the layer up once the reveal key is let go, for work that takes typing.
    func latchFloatingTabs() {
        if !floatingVisibility.isLatched {
            floatingVisibility.toggle()
        }
    }
    var spaceToReveal: Space.ID?

    func floatingSpaceChanged() {
        let shouldReveal = spaceToReveal == windowState.activeSpaceID
        spaceToReveal = nil
        dismissFloatingTabs()
        floatingCamera = TabSpatialCamera()
        if let tab = windowState.activeTab, let viewport = windowState.tableController?.viewportFrame {
            focusPage(tab, in: viewport)
        }
        if shouldReveal {
            toggleFloatingTabs()
        }
    }

    func confirmFloatingPlacement() {
        guard !UserDefaults.standard.bool(forKey: "floatingTabs.hasRecalledPlacement") else { return }
        UserDefaults.standard.set(true, forKey: "floatingTabs.hasRecalledPlacement")
        windowState.showToast("Hold \(FloatingRevealKey.current.title) to find it here again.")
    }
    func beginFloatingManipulation() {
        floatingVisibility.beginManipulation()
    }
    func endFloatingManipulation() {
        floatingVisibility.endManipulation()
    }

    /// All navigation surfaces resolve directional neighbors from the same card rectangles.
    func spatialNeighbor(from id: Tab.ID, toward direction: TableDirection, among ids: Set<Tab.ID>) -> Tab.ID? {
        if floatingTabs.contains(where: { ids.contains($0.id) && storedFloatingPlacement(for: $0) == nil }) {
            placeFloatingTabs()
        }
        let tiles = floatingTabs.filter { ids.contains($0.id) && !isFolded($0) }.map {
            CanvasNavigation.Tile(id: $0.id, frame: tablePlacement(for: $0).frame(in: floatingArea), groupID: $0.group?.id)
        }
        return CanvasNavigation.neighbor(from: id, toward: direction.canvasDirection, in: tiles)
    }

    /// Aligns the selected page's table anchor with its available viewport.
    func focusPage(_ tab: Tab, in viewport: CGRect) {
        guard !isActive, !viewport.isEmpty else { return }
        if storedFloatingPlacement(for: tab)?.tableOrigin == nil {
            placeFloatingTabs()
        }
        let anchor = tablePlacement(for: tab).frame(in: floatingArea).origin
        let scale: CGFloat = isMomentaryNavigation ? Layout.inspectionScale : 1
        let margin = CGSize(width: viewport.width * (1 - scale) / 2, height: viewport.height * (1 - scale) / 2)
        let target = TabSpatialCamera(
            origin: CGPoint(
                x: anchor.x - (viewport.minX + margin.width) / scale,
                y: anchor.y - (viewport.minY + margin.height) / scale,
            ),
            scale: scale,
        )
        focusedFloatingTabID = tab.id
        guard floatingCamera != target else { return }
        let animate = (floatingVisibility.isRevealed || floatingCamera.scale != 1)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animate ? .easeOut(duration: 0.12) : nil) { floatingCamera = target }
    }

    /// The active page and its card share one table anchor and camera projection.
    func pageFrame(for tab: Tab, in viewport: CGRect) -> CGRect {
        let anchor = tablePlacement(for: tab).frame(in: floatingArea).origin
        return floatingCamera.project(CGRect(origin: anchor, size: viewport.size))
            .offsetBy(dx: -viewport.minX, dy: -viewport.minY)
    }

    /// Moves the viewport in screen points while every stored tab keeps its position.
    func panFloatingCamera(by delta: CGPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        if floatingTabs.contains(where: { storedFloatingPlacement(for: $0)?.tableOrigin == nil }) {
            placeFloatingTabs()
        }
        floatingCamera.pan(by: delta)
    }

    /// The overview reports its projection into the shared camera.
    func updateTableCamera(_ camera: TabSpatialCamera) {
        floatingCamera = camera
    }

    func zoomFromPage(by factor: CGFloat, aboutWindowPoint point: CGPoint) {
        if isActive {
            board?.zoom(by: factor, aboutWindowPoint: point)
        } else {
            pendingCameraZoom = (factor, point)
            show()
        }
    }

    /// Moves only the camera to reveal a destination; the saved cards stay on the table.
    func revealSpatialDestination(_ id: Tab.ID) {
        guard let tab = floatingTabs.first(where: { $0.id == id }) else { return }
        focusedFloatingTabID = id
        if isActive {
            board?.reveal(id)
            return
        }
        let frame = tablePlacement(for: tab).frame(in: floatingArea)
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.18)) {
            floatingCamera.reveal(frame, in: floatingArea.insetBy(dx: 32, dy: 32))
        }
    }

    func openFocusedFloatingTab() {
        guard let tab = floatingTabs.first(where: { $0.id == focusedFloatingTabID }) else { return }
        openFloatingTab(tab)
    }

    func closeFloatingTab(_ tab: Tab) {
        tabManager.closeTab(tab)
    }

    func toggleFloatingTabs() {
        guard !windowState.isSpaceLocked else { return }
        if isActive {
            dismiss(activating: nil)
        }
        placeFloatingTabs()
        floatingVisibility.toggle()
        focusedFloatingTabID = windowState.activeTabID ?? floatingTabs.first?.id
        if floatingVisibility.isRevealed {
            refreshFloatingSnapshots()
        }
    }

    func openFloatingTab(_ tab: Tab) {
        floatingVisibility.dismiss()
        tabManager.setActiveTab(tab, in: windowState)
        if let viewport = windowState.tableController?.viewportFrame {
            focusPage(tab, in: viewport)
        }
    }

    func showFloatingPlace(of tab: Tab) {
        if !floatingVisibility.isRevealed {
            toggleFloatingTabs()
        }
        revealSpatialDestination(tab.id)
        if tab.floatingPlacement == nil {
            recentIsOpen = true
        }
    }

    private func placeFloatingTabs() {
        for tab in floatingTabs where windowState.floatingPlacements[tab.id] == nil {
            if let placement = storedFloatingPlacement(for: tab) {
                windowState.floatingPlacements[tab.id] = placement
            }
        }
        var occupied = floatingTabs.filter { storedFloatingPlacement(for: $0) != nil }.map { floatingPlacement(for: $0) }
        for tab in unplacedFloatingTabs {
            guard let placement = startingPlacement(for: tab, avoiding: occupied) else { break }
            updateFloatingPlacement(placement, for: tab)
            occupied.append(floatingPlacement(for: tab))
        }
        for tab in floatingTabs {
            if var placement = storedFloatingPlacement(for: tab), placement.tableOrigin == nil {
                placement.tableOrigin = placement.frame(in: floatingArea).origin
                storeTablePlacement(placement, for: tab)
            }
        }
        var bottom = max(floatingArea.maxY, floatingTabs.compactMap { storedFloatingPlacement(for: $0)?.frame(in: floatingArea).maxY }.max() ?? 0)
        for tab in unplacedFloatingTabs {
            var placement = tablePlacement(for: tab)
            placement.tableOrigin = CGPoint(x: Layout.deskInset, y: bottom + Layout.gap)
            storeTablePlacement(placement, for: tab)
            bottom = placement.frame(in: floatingArea).maxY
        }
        separateCoincidentTabs()
        for tab in floatingTabs where tab.group == nil && storedFloatingPlacement(for: tab) != nil {
            fileIntoSiteStack(tab)
        }
        dissolveLoneSiteStacks()
        tabManager.state.scheduleSave()
    }

    /// Gives cards with the same saved rectangle separate places while keeping their other neighbors fixed.
    private func separateCoincidentTabs() {
        let area = floatingArea
        let tabs = floatingTabs
        let active = tabs.first { $0.id == windowState.activeTabID }
        let ordered = [active].compactMap { $0 } + tabs.filter { $0.id != active?.id }
        var frames = Dictionary(uniqueKeysWithValues: tabs.compactMap { tab in
            storedFloatingPlacement(for: tab).flatMap { $0.isDocked ? nil : (tab.id, $0.frame(in: area)) }
        })
        var visited: [CGRect] = []
        for tab in ordered {
            guard var placement = storedFloatingPlacement(for: tab), !placement.isDocked else { continue }
            let frame = placement.frame(in: area)
            if visited.contains(frame) {
                let occupied = frames.compactMap { $0.key == tab.id ? nil : $0.value }
                let gap = FloatingArrangement.gap
                let candidates = [
                    CGPoint(x: frame.maxX + gap, y: frame.minY),
                    CGPoint(x: frame.minX, y: frame.maxY + gap),
                    CGPoint(x: frame.minX - frame.width - gap, y: frame.minY),
                    CGPoint(x: frame.minX, y: frame.minY - frame.height - gap),
                ]
                let clearance = gap - 0.5
                let clear = candidates.first { origin in
                    let candidate = CGRect(origin: origin, size: frame.size)
                    return !occupied.contains { $0.insetBy(dx: -clearance, dy: -clearance).intersects(candidate) }
                }
                let fallback = FloatingArrangement.freeCell(
                    for: frame.size,
                    avoiding: occupied,
                    in: FloatingArrangement.arrangeArea(in: area, rail: .zero),
                    fromTrailing: false,
                )
                if let origin = clear ?? fallback {
                    placement.tableOrigin = origin
                    storeTablePlacement(placement, for: tab)
                    frames[tab.id] = placement.frame(in: area)
                }
            }
            visited.append(placement.frame(in: area))
        }
    }

    private func refreshFloatingSnapshots() {
        floatingSnapshotTask?.cancel()
        let currentTabs = floatingTabs
        floatingSnapshotTask = Task(name: "Floating tab snapshots") { [weak self] in
            for tab in currentTabs {
                guard !Task.isCancelled, let self else { return }
                if tab.space?.dataStoreMode != .private, snapshots[tab.id] == nil,
                   let data = await CanvasSnapshotStore.load(for: tab.id), let image = NSImage(data: data) {
                    snapshots[tab.id] = image
                }
                guard !Task.isCancelled else { return }
                await refreshSnapshot(for: tab)
            }
        }
    }

    @ObservationIgnored
    private var floatingSnapshotTask: Task<Void, Never>?

    /// Tabs on the desk, in the space's tab order.
    private(set) var tabs: [Tab] = []

    /// Card rectangles in shared table coordinates, also used by the floating layer.
    private(set) var tileFrames: [Tab.ID: CGRect] = [:]

    /// Zones derived from the space's groups and the current tile positions.
    private(set) var zones: [CanvasZone] = []

    /// Magnets derived from the space's groups.
    private(set) var magnets: [CanvasMagnet] = []

    /// Snapshot of each tab's page.
    private(set) var snapshots: [Tab.ID: NSImage] = [:]

    /// Tiles picked up by the lasso.
    private(set) var selectedTabIDs: Set<Tab.ID> = []

    /// The latest camera request; the board flies there once per serial.
    private(set) var zoomRequest: CanvasZoomRequest?

    /// Bumped by ``close()``; the board zooms back into the focused tile once per value.
    private(set) var closeRequest: Int?

    /// A pinch on the page is opening the canvas and has not been released.
    private(set) var isOpeningInteractively = false

    /// The pinch scale of an interactive opening: 1 at its start, smaller as the fingers close.
    @ObservationIgnored
    private(set) var openingScale: CGFloat = 1

    /// ⌃-scrolling on a page is sliding the desk under it.
    private(set) var isPanningFromPage = false

    /// Wheel movement that arrived before the board was on screen.
    @ObservationIgnored
    private(set) var pendingPan: CGPoint = .zero

    /// A one-time hint on screen, if any.
    private(set) var hint: CanvasHint?

    @ObservationIgnored
    private var hintTask: Task<Void, Never>?

    /// Where the live page sat when the canvas opened, in window coordinates. Tiles
    /// align to it, so the focused tile starts exactly over the page it shows.
    @ObservationIgnored
    private(set) var livePageFrame: CGRect?

    /// The tab the board zooms out from on show and back into on dismiss.
    private(set) var focusedTabID: Tab.ID?

    /// The bounded desk for the space on screen.
    private(set) var deskSize = Layout.minimumDeskSize

    /// Tile size, matching the content area's aspect ratio so a zoomed tile lands
    /// exactly on the live page.
    private(set) var tileSize = Layout.defaultTileSize

    /// The board on screen while the canvas is open.
    @ObservationIgnored
    weak var board: (any CanvasBoardDriver)?

    @ObservationIgnored
    private var snapshotTask: Task<Void, Never>?

    @ObservationIgnored
    private var activationTask: Task<Void, Never>?

    @ObservationIgnored
    private var previousActiveTabID: Tab.ID?

    // MARK: - Constants

    /// The canvas's symbol, shared by the menu item, toolbar button, and Command Lens.
    static let symbolName = "rectangle.3.group"

    enum Layout {
        /// Leaves enough table around the reading page to see its adjacent pages.
        static let inspectionScale: CGFloat = 0.84
        static let independentPlacementClearance: CGFloat = 80
        /// The smallest desk; a space with more tabs gets a proportionally larger one.
        static let minimumDeskSize = CGSize(width: 1_280, height: 820)
        /// Free slots in the desk's starting grid per tab, so a space opens with room to
        /// move tiles around rather than packed edge to edge.
        static let slotsPerTab: CGFloat = 1.5
        /// Step by which the desk is scaled up until it holds the space.
        static let deskGrowthStep: CGFloat = 0.1
        static let defaultTileSize = CGSize(width: 320, height: 200)
        static let tileWidth: CGFloat = 320
        static let gap: CGFloat = 48
        /// Margin kept between the desk's edge and auto-placed tiles.
        static let deskInset: CGFloat = 120
        /// Stands in for the window while a placement is chosen before the window has a size.
        static let nominalFloatingArea = CGRect(x: 0, y: 0, width: 1_280, height: 800)
        /// Breathing room around the tiles when zoomed to fit everything.
        static let fitInset: CGFloat = 80
        /// Width of the snapshot image; the tile is scaled from this.
        static let snapshotWidth = 800
        /// How often tiles of pages playing media are re-captured while the board is open.
        static let mediaRefreshInterval: Duration = .seconds(1)
        /// Space between a zone's edge and the tiles inside it.
        static let zonePadding: CGFloat = 24
        /// Extra room at the top of a zone for its name.
        static let zoneHeaderHeight: CGFloat = 36
        /// Room above a tile for its title.
        static let tileTitleHeight: CGFloat = 24
        /// How long a close may take before the canvas closes without the board.
        static let closeFallbackDelay: Duration = .milliseconds(1_500)
        /// How long a one-time hint stays on screen.
        static let hintDuration: Duration = .seconds(4)
        /// Smallest ring a magnet lays its members on.
        static let magnetMinimumRadius: CGFloat = 260
    }

    // MARK: - Initialization

    init(tabManager: TabManager, windowState: WindowState, pagePool: WebPagePool, groupManager: TabGroupManager) {
        self.tabManager = tabManager
        self.windowState = windowState
        self.pagePool = pagePool
        self.groupManager = groupManager

        windowState.tabDisplacedHandler = { [weak self] tab in self?.tabDisplaced(tab) }
        startObservingActivation()
    }

    isolated deinit {
        activationTask?.cancel()
        snapshotTask?.cancel()
        floatingSnapshotTask?.cancel()
    }

    // MARK: - Showing

    func toggle() {
        if isActive {
            close()
        } else {
            show()
        }
    }

    /// Leaves the canvas the way it was entered: the board zooms back into the tab it
    /// opened from, and that page takes over.
    func close() {
        guard isActive else { return }
        let request = (closeRequest ?? 0) + 1
        closeRequest = request
        // The board normally closes the canvas when its flight lands; if it cannot, the
        // canvas closes anyway rather than trapping the window on the desk.
        Task(name: "Canvas close fallback") { [weak self] in
            try? await Task.sleep(for: Layout.closeFallbackDelay)
            guard let self, isActive, closeRequest == request else { return }
            Logger.debug("close fallback after a board that never landed", category: Logger.canvas)
            dismiss(activating: nil)
        }
    }

    // MARK: - Hints

    /// Shows `hint` once ever, for a few seconds.
    func offerHint(_ hint: CanvasHint) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hint.seenKey) else { return }
        defaults.set(true, forKey: hint.seenKey)
        self.hint = hint
        hintTask?.cancel()
        hintTask = Task(name: "Canvas hint") { [weak self] in
            try? await Task.sleep(for: Layout.hintDuration)
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }

    // MARK: - Interactive Opening

    /// A pinch on the page starts opening the canvas under the fingers.
    func beginInteractiveOpen() {
        guard !isActive else { return }
        openingScale = 1
        isOpeningInteractively = true
        show()
    }

    /// The pinch moved to `scale`: 1 at its start, smaller as the fingers close.
    func updateInteractiveOpen(scale: CGFloat) {
        guard isOpeningInteractively else { return }
        openingScale = scale
        board?.setOpeningScale(scale)
    }

    // MARK: - Panning from a Page

    /// ⌃-scrolling on a page brings the desk up at page size, to slide under the wheel.
    func beginPan() {
        guard !isActive else { return }
        pendingPan = .zero
        isPanningFromPage = true
        show()
    }

    /// The wheel moved by `delta` screen points.
    func pan(by delta: CGPoint) {
        guard isPanningFromPage else { return }
        if let board {
            board.pan(by: delta)
        } else {
            pendingPan.x += delta.x
            pendingPan.y += delta.y
        }
    }

    /// A trackpad scroll moves the desk brought up from a page.
    func scroll(by delta: CGPoint) {
        guard isPanningFromPage else { return }
        board?.scroll(by: delta)
    }

    /// Zooms the arrangement around the pointer.
    func zoom(by factor: CGFloat, aboutWindowPoint point: CGPoint) {
        guard isActive else { return }
        board?.zoom(by: factor, aboutWindowPoint: point)
    }

    func step(_ direction: TableDirection) {
        board?.step(direction)
    }

    func zoom(by factor: CGFloat) {
        board?.zoom(by: factor)
    }

    /// The desk brought up from a page settles into a tile and the page takes over.
    func endPan(settlingOn place: CanvasPanSettle) {
        guard isPanningFromPage else { return }
        isPanningFromPage = false
        if let board {
            board.settle(on: place)
        } else {
            dismiss(activating: nil)
        }
    }

    /// The pinch was released: the canvas finishes opening, or goes back to the page.
    func endInteractiveOpen(commit: Bool) {
        guard isOpeningInteractively else { return }
        isOpeningInteractively = false
        if let board {
            board.finishOpening(commit: commit)
        } else if !commit {
            dismiss(activating: nil)
        }
    }

    /// The live page's frame in window coordinates, while it is on screen.
    func currentLivePageFrame() -> CGRect? {
        guard let tab = windowState.activeTab,
              let view = pagePool.existingPage(for: tab.activePage)?.contentView,
              view.window != nil, !view.isHiddenOrHasHiddenAncestor
        else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    /// Whether the live page is at its normal size, so a closing pinch belongs to the
    /// canvas. A WebKit page zoomed in with a pinch zooms back out first.
    var isLivePageAtNormalSize: Bool {
        guard let tab = windowState.activeTab,
              let webView = pagePool.existingPage(for: tab.activePage)?.contentView as? WKWebView
        else { return true }
        return webView.magnification <= 1.001
    }

    /// A tile is being entered: its tab becomes the active one beneath the canvas, so
    /// the page revealed as the canvas fades is that tab's.
    func prepareToEnter(_ tab: Tab) {
        focusedTabID = tab.id
        focusedFloatingTabID = tab.id
        if windowState.activeTab?.id != tab.id {
            tabManager.setActiveTab(tab, in: windowState)
        }
    }

    // MARK: - Showing

    /// Opens the canvas for the active space, optionally flying from the current page to every tab.
    func show(fittingEverything: Bool = false) {
        guard !isActive else { return }
        openingCameraFrame = floatingCamera.unproject(floatingArea)
        openingFitRect = nil
        dismissFloatingTabs()

        focusedTabID = windowState.activeTab?.id
        livePageFrame = currentLivePageFrame()
        tileSize = contentAspectTileSize()
        selectedTabIDs = []
        reloadTabs()
        if fittingEverything {
            openingFitRect = everythingRect
        }
        isActive = true
        offerHint(.leavingCanvas)

        snapshotTask = Task(name: "Canvas snapshots") { [weak self] in
            guard !Task.isCancelled, let self else { return }
            await loadStoredSnapshots()
            await refreshSnapshots()
            await keepMediaTilesFresh()
        }
    }

    /// Closes the canvas, switching to `tab` first when one was chosen.
    func dismiss(activating tab: Tab?) {
        guard isActive else { return }
        if let tab {
            tabManager.setActiveTab(tab, in: windowState)
        }
        floatingCamera.zoom(to: 1, at: CGPoint(x: floatingArea.midX, y: floatingArea.midY))
        openingFitRect = nil
        pendingCameraZoom = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        selectedTabIDs = []
        openingScale = 1
        isPanningFromPage = false
        isOpeningInteractively = false
        isActive = false
    }

    /// Re-reads the space's tabs, places new ones, and rebuilds zones and magnets.
    private func reloadTabs() {
        placeFloatingTabs()
        tabs = floatingTabs.filter { storedFloatingPlacement(for: $0)?.isDocked != true }
        loadTileFrames()
        // The desk is sized when the canvas opens and only grows while it is open, so
        // no tile is ever left beyond its edge.
        let fitted = fittedDeskSize()
        deskSize = isActive
            ? CGSize(width: max(deskSize.width, fitted.width), height: max(deskSize.height, fitted.height))
            : fitted
        rebuildGroups()
    }

    /// The smallest desk, in the minimum desk's proportions, whose starting grid has
    /// ``Layout/slotsPerTab`` slots for every tab and that reaches past every placed tile.
    private func fittedDeskSize() -> CGSize {
        let needed = Int((CGFloat(tabs.count) * Layout.slotsPerTab).rounded(.up))
        var scale: CGFloat = 1
        var size = Layout.minimumDeskSize
        while gridSlots(on: size).columns * gridSlots(on: size).rows < needed {
            scale += Layout.deskGrowthStep
            size = CGSize(width: (Layout.minimumDeskSize.width * scale).rounded(), height: (Layout.minimumDeskSize.height * scale).rounded())
        }
        let placed = tabs.compactMap { tileFrames[$0.id] }
        if let first = placed.first {
            let extent = placed.dropFirst().reduce(first) { $0.union($1) }
            size.width = max(size.width, extent.maxX + Layout.deskInset)
            size.height = max(size.height, extent.maxY + Layout.deskInset)
        }
        return size
    }

    /// Columns and rows of the grid new tiles are placed on.
    private func gridSlots(on desk: CGSize) -> (columns: Int, rows: Int, step: CGSize) {
        let step = CGSize(width: tileSize.width + Layout.gap, height: tileSize.height + Layout.gap * 1.5)
        let columns = max(1, Int((desk.width - Layout.deskInset * 2 + Layout.gap) / step.width))
        let rows = max(1, Int((desk.height - Layout.deskInset * 2 + Layout.gap) / step.height))
        return (columns, rows, step)
    }

    // MARK: - Tiles

    /// Records where tiles came to rest, and reshapes the zones around them.
    func settleTiles(_ frames: [Tab.ID: CGRect]) {
        for (tabID, frame) in frames {
            moveTile(tabID, to: frame)
        }
        rebuildGroups()
    }

    private func moveTile(_ tabID: Tab.ID, to frame: CGRect) {
        guard let tab = tab(for: tabID) else { return }
        var placement = tablePlacement(for: tab)
        placement.tableOrigin = frame.origin
        storeTablePlacement(placement, for: tab)
        tileFrames[tabID] = placement.frame(in: floatingArea)
        deskSize.width = max(deskSize.width, frame.maxX + Layout.deskInset)
        deskSize.height = max(deskSize.height, frame.maxY + Layout.deskInset)
    }

    /// Changes presentation in the shared arrangement while keeping the leading corner fixed.
    func togglePreview(_ tabID: Tab.ID, at frame: CGRect) {
        guard let tab = tab(for: tabID) else { return }
        var placement = tablePlacement(for: tab)
        placement.tableOrigin = frame.origin
        placement.shape = placement.shape == .live ? .tab : .live
        storeTablePlacement(placement, for: tab)
        reloadTabs()
    }

    var selectionIsCompact: Bool {
        !selectedTabs.isEmpty && selectedTabs.allSatisfy { floatingPlacement(for: $0).shape != .live }
    }

    func toggleSelectedPreviews() {
        let shape: FloatingCardShape = selectionIsCompact ? .live : .tab
        for tab in selectedTabs {
            var placement = tablePlacement(for: tab)
            placement.shape = shape
            storeTablePlacement(placement, for: tab)
        }
        reloadTabs()
    }

    /// Settles a dropped tile: it joins the zone it landed in, or leaves the one it left.
    func finishTileDrag(_ tabID: Tab.ID) {
        defer { rebuildGroups() }
        guard let tab = tab(for: tabID), let frame = tileFrames[tabID] else { return }

        let target = zone(containing: CGPoint(x: frame.midX, y: frame.midY))
        let targetGroup = target.flatMap { group(for: $0.id) }
        guard tab.group?.id != targetGroup?.id else { return }
        // Magnet members stay with their magnet unless dropped into a zone.
        if tab.group?.isMagnet == true, targetGroup == nil {
            return
        }

        groupManager.moveTabToGroup(tab, group: targetGroup, in: windowState.activeSpace)
    }

    /// The tile of the focused tab, or the first tile.
    var focusedTileFrame: CGRect? {
        if let focusedTabID, let frame = tileFrames[focusedTabID] {
            return frame
        }
        return tabs.first.flatMap { tileFrames[$0.id] }
    }

    /// The whole table, including its edges, anchors the overview.
    var deskBounds: CGRect {
        CGRect(origin: .zero, size: deskSize)
    }

    /// Tiles are still moving; ``tileFrames`` holds where they last came to rest.
    var isSettling: Bool {
        board?.isSimulating ?? false
    }

    /// The destination shown by keyboard navigation or a page peek.
    var navigationTabID: Tab.ID? {
        isActive ? board?.navigationTabID : nil
    }

    /// Pairs of tiles whose collision boxes overlap. Zero on a settled desk.
    var overlappingPairCount: Int {
        let boxes = tabs.compactMap { tileFrames[$0.id] }
            .map { CanvasPhysics.collisionBox($0).insetBy(dx: CanvasPhysics.Constants.slop, dy: CanvasPhysics.Constants.slop) }
        var count = 0
        for i in boxes.indices {
            for j in (i + 1) ..< boxes.count where boxes[i].intersects(boxes[j]) {
                count += 1
            }
        }
        return count
    }

    /// Drags a tile as a pointer would, then waits for the desk to come to rest.
    /// Returns false when the canvas is not on screen or the desk never settled.
    func performDrag(_ tabID: Tab.ID, to origin: CGPoint, duration: TimeInterval, fling: Bool) async -> Bool {
        guard isActive, let board else { return false }
        await board.drag(tabID, to: origin, duration: duration, fling: fling)
        return await waitUntilSettled()
    }

    /// Waits for the physics to stop moving tiles, up to `timeout`.
    func waitUntilSettled(timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while isSettling {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    // MARK: - Selection

    func select(_ tabIDs: Set<Tab.ID>) {
        selectedTabIDs = tabIDs.intersection(tabs.map(\.id))
    }

    func clearSelection() {
        selectedTabIDs = []
    }

    var selectedTabs: [Tab] {
        tabs.filter { selectedTabIDs.contains($0.id) }
    }

    var selectionBounds: CGRect? {
        let frames = selectedTabs.compactMap { tileFrames[$0.id] }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    func zoomToSelection() {
        guard let bounds = selectionBounds else { return }
        requestZoom(to: bounds.insetBy(dx: -Layout.fitInset, dy: -Layout.fitInset))
    }

    /// Fits every tile and zone in view; the desk itself when it holds none.
    func zoomToEverything() {
        requestZoom(to: everythingRect)
    }

    private var everythingRect: CGRect {
        let content = (Array(tileFrames.values) + zones.map(\.frame)).reduce(CGRect.null) { $0.union($1) }
        return content.isNull ? deskBounds : content.insetBy(dx: -Layout.fitInset, dy: -Layout.fitInset)
    }

    private func requestZoom(to rect: CGRect) {
        zoomRequest = CanvasZoomRequest(serial: (zoomRequest?.serial ?? 0) + 1, rect: rect)
    }

    func closeSelected() {
        let closing = selectedTabs
        guard !closing.isEmpty else { return }
        tabManager.closeTabs(closing)
        selectedTabIDs = []
        reloadTabs()
    }

    /// Puts the selection into a new zone claiming the area the tiles occupy.
    func groupSelected() {
        let members = selectedTabs
        guard !members.isEmpty, let bounds = selectionBounds,
              let group = try? groupManager.createGroup(in: windowState.activeSpace, name: "Group", color: Self.nextGroupColor())
        else { return }

        for tab in members {
            groupManager.moveTabToGroup(tab, group: group, in: windowState.activeSpace)
        }
        group.boardFrame = bounds.insetBy(dx: -Layout.zonePadding, dy: -Layout.zonePadding)
        tabManager.state.scheduleSave()
        selectedTabIDs = []
        rebuildGroups()
    }

    /// Turns the selection into a magnet at its center, then lets it attract similar tabs.
    func makeMagnetFromSelected() {
        let members = selectedTabs
        guard !members.isEmpty, let bounds = selectionBounds else { return }

        let keys = Set(members.compactMap(CanvasSimilarity.key(for:)))
        let name = keys.count == 1 ? keys.first! : "Magnet"
        guard let group = try? groupManager.createGroup(in: windowState.activeSpace, name: name, color: Self.nextGroupColor()) else { return }

        group.boardAnchor = CGPoint(x: bounds.midX, y: bounds.midY)
        for tab in members {
            groupManager.moveTabToGroup(tab, group: group, in: windowState.activeSpace)
        }
        attractSimilarTabs(to: group)
        arrangeMembers(of: group)
        selectedTabIDs = []
        rebuildGroups()
    }

    // MARK: - Zones and Magnets

    /// Moves a zone and everything in it.
    func moveZone(_ groupID: UUID, by delta: CGPoint) {
        guard let zone = zones.first(where: { $0.id == groupID }) else { return }
        for tabID in zone.memberTabIDs {
            if let frame = tileFrames[tabID] {
                moveTile(tabID, to: frame.offsetBy(dx: delta.x, dy: delta.y))
            }
        }
        for group in groups() where group.id == groupID || descendantGroupIDs(of: groupID).contains(group.id) {
            if let claimed = group.boardFrame {
                group.boardFrame = claimed.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
        rebuildGroups()
    }

    /// Moves a magnet and its ring of members.
    func moveMagnet(_ groupID: UUID, by delta: CGPoint) {
        guard let group = group(for: groupID), let anchor = group.boardAnchor,
              let magnet = magnets.first(where: { $0.id == groupID }) else { return }
        group.boardAnchor = CGPoint(x: anchor.x + delta.x, y: anchor.y + delta.y)
        for tabID in magnet.memberTabIDs {
            if let frame = tileFrames[tabID] {
                moveTile(tabID, to: frame.offsetBy(dx: delta.x, dy: delta.y))
            }
        }
        rebuildGroups()
    }

    /// Pulls in every ungrouped tab similar to the magnet's members and re-forms the ring.
    func attract(_ groupID: UUID) {
        guard let group = group(for: groupID), group.isMagnet else { return }
        attractSimilarTabs(to: group)
        arrangeMembers(of: group)
        rebuildGroups()
    }

    private func attractSimilarTabs(to group: TabGroup) {
        let memberKeys = Set(tabs.filter { $0.group?.id == group.id }.compactMap(CanvasSimilarity.key(for:)))
        guard !memberKeys.isEmpty else { return }
        for tab in tabs where tab.group == nil {
            if let key = CanvasSimilarity.key(for: tab), memberKeys.contains(key) {
                groupManager.moveTabToGroup(tab, group: group, in: windowState.activeSpace)
            }
        }
    }

    /// Lays a magnet's members on a ring around its anchor.
    private func arrangeMembers(of group: TabGroup) {
        guard let anchor = group.boardAnchor else { return }
        let members = tabs.filter { $0.group?.id == group.id }
        guard !members.isEmpty else { return }

        let circumference = CGFloat(members.count) * (tileSize.width + Layout.gap)
        let radius = max(Layout.magnetMinimumRadius, circumference / (2 * .pi))
        for (index, tab) in members.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(index) / CGFloat(members.count) * 2 * .pi
            let center = CGPoint(x: anchor.x + cos(angle) * radius, y: anchor.y + sin(angle) * radius)
            let size = tileFrames[tab.id]?.size ?? tileSize
            moveTile(tab.id, to: CGRect(
                x: (center.x - size.width / 2).rounded(),
                y: (center.y - size.height / 2).rounded(),
                width: size.width,
                height: size.height,
            ))
        }
    }

    private static let groupColors: [GroupColor] = [.pelorus, .coral, .emerald, .violet, .flamingo, .turquoise, .orchid, .avocado]
    private static var nextColorIndex = 0

    static var pendingGroupColor: String {
        groupColors[nextColorIndex % groupColors.count].rawValue
    }

    static func nextGroupColor() -> String {
        let color = pendingGroupColor
        nextColorIndex += 1
        return color
    }

    // MARK: - Lookup

    private func tab(for id: Tab.ID) -> Tab? {
        tabs.first { $0.id == id }
    }

    private func groups() -> [TabGroup] {
        windowState.activeSpaceGroups.filter { !$0.isArchive }
    }

    private func group(for id: UUID) -> TabGroup? {
        groups().first { $0.id == id }
    }

    private func descendantGroupIDs(of groupID: UUID) -> Set<UUID> {
        let all = groups()
        var result = Set<UUID>()
        var frontier = [groupID]
        while let current = frontier.popLast() {
            for child in all where child.parentGroupID == current && !result.contains(child.id) {
                result.insert(child.id)
                frontier.append(child.id)
            }
        }
        return result
    }

    /// The deepest zone whose rectangle contains `point`.
    private func zone(containing point: CGPoint) -> CanvasZone? {
        zones.filter { $0.frame.contains(point) }.max { $0.depth < $1.depth }
    }

    // MARK: - Placement

    private func loadTileFrames() {
        tileFrames = Dictionary(uniqueKeysWithValues: tabs.compactMap { tab in
            storedFloatingPlacement(for: tab).map { (tab.id, $0.frame(in: floatingArea)) }
        })
    }

    private func contentAspectTileSize() -> CGSize {
        guard let activeTab = windowState.activeTab,
              let page = pagePool.existingPage(for: activeTab.activePage) else {
            return Layout.defaultTileSize
        }
        let bounds = page.contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return Layout.defaultTileSize }
        let height = (Layout.tileWidth * bounds.height / bounds.width).rounded()
        return CGSize(width: Layout.tileWidth, height: height)
    }

    // MARK: - Group Shapes

    /// Recomputes every zone and magnet from the groups and the current tile positions.
    ///
    /// A zone is the union of the group's claimed rectangle, its own tiles (padded,
    /// with room for their titles), and its child zones. Groups with neither a claim
    /// nor members have no zone. Groups with an anchor are magnets instead.
    private func rebuildGroups() {
        let all = groups()
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var frames: [UUID: CGRect] = [:]
        var members: [UUID: [Tab.ID]] = [:]

        func depth(of group: TabGroup) -> Int {
            var depth = 0
            var parent = group.parentGroupID.flatMap { byID[$0] }
            while let current = parent {
                depth += 1
                parent = current.parentGroupID.flatMap { byID[$0] }
            }
            return depth
        }

        func resolve(_ group: TabGroup) -> CGRect? {
            if let frame = frames[group.id] {
                return frame
            }
            var rects: [CGRect] = []
            var tabIDs: [Tab.ID] = []
            if let claimed = group.boardFrame {
                rects.append(claimed)
            }
            for tab in tabs where tab.group?.id == group.id {
                if let frame = tileFrames[tab.id] {
                    var padded = frame.insetBy(dx: -Layout.zonePadding, dy: -Layout.zonePadding)
                    padded.origin.y -= Layout.tileTitleHeight
                    padded.size.height += Layout.tileTitleHeight
                    rects.append(padded)
                    tabIDs.append(tab.id)
                }
            }
            for child in all where child.parentGroupID == group.id && !child.isMagnet {
                if let childFrame = resolve(child) {
                    rects.append(childFrame.insetBy(dx: -Layout.zonePadding, dy: -Layout.zonePadding))
                    tabIDs.append(contentsOf: members[child.id] ?? [])
                }
            }
            guard let first = rects.first else { return nil }
            var union = rects.dropFirst().reduce(first) { $0.union($1) }
            union.origin.y -= Layout.zoneHeaderHeight
            union.size.height += Layout.zoneHeaderHeight
            frames[group.id] = union
            members[group.id] = tabIDs
            return union
        }

        zones = all.filter { !$0.isMagnet }.compactMap { group in
            guard let frame = resolve(group) else { return nil }
            return CanvasZone(
                id: group.id,
                name: group.name,
                color: NSColor(group.color),
                frame: frame,
                depth: depth(of: group),
                memberTabIDs: members[group.id] ?? [],
            )
        }
        .sorted { $0.depth < $1.depth }

        magnets = all.compactMap { group in
            guard let anchor = group.boardAnchor else { return nil }
            return CanvasMagnet(
                id: group.id,
                name: group.name,
                color: NSColor(group.color),
                anchor: anchor,
                memberTabIDs: tabs.filter { $0.group?.id == group.id }.map(\.id),
            )
        }
    }

    // MARK: - Snapshots

    /// Captures a tab's page as it is switched away from, so its tile shows what was last seen.
    private func startObservingActivation() {
        let getActiveTabID = { [weak windowState] in windowState?.activeTabID }
        let changes = Observations { getActiveTabID() }

        activationTask = Task { [weak self] in
            for await activeTabID in changes {
                guard let self else { return }
                if let previous = previousActiveTabID, previous != activeTabID,
                   let tab = tabManager.state.tab(for: previous) {
                    await refreshSnapshot(for: tab)
                }
                previousActiveTabID = activeTabID
            }
        }
    }

    /// Fills tiles from disk for tabs without an in-memory snapshot.
    private func loadStoredSnapshots() async {
        for tab in tabs {
            guard !Task.isCancelled else { return }
            guard tab.space?.dataStoreMode != .private, snapshots[tab.id] == nil else { continue }
            let id = tab.id
            if let data = await CanvasSnapshotStore.load(for: id), !Task.isCancelled, let image = NSImage(data: data) {
                snapshots[id] = image
            }
        }
    }

    /// Captures every live page. WebKit paints the snapshot in the web process from
    /// the frame's contents, so pages that are not on screen can be captured too.
    private func refreshSnapshots() async {
        for tab in tabs {
            guard !Task.isCancelled else { return }
            await refreshSnapshot(for: tab)
        }
    }

    /// Pages playing media change under their snapshot; re-capture them while the board is open.
    private func keepMediaTilesFresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Layout.mediaRefreshInterval)
            guard !Task.isCancelled else { return }
            for tab in tabs {
                guard !Task.isCancelled else { return }
                if pagePool.existingPage(for: tab.activePage)?.isPlayingAudio == true {
                    await refreshSnapshot(for: tab)
                }
            }
        }
    }

    func refreshSnapshot(for tab: Tab) async {
        guard let page = pagePool.existingPage(for: tab.activePage) else { return }
        let bounds = page.contentView.bounds
        guard bounds.width > 0, bounds.height > 0,
              let captured = try? await page.snapshot(), !Task.isCancelled,
              let image = captured.scaled(toWidth: CGFloat(Layout.snapshotWidth)) else { return }
        snapshots[tab.id] = image
        if tab.space?.dataStoreMode != .private, let tiff = image.tiffRepresentation {
            await CanvasSnapshotStore.save(tiff: tiff, for: tab.id)
        }
    }
}
