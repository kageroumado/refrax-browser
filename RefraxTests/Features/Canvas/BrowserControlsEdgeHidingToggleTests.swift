import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Refrax

/// ⌘S: hides and shows the rail and the File Island together, through Hide at the Edge.
struct BrowserControlsEdgeHidingToggleTests {
    private let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
    private let rail = CGRect(x: 1_540, y: 200, width: 48, height: 500)

    @MainActor
    private func makeStates(hiding: Bool, defaults: UserDefaults? = nil) -> (ControlIslandState, FileIslandState) {
        let configuration = ControlIslandConfiguration(defaults: defaults)
        configuration.setHidesAtEdge(hiding)
        configuration.setFileIslandHidesAtEdge(hiding)
        let state = ControlIslandState(defaults: nil, configuration: configuration)
        state.placement = ControlIslandPlacement(x: 1, y: 0.5)
        return (state, FileIslandState(defaults: nil))
    }

    @Test @MainActor
    func `the toggle sends a shown rail away at once and brings a hidden one back to stay`() {
        let (state, files) = makeStates(hiding: false)
        #expect(!state.isHiddenAtEdge)

        let hides = state.toggleEdgeHiding(with: files)
        #expect(hides)
        #expect(state.configuration.hidesAtEdge)
        #expect(state.isHiddenAtEdge, "away at once, not after the pointer has rested")

        let shows = state.toggleEdgeHiding(with: files)
        #expect(!shows)
        #expect(!state.configuration.hidesAtEdge)
        #expect(!state.isHiddenAtEdge)
        #expect(state.hiddenEdge == nil, "nothing left to hide past: the rail stays")
    }

    @Test @MainActor
    func `the File Island hides and shows with the rail`() {
        let (state, files) = makeStates(hiding: false)
        files.hiddenEdge = nil
        files.wake()

        state.toggleEdgeHiding(with: files)
        #expect(state.configuration.fileIslandHidesAtEdge)
        // The island's view sets its edge from the setting; it is snapped to the left here.
        files.hiddenEdge = .left
        #expect(files.isHiddenAtEdge, "an uncoupled island leaves with the rail, without waiting to rest")

        state.toggleEdgeHiding(with: files)
        #expect(!state.configuration.fileIslandHidesAtEdge)
        files.hiddenEdge = nil
        #expect(!files.isHiddenAtEdge)
    }

    @Test @MainActor
    func `the edge still brings the hidden rail back after the toggle`() {
        let (state, files) = makeStates(hiding: false)
        state.areaBounds = area
        state.revealStrip = ControlIslandPlacement.revealStrip(for: rail, at: .right, in: area)
        state.toggleEdgeHiding(with: files)
        #expect(state.isHiddenAtEdge)

        _ = state.tracksPointer(CGPoint(x: area.maxX - 2, y: rail.midY))
        #expect(!state.isHiddenAtEdge, "the flap works as before")
        #expect(state.edgeReveal == .pointer)
        #expect(state.configuration.hidesAtEdge, "a peek does not turn hiding off")
    }

    @Test @MainActor
    func `a download arriving on the hidden island still wakes it`() {
        let (state, files) = makeStates(hiding: false)
        state.toggleEdgeHiding(with: files)
        files.hiddenEdge = .right
        #expect(files.isHiddenAtEdge)

        files.holdAwake(for: FileIslandState.arrivalHold)
        #expect(!files.isHiddenAtEdge)

        // A coupled island comes back by bringing the rail back, which the toggle leaves working.
        state.revealAtEdge(.request)
        #expect(!state.isHiddenAtEdge)
    }

    @Test @MainActor
    func `a rail the lens needs on screen stays until it is free, then hides`() {
        let (state, files) = makeStates(hiding: false)
        state.setNeededOnScreen(true)
        state.toggleEdgeHiding(with: files)
        #expect(state.configuration.hidesAtEdge)
        #expect(!state.isHiddenAtEdge)
    }

    @Test @MainActor
    func `the choice survives a relaunch`() throws {
        let suite = "BrowserControlsEdgeHidingToggleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (state, files) = makeStates(hiding: false, defaults: defaults)
        state.toggleEdgeHiding(with: files)

        let restored = ControlIslandConfiguration(defaults: defaults)
        #expect(restored.hidesAtEdge)
        #expect(restored.fileIslandHidesAtEdge)
        let relaunched = ControlIslandState(defaults: nil, configuration: restored)
        relaunched.placement = ControlIslandPlacement(x: 1, y: 0.5)
        #expect(relaunched.isHiddenAtEdge, "a relaunched window starts with the rail away")

        relaunched.toggleEdgeHiding(with: FileIslandState(defaults: nil))
        let shown = ControlIslandConfiguration(defaults: defaults)
        #expect(!shown.hidesAtEdge)
        #expect(!shown.fileIslandHidesAtEdge)
    }

    @Test @MainActor
    func `View offers it on ⌘S and Save Page As moves to ⌥⌘S`() throws {
        let env = try TabManagerTestEnvironment()
        let menus = MenuBarManager(windowManager: env.windowManager, undoRedoManager: UndoRedoManager())
        let items = [menus.createAppMenu(), menus.createFileMenu(), menus.createEditMenu(), menus.createViewMenu(),
                     menus.createHistoryMenu(), menus.createBookmarksMenu(), menus.createWindowMenu(), menus.createHelpMenu()]
            .compactMap(\.submenu).flatMap(\.items)
        let commandS = items.filter { $0.keyEquivalent == "s" && $0.keyEquivalentModifierMask == [.command] }
        #expect(commandS.count == 1)
        #expect(commandS.first?.tag == MenuItemTag.browserControlsEdgeHiding.rawValue)
        #expect(commandS.first?.title == "Hide Browser Controls")
        let saveAs = items.first { $0.title == "Save Page As…" }
        #expect(saveAs?.keyEquivalentModifierMask == [.command, .option])
        #expect(!items.contains { $0 !== saveAs && $0.keyEquivalent == "s" && $0.keyEquivalentModifierMask == [.command, .option] })
    }
}
