import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct CanvasTileLayoutTests {
    @Test
    func `Saved layouts without a size choice open as previews`() {
        let data = Data(#"{"x":120,"y":160,"width":320,"height":200}"#.utf8)
        #expect(BoardFrame.decode(data) == CGRect(x: 120, y: 160, width: 320, height: 200))
        #expect(!BoardFrame.isCompact(data))
    }

    @Test
    func `Compact choice and preview geometry survive serialization`() throws {
        let preview = CGRect(x: 180, y: 340, width: 320, height: 240)
        let data = try #require(BoardFrame.encode(preview, isCompact: true))
        #expect(BoardFrame.isCompact(data))
        #expect(BoardFrame.decode(data) == preview)
    }

    @Test
    @MainActor
    func `Compact slabs claim their header and lower rim at the table edge`() {
        let desk = CGRect(x: 0, y: 0, width: 1_280, height: 820)
        let compact = CGRect(origin: CGPoint(x: 1_200, y: 800), size: FloatingCardShape.tab.naturalSize)
        let resting = CanvasPhysics.keepingOnDesk(compact, desk: desk)
        #expect(desk.contains(CanvasPhysics.collisionBox(resting)))
        #expect(resting.maxY + CanvasPhysics.Constants.slabThickness < desk.maxY)
    }
}
