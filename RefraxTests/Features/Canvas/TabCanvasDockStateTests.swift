import AppKit
import Testing
@testable import Refrax

/// The docked pages are read from the tabs once per change, and follow every change.
@MainActor
struct TabCanvasDockStateTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1_440, height: 1_080)

    @Test
    func `docking and undocking a page is seen through the cached dock state`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
        let page = env.tabManager.createTab(url: .blank, in: space, makeActive: true, loadImmediately: false)
        let side = env.tabManager.createTab(url: .blank, in: space, makeActive: false, loadImmediately: false)
        #expect(window.activeTabID == page.id)

        #expect(canvas.dockedTab(on: .leading) == nil)
        #expect(canvas.dockedTab(on: .trailing) == nil)
        let version = canvas.dockStateVersion

        canvas.dock(side, to: .trailing)
        #expect(canvas.dockedTab(on: .trailing)?.id == side.id)
        #expect(canvas.dockedTab(on: .leading) == nil)
        #expect(canvas.dockStateVersion != version)
        #expect(canvas.dockColumns(in: bounds).trailing != nil)

        var placement = canvas.floatingPlacement(for: side)
        placement.dockFraction = 0.4
        canvas.updateFloatingPlacement(placement, for: side)
        #expect(canvas.dockState.trailing?.fraction == 0.4)

        canvas.undock(side)
        #expect(canvas.dockedTab(on: .trailing) == nil)
        #expect(canvas.dockColumns(in: bounds).trailing == nil)
    }

    @Test
    func `repeated questions reuse one reading of the tabs`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
        _ = env.tabManager.createTab(url: .blank, in: space, makeActive: true, loadImmediately: false)
        let side = env.tabManager.createTab(url: .blank, in: space, makeActive: false, loadImmediately: false)
        canvas.dock(side, to: .leading)

        let version = canvas.dockStateVersion
        for _ in 0 ..< 50 {
            _ = canvas.dockHitRegions(in: bounds)
            _ = canvas.dockedTab(on: .leading)
        }
        #expect(canvas.dockStateVersion == version)
        #expect(canvas.dockStateCache != nil)

        // A page becoming the current page leaves its column: the cache follows the active tab.
        env.tabManager.setActiveTab(side, in: window)
        #expect(canvas.dockedTab(on: .leading) == nil)
    }
}
