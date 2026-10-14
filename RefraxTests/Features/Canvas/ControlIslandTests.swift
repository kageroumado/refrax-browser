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

    @Test @MainActor
    func `the default rail keeps Now Playing and the update badge`() {
        let visible = ControlIslandConfiguration.defaultItems.filter(\.isVisible).map(\.item)
        #expect(visible == [.windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces, .favoriteTabs, .nowPlaying, .updates])
        #expect(ControlIslandItem.allCases.allSatisfy { ($0.section == .main) == $0.isDefault || $0.isConditional })
        #expect(ControlIslandItem.allCases.filter(\.isConditional) == [.nowPlaying, .updates])
    }

    @Test @MainActor
    func `Now Playing costs no height while nothing plays and one row with its divider while something does`() {
        let main: [ControlIslandItem] = [.windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces]
        let silent = ControlIslandPlacement.railHeight(items: main, spaceCount: 2, favoriteCount: 0)
        let playing = ControlIslandPlacement.railHeight(items: main + [.nowPlaying], spaceCount: 2, favoriteCount: 0)
        let flatBottom = ControlIslandPlacement.gripBottomInset(aboveRadius: 0)
        let spacesBottom = ControlIslandPlacement.gripBottomInset(aboveRadius: ControlIslandPlacement.spaceRowHeight / 2)
        #expect(abs(playing - silent - (ControlIslandPlacement.sectionGap + ControlIslandPlacement.rowHeight + flatBottom - spacesBottom)) < 0.001)
        #expect(ControlIslandRailLayout(visibleItems: main + [.nowPlaying]).elements.suffix(3)
            == [.line(before: .nowPlaying), .row(.nowPlaying), .grip])
        #expect(ControlIslandRailLayout(visibleItems: [.navigation, .nowPlaying, .updates]).elements
            == [.row(.navigation), .line(before: .nowPlaying), .row(.nowPlaying), .row(.updates), .grip])
    }

    @Test
    func `the space picker and favorites share a plain gap and the grip closes the rail`() {
        let layout = ControlIslandRailLayout(visibleItems: [.windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces, .favoriteTabs])
        #expect(layout.elements == [
            .row(.windowControls), .line(before: .navigation),
            .row(.navigation), .row(.page), .row(.commandLens), .row(.floatingTabs), .row(.desk),
            .line(before: .spaces), .row(.spaces), .gap(before: .favoriteTabs), .row(.favoriteTabs), .grip,
        ])
    }

    @Test
    func `additional controls gather at the bottom in their customized order`() {
        let layout = ControlIslandRailLayout(visibleItems: [.history, .navigation, .reload, .spaces, .favoriteTabs, .settings, .page])
        #expect(layout.elements == [
            .row(.navigation), .line(before: .spaces), .row(.spaces), .gap(before: .favoriteTabs), .row(.favoriteTabs),
            .line(before: .page), .row(.page),
            .line(before: .history), .row(.history), .row(.reload), .row(.settings), .grip,
        ])
        #expect(layout.rows == [.navigation, .spaces, .favoriteTabs, .page, .history, .reload, .settings])
    }

    @Test
    func `the grip closes the rail whatever the rows and a section break is one line`() {
        #expect(ControlIslandRailLayout(visibleItems: [.navigation, .commandLens, .history]).elements
            == [.row(.navigation), .row(.commandLens), .line(before: .history), .row(.history), .grip])
        #expect(ControlIslandRailLayout(visibleItems: [.navigation, .favoriteTabs, .history]).elements
            == [.row(.navigation), .line(before: .favoriteTabs), .row(.favoriteTabs), .line(before: .history), .row(.history), .grip])
        #expect(ControlIslandRailLayout(visibleItems: [.history, .settings]).elements == [.row(.history), .row(.settings), .grip])
        #expect(ControlIslandRailLayout(visibleItems: [.navigation]).elements == [.row(.navigation), .grip])
        #expect(ControlIslandRailLayout(visibleItems: []).elements == [.grip])
    }

    @Test @MainActor
    func `the rail's height counts every row and every gap, and is the same at rest and awake`() {
        let items: [ControlIslandItem] = [.windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces]
        let height = ControlIslandPlacement.railHeight(items: items, spaceCount: 2, favoriteCount: 0)
        let rows = ControlIslandPlacement.rowHeight * 8
        let gaps = ControlIslandPlacement.sectionGap * 2
        let spaces = ControlIslandPlacement.spaceRowHeight * 2
        let grip = ControlIslandPlacement.gripGap + ControlIslandPlacement.gripSize.height
        let bottom = ControlIslandPlacement.gripBottomInset(aboveRadius: ControlIslandPlacement.spaceRowHeight / 2)
        #expect(height == ControlIslandPlacement.contentInset + bottom + rows + gaps + spaces + grip)
        #expect(ControlIslandPlacement.gripSize == CGSize(width: 16, height: 10))
    }

    @Test
    func `the grip's bottom inset grows by the corner sag at its ends`() {
        let half = ControlIslandPlacement.gripSize.width / 2
        let railSag = ControlIslandPlacement.cornerSag(radius: ControlIslandPlacement.cornerRadius, offset: half)
        #expect(abs(railSag - 1.37) < 0.05)
        #expect(ControlIslandPlacement.cornerSag(radius: 20, offset: 0) == 0)
        #expect(ControlIslandPlacement.cornerSag(radius: 20, offset: 20) == 20)
        let underSpaces = ControlIslandPlacement.gripBottomInset(aboveRadius: ControlIslandPlacement.spaceRowHeight / 2)
        let underRow = ControlIslandPlacement.gripBottomInset(aboveRadius: 0)
        #expect(abs(underSpaces - 9.04) < 0.05)
        #expect(abs(underRow - 7.37) < 0.05)
        #expect(underSpaces > underRow)
    }

    @Test @MainActor
    func `the bottom section adds its divider and rows to the rail's height`() {
        let main: [ControlIslandItem] = [.navigation, .spaces, .favoriteTabs]
        let base = ControlIslandPlacement.railHeight(items: main, spaceCount: 1, favoriteCount: 2)
        let withExtras = ControlIslandPlacement.railHeight(items: main + [.history, .settings], spaceCount: 1, favoriteCount: 2)
        let grip = ControlIslandPlacement.gripGap + ControlIslandPlacement.gripSize.height
        let flatBottom = ControlIslandPlacement.gripBottomInset(aboveRadius: 0)
        #expect(base == ControlIslandPlacement.contentInset + flatBottom + ControlIslandPlacement.rowHeight
            + ControlIslandPlacement.sectionGap * 2 + ControlIslandPlacement.spaceRowHeight + ControlIslandFavoriteTabs.height(for: 2) + grip)
        #expect(abs(withExtras - base - (ControlIslandPlacement.sectionGap + ControlIslandPlacement.rowHeight * 2)) < 0.001)
        let empty = ControlIslandPlacement.railHeight(items: [], spaceCount: 0, favoriteCount: 0)
        #expect(empty == ControlIslandPlacement.contentInset + flatBottom + grip)
    }

    @Test
    func `Option-click meanings are written into the catalog`() {
        #expect(ControlIslandItem.navigation.detail.contains("⌥-click shows history"))
        #expect(ControlIslandItem.floatingTabs.detail.contains("Recent tabs"))
        #expect(!ControlIslandItem.desk.detail.contains("debug"))
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
