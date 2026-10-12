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
    func `Compact tabs keep the center of their large preview`() {
        let preview = CGRect(x: 100, y: 200, width: 320, height: 280)
        let compact = CanvasTileLayout.displayedFrame(for: preview, isCompact: true)
        #expect(compact.midX == preview.midX)
        #expect(compact.midY == preview.midY)
        #expect(compact.width < preview.width)
        #expect(compact.height < preview.height)
        #expect(CanvasTileLayout.previewFrame(for: compact, previewSize: preview.size) == preview)
    }

    @Test
    func `Moving a compact tab carries its remembered preview size`() {
        let preview = CGRect(x: 100, y: 200, width: 320, height: 280)
        let compact = CanvasTileLayout.displayedFrame(for: preview, isCompact: true).offsetBy(dx: 470, dy: -130)
        let restored = CanvasTileLayout.previewFrame(for: compact, previewSize: preview.size)
        #expect(restored == preview.offsetBy(dx: 470, dy: -130))
    }

    @Test
    @MainActor
    func `Compact slabs claim their header and lower rim at the table edge`() {
        let desk = CGRect(x: 0, y: 0, width: 1_280, height: 820)
        let compact = CGRect(origin: CGPoint(x: 1_200, y: 800), size: CanvasTileLayout.compactContentSize)
        let resting = CanvasPhysics.keepingOnDesk(compact, desk: desk)
        #expect(desk.contains(CanvasPhysics.collisionBox(resting)))
        #expect(resting.maxY + CanvasPhysics.Constants.slabThickness < desk.maxY)
    }
}
