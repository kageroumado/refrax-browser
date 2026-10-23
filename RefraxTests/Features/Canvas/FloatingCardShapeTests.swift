import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct FloatingCardShapeTests {
    private typealias Layout = FloatingCardShape.Layout

    private let window = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
    /// The placement area inside `window`: 16 points in from every edge.
    private let area = CGRect(x: 16, y: 16, width: 1_568, height: 968)

    // MARK: Shape for size

    @Test
    func `An icon becomes a tab only once clearly wider`() {
        #expect(FloatingCardShape.shape(after: .icon, proposing: CGSize(width: 90, height: 44)) == .icon)
        #expect(FloatingCardShape.shape(after: .icon, proposing: CGSize(width: Layout.iconToTabWidth, height: 44)) == .icon)
        #expect(FloatingCardShape.shape(after: .icon, proposing: CGSize(width: Layout.iconToTabWidth + 1, height: 44)) == .tab)
    }

    @Test
    func `A tab becomes an icon only once clearly narrower`() {
        #expect(FloatingCardShape.shape(after: .tab, proposing: CGSize(width: 80, height: 34)) == .tab)
        #expect(FloatingCardShape.shape(after: .tab, proposing: CGSize(width: Layout.tabToIconWidth - 1, height: 34)) == .icon)
    }

    @Test
    func `Between the icon and tab thresholds the shape holds`() {
        let between = CGSize(width: (Layout.iconToTabWidth + Layout.tabToIconWidth) / 2, height: 40)
        #expect(FloatingCardShape.shape(after: .icon, proposing: between) == .icon)
        #expect(FloatingCardShape.shape(after: .tab, proposing: between) == .tab)
    }

    @Test
    func `A tab or icon dragged tall enough becomes a live page`() {
        let tall = CGSize(width: 200, height: Layout.tabToLiveHeight + 1)
        #expect(FloatingCardShape.shape(after: .tab, proposing: tall) == .live)
        #expect(FloatingCardShape.shape(after: .icon, proposing: tall) == .live)
        #expect(FloatingCardShape.shape(after: .tab, proposing: CGSize(width: 200, height: Layout.tabToLiveHeight)) == .tab)
    }

    @Test
    func `A live page folds to a tab, or to an icon when also narrow`() {
        #expect(FloatingCardShape.shape(after: .live, proposing: CGSize(width: 300, height: 100)) == .live)
        #expect(FloatingCardShape.shape(after: .live, proposing: CGSize(width: 300, height: Layout.liveToTabHeight - 1)) == .tab)
        #expect(FloatingCardShape.shape(after: .live, proposing: CGSize(width: 40, height: 40)) == .icon)
    }

    @Test
    func `Between the tab and live thresholds the shape holds`() {
        let between = CGSize(width: 300, height: (Layout.tabToLiveHeight + Layout.liveToTabHeight) / 2)
        #expect(FloatingCardShape.shape(after: .tab, proposing: between) == .tab)
        #expect(FloatingCardShape.shape(after: .live, proposing: between) == .live)
    }

    @Test(arguments: FloatingCardShape.allCases)
    func `Each shape's crossing thresholds sit past its own limits`(shape: FloatingCardShape) {
        // A card resting at any size of its shape must keep that shape, or it would flicker.
        for size in [shape.minimumSize, shape.naturalSize] {
            #expect(FloatingCardShape.shape(after: shape, proposing: size) == shape)
        }
    }

    // MARK: Natural size

    @Test
    func `The icon is a fixed square and the tab a fixed height`() {
        #expect(FloatingCardShape.icon.fitted(CGSize(width: 300, height: 300)) == CGSize(width: 44, height: 44))
        #expect(FloatingCardShape.tab.fitted(CGSize(width: 200, height: 300)) == CGSize(width: 200, height: 34))
        #expect(FloatingCardShape.tab.fitted(CGSize(width: 10, height: 0)).width == Layout.tabMinimumWidth)
        #expect(FloatingCardShape.tab.fitted(CGSize(width: 900, height: 0)).width == Layout.tabMaximumWidth)
    }

    @Test
    func `A live page has a minimum and grows freely`() {
        #expect(FloatingCardShape.live.fitted(CGSize(width: 10, height: 10)) == Layout.liveMinimumSize)
        #expect(FloatingCardShape.live.fitted(CGSize(width: 1_200, height: 900)) == CGSize(width: 1_200, height: 900))
        #expect(FloatingCardShape.live.fitted(CGSize(width: CGFloat.nan, height: .infinity)) == Layout.liveNaturalSize)
    }

    // MARK: Resize math

    @Test
    func `Each handle grows its own sides`() {
        let start = CGSize(width: 300, height: 200)
        let drag = CGSize(width: 20, height: 10)
        #expect(FloatingResizeHandle.bottomTrailing.proposedSize(from: start, translation: drag) == CGSize(width: 320, height: 210))
        #expect(FloatingResizeHandle.topLeading.proposedSize(from: start, translation: drag) == CGSize(width: 280, height: 190))
        #expect(FloatingResizeHandle.trailing.proposedSize(from: start, translation: drag) == CGSize(width: 320, height: 200))
        #expect(FloatingResizeHandle.top.proposedSize(from: start, translation: drag) == CGSize(width: 300, height: 190))
        #expect(FloatingResizeHandle.leading.proposedSize(from: start, translation: CGSize(width: 500, height: 0)).width == 0)
    }

    @Test(arguments: FloatingResizeHandle.allCases)
    func `The sides opposite the handle stay fixed`(handle: FloatingResizeHandle) {
        let start = CGRect(x: 400, y: 300, width: 300, height: 200)
        let frame = handle.frame(from: start, size: CGSize(width: 360, height: 260), minimum: .zero, within: area)
        switch handle.horizontal {
        case -1: #expect(frame.maxX == start.maxX)
        default: #expect(frame.minX == start.minX)
        }
        switch handle.vertical {
        case -1: #expect(frame.maxY == start.maxY)
        default: #expect(frame.minY == start.minY)
        }
    }

    @Test
    func `Resizing stops at the window area unless the shape needs the room`() {
        let start = CGRect(x: 1_400, y: 800, width: 150, height: 150)
        let grown = FloatingResizeHandle.bottomTrailing.frame(from: start, size: CGSize(width: 900, height: 900), minimum: .zero, within: area)
        #expect(grown.maxX == area.maxX)
        #expect(grown.maxY == area.maxY)
        let leading = FloatingResizeHandle.topLeading.frame(from: start, size: CGSize(width: 2_000, height: 2_000), minimum: .zero, within: area)
        #expect(leading.minX == area.minX)
        #expect(leading.minY == area.minY)
        let cramped = FloatingResizeHandle.trailing.frame(
            from: CGRect(x: 1_550, y: 100, width: 30, height: 34), size: CGSize(width: 40, height: 34),
            minimum: FloatingCardShape.tab.minimumSize, within: area,
        )
        #expect(cramped.width == Layout.tabMinimumWidth)
    }

    // MARK: Placement

    @Test
    func `Dragging an icon's trailing edge out opens a tab at its minimum width, leading edge fixed`() {
        var placement = FloatingTabPlacement(x: 0.5, y: 0.5, shape: .icon, isPinned: false)
        let start = placement.frame(in: window)
        #expect(start.size == CGSize(width: 44, height: 44))
        let changed1 = placement.resize(dragging: .trailing, from: start, by: CGSize(width: 40, height: 0), in: window)
        #expect(!changed1)
        #expect(placement.shape == .icon)
        let changed2 = placement.resize(dragging: .trailing, from: start, by: CGSize(width: 60, height: 0), in: window)
        #expect(changed2)
        #expect(placement.shape == .tab)
        let frame = placement.frame(in: window)
        #expect(abs(frame.minX - start.minX) < 0.001)
        #expect(frame.size == CGSize(width: Layout.tabMinimumWidth, height: Layout.tabHeight))
    }

    @Test
    func `A tab then follows the pointer and remembers its width`() {
        var placement = FloatingTabPlacement(x: 0.5, y: 0.5, shape: .tab, isPinned: false)
        let start = placement.frame(in: window)
        placement.resize(dragging: .trailing, from: start, by: CGSize(width: 50, height: 0), in: window)
        #expect(placement.frame(in: window).width == start.width + 50)
        placement.setShape(.live, in: window)
        placement.setShape(.tab, in: window)
        #expect(placement.frame(in: window).width == start.width + 50)
    }

    @Test
    func `Dragging a tab's top edge up opens a live page above it, bottom edge fixed`() {
        var placement = FloatingTabPlacement(x: 0.5, y: 0.5, shape: .tab, isPinned: false)
        let start = placement.frame(in: window)
        let changed3 = placement.resize(dragging: .top, from: start, by: CGSize(width: 0, height: -90), in: window)
        #expect(changed3)
        #expect(placement.shape == .live)
        let frame = placement.frame(in: window)
        #expect(abs(frame.maxY - start.maxY) < 0.001)
        #expect(frame.height == Layout.liveMinimumSize.height)
    }

    @Test
    func `A live page dragged back past the threshold folds to a tab at the pointer's width`() {
        var placement = FloatingTabPlacement(x: 0.5, y: 0.5, shape: .live, isPinned: false)
        let start = placement.frame(in: window)
        placement.resize(dragging: .bottomTrailing, from: start, by: CGSize(width: -100, height: -start.height + 120), in: window)
        #expect(placement.shape == .live)
        placement.resize(dragging: .bottomTrailing, from: start, by: CGSize(width: -100, height: -start.height + 60), in: window)
        #expect(placement.shape == .tab)
        let frame = placement.frame(in: window)
        #expect(frame.width == start.width - 100)
        #expect(abs(frame.minX - start.minX) < 0.001)
        #expect(abs(frame.minY - start.minY) < 0.001)
    }

    // MARK: Migration

    @Test
    func `A stored compact flag becomes the tab shape, any other card a live page`() throws {
        let compact = Data(#"{"x":0,"y":0,"width":0,"height":0,"floating":{"x":0.5,"y":0.5,"isCompact":true,"isPinned":false}}"#.utf8)
        let preview = Data(#"{"x":0,"y":0,"width":0,"height":0,"floating":{"x":0.5,"y":0.5,"isCompact":false,"isPinned":true,"previewWidth":400}}"#.utf8)
        let tab = try #require(BoardFrame.value(FloatingShapeMigration.migrated(compact))?.floating)
        let live = try #require(BoardFrame.value(FloatingShapeMigration.migrated(preview))?.floating)
        #expect(tab.shape == .tab)
        #expect(live.shape == .live)
        #expect(live.isPinned)
        #expect(live.previewWidth == 400)
        let rewritten = try #require(FloatingShapeMigration.migrated(compact))
        let board = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        let floating = try #require(board["floating"] as? [String: Any])
        #expect(floating["isCompact"] == nil)
    }

    @Test
    func `Migrated data, desk-only data, and no data are left alone`() {
        let migrated = Data(#"{"x":0,"y":0,"width":0,"height":0,"floating":{"x":0.5,"y":0.5,"shape":"icon","isPinned":false}}"#.utf8)
        let desk = Data(#"{"x":120,"y":160,"width":320,"height":200,"isCompact":true}"#.utf8)
        #expect(FloatingShapeMigration.migrated(migrated) == nil)
        #expect(FloatingShapeMigration.migrated(desk) == nil)
        #expect(FloatingShapeMigration.migrated(nil) == nil)
        #expect(BoardFrame.value(migrated)?.floating?.shape == .icon)
    }

    @Test
    func `The desk's own compact flag survives the migration`() throws {
        let data = Data(#"{"x":10,"y":20,"width":320,"height":200,"isCompact":true,"floating":{"x":0.5,"y":0.5,"isCompact":false,"isPinned":false}}"#.utf8)
        let rewritten = try #require(FloatingShapeMigration.migrated(data))
        #expect(BoardFrame.isCompact(rewritten))
        #expect(BoardFrame.decode(rewritten) == CGRect(x: 10, y: 20, width: 320, height: 200))
    }
}
