import CoreGraphics
import Testing
@testable import Refrax

struct FloatingArrangementTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1_280, height: 800)
    private let compact = CGSize(width: 250, height: 34)

    @Test
    func `The arrange area sits beside the island, away from it`() {
        let leftRail = CGRect(x: 12, y: 100, width: 48, height: 400)
        let left = FloatingArrangement.arrangeArea(in: bounds, rail: leftRail)
        #expect(left.minX == leftRail.maxX + FloatingArrangement.gap)
        #expect(left.maxX == bounds.maxX - FloatingArrangement.margin)
        #expect(!FloatingArrangement.fillsFromTrailing(bounds: bounds, rail: leftRail))

        let rightRail = CGRect(x: 1_220, y: 100, width: 48, height: 400)
        let right = FloatingArrangement.arrangeArea(in: bounds, rail: rightRail)
        #expect(right.maxX == rightRail.minX - FloatingArrangement.gap)
        #expect(FloatingArrangement.fillsFromTrailing(bounds: bounds, rail: rightRail))

        #expect(FloatingArrangement.arrangeArea(in: bounds, rail: .zero) == bounds.insetBy(dx: FloatingArrangement.margin, dy: FloatingArrangement.margin))
    }

    @Test
    func `The grid fills a column top to bottom from the island's side`() {
        let area = CGRect(x: 72, y: 16, width: 1_192, height: 768)
        let origins = FloatingArrangement.gridOrigins(for: Array(repeating: compact, count: 3), in: area, fromTrailing: false)
        #expect(origins == [
            CGPoint(x: 72, y: 16),
            CGPoint(x: 72, y: 16 + compact.height + FloatingArrangement.gap),
            CGPoint(x: 72, y: 16 + (compact.height + FloatingArrangement.gap) * 2),
        ])
    }

    @Test
    func `A full column starts the next one, away from a trailing island`() {
        let area = CGRect(x: 16, y: 16, width: 1_000, height: 100)
        let origins = FloatingArrangement.gridOrigins(for: Array(repeating: compact, count: 3), in: area, fromTrailing: true)
        #expect(origins[0].x == area.maxX - compact.width)
        #expect(origins[1].y > origins[0].y)
        #expect(origins[2] == CGPoint(x: area.maxX - compact.width * 2 - FloatingArrangement.gap, y: area.minY))
    }

    @Test
    func `Columns are as wide as the widest cell, so cards line up`() {
        let area = CGRect(x: 0, y: 0, width: 1_000, height: 260)
        let sizes = [CGSize(width: 340, height: 250), compact, compact]
        let origins = FloatingArrangement.gridOrigins(for: sizes, in: area, fromTrailing: false)
        #expect(origins[1].x == 340 + FloatingArrangement.gap)
        #expect(origins[2].x == origins[1].x)
        #expect(FloatingArrangement.gridOrigins(for: [], in: area, fromTrailing: false).isEmpty)
    }

    @Test
    func `Site stacks keep sites with two or more cards, in first-seen order`() {
        let stacks = FloatingArrangement.siteStacks([
            (id: 1, site: "github.com"),
            (id: 2, site: "apple.com"),
            (id: 3, site: "github.com"),
            (id: 4, site: nil),
            (id: 5, site: "swift.org"),
            (id: 6, site: "apple.com"),
            (id: 7, site: ""),
        ])
        #expect(stacks.map { $0.site } == ["github.com", "apple.com"])
        #expect(stacks.map { $0.ids } == [[1, 3], [2, 6]])
    }

    @Test
    func `A moving selection stays inside the window`() {
        let selection = CGRect(x: 100, y: 100, width: 400, height: 200)
        let area = CGRect(x: 16, y: 16, width: 1_248, height: 768)
        let clamped = FloatingArrangement.clampedTranslation(CGSize(width: -500, height: 900), moving: selection, in: area)
        #expect(clamped.width == area.minX - selection.minX)
        #expect(clamped.height == area.maxY - selection.maxY)
        #expect(FloatingArrangement.clampedTranslation(CGSize(width: 20, height: -30), moving: selection, in: area) == CGSize(width: 20, height: -30))
    }

    @Test
    func `The options capsule sits under the selection, or above it at the bottom edge`() {
        let size = CGSize(width: 300, height: 36)
        let below = FloatingArrangement.capsuleOrigin(for: CGRect(x: 400, y: 100, width: 200, height: 100), size: size, in: bounds)
        #expect(below == CGPoint(x: 350, y: 200 + FloatingArrangement.gap))
        let above = FloatingArrangement.capsuleOrigin(for: CGRect(x: 400, y: 700, width: 200, height: 90), size: size, in: bounds)
        #expect(above.y == 700 - FloatingArrangement.gap - size.height)
        let edge = FloatingArrangement.capsuleOrigin(for: CGRect(x: 1_200, y: 100, width: 60, height: 40), size: size, in: bounds)
        #expect(edge.x + size.width <= bounds.maxX)
    }
}
