import Foundation
import Testing
@testable import Refrax

struct OutsideClickDismissalTests {
    private typealias Dismissal = OutsideClickDismissal
    private let drawer = CGRect(x: 1_252, y: 8, width: 280, height: 900)

    // MARK: - Clicks

    @Test
    func `a click with nothing open goes through`() {
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 400, y: 400), in: .init()) == .pass)
    }

    @Test
    func `a click beside a sheet cancels it and stops there`() {
        let scene = Dismissal.Scene(hasDismissibleSheet: true)
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 40, y: 40), in: scene) == .cancelSheet)
    }

    @Test
    func `a click outside the drawer closes it, a click inside it goes through`() {
        let scene = Dismissal.Scene(panelFrames: [drawer])
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 300, y: 500), in: scene) == .dismissPanel(0))
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 1_400, y: 500), in: scene) == .pass)
    }

    @Test
    func `a drawer not laid out yet counts every click as outside`() {
        let scene = Dismissal.Scene(panelFrames: [.null])
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 1_400, y: 500), in: scene) == .dismissPanel(0))
    }

    @Test
    func `one layer per click, the newest first`() {
        let popoverOverAll = Dismissal.Scene(popoverAboveClick: true, hasDismissibleSheet: true, panelFrames: [drawer])
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 300, y: 500), in: popoverOverAll) == .swallow)

        let sheetOverDrawer = Dismissal.Scene(hasDismissibleSheet: true, panelFrames: [drawer])
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 1_400, y: 500), in: sheetOverDrawer) == .cancelSheet)

        let twoPanels = Dismissal.Scene(panelFrames: [drawer, CGRect(x: 0, y: 0, width: 100, height: 100)])
        #expect(Dismissal.mouseDownAction(at: CGPoint(x: 1_400, y: 500), in: twoPanels) == .dismissPanel(1))
    }

    @Test
    func `a popover's own close counts for the click that caused it`() {
        #expect(Dismissal.popoverClosed(at: 100.02, for: 100.0))
        #expect(!Dismissal.popoverClosed(at: 99.9, for: 100.0))
        #expect(!Dismissal.popoverClosed(at: 101.0, for: 100.0))
        #expect(!Dismissal.popoverClosed(at: nil, for: 100.0))
    }

    // MARK: - Esc

    @Test
    func `Esc closes the newest popover, then the drawer`() {
        let both = Dismissal.EscapeScene(popoverCount: 2, panelCount: 1)
        #expect(Dismissal.escapeAction(in: both) == .closePopover(1))
        #expect(Dismissal.escapeAction(in: .init(panelCount: 1)) == .dismissPanel(0))
    }

    @Test
    func `Esc belongs to text being composed and to a sheet's own handling`() {
        #expect(Dismissal.escapeAction(in: .init(isComposingText: true, popoverCount: 1, panelCount: 1)) == .pass)
        #expect(Dismissal.escapeAction(in: .init(hasAttachedSheet: true, panelCount: 1)) == .pass)
        #expect(Dismissal.escapeAction(in: .init()) == .pass)
    }
}
