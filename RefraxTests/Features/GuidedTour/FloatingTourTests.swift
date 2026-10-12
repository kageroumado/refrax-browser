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
        let defaults: UserDefaults
        let tour: FloatingTourManager

        init() throws {
            env = try TabManagerTestEnvironment()
            space = env.makeSpace()
            window = env.makeActiveWindowState(with: space)
            canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
            defaults = try #require(UserDefaults(suiteName: "FloatingTourTests.\(UUID())"))
            tour = FloatingTourManager(windowState: window, canvas: canvas, tabManager: env.tabManager, defaults: defaults)
        }

        func openPage(_ fragment: String) throws -> Tab {
            try env.createActiveTab(url: #require(URL(string: "about:blank#\(fragment)")), in: space, for: window)
        }
    }

    @Test func `steps advance only on their own condition and never skip`() throws {
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

        // The button latches the layer; only the held key completes the step.
        stage.canvas.toggleFloatingTabs()
        tour.review()
        #expect(tour.currentStep == .revealPages)
        stage.canvas.revealFloatingTabs()
        tour.review()
        #expect(tour.currentStep == .placePage)

        // Pinning belongs to a later step; it does not count as placing.
        var pinned = stage.canvas.floatingPlacement(for: first)
        pinned.isPinned = true
        stage.canvas.updateFloatingPlacement(pinned, for: first)
        tour.review()
        #expect(tour.currentStep == .placePage)
        var moved = stage.canvas.floatingPlacement(for: first)
        moved.x = 0.7
        stage.canvas.updateFloatingPlacement(moved, for: first)
        tour.review()
        #expect(tour.currentStep == .keepVisible)

        // A pin from before the step began does not complete it; a new pin does.
        tour.review()
        #expect(tour.currentStep == .keepVisible)
        var kept = stage.canvas.floatingPlacement(for: second)
        kept.isPinned = true
        stage.canvas.updateFloatingPlacement(kept, for: second)
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
        #expect(stage.defaults.bool(forKey: FloatingTourManager.hintsDismissedKey))
        #expect(stage.defaults.string(forKey: FloatingTourManager.outcomeKey) == FloatingTourManager.Outcome.completed.rawValue)
    }

    @Test func `progress counts completed steps over the total`() throws {
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
        tour.skip()
    }

    @Test func `skip ends the tour and records the dismissal`() throws {
        let stage = try Stage()
        let tour = stage.tour
        tour.start()
        _ = try stage.openPage("first")
        tour.review()
        tour.skip()
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
        tour.skip()
    }

    @Test func `an untouched launch offers the tour once`() throws {
        let stage = try Stage()
        FloatingTourManager.hasOfferedThisLaunch = false
        stage.tour.offer()
        #expect(stage.tour.isActive)
        stage.tour.skip()
        stage.defaults.removeObject(forKey: FloatingTourManager.outcomeKey)
        stage.tour.offer()
        #expect(!stage.tour.isActive)
    }

    @Test func `tutorial pages appear only when a step needs pages and none exist`() throws {
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
        tour.skip()
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
}
