import AppKit
import Testing
@testable import Refrax

/// The page icon's row on a rail at either window edge; Ely keeps hers on the right.
private nonisolated enum RailIcon {
    static let right = CGRect(x: 1_388, y: 300, width: 44, height: 26)
    static let left = CGRect(x: 8, y: 300, width: 44, height: 26)
}

/// The rail's page icon, as the rail would report it, for the input to read.
@MainActor
private final class ReportedIcon {
    var frame: CGRect?
    init(_ frame: CGRect?) {
        self.frame = frame
    }
}

@MainActor
private final class TabIconScrollFixture {
    let env: TabManagerTestEnvironment
    let space: Space
    let window: WindowState
    let canvas: TabCanvasManager
    let islands: IslandController
    let input: IslandInput
    let icon: ReportedIcon
    let defaults: UserDefaults
    let bounds = CGRect(x: 0, y: 0, width: 1_440, height: 1_080)
    private let suite = "TabIconScrollTests.\(UUID().uuidString)"

    init(icon frame: CGRect? = RailIcon.right) throws {
        self.env = try TabManagerTestEnvironment()
        self.space = env.makeSpace()
        self.window = env.makeActiveWindowState(with: space)
        self.canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
        self.defaults = try #require(UserDefaults(suiteName: suite))
        self.islands = IslandController(
            windowState: window, tabManager: env.tabManager, groupManager: env.groupManager, canvas: canvas, pagePool: env.pagePool,
            defaults: self.defaults,
        )
        let icon = ReportedIcon(frame)
        self.icon = icon
        self.input = IslandInput(islands: islands, canvas: canvas, tabIcon: { icon.frame })
        window.islandController = islands
        islands.start()
        islands.updateArea(bounds.insetBy(dx: 16, dy: 16), in: bounds)
    }

    isolated deinit { islands.stop() }

    /// Three tabs on one island, in the island's row order, the middle one current.
    func threeTabs() -> [Refrax.Tab] {
        for title in ["First", "Second", "Third"] {
            let tab = env.tabManager.createTab(url: .blank, in: space, makeActive: false, loadImmediately: false)
            tab.activePage.title = title
        }
        islands.refresh()
        let rows = (islands.island(space.id)?.tabIDs ?? []).compactMap { islands.tab(for: $0) }
        precondition(rows.count == 3, "three rows on the island")
        window.setActiveTabID(rows[1].id, for: space.id)
        return rows
    }

    /// A point on the icon, or `dx`/`dy` away from its middle.
    func onIcon(dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        let frame = icon.frame ?? RailIcon.right
        return CGPoint(x: frame.midX + dx, y: frame.midY + dy)
    }

    /// Somewhere over the page, far from the rail.
    var onPage: CGPoint { CGPoint(x: 700, y: 500) }

    /// Routes a sample with the pointer at `point`; the window lets the islands reveal, and
    /// the pointer is over the controls when it is on the icon.
    @discardableResult
    func route(_ sample: TableScrollRouter.Sample, at point: CGPoint, keyHeld: Bool = false, eligible: Bool = true) -> Bool {
        let overControls = TabIconScrollHold.icon(icon.frame, holds: point, slack: 0)
        return input.route(sample, keyHeld: keyHeld, at: point, eligible: { eligible }, overControls: { overControls })
    }

    /// The page view finished the move a step began.
    func settleTravel() {
        if let id = islands.travel?.id {
            islands.finishTravel(id)
        }
    }
}

private func gesture(_ phase: NSEvent.Phase, _ dx: CGFloat = 0, _ dy: CGFloat = 0) -> TableScrollRouter.Sample {
    TableScrollRouter.Sample(source: .trackpad, phase: phase, delta: CGSize(width: dx, height: dy))
}

private func momentum(_ phase: NSEvent.Phase, _ dx: CGFloat = 0, _ dy: CGFloat = 0) -> TableScrollRouter.Sample {
    TableScrollRouter.Sample(source: .trackpad, momentumPhase: phase, delta: CGSize(width: dx, height: dy))
}

private func wheel(_ dx: CGFloat, _ dy: CGFloat) -> TableScrollRouter.Sample {
    TableScrollRouter.Sample(source: .wheel, delta: CGSize(width: dx, height: dy))
}

@Suite("Scrolling on the rail's page icon")
@MainActor
struct TabIconScrollHoldTests {
    private let icon = CGRect(x: 1_388, y: 300, width: 44, height: 26)

    @Test
    func `Before a hold, only a scroll on the icon itself is claimed`() {
        let hold = TabIconScrollHold()
        #expect(hold.claims(CGPoint(x: 1_400, y: 310), icon: icon))
        #expect(hold.claims(CGPoint(x: 1_400, y: 328), icon: icon) == false)
        #expect(hold.claims(CGPoint(x: 1_386, y: 310), icon: icon) == false)
        #expect(hold.claims(CGPoint(x: 1_400, y: 310), icon: nil) == false)
        #expect(hold.claims(CGPoint(x: 1_400, y: 310), icon: .zero) == false)
    }

    @Test
    func `A hold begins once and reads the icon with slack`() {
        var hold = TabIconScrollHold()
        let began = hold.begin()
        #expect(began)
        #expect(hold.isHolding)
        let beganAgain = hold.begin()
        #expect(beganAgain == false)
        #expect(hold.claims(CGPoint(x: 1_400, y: 329), icon: icon))
        let endedNear = hold.pointerMoved(to: CGPoint(x: 1_434, y: 310), icon: icon)
        #expect(endedNear == false)
        #expect(hold.isHolding)
        let endedFar = hold.pointerMoved(to: CGPoint(x: 1_440, y: 310), icon: icon)
        #expect(endedFar)
        #expect(hold.isHolding == false)
    }

    @Test
    func `The pointer moving with no hold on changes nothing`() {
        var hold = TabIconScrollHold()
        let ended = hold.pointerMoved(to: CGPoint(x: 10, y: 10), icon: icon)
        #expect(ended == false)
        let wasOn = hold.end()
        #expect(wasOn == false)
    }

    @Test
    func `The rail going away ends the hold at the next pointer move`() {
        var hold = TabIconScrollHold()
        _ = hold.begin()
        let ended = hold.pointerMoved(to: CGPoint(x: 1_400, y: 310), icon: nil)
        #expect(ended)
        #expect(hold.isHolding == false)
    }

    @Test
    func `Ending from elsewhere reports whether a hold was on`() {
        var hold = TabIconScrollHold()
        _ = hold.begin()
        let wasOn = hold.end()
        #expect(wasOn)
        let wasStillOn = hold.end()
        #expect(wasStillOn == false)
    }
}

@Suite("Scrolling on the rail's page icon steps between tabs", .serialized)
@MainActor
struct TabIconScrollInputTests {
    @Test(arguments: [RailIcon.right, RailIcon.left])
    func `A swipe on the icon holds the islands revealed and steps once, whichever side the rail is on`(icon: CGRect) throws {
        let fixture = try TabIconScrollFixture(icon: icon)
        let tabs = fixture.threeTabs()
        #expect(fixture.route(gesture(.began), at: fixture.onIcon()))
        #expect(fixture.canvas.floatingVisibility.isHeld)
        #expect(fixture.input.holdsOnTabIcon)
        #expect(fixture.route(gesture(.changed, 0, -30), at: fixture.onIcon()))
        #expect(fixture.window.activeTabID == tabs[1].id)
        #expect(fixture.route(gesture(.changed, 0, -30), at: fixture.onIcon()))
        #expect(fixture.window.activeTabID == tabs[2].id)
        fixture.settleTravel()
        // The rest of the gesture and its momentum are swallowed without another step.
        #expect(fixture.route(gesture(.changed, 0, -80), at: fixture.onIcon()))
        #expect(fixture.route(gesture(.ended), at: fixture.onIcon()))
        #expect(fixture.route(momentum(.began, 0, -20), at: fixture.onIcon()))
        #expect(fixture.route(momentum(.changed, 0, -60), at: fixture.onIcon()))
        #expect(fixture.route(momentum(.ended), at: fixture.onIcon()))
        #expect(fixture.window.activeTabID == tabs[2].id)
        #expect(fixture.canvas.floatingVisibility.isHeld)
    }

    @Test
    func `A second swipe with the pointer still on the icon steps again`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        fixture.route(gesture(.began), at: fixture.onIcon())
        fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon())
        fixture.route(gesture(.ended), at: fixture.onIcon())
        fixture.route(momentum(.began, 0, -10), at: fixture.onIcon())
        fixture.route(momentum(.ended), at: fixture.onIcon())
        fixture.settleTravel()
        #expect(fixture.window.activeTabID == tabs[2].id)
        #expect(fixture.route(gesture(.began), at: fixture.onIcon()))
        #expect(fixture.route(gesture(.changed, 0, 60), at: fixture.onIcon()))
        #expect(fixture.window.activeTabID == tabs[1].id)
        #expect(fixture.canvas.floatingVisibility.isHeld)
    }

    @Test
    func `Leaving the icon lets the islands go and swallows the rest of the gesture`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        fixture.route(gesture(.began), at: fixture.onIcon())
        fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon())
        fixture.route(gesture(.ended), at: fixture.onIcon())
        fixture.route(momentum(.began, 0, -20), at: fixture.onIcon())
        fixture.settleTravel()
        fixture.input.pointerMoved(to: fixture.onPage, keyHeld: false)
        #expect(fixture.input.holdsOnTabIcon == false)
        #expect(fixture.canvas.floatingVisibility.isHeld == false)
        #expect(fixture.window.activeTabID == tabs[2].id)
        // Momentum still arriving neither scrolls the page nor steps.
        #expect(fixture.route(momentum(.changed, 0, -60), at: fixture.onPage))
        #expect(fixture.route(momentum(.ended), at: fixture.onPage))
        #expect(fixture.window.activeTabID == tabs[2].id)
        // The next gesture over the page, with no key, is the page's.
        #expect(fixture.route(gesture(.began), at: fixture.onPage) == false)
        #expect(fixture.route(gesture(.changed, 0, -60), at: fixture.onPage) == false)
        #expect(fixture.window.activeTabID == tabs[2].id)
    }

    @Test
    func `A pointer drifting a little keeps the hold; farther ends it`() throws {
        let fixture = try TabIconScrollFixture()
        _ = fixture.threeTabs()
        fixture.route(gesture(.began), at: fixture.onIcon())
        fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon())
        fixture.input.pointerMoved(to: fixture.onIcon(dx: 24), keyHeld: false)
        #expect(fixture.input.holdsOnTabIcon)
        #expect(fixture.canvas.floatingVisibility.isHeld)
        fixture.input.pointerMoved(to: fixture.onIcon(dy: 22), keyHeld: false)
        #expect(fixture.input.holdsOnTabIcon == false)
        #expect(fixture.canvas.floatingVisibility.isHeld == false)
    }

    @Test
    func `Fingers resting on the trackpad over the icon reveal nothing`() throws {
        let fixture = try TabIconScrollFixture()
        _ = fixture.threeTabs()
        #expect(fixture.route(gesture(.mayBegin), at: fixture.onIcon()) == false)
        #expect(fixture.input.holdsOnTabIcon == false)
        #expect(fixture.canvas.floatingVisibility.isHeld == false)
    }

    @Test
    func `A scroll on the rail beside the icon is the rail's`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        let beside = fixture.onIcon(dy: 30)
        #expect(fixture.input.route(gesture(.began), keyHeld: false, at: beside, eligible: { true }, overControls: { true }) == false)
        #expect(fixture.input.route(gesture(.changed, 0, -60), keyHeld: false, at: beside, eligible: { true }, overControls: { true }) == false)
        #expect(fixture.window.activeTabID == tabs[1].id)
        #expect(fixture.canvas.floatingVisibility.isHeld == false)
    }

    @Test
    func `A scroll on the icon while the lens is up or the space is locked does nothing`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        #expect(fixture.route(gesture(.began), at: fixture.onIcon(), eligible: false) == false)
        #expect(fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon(), eligible: false) == false)
        #expect(fixture.window.activeTabID == tabs[1].id)
        #expect(fixture.canvas.floatingVisibility.isHeld == false)
    }

    @Test
    func `A wheel notch on the icon steps once per notch and holds`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        #expect(fixture.route(wheel(0, -1), at: fixture.onIcon()))
        #expect(fixture.window.activeTabID == tabs[2].id)
        #expect(fixture.canvas.floatingVisibility.isHeld)
        fixture.settleTravel()
        #expect(fixture.route(wheel(0, 1), at: fixture.onIcon()))
        #expect(fixture.window.activeTabID == tabs[1].id)
        fixture.settleTravel()
        fixture.input.pointerMoved(to: fixture.onPage, keyHeld: false)
        #expect(fixture.canvas.floatingVisibility.isHeld == false)
        #expect(fixture.route(wheel(0, -1), at: fixture.onPage) == false)
        #expect(fixture.window.activeTabID == tabs[1].id)
    }

    @Test
    func `The rail hiding at its edge ends the hold at the next pointer move`() throws {
        let fixture = try TabIconScrollFixture()
        _ = fixture.threeTabs()
        fixture.route(gesture(.began), at: fixture.onIcon())
        fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon())
        #expect(fixture.canvas.floatingVisibility.isHeld)
        fixture.icon.frame = nil
        fixture.input.pointerMoved(to: fixture.onIcon(), keyHeld: false)
        #expect(fixture.input.holdsOnTabIcon == false)
        #expect(fixture.canvas.floatingVisibility.isHeld == false)
    }

    @Test
    func `A click or a key ends the hold`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        fixture.route(gesture(.began), at: fixture.onIcon())
        fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon())
        fixture.settleTravel()
        fixture.input.interrupt()
        #expect(fixture.input.holdsOnTabIcon == false)
        // What is left of the gesture is swallowed and steps no further.
        #expect(fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon()))
        #expect(fixture.window.activeTabID == tabs[2].id)
    }

    @Test
    func `The reveal key down keeps the islands when the pointer leaves the icon`() throws {
        let fixture = try TabIconScrollFixture()
        _ = fixture.threeTabs()
        fixture.route(gesture(.began), at: fixture.onIcon())
        fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon())
        fixture.input.pointerMoved(to: fixture.onPage, keyHeld: true)
        #expect(fixture.input.holdsOnTabIcon == false)
        #expect(fixture.canvas.floatingVisibility.isHeld)
    }

    @Test
    func `The islands let go from elsewhere end the hold`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        fixture.route(gesture(.began), at: fixture.onIcon())
        fixture.route(gesture(.changed, 0, -60), at: fixture.onIcon())
        fixture.route(gesture(.ended), at: fixture.onIcon())
        fixture.route(momentum(.began, 0, -10), at: fixture.onIcon())
        fixture.route(momentum(.ended), at: fixture.onIcon())
        fixture.settleTravel()
        fixture.canvas.releaseFloatingTabs()
        fixture.input.pointerMoved(to: fixture.onPage, keyHeld: false)
        #expect(fixture.input.holdsOnTabIcon == false)
        #expect(fixture.route(gesture(.began), at: fixture.onPage) == false)
        #expect(fixture.window.activeTabID == tabs[2].id)
    }

    @Test
    func `The reveal key and a scroll over the page still step, with no hold on the icon`() throws {
        let fixture = try TabIconScrollFixture()
        let tabs = fixture.threeTabs()
        #expect(fixture.route(gesture(.began), at: fixture.onPage, keyHeld: true))
        #expect(fixture.route(gesture(.changed, 0, -60), at: fixture.onPage, keyHeld: true))
        #expect(fixture.window.activeTabID == tabs[2].id)
        #expect(fixture.input.holdsOnTabIcon == false)
    }
}
