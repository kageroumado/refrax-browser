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
        let addressIndex = try #require(items.firstIndex(where: { $0.item == .address }))
        items[addressIndex].isVisible = false
        configuration.apply(items, optionDragTarget: .window)

        let restored = ControlIslandConfiguration(defaults: defaults)
        #expect(restored.items == items)
        #expect(restored.visibleItems.first == .history)
        #expect(!restored.visibleItems.contains(.address))
        #expect(restored.optionDragTarget == .window)
        #expect(restored.optionDragTarget.backgroundTarget == .panel)
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
        defaults.set("futureTarget", forKey: ControlIslandConfiguration.dragTargetKey)
        let configuration = ControlIslandConfiguration(defaults: defaults)
        #expect(configuration.items.count == ControlIslandItem.allCases.count)
        #expect(configuration.items.first?.item == .history)
        #expect(configuration.items.first?.isVisible == false)
        #expect(Set(configuration.items.map(\.item)).count == configuration.items.count)
        #expect(configuration.optionDragTarget == .panel)
    }

    @Test @MainActor
    func `shortcut users can hide every optional item across windows`() {
        let configuration = ControlIslandConfiguration(defaults: nil)
        let first = ControlIslandState(defaults: nil, configuration: configuration)
        let second = ControlIslandState(defaults: nil, configuration: configuration)
        configuration.apply(configuration.items.map { .init(item: $0.item, isVisible: false) })
        #expect(first.configuration.visibleItems.isEmpty)
        #expect(second.configuration.visibleItems.isEmpty)
        first.mode = .button
        first.showsCustomization = true
        first.dismissIfOutside(CGPoint(x: 800, y: 800))
        #expect(first.isRevealed)
        #expect(!second.showsCustomization)
        first.showsCustomization = false
        #expect(!first.isRevealed)
        configuration.apply(ControlIslandConfiguration.defaultItems)
        #expect(second.configuration.visibleItems.contains(.address))
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
    func `circular disclosure stays in the window and leaves its trigger uncovered`(x: Double, y: Double) {
        let placement = ControlIslandPlacement(x: x, y: y)
        for bounds in [area, CGRect(x: 20, y: 40, width: 650, height: 400)] {
            let button = placement.railFrame(in: bounds, height: ControlIslandPlacement.railWidth)
            let panel = placement.buttonPanelFrame(in: bounds, height: 560)
            #expect(bounds.contains(button))
            #expect(bounds.contains(panel))
            #expect(!panel.intersects(button))
            #expect(button.width == button.height)
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
        state.mode = .button
        state.isLatched = true
        state.isPresenting = true
        let restored = ControlIslandState(defaults: defaults)
        #expect(restored.mode == .button)
        #expect(!restored.isLatched)
        #expect(!restored.isPresenting)
    }

    @Test @MainActor
    func `popover and click disclosure survive pointer exit`() {
        let state = ControlIslandState(defaults: nil)
        state.mode = .button
        state.isPresenting = true
        #expect(state.isRevealed)
        state.isPresenting = false
        #expect(!state.isRevealed)
        state.isLatched = true
        #expect(state.isRevealed)
        state.isLatched = false
        #expect(!state.isRevealed)
    }

    @Test @MainActor
    func `dismissal clears temporary disclosure and preserves the compact rail`() {
        let state = ControlIslandState(defaults: nil)
        state.mode = .button
        state.isLatched = true
        state.isHovered = true
        state.showsAddress = true
        state.focus()
        state.dismiss()
        #expect(!state.isRevealed)
        #expect(state.dismissalRequest == 1)
        state.mode = .rail
        #expect(state.isRevealed)
    }

    @Test @MainActor
    func `single button supports keyboard access and dismisses on page interaction`() {
        let state = ControlIslandState(defaults: nil)
        state.mode = .button
        state.hitRegions = [CGRect(x: 12, y: 12, width: 48, height: 400)]
        state.focus()
        #expect(state.isRevealed)
        state.dismissIfOutside(CGPoint(x: 20, y: 50))
        #expect(state.isRevealed)
        state.dismissIfOutside(CGPoint(x: 500, y: 500))
        #expect(!state.isRevealed)
        #expect(!state.hasKeyboardFocus)
        #expect(state.dismissalRequest == 1)
        #expect(state.pageFocusRequest == 0)
    }

    @Test @MainActor
    func `controls remain available above either lens`() throws {
        let environment = try TabManagerTestEnvironment()
        let state = environment.makeWindowState()
        state.usesFloatingTabs = true
        let canvas = TabCanvasManager(tabManager: environment.tabManager, windowState: state,
                                      pagePool: environment.pagePool, groupManager: environment.groupManager)
        state.openCommandLens()
        #expect(canvas.showsFloatingControls)
        state.openAddressLens()
        #expect(canvas.showsFloatingControls)
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
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: point, modifierFlags: [],
                                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                       eventNumber: 0, trackingNumber: 0, userData: nil))
        group.mouseEntered(with: event)
        let theme = try #require(window.contentView?.superview)
        let refresh = NSSelectorFromString("_updateMouseTracking")
        #expect(theme.responds(to: refresh))
        theme.perform(refresh)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        try expectWidgetHover(group, state: 4)

        let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: CGPoint(x: 500, y: 500), modifierFlags: [],
                                                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                      eventNumber: 0, trackingNumber: 0, userData: nil))
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
        NSApp.sendEvent(try mouseEvent(.mouseMoved, at: CGPoint(x: 400, y: 400), window: window))
        try expectWidgetHover(group, state: 0)
    }

    @Test @MainActor
    func `Option over a stationary pointer shows the target and restores the cursor on release`() throws {
        let previousCursor = NSCursor.current
        let window = ControlIslandTestWindow(contentRect: area, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let drag = ControlIslandOptionDragView(frame: CGRect(x: 100, y: 100, width: 48, height: 500))
        window.contentView?.addSubview(drag)
        window.pointerLocation = CGPoint(x: 124, y: 300)
        var feedback: [ControlIslandDragFeedback] = []
        drag.onFeedback = { feedback.append($0) }
        for target in ControlIslandDragTarget.allCases {
            drag.target = target
            let option = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .option,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 58))
            #expect(drag.handle(option) === option)
            #expect(drag.feedback == .ready(target))
            #expect(NSCursor.current == .openHand)
            let release = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 58))
            _ = drag.handle(release)
            #expect(drag.feedback == .idle)
            #expect(NSCursor.current == previousCursor)
        }
        #expect(feedback == [.ready(.panel), .idle, .ready(.window), .idle])
    }

    @Test @MainActor
    func `hand cursor stays inside the visible rounded panel and clears when detached`() throws {
        let previousCursor = NSCursor.current
        let window = ControlIslandTestWindow(contentRect: area, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let drag = ControlIslandOptionDragView(frame: CGRect(x: 100, y: 100, width: 48, height: 500))
        drag.cornerRadius = 24
        window.contentView?.addSubview(drag)
        drag.updateTrackingAreas()
        for tracking in drag.trackingAreas { #expect(drag.bounds.contains(tracking.rect)) }
        let inside = CGPoint(x: 124, y: 300)
        _ = drag.handle(try mouseEvent(.mouseMoved, at: inside, window: window, modifiers: .option))
        #expect(drag.feedback == .ready(.panel))
        for outside in [CGPoint(x: 101, y: 101), CGPoint(x: 500, y: 500)] {
            _ = drag.handle(try mouseEvent(.mouseMoved, at: outside, window: window, modifiers: .option))
            #expect(drag.feedback == .idle)
            #expect(NSCursor.current == previousCursor)
        }
        _ = drag.handle(try mouseEvent(.mouseMoved, at: inside, window: window, modifiers: .option))
        drag.isHidden = true
        _ = drag.handle(try mouseEvent(.mouseMoved, at: inside, window: window, modifiers: .option))
        #expect(drag.feedback == .idle)
        drag.isHidden = false
        _ = drag.handle(try mouseEvent(.mouseMoved, at: inside, window: window, modifiers: .option))
        drag.removeFromSuperview()
        #expect(drag.feedback == .idle)
        #expect(NSCursor.current == previousCursor)
    }

    @Test @MainActor
    func `drag cursor captures its target through modifier changes and Escape releases it`() async throws {
        let previousCursor = NSCursor.current
        let window = ControlIslandTestWindow(contentRect: area, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let drag = ControlIslandOptionDragView(frame: CGRect(x: 100, y: 100, width: 48, height: 500))
        window.contentView?.addSubview(drag)
        let point = CGPoint(x: 124, y: 300)
        _ = drag.handle(try mouseEvent(.leftMouseDown, at: point, window: window, modifiers: .option))
        #expect(drag.feedback == .dragging(.panel))
        #expect(NSCursor.current == .closedHand)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let release = try #require(NSEvent.keyEvent(with: .flagsChanged, location: point, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 58))
        _ = drag.handle(release)
        NSCursor.arrow.set()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(NSCursor.current == .closedHand)
        drag.target = .window
        _ = drag.handle(try mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 500), window: window))
        #expect(drag.feedback == .dragging(.panel))
        #expect(NSCursor.current == .closedHand)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: point, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        #expect(drag.handle(escape) == nil)
        #expect(drag.feedback == .idle)
        #expect(NSCursor.current == previousCursor)
    }

    @Test @MainActor
    func `option drag consumes button presses and keeps its target after releasing Option`() throws {
        let window = NSWindow(contentRect: area, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let drag = ControlIslandOptionDragView(frame: CGRect(x: 200, y: 200, width: 48, height: 500))
        window.contentView?.addSubview(drag)
        var began = 0
        var ended = 0
        var translations: [CGSize] = []
        drag.onBegin = { began += 1 }
        drag.onMove = { translations.append($0) }
        drag.onEnd = { ended += 1 }
        let start = CGPoint(x: 224, y: 600)
        #expect(drag.handle(try mouseEvent(.leftMouseDown, at: start, window: window)) != nil)
        #expect(drag.handle(try mouseEvent(.leftMouseDown, at: CGPoint(x: 500, y: 500), window: window, modifiers: .option)) != nil)
        #expect(began == 0)
        #expect(drag.handle(try mouseEvent(.leftMouseDown, at: start, window: window, modifiers: .option)) == nil)
        #expect(began == 1)
        drag.target = .window
        #expect(drag.handle(try mouseEvent(.leftMouseDragged, at: CGPoint(x: 225, y: 600), window: window)) == nil)
        #expect(translations.isEmpty)
        #expect(drag.handle(try mouseEvent(.leftMouseDragged, at: CGPoint(x: 254, y: 580), window: window)) == nil)
        #expect(translations == [CGSize(width: 30, height: 20)])
        #expect(drag.handle(try mouseEvent(.leftMouseUp, at: CGPoint(x: 254, y: 580), window: window)) == nil)
        #expect(ended == 1)
        #expect(drag.handle(try mouseEvent(.leftMouseUp, at: start, window: window)) != nil)
    }

    @Test @MainActor
    func `option click stays inert and detaching ends a drag`() throws {
        let window = NSWindow(contentRect: area, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let drag = ControlIslandOptionDragView(frame: CGRect(x: 0, y: 0, width: 48, height: 500))
        window.contentView?.addSubview(drag)
        var moves = 0
        var ends = 0
        drag.onMove = { _ in moves += 1 }
        drag.onEnd = { ends += 1 }
        let point = CGPoint(x: 24, y: 250)
        NSApp.sendEvent(try mouseEvent(.leftMouseDown, at: point, window: window, modifiers: .option))
        NSApp.sendEvent(try mouseEvent(.leftMouseUp, at: point, window: window))
        #expect(moves == 0)
        #expect(ends == 1)
        _ = drag.handle(try mouseEvent(.leftMouseDown, at: point, window: window, modifiers: .option))
        drag.removeFromSuperview()
        #expect(ends == 2)
    }

    @Test @MainActor
    func `favorite reordering reserves the gesture from Option movement`() throws {
        let window = ControlIslandTestWindow(contentRect: area, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let drag = ControlIslandOptionDragView(frame: CGRect(x: 0, y: 0, width: 48, height: 500))
        window.contentView?.addSubview(drag)
        let event = try mouseEvent(.leftMouseDown, at: CGPoint(x: 24, y: 250), window: window, modifiers: .option)
        var began = 0
        drag.onBegin = { began += 1 }
        drag.isEnabled = false
        #expect(drag.handle(event) === event)
        #expect(drag.feedback == .idle)
        #expect(began == 0)
        drag.isEnabled = true
        #expect(drag.handle(event) == nil)
        #expect(began == 1)
        drag.finish()
    }

    @MainActor
    private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow,
                            modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 0))
    }

    @Test @MainActor
    func `window option drag uses native movement and immovable windows consume the gesture`() throws {
        let window = ControlIslandTestWindow(contentRect: area, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let drag = ControlIslandOptionDragView(frame: CGRect(x: 0, y: 0, width: 48, height: 500))
        window.contentView?.addSubview(drag)
        drag.target = .window
        var panelMoves = 0
        drag.onMove = { _ in panelMoves += 1 }
        let point = CGPoint(x: 24, y: 200)
        let press = try mouseEvent(.leftMouseDown, at: point, window: window, modifiers: .option)
        #expect(drag.handle(press) == nil)
        #expect(window.dragCount == 1)
        #expect(window.cursorDuringDrag == .closedHand)
        window.isMovable = false
        #expect(drag.handle(press) == nil)
        #expect(drag.feedback == .unavailable)
        #expect(NSCursor.current == .operationNotAllowed)
        #expect(drag.handle(try mouseEvent(.leftMouseDragged, at: CGPoint(x: 200, y: 200), window: window)) == nil)
        #expect(drag.handle(try mouseEvent(.leftMouseUp, at: point, window: window)) == nil)
        #expect(window.dragCount == 1)
        #expect(panelMoves == 0)
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
        if let group = view as? ControlIslandWindowButtonGroup { return group }
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
    var dragCount = 0
    var cursorDuringDrag: NSCursor?
    var pointerLocation: CGPoint?
    override var mouseLocationOutsideOfEventStream: NSPoint {
        pointerLocation ?? super.mouseLocationOutsideOfEventStream
    }
    override func performDrag(with _: NSEvent) {
        dragCount += 1
        cursorDuringDrag = NSCursor.current
    }
}
