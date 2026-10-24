import AppKit
import SwiftUI

/// A tab taken out of its island: a window of its own over the page, with the window's lights
/// and title bar, resizable, moved by its title bar, a child of the browser window so it
/// follows it. Red closes the tab; the toolbar's two buttons return it to its island or open it
/// as the page.
final class TabCardWindow: FloatingPageWindow {
    var onClose: () -> Void = {}
    var onReturn: () -> Void = {}
    var onOpen: () -> Void = {}

    static let minimumSize = NSSize(width: 320, height: 240)
    static let defaultSize = NSSize(width: 480, height: 360)

    override init() {
        super.init()
        minSize = Self.minimumSize
        contentMinSize = Self.minimumSize
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.fullScreenAuxiliary, .transient]
        // No lights: the card closes from the gray button in its toolbar, the Finder preview's
        // way; a child window neither minimizes nor zooms.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
    }

    override func performClose(_: Any?) {
        onClose()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Keeps one card window per tab taken out of an island in one browser window, placed where
/// its placement says, and writes back where it is moved or resized. A card let go over an
/// island goes back in as a row.
@MainActor
final class TabCardPresenter {
    private struct Card {
        let window: TabCardWindow
        let tab: Tab
        var observers: [any NSObjectProtocol] = []
        var persist: Task<Void, Never>?
    }

    private enum Layout {
        /// How long after the last move or resize the placement is kept.
        static let persistDelay: Duration = .milliseconds(400)
        /// How often a held card is checked for its release.
        static let releasePoll: Duration = .milliseconds(50)
        /// A card this close to an anchored lens is away while the lens is up.
        static let lensClearance: CGFloat = 8
    }

    private unowned let parent: NSWindow
    private unowned let windowState: WindowState
    private unowned let islands: IslandController
    private unowned let canvas: TabCanvasManager
    private unowned let tabManager: TabManager
    private let environment: RefraxEnvironment
    private var cards: [UUID: Card] = [:]
    private var observation: Task<Void, Never>?
    /// The card whose address the lens is editing; it is away while the lens is up.
    private var editingTabID: UUID?

    init(parent: NSWindow, windowState: WindowState, islands: IslandController, canvas: TabCanvasManager, tabManager: TabManager, environment: RefraxEnvironment) {
        self.parent = parent
        self.windowState = windowState
        self.islands = islands
        self.canvas = canvas
        self.tabManager = tabManager
        self.environment = environment
    }

    func start() {
        sync()
        let islands = islands
        let windowState = windowState
        let changes = Observations {
            Key(
                detached: Set(islands.detachedTabs.map(\.id)),
                activeTabID: windowState.activeTabID,
                hidden: windowState.showsCenteredLens || windowState.isSpaceLocked,
                anchored: windowState.showsAnchoredLens,
                lensFrame: windowState.commandLensFrame,
            )
        }
        observation = Task(name: "Follow the cards") { [weak self] in
            for await _ in changes {
                self?.sync()
            }
        }
    }

    func stop() {
        observation?.cancel()
        for id in Array(cards.keys) {
            close(id)
        }
    }

    private struct Key: Equatable {
        var detached: Set<UUID>
        var activeTabID: UUID?
        var hidden: Bool
        var anchored: Bool
        var lensFrame: CGRect
    }

    // MARK: - Keeping the windows in step

    private func sync() {
        let wanted = islands.detachedTabs.filter { $0.id != windowState.activeTabID }
        let hidden = windowState.showsCenteredLens || windowState.isSpaceLocked
        if !windowState.showsAnchoredLens {
            editingTabID = nil
        }
        for id in Array(cards.keys) where !wanted.contains(where: { $0.id == id }) {
            close(id)
        }
        for tab in wanted where cards[tab.id] == nil {
            open(tab)
        }
        // An anchored lens lives in the browser window, under every card: the card it edits
        // makes way, and so does any card over it.
        let lens = windowState.showsAnchoredLens && editingTabID != nil ? windowState.commandLensFrame.insetBy(dx: -Layout.lensClearance, dy: -Layout.lensClearance) : .null
        for (id, card) in cards {
            let away = hidden || id == editingTabID || contentFrame(of: card.window).intersects(lens)
            card.window.alphaValue = away ? 0 : 1
            card.window.ignoresMouseEvents = away
        }
    }

    private func open(_ tab: Tab) {
        guard let page = tabManager.pagePool.page(for: tab.activePage) else { return }
        let window = TabCardWindow()
        window.onClose = { [weak self] in self?.tabManager.requestCloseTab(tab) }
        window.onReturn = { [weak self] in self?.islands.returnToIsland(tab.id) }
        window.onOpen = { [weak self] in self?.islands.open(tab) }
        window.title = tab.displayTitle
        let content = TabCardContent(
            tab: tab, page: page,
            onEditAddress: { [weak self] in self?.editAddress(of: tab, in: window) },
            onClose: { [weak self] in self?.tabManager.requestCloseTab(tab) },
            onReturn: { [weak self] in self?.islands.returnToIsland(tab.id) },
            onOpen: { [weak self] in self?.islands.open(tab) },
        )
        .refraxEnvironment(environment)
        let hosting = FirstMouseHostingView(rootView: content)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setFrame(frame(for: tab), display: false)
        var card = Card(window: window, tab: tab)
        let center = NotificationCenter.default
        let id = tab.id
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            card.observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowChanged(id) }
            })
        }
        cards[tab.id] = card
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
    }

    private func close(_ id: UUID) {
        guard let card = cards.removeValue(forKey: id) else { return }
        card.persist?.cancel()
        for observer in card.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        parent.removeChildWindow(card.window)
        card.window.contentView = nil
        card.window.orderOut(nil)
    }

    // MARK: - Geometry

    /// The parent's content area on screen, bottom-up as AppKit has it.
    private var contentOnScreen: CGRect {
        guard let content = parent.contentView else { return parent.frame }
        return parent.convertToScreen(content.frame)
    }

    /// The card's screen frame from its placement, which is top-down in the parent's content.
    private func frame(for tab: Tab) -> CGRect {
        let content = contentOnScreen
        let bounds = CGRect(origin: .zero, size: content.size)
        var placement = canvas.floatingPlacement(for: tab)
        let size = CGSize(
            width: max(TabCardWindow.minimumSize.width, placement.previewWidth ?? TabCardWindow.defaultSize.width),
            height: max(TabCardWindow.minimumSize.height, placement.previewHeight ?? TabCardWindow.defaultSize.height),
        )
        placement.previewWidth = size.width
        placement.previewHeight = size.height
        let local = placement.frame(in: bounds)
        return CGRect(
            x: content.minX + local.minX,
            y: content.maxY - local.minY - size.height,
            width: size.width, height: size.height,
        )
    }

    /// The window moved or grew: its placement follows, and while the pointer still holds it,
    /// the side it would dock to shows its silhouette. Once let go, the card docks, leaves the
    /// window, goes back into an island, or keeps its place.
    private func windowChanged(_ id: UUID) {
        guard var card = cards[id] else { return }
        let content = contentOnScreen
        let screen = card.window.frame
        let bounds = CGRect(origin: .zero, size: content.size)
        let local = CGPoint(x: screen.minX - content.minX, y: content.maxY - screen.maxY)
        var placement = canvas.floatingPlacement(for: card.tab)
        placement.previewWidth = screen.width
        placement.previewHeight = screen.height
        placement.move(to: local, in: bounds)
        canvas.updateFloatingPlacement(placement, for: card.tab, persisting: false)
        if NSEvent.pressedMouseButtons != 0 {
            canvas.updateDockTarget(at: pointerInContent, dragging: [card.tab], in: bounds)
        }
        card.persist?.cancel()
        card.persist = Task(name: "Settle a card") { [weak self] in
            while NSEvent.pressedMouseButtons != 0, !Task.isCancelled {
                try? await Task.sleep(for: Layout.releasePoll)
            }
            try? await Task.sleep(for: Layout.persistDelay)
            guard !Task.isCancelled, let self, let card = cards[id] else { return }
            settle(card)
        }
        cards[id] = card
    }

    private enum Settle {
        /// How far past the browser window's edge a card is let go to leave it.
        static let tearOffReach: CGFloat = 24
    }

    /// What a card let go does: dock to the side its silhouette showed, leave for a window of
    /// its own when it is past the browser window's edge, go back into the island under the
    /// pointer, or keep its place.
    private func settle(_ card: Card) {
        let pointer = pointerInContent
        if let target = canvas.dockTarget, target.tabID == card.tab.id {
            canvas.dockTarget = nil
            canvas.dock(card.tab, to: target.edge)
            return
        }
        canvas.dockTarget = nil
        if droppedOnIsland(card, pointer: pointer) {
            return
        }
        if !parent.frame.insetBy(dx: -Settle.tearOffReach, dy: -Settle.tearOffReach).contains(NSEvent.mouseLocation) {
            tearOff(card)
            return
        }
        if let placement = windowState.floatingPlacements[card.tab.id] {
            canvas.updateFloatingPlacement(placement, for: card.tab)
        }
    }

    /// The card becomes the page of a new browser window where the card was.
    private func tearOff(_ card: Card) {
        let frame = card.window.frame
        guard let window = tabManager.moveTabToNewWindow(card.tab, from: windowState)?.window else { return }
        let size = CGSize(width: max(frame.width, window.minSize.width), height: max(frame.height, window.minSize.height))
        var target = CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        if let visible = (NSScreen.screens.first { $0.frame.contains(frame.origin) } ?? window.screen)?.visibleFrame {
            target.origin.x = min(max(target.minX, visible.minX), visible.maxX - target.width)
            target.origin.y = min(max(target.minY, visible.minY), visible.maxY - target.height)
        }
        window.setFrame(target, display: true)
    }

    /// A card's frame in the parent's content, top-down.
    private func contentFrame(of window: NSWindow) -> CGRect {
        let content = contentOnScreen
        let screen = window.frame
        return CGRect(x: screen.minX - content.minX, y: content.maxY - screen.maxY, width: screen.width, height: screen.height)
    }

    /// The pointer in the parent's content, top-down.
    private var pointerInContent: CGPoint {
        let content = contentOnScreen
        let pointer = NSEvent.mouseLocation
        return CGPoint(x: pointer.x - content.minX, y: content.maxY - pointer.y)
    }

    /// A card let go with the pointer over an island goes into that island.
    private func droppedOnIsland(_ card: Card, pointer: CGPoint) -> Bool {
        guard islands.visibleIslands.contains(where: { islands.frame(of: $0).contains(pointer) }) else { return false }
        return canvas.islandDrop?(card.tab, pointer) ?? false
    }

    /// The address field was clicked: the lens opens in the browser window on the card's own
    /// field, the card away meanwhile, so the lens is where the field was.
    private func editAddress(of tab: Tab, in window: TabCardWindow) {
        let content = contentOnScreen
        let screen = window.frame
        let card = CGRect(x: screen.minX - content.minX, y: content.maxY - screen.maxY, width: screen.width, height: screen.height)
        let field = TabCardContent.addressFieldFrame(inCard: card)
        windowState.recordInteraction(with: tab.activePage.id)
        editingTabID = tab.id
        parent.makeKeyAndOrderFront(nil)
        windowState.openCommandLens(prefill: tab.activePage.url.absoluteString, anchor: field, source: field)
    }
}

/// What a card window shows: the page's address bar under the window's lights, the card's two
/// verbs at its trailing end, and the page. The toolbar carries the window's tint, so the
/// card reads as the islands' sibling.
private struct TabCardContent: View {
    let tab: Tab
    let page: WebPage
    let onEditAddress: () -> Void
    let onClose: () -> Void
    let onReturn: () -> Void
    let onOpen: () -> Void

    @Environment(WindowState.self) private var windowState
    @State private var isToolbarHovered = false

    enum Layout {
        static let toolbarHeight: CGFloat = 40
        /// The address field's own inset, on both sides of the toolbar.
        static let edgeInset: CGFloat = 8
        static let closeSize: CGFloat = 16
        /// The two verbs' width together, at the trailing end.
        static var verbsWidth: CGFloat { Constants.PageControls.buttonWidth * 2 + edgeInset }
    }

    /// Where the address field sits in a card at `card`: after the close button, before the
    /// verbs, centered in the toolbar.
    static func addressFieldFrame(inCard card: CGRect) -> CGRect {
        let leading = Layout.edgeInset + Constants.PageControls.buttonWidth
        return CGRect(
            x: card.minX + leading, y: card.minY + (Layout.toolbarHeight - Constants.PageControls.height) / 2,
            width: max(0, card.width - leading - Layout.verbsWidth), height: Constants.PageControls.height,
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebViewContainer(page: page)
                .ignoresSafeArea()
                .webViewAutomaticallyAdjustsContentInsets(false)
                .webViewTopContentInset(Layout.toolbarHeight)
            HStack(spacing: 0) {
                closeButton
                    .padding(.leading, Layout.edgeInset)
                PageAddressField(webPage: page, onEdit: onEditAddress)
                // The verbs wait under the pointer, so the toolbar is the address alone at rest.
                HStack(spacing: 0) {
                    verb("Return to island", symbol: "arrow.down.right.and.arrow.up.left", action: onReturn)
                    verb("Open as the page", symbol: "arrow.up.left.and.arrow.down.right", action: onOpen)
                }
                .opacity(isToolbarHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isToolbarHovered)
                .padding(.trailing, Layout.edgeInset)
            }
            .frame(height: Layout.toolbarHeight)
            .frame(maxWidth: .infinity)
            .background(windowState.controlIslandTint)
            .background(.bar)
            .ignoresSafeArea()
            .onHover { isToolbarHovered = $0 }
        }
        .frame(minWidth: TabCardWindow.minimumSize.width, minHeight: TabCardWindow.minimumSize.height)
    }

    /// The gray close of a Finder preview: it closes the tab, as closing the window does.
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: Layout.closeSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Constants.PageControls.buttonWidth, height: Constants.PageControls.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close tab")
        .accessibilityLabel("Close tab")
    }

    /// A verb in the address field's own control style, the reload button's.
    private func verb(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Constants.PageControls.buttonFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Constants.PageControls.buttonWidth, height: Constants.PageControls.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
