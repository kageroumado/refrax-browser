import AppKit
import SwiftUI

/// Individual favorite tile displayed in the sidebar grid.
///
/// Tiles adapt their size and layout based on:
/// - Content type (bookmark vs folder)
/// - Icon availability (SF Symbol, emoji, or image)
/// - Title length
///
/// ## Visual Design
///
/// Following Passwords.app aesthetic:
/// - Flat tiles with no shadows or volume
/// - Clean typography with proper hierarchy
/// - Smooth hover and press states
///
/// ## Interaction
///
/// - **Tap**: Activates bookmark or opens folder menu
/// - **Long press**: Shows context menu
/// - **Drag**: Managed by FavoritesGrid
struct FavoriteTileView: View {
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState
    @Environment(DragCoordinator.self) private var dragCoordinator
    @Environment(WebPagePool.self) private var pagePool
    @Environment(ModifierKeysState.self) private var modifierKeysState

    let item: FavoriteItem
    let isDragging: Bool
    let shouldShowTitle: Bool

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var isShowingInfoPopover = false
    @State private var isShowingPreviewPopover = false
    @State private var tileFrame: CGRect = .zero

    /// Whether this live favorite tab is currently being displayed.
    private var isActiveLiveFavorite: Bool {
        guard case let .liveFavorite(_, tab) = item.type else { return false }
        return windowState.activeTabID == tab.id
    }

    /// The tab associated with a live favorite, if any.
    private var liveFavoriteTab: Tab? {
        guard case let .liveFavorite(_, tab) = item.type else { return nil }
        return tab
    }

    /// Whether this item can show a preview (live favorites only - requires existing WebPage and not active).
    private var canShowPreview: Bool {
        liveFavoriteTab != nil && !isActiveLiveFavorite
    }

    /// The WebPage for the live favorite tab, if loaded.
    private var previewWebPage: WebPage? {
        guard let tab = liveFavoriteTab else { return nil }
        return pagePool.existingPage(for: tab.activePage)
    }

    /// Whether this live favorite has navigated away from its home URL.
    private var showHomeButton: Bool {
        liveFavoriteTab?.hasNavigatedFromHome == true
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if case let .folder(folder) = item.type {
                folderTile(folder)
            } else {
                bookmarkTile
            }
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .accessibilityIdentifier("Favorite")
        .accessibilityLabel(item.displayName)
    }
    
    // MARK: - Bookmark Tile
    
    private var bookmarkTile: some View {
        Button { handleTap() } label: {
            tileContent
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            SidebarContextMenus.Favorite(
                item: item,
                onOpen: handleTap,
                onOpenInWindow: appShortcutOpenInWindowAction,
                onGetInfo: liveFavoriteTab != nil ? { isShowingInfoPopover = true } : nil,
                onPreview: canShowPreview ? { showPreview() } : nil,
            )
        }
        .if(isShowingInfoPopover) { view in
            view.popover(isPresented: $isShowingInfoPopover, arrowEdge: .trailing) {
                if let tab = liveFavoriteTab {
                    TabInfoPopover(tab: tab, isPresented: $isShowingInfoPopover)
                }
            }
        }
        .if(isShowingPreviewPopover) { view in
            view.popover(isPresented: $isShowingPreviewPopover, arrowEdge: .trailing) {
                if let webPage = previewWebPage {
                    SnapshotPreviewView(webPage: webPage)
                }
            }
        }
        .onHover { isHovered = $0 }
        .onGeometryChange(for: CGRect.self) { geo in
            geo.frame(in: .global)
        } action: { frame in
            tileFrame = frame
        }
    }
    
    // MARK: - Folder Tile

    private func folderTile(_ folder: BookmarkFolder) -> some View {
        FolderMenuTile(folder: folder) {
            tileContent
        }
        .contextMenu {
            folderContextMenu(folder)
        }
        .onHover { isHovered = $0 }
    }
    
    // MARK: - Tile Content

    /// Whether this item is a live favorite (can be activated/selected).
    private var isLiveFavorite: Bool {
        if case .liveFavorite = item.type { return true }
        return false
    }

    /// Whether this item is a shortcut favorite.
    private var isShortcut: Bool {
        if case .shortcut = item.type { return true }
        return false
    }

    /// Returns the open in window action only for app shortcuts, nil otherwise.
    private var appShortcutOpenInWindowAction: (() -> Void)? {
        guard case let .appShortcut(shortcut) = item.type else { return nil }
        let type = shortcut.shortcutType
        return {
            let appDelegate = NSApp.typedDelegate
            switch type {
            case .downloads:
                appDelegate.downloadsWindowController.showWindow()
            case .bookmarks:
                appDelegate.bookmarksWindowController.showWindow()
            case .history:
                appDelegate.historyWindowController.showWindow()
            case .settings:
                appDelegate.settingsWindowController.showWindow()
            }
        }
    }

    /// Effective hover state: disabled when any drag is happening to prevent visual noise.
    private var effectiveHover: Bool {
        isHovered && !dragCoordinator.isDragging
    }

    /// Background style with two-tiered hover behavior:
    /// - Live favorites: subtle default, muted on hover (darkens)
    /// - Non-live favorites: muted default, subtle on hover (lightens)
    ///
    /// This swap on hover shows both types are interactive while visually
    /// distinguishing "activatable" items from "action" items.
    private var backgroundStyle: AdaptiveBackgroundStyle {
        if isActiveLiveFavorite {
            .emphasized
        } else {
            // Light by default, darken on hover
            effectiveHover ? .muted : .subtle
        }
    }
    
    private var tileContent: some View {
        tileLayout
            .padding(Metrics.tilePadding)
            .frame(height: Metrics.tileHeight)
            .adaptiveBackground(backgroundStyle, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .adaptiveBackgroundBlur()
            .overlay(alignment: .topTrailing) {
                if showHomeButton, effectiveHover {
                    homeButton
                } else if isShortcut {
                    shortcutIndicator
                } else if liveFavoriteTab?.isUnread == true {
                    unreadIndicator
                }
            }
    }

    /// Button to navigate back to the live favorite's home URL.
    @ViewBuilder
    private var homeButton: some View {
        if let tab = liveFavoriteTab, let homeURL = tab.homeURL {
            FavoriteTileHomeButton(tab: tab, homeURL: homeURL)
        }
    }

    /// Indicator showing this favorite is a shortcut (navigates current tab).
    private var shortcutIndicator: some View {
        Image(systemName: "arrowshape.turn.up.forward.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 18)
            .padding(4)
            .help("Shortcut: opens in current tab")
    }

    /// Indicator showing this live favorite has unread content.
    private var unreadIndicator: some View {
        Image(systemName: "circlebadge.fill")
            .font(.system(size: 9))
            .foregroundStyle(Color.appAccentColor)
            .frame(width: 18, height: 18)
            .padding(4)
    }
    
    // MARK: - Layout Variants
    
    private var mediumLayout: some View {
        VStack(spacing: Metrics.contentSpacing) {
            iconView
                .frame(height: Metrics.iconSize)
            
            titleText(lineLimit: 1)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var iconOnlyLayout: some View {
        ZStack {
            iconView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var tileLayout: some View {
        if shouldShowTitle {
            mediumLayout
        } else {
            iconOnlyLayout
        }
    }
    
    /// Title text with consistent height for layout stability.
    private func titleText(lineLimit: Int) -> some View {
        Text(item.displayName.isEmpty ? " " : item.displayName)
            .font(.caption)
            .fontWeight(.regular)
            .lineLimit(lineLimit)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .frame(minHeight: Metrics.titleMinHeight)
    }
    
    // MARK: - Icon View
    
    @ViewBuilder
    private var iconView: some View {
        switch item.type {
        case let .appShortcut(shortcut):
            if let customIcon = item.customIcon {
                // User-defined custom icon takes priority
                customIcon.view(size: Metrics.iconSize)
            } else {
                SymbolIconView(
                    symbolName: shortcut.iconName,
                    size: Metrics.iconSize,
                    fontSize: Metrics.iconFontSize,
                    backgroundColor: Color.resolveStoredColor(shortcut.color),
                )
            }
            
        case .folder:
            if let customIcon = item.customIcon {
                // User-defined custom icon takes priority
                customIcon.view(size: Metrics.iconSize)
            } else {
                SymbolIconView(
                    symbolName: "folder.fill",
                    size: Metrics.iconSize,
                    fontSize: Metrics.iconFontSize,
                    backgroundColor: Color.resolveStoredColor(item.color ?? "#808080"),
                )
            }
            
        default:
            if let customIcon = item.customIcon {
                // User-defined custom icon takes priority
                customIcon.view(size: Metrics.iconSize)
            } else {
                // Website favicon with automatic letter fallback
                // Use large favicon for favorites grid (high-res display)
                FaviconView(data: item.largeFaviconData, url: item.url, size: Metrics.iconSize)
            }
        }
    }
    
    // MARK: - Actions

    private func handleTap() {
        // Option+Click shows preview instead of activating
        if modifierKeysState.isOptionPressed, canShowPreview {
            showPreview()
            return
        }

        // If preview is showing for this item, dismiss it and activate normally
        if isShowingPreviewPopover {
            isShowingPreviewPopover = false
        }

        withAnimation(.spring(response: 0.2)) {
            isPressed = true
        }

        Task { @MainActor in
            try await Task.sleep(for: .milliseconds(100))

            withAnimation(.spring(response: 0.2)) {
                isPressed = false
            }

            switch item.type {
            case let .shortcut(bookmark):
                windowState.clearActiveLiveFavorite()
                if let activePage = windowState.activePage {
                    tabManager.state.webPage(for: activePage.id)?.load(bookmark.url)
                } else {
                    tabManager.createTab(url: bookmark.url)
                }
                bookmarksManager.recordVisit(for: bookmark)

            case let .liveFavorite(bookmark, tab):
                tabManager.setActiveTab(tab, in: windowState)
                bookmarksManager.recordVisit(for: bookmark)

            case .folder:
                break

            case let .appShortcut(shortcut):
                handleAppShortcutTap(shortcut.shortcutType)
            }
        }
    }

    private func showPreview() {
        // Only show preview if we have a loaded WebPage
        guard previewWebPage != nil else { return }
        isShowingPreviewPopover = true
    }
    
    private func handleAppShortcutTap(_ type: AppShortcutType) {
        switch type {
        case .downloads:
            windowState.showDetailTray(.downloads)
        case .bookmarks:
            windowState.showDetailTray(.bookmarks)
        case .history:
            windowState.showDetailTray(.history)
        case .settings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Context Menus

    private func folderContextMenu(_ folder: BookmarkFolder) -> some View {
        SidebarContextMenus.FolderFavorite(folder: folder)
    }
}

private struct SymbolIconView: View {
    let symbolName: String
    let size: CGFloat
    let fontSize: CGFloat
    let backgroundColor: Color
    
    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .offset(x: 0.5)
            .frame(width: size, height: size)
            .background {
                SquircleShape()
                    .fill(backgroundColor)
            }
    }
}

// MARK: - Folder Menu Tile

/// A wrapper that provides folder menu functionality while allowing SwiftUI gestures to work.
///
/// The view uses a callback-based approach: when a tap is detected by the parent's gesture,
/// it calls `showMenu()` on the menu trigger stored in state.
private struct FolderMenuTile<Content: View>: View {
    @Environment(WindowState.self) private var windowState
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(TabManager.self) private var tabManager

    let folder: BookmarkFolder
    let content: Content

    /// Holds the menu trigger callback. Set by the underlying NSViewRepresentable.
    @State private var menuTrigger: (() -> Void)?

    init(folder: BookmarkFolder, @ViewBuilder content: () -> Content) {
        self.folder = folder
        self.content = content()
    }

    var body: some View {
        FolderMenuTileRepresentable(
            folder: folder,
            content: content,
            menuTrigger: $menuTrigger,
            openBookmark: openBookmark,
        )
        // Tap gesture shows the folder menu (doesn't interfere with drag)
        .onTapGesture {
            menuTrigger?()
        }
    }

    private func openBookmark(_ bookmark: Bookmark) {
        if bookmark.favoriteMode == .liveFavorite,
           let tab = bookmarksManager.liveFavoriteTab(for: bookmark) {
            tabManager.setActiveTab(tab, in: windowState)
        } else {
            windowState.clearActiveLiveFavorite()
            if let activePage = windowState.activePage {
                tabManager.state.webPage(for: activePage.id)?.load(bookmark.url)
            } else {
                tabManager.createTab(url: bookmark.url)
            }
        }

        bookmarksManager.recordVisit(for: bookmark)
    }
}

/// The underlying NSViewRepresentable that hosts content and provides menu functionality.
private struct FolderMenuTileRepresentable<Content: View>: NSViewRepresentable {
    @Environment(BookmarksManager.self) private var bookmarksManager

    let folder: BookmarkFolder
    let content: Content
    @Binding var menuTrigger: (() -> Void)?
    let openBookmark: (Bookmark) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(openBookmark: openBookmark)
    }

    func makeNSView(context: Context) -> MenuHostingView<Content> {
        let view = MenuHostingView(rootView: content)
        view.menuProvider = { menu(for: folder, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: MenuHostingView<Content>, context: Context) {
        nsView.rootView = content
        nsView.menuProvider = { menu(for: folder, coordinator: context.coordinator) }

        // Update the menu trigger to show menu at view center
        DispatchQueue.main.async {
            menuTrigger = { [weak nsView] in
                guard let view = nsView else { return }
                let centerPoint = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
                view.showMenu(at: centerPoint)
            }
        }
    }
    
    private func menu(for folder: BookmarkFolder, coordinator: Coordinator) -> NSMenu {
        let nsMenu = NSMenu()
        let bookmarks = bookmarksManager.bookmarks(in: folder)
        let subfolders = bookmarksManager.subfolders(of: folder)
        
        for bookmark in bookmarks {
            let item = NSMenuItem(
                title: bookmark.title,
                action: #selector(Coordinator.openBookmark(_:)),
                keyEquivalent: "",
            )
            item.target = coordinator
            item.representedObject = bookmark
            item.image = menuImage(for: bookmark)
            nsMenu.addItem(item)
        }
        
        if !bookmarks.isEmpty, !subfolders.isEmpty {
            nsMenu.addItem(.separator())
        }
        
        for subfolder in subfolders {
            let item = NSMenuItem(title: subfolder.name, action: nil, keyEquivalent: "")
            item.image = menuImage(for: subfolder)
            item.submenu = menu(for: subfolder, coordinator: coordinator)
            nsMenu.addItem(item)
        }
        
        return nsMenu
    }
    
    private func menuImage(for bookmark: Bookmark) -> NSImage? {
        if let customIcon = bookmark.customIcon {
            return menuImage(for: customIcon)
        }
        if let faviconData = bookmark.faviconData,
           let favicon = NSImage(data: faviconData) {
            return resizedMenuImage(favicon)
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
    }

    private func resizedMenuImage(_ image: NSImage) -> NSImage {
        let size = NSSize(width: Metrics.menuIconSize, height: Metrics.menuIconSize)
        let resized = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        resized.isTemplate = false
        return resized
    }
    
    private func menuImage(for folder: BookmarkFolder) -> NSImage? {
        if let customIcon = folder.customIcon {
            return menuImage(for: customIcon)
        }
        let color = (Color.resolveStoredColorComponents(folder.color) ?? Color.Components(color: .steel)).nsColor
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
    
    private func menuImage(for icon: BookmarkIcon) -> NSImage? {
        switch icon {
        case let .sfSymbol(name):
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case let .emoji(emoji):
            emojiImage(emoji)
        case let .image(data):
            NSImage(data: data)
        }
    }
    
    private func emojiImage(_ emoji: String) -> NSImage? {
        let size = NSSize(width: Metrics.menuIconSize, height: Metrics.menuIconSize)
        return NSImage(size: size, flipped: false) { rect in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: Metrics.menuIconSize),
            ]
            (emoji as NSString).draw(in: rect, withAttributes: attributes)
            return true
        }
    }
}

private final class MenuHostingView<Content: View>: NSView {
    var menuProvider: (() -> NSMenu)?

    private let hostingView: NSHostingView<Content>

    var rootView: Content {
        get { hostingView.rootView }
        set { hostingView.rootView = newValue }
    }

    init(rootView: Content) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    // MARK: - Event Handling

    /// Let left-click events pass through to SwiftUI for gesture handling.
    /// Only intercept right-clicks for context menu.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Check if point is in bounds
        guard bounds.contains(point) else { return nil }

        // Let the hosting view handle hit testing for its content
        let pointInHostingView = hostingView.convert(point, from: self)
        if let hitView = hostingView.hitTest(pointInHostingView) {
            return hitView
        }

        // If no subview handled it, return nil to let events pass through to SwiftUI
        return nil
    }

    /// Shows the folder menu at the specified location.
    /// Called from SwiftUI via the coordinator.
    func showMenu(at point: NSPoint) {
        guard let menu = menuProvider?() else { return }
        menu.popUp(positioning: nil, at: point, in: self)
    }
}

private final class Coordinator: NSObject {
    private let openBookmarkHandler: (Bookmark) -> Void

    init(openBookmark: @escaping (Bookmark) -> Void) {
        self.openBookmarkHandler = openBookmark
    }

    // AppKit callbacks must dispatch SwiftUI state changes asynchronously.
    // See: https://chris.eidhof.nl/post/view-representable/
    @objc
    func openBookmark(_ sender: NSMenuItem) {
        guard let bookmark = sender.representedObject as? Bookmark else { return }
        DispatchQueue.main.async { [self] in
            openBookmarkHandler(bookmark)
        }
    }
}

// MARK: - Favorite Tile Home Button

/// Home button for live favorites that shows background only when the button itself is hovered.
private struct FavoriteTileHomeButton: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState

    let tab: Tab
    let homeURL: URL

    @State private var isHovered = false

    var body: some View {
        Button {
            if let webPage = tabManager.state.webPage(for: tab.activePage.id) {
                webPage.load(homeURL)
            }
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .adaptiveBackground(
                    isHovered ? buttonHoverStyle : .clear,
                    in: Circle(),
                )
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .padding(4)
        .help("Go to Home")
    }
    
    /// Background style for button hover state - subtle for selected tabs, muted for non-selected.
    private var buttonHoverStyle: AdaptiveBackgroundStyle {
        windowState.activeTabID == tab.id ? .subtle : .muted
    }
}

// MARK: - Metrics

private enum Metrics {
    static let minTileWidth: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let tileHeight: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let tilePadding: CGFloat = 4
    static let contentSpacing: CGFloat = 1
    static let iconFontSize: CGFloat = 16
    static let iconSize: CGFloat = 32
    static let cornerRadius: CGFloat = 16
    static let titleMinHeight: CGFloat = 14
    static let menuIconSize: CGFloat = 14
}

// MARK: - Equatable Conformance

extension FavoriteTileView: Equatable {
    static func == (lhs: FavoriteTileView, rhs: FavoriteTileView) -> Bool {
        lhs.item.id == rhs.item.id &&
            lhs.isDragging == rhs.isDragging &&
            lhs.shouldShowTitle == rhs.shouldShowTitle
    }
}
