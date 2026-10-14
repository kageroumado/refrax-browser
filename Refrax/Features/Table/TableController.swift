import AppKit
import SwiftUI

/// Routes page-level navigation to the shared tab table and keeps page snapshots.
@MainActor
@Observable
final class TableController {
    private enum Layout {
        static let snapshotLimit = 12
        static let moveStep: CGFloat = 24
        static let gestureStepDistance: CGFloat = 48
        static let smoothWheelFirstStepDistance: CGFloat = 16
    }

    private(set) var viewport: CGSize = .zero
    @ObservationIgnored private(set) var viewportFrame: CGRect = .zero
    private(set) var isMoving = false
    private(set) var blockedDirection: TableDirection?
    private(set) var approachDirection: TableDirection?
    private(set) var approachFraction: CGFloat = 0
    @ObservationIgnored private var gestureDistance: CGFloat = 0
    @ObservationIgnored private var gestureDirection: TableDirection?
    @ObservationIgnored private var gestureHasStepped = false
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

    func canSlide(atWindowPoint point: CGPoint) -> Bool {
        guard let window = windowState.window, let content = window.contentView,
              !windowState.showsCommandLens, !windowState.isSpaceLocked,
              window.attachedSheet == nil, !canvas.isActive, currentTab != nil else { return false }
        let local = content.convert(point, from: nil)
        let topLeft = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
        return viewportFrame.contains(topLeft)
    }

    func updateViewport(_ frame: CGRect) {
        viewportFrame = frame
        viewport = frame.size
    }

    func beginPan(_ delta: CGSize, shift: Bool = false, source: TableScrollSource = .trackpad) {
        isMoving = true
        gestureDistance = 0
        gestureDirection = nil
        gestureHasStepped = false
        approachDirection = nil
        approachFraction = 0
        pan(delta, shift: shift, source: source)
    }

    func pan(_ delta: CGSize, shift: Bool = false, source: TableScrollSource = .trackpad) {
        guard isMoving,
              let direction = TableDirection.wheelStep(deltaX: delta.width, deltaY: delta.height, shift: shift) else { return }
        if direction != gestureDirection {
            gestureDistance = 0
            gestureDirection = direction
            gestureHasStepped = false
        }
        gestureDistance += abs(abs(delta.width) > abs(delta.height) ? delta.width : delta.height)
        let threshold = source == .smoothWheel && !gestureHasStepped
            ? Layout.smoothWheelFirstStepDistance : Layout.gestureStepDistance
        if gestureDistance >= threshold {
            gestureDistance = gestureDistance.truncatingRemainder(dividingBy: threshold)
            gestureHasStepped = true
            step(direction)
        }
        approachDirection = direction
        approachFraction = min(1, gestureDistance / threshold)
    }

    func endPan() {
        isMoving = false
        gestureDistance = 0
        gestureDirection = nil
        gestureHasStepped = false
        approachDirection = nil
        approachFraction = 0
    }

    func destination(toward direction: TableDirection) -> Tab? {
        guard let current = navigationTabID else { return nil }
        let ids = Set(canvas.floatingTabs.filter { canvas.tablePlacement(for: $0).isDocked == false }.map(\.id))
        guard let target = canvas.spatialNeighbor(from: current, toward: direction, among: ids) else { return nil }
        return canvas.floatingTabs.first { $0.id == target }
    }

    /// Every wheel step follows the destination displayed at the page edge.
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
        canvas.revealSpatialDestination(tab.id)
        tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
    }

    func clearBlockedDirection() {
        blockedDirection = nil
    }

    func zoom(by factor: CGFloat, at point: CGPoint) {
        canvas.zoomFromPage(by: factor, aboutWindowPoint: point)
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
