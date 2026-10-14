import AppKit
import SwiftUI

/// Routes page-level navigation to the shared tab table and keeps page snapshots.
@MainActor
@Observable
final class TableController {
    static let pageTravelAnimationDuration: TimeInterval = 0.32

    private enum Layout {
        static let snapshotLimit = 12
        static let moveStep: CGFloat = 24
        static let pageTravelDuration: Duration = .milliseconds(320)
    }

    private(set) var viewport: CGSize = .zero
    @ObservationIgnored private(set) var viewportFrame: CGRect = .zero
    private(set) var blockedDirection: TableDirection?
    private(set) var departingTab: Tab?
    private(set) var departingSnapshot: NSImage?
    private(set) var pageTravelOpacity: Double = 0
    @ObservationIgnored private var pageTravelTask: Task<Void, Never>?
    private var captures: [UUID: NSImage] = [:]
    @ObservationIgnored private var captureOrder: [UUID] = []
    @ObservationIgnored private var capturing: Set<UUID> = []
    @ObservationIgnored private unowned let windowState: WindowState
    @ObservationIgnored private unowned let tabManager: TabManager
    @ObservationIgnored private unowned let canvas: TabCanvasManager
    @ObservationIgnored private unowned let pagePool: WebPagePool

    init(windowState: WindowState, tabManager: TabManager, canvas: TabCanvasManager, pagePool: WebPagePool) {
        self.windowState = windowState
        self.tabManager = tabManager
        self.canvas = canvas
        self.pagePool = pagePool
    }

    var currentTab: Tab? {
        windowState.activeTab
    }
    var navigationTabID: UUID? {
        windowState.activeTabID
    }

    func holds(_ tab: Tab) -> Bool {
        canvas.floatingTabs.contains { $0.id == tab.id }
    }

    func updateViewport(_ frame: CGRect) {
        viewportFrame = frame
        viewport = frame.size
    }

    func destination(toward direction: TableDirection) -> Tab? {
        guard let current = navigationTabID else { return nil }
        let ids = Set(canvas.floatingTabs.filter { canvas.tablePlacement(for: $0).isDocked == false }.map(\.id))
        guard let target = canvas.spatialNeighbor(from: current, toward: direction, among: ids) else { return nil }
        return canvas.floatingTabs.first { $0.id == target }
    }

    /// Opens the neighbor displayed at the page edge.
    func step(_ direction: TableDirection) {
        if canvas.isActive {
            blockedDirection = nil
            canvas.step(direction)
            return
        }
        guard let tab = destination(toward: direction) else {
            blockedDirection = direction
            return
        }
        blockedDirection = nil
        pageTravelTask?.cancel()
        departingTab = currentTab
        departingSnapshot = currentTab.flatMap { snapshot(for: $0.id) }
        pageTravelOpacity = 1
        tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
        pageTravelTask = Task(name: "Finish table page travel") { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Self.pageTravelAnimationDuration)) {
                self.pageTravelOpacity = 0
            }
            try? await Task.sleep(for: Layout.pageTravelDuration)
            guard !Task.isCancelled else { return }
            self.departingTab = nil
            self.departingSnapshot = nil
        }
    }

    func clearBlockedDirection() {
        blockedDirection = nil
    }

    /// Moves the selected tab on the same table used by cards and overview.
    func moveFocusedSlab(_ direction: TableDirection) {
        guard let tab = currentTab else { return }
        var placement = canvas.tablePlacement(for: tab)
        var origin = placement.frame(in: canvas.floatingArea).origin
        switch direction {
        case .left: origin.x -= Layout.moveStep
        case .right: origin.x += Layout.moveStep
        case .up: origin.y -= Layout.moveStep
        case .down: origin.y += Layout.moveStep
        }
        placement.tableOrigin = origin
        canvas.storeTablePlacement(placement, for: tab)
        canvas.revealSpatialDestination(tab.id)
    }

    func cycleWidth() {
        guard let tab = currentTab else { return }
        setWidth((width(of: tab) ?? .third).next, of: tab)
    }

    func toggleFill() {
        guard let tab = currentTab else { return }
        var placement = canvas.tablePlacement(for: tab)
        placement.shape = .live
        if let width = placement.previewWidthBeforeFill {
            placement.previewWidth = width
            placement.previewWidthBeforeFill = nil
        } else {
            placement.previewWidthBeforeFill = placement.size.width
            placement.previewWidth = canvas.floatingArea.width
        }
        canvas.storeTablePlacement(placement, for: tab)
        canvas.revealSpatialDestination(tab.id)
    }

    func setWidth(_ width: TableWidth, of tab: Tab) {
        var placement = canvas.tablePlacement(for: tab)
        placement.shape = .live
        placement.previewWidthBeforeFill = nil
        placement.previewWidth = max(FloatingCardShape.live.minimumSize.width, canvas.floatingArea.width * width.fraction)
        canvas.storeTablePlacement(placement, for: tab)
        canvas.revealSpatialDestination(tab.id)
    }

    func width(of tab: Tab) -> TableWidth? {
        guard holds(tab) else { return nil }
        let fraction = canvas.tablePlacement(for: tab).size.width / canvas.floatingArea.width
        return TableWidth.allCases.min { abs($0.fraction - fraction) < abs($1.fraction - fraction) }
    }

    func snapshot(for tabID: UUID) -> NSImage? {
        captures[tabID] ?? canvas.snapshots[tabID]
    }

    /// Captures the page after its first presentation so adjacent previews show its contents.
    func captureSnapshot(of tab: Tab) async {
        guard !capturing.contains(tab.id), let page = pagePool.existingPage(for: tab.activePage),
              page.url != nil else { return }
        capturing.insert(tab.id)
        defer { capturing.remove(tab.id) }
        let deadline = ContinuousClock.now + .seconds(10)
        while page.isLoading && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }
        guard !page.isLoading else { return }
        await page.waitForPresentationUpdate()
        let bounds = page.contentView.bounds
        guard !Task.isCancelled, bounds.width > 0, bounds.height > 0,
              let image = try? await page.snapshot() else { return }
        store(image, for: tab.id)
    }

    /// Fills in a slab or card with no image from the canvas snapshot stored on disk.
    func requestStoredSnapshot(for tab: Tab) {
        guard snapshot(for: tab.id) == nil, !capturing.contains(tab.id), tab.space?.dataStoreMode != .private else { return }
        let id = tab.id
        capturing.insert(id)
        Task(name: "Load table snapshot") { [weak self] in
            let data = await CanvasSnapshotStore.load(for: id)
            guard let self, !Task.isCancelled else { return }
            if let data, let image = NSImage(data: data), captures[id] == nil {
                store(image, for: id)
            }
            capturing.remove(id)
        }
    }

    private func store(_ image: NSImage, for tabID: UUID) {
        captures[tabID] = image
        captureOrder.removeAll { $0 == tabID }
        captureOrder.append(tabID)
        while captureOrder.count > Layout.snapshotLimit {
            captures.removeValue(forKey: captureOrder.removeFirst())
        }
    }
}
