import AppKit
import Observation
import SwiftUI

/// A step-by-step tour of the floating-tabs browser that advances on real actions.
///
/// The tour owns its step list: each action step names the control it spotlights and the
/// state change that completes it. The overlay draws what the tour reports and never decides
/// a step on its own. A step completes only when its own condition turns true after the
/// step began, so state that already held when the step started counts for nothing.
@Observable
final class FloatingTourManager {
    /// The tour's steps, in order. Every step before `done` completes on an action.
    enum Step: Int, CaseIterable, Sendable {
        case openPage
        case openSecondPage
        case revealPages
        case placePage
        case keepVisible
        case pageCard
        case movePanel
        case done

        /// The steps that teach something, in order.
        static let actionSteps = Self.allCases.filter { $0 != .done }

        /// How many open pages the step needs before it can show anything.
        var requiredPageCount: Int {
            switch self {
            case .openPage, .openSecondPage, .done: 0
            case .revealPages, .placePage, .keepVisible: 2
            case .pageCard, .movePanel: 1
            }
        }

        /// The tutorial page the step asks the lens to offer first, while the step asks for a page.
        var requestedPage: FloatingTabsTutorial.Page? {
            switch self {
            case .openPage: .tripDraft
            case .openSecondPage: .arrivalDetails
            default: nil
            }
        }

        /// The number of steps completed when this step is current.
        var completedSteps: Int {
            rawValue
        }
    }

    /// How a tour ended. An automatic start never repeats a tour the person already answered.
    enum Outcome: String, Sendable {
        case completed
        case skipped
    }

    /// The current step, or nil while the tour is not running.
    private(set) var currentStep: Step?

    /// The inline lens on the empty page, in window content coordinates, while that page is shown.
    var startPageLensFrame: CGRect = .zero

    /// Counts the times a beam was asked for anew, carried by every ``beamRequests`` entry.
    private(set) var beamRevision = 0

    static let totalSteps = Step.actionSteps.count
    static let outcomeKey = "floatingTour.outcome"
    static let hintsDismissedKey = "startPage.hintsDismissed"
    private static let escapeKeyCode: UInt16 = 53

    /// Whether an automatic start already happened in this process.
    static var hasOfferedThisLaunch = false

    @ObservationIgnored private unowned let windowState: WindowState
    @ObservationIgnored private unowned let canvas: TabCanvasManager
    @ObservationIgnored private unowned let tabManager: TabManager
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var entry = Baseline()
    /// The current step's condition has been false since the step began, so a true reading is the person's doing.
    @ObservationIgnored private var armed = false
    /// The beams on screen at the last review; a kind joining them bumps the revision.
    @ObservationIgnored private var litBeams: Set<TourBeam.Kind> = []
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var keyMonitor: Any?

    /// What the window looked like when the current step began.
    private struct Baseline {
        var activeTabID: Tab.ID?
        var placements: [Tab.ID: FloatingTabPlacement] = [:]
        var islandPlacement = ControlIslandPlacement()
    }

    /// Everything a step's condition depends on, read inside one observation so a change re-evaluates the step.
    private struct Reading: Equatable, Sendable {
        var holds: Bool
        var pageCount: Int
        var beams: [TourBeam.Kind]
    }

    init(windowState: WindowState, canvas: TabCanvasManager, tabManager: TabManager, defaults: UserDefaults? = .standard) {
        self.windowState = windowState
        self.canvas = canvas
        self.tabManager = tabManager
        self.defaults = defaults
    }

    isolated deinit {
        observation?.cancel()
        removeKeyMonitor()
    }

    // MARK: - State

    var isActive: Bool {
        currentStep != nil
    }

    /// Completed steps over the total, from 0 at the first step to 1 on the closing card.
    var progress: Double {
        Double(currentStep?.completedSteps ?? 0) / Double(Self.totalSteps)
    }

    /// The tutorial page the lens offers first, while the current step asks for a page.
    var requestedPage: FloatingTabsTutorial.Page? {
        currentStep?.requestedPage
    }

    /// The page is dimmed while no lens is anchored to the page card; the anchored lens has its
    /// own place there. The centered Command Lens stands in a spotlight of its own under the scrim.
    var dimsPage: Bool {
        !windowState.showsAnchoredLens
    }

    /// A lens over the page takes its own clicks and its own Escape.
    private var lensIsOpen: Bool {
        windowState.showsCommandLens
    }

    /// The Command Lens over the page, in window content coordinates, while it is up.
    private var openLensFrame: CGRect? {
        guard windowState.showsCommandLens, !windowState.commandLensFrame.isEmpty else { return nil }
        return windowState.commandLensFrame
    }

    // MARK: - Lifecycle

    /// Starts the tour from the first step.
    func start() {
        Self.hasOfferedThisLaunch = true
        enter(.openPage)
        observe()
        installKeyMonitor()
    }

    /// Starts the tour the first time the empty page appears in this launch, unless the person
    /// already finished or skipped a tour or dismissed the empty page's hints.
    func offer() {
        guard !Self.hasOfferedThisLaunch, !isActive,
              defaults?.bool(forKey: Self.hintsDismissedKey) != true,
              defaults?.string(forKey: Self.outcomeKey) == nil else { return }
        start()
    }

    /// Ends the tour early and remembers that it was declined.
    func skip() {
        end(.skipped)
    }

    /// Ends the tour from its closing card. The empty page's hints have done their job and go away.
    func finish() {
        defaults?.set(true, forKey: Self.hintsDismissedKey)
        end(.completed)
    }

    private func end(_ outcome: Outcome) {
        guard isActive else { return }
        defaults?.set(outcome.rawValue, forKey: Self.outcomeKey)
        observation?.cancel()
        observation = nil
        removeKeyMonitor()
        armed = false
        litBeams = []
        currentStep = nil
    }

    // MARK: - Steps

    /// Reads the window and advances when the current step's condition has turned true.
    func review() {
        guard let step = currentStep, step != .done else { return }
        ensurePages(for: step)
        adoptNewPlacements()
        reviewBeams()
        if conditionHolds(for: step) {
            if armed {
                advance()
            }
        } else {
            armed = true
        }
    }

    private func advance() {
        guard let step = currentStep, let next = Step(rawValue: step.rawValue + 1) else { return }
        enter(next)
    }

    private func enter(_ step: Step) {
        currentStep = step
        ensurePages(for: step)
        entry = Baseline(
            activeTabID: windowState.activeTabID,
            placements: windowState.floatingPlacements,
            islandPlacement: windowState.controlIsland.placement,
        )
        armed = !conditionHolds(for: step)
        reviewBeams()
    }

    private func conditionHolds(for step: Step) -> Bool {
        switch step {
        case .openPage:
            windowState.activeTabID != nil && windowState.activeTabID != entry.activeTabID
        case .openSecondPage:
            pageCount >= 2 && windowState.activeTabID != entry.activeTabID
        case .revealPages:
            canvas.floatingVisibility.isHeld
        case .placePage:
            windowState.floatingPlacements.contains { id, placement in
                guard let before = entry.placements[id] else { return false }
                return before.x != placement.x || before.y != placement.y
            }
        case .keepVisible:
            windowState.floatingPlacements.contains { id, placement in
                placement.isPinned && entry.placements[id]?.isPinned != true
            }
        case .pageCard:
            windowState.controlIsland.tabInfo.isVisible || windowState.controlIsland.showsAddress
        case .movePanel:
            windowState.controlIsland.placement != entry.islandPlacement
        case .done:
            false
        }
    }

    /// A page placed after the step began is measured from where it first appeared.
    private func adoptNewPlacements() {
        for (id, placement) in windowState.floatingPlacements where entry.placements[id] == nil {
            entry.placements[id] = placement
        }
    }

    private var pageCount: Int {
        _ = tabManager.state.tabListVersion
        return windowState.activeSpaceTabs.filter { !$0.isArchived }.count
    }

    /// Opens the two tutorial pages when a step needs pages to show and the space has too few.
    private func ensurePages(for step: Step) {
        let required = step.requiredPageCount
        guard required > 0, pageCount < required, let space = windowState.activeSpace, !windowState.isSpaceLocked else { return }
        let draft = tabManager.createTab(url: FloatingTabsTutorial.Page.tripDraft.url, in: space, makeActive: false)
        let reference = tabManager.createTab(url: FloatingTabsTutorial.Page.arrivalDetails.url, in: space, makeActive: false)
        draft.activePage.title = FloatingTabsTutorial.Page.tripDraft.title
        reference.activePage.title = FloatingTabsTutorial.Page.arrivalDetails.title
        canvas.updateFloatingPlacement(.init(x: 0.1, y: 0.4, isCompact: true, isPinned: false), for: draft)
        canvas.updateFloatingPlacement(.init(x: 0.8, y: 0.4, isCompact: false, isPinned: false), for: reference)
        if windowState.activeTab == nil {
            tabManager.setActiveTab(draft, in: windowState)
        }
    }

    // MARK: - Targets

    /// The rail row the current step points at, when the step has one.
    private var railItem: ControlIslandItem? {
        switch currentStep {
        case .openPage: windowState.activeTab == nil ? nil : .commandLens
        case .openSecondPage: .commandLens
        case .revealPages: .floatingTabs
        case .placePage, .keepVisible: canvas.visibleFloatingTabs.isEmpty ? .floatingTabs : nil
        case .pageCard: .page
        case .movePanel, .done, nil: nil
        }
    }

    /// The rail row the rail lights above its glass: the step's row, while the rail shows it.
    var highlightedItem: ControlIslandItem? {
        guard let item = railItem, let frame = windowState.controlIsland.itemFrames[item], !frame.isEmpty else { return nil }
        return item
    }

    /// Whether the rail lights its whole glass: the step moves the panel, or points at a row
    /// that customization has hidden.
    var highlightsRail: Bool {
        guard let step = currentStep else { return false }
        return step == .movePanel || (railItem != nil && highlightedItem == nil)
    }

    /// The areas the current step lights, in window content coordinates, each with the corner
    /// radius of what it surrounds.
    ///
    /// Rail rows come from the control island's reported frames; floating pages from the
    /// canvas; the empty page's lens from the page itself. A step whose control is hidden
    /// by customization lights the whole rail. While the Command Lens is up over the page,
    /// the lens is the one lit area, wherever the step points.
    func spotlights(in bounds: CGRect) -> [TourSpotlight] {
        guard let step = currentStep else { return [] }
        if let lens = openLensFrame {
            return [FloatingTourLayout.spotlight(around: lens, of: .lens)]
        }
        let island = windowState.controlIsland
        let rail: [TourSpotlight] = island.railFrame.isEmpty ? [] : [FloatingTourLayout.spotlight(around: island.railFrame, of: .rail)]
        func row(_ item: ControlIslandItem) -> [TourSpotlight] {
            if let frame = island.itemFrames[item], !frame.isEmpty {
                return [FloatingTourLayout.spotlight(around: frame, of: .railRow)]
            }
            return rail
        }
        switch step {
        case .openPage:
            if windowState.activeTab == nil {
                return startPageLensFrame.isEmpty ? [] : [FloatingTourLayout.spotlight(around: startPageLensFrame, of: .lens)]
            }
            return row(.commandLens)
        case .openSecondPage:
            return row(.commandLens)
        case .revealPages:
            return row(.floatingTabs)
        case .placePage, .keepVisible:
            let cards = canvas.visibleFloatingTabs.map { FloatingTourLayout.spotlight(around: canvas.floatingFrame(for: $0, in: bounds), of: .floatingCard) }
            return cards.isEmpty ? row(.floatingTabs) : cards
        case .pageCard:
            return row(.page) + (pageCardSpotlight.map { [$0] } ?? [])
        case .movePanel:
            return rail
        case .done:
            return []
        }
    }

    /// The page card, lit together with the page icon once it has unfolded.
    private var pageCardSpotlight: TourSpotlight? {
        let frame = windowState.controlIsland.pageCardFrame
        return frame.isEmpty ? nil : FloatingTourLayout.spotlight(around: frame, of: .pageCard)
    }

    /// The area the instruction card sits beside: the page card once it has unfolded, else
    /// everything the step lights, together.
    func instructionAnchor(in bounds: CGRect) -> CGRect? {
        if currentStep == .pageCard, openLensFrame == nil, let card = pageCardSpotlight {
            return card.rect
        }
        let union = spotlights(in: bounds).reduce(CGRect.null) { $0.union($1.rect) }
        return union.isNull ? nil : union
    }

    /// Where clicks reach the content under the overlay: the lit targets, while no lens is up.
    /// A lens lives in the overlay itself and takes its own clicks.
    func passThroughRegions(in bounds: CGRect) -> [CGRect] {
        guard isActive, !lensIsOpen else { return [] }
        return spotlights(in: bounds).map(\.rect)
    }

    // MARK: - Beams

    /// Paths of light from a control to what it opened, for the light engine to draw: the
    /// rail's lens button to the open lens, and the page icon to its card.
    var beamRequests: [TourBeam] {
        guard isActive else { return [] }
        let island = windowState.controlIsland
        var beams: [TourBeam] = []
        if let lens = openLensFrame, let button = island.itemFrames[.commandLens], !button.isEmpty {
            beams.append(TourBeam(kind: .lensButtonToLens, from: button, to: lens, revision: beamRevision))
        }
        if currentStep == .pageCard, let row = island.itemFrames[.page], !row.isEmpty, let card = pageCardSpotlight {
            beams.append(TourBeam(kind: .pageIconToCard, from: row, to: card.rect.insetBy(dx: FloatingTourLayout.spotlightPadding, dy: FloatingTourLayout.spotlightPadding), revision: beamRevision))
        }
        return beams
    }

    /// A beam that was not lit at the last review is asked for anew.
    private func reviewBeams() {
        let lit = Set(beamRequests.map(\.kind))
        if !lit.subtracting(litBeams).isEmpty {
            beamRevision += 1
        }
        litBeams = lit
    }

    // MARK: - Observation

    private func observe() {
        observation?.cancel()
        observation = Task(name: "Floating tour steps") { [weak self] in
            let readings = Observations { @MainActor [weak self] in self?.reading() }
            for await _ in readings {
                guard let self, !Task.isCancelled else { return }
                review()
            }
        }
    }

    private func reading() -> Reading {
        guard let step = currentStep else { return Reading(holds: false, pageCount: 0, beams: []) }
        return Reading(holds: conditionHolds(for: step), pageCount: step.requiredPageCount > 0 ? pageCount : 0, beams: beamRequests.map(\.kind))
    }

    // MARK: - Escape

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == Self.escapeKeyCode, event.window === windowState.window,
                  isActive, escapeEndsTour else { return event }
            skip()
            return nil
        }
    }

    /// Escape first serves whatever is open above the page: a lens, the revealed tab layer, a sheet.
    private var escapeEndsTour: Bool {
        !lensIsOpen && !canvas.floatingVisibility.isRevealed
            && windowState.window?.attachedSheet == nil && !windowState.controlIsland.showsCustomization
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}

// MARK: - Step Text

extension FloatingTourManager.Step {
    /// What the window looks like while the step is shown, which chooses the wording.
    struct Context {
        var revealKey: FloatingRevealKey
        var hasPage: Bool
        var lensIsOpen: Bool
        var layerRevealed: Bool
        var optionDragMovesPanel: Bool
    }

    var title: String {
        switch self {
        case .openPage: "Open a page"
        case .openSecondPage: "Open a second page"
        case .revealPages: "See both pages"
        case .placePage: "Put a page somewhere"
        case .keepVisible: "Keep a page in view"
        case .pageCard: "The current page"
        case .movePanel: "Move the panel"
        case .done: "You know the whole browser"
        }
    }

    var symbol: String {
        switch self {
        case .openPage: "sparkle.magnifyingglass"
        case .openSecondPage: "plus.square.on.square"
        case .revealPages: "square.on.square"
        case .placePage: "hand.draw"
        case .keepVisible: "pin"
        case .pageCard: "globe"
        case .movePanel: "slider.horizontal.3"
        case .done: "checkmark.seal"
        }
    }

    func instruction(in context: Context) -> String {
        let hold = "Hold \(context.revealKey.title) (\(context.revealKey.glyph))"
        /// "Press Return" once the lens is up; "Press ⌘T, then Return" while it has to be opened first.
        func open(_ page: FloatingTabsTutorial.Page, lensShown: Bool) -> String {
            lensShown ? "Press Return to open \(page.title)" : "Press ⌘T, then Return to open \(page.title)"
        }
        switch self {
        case .openPage:
            return "\(open(.tripDraft, lensShown: context.lensIsOpen || !context.hasPage)), or type anything to search."
        case .openSecondPage:
            return "\(open(.arrivalDetails, lensShown: context.lensIsOpen))."
        case .revealPages:
            return "\(hold) to see every open page where it was left. Release to hide them."
        case .placePage:
            return context.layerRevealed
                ? "Drag a page's title to where you want it. It stays there."
                : "\(hold), then drag a page's title to where you want it. It stays there."
        case .keepVisible:
            return context.layerRevealed
                ? "Click a page's pin, or choose Keep Visible from its actions menu. It stays after you release."
                : "\(hold), then click a page's pin or choose Keep Visible from its actions menu. It stays after you release."
        case .pageCard:
            return "Hover the page's icon on the panel for its card: title, address, reload, favorite, and actions."
        case .movePanel:
            return context.optionDragMovesPanel
                ? "Hold ⌥ and drag the panel somewhere else. It rests while you work and wakes as you approach."
                : "Drag the panel's empty glass somewhere else. It rests while you work and wakes as you approach."
        case .done:
            return "Pages open from the lens, keep their places behind \(context.revealKey.glyph), and the panel stays out of your way."
        }
    }
}
