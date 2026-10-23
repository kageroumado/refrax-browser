import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct FloatingTourTests {
    @MainActor
    private struct Stage {
        let env: TabManagerTestEnvironment
        let space: Space
        let window: WindowState
        let canvas: TabCanvasManager
        let table: IslandController
        let defaults: UserDefaults
        let tour: FloatingTourManager

        init() throws {
            self.env = try TabManagerTestEnvironment()
            self.space = env.makeSpace()
            self.window = env.makeActiveWindowState(with: space)
            self.canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
            self.table = IslandController(windowState: window, tabManager: env.tabManager, groupManager: env.groupManager, canvas: canvas, pagePool: env.pagePool)
            window.islandController = table
            table.start()
            self.defaults = try #require(UserDefaults(suiteName: "FloatingTourTests.\(UUID())"))
            self.tour = FloatingTourManager(windowState: window, canvas: canvas, tabManager: env.tabManager, defaults: defaults)
        }

        func openPage(_ fragment: String) throws -> Tab {
            let tab = try env.createActiveTab(url: #require(URL(string: "about:blank#\(fragment)")), in: space, for: window)
            table.refresh()
            return tab
        }

        /// The window's lens, with the tour's provider in place.
        func makeLens() -> CommandLensManager {
            CommandLensManager(
                tabManager: env.tabManager, historyManager: env.historyManager, windowState: window, browserSettings: env.settings,
                siteSettingsManager: env.siteSettingsManager, downloadManager: env.downloadManager,
                extensionManager: env.extensionManager, customSearchEngineManager: env.customSearchEngineManager,
                localNetworkSource: EmptyLocalNetworkSource(), floatingTour: tour,
            )
        }

        /// A rail at the window's left edge with the lens, tab, and page rows reported.
        static let rail = CGRect(x: 12, y: 200, width: 48, height: 400)
        static let rows: [ControlIslandItem: CGRect] = [
            .page: CGRect(x: 16, y: 304, width: 40, height: 32),
            .commandLens: CGRect(x: 16, y: 336, width: 40, height: 32),
            .floatingTabs: CGRect(x: 16, y: 368, width: 40, height: 32),
        ]

        func reportRail() {
            window.controlIsland.railFrame = Self.rail
            for (item, frame) in Self.rows {
                window.controlIsland.reportFrame(frame, for: item)
            }
        }

        /// Steps the page the way the wheel would, and lands the move the page view would animate.
        func step(_ direction: TableDirection) {
            table.step(direction)
            if let travel = table.travel {
                table.finishTravel(travel.id)
            }
        }

        /// The direction from the current page to `tab`, its neighbor on the island.
        func neighbor(_ tab: Tab) -> TableDirection {
            table.refresh()
            return table.destination(toward: .up)?.id == tab.id ? .up : .down
        }

        /// Starts the tour and performs each step's action until `step` is current.
        func advance(to step: FloatingTourManager.Step) throws {
            tour.start()
            guard step.rawValue > FloatingTourManager.Step.openPage.rawValue else { return }
            let first = try openPage("first")
            tour.review()
            guard step.rawValue > FloatingTourManager.Step.openSecondPage.rawValue else { return }
            let second = try openPage("second")
            tour.review()
            guard step.rawValue > FloatingTourManager.Step.revealPages.rawValue else { return }
            canvas.revealFloatingTabs()
            tour.review()
            guard step.rawValue > FloatingTourManager.Step.visitNeighbor.rawValue else { return }
            tour.skipStep()
            guard step.rawValue > FloatingTourManager.Step.floatPage.rawValue else { return }
            table.detach(second.id, at: CGPoint(x: 400, y: 300))
            tour.review()
            guard step.rawValue > FloatingTourManager.Step.pinIsland.rawValue else { return }
            if let island = table.island(holding: first.id) {
                table.togglePin(island.id)
            }
            tour.review()
            guard step.rawValue > FloatingTourManager.Step.pageCard.rawValue else { return }
            canvas.releaseFloatingTabs()
            canvas.dismissFloatingTabs()
            window.controlIsland.showsAddress = false
            tour.review()
            window.controlIsland.showsAddress = true
            tour.review()
        }
    }

    private static let padding = FloatingTourLayout.spotlightPadding

    @Test
    func `the lens offers the step's tutorial page first only while a step asks for a page`() async throws {
        let stage = try Stage()
        let lens = stage.makeLens()
        let provider = TourSuggestionProvider(tour: stage.tour)
        let typed = SuggestionContext(input: "anything", settings: stage.env.settings, currentTabID: nil, selectedSearchEngine: nil)
        #expect(!provider.shouldProvide(for: typed))
        await lens.showStandingSuggestions()
        #expect(lens.suggestions.isEmpty)
        #expect(!lens.isPopupVisible)

        stage.tour.start()
        await lens.showStandingSuggestions()
        #expect(lens.suggestions.map(\.type) == [.tutorialPage(.tripDraft)])
        #expect(lens.suggestions.first?.text == "Trip draft · tutorial page")
        #expect(lens.suggestions.first?.url == FloatingTabsTutorial.Page.tripDraft.url)
        #expect(lens.isPopupVisible)
        #expect(lens.selection.index == 0)

        // Typed text still lists the page; the lens's search row stays ahead of it.
        #expect(provider.shouldProvide(for: typed))
        #expect(await provider.suggestions(for: typed).map(\.type) == [.tutorialPage(.tripDraft)])

        _ = try stage.openPage("first")
        stage.tour.review()
        #expect(stage.tour.currentStep == .openSecondPage)
        #expect(stage.tour.requestedPage == .arrivalDetails)
        #expect(await provider.suggestions(for: typed).first?.text == "Arrival details · tutorial page")

        _ = try stage.openPage("second")
        stage.tour.review()
        #expect(stage.tour.currentStep == .revealPages)
        #expect(stage.tour.requestedPage == nil)
        #expect(!provider.shouldProvide(for: typed))
        lens.reset()
        await lens.showStandingSuggestions()
        #expect(lens.suggestions.isEmpty)
        #expect(!lens.isPopupVisible)
        stage.tour.endTour()
    }

    @Test(arguments: FloatingTourTarget.allCases)
    func `a spotlight is concentric with its target`(kind: FloatingTourTarget) {
        let target = CGRect(x: 100, y: 200, width: 40, height: 32)
        let spot = FloatingTourLayout.spotlight(around: target, of: kind)
        #expect(spot.cornerRadius == kind.cornerRadius + Self.padding)
        #expect(spot.rect == target.insetBy(dx: -Self.padding, dy: -Self.padding))
        let expected: CGFloat = switch kind {
        case .railRow: 16
        case .rail: 16
        case .pageCard: 22
        case .floatingCard: 12
        case .island: 16
        case .lens: 26
        }
        #expect(kind.cornerRadius == expected)
    }

    @Test
    func `each step lights its target with that target's corners`() throws {
        let stage = try Stage()
        let tour = stage.tour
        let bounds = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        stage.reportRail()
        let row = { (item: ControlIslandItem) in FloatingTourLayout.spotlight(around: Stage.rows[item]!, of: .railRow) }

        tour.start()
        let inlineLens = CGRect(x: 480, y: 150, width: 640, height: 52)
        tour.startPageLensFrame = inlineLens
        #expect(tour.spotlights(in: bounds) == [FloatingTourLayout.spotlight(around: inlineLens, of: .lens)])
        #expect(tour.spotlights(in: bounds).map(\.cornerRadius) == [34])
        #expect(tour.highlightedItem == nil)
        #expect(!tour.highlightsRail)

        let first = try stage.openPage("first")
        tour.review()
        #expect(tour.currentStep == .openSecondPage)
        #expect(tour.spotlights(in: bounds) == [row(.commandLens)])
        #expect(tour.spotlights(in: bounds).map(\.cornerRadius) == [24])
        #expect(tour.highlightedItem == .commandLens)
        #expect(tour.passThroughRegions(in: bounds) == [row(.commandLens).rect])

        let second = try stage.openPage("second")
        tour.review()
        #expect(tour.currentStep == .revealPages)
        #expect(tour.spotlights(in: bounds) == [row(.floatingTabs)])
        #expect(tour.highlightedItem == .floatingTabs)

        stage.canvas.revealFloatingTabs()
        tour.review()
        #expect(tour.currentStep == .visitNeighbor)
        tour.skipStep()
        // Held, the islands take no drag: the float step lights the tabs button. Latched, it
        // lights the islands.
        #expect(tour.spotlights(in: bounds) == [row(.floatingTabs)])
        #expect(tour.highlightedItem == .floatingTabs)
        stage.canvas.releaseFloatingTabs()
        stage.canvas.toggleFloatingTabs()
        let lit = tour.spotlights(in: bounds)
        #expect(lit.count == stage.table.visibleIslands.count)
        #expect(!lit.isEmpty)
        #expect(lit.allSatisfy { $0.cornerRadius == WindowCorner.radius + FloatingTourLayout.spotlightPadding })
        #expect(tour.highlightedItem == nil)
        tour.endTour()
    }

    @Test
    func `the page card step lights the icon and the card together and anchors the card`() throws {
        let stage = try Stage()
        let tour = stage.tour
        let bounds = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        stage.reportRail()
        try stage.advance(to: .pageCard)
        #expect(tour.currentStep == .pageCard)
        let icon = try FloatingTourLayout.spotlight(around: #require(Stage.rows[.page]), of: .railRow)
        #expect(tour.spotlights(in: bounds) == [icon])
        #expect(tour.highlightedItem == .page)
        #expect(tour.beamRequests.isEmpty)
        let revisionBefore = tour.beamRevision

        let card = CGRect(x: 68, y: 200, width: 416, height: 44)
        stage.window.controlIsland.pageCardFrame = card
        tour.review()
        let lit = tour.spotlights(in: bounds)
        #expect(lit == [icon, FloatingTourLayout.spotlight(around: card, of: .pageCard)])
        #expect(lit.map(\.cornerRadius) == [24, 30])
        #expect(tour.instructionAnchor(in: bounds) == FloatingTourLayout.spotlight(around: card))
        let beam = try #require(tour.beamRequests.first)
        #expect(beam.kind == .pageIconToCard)
        #expect(beam.from == Stage.rows[.page]!)
        #expect(beam.to == card)
        #expect(beam.revision == revisionBefore + 1)
        tour.endTour()
    }

    @Test
    func `a lens opening during the tour moves the spotlight to the lens and asks for a beam`() throws {
        let stage = try Stage()
        let tour = stage.tour
        let bounds = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        stage.reportRail()
        try stage.advance(to: .openSecondPage)
        let row = try FloatingTourLayout.spotlight(around: #require(Stage.rows[.commandLens]), of: .railRow)
        #expect(tour.spotlights(in: bounds) == [row])
        #expect(tour.beamRequests.isEmpty)

        let lensFrame = CGRect(x: 480, y: 180, width: 640, height: 300)
        stage.window.openCommandLens()
        #expect(stage.window.showsCommandLens)
        stage.window.commandLensFrame = lensFrame
        tour.review()
        let lens = FloatingTourLayout.spotlight(around: lensFrame, of: .lens)
        #expect(tour.spotlights(in: bounds) == [lens])
        #expect(lens.cornerRadius == 34)
        #expect(tour.instructionAnchor(in: bounds) == lens.rect)
        #expect(tour.passThroughRegions(in: bounds).isEmpty)
        #expect(tour.highlightedItem == .commandLens)
        #expect(tour.dimsPage)
        let beam = try #require(tour.beamRequests.first)
        #expect(beam.kind == .lensButtonToLens)
        #expect(beam.from == Stage.rows[.commandLens]!)
        #expect(beam.to == lensFrame)
        #expect(beam.revision == 1)

        stage.window.closeCommandLens()
        tour.review()
        #expect(tour.spotlights(in: bounds) == [row])
        #expect(tour.beamRequests.isEmpty)
        #expect(tour.passThroughRegions(in: bounds) == [row.rect])

        // Opening the lens again lights the beam again once the overlay reports its frame.
        stage.window.openCommandLens()
        stage.window.commandLensFrame = lensFrame
        tour.review()
        #expect(tour.beamRequests.first?.revision == 2)
        #expect(tour.currentStep == .openSecondPage)
        tour.endTour()
    }

    @Test
    func `steps advance only on their own condition and never skip`() throws {
        let stage = try Stage()
        let tour = stage.tour
        tour.start()
        #expect(tour.currentStep == .openPage)

        // Later steps' conditions count for nothing while an earlier step is current.
        stage.window.controlIsland.placement.x = 0.5
        stage.window.controlIsland.showsAddress = true
        tour.review()
        #expect(tour.currentStep == .openPage)

        let first = try stage.openPage("first")
        tour.review()
        #expect(tour.currentStep == .openSecondPage)

        // Returning to the same page is still one page, however often it is reviewed.
        stage.env.tabManager.setActiveTab(first, in: stage.window)
        tour.review()
        #expect(tour.currentStep == .openSecondPage)

        let second = try stage.openPage("second")
        tour.review()
        #expect(tour.currentStep == .revealPages)

        // The tabs button completes the reveal step as the held key does.
        stage.canvas.toggleFloatingTabs()
        tour.review()
        #expect(tour.currentStep == .visitNeighbor)
        stage.canvas.revealFloatingTabs()

        let toward = stage.neighbor(first)
        #expect(stage.table.destination(toward: toward)?.id == first.id)
        stage.step(toward)
        tour.review()
        #expect(tour.currentStep == .visitNeighbor)
        stage.step(toward.opposite)
        tour.review()
        #expect(tour.currentStep == .floatPage)

        // Pinning belongs to a later step; it does not count as floating a page.
        let loose = try #require(stage.table.island(holding: first.id))
        stage.table.togglePin(loose.id)
        tour.review()
        #expect(tour.currentStep == .floatPage)
        stage.table.detach(second.id, at: CGPoint(x: 400, y: 300))
        tour.review()
        #expect(tour.currentStep == .pinIsland)

        // A pin from before the step began does not complete it; a new pin does.
        tour.review()
        #expect(tour.currentStep == .pinIsland)
        stage.table.makeIsland(from: first.id)
        let made = try #require(stage.table.island(holding: first.id))
        #expect(made.id != loose.id)
        stage.table.togglePin(made.id)
        tour.review()
        #expect(tour.currentStep == .pageCard)

        // The reveal from step three holds the card open; the step needs the person's own hover.
        tour.review()
        #expect(tour.currentStep == .pageCard)
        stage.canvas.releaseFloatingTabs()
        stage.canvas.dismissFloatingTabs()
        stage.window.controlIsland.showsAddress = false
        tour.review()
        #expect(tour.currentStep == .pageCard)
        stage.window.controlIsland.showsAddress = true
        tour.review()
        #expect(tour.currentStep == .movePanel)

        tour.review()
        #expect(tour.currentStep == .movePanel)
        stage.window.controlIsland.placement.y = 0.9
        tour.review()
        #expect(tour.currentStep == .done)
        #expect(tour.isActive)

        tour.finish()
        #expect(!tour.isActive)
        // The island pinned for the Keep an Island step lets go.
        #expect(stage.table.island(made.id)?.placement.isPinned == false)
        #expect(stage.defaults.bool(forKey: FloatingTourManager.hintsDismissedKey))
        #expect(stage.defaults.string(forKey: FloatingTourManager.outcomeKey) == FloatingTourManager.Outcome.completed.rawValue)
    }

    @Test
    func `tutorial pages make an adjacent wheel path that returns to the starting page`() async throws {
        let stage = try Stage()
        let tour = stage.tour
        tour.start()
        let draft = try stage.env.createActiveTab(url: FloatingTabsTutorial.Page.tripDraft.url, in: stage.space, for: stage.window)
        tour.review()
        let arrival = try stage.env.createActiveTab(url: FloatingTabsTutorial.Page.arrivalDetails.url, in: stage.space, for: stage.window)
        tour.review()
        #expect(tour.currentStep == .revealPages)
        let toward = stage.neighbor(draft)
        #expect(stage.table.destination(toward: toward)?.id == draft.id)

        stage.canvas.revealFloatingTabs()
        tour.review()
        #expect(tour.currentStep == .visitNeighbor)
        try await Task.sleep(for: .milliseconds(30))
        stage.step(toward)
        try await Task.sleep(for: .milliseconds(30))
        #expect(stage.window.activeTabID == draft.id)
        #expect(tour.currentStep == .visitNeighbor)
        stage.step(toward.opposite)
        for _ in 0 ..< 25 where tour.currentStep != .floatPage {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(stage.window.activeTabID == arrival.id)
        #expect(tour.currentStep == .floatPage)
        tour.endTour()
    }

    @Test
    func `progress counts completed steps over the total`() throws {
        let stage = try Stage()
        let tour = stage.tour
        #expect(tour.progress == 0)
        tour.start()
        #expect(tour.progress == 0)
        _ = try stage.openPage("first")
        tour.review()
        #expect(tour.progress == 1 / Double(FloatingTourManager.totalSteps))
        _ = try stage.openPage("second")
        tour.review()
        #expect(tour.progress == 2 / Double(FloatingTourManager.totalSteps))
        #expect(FloatingTourManager.totalSteps == FloatingTourManager.Step.allCases.count - 1)
        #expect(FloatingTourManager.Step.done.completedSteps == FloatingTourManager.totalSteps)
        tour.endTour()
    }

    @Test
    func `placement guidance opens the card layer after adjacent navigation`() throws {
        let stage = try Stage()
        try stage.advance(to: .floatPage)
        stage.reportRail()
        #expect(stage.canvas.isMomentaryNavigation)
        let tabsButton = try #require(Stage.rows[.floatingTabs])
        #expect(stage.tour.spotlights(in: CGRect(x: 0, y: 0, width: 1_200, height: 800)) == [
            FloatingTourLayout.spotlight(around: tabsButton, of: .railRow),
        ])
        let navigating = FloatingTourManager.Step.Context(revealKey: .control, hasPage: true, lensIsOpen: false, islandsVisible: false)
        #expect(FloatingTourManager.Step.floatPage.instruction(in: navigating).contains("Click the tabs button"))

        stage.canvas.releaseFloatingTabs()
        stage.canvas.toggleFloatingTabs()
        #expect(!stage.canvas.isMomentaryNavigation)
        let arranging = FloatingTourManager.Step.Context(revealKey: .control, hasPage: true, lensIsOpen: false, islandsVisible: true)
        #expect(FloatingTourManager.Step.floatPage.instruction(in: arranging).contains("Drag a row"))
        stage.tour.endTour()
    }

    @Test
    func `End Tour ends the tour and records the dismissal`() throws {
        let stage = try Stage()
        let tour = stage.tour
        tour.start()
        _ = try stage.openPage("first")
        tour.review()
        tour.endTour()
        #expect(!tour.isActive)
        #expect(tour.currentStep == nil)
        #expect(tour.progress == 0)
        #expect(stage.defaults.string(forKey: FloatingTourManager.outcomeKey) == FloatingTourManager.Outcome.skipped.rawValue)
        #expect(!stage.defaults.bool(forKey: FloatingTourManager.hintsDismissedKey))

        // A declined tour is never offered again on its own; asking for it still works.
        FloatingTourManager.hasOfferedThisLaunch = false
        tour.offer()
        #expect(!tour.isActive)
        tour.start()
        #expect(tour.currentStep == .openPage)
        tour.endTour()
    }

    @Test
    func `an untouched launch offers the tour once`() throws {
        let stage = try Stage()
        FloatingTourManager.hasOfferedThisLaunch = false
        stage.tour.offer()
        #expect(stage.tour.isActive)
        stage.tour.endTour()
        stage.defaults.removeObject(forKey: FloatingTourManager.outcomeKey)
        stage.tour.offer()
        #expect(!stage.tour.isActive)
    }

    @Test
    func `tutorial pages appear only when a step needs pages and none exist`() throws {
        let stage = try Stage()
        let tour = stage.tour
        tour.start()
        tour.review()
        #expect(stage.window.activeSpaceTabs.isEmpty)

        let first = try stage.openPage("first")
        tour.review()
        let second = try stage.openPage("second")
        tour.review()
        #expect(tour.currentStep == .revealPages)
        #expect(stage.window.activeSpaceTabs.count == 2)

        stage.env.tabManager.closeTab(first)
        stage.env.tabManager.closeTab(second)
        #expect(stage.window.activeSpaceTabs.isEmpty)
        tour.review()
        #expect(tour.currentStep == .revealPages)
        let pages = stage.window.activeSpaceTabs
        #expect(pages.count == 2)
        #expect(Set(pages.map(\.displayTitle)) == ["Trip draft", "Arrival details"])
        #expect(stage.window.activeTab?.displayTitle == "Trip draft")
        #expect(pages.allSatisfy { stage.window.floatingPlacements[$0.id] != nil })
        tour.endTour()
    }

    @Test(arguments: [
        CGRect(x: 12, y: 200, width: 48, height: 320),
        CGRect(x: 400, y: 150, width: 640, height: 52),
        CGRect(x: 1_500, y: 900, width: 250, height: 34),
        CGRect(x: -40, y: -40, width: 10, height: 10),
    ])
    func `the instruction card stays inside the window beside its target`(target: CGRect) {
        let bounds = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        let size = CGSize(width: FloatingTourLayout.cardWidth, height: 160)
        let origin = FloatingTourLayout.cardOrigin(for: target, cardSize: size, in: bounds)
        let card = CGRect(origin: origin, size: size)
        #expect(bounds.contains(card))
        #expect(card.minY >= FloatingTourLayout.topInset)
        #expect(!card.intersects(FloatingTourLayout.spotlight(around: target)))
        let centered = FloatingTourLayout.cardOrigin(for: nil, cardSize: size, in: bounds)
        #expect(abs(centered.x + size.width / 2 - bounds.midX) < 1)
    }

    @Test
    func `the card keeps clear of the rail when its target is a rail row`() {
        let bounds = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        let rail = CGRect(x: 12, y: 200, width: 48, height: 400)
        let row = CGRect(x: 16, y: 360, width: 40, height: 32)
        let size = CGSize(width: 360, height: 90)
        let origin = FloatingTourLayout.cardOrigin(for: row, cardSize: size, in: bounds, avoiding: rail)
        let card = CGRect(origin: origin, size: size)
        #expect(!card.intersects(rail))
        #expect(bounds.contains(card))
        #expect(origin.x >= rail.maxX)
    }
}
