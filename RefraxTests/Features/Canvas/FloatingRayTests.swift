import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct FloatingRayPathTests {
    private let area = CGRect(x: 0, y: 0, width: 1_200, height: 800)
    private let lens = CGRect(x: 280, y: 180, width: 640, height: 48)

    private func contains(_ path: FloatingRayPath) -> Bool {
        [path.start, path.bend, path.end].allSatisfy { area.contains($0) || area.maxX == $0.x || area.maxY == $0.y }
    }

    @Test(arguments: [
        CGRect(x: 16, y: 750, width: 250, height: 34),
        CGRect(x: 934, y: 750, width: 250, height: 34),
        CGRect(x: 16, y: 16, width: 250, height: 34),
        CGRect(x: 934, y: 16, width: 250, height: 34),
        CGRect(x: 1_000, y: 300, width: 250, height: 34),
    ])
    func `the ray stays in the window and lands on the destination's edge`(destination: CGRect) {
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        #expect(contains(path))
        let onEdge = abs(path.end.x - destination.minX) < 0.01 || abs(path.end.x - destination.maxX) < 0.01
            || abs(path.end.y - destination.minY) < 0.01 || abs(path.end.y - destination.maxY) < 0.01
        #expect(onEdge)
        #expect(destination.insetBy(dx: -0.01, dy: -0.01).contains(path.end))
        #expect(path.length > 0)
    }

    @Test
    func `the bend turns the ray toward the pane's normal`() throws {
        let destination = CGRect(x: 16, y: 750, width: 250, height: 34)
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        let side = try #require(FloatingRayPath.nearSide(of: destination, from: path.start))
        #expect(side == .top)
        let sines = path.sines(normal: side.inwardNormal)
        #expect(sines.incidence > 0)
        #expect(sines.refraction < sines.incidence)
        #expect(abs(sines.refraction - sines.incidence / FloatingRayPath.refractiveIndex) < 0.05)
        #expect(abs(path.bend.y - (destination.minY - FloatingRayPath.paneGap)) < 0.01)
        #expect(path.bend.x < path.start.x, "the first run heads for the destination's center")
        #expect(path.end.x < path.bend.x, "the second run keeps the same tangential sense")
    }

    @Test
    func `a ray straight down the normal keeps its line`() {
        let destination = CGRect(x: 475, y: 700, width: 250, height: 34)
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        #expect(abs(path.start.x - path.bend.x) < 0.01)
        #expect(abs(path.bend.x - path.end.x) < 0.01)
        #expect(abs(path.end.y - destination.minY) < 0.01)
    }

    @Test
    func `a destination beside the source enters through its side`() {
        let destination = CGRect(x: 1_000, y: 190, width: 180, height: 34)
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        #expect(FloatingRayPath.nearSide(of: destination, from: path.start) == .leading)
        let gap = FloatingRayPath.paneGap(forApproach: destination.minX - path.start.x)
        #expect(gap < FloatingRayPath.paneGap, "a short approach draws the pane in")
        #expect(abs(path.bend.x - (destination.minX - gap)) < 0.01)
        #expect(abs(path.end.x - destination.minX) < 0.01)
        #expect(contains(path))
    }

    @Test(arguments: [
        CGRect(x: 300, y: 190, width: 250, height: 34),
        CGRect(x: 280, y: 180, width: 640, height: 48),
        CGRect(x: 600, y: 240, width: 250, height: 34),
        CGRect(x: 0, y: 0, width: 0, height: 0),
        CGRect(x: CGFloat.nan, y: CGFloat.infinity, width: 10, height: 10),
    ])
    func `overlapping, touching, and invalid rects give a short finite path`(destination: CGRect) {
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        for point in [path.start, path.bend, path.end] {
            #expect(point.x.isFinite && point.y.isFinite)
        }
        #expect(contains(path))
        #expect(path.length < hypot(lens.width, lens.height) + 1)
    }

    @Test
    func `an empty source starts the ray at its point`() {
        let destination = CGRect(x: 934, y: 750, width: 250, height: 34)
        let path = FloatingRayPath(from: .zero, to: destination, in: area)
        #expect(path.start == .zero)
        #expect(contains(path))
        #expect(path.length > 0)
    }
}

@Suite(.serialized)
@MainActor
struct FloatingRayTriggerTests {
    private let lensFrame = CGRect(x: 280, y: 180, width: 640, height: 48)

    @Test
    func `a page replaced from the lens takes the nearest corner and gets a ray from the lens`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let first = try env.createActiveTab(url: #require(URL(string: "about:blank#first")), in: space, for: window)
        #expect(canvas.rayRequest == nil)

        window.commandLensFrame = lensFrame
        window.openCommandLens()
        let second = try env.tabManager.createTab(url: #require(URL(string: "about:blank#second")), in: space, makeActive: false)
        env.tabManager.setActiveTab(second, in: window)
        window.closeCommandLens()

        let request = try #require(canvas.rayRequest)
        #expect(request.tabID == first.id)
        #expect(request.source == lensFrame)
        #expect(canvas.unplacedFloatingTabs.map(\.id) == [second.id])
        let placement = canvas.floatingPlacement(for: first)
        #expect(placement.y == 0)
        #expect(first.floatingPlacement == placement)

        canvas.finishRay(request.revision)
        #expect(canvas.rayRequest == nil)
    }

    @Test
    func `without the lens the ray leaves from the page card and a placed page stays quiet`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        window.addressBarFrame = CGRect(x: 4, y: 300, width: 40, height: 44)
        let first = try env.createActiveTab(url: #require(URL(string: "about:blank#first")), in: space, for: window)
        let second = try env.tabManager.createTab(url: #require(URL(string: "about:blank#second")), in: space, makeActive: false)

        env.tabManager.setActiveTab(second, in: window)
        let request = try #require(canvas.rayRequest)
        #expect(request.source == window.addressBarFrame)
        #expect(canvas.floatingPlacement(for: first).x == 0)

        env.tabManager.setActiveTab(first, in: window)
        #expect(canvas.rayRequest?.tabID == second.id)
        let revision = try #require(canvas.rayRequest?.revision)
        env.tabManager.setActiveTab(second, in: window)
        #expect(canvas.rayRequest?.revision == revision, "a page with a place of its own gets no ray")
    }

    @Test
    func `favorites, other spaces, and Look visits get no ray`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let other = env.makeSpace(name: "Other")
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let source = try env.createActiveTab(url: #require(URL(string: "about:blank#source")), in: space, for: window)
        let reference = try env.tabManager.createTab(url: #require(URL(string: "about:blank#reference")), in: space, makeActive: false)

        env.tabManager.look(at: reference, in: window)
        #expect(canvas.rayRequest == nil)
        #expect(env.tabManager.returnFromLook(in: window))
        #expect(canvas.rayRequest == nil)

        ControlIslandTabActions(tab: source, windowState: window, tabs: env.tabManager, bookmarks: env.bookmarksManager).toggleFavorite()
        #expect(window.activeTab?.isFavorite == true)
        env.tabManager.setActiveTab(reference, in: window)
        #expect(canvas.rayRequest == nil)

        let elsewhere = try env.tabManager.createTab(url: #require(URL(string: "about:blank#elsewhere")), in: other, makeActive: false)
        env.tabManager.setActiveTab(elsewhere, in: window)
        #expect(window.activeSpaceID == space.id)
        #expect(canvas.rayRequest == nil)
    }

    @Test
    func `displaced pages take free corners and the rest wait for the count`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        var pages: [Tab] = []
        for index in 0 ..< 6 {
            try pages.append(env.createActiveTab(url: #require(URL(string: "about:blank#\(index)")), in: space, for: window))
        }
        let placed = pages.filter { $0.floatingPlacement != nil }
        #expect(placed.count == FloatingTabPlacement.startingSlotCount)
        #expect(Set(placed.map { "\($0.floatingPlacement!.x),\($0.floatingPlacement!.y)" }).count == placed.count)
        #expect(canvas.unplacedFloatingTabs.count == 2)
        #expect(canvas.rayRequest?.tabID == pages[3].id)
    }
}
