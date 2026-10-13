import CoreGraphics
import Testing
@testable import Refrax

struct LassoSelectionTests {
    private func square(from origin: CGPoint, side: CGFloat) -> LassoSelection {
        var lasso = LassoSelection(at: origin)
        lasso.extend(to: CGPoint(x: origin.x + side, y: origin.y))
        lasso.extend(to: CGPoint(x: origin.x + side, y: origin.y + side))
        lasso.extend(to: CGPoint(x: origin.x, y: origin.y + side))
        return lasso
    }

    @Test
    func `A drag draws only after it passes the threshold`() {
        var lasso = LassoSelection(at: .zero)
        let belowThreshold = lasso.extend(to: CGPoint(x: 2, y: 2))
        #expect(!belowThreshold)
        #expect(!lasso.isDrawing)
        let atThreshold = lasso.extend(to: CGPoint(x: LassoSelection.threshold, y: 0))
        #expect(atThreshold)
        #expect(lasso.isDrawing)
        #expect(lasso.points.count == 2)
    }

    @Test
    func `A card is caught when its center is inside the closed lasso`() {
        let lasso = square(from: CGPoint(x: 100, y: 100), side: 300)
        let frames = [
            (id: "inside", frame: CGRect(x: 150, y: 150, width: 100, height: 40)),
            (id: "straddling", frame: CGRect(x: 350, y: 200, width: 200, height: 40)),
            (id: "outside", frame: CGRect(x: 600, y: 600, width: 100, height: 40)),
        ]
        #expect(lasso.caught(frames) == ["inside"])
    }

    @Test
    func `A lasso too short to enclose anything catches nothing`() {
        var lasso = LassoSelection(at: .zero)
        lasso.extend(to: CGPoint(x: 100, y: 100))
        #expect(!lasso.canCatch)
        #expect(lasso.caught([(id: 1, frame: CGRect(x: 40, y: 40, width: 20, height: 20))]).isEmpty)
    }
}
