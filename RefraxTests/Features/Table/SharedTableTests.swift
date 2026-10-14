import AppKit
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct SharedTableTests {
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
        table.step(.left)
        #expect(window.activeTabID == tabs[0].id)
        table.step(.left)
        #expect(window.activeTabID == tabs[2].id)
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
        table.pan(CGSize(width: 0, height: -24))
        #expect(window.activeTabID == map.id)
        table.endPan()
        #expect(table.destination(toward: .left)?.id == hotel.id)
    }

    @Test
    func `smooth mouse movement responds early and keeps fractional progress through a row`() throws {
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
        table.pan(CGSize(width: 0, height: -40), source: smooth)
        #expect(window.activeTabID == tabs[1].id)
        table.pan(CGSize(width: 0, height: -12), source: smooth)
        #expect(window.activeTabID == tabs[2].id)
        table.pan(CGSize(width: 0, height: 8), source: smooth)
        table.pan(CGSize(width: 0, height: 8), source: smooth)
        #expect(window.activeTabID == tabs[1].id)
        table.endPan()

        env.tabManager.setActiveTab(tabs[0], in: window)
        table.beginPan(CGSize(width: 0, height: -40))
        table.pan(CGSize(width: 0, height: -40))
        #expect(window.activeTabID == tabs[1].id)
        table.pan(CGSize(width: 0, height: -16))
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
