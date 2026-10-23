import AppKit
import Observation
import SwiftUI
import WebKit

/// Manages a window's floating layer: the tabs taken out of their islands as cards over the
/// page, the pages docked to the window's sides, and the reveal that shows islands and cards
/// while the reveal key is held or the layer is latched.
///
/// A card keeps the placement it was given (persisted on ``Tab/floatingPlacement``). A click
/// opens that tab's page. A card shows a snapshot of its page, captured whenever the tab is
/// switched away from and again when the layer is revealed, and kept on disk, until its page
/// is live.
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

    // MARK: - Public State

    var showsFloatingControls: Bool {
        !windowState.isSpaceLocked
    }

    /// The page is shown as its image, a slab over the window's background.
    var showsPageSlab = false

    /// The control rail shows whenever the floating controls do: it is the window's chrome and
    /// stays through a slab, which it never hides.
    var showsControlIsland: Bool {
        showsFloatingControls
    }

    /// The floating layer appears while Control is held or its toolbar button is on.
    private(set) var floatingVisibility = FloatingTabVisibility()

    /// A held reveal key previews adjacent pages while the reading page stays in place.
    var isMomentaryNavigation: Bool {
        floatingVisibility.isHeld && !floatingVisibility.isLatched && !floatingVisibility.isManipulating
    }

    private(set) var focusedFloatingTabID: Tab.ID?
    var regionSelectionError: String?
    var regionSelection: FloatingRegionSelection?
    @ObservationIgnored var regionSelectionTask: Task<Void, Never>?
    var verifiedRegionPages: [TabPage.ID: UUID] = [:]
    var retainedInputTabID: Tab.ID?
    var menuTabID: Tab.ID?
    /// The card whose title is being edited; it stays on screen until the edit ends.
    var renamingTabID: Tab.ID?
    /// Takes a card released at a point: true when an island took it in as a row.
    @ObservationIgnored var islandDrop: ((Tab, CGPoint) -> Bool)?

    /// The side a dragged card docks to if it is let go now; the layer draws its silhouette.
    var dockTarget: FloatingDockTarget?

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

    /// The cards on screen: the tabs taken out of their islands, other than the window's page.
    var visibleFloatingTabs: [Tab] {
        guard regionSelection == nil, !windowState.isSpaceLocked, !windowState.showsCommandLens else { return [] }
        return (windowState.islandController?.detachedTabs ?? []).filter { $0.id != windowState.activeTabID }
    }

    /// The shape a card starts in: a live page for a tab saved as a preview, a tab otherwise.
    func startingFloatingShape(for tab: Tab) -> FloatingCardShape {
        tab.boardFrame == nil || tab.boardIsCompact ? .tab : .live
    }

    /// The tab's placement, anchored at the point its frame has in the window.
    func floatingPlacement(for tab: Tab) -> FloatingTabPlacement {
        var placement = storedFloatingPlacement(for: tab) ?? .initial(
            index: floatingTabs.firstIndex(where: { $0.id == tab.id }) ?? 0,
            count: floatingTabs.count,
            shape: startingFloatingShape(for: tab),
        )
        placement.tableOrigin = placement.frame(in: floatingArea).origin
        return placement
    }

    /// Keeps a card's placement. While a drag is under way only the window's copy changes,
    /// which is what the layer draws; the tab and the store take the placement when the drag
    /// ends, through `persisting`.
    func updateFloatingPlacement(_ placement: FloatingTabPlacement, for tab: Tab, persisting: Bool = true) {
        var stored = placement
        stored.tableOrigin = placement.frame(in: floatingArea).origin
        windowState.floatingPlacements[tab.id] = stored
        guard persisting else { return }
        windowState.window?.invalidateRestorableState()
        if tab.space?.dataStoreMode != .private {
            tab.floatingPlacement = stored
        }
        if stored.isPinned || stored.isDocked {
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

    // MARK: - Revealing

    func revealFloatingTabs() {
        guard !windowState.isSpaceLocked else { return }
        UserDefaults.standard.set(true, forKey: "floatingTabs.hasRecalledPlacement")
        floatingVisibility.hold()
        windowState.controlIsland.tabInfo.hold()
        focusedFloatingTabID = windowState.activeTabID ?? floatingTabs.first?.id
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

    func openFocusedFloatingTab() {
        guard let tab = floatingTabs.first(where: { $0.id == focusedFloatingTabID }) else { return }
        openFloatingTab(tab)
    }

    func closeFloatingTab(_ tab: Tab) {
        tabManager.closeTab(tab)
    }

    func toggleFloatingTabs() {
        guard !windowState.isSpaceLocked else { return }
        floatingVisibility.toggle()
        focusedFloatingTabID = windowState.activeTabID ?? floatingTabs.first?.id
    }

    func openFloatingTab(_ tab: Tab) {
        floatingVisibility.dismiss()
        tabManager.setActiveTab(tab, in: windowState)
    }

    /// Reveals the layer with `tab`'s card in front.
    func showFloatingPlace(of tab: Tab) {
        if !floatingVisibility.isRevealed {
            toggleFloatingTabs()
        }
        focusedFloatingTabID = tab.id
    }

    enum Layout {
        /// Stands in for the window while a placement is chosen before the window has a size.
        static let nominalFloatingArea = CGRect(x: 0, y: 0, width: 1_280, height: 800)
    }

    // MARK: - Initialization

    init(tabManager: TabManager, windowState: WindowState, pagePool: WebPagePool) {
        self.tabManager = tabManager
        self.windowState = windowState
        self.pagePool = pagePool
    }

    isolated deinit {
    }
}
