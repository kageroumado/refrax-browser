import AppKit
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct SharedTableTests {
    @Test
    func `edge previews retain their neighbors' row and column positions`() {
        let viewport = CGSize(width: 1_600, height: 1_000)
        let preview = CGSize(width: 240, height: 234)
        let current = CGRect(x: 100, y: 100, width: 300, height: 200)
        let right = CGRect(x: 420, y: 220, width: 300, height: 200)
        let leftCenter = TableEdgePreviewLayout.center(
            for: .left, current: right, destination: current,
            viewport: viewport, preview: preview, scale: 0.84
        )
        let rightCenter = TableEdgePreviewLayout.center(
            for: .right, current: current, destination: right,
            viewport: viewport, preview: preview, scale: 0.84
        )
        #expect(rightCenter == CGPoint(x: 1_464, y: 512.8))
        #expect(leftCenter == CGPoint(x: 136, y: 311.2))

        let below = CGRect(x: 300, y: 450, width: 300, height: 200)
        let downCenter = TableEdgePreviewLayout.center(
            for: .down, current: current, destination: below,
            viewport: viewport, preview: preview, scale: 0.84
        )
        #expect(downCenter == CGPoint(x: 968, y: 867))
    }

    @Test
    func `edge previews stop short of other directions' previews`() {
        let viewport = CGSize(width: 1_600, height: 1_000)
        let preview = CGSize(width: 240, height: 234)
        let current = CGRect(x: 100, y: 100, width: 300, height: 200)
        let farDown = CGRect(x: 420, y: 2_000, width: 300, height: 200)
        let center = TableEdgePreviewLayout.center(
            for: .right, current: current, destination: farDown,
            viewport: viewport, preview: preview, scale: 0.84,
            reserves: .init(top: 160, bottom: 220)
        )
        #expect(center.y == 647)
    }

    @Test
    func `wheel navigation follows fixed positions and reverses immediately`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        var tabs: [Tab] = []
        for x in [300.0, 600, 0] {
            let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank#\(x)")), in: space, makeActive: false)
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = CGPoint(x: x, y: 100)
            canvas.storeTablePlacement(placement, for: tab)
            tabs.append(tab)
        }
        env.tabManager.setActiveTab(tabs[0], in: window)
        canvas.revealFloatingTabs()
        let placements = tabs.map { canvas.tablePlacement(for: $0) }
        table.step(.right)
        #expect(window.activeTabID == tabs[1].id)
        #expect(table.departingTab?.id == tabs[0].id)
        table.step(.left)
        #expect(window.activeTabID == tabs[0].id)
        #expect(table.departingTab?.id == tabs[1].id)
        table.step(.left)
        #expect(window.activeTabID == tabs[2].id)
        table.step(.left)
        #expect(window.activeTabID == tabs[2].id)
        #expect(table.blockedDirection == .left)
        table.step(.right)
        #expect(window.activeTabID == tabs[0].id)
        #expect(table.blockedDirection == nil)
        #expect(tabs.map { canvas.tablePlacement(for: $0) } == placements)
        env.tabManager.closeTab(tabs[2])
        #expect(table.navigationTabID == window.activeTabID)
        canvas.dismissFloatingTabs()
    }

    @Test
    func `a partial page gesture stays on its page`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        var placement = FloatingTabPlacement.initial(index: 0)
        placement.tableOrigin = CGPoint(x: 100, y: 200)
        canvas.storeTablePlacement(placement, for: tab)
        let delta = CGPoint(x: -20, y: 10)
        table.beginPan(CGSize(width: delta.x, height: delta.y))
        table.endPan()
        let stopped = canvas.floatingCamera
        table.pan(CGSize(width: 200, height: 200))
        #expect(canvas.floatingCamera == stopped)
        #expect(canvas.tablePlacement(for: tab) == placement)
        canvas.show()
        #expect(canvas.openingCameraFrame == stopped.unproject(canvas.floatingArea))
        canvas.dismiss(activating: nil)
        #expect(canvas.floatingCamera == stopped)
    }

    @Test
    func `a precise gesture follows the same announced neighbor as a wheel notch`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        let hotel = try env.tabManager.createTab(url: #require(URL(string: "about:blank#hotel")), in: space, makeActive: false)
        let map = try env.tabManager.createTab(url: #require(URL(string: "about:blank#map")), in: space, makeActive: false)
        for (tab, x) in [(hotel, 0.0), (map, 300.0)] {
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = CGPoint(x: x, y: 100)
            canvas.storeTablePlacement(placement, for: tab)
        }
        env.tabManager.setActiveTab(hotel, in: window)
        #expect(table.destination(toward: .right)?.id == map.id)
        table.beginPan(CGSize(width: 0, height: -24))
        #expect(window.activeTabID == hotel.id)
        #expect(table.approachDirection == .right)
        #expect(table.approachFraction == 0.5)
        table.pan(CGSize(width: 0, height: -24))
        #expect(window.activeTabID == map.id)
        table.endPan()
        #expect(table.approachDirection == nil)
        #expect(table.approachFraction == 0)
        #expect(table.destination(toward: .left)?.id == hotel.id)
    }

    @Test
    func `one continuous gesture reaches one announced neighbor`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        var tabs: [Tab] = []
        for x in [0.0, 300, 600] {
            let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank#\(x)")), in: space, makeActive: false)
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = CGPoint(x: x, y: 100)
            canvas.storeTablePlacement(placement, for: tab)
            tabs.append(tab)
        }
        env.tabManager.setActiveTab(tabs[0], in: window)
        let smooth: TableScrollSource = .smoothWheel
        table.beginPan(CGSize(width: 0, height: -8), source: smooth)
        #expect(window.activeTabID == tabs[0].id)
        table.pan(CGSize(width: 0, height: -8), source: smooth)
        #expect(window.activeTabID == tabs[1].id)
        #expect(table.approachDirection == nil)
        table.pan(CGSize(width: 0, height: -40), source: smooth)
        table.pan(CGSize(width: 0, height: -12), source: smooth)
        table.pan(CGSize(width: 0, height: 8), source: smooth)
        table.pan(CGSize(width: 0, height: 8), source: smooth)
        #expect(window.activeTabID == tabs[1].id)
        table.endPan()

        table.beginPan(CGSize(width: 0, height: 8), source: smooth)
        table.pan(CGSize(width: 0, height: 8), source: smooth)
        #expect(window.activeTabID == tabs[0].id)
        table.endPan()

        env.tabManager.setActiveTab(tabs[0], in: window)
        table.beginPan(CGSize(width: 0, height: -40))
        table.pan(CGSize(width: 0, height: -40))
        #expect(window.activeTabID == tabs[1].id)
        table.pan(CGSize(width: 0, height: -16))
        #expect(window.activeTabID == tabs[1].id)
        table.endPan()

        table.beginPan(CGSize(width: 0, height: -48))
        #expect(window.activeTabID == tabs[2].id)
        table.endPan()
    }

    @Test
    func `reading navigation uses the visible page when a different card is focused`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        let hotel = try env.tabManager.createTab(url: #require(URL(string: "about:blank#hotel")), in: space, makeActive: false)
        let map = try env.tabManager.createTab(url: #require(URL(string: "about:blank#map")), in: space, makeActive: false)
        for (tab, x) in [(hotel, 0.0), (map, 300.0)] {
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = CGPoint(x: x, y: 100)
            canvas.storeTablePlacement(placement, for: tab)
        }
        env.tabManager.setActiveTab(hotel, in: window)
        canvas.revealFloatingTabs()
        canvas.revealSpatialDestination(map.id)
        #expect(table.navigationTabID == hotel.id)
        #expect(table.destination(toward: .right)?.id == map.id)
        table.step(.right)
        #expect(window.activeTabID == map.id)
    }

    @Test
    func `Control shows adjacent destinations while the floating button opens the card layer`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        let hotel = try env.tabManager.createTab(url: #require(URL(string: "about:blank#hotel")), in: space, makeActive: false)
        let map = try env.tabManager.createTab(url: #require(URL(string: "about:blank#map")), in: space, makeActive: false)
        for (tab, x) in [(hotel, 0.0), (map, 300.0)] {
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = CGPoint(x: x, y: 100)
            canvas.storeTablePlacement(placement, for: tab)
        }
        env.tabManager.setActiveTab(hotel, in: window)

        canvas.revealFloatingTabs()
        #expect(canvas.isMomentaryNavigation)
        #expect(canvas.visibleFloatingTabs.isEmpty)
        #expect(table.destination(toward: .right)?.id == map.id)

        canvas.releaseFloatingTabs()
        canvas.toggleFloatingTabs()
        #expect(!canvas.isMomentaryNavigation)
        #expect(canvas.visibleFloatingTabs.contains { $0.id == map.id })
    }

    @Test
    func `the active page and its card move under the same camera`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        var placement = FloatingTabPlacement.initial(index: 0)
        placement.tableOrigin = CGPoint(x: 800, y: 500)
        canvas.storeTablePlacement(placement, for: tab)
        let viewport = CGRect(x: 180, y: 20, width: 900, height: 700)
        canvas.focusPage(tab, in: viewport)
        #expect(canvas.pageFrame(for: tab, in: viewport) == CGRect(origin: .zero, size: viewport.size))
        let card = canvas.floatingFrame(for: tab, in: canvas.floatingArea)
        let delta = CGPoint(x: -80, y: 45)
        canvas.panFloatingCamera(by: delta)
        #expect(canvas.pageFrame(for: tab, in: viewport).origin == delta)
        #expect(canvas.floatingFrame(for: tab, in: canvas.floatingArea).origin == CGPoint(x: card.minX + delta.x, y: card.minY + delta.y))
        #expect(canvas.tablePlacement(for: tab) == placement)
    }

    @Test
    func `holding Control frames the current page without moving its place on the table`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        var placement = FloatingTabPlacement.initial(index: 0)
        placement.tableOrigin = CGPoint(x: 800, y: 500)
        canvas.storeTablePlacement(placement, for: tab)
        env.tabManager.setActiveTab(tab, in: window)
        let viewport = CGRect(x: 180, y: 20, width: 900, height: 700)
        canvas.focusPage(tab, in: viewport)

        canvas.revealFloatingTabs()
        canvas.focusPage(tab, in: viewport)
        let framed = canvas.pageFrame(for: tab, in: viewport)
        #expect(abs(framed.minX - 72) < 0.001)
        #expect(abs(framed.minY - 56) < 0.001)
        #expect(abs(framed.width - 756) < 0.001)
        #expect(abs(framed.height - 588) < 0.001)
        #expect(canvas.tablePlacement(for: tab) == placement)

        canvas.releaseFloatingTabs()
        canvas.focusPage(tab, in: viewport)
        #expect(canvas.pageFrame(for: tab, in: viewport) == CGRect(origin: .zero, size: viewport.size))
        #expect(canvas.tablePlacement(for: tab) == placement)
    }

    @Test(arguments: [false, true])
    func `reopening a page restores its table position`(isPrivate: Bool) throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        if isPrivate {
            space.dataStoreMode = .private
        }
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank#restore")), in: space, makeActive: false)
        var placement = FloatingTabPlacement.initial(index: 0, shape: .live)
        placement.tableOrigin = CGPoint(x: 820, y: 460)
        canvas.storeTablePlacement(placement, for: tab)

        env.tabManager.closeTab(tab)
        env.undoRedoManager.reopenLastClosedTab()

        let restored = try #require(window.activeTab)
        #expect(restored.id != tab.id)
        #expect(canvas.tablePlacement(for: restored) == placement)
    }

    @Test(arguments: [false, true])
    func `closing a page returns to its visible neighbor before a distant recent page`(archiveEnabled: Bool) throws {
        let env = try TabManagerTestEnvironment()
        env.settings.archiveEnabled = archiveEnabled
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        window.tableController = table
        var tabs: [Tab] = []
        for x in [0.0, 262, 900] {
            let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank#\(x)")), in: space, makeActive: false)
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = CGPoint(x: x, y: 100)
            canvas.storeTablePlacement(placement, for: tab)
            tabs.append(tab)
        }
        env.tabManager.setActiveTab(tabs[0], in: window)
        env.tabManager.setActiveTab(tabs[2], in: window)
        env.tabManager.setActiveTab(tabs[1], in: window)
        #expect(window.previousActiveTabID(for: space.id) == tabs[2].id)
        #expect(table.destination(toward: .left)?.id == tabs[0].id)

        env.tabManager.closeTab(tabs[1])

        #expect(window.activeTabID == tabs[0].id)
    }

    @Test
    func `pan has equal screen displacement at every zoom level`() {
        let frame = CGRect(x: 400, y: 300, width: 250, height: 34)
        let delta = CGPoint(x: -80, y: 25)
        for scale in [0.25, 0.5, 1.0, 2.0] {
            var camera = TabSpatialCamera(origin: CGPoint(x: 60, y: -40), scale: scale)
            let before = camera.project(frame)
            camera.pan(by: delta)
            #expect(camera.project(frame) == before.offsetBy(dx: delta.x, dy: delta.y))
        }
    }

    @Test
    func `table commands edit shared cards while keeping their anchor`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let table = TableController(windowState: window, tabManager: env.tabManager, canvas: canvas, pagePool: env.pagePool)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        env.tabManager.setActiveTab(tab, in: window)
        var placement = FloatingTabPlacement.initial(index: 0, shape: .live)
        placement.tableOrigin = CGPoint(x: 100, y: 200)
        canvas.storeTablePlacement(placement, for: tab)
        table.moveFocusedSlab(.right)
        let moved = canvas.tablePlacement(for: tab)
        #expect(moved.tableOrigin == CGPoint(x: 124, y: 200))
        table.toggleFill()
        #expect(canvas.tablePlacement(for: tab).size.width == canvas.floatingArea.width)
        table.toggleFill()
        #expect(canvas.tablePlacement(for: tab).size == moved.size)
        #expect(canvas.tablePlacement(for: tab).tableOrigin == moved.tableOrigin)
        canvas.show()
        #expect(canvas.tileFrames[tab.id] == moved.frame(in: canvas.floatingArea))
        canvas.dismiss(activating: nil)
    }
}
