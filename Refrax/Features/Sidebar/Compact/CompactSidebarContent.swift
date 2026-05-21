import AppKit
import SwiftUI

// MARK: - Compact Sidebar Content

/// Compact sidebar view showing dock-style tab favicons.
///
/// A narrow strip (48pt) with three zones:
/// - **Top controls**: Sidebar toggle, navigation, favorites
/// - **Tab list**: `RecyclingTabListView` in compact mode — NSTableView
///   with favicon-only cells, shared infrastructure with the expanded sidebar
/// - **Bottom controls**: Footer buttons, space switcher
///
/// Tooltips are positioned via direct frame reporting from cells
/// to `WindowState.compactTabTooltipFrame`.
struct CompactSidebarContent: View {
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserState.self) private var browserState
    @Environment(Sidebar.LayoutManager.self) private var layoutManager
    @Environment(SpaceManager.self) private var spaceManager

    @State private var showingFavoritesPopover = false

    // Space management state
    @State private var showingSpacePopover = false
    @State private var showCreateSpaceSheet = false
    @State private var showSpaceManagementSheet = false
    @State private var spaceToEdit: Space?

    // Recycling tab list state
    @State private var scrollToProxy = ScrollToItemProxy()
    @State private var topControlsHeight: CGFloat = 0
    @State private var bottomControlsHeight: CGFloat = 0

    private typealias Layout = CompactSidebarLayout

    // MARK: - Body

    var body: some View {
        let activeTabID = windowState.activeTabID
        let activeTab = windowState.activeTab
        let activeSpace = windowState.activeSpace

        // Compute active live favorite favicon data once at body level
        let activeFavoriteFaviconData: Data? = {
            guard let tab = activeTab, tab.status == .liveFavorite else { return nil }
            return layoutManager.favoritesLayout
                .first { $0.tab?.id == tab.id }?
                .faviconData
        }()

        RecyclingTabListView(
            pinnedItems: layoutManager.pinnedItems,
            normalItems: layoutManager.normalItems,
            activeTabID: activeTabID,
            isShowingLiveFavorite: windowState.isShowingLiveFavorite,
            isCompact: true,
            scrollToProxy: scrollToProxy,
            tabListPushOffset: 0,
            itemPushOffsets: [:],
            topContentInset: topControlsHeight,
            bottomContentInset: bottomControlsHeight,
            onScrollChange: nil,
            emptyAreaMenuBuilder: nil,
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            topControls(activeFavoriteFaviconData: activeFavoriteFaviconData)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    topControlsHeight = height
                }
        }
        .overlay(alignment: .bottom) {
            bottomControls(activeSpace: activeSpace)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    bottomControlsHeight = height
                }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showCreateSpaceSheet) {
            CreateSpaceSheet()
        }
        .sheet(isPresented: $showSpaceManagementSheet) {
            SpaceManagementSheet()
        }
        .sheet(item: $spaceToEdit) { space in
            EditSpaceSheet(space: space)
        }
    }

    // MARK: - Top Controls

    private func topControls(activeFavoriteFaviconData: Data?) -> some View {
        VStack(spacing: Layout.buttonSpacing) {
            sidebarToggleButton
            CompactNavigationControls()

            if !layoutManager.favoritesLayout.isEmpty {
                favoritesButton(activeFaviconData: activeFavoriteFaviconData)
            }
        }
        .padding(.top, Layout.topControlsPadding)
        .frame(maxWidth: .infinity)
        .background { CompactControlsBackground(edge: .top) }
    }

    // MARK: - Bottom Controls

    private func bottomControls(activeSpace: Space?) -> some View {
        VStack(spacing: Layout.buttonSpacing) {
            CompactFooterControls()
            spaceSwitcher(activeSpace: activeSpace)
        }
        .padding(.bottom, Layout.bottomControlsPadding)
        .frame(maxWidth: .infinity)
        .background { CompactControlsBackground(edge: .bottom) }
    }

    // MARK: - Space Switcher

    private func spaceSwitcher(activeSpace: Space?) -> some View {
        Button {
            showingSpacePopover = true
        } label: {
            currentSpaceIcon(activeSpace: activeSpace)
        }
        .buttonStyle(.plain)
        .help(activeSpace?.name ?? "Switch Space")
        .hoverFillAction(
            isActive: $showingSpacePopover,
            delay: Layout.longHoverDelay,
            fillColor: .secondary.opacity(Layout.Icon.backgroundOpacity),
            clipShape: SquircleShape(),
            size: Layout.buttonSize,
        ) {
            showingSpacePopover = true
        }
        .arrowlessPopover(isPresented: $showingSpacePopover, arrowEdge: .trailing) {
            spacePopoverContent(activeSpace: activeSpace)
        }
    }

    private func spacePopoverContent(activeSpace: Space?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Space list
            ForEach(browserState.spaces) { space in
                spacePopoverButton(for: space, activeSpaceID: activeSpace?.id)
            }

            Divider()
                .padding(.vertical, 4)

            // Edit current space
            if let space = activeSpace {
                Button {
                    showingSpacePopover = false
                    spaceToEdit = space
                } label: {
                    Label("Edit '\(space.name)'...", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(CompactSpacePopoverButtonStyle())
            }

            // New space
            Button {
                showingSpacePopover = false
                showCreateSpaceSheet = true
            } label: {
                Label("New Space...", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CompactSpacePopoverButtonStyle())

            // Manage all spaces
            Button {
                showingSpacePopover = false
                showSpaceManagementSheet = true
            } label: {
                Label("Manage All Spaces...", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CompactSpacePopoverButtonStyle())
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    private func spacePopoverButton(for space: Space, activeSpaceID: Space.ID?) -> some View {
        Button {
            showingSpacePopover = false
            spaceManager.switchToSpaceSync(space, for: windowState)
        } label: {
            HStack(spacing: 8) {
                spaceIconContent(for: space)
                    .frame(width: 20, height: 20)

                Text(space.name)
                    .lineLimit(1)

                Spacer()

                if space.id == activeSpaceID {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CompactSpacePopoverButtonStyle())
    }

    @ViewBuilder
    private func currentSpaceIcon(activeSpace: Space?) -> some View {
        if let space = activeSpace {
            spaceIconContent(for: space)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func spaceMenuIcon(for space: Space) -> some View {
        if space.isEmoji {
            Text(space.iconName)
        } else {
            Image(systemName: space.iconName)
        }
    }

    @ViewBuilder
    private func spaceIconContent(for space: Space) -> some View {
        if space.isEmoji {
            Text(space.iconName)
                .font(.system(size: Layout.Icon.standardSize))
        } else {
            Image(systemName: space.iconName)
                .font(.system(size: Layout.Icon.standardSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sidebar Toggle Button

    private var sidebarToggleButton: some View {
        Button {
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        } label: {
            compactButtonIconContent("sidebar.left")
                .frame(maxWidth: .infinity)
                .frame(height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Toggle Sidebar")
        .contextMenu {
            Button {
                toggleLayoutMode()
            } label: {
                Label("Layout Mode", systemImage: "rectangle.split.2x1")
            }

            Button {
                NSApp.sendAction(#selector(NSSplitViewController.toggleInspector(_:)), to: nil, from: nil)
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }

    private func toggleLayoutMode() {
        if windowState.isInLayoutMode {
            windowState.exitLayoutMode()
        } else {
            windowState.enterLayoutMode()
        }
    }

    // MARK: - Favorites Button

    private func favoritesButton(activeFaviconData: Data?) -> some View {
        Button {
            showingFavoritesPopover = true
        } label: {
            favoritesButtonIcon(activeFaviconData: activeFaviconData)
        }
        .buttonStyle(.plain)
        .help("Favorites")
        .hoverFillAction(
            isActive: $showingFavoritesPopover,
            delay: Layout.longHoverDelay,
            fillColor: .secondary.opacity(Layout.Icon.backgroundOpacity),
            clipShape: SquircleShape(),
            size: Layout.buttonSize,
        ) {
            showingFavoritesPopover = true
        }
        .arrowlessPopover(isPresented: $showingFavoritesPopover, arrowEdge: .trailing) {
            FavoritesGrid()
                .frame(width: Layout.favoritesGridWidth)
                .padding()
        }
    }

    private func favoritesButtonIcon(activeFaviconData: Data?) -> some View {
        ZStack {
            if let faviconData = activeFaviconData,
               let nsImage = NSImage(data: faviconData) {
                // Live favorite active - show full-size favicon with star badge
                ZStack(alignment: .topLeading) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                        .clipToSquircle()

                    // Star badge
                    favoriteTabIcon
                }
            } else {
                // No live favorite - show star (hoverFillAction provides background)
                Image(systemName: "star.fill")
                    .font(.system(size: Layout.Icon.standardSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.buttonSize)
        .contentShape(Rectangle())
    }
    
    private var favoriteTabIcon: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            .offset(y: -0.5) // optical centering
            .frame(width: 12, height: 12)
            .background(
                Circle()
                    .fill(Color.secondary.opacity(0.9)),
            )
            .offset(
                x: Layout.favoriteTabIconOffset,
                y: Layout.favoriteTabIconOffset,
            )
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Helpers

    /// Button icon with squircle background (for buttons without hover popover).
    private func compactButtonIcon(_ systemName: String) -> some View {
        ZStack {
            SquircleShape()
                .fill(.secondary.opacity(Layout.Icon.backgroundOpacity))
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)

            compactButtonIconContent(systemName)
        }
        .frame(height: Layout.buttonSize)
        .contentShape(Rectangle())
    }

    /// Button icon content only (for buttons using hoverPopover which provides its own background).
    private func compactButtonIconContent(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: Layout.Icon.standardSize, weight: .medium))
            .foregroundStyle(.secondary)
    }

    /// Icon button for use inside popovers (no background since popover provides its own).
    private func compactPopoverButtonIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: Layout.Icon.standardSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Layout.buttonSize, height: 28)
            .contentShape(Rectangle())
    }
}

// MARK: - Isolated Observation Views

/// Isolates focusedWebPage observation to prevent cascading re-renders to tab list.
///
/// Navigation state changes frequently during browsing (canGoBack, canGoForward, isLoading).
/// By isolating these observations here, the parent view and 100+ tab buttons don't re-evaluate.
private struct CompactNavigationControls: View {
    @Environment(WindowState.self) private var windowState
    @Environment(ModifierKeysState.self) private var modifierKeys

    @State private var showsCopiedFeedback = false
    @State private var addressBarDismissTask: Task<Void, Never>?
    @State private var copiedFeedbackTask: Task<Void, Never>?

    private var webPage: WebPage? {
        windowState.focusedWebPage
    }
    private var canGoBack: Bool {
        webPage?.canGoBack == true
    }
    private var canGoForward: Bool {
        webPage?.canGoForward == true
    }
    private var isLoading: Bool {
        webPage?.isLoading == true
    }

    private var showsAddressBar: Binding<Bool> {
        Binding(
            get: { windowState.showsCompactAddressBar },
            set: { newValue in
                withAnimation(.snappy(duration: 0.25)) {
                    windowState.showsCompactAddressBar = newValue
                }
            },
        )
    }

    var body: some View {
        VStack(spacing: CompactSidebarLayout.buttonSpacing) {
            linkButton
            navigationButtons
        }
        .onDisappear {
            addressBarDismissTask?.cancel()
            copiedFeedbackTask?.cancel()
        }
    }

    // MARK: - Link Button

    private var linkButton: some View {
        Button {
            copyCleanURL()
        } label: {
            linkButtonIcon
        }
        .buttonStyle(.plain)
        .help("Copy Link")
        .hoverFillAction(
            isActive: showsAddressBar,
            delay: CompactSidebarLayout.longHoverDelay,
            fillColor: .secondary.opacity(CompactSidebarLayout.Icon.backgroundOpacity),
            clipShape: SquircleShape(),
            size: CompactSidebarLayout.buttonSize,
        ) {
            addressBarDismissTask?.cancel()
            withAnimation(.snappy(duration: 0.25)) {
                windowState.showsCompactAddressBar = true
            }
        }
        .onHover { isHovering in
            if isHovering {
                addressBarDismissTask?.cancel()
            }
        }
        .onChange(of: isLoading) { oldValue, newValue in
            if newValue {
                addressBarDismissTask?.cancel()
                withAnimation(.snappy(duration: 0.25)) {
                    windowState.showsCompactAddressBar = true
                }
            } else if oldValue {
                addressBarDismissTask = Task {
                    try? await Task.sleep(for: CompactSidebarLayout.addressBarDismissDelay)
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        windowState.showsCompactAddressBar = false
                    }
                }
            }
        }
    }

    private var linkButtonIcon: some View {
        Image(systemName: showsCopiedFeedback ? "checkmark" : "link")
            .font(.system(size: CompactSidebarLayout.Icon.standardSize, weight: .medium))
            .foregroundStyle(linkButtonForegroundStyle)
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeInOut(duration: 0.15), value: showsCopiedFeedback)
            .frame(maxWidth: .infinity)
            .frame(height: CompactSidebarLayout.buttonSize)
            .contentShape(Rectangle())
    }

    private var linkButtonForegroundStyle: some ShapeStyle {
        if showsCopiedFeedback {
            AnyShapeStyle(.green)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    private func copyCleanURL() {
        guard let url = webPage?.url else { return }
        let cleanURL = url.removingTrackingParameters()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cleanURL.absoluteString, forType: .string)

        copiedFeedbackTask?.cancel()
        showsCopiedFeedback = true
        copiedFeedbackTask = Task {
            try? await Task.sleep(for: CompactSidebarLayout.copiedFeedbackDuration)
            guard !Task.isCancelled else { return }
            showsCopiedFeedback = false
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 0) {
            backButton
                .frame(maxWidth: .infinity)

            if canGoForward {
                forwardButton
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CompactSidebarLayout.buttonSize)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: canGoForward)
    }

    /// Back button or reload button (when Option is held).
    ///
    /// Right-click shows the back/forward history list, matching the
    /// address bar's back button behavior.
    private var backButton: some View {
        let showReload = modifierKeys.isOptionPressed

        return Button {
            if showReload {
                webPage?.reload()
            } else {
                webPage?.goBack()
            }
        } label: {
            Image(systemName: showReload ? "arrow.clockwise" : "chevron.left")
                .font(.system(size: CompactSidebarLayout.Icon.navigationSize, weight: .bold))
                .foregroundStyle(showReload || canGoBack ? .secondary : .quaternary)
                .frame(height: CompactSidebarLayout.buttonSize)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!showReload && !canGoBack)
        .contextMenu { backContextMenu }
    }

    @ViewBuilder
    private var backContextMenu: some View {
        if let backList = webPage?.backList, !backList.isEmpty {
            ForEach(backList) { item in
                Button(item.title ?? item.url.absoluteString) {
                    webPage?.loadBackForwardItem(item)
                }
            }
        }
    }

    private var forwardButton: some View {
        Button {
            webPage?.goForward()
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: CompactSidebarLayout.Icon.navigationSize, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(height: CompactSidebarLayout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
        .contextMenu { forwardContextMenu }
    }

    @ViewBuilder
    private var forwardContextMenu: some View {
        if let forwardList = webPage?.forwardList, !forwardList.isEmpty {
            ForEach(forwardList) { item in
                Button(item.title ?? item.url.absoluteString) {
                    webPage?.loadBackForwardItem(item)
                }
            }
        }
    }
}

/// Isolates backgroundColor observation from content.
///
/// Background color changes with website theme colors. By isolating this observation,
/// the sidebar content doesn't re-render when the background tint changes.
private struct CompactControlsBackground: View {
    @Environment(WindowState.self) private var windowState
    let edge: VariableBlurEdge

    var body: some View {
        VariableBackdropBlurView(
            edge: edge,
            tintColor: Color(windowState.backgroundColor.color),
        )
    }
}
