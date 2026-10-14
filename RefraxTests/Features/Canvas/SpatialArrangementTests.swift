import AppKit
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct SpatialArrangementTests {
    @Test
    func `opening the desk frames every placed tab`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        for (index, origin) in [CGPoint(x: 80, y: 100), CGPoint(x: 1_200, y: 900)].enumerated() {
            let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank#\(index)")), in: space, makeActive: false)
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = origin
            canvas.storeTablePlacement(placement, for: tab)
        }

        canvas.show()
        defer { canvas.dismiss(activating: nil) }

        let fit = try #require(canvas.openingFitRect)
        #expect(fit.contains(canvas.deskBounds))
        #expect(canvas.tileFrames.values.allSatisfy(fit.contains))
    }

    @Test
    func `overview reuses floating frames and preserves overlapping placements on entry`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        var tabs: [Tab] = []
        for shape in FloatingCardShape.allCases {
            let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank#\(shape.rawValue)")), in: space, makeActive: false)
            var placement = FloatingTabPlacement.initial(index: 0, shape: shape)
            placement.tableOrigin = CGPoint(x: 100, y: 200)
            canvas.updateFloatingPlacement(placement, for: tab)
            tabs.append(tab)
        }
        let frames = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, canvas.floatingFrame(for: $0, in: canvas.floatingArea)) })
        canvas.show()
        defer { canvas.dismiss(activating: nil) }
        #expect(canvas.tileFrames == frames)
        for tab in tabs {
            #expect(canvas.floatingFrame(for: tab, in: canvas.floatingArea) == frames[tab.id])
        }
    }

    @Test
    func `overview movement and shape changes update the floating arrangement`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        canvas.show()
        defer { canvas.dismiss(activating: nil) }
        let origin = CGPoint(x: 1_500, y: 900)
        let moved = CGRect(origin: origin, size: canvas.floatingPlacement(for: tab).size)
        canvas.settleTiles([tab.id: moved])
        #expect(canvas.floatingFrame(for: tab, in: canvas.floatingArea).origin == origin)
        canvas.togglePreview(tab.id, at: moved)
        #expect(canvas.floatingPlacement(for: tab).shape == .live)
        #expect(canvas.tileFrames[tab.id] == canvas.floatingFrame(for: tab, in: canvas.floatingArea))
        #expect(canvas.tileFrames[tab.id]?.origin == origin)
        #expect(tab.boardFrame == nil)
    }

    @Test
    func `full size navigation follows card positions instead of creation order`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        var tabs: [Tab] = []
        for x in [300.0, 600, 0] {
            let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank#\(x)")), in: space, makeActive: false)
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = CGPoint(x: x, y: 100)
            canvas.updateFloatingPlacement(placement, for: tab)
            tabs.append(tab)
        }
        let ids = Set(tabs.map(\.id))
        #expect(canvas.spatialNeighbor(from: tabs[0].id, toward: .left, among: ids) == tabs[2].id)
        #expect(canvas.spatialNeighbor(from: tabs[0].id, toward: .right, among: ids) == tabs[1].id)
    }

    @Test
    func `table positions survive resizing and Codable round trips`() throws {
        var placement = FloatingTabPlacement.initial(index: 0, shape: .live)
        placement.tableOrigin = CGPoint(x: 900, y: 300)
        let restored = try JSONDecoder().decode(FloatingTabPlacement.self, from: JSONEncoder().encode(placement))
        #expect(restored.frame(in: CGRect(x: 0, y: 0, width: 800, height: 600)) == placement.frame(in: CGRect(x: 0, y: 0, width: 1_600, height: 1_000)))
    }

    @Test
    func `camera movement leaves saved positions unchanged and edits convert back to table coordinates`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        var placement = FloatingTabPlacement.initial(index: 0)
        placement.tableOrigin = CGPoint(x: 1_500, y: 900)
        canvas.updateFloatingPlacement(placement, for: tab)
        let saved = canvas.tablePlacement(for: tab)
        canvas.revealSpatialDestination(tab.id)
        #expect(canvas.floatingCamera.origin != .zero)
        #expect(canvas.tablePlacement(for: tab) == saved)
        canvas.dock(tab, to: .leading)
        canvas.undock(tab)
        #expect(canvas.tablePlacement(for: tab).tableOrigin == saved.tableOrigin)
        var displayed = canvas.floatingPlacement(for: tab)
        let origin = displayed.frame(in: canvas.floatingArea).origin
        displayed.move(to: CGPoint(x: origin.x - 20, y: origin.y - 30), in: canvas.floatingArea)
        canvas.updateFloatingPlacement(displayed, for: tab)
        let moved = try #require(canvas.tablePlacement(for: tab).tableOrigin)
        #expect(abs(moved.x - 1_480) < 0.001)
        #expect(abs(moved.y - 870) < 0.001)
    }

    @Test
    func `zoom preserves the point under the pointer and round trips frames`() {
        var camera = TabSpatialCamera(origin: CGPoint(x: 300, y: 150))
        let pointer = CGPoint(x: 410, y: 260)
        let anchor = camera.unproject(CGRect(origin: pointer, size: .zero)).origin
        let frame = CGRect(x: 730, y: 460, width: 340, height: 250)
        for scale in [0.25, 2.0, 0.75, 1.0] {
            camera.zoom(to: scale, at: pointer)
            let projected = camera.project(CGRect(origin: anchor, size: .zero)).origin
            #expect(abs(projected.x - pointer.x) < 0.001)
            #expect(abs(projected.y - pointer.y) < 0.001)
            let restored = camera.unproject(camera.project(frame))
            #expect(abs(restored.minX - frame.minX) < 0.001)
            #expect(abs(restored.minY - frame.minY) < 0.001)
            #expect(abs(restored.width - frame.width) < 0.001)
        }
    }

    @Test
    func `overview wheel changes destination at constant zoom and reverses immediately`() throws {
        let left = try Tab(space: nil, url: #require(URL(string: "about:blank#left")))
        let right = try Tab(space: nil, url: #require(URL(string: "about:blank#right")))
        let view = TabCanvasScrollView(deskSize: CGSize(width: 1_280, height: 820))
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()
        view.reload(CanvasBoardContent(
            tabs: [left, right],
            frames: [left.id: CGRect(x: 100, y: 100, width: 250, height: 34), right.id: CGRect(x: 400, y: 100, width: 250, height: 34)],
            snapshots: [:], zones: [], magnets: [], selectedTabIDs: [], focusedTabID: left.id,
            tileSize: CGSize(width: 250, height: 34), deskSize: CGSize(width: 1_280, height: 820),
        ))
        let scale = view.magnification
        view.handleWheel(.step(.right), at: .zero)
        #expect(view.navigationTabID == right.id)
        #expect(view.magnification == scale)
        view.handleWheel(.step(.left), at: .zero)
        #expect(view.navigationTabID == left.id)
        #expect(view.magnification == scale)
        view.zoom(by: 1_000, aboutWindowPoint: CGPoint(x: 400, y: 300))
        let atLimit = view.contentView.bounds
        view.zoom(by: 1_000, aboutWindowPoint: CGPoint(x: 400, y: 300))
        #expect(view.magnification == view.maxMagnification)
        #expect(view.contentView.bounds == atLimit)
    }

    @Test
    func `a pile offers no invisible wheel destinations`() {
        let ids = [UUID(), UUID(), UUID()]
        let frames = ids.map { CanvasNavigation.Tile(id: $0, frame: CGRect(x: 100, y: 100, width: 250, height: 34)) }
        #expect(CanvasNavigation.neighbor(from: ids[0], toward: .down, in: frames) == nil)
        #expect(CanvasNavigation.neighbor(from: ids[1], toward: .down, in: frames) == nil)
        #expect(CanvasNavigation.neighbor(from: ids[2], toward: .up, in: frames) == nil)
        #expect(CanvasNavigation.neighbor(from: ids[0], toward: .up, in: frames) == nil)
    }

    @Test
    func `restoring overlapping cards leaves physics asleep`() {
        var physics = CanvasPhysics(desk: CGRect(x: 0, y: 0, width: 1_280, height: 800))
        let frame = CGRect(x: 100, y: 100, width: 200, height: 60)
        let ids = [UUID(), UUID()]
        for id in ids {
            physics.place(id, frame: frame, awake: false)
        }
        for id in ids {
            #expect(!physics.isActive(id))
        }
    }
}

struct CanvasWheelInputTests {
    @Test(arguments: [false, true])
    func `ordinary wheel uses the same direction as the full size table`(shift: Bool) {
        for delta in [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -4), CGPoint(x: 2, y: 0)] {
            let expected = TableDirection.wheelStep(deltaX: delta.x, deltaY: delta.y, shift: shift)
            #expect(CanvasWheelInput.action(delta: delta, source: .wheel, shift: shift, zoom: false) == expected.map(CanvasWheelInput.Action.step))
        }
    }

    @Test
    func `zoom requires its modifier and bounds large wheel impulses`() {
        #expect(CanvasWheelInput.action(delta: CGPoint(x: 0, y: 100), source: .wheel, shift: false, zoom: true) == .zoom(pow(1.1, 3)))
        #expect(CanvasWheelInput.action(delta: .zero, source: .wheel, shift: false, zoom: true) == .none)
        #expect(CanvasWheelInput.action(delta: CGPoint(x: 0, y: 12), source: .smoothWheel, shift: false, zoom: false) == .pan(CGPoint(x: 0, y: 12)))
    }
}
