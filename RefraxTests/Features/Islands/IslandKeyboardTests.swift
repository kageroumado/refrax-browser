import AppKit
import Foundation
import Testing
@testable import Refrax

/// Which keys the islands answer while they have the keyboard.
struct IslandKeyTests {
    @Test(arguments: [
        (UInt16(126), IslandKey.up), (125, .down), (123, .left), (124, .right), (36, .open), (76, .open), (51, .close), (117, .close),
        (49, .preview), (53, .leave),
    ])
    func `The arrows, Return, Delete, Space, and Escape are the islands'`(keyCode: UInt16, key: IslandKey) {
        #expect(IslandKey(keyCode: keyCode, characters: nil, command: false, control: false, option: false) == key)
    }

    @Test
    func `Command-Delete closes, and every other shortcut goes to the page`() {
        #expect(IslandKey(keyCode: 51, characters: "\u{8}", command: true, control: false, option: false) == .close)
        #expect(IslandKey(keyCode: 13, characters: "w", command: true, control: false, option: false) == nil)
        #expect(IslandKey(keyCode: 125, characters: nil, command: false, control: true, option: false) == nil)
        #expect(IslandKey(keyCode: 0, characters: "å", command: false, control: false, option: true) == nil)
    }

    @Test
    func `Letters are typed, and Tab is not`() {
        #expect(IslandKey(keyCode: 0, characters: "A", command: false, control: false, option: false) == .text("A"))
        #expect(IslandKey(keyCode: 48, characters: "\t", command: false, control: false, option: false) == nil)
    }
}

/// Which keys latched islands take from the page.
struct IslandKeyRoutingTests {
    private static let arrows: [IslandKey] = [.up, .down, .left, .right]
    private static let others: [IslandKey] = [.open, .close, .preview, .leave, .text("a")]

    @Test(arguments: arrows)
    func `An arrow starts browsing over the page`(key: IslandKey) {
        #expect(IslandKeyRouting.takes(key, browsing: false, responder: .other, covered: false))
    }

    @Test(arguments: others)
    func `Before browsing starts, Return, Delete, Space, Escape and letters stay the page's`(key: IslandKey) {
        #expect(!IslandKeyRouting.takes(key, browsing: false, responder: .other, covered: false))
    }

    @Test(arguments: arrows + others)
    func `Once browsing, every key is the islands'`(key: IslandKey) {
        #expect(IslandKeyRouting.takes(key, browsing: true, responder: .other, covered: false))
    }

    @Test(arguments: arrows + others)
    func `A text field or the drawer over the islands keeps every key`(key: IslandKey) {
        #expect(!IslandKeyRouting.takes(key, browsing: true, responder: .textInput, covered: false))
        #expect(!IslandKeyRouting.takes(key, browsing: true, responder: .other, covered: true))
        #expect(!IslandKeyRouting.takes(key, browsing: false, responder: .other, covered: true))
    }
}

/// Moving through the islands' rows with the keyboard alone.
struct IslandKeyboardNavigatorTests {
    private let left = IslandKeyboardNavigator.Column(id: UUID(), tabIDs: [UUID(), UUID(), UUID()])
    private let right = IslandKeyboardNavigator.Column(id: UUID(), tabIDs: [UUID(), UUID()])
    private let now = Date(timeIntervalSinceReferenceDate: 0)

    private var columns: [IslandKeyboardNavigator.Column] {
        [left, right]
    }

    private var titles: [UUID: String] {
        [
            left.tabIDs[0]: "Swift Forums", left.tabIDs[1]: "WebKit Blog", left.tabIDs[2]: "Settings",
            right.tabIDs[0]: "Söra Notes", right.tabIDs[1]: "Swift Evolution",
        ]
    }

    private func press(_ key: IslandKey, _ navigator: inout IslandKeyboardNavigator, at time: TimeInterval = 0) -> IslandKeyboardNavigator.Effect {
        let left = left
        let right = right
        let titles = titles
        return navigator.handle(
            key, columns: columns,
            neighbor: { id, direction in
                if id == left.id, direction == .right {
                    return right.id
                }
                if id == right.id, direction == .left {
                    return left.id
                }
                return nil
            },
            title: { titles[$0] ?? "" },
            now: now.addingTimeInterval(time),
        )
    }

    @Test
    func `It starts on the current row, or the first row when the current tab is on none`() {
        #expect(IslandKeyboardNavigator(current: left.tabIDs[1], columns: columns).cursor == left.tabIDs[1])
        #expect(IslandKeyboardNavigator(current: UUID(), columns: columns).cursor == left.tabIDs[0])
        #expect(IslandKeyboardNavigator(current: nil, columns: []).cursor == nil)
    }

    @Test
    func `Up and down stop at the island's first and last rows`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[0], columns: columns)
        #expect(press(.up, &navigator) == .none)
        #expect(navigator.cursor == left.tabIDs[0])
        #expect(press(.down, &navigator) == .moved)
        #expect(press(.down, &navigator) == .moved)
        #expect(navigator.cursor == left.tabIDs[2])
        #expect(press(.down, &navigator) == .none)
        #expect(navigator.cursor == left.tabIDs[2])
    }

    @Test
    func `Left and right cross to the neighboring island at the same height, or its last row`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[2], columns: columns)
        #expect(press(.right, &navigator) == .moved)
        #expect(navigator.cursor == right.tabIDs[1])
        #expect(press(.right, &navigator) == .none)
        #expect(press(.left, &navigator) == .moved)
        #expect(navigator.cursor == left.tabIDs[1])
    }

    @Test
    func `Return opens the chosen row`() {
        var navigator = IslandKeyboardNavigator(current: right.tabIDs[0], columns: columns)
        #expect(press(.open, &navigator) == .open(right.tabIDs[0]))
    }

    @Test
    func `Closing the chosen row moves to the row below, or above at the bottom`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[1], columns: columns)
        #expect(press(.close, &navigator) == .close(left.tabIDs[1]))
        #expect(navigator.cursor == left.tabIDs[2])
        var last = IslandKeyboardNavigator(current: left.tabIDs[2], columns: columns)
        _ = press(.close, &last)
        #expect(last.cursor == left.tabIDs[1])
    }

    @Test
    func `When the chosen row goes away, the row now at its place is chosen`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[2], columns: columns)
        let shrunk = IslandKeyboardNavigator.Column(id: left.id, tabIDs: [left.tabIDs[0]])
        navigator.sync([shrunk, right])
        #expect(navigator.cursor == left.tabIDs[0])
        navigator.sync([right])
        #expect(navigator.cursor == right.tabIDs[0])
        navigator.sync([])
        #expect(navigator.cursor == nil)
    }

    @Test
    func `Space shows the chosen row's page, the preview follows the arrows, and Escape puts it away first`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[0], columns: columns)
        #expect(press(.preview, &navigator) == .preview(left.tabIDs[0]))
        #expect(press(.down, &navigator) == .preview(left.tabIDs[1]))
        #expect(press(.leave, &navigator) == .preview(nil))
        #expect(navigator.cursor == left.tabIDs[1])
        #expect(press(.leave, &navigator) == .leave)
        #expect(navigator.cursor == nil)
    }

    @Test
    func `Typing jumps to the next title starting with the letters, across islands, wrapping`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[0], columns: columns)
        // "s" looks past the chosen row: Settings, then Söra (accents ignored), then Swift Evolution.
        #expect(press(.text("s"), &navigator, at: 0) == .moved)
        #expect(navigator.cursor == left.tabIDs[2])
        #expect(press(.text("s"), &navigator, at: 5) == .moved)
        #expect(navigator.cursor == right.tabIDs[0])
        #expect(press(.text("s"), &navigator, at: 10) == .moved)
        #expect(navigator.cursor == right.tabIDs[1])
        #expect(press(.text("s"), &navigator, at: 15) == .moved)
        #expect(navigator.cursor == left.tabIDs[0])
    }

    @Test
    func `Letters typed in one breath make one word, which may keep the chosen row`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[1], columns: columns)
        _ = press(.text("s"), &navigator, at: 0)
        #expect(navigator.cursor == left.tabIDs[2])
        _ = press(.text("w"), &navigator, at: 0.3)
        #expect(navigator.cursor == right.tabIDs[1])
        _ = press(.text("i"), &navigator, at: 0.6)
        #expect(navigator.cursor == right.tabIDs[1])
    }

    @Test
    func `A word starting no title finds one that contains it, and one in none moves nothing`() {
        var navigator = IslandKeyboardNavigator(current: left.tabIDs[0], columns: columns)
        _ = press(.text("blog"), &navigator)
        #expect(navigator.cursor == left.tabIDs[1])
        #expect(press(.text("zzz"), &navigator, at: 5) == .none)
        #expect(navigator.cursor == left.tabIDs[1])
    }
}

/// The islands taking the keyboard in a window.
@Suite("Island keyboard", .serialized)
@MainActor
struct IslandKeyboardTests {
    private func fixtureWithTwoIslands() throws -> (IslandFixture, own: [Refrax.Tab], grouped: [Refrax.Tab], group: TabGroup) {
        let fixture = try IslandFixture()
        let own = [fixture.tab("Alpha"), fixture.tab("Beta")]
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Reading")
        let grouped = [fixture.tab("Gamma", group: group), fixture.tab("Delta", group: group)]
        let loose = try #require(fixture.islands.island(fixture.space.id))
        fixture.window.setActiveTabID(loose.tabIDs[0], for: fixture.space.id)
        // The group's island to the right of the loose tabs'.
        fixture.islands.moveIsland(group.id, to: CGPoint(x: fixture.islands.frame(of: loose).maxX + 200, y: fixture.islands.frame(of: loose).minY))
        fixture.islands.endIslandMove(keeping: group.id)
        return (fixture, own, grouped, group)
    }

    @Test
    func `Browsing latches the islands with the current row chosen, and the page stays`() throws {
        let (fixture, _, _, _) = try fixtureWithTwoIslands()
        let current = fixture.window.activeTabID
        fixture.islands.beginKeyboardBrowsing()
        #expect(fixture.canvas.floatingVisibility.isLatched)
        #expect(fixture.islands.keyboardCursorID == current)
        fixture.islands.handleKey(.down)
        #expect(fixture.islands.keyboardCursorID != current)
        #expect(fixture.window.activeTabID == current)
    }

    @Test
    func `Right crosses to the island on that side`() throws {
        let (fixture, _, _, group) = try fixtureWithTwoIslands()
        fixture.islands.beginKeyboardBrowsing()
        fixture.islands.handleKey(.right)
        let cursor = try #require(fixture.islands.keyboardCursorID)
        #expect(fixture.islands.island(holding: cursor)?.id == group.id)
    }

    @Test
    func `Return opens the chosen row and lets the islands go`() throws {
        let (fixture, _, _, _) = try fixtureWithTwoIslands()
        fixture.islands.beginKeyboardBrowsing()
        fixture.islands.handleKey(.down)
        let chosen = try #require(fixture.islands.keyboardCursorID)
        fixture.islands.handleKey(.open)
        #expect(fixture.window.activeTabID == chosen)
        #expect(!fixture.canvas.floatingVisibility.isRevealed)
        #expect(fixture.islands.keyboardCursorID == nil)
    }

    @Test
    func `Space previews the chosen row, Escape puts the preview away, then leaves`() throws {
        let (fixture, _, _, _) = try fixtureWithTwoIslands()
        fixture.islands.beginKeyboardBrowsing()
        let chosen = fixture.islands.keyboardCursorID
        fixture.islands.handleKey(.preview)
        #expect(fixture.islands.previewedTabID == chosen)
        fixture.islands.handleKey(.leave)
        #expect(fixture.islands.previewedTabID == nil)
        #expect(fixture.canvas.floatingVisibility.isLatched)
        fixture.islands.handleKey(.leave)
        #expect(!fixture.canvas.floatingVisibility.isRevealed)
    }

    @Test
    func `Before an arrow, Delete over the page closes nothing and goes to the page`() throws {
        let (fixture, _, _, _) = try fixtureWithTwoIslands()
        let count = fixture.space.mainTabs.count
        fixture.canvas.toggleFloatingTabs()
        let parent = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: .titled, backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        let page = FocusablePage()
        parent.contentView = page
        parent.makeFirstResponder(page)
        let gestures = CanvasPageGestures(
            window: parent, canvas: fixture.canvas, floatingEligible: { true }, floatingContains: { _ in false }, floatingHasKeyboardFocus: { false },
        )
        gestures.islands = fixture.islands
        for (keyCode, characters) in [(UInt16(51), "\u{7F}"), (49, " "), (36, "\r"), (0, "a")] {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: parent.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode,
            ))
            #expect(gestures.handle(event) != nil, "key \(keyCode) was taken")
        }
        #expect(fixture.space.mainTabs.count == count)
        #expect(fixture.islands.keyboardCursorID == nil)
        #expect(fixture.islands.previewedTabID == nil)
    }

    @Test
    func `After an arrow starts browsing, letters, Space, and Return reach the islands, not the page`() throws {
        let (fixture, _, grouped, _) = try fixtureWithTwoIslands()
        fixture.canvas.toggleFloatingTabs()
        let parent = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: .titled, backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        let page = FocusablePage()
        parent.contentView = page
        parent.makeFirstResponder(page)
        let gestures = CanvasPageGestures(
            window: parent, canvas: fixture.canvas, floatingEligible: { true }, floatingContains: { _ in false }, floatingHasKeyboardFocus: { false },
        )
        gestures.islands = fixture.islands
        func key(_ keyCode: UInt16, _ characters: String) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: parent.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode,
            ))
        }
        #expect(try gestures.handle(key(125, "\u{F701}")) == nil)
        #expect(fixture.islands.keyboardCursorID != nil)
        #expect(try gestures.handle(key(2, "d")) == nil)
        #expect(try gestures.handle(key(14, "e")) == nil)
        #expect(fixture.islands.keyboardCursorID == grouped[1].id)
        #expect(try gestures.handle(key(49, " ")) == nil)
        #expect(fixture.islands.previewedTabID == grouped[1].id)
        #expect(try gestures.handle(key(36, "\r")) == nil)
        #expect(fixture.window.activeTabID == grouped[1].id)
        #expect(!fixture.canvas.floatingVisibility.isRevealed)
    }

    @Test
    func `With the library drawer over the islands, keys pass through`() throws {
        let (fixture, _, _, _) = try fixtureWithTwoIslands()
        fixture.canvas.toggleFloatingTabs()
        fixture.window.showDetailTray(.archive)
        #expect(!fixture.islands.handleKey(.down))
        #expect(fixture.islands.keyboardCursorID == nil)
    }

    @Test
    func `Letting the latch go ends browsing and puts the preview away`() throws {
        let (fixture, _, _, _) = try fixtureWithTwoIslands()
        fixture.islands.beginKeyboardBrowsing()
        fixture.islands.handleKey(.preview)
        #expect(fixture.islands.previewedTabID != nil)
        fixture.canvas.dismissFloatingTabs()
        #expect(fixture.islands.previewedTabID == nil)
        #expect(fixture.islands.keyboardCursorID == nil)
        // The next latch starts with nothing chosen.
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.keyboardCursorID == nil)
        #expect(!fixture.islands.handleKey(.close))
    }

    @Test
    func `Escape with no row chosen is left to the window`() throws {
        let (fixture, _, _, _) = try fixtureWithTwoIslands()
        fixture.canvas.toggleFloatingTabs()
        #expect(!fixture.islands.handleKey(.leave))
        #expect(fixture.islands.keyboardCursorID == nil)
    }

    @Test
    func `A filter hiding the chosen row moves the choice to a row still shown`() throws {
        let (fixture, own, _, _) = try fixtureWithTwoIslands()
        for tab in own {
            tab.isUnread = false
        }
        let current = try #require(fixture.window.activeTabID)
        fixture.islands.beginKeyboardBrowsing()
        fixture.islands.handleKey(.down)
        let chosen = try #require(fixture.islands.keyboardCursorID)
        #expect(chosen != current)
        fixture.islands.setFilter(.unread)
        let cursor = try #require(fixture.islands.keyboardCursorID)
        #expect(fixture.islands.visibleIslands.contains { $0.tabIDs.contains(cursor) })
        #expect(cursor != chosen)
    }

    @Test
    func `Typing a title chooses its row`() throws {
        let (fixture, _, grouped, _) = try fixtureWithTwoIslands()
        fixture.islands.beginKeyboardBrowsing()
        fixture.islands.handleKey(.text("del"))
        #expect(fixture.islands.keyboardCursorID == grouped[1].id)
    }
}

/// A view that takes keyboard focus the way a page does.
private final class FocusablePage: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}
