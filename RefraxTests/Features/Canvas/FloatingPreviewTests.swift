import AppKit
import Testing
@testable import Refrax

@MainActor
struct FloatingPreviewTests {
    @Test
    func `preview resizing preserves desktop coordinates and maps pointer positions`() {
        let content = NSView()
        let desktop = CGSize(width: 1_600, height: 1_000)
        let preview = FloatingPreviewScaleView(content: content, viewportSize: desktop)
        preview.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        preview.layoutSubtreeIfNeeded()
        #expect(content.bounds.size == desktop)
        let center = content.convert(CGPoint(x: 160, y: 100), from: preview)
        #expect(abs(center.x - 800) < 0.01)
        #expect(abs(center.y - 500) < 0.01)

        preview.frame.size = CGSize(width: 800, height: 600)
        preview.needsLayout = true
        preview.layoutSubtreeIfNeeded()
        #expect(content.bounds.size == desktop)
        let enlargedCenter = content.convert(CGPoint(x: 400, y: 300), from: preview)
        #expect(abs(enlargedCenter.x - 800) < 0.01)
        #expect(abs(enlargedCenter.y - 500) < 0.01)
    }

    @Test
    func `preview returns the existing page to its host`() throws {
        let environment = try ConcurrencyTestEnvironment()
        let page = try environment.makeWebPage(url: #require(URL(string: "about:blank")))
        let window = NSObject()
        let windowID = ObjectIdentifier(window)
        page.claimOwnership(id: windowID)
        let session = FloatingPreviewSession()
        #expect(session.acquire(page, windowID: windowID))
        #expect(page.isInFloatingPreview)
        session.release()
        #expect(page.ownerWindowID == windowID)
        #expect(page.isInFloatingPreview == false)
    }

    @Test
    func `opening the full tab takes precedence over preview cleanup`() throws {
        let environment = try ConcurrencyTestEnvironment()
        let page = try environment.makeWebPage(url: #require(URL(string: "about:blank")))
        let window = NSObject()
        let windowID = ObjectIdentifier(window)
        let session = FloatingPreviewSession()
        #expect(session.acquire(page, windowID: windowID))
        page.claimOwnership(id: windowID)
        session.release()
        #expect(page.ownerWindowID == windowID)
        #expect(page.isInFloatingPreview == false)
    }

    @Test
    func `preview respects another windows live page`() throws {
        let environment = try ConcurrencyTestEnvironment()
        let page = try environment.makeWebPage(url: #require(URL(string: "about:blank")))
        let window = NSObject()
        let otherWindow = NSObject()
        page.claimOwnership(id: ObjectIdentifier(otherWindow))
        let session = FloatingPreviewSession()
        #expect(session.acquire(page, windowID: ObjectIdentifier(window)) == false)
        #expect(page.ownerWindowID == ObjectIdentifier(otherWindow))
    }

    @Test
    func `preview restores its host after the container releases ownership`() throws {
        let environment = try ConcurrencyTestEnvironment()
        let page = try environment.makeWebPage(url: #require(URL(string: "about:blank")))
        let window = NSObject()
        let windowID = ObjectIdentifier(window)
        page.claimOwnership(id: windowID)
        let session = FloatingPreviewSession()
        #expect(session.acquire(page, windowID: windowID))
        page.releaseOwnership(id: session.id)
        session.release()
        #expect(page.ownerWindowID == windowID)
    }

    @Test
    func `control held scrolling keeps precision and phases`() throws {
        let raw = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -37, wheel2: 9, wheel3: 0))
        raw.flags = [.maskControl, .maskShift]
        raw.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        raw.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        let event = try #require(NSEvent(cgEvent: raw))
        let forwarded = FloatingPreviewInput.removingRevealModifier(from: event, key: .control)
        #expect(forwarded.modifierFlags.contains(.control) == false)
        #expect(forwarded.modifierFlags.contains(.shift))
        #expect(forwarded.scrollingDeltaY == event.scrollingDeltaY)
        #expect(forwarded.scrollingDeltaX == event.scrollingDeltaX)
        #expect(forwarded.hasPreciseScrollingDeltas == event.hasPreciseScrollingDeltas)
        #expect(forwarded.phase == event.phase)
        #expect(forwarded.momentumPhase == event.momentumPhase)
    }

    @Test(arguments: FloatingRevealKey.allCases)
    func `configured reveal modifier is consumed while other modifiers survive`(key: FloatingRevealKey) throws {
        let raw = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 18, wheel2: 0, wheel3: 0))
        raw.flags = [key.cgFlag, .maskShift]
        let event = try #require(NSEvent(cgEvent: raw))
        let forwarded = FloatingPreviewInput.removingRevealModifier(from: event, key: key)
        #expect(!forwarded.modifierFlags.contains(key.flag))
        #expect(forwarded.modifierFlags.contains(.shift))
        #expect(forwarded.scrollingDeltaY == event.scrollingDeltaY)
    }

    @Test
    func `control held typing supplies text and preserves shift`() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{01}",
            charactersIgnoringModifiers: "A",
            isARepeat: false,
            keyCode: 0,
        ))
        let forwarded = FloatingPreviewInput.removingRevealModifier(from: event, key: .control)
        #expect(forwarded.characters == "A")
        #expect(forwarded.modifierFlags.contains(.control) == false)
        #expect(forwarded.modifierFlags.contains(.shift))
    }

    @Test
    func `forwarded clicks keep their target window and location`() throws {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 85, y: 110),
            modifierFlags: .control,
            timestamp: 12,
            windowNumber: 123,
            context: nil,
            eventNumber: 4,
            clickCount: 2,
            pressure: 1,
        ))
        let forwarded = FloatingPreviewInput.removingRevealModifier(from: event, key: .control)
        #expect(forwarded.windowNumber == event.windowNumber)
        #expect(forwarded.locationInWindow == event.locationInWindow)
        #expect(forwarded.clickCount == 2)
    }

    @Test
    func `preview editing owns escape and browser controls can dismiss`() throws {
        let defaults = UserDefaults.standard
        let savedRevealKey = defaults.string(forKey: "floatingTabs.revealKey")
        defaults.set(FloatingRevealKey.control.rawValue, forKey: "floatingTabs.revealKey")
        defer { defaults.set(savedRevealKey, forKey: "floatingTabs.revealKey") }
        let environment = try TabManagerTestEnvironment()
        let state = environment.makeWindowState()
        let canvas = TabCanvasManager(
            tabManager: environment.tabManager,
            windowState: state,
            pagePool: environment.pagePool,
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var previewHasFocus = true
        let gestures = CanvasPageGestures(
            window: window,
            canvas: canvas,
            floatingEligible: { true },
            floatingContains: { _ in true },
            floatingHasKeyboardFocus: { previewHasFocus },
        )
        canvas.revealFloatingTabs()
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 40, y: 60),
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1,
        ))
        #expect(try #require(gestures.handle(click)).modifierFlags.contains(.control) == false)
        #expect(canvas.floatingVisibility.isHeld)
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0,
        ))
        #expect(try #require(gestures.handle(key)).characters == "a")
        #expect(canvas.floatingVisibility.isHeld)
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53,
        ))
        #expect(try #require(gestures.handle(escape)).characters == "\u{1b}")
        #expect(canvas.floatingVisibility.isHeld)
        previewHasFocus = false
        #expect(gestures.handle(escape) == nil)
        #expect(canvas.floatingVisibility.isRevealed == false)
    }

    @Test
    func `control tab remains a browser shortcut while typing in a preview`() throws {
        let environment = try TabManagerTestEnvironment()
        let state = environment.makeWindowState()
        let canvas = TabCanvasManager(
            tabManager: environment.tabManager,
            windowState: state,
            pagePool: environment.pagePool,
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let gestures = CanvasPageGestures(
            window: window,
            canvas: canvas,
            floatingEligible: { true },
            floatingContains: { _ in true },
            floatingHasKeyboardFocus: { true },
        )
        canvas.revealFloatingTabs()
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48,
        ))
        #expect(try #require(gestures.handle(key)).modifierFlags.contains(.control))
        #expect(!canvas.floatingVisibility.isRevealed)
    }

    @Test
    func `holding the reveal key shows destinations before scrolling`() throws {
        let environment = try TabManagerTestEnvironment()
        let state = environment.makeWindowState()
        let canvas = TabCanvasManager(
            tabManager: environment.tabManager,
            windowState: state,
            pagePool: environment.pagePool,
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let gestures = CanvasPageGestures(
            window: window,
            canvas: canvas,
            floatingEligible: { true },
            floatingContains: { _ in false },
            floatingHasKeyboardFocus: { false },
        )
        func flags(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 59,
            ))
        }

        _ = try gestures.handle(flags(FloatingRevealKey.current.flag))
        #expect(canvas.isMomentaryNavigation)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let click = try #require(NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: 40, y: 60),
                modifierFlags: FloatingRevealKey.current.flag,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1,
            ))
            let forwarded = try #require(gestures.handle(click))
            #expect(!forwarded.modifierFlags.contains(FloatingRevealKey.current.flag))
            #expect(canvas.isMomentaryNavigation)
        }
        _ = try gestures.handle(flags([]))
        #expect(!canvas.floatingVisibility.isHeld)
    }

    @Test
    func `adding and releasing Shift keeps the floating arrangement held`() throws {
        let environment = try TabManagerTestEnvironment()
        let state = environment.makeWindowState()
        let canvas = TabCanvasManager(
            tabManager: environment.tabManager,
            windowState: state,
            pagePool: environment.pagePool,
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let gestures = CanvasPageGestures(
            window: window,
            canvas: canvas,
            floatingEligible: { true },
            floatingContains: { _ in false },
            floatingHasKeyboardFocus: { false },
        )
        canvas.revealFloatingTabs()
        let reveal = FloatingRevealKey.current.flag
        for flags: NSEvent.ModifierFlags in [[reveal, .shift], reveal, [reveal, .capsLock]] {
            let event = try #require(NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 56,
            ))
            _ = gestures.handle(event)
            #expect(canvas.floatingVisibility.isHeld)
        }
        let release = try #require(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 59,
        ))
        _ = gestures.handle(release)
        #expect(canvas.floatingVisibility.isHeld == false)
    }

    @Test
    func `a physical right click keeps its context menu gesture`() throws {
        let raw = try #require(CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: .zero, mouseButton: .right))
        raw.flags = .maskControl
        let forwarded = try FloatingPreviewInput.removingRevealModifier(from: #require(NSEvent(cgEvent: raw)), key: .control)
        #expect(forwarded.type == .rightMouseDown)
        #expect(forwarded.buttonNumber == 1)
        #expect(forwarded.modifierFlags.contains(.control) == false)
    }
}
