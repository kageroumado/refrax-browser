import CoreGraphics
import Testing
@testable import Refrax

struct FloatingGroupLayoutTests {
    private let area = CGRect(x: 0, y: 0, width: 1_280, height: 800)

    @Test
    func `Radii are concentric from the header out to the cards`() {
        #expect(FloatingGroupLayout.outlineRadius == FloatingGroupLayout.headerHeight / 2 + FloatingGroupLayout.headerInset)
        #expect(FloatingGroupLayout.concentricRadius(outer: FloatingGroupLayout.outlineRadius, inset: FloatingGroupLayout.headerInset)
            == FloatingGroupLayout.headerHeight / 2)
        #expect(FloatingGroupLayout.concentricRadius(outer: FloatingGroupLayout.outlineRadius, inset: FloatingGroupLayout.cardPadding)
            == CanvasTileLayout.slabCornerRadius)
        #expect(FloatingGroupLayout.concentricRadius(outer: 4, inset: 10) == 0)
    }

    @Test
    func `The outline holds every member with the header above them`() throws {
        let cards = [CGRect(x: 200, y: 200, width: 250, height: 34), CGRect(x: 500, y: 300, width: 340, height: 250)]
        let outline = try #require(FloatingGroupLayout.outlineFrame(around: cards, in: area))
        for card in cards {
            #expect(outline.contains(card))
        }
        #expect(outline.minY == 200 - FloatingGroupLayout.topPadding)
        #expect(outline.minX == 200 - FloatingGroupLayout.cardPadding)
        let header = FloatingGroupLayout.headerFrame(in: outline, width: 120)
        #expect(header.maxY + FloatingGroupLayout.headerGap == cards[0].minY)
        #expect(FloatingGroupLayout.outlineFrame(around: [], in: area) == nil)
    }

    @Test
    func `The outline stays inside the window`() throws {
        let outline = try #require(FloatingGroupLayout.outlineFrame(around: [CGRect(x: 4, y: 10, width: 250, height: 34)], in: area))
        #expect(area.contains(outline))
    }

    @Test
    func `A folded header keeps the unfolded header's place`() {
        let outline = CGRect(x: 100, y: 100, width: 600, height: 400)
        let folded = FloatingGroupLayout.foldedHeaderFrame(in: outline, width: 140)
        let unfolded = FloatingGroupLayout.headerFrame(in: outline, width: 140)
        #expect(folded == unfolded)
        #expect(FloatingGroupLayout.foldedHeaderFrame(in: outline, width: 900).width == FloatingGroupLayout.maximumHeaderWidth)
    }

    @Test
    func `An unfolded header never outgrows its outline`() {
        let outline = CGRect(x: 0, y: 0, width: 120, height: 200)
        let header = FloatingGroupLayout.headerFrame(in: outline, width: 400)
        #expect(header.maxX <= outline.maxX - FloatingGroupLayout.headerInset)
    }

    @Test
    func `Piled members put the folded header at the requested spot`() throws {
        let headerOrigin = CGPoint(x: 300, y: 120)
        let member = FloatingGroupLayout.memberOrigin(forHeaderAt: headerOrigin)
        let card = CGRect(origin: member, size: CGSize(width: 250, height: 34))
        let outline = try #require(FloatingGroupLayout.outlineFrame(around: [card], in: area))
        #expect(FloatingGroupLayout.foldedHeaderFrame(in: outline, width: 100).origin == headerOrigin)
    }

    @Test
    func `A pile is cards at one origin`() {
        let card = CGRect(x: 40, y: 40, width: 250, height: 34)
        #expect(FloatingGroupLayout.isPiled([card, card.offsetBy(dx: 1, dy: -1)]))
        #expect(!FloatingGroupLayout.isPiled([card, card.offsetBy(dx: 40, dy: 0)]))
        #expect(!FloatingGroupLayout.isPiled([card]))
    }

    @Test
    func `Fanning a pile lays its cards out in a square without overlap`() {
        let size = CGSize(width: 250, height: 34)
        let origins = FloatingGroupLayout.fanOrigins(count: 5, size: size, from: CGPoint(x: 100, y: 100), in: area)
        #expect(origins.count == 5)
        #expect(origins[0] == CGPoint(x: 100, y: 100))
        #expect(Set(origins.map(\.y)).count == 2)
        let frames = origins.map { CGRect(origin: $0, size: size) }
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] {
                #expect(!frame.intersects(other))
            }
        }
    }

    @Test
    func `Fanning near the trailing edge turns back into the window`() {
        let size = CGSize(width: 250, height: 34)
        let origins = FloatingGroupLayout.fanOrigins(count: 4, size: size, from: CGPoint(x: 1_200, y: 100), in: area)
        #expect(origins.allSatisfy { $0.x + size.width <= area.maxX })
    }

    @Test
    func `A nested group wins a drop over its parent`() {
        let parent = CGRect(x: 0, y: 0, width: 800, height: 600)
        let nested = CGRect(x: 100, y: 100, width: 300, height: 200)
        let targets = [(id: "parent", frame: parent), (id: "nested", frame: nested)]
        #expect(FloatingGroupLayout.dropTarget(at: CGPoint(x: 150, y: 150), among: targets) == "nested")
        #expect(FloatingGroupLayout.dropTarget(at: CGPoint(x: 700, y: 500), among: targets) == "parent")
        #expect(FloatingGroupLayout.dropTarget(at: CGPoint(x: 900, y: 700), among: targets) == nil)
    }
}
