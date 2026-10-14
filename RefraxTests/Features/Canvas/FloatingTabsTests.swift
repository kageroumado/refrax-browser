import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Refrax

struct FloatingTabsTests {
    @Test
    func `releasing control keeps only pinned previews`() {
        var state = FloatingTabVisibility()
        state.hold()
        #expect(state.shows(isPinned: false))
        state.release()
        #expect(state.shows(isPinned: false) == false)
        #expect(state.shows(isPinned: true))
    }

    @Test
    func `button reveal survives control release and escape dismisses it`() {
        var state = FloatingTabVisibility()
        state.toggle()
        state.hold()
        state.release()
        #expect(state.isRevealed)
        state.dismiss()
        #expect(state.isRevealed == false)
        #expect(state.shows(isPinned: true))
    }

    @Test(arguments: FloatingCardShape.allCases)
    func `placement stays reachable after resize and out of bounds drag`(shape: FloatingCardShape) {
        var placement = FloatingTabPlacement(x: 0.4, y: 0.6, shape: shape, isPinned: false)
        let large = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        placement.move(to: CGPoint(x: 9_000, y: -800), in: large)
        #expect(placement.x == 1)
        #expect(placement.y == 0)
        let small = CGRect(x: 0, y: 0, width: 500, height: 350)
        #expect(small.contains(placement.frame(in: small)))
        #expect(placement.frame(in: small).minY >= 16)
    }

    @Test
    func `moving one tile does not reflow another`() {
        let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        var moved = FloatingTabPlacement.initial(index: 0)
        let neighbor = FloatingTabPlacement.initial(index: 1)
        let original = neighbor.frame(in: area)
        moved.move(to: original.origin, in: area)
        #expect(neighbor.frame(in: area) == original)
        #expect(moved.frame(in: area) == original)
    }

    @Test @MainActor
    func `floating and desk edits preserve each other across serialization`() throws {
        let tab = try Tab(space: nil, url: #require(URL(string: "https://example.com")))
        let placement = FloatingTabPlacement(x: 0.72, y: 0.3, shape: .live, isPinned: true)
        tab.floatingPlacement = placement
        #expect(tab.boardFrame == nil)
        tab.boardFrame = CGRect(x: 80, y: 90, width: 320, height: 240)
        tab.boardIsCompact = true
        #expect(tab.floatingPlacement == placement)
        let data = try #require(tab.boardFrameData)
        let restored = try Tab(space: nil, url: #require(URL(string: "https://example.com")))
        restored.boardFrameData = data
        #expect(restored.floatingPlacement == placement)
        #expect(restored.boardIsCompact)
        #expect(restored.boardFrame == tab.boardFrame)
        restored.floatingPlacement = nil
        #expect(restored.boardFrame == tab.boardFrame)
    }

    @Test
    func `existing desk data decodes without floating state`() {
        let data = Data(#"{"x":120,"y":160,"width":320,"height":200,"isCompact":true}"#.utf8)
        #expect(BoardFrame.value(data)?.floating == nil)
        #expect(BoardFrame.decode(data) == CGRect(x: 120, y: 160, width: 320, height: 200))
        #expect(BoardFrame.isCompact(data))
    }

    @Test
    func `invalid coordinates stay inside the window`() {
        let placement = FloatingTabPlacement(x: .nan, y: .infinity, shape: .live, isPinned: false)
        let area = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        #expect(area.contains(placement.frame(in: area)))
    }

    @Test
    func `resizing preserves the top left and the live size persists through other shapes`() throws {
        let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        var placement = FloatingTabPlacement(x: 0.2, y: 0.3, shape: .live, isPinned: true)
        let origin = placement.frame(in: area).origin
        placement.resize(to: CGSize(width: 650, height: 450), in: area)
        #expect(abs(placement.frame(in: area).minX - origin.x) < 0.001)
        #expect(abs(placement.frame(in: area).minY - origin.y) < 0.001)
        #expect(placement.size == CGSize(width: 650, height: 450))
        placement.shape = .tab
        let data = try JSONEncoder().encode(placement)
        var restored = try JSONDecoder().decode(FloatingTabPlacement.self, from: data)
        #expect(restored.size.height == FloatingTabPlacement.headerHeight)
        restored.shape = .live
        #expect(restored.size == CGSize(width: 650, height: 450))
    }

    @Test
    func `oversized and invalid resize stays reachable`() {
        let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        var placement = FloatingTabPlacement(x: 0.7, y: 0.7, shape: .live, isPinned: false)
        let origin = placement.frame(in: area).origin
        placement.resize(to: CGSize(width: 9_000, height: 9_000), in: area)
        #expect(abs(placement.frame(in: area).minX - origin.x) < 0.001)
        #expect(abs(placement.frame(in: area).minY - origin.y) < 0.001)
        #expect(area.contains(placement.frame(in: area)))
        placement.resize(to: CGSize(width: CGFloat.nan, height: 120), in: area)
        #expect(area.contains(placement.frame(in: area)))
        #expect(placement.shape == .live)
        #expect(placement.size.height == FloatingCardShape.live.minimumSize.height)
    }

    @Test
    func `saved placements without dimensions use the default preview size`() throws {
        let data = Data(#"{"x":0.2,"y":0.3,"shape":"live","isPinned":true}"#.utf8)
        let placement = try JSONDecoder().decode(FloatingTabPlacement.self, from: data)
        #expect(placement.size == FloatingCardShape.Layout.liveNaturalSize)
    }

    @Test
    func `changing shape keeps the card's top-leading corner and its kept state`() {
        let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        var placement = FloatingTabPlacement(x: 0.3, y: 0.2, shape: .tab, isPinned: false)
        let origin = placement.frame(in: area).origin
        placement.setShape(.live, in: area)
        #expect(abs(placement.frame(in: area).minX - origin.x) < 0.001)
        #expect(abs(placement.frame(in: area).minY - origin.y) < 0.001)
        placement.isPinned = true
        placement.setShape(.icon, in: area)
        #expect(abs(placement.frame(in: area).minX - origin.x) < 0.001)
        #expect(abs(placement.frame(in: area).minY - origin.y) < 0.001)
        #expect(placement.isPinned)
    }
    @Test @MainActor
    func `empty space passes clicks to the page`() {
        let host = FloatingTabsHostingView(rootView: Color.clear)
        host.frame = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        host.hitRegions = { [CGRect(x: 20, y: 64, width: 340, height: 250)] }
        #expect(host.hitTest(CGPoint(x: 600, y: 400)) == nil)
        host.hitRegions = { [] }
        #expect(host.hitTest(CGPoint(x: 40, y: 100)) == nil)
    }

    @Test
    func `new tabs have distinct starting positions in large spaces`() {
        let placements = (0 ..< 40).map { FloatingTabPlacement.initial(index: $0, count: 40) }
        let origins = placements.map { $0.frame(in: CGRect(x: 0, y: 0, width: 1_600, height: 1_000)).origin }
        for (index, origin) in origins.enumerated() {
            #expect(origins[..<index].contains(origin) == false)
        }
    }
}
