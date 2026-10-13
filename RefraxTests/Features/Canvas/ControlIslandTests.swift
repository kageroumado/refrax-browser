import AppKit
import SwiftUI
import Testing
@testable import Refrax

@Suite(.serialized)
struct ControlIslandTests {
    private let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)

    @Test @MainActor
    func `custom order and hidden controls survive relaunch`() throws {
        let suite = "ControlIslandTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = ControlIslandConfiguration(defaults: defaults)
        var items = configuration.items
        let historyIndex = try #require(items.firstIndex(where: { $0.item == .history }))
        var history = items.remove(at: historyIndex)
        history.isVisible = true
        items.insert(history, at: 0)
        let addressIndex = try #require(items.firstIndex(where: { $0.item == .page }))
        items[addressIndex].isVisible = false
        configuration.apply(items)

        let restored = ControlIslandConfiguration(defaults: defaults)
        #expect(restored.items == items)
        #expect(restored.visibleItems.first == .history)
        #expect(!restored.visibleItems.contains(.page))
    }

    @Test @MainActor
    func `saved arrangements tolerate unknown and duplicate controls`() throws {
        let suite = "ControlIslandTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = Data("""
        [{"id":"futureControl","isVisible":true},{"id":"history","isVisible":false},{"id":"history","isVisible":true}]
        """.utf8)
        defaults.set(records, forKey: ControlIslandConfiguration.storageKey)
        let configuration = ControlIslandConfiguration(defaults: defaults)
        #expect(configuration.items.count == ControlIslandItem.allCases.count)
        #expect(configuration.items.first?.item == .history)
        #expect(configuration.items.first?.isVisible == false)
        #expect(Set(configuration.items.map(\.item)).count == configuration.items.count)
    }

    @Test @MainActor
    func `shortcut users can hide every optional item across windows`() {
        let configuration = ControlIslandConfiguration(defaults: nil)
        let first = ControlIslandState(defaults: nil, configuration: configuration)
        let second = ControlIslandState(defaults: nil, configuration: configuration)
        configuration.apply(configuration.items.map { .init(item: $0.item, isVisible: false) })
        #expect(first.configuration.visibleItems.isEmpty)
        #expect(second.configuration.visibleItems.isEmpty)
        first.showsCustomization = true
        first.dismissIfOutside(CGPoint(x: 800, y: 800))
        #expect(first.isEngaged)
        #expect(!second.showsCustomization)
        first.showsCustomization = false
        #expect(!first.isEngaged)
        configuration.apply(ControlIslandConfiguration.defaultItems)
        #expect(second.configuration.visibleItems.contains(.page))
    }

    @Test(arguments: [CGPoint(x: -800, y: -700), CGPoint(x: 8_000, y: 5_000), CGPoint(x: 600, y: 300)])
    func `moving and resizing keep controls reachable without changing saved anchors`(origin: CGPoint) {
        var placement = ControlIslandPlacement()
        placement.move(to: origin, in: area, height: 500)
        let saved = placement
        let small = CGRect(x: 0, y: 0, width: 650, height: 400)
        let rail = placement.railFrame(in: small, height: 500)
        #expect(small.contains(rail))
        #expect(small.contains(placement.pageBranchFrame(in: small, anchor: rail, height: 40)))
        #expect(placement == saved)
    }

    @Test
    func `invalid stored coordinates produce finite visible controls`() {
        let placement = ControlIslandPlacement(x: .nan, y: .infinity)
        #expect(area.contains(placement.railFrame(in: area, height: 420)))
    }

    @Test(arguments: [0.0, 0.3, 0.7, 1.0], [0.0, 0.5, 1.0])
    func `a tall rail stays in the window at every anchor`(x: Double, y: Double) {
        let placement = ControlIslandPlacement(x: x, y: y)
        for bounds in [area, CGRect(x: 20, y: 40, width: 650, height: 400)] {
            let rail = placement.railFrame(in: bounds, height: 560)
            #expect(bounds.insetBy(dx: ControlIslandPlacement.margin, dy: ControlIslandPlacement.margin).contains(rail))
            #expect(rail.width == ControlIslandPlacement.railWidth)
        }
    }

    @Test
    func `page controls share the panel leading edge`() {
        let placement = ControlIslandPlacement()
        let panel = placement.railFrame(in: area, height: 500)
        let address = placement.pageBranchFrame(in: area, anchor: panel, height: 40)
        #expect(address.minY == panel.minY)
    }

    @Test @MainActor
    func `control preferences survive a new window while temporary disclosure stays local`() throws {
        let suite = "ControlIslandTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = ControlIslandState(defaults: defaults)
        state.placement = ControlIslandPlacement(x: 1, y: 0.5)
        state.savePlacement()
        state.isPresenting = true
        state.focus()
        let restored = ControlIslandState(defaults: defaults)
        #expect(restored.placement == ControlIslandPlacement(x: 1, y: 0.5))
        #expect(!restored.isPresenting)
        #expect(!restored.hasKeyboardFocus)
    }

    @Test @MainActor
    func `popover and keyboard use keep the rail engaged after the pointer leaves`() {
        let state = ControlIslandState(defaults: nil)
        state.isPresenting = true
        #expect(state.isEngaged)
        state.isPresenting = false
        #expect(!state.isEngaged)
        state.focus()
        #expect(state.isEngaged)
        state.dismiss()
        #expect(!state.isEngaged)
    }

    @Test @MainActor
    func `dismissal clears temporary disclosure`() {
        let state = ControlIslandState(defaults: nil)
        state.isHovered = true
        state.showsAddress = true
        state.focus()
        state.dismiss()
        #expect(!state.isEngaged)
        #expect(state.dismissalRequest == 1)
        #expect(state.pageFocusRequest == 1)
    }

    @Test @MainActor
    func `keyboard access ends on page interaction outside the controls`() {
        let state = ControlIslandState(defaults: nil)
        state.hitRegions = [CGRect(x: 12, y: 12, width: 48, height: 400)]
        state.focus()
        #expect(state.isEngaged)
        state.dismissIfOutside(CGPoint(x: 20, y: 50))
        #expect(state.isEngaged)
        state.dismissIfOutside(CGPoint(x: 500, y: 500))
        #expect(!state.isEngaged)
        #expect(!state.hasKeyboardFocus)
        #expect(state.dismissalRequest == 1)
        #expect(state.pageFocusRequest == 0)
    }

    @Test @MainActor
    func `controls remain available above either lens`() throws {
        let environment = try TabManagerTestEnvironment()
        let state = environment.makeWindowState()
        state.usesFloatingTabs = true
        let canvas = TabCanvasManager(
            tabManager: environment.tabManager,
            windowState: state,
            pagePool: environment.pagePool,
            groupManager: environment.groupManager,
        )
        state.openCommandLens()
        #expect(canvas.showsFloatingControls)
        state.editAddress()
        #expect(canvas.showsFloatingControls)
    }

    @Test
    func `the default rail starts without a recent-tabs row and keeps the update badge`() {
        let visible = ControlIslandConfiguration.defaultItems.filter(\.isVisible).map(\.item)
        #expect(visible == [.windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces, .favoriteTabs, .updates])
        #expect(!visible.contains(.recentTabs))
        #expect(ControlIslandItem.allCases.allSatisfy { ($0.section == .main) == $0.isDefault || $0 == .updates })
    }

    @Test
    func `the grip takes the gap under the space picker and favorites follow it`() {
        let layout = ControlIslandRailLayout(visibleItems: [.windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces, .favoriteTabs])
        #expect(layout.elements == [
            .row(.windowControls), .line(before: .navigation),
            .row(.navigation), .row(.page), .row(.commandLens), .row(.floatingTabs), .row(.desk),
            .line(before: .spaces), .row(.spaces), .grip, .row(.favoriteTabs),
        ])
    }

    @Test
    func `additional controls gather at the bottom in their customized order`() {
        let layout = ControlIslandRailLayout(visibleItems: [.history, .navigation, .reload, .spaces, .favoriteTabs, .settings, .page])
        #expect(layout.elements == [
            .row(.navigation), .line(before: .spaces), .row(.spaces), .grip, .row(.favoriteTabs),
            .line(before: .history), .row(.history), .row(.reload), .row(.settings), .row(.page),
        ])
        #expect(layout.rows == [.navigation, .spaces, .favoriteTabs, .history, .reload, .settings, .page])
    }

    @Test
    func `without a space picker the grip ends the main section and never doubles a gap`() {
        #expect(ControlIslandRailLayout(visibleItems: [.navigation, .commandLens, .history]).elements
            == [.row(.navigation), .row(.commandLens), .grip, .row(.history)])
        #expect(ControlIslandRailLayout(visibleItems: [.navigation, .favoriteTabs, .history]).elements
            == [.row(.navigation), .line(before: .favoriteTabs), .row(.favoriteTabs), .grip, .row(.history)])
        #expect(ControlIslandRailLayout(visibleItems: [.history, .settings]).elements == [.grip, .row(.history), .row(.settings)])
        #expect(ControlIslandRailLayout(visibleItems: [.navigation]).elements == [.row(.navigation), .grip])
        #expect(ControlIslandRailLayout(visibleItems: []).elements == [.grip])
    }

    @Test @MainActor
    func `the rail's height counts every row and every gap, and is the same at rest and awake`() {
        let items: [ControlIslandItem] = [.windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces]
        let height = ControlIslandPlacement.railHeight(items: items, spaceCount: 2, favoriteCount: 0)
        let rows = ControlIslandPlacement.rowHeight * 8
        let gaps = ControlIslandPlacement.sectionGap * 3
        let spaces = ControlIslandPlacement.spaceRowHeight * 2
        #expect(height == ControlIslandPlacement.contentInset * 2 + rows + gaps + spaces)
        #expect(ControlIslandPlacement.gripSize == CGSize(width: 3, height: 18))
        #expect(ControlIslandPlacement.gripHitHeight > ControlIslandPlacement.sectionGap)
    }

    @Test @MainActor
    func `the bottom section adds its divider and rows to the rail's height`() {
        let main: [ControlIslandItem] = [.navigation, .spaces, .favoriteTabs]
        let base = ControlIslandPlacement.railHeight(items: main, spaceCount: 1, favoriteCount: 2)
        let withExtras = ControlIslandPlacement.railHeight(items: main + [.history, .settings], spaceCount: 1, favoriteCount: 2)
        #expect(base == ControlIslandPlacement.contentInset * 2 + ControlIslandPlacement.rowHeight
            + ControlIslandPlacement.sectionGap * 2 + ControlIslandPlacement.spaceRowHeight + ControlIslandFavoriteTabs.height(for: 2))
        #expect(withExtras - base == ControlIslandPlacement.sectionGap + ControlIslandPlacement.rowHeight * 2)
        let empty = ControlIslandPlacement.railHeight(items: [], spaceCount: 0, favoriteCount: 0)
        #expect(empty == ControlIslandPlacement.contentInset * 2 + ControlIslandPlacement.sectionGap)
    }

    @Test
    func `Option-click meanings are written into the catalog`() {
        #expect(ControlIslandItem.navigation.detail.contains("⌥-click shows history"))
        #expect(ControlIslandItem.floatingTabs.detail.contains("⌥-click for recent tabs"))
        #expect(ControlIslandItem.desk.detail.contains("⌥-click"))
        #expect(ControlIslandItem.updates.symbol == "arrow.down.circle.fill")
    }

    @Test @MainActor
    func `native window widgets cover the complete rectangular cell and reveal native glyphs`() throws {
        let window = NSWindow(contentRect: area, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let group = ControlIslandWindowButtonGroup()
        group.frame = CGRect(x: 0, y: 0, width: 40, height: 96)
        window.contentView?.addSubview(group)
        group.layoutSubtreeIfNeeded()
        #expect(group.buttons.count == 3)
        for button in group.buttons {
            #expect(button.frame.width == 40)
            #expect(button.frame.height == 32)
            for offset in [CGPoint(x: 1, y: 1), CGPoint(x: 39, y: 31)] {
                let point = CGPoint(x: button.frame.minX + offset.x, y: button.frame.minY + offset.y)
                #expect(group.hitTest(group.convert(point, to: group.superview)) === button)
            }
        }
        let selector = NSSelectorFromString("_bezelInteractionState")
        typealias GetState = @convention(c) (AnyObject, Selector) -> Int
        for hovered in [true, false] {
            group.setRollover(hovered)
            for button in group.buttons {
                let cell = try #require(button.cell)
                let method = try #require(cell.method(for: selector))
                #expect(unsafeBitCast(method, to: GetState.self)(cell, selector) == (hovered ? 4 : 0))
            }
        }
    }

    @Test
    func `releasing control during a drag keeps the tab until the drop`() {
        var visibility = FloatingTabVisibility()
        visibility.hold()
        visibility.beginManipulation()
        visibility.release()
        #expect(visibility.shows(isPinned: false))
        visibility.endManipulation()
        #expect(!visibility.shows(isPinned: false))
        #expect(visibility.shows(isPinned: true))
    }

    @Test @MainActor
    func `traffic light hover survives native tracking refresh and clears on exit`() async throws {
        let window = NSWindow(contentRect: area, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let group = ControlIslandWindowButtonGroup()
        group.frame = CGRect(x: 0, y: 0, width: 40, height: 96)
        window.contentView?.addSubview(group)
        group.layoutSubtreeIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let point = group.convert(CGPoint(x: 20, y: 16), to: nil)
        let event = try #require(NSEvent.enterExitEvent(
            with: .mouseEntered,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil,
        ))
        group.mouseEntered(with: event)
        let theme = try #require(window.contentView?.superview)
        let refresh = NSSelectorFromString("_updateMouseTracking")
        #expect(theme.responds(to: refresh))
        theme.perform(refresh)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        try expectWidgetHover(group, state: 4)

        let exit = try #require(NSEvent.enterExitEvent(
            with: .mouseExited,
            location: CGPoint(x: 500, y: 500),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil,
        ))
        group.mouseExited(with: exit)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        try expectWidgetHover(group, state: 0)
        group.mouseEntered(with: event)
        group.removeFromSuperview()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(group.window == nil)
    }

    @Test @MainActor
    func `direct pointer movement reaches traffic lights without entering other controls`() async throws {
        let window = ControlIslandTestWindow(contentRect: area, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.pointerLocation = CGPoint(x: 400, y: 400)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = FloatingTabsHostingView(rootView: ControlIslandWindowButtons()
            .frame(width: 40, height: 96)
            .frame(width: area.width, height: area.height, alignment: .topLeading))
        host.hitRegions = { [CGRect(x: 0, y: 0, width: 40, height: 96)] }
        host.frame = area
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let group = try #require(widgetGroup(in: host))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        group.updateTrackingAreas()
        for tracking in group.trackingAreas {
            #expect(group.bounds.contains(tracking.rect))
        }
        #expect(window.acceptsMouseMovedEvents)
        for local in [CGPoint(x: 20, y: 1), CGPoint(x: 1, y: 16), CGPoint(x: 39, y: 80)] {
            group.setRollover(false)
            let point = group.convert(local, to: nil)
            window.pointerLocation = point
            let event = try mouseEvent(.mouseMoved, at: point, window: window)
            NSApp.sendEvent(event)
            let theme = try #require(window.contentView?.superview)
            theme.perform(NSSelectorFromString("_updateMouseTracking"))
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            try expectWidgetHover(group, state: 4)
        }
        window.pointerLocation = CGPoint(x: 400, y: 400)
        try NSApp.sendEvent(mouseEvent(.mouseMoved, at: CGPoint(x: 400, y: 400), window: window))
        try expectWidgetHover(group, state: 0)
    }

    @MainActor
    private func mouseEvent(
        _ type: NSEvent.EventType,
        at point: CGPoint,
        window: NSWindow,
        modifiers: NSEvent.ModifierFlags = [],
    ) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0,
        ))
    }

    @MainActor
    private func expectWidgetHover(_ group: ControlIslandWindowButtonGroup, state: Int) throws {
        let selector = NSSelectorFromString("_bezelInteractionState")
        typealias GetState = @convention(c) (AnyObject, Selector) -> Int
        for button in group.buttons {
            let cell = try #require(button.cell)
            let method = try #require(cell.method(for: selector))
            #expect(unsafeBitCast(method, to: GetState.self)(cell, selector) == state)
        }
    }

    @MainActor
    private func widgetGroup(in view: NSView) -> ControlIslandWindowButtonGroup? {
        if let group = view as? ControlIslandWindowButtonGroup {
            return group
        }
        return view.subviews.lazy.compactMap { widgetGroup(in: $0) }.first
    }

    @Test
    func `escape clears a held drag and latch`() {
        var visibility = FloatingTabVisibility()
        visibility.toggle()
        visibility.hold()
        visibility.beginManipulation()
        visibility.dismiss()
        #expect(!visibility.isRevealed)
    }

    @Test @MainActor
    func `a retired preview host cannot resize or detach a promoted page`() throws {
        let environment = try ConcurrencyTestEnvironment()
        let page = try environment.makeWebPage(url: #require(URL(string: "about:blank")))
        let preview = CocoaWebViewAdapter(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let main = CocoaWebViewAdapter(frame: area)
        preview.setActiveMode(webView: page.backingWebView)
        main.setActiveMode(webView: page.backingWebView)
        preview.frame = .zero
        preview.needsLayout = true
        preview.layoutSubtreeIfNeeded()
        #expect(page.backingWebView.superview === main)
        #expect(page.backingWebView.frame.size == area.size)
        preview.prepareForDismantle()
        #expect(page.backingWebView.superview === main)
    }
}

@MainActor
private final class ControlIslandTestWindow: NSWindow {
    var pointerLocation: CGPoint?
    override var mouseLocationOutsideOfEventStream: NSPoint {
        pointerLocation ?? super.mouseLocationOutsideOfEventStream
    }
}
