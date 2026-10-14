import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct FloatingCardChromeTests {
    // MARK: Radius and shadow by state

    @Test
    func `Kept cards are rounder than transient ones`() {
        #expect(FloatingCardChrome.cornerRadius(for: .live, isKept: true) == 16)
        #expect(FloatingCardChrome.cornerRadius(for: .live, isKept: false) == 12)
        #expect(FloatingCardChrome.cornerRadius(for: .tab, isKept: true) == 16)
        #expect(FloatingCardChrome.cornerRadius(for: .tab, isKept: false) == 12)
    }

    @Test
    func `An icon is a squircle, rounder when kept`() {
        #expect(FloatingCardChrome.cornerRadius(for: .icon, isKept: true) == 12)
        #expect(FloatingCardChrome.cornerRadius(for: .icon, isKept: false) == 10)
    }

    @Test(arguments: [true, false])
    func `The preview is concentric with its card`(isKept: Bool) {
        let outer = FloatingCardChrome.cornerRadius(for: .live, isKept: isKept)
        #expect(FloatingCardChrome.previewCornerRadius(isKept: isKept) == outer - FloatingTabPlacement.previewInset)
        #expect(FloatingCardChrome.previewCornerRadius(isKept: true) == 10)
    }

    @Test
    func `Kept cards cast the softer, wider window shadow`() {
        let window = FloatingCardChrome.shadow(isKept: true)
        let card = FloatingCardChrome.shadow(isKept: false)
        #expect(window == FloatingCardChrome.windowShadow)
        #expect(card == FloatingCardChrome.cardShadow)
        #expect(window.radius > card.radius)
        #expect(window.y > card.y)
    }

    // MARK: Header

    @Test
    func `The favicon sits as far from the leading edge as from the top`() {
        typealias Header = FloatingCardChrome.Header
        #expect(Header.leadingPadding == (Header.height - Header.glyphBox) / 2)
        #expect(Header.edgeGap == 9)
    }

    @Test
    func `The last control's glyph sits as far from the trailing edge as the favicon from the leading`() {
        typealias Header = FloatingCardChrome.Header
        #expect(Header.trailingPadding + Header.controlPadding == Header.leadingPadding)
        #expect(Header.controlSize == Header.glyphBox + 2 * Header.controlPadding)
        #expect(Header.controlSize <= Header.height)
    }

    @Test
    func `Identity items and controls are spaced alike`() {
        typealias Header = FloatingCardChrome.Header
        // Two neighboring controls, laid out with no spacing, leave two paddings between glyphs.
        #expect(Header.itemSpacing == Header.controlPadding * 2)
    }

    // MARK: Tear-off

    @Test
    func `The card leaves only past the threshold outside the window`() {
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!FloatingTearOff.isTornOff(pointer: CGPoint(x: 500, y: 400), from: window))
        #expect(!FloatingTearOff.isTornOff(pointer: CGPoint(x: 900 + FloatingTearOff.threshold - 1, y: 400), from: window))
        #expect(FloatingTearOff.isTornOff(pointer: CGPoint(x: 900 + FloatingTearOff.threshold + 1, y: 400), from: window))
        #expect(FloatingTearOff.isTornOff(pointer: CGPoint(x: 500, y: 100 - FloatingTearOff.threshold - 1), from: window))
        #expect(FloatingTearOff.threshold == 24)
    }

    @Test
    func `The copy keeps the pointer where it held the card`() {
        let frame = FloatingTearOff.ghostFrame(pointer: CGPoint(x: 400, y: 300), grab: CGPoint(x: 40, y: 10), size: CGSize(width: 250, height: 34))
        #expect(frame.minX == 360)
        #expect(frame.maxY == 310)
        #expect(frame.size == CGSize(width: 250, height: 34))
    }

    @Test
    func `The new window's title bar lands under the pointer`() {
        let visible = CGRect(x: 0, y: 0, width: 2_000, height: 1_200)
        let frame = FloatingTearOff.windowFrame(
            size: CGSize(width: 800, height: 600), pointer: CGPoint(x: 1_000, y: 900), grabFraction: 0.25, titleBarHeight: 40, within: visible,
        )
        #expect(frame.minX == 800)
        #expect(frame.maxY == 920)
        #expect(frame.size == CGSize(width: 800, height: 600))
    }

    @Test
    func `The new window stays on the screen`() {
        let visible = CGRect(x: 0, y: 0, width: 1_400, height: 900)
        let frame = FloatingTearOff.windowFrame(
            size: CGSize(width: 800, height: 600), pointer: CGPoint(x: 1_390, y: 890), grabFraction: 0.1, titleBarHeight: 40, within: visible,
        )
        #expect(visible.contains(frame))
        #expect(frame.maxX == visible.maxX)
        #expect(frame.maxY == visible.maxY)
    }

    // MARK: Clearance from the island's rail

    @Test
    func `A card beside the rail keeps the island's adjacent gap`() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let rail = CGRect(x: 12, y: 160, width: 48, height: 300)
        var placement = FloatingTabPlacement(x: 0, y: 0.3, shape: .tab, isPinned: false)
        placement.move(to: CGPoint(x: rail.maxX + 3.5, y: 200), in: bounds)
        placement.keepClear(of: rail, gap: ControlIslandPlacement.adjacentGap, in: bounds)
        let frame = placement.frame(in: bounds)
        #expect(abs(frame.minX - (rail.maxX + ControlIslandPlacement.adjacentGap)) < 0.5)
    }

    @Test
    func `A card already clear of the rail stays put`() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let rail = CGRect(x: 12, y: 160, width: 48, height: 300)
        var placement = FloatingTabPlacement(x: 0.5, y: 0.5, shape: .tab, isPinned: false)
        let before = placement
        placement.keepClear(of: rail, gap: ControlIslandPlacement.adjacentGap, in: bounds)
        #expect(placement == before)
    }

    // MARK: Beam between windows

    @Test
    func `The beam's panel holds both ends and their halos`() {
        let source = CGRect(x: 100, y: 100, width: 200, height: 100)
        let destination = CGRect(x: 600, y: 400, width: 800, height: 600)
        let panel = ScreenBeam.panelFrame(from: source, to: destination)
        #expect(panel.contains(source.union(destination)))
        let local = ScreenBeam.local(destination, in: panel)
        #expect(local.minY == panel.maxY - destination.maxY)
        #expect(local.minX == destination.minX - panel.minX)
    }
}
