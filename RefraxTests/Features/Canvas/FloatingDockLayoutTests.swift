import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct FloatingDockLayoutTests {
    private let window = CGRect(x: 0, y: 0, width: 1_280, height: 800)
    private let margin = FloatingDockLayout.margin

    @Test
    func `A docked column fills its side at full height, concentric with the window`() throws {
        let columns = FloatingDockLayout.columns(leading: nil, trailing: FloatingDockLayout.defaultFraction, in: window, rail: nil)
        let column = try #require(columns.trailing)
        #expect(columns.leading == nil)
        #expect(column.maxX == window.maxX - margin)
        #expect(column.minY == margin)
        #expect(column.height == window.height - margin * 2)
        #expect(abs(column.width - window.width * CGFloat(FloatingDockLayout.defaultFraction)) < 0.001)
        #expect(FloatingDockLayout.cornerRadius == FloatingDockLayout.windowCornerRadius - margin)
    }

    @Test
    func `The page reflows beside the column with a margin between them`() throws {
        let columns = FloatingDockLayout.columns(leading: 0.3, trailing: nil, in: window, rail: nil)
        let column = try #require(columns.leading)
        let page = FloatingDockLayout.pageFrame(beside: columns, in: window)
        #expect(page.minX == column.maxX + margin)
        #expect(page.maxX == window.maxX)
        #expect(page.height == window.height)
        #expect(FloatingDockLayout.pageFrame(beside: .init(), in: window) == window)
    }

    @Test
    func `A column keeps its minimum width`() throws {
        let column = try #require(FloatingDockLayout.columns(leading: 0.05, trailing: nil, in: window, rail: nil).leading)
        #expect(column.width == FloatingDockLayout.minimumColumnWidth)
    }

    @Test
    func `A wide column leaves the page its minimum width`() {
        let columns = FloatingDockLayout.columns(leading: 0.95, trailing: nil, in: window, rail: nil)
        let page = FloatingDockLayout.pageFrame(beside: columns, in: window)
        #expect(abs(page.width - FloatingDockLayout.minimumPageWidth) < 0.001)
    }

    @Test
    func `Two columns share the room the page leaves them`() throws {
        let columns = FloatingDockLayout.columns(leading: 0.38, trailing: 0.38, in: window, rail: nil)
        let leading = try #require(columns.leading)
        let trailing = try #require(columns.trailing)
        let page = FloatingDockLayout.pageFrame(beside: columns, in: window)
        #expect(abs(page.width - FloatingDockLayout.minimumPageWidth) < 0.001)
        #expect(abs(leading.width - trailing.width) < 0.001)
        #expect(leading.width >= FloatingDockLayout.minimumColumnWidth)
    }

    @Test
    func `In a narrow window the columns keep their minimum before the page does`() throws {
        let narrow = CGRect(x: 0, y: 0, width: 900, height: 600)
        let columns = FloatingDockLayout.columns(leading: 0.5, trailing: 0.5, in: narrow, rail: nil)
        #expect(try #require(columns.leading).width == FloatingDockLayout.minimumColumnWidth)
        #expect(try #require(columns.trailing).width == FloatingDockLayout.minimumColumnWidth)
    }

    @Test
    func `A column starts past the rail resting on its side`() throws {
        let rail = CGRect(x: 12, y: 160, width: 48, height: 420)
        let leading = try #require(FloatingDockLayout.columns(leading: 0.3, trailing: nil, in: window, rail: rail).leading)
        #expect(leading.minX == rail.maxX + margin)
        #expect(!leading.intersects(rail))
        let trailing = try #require(FloatingDockLayout.columns(leading: nil, trailing: 0.3, in: window, rail: rail).trailing)
        #expect(trailing.maxX == window.maxX - margin)
    }

    @Test
    func `A rail away from the sides leaves the columns where they are`() throws {
        let rail = CGRect(x: 600, y: 12, width: 48, height: 420)
        #expect(!FloatingDockLayout.railRests(on: .leading, rail: rail, in: window))
        #expect(!FloatingDockLayout.railRests(on: .trailing, rail: rail, in: window))
        let column = try #require(FloatingDockLayout.columns(leading: 0.3, trailing: nil, in: window, rail: rail).leading)
        #expect(column.minX == margin)
    }

    @Test
    func `A card docks when the pointer comes near a side`() {
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: 10, y: 400), in: window, rail: nil) == .leading)
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: -30, y: 400), in: window, rail: nil) == .leading)
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: 1_270, y: 400), in: window, rail: nil) == .trailing)
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: 640, y: 400), in: window, rail: nil) == nil)
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: 10, y: 900), in: window, rail: nil) == nil)
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: 40, y: 400), in: window, rail: nil) == nil)
    }

    @Test
    func `With the rail on a side the snap zone reaches past the rail`() {
        let rail = CGRect(x: 1_220, y: 100, width: 48, height: 400)
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: 1_200, y: 400), in: window, rail: rail) == .trailing)
        #expect(FloatingDockLayout.snapEdge(at: CGPoint(x: 1_180, y: 400), in: window, rail: rail) == nil)
    }

    @Test
    func `Dragging the seam sets the fraction, clamped`() throws {
        let fraction = FloatingDockLayout.fraction(forSeamAt: 500, edge: .leading, opposite: nil, in: window, rail: nil)
        let column = try #require(FloatingDockLayout.columns(leading: fraction, trailing: nil, in: window, rail: nil).leading)
        #expect(abs(column.maxX + margin / 2 - 500) < 0.001)
        let seam = FloatingDockLayout.seamFrame(beside: column, edge: .leading)
        #expect(abs(seam.midX - 500) < 0.001)

        let tooNarrow = FloatingDockLayout.fraction(forSeamAt: 1_250, edge: .trailing, opposite: nil, in: window, rail: nil)
        #expect(abs(tooNarrow - Double(FloatingDockLayout.minimumColumnWidth / window.width)) < 0.001)
        let tooWide = FloatingDockLayout.fraction(forSeamAt: 1_200, edge: .leading, opposite: nil, in: window, rail: nil)
        let wide = try #require(FloatingDockLayout.columns(leading: tooWide, trailing: nil, in: window, rail: nil).leading)
        #expect(abs(window.maxX - (wide.maxX + margin) - FloatingDockLayout.minimumPageWidth) < 0.001)
    }

    @Test
    func `A header dragged toward the page or far away undocks`() {
        #expect(FloatingDockLayout.undocks(after: CGSize(width: 60, height: 0), from: .leading))
        #expect(!FloatingDockLayout.undocks(after: CGSize(width: -60, height: 0), from: .leading))
        #expect(FloatingDockLayout.undocks(after: CGSize(width: -60, height: 0), from: .trailing))
        #expect(!FloatingDockLayout.undocks(after: CGSize(width: 20, height: 30), from: .trailing))
        #expect(FloatingDockLayout.undocks(after: CGSize(width: 0, height: 120), from: .trailing))
    }

    @Test
    func `A stored placement without a dock decodes undocked at the default width`() throws {
        let json = Data(#"{"x":0.2,"y":0.4,"isCompact":false,"isPinned":true}"#.utf8)
        let placement = try JSONDecoder().decode(FloatingTabPlacement.self, from: json)
        #expect(placement.dock == nil)
        #expect(!placement.isDocked)
        #expect(placement.dockWidthFraction == FloatingDockLayout.defaultFraction)

        var docked = placement
        docked.dock = .trailing
        docked.dockFraction = 0.5
        let decoded = try JSONDecoder().decode(FloatingTabPlacement.self, from: JSONEncoder().encode(docked))
        #expect(decoded == docked)
        #expect(decoded.frame(in: window) == placement.frame(in: window))
    }
}
