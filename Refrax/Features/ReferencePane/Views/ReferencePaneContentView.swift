import AppKit
import SwiftUI
import WebKit

/// Reference pane view for side-by-side browsing and AI context features.
///
/// The reference pane supports three content types:
/// - **Reference Tabs**: User-created tabs for side-by-side browsing (max 4)
/// - **Context Tab**: AI-generated content tied to main content (Ask AI, Translation, Summary)
/// - **Empty State**: Prompt to add reference content
///
/// ## Layout Modes
/// - **Docked**: Attached to right side of window in inspector panel
/// - **Separate Window**: Detached into its own window via "Open in Window"
///
/// ## Interaction
/// - Tab strip at top for switching between reference tabs
/// - Context tab badge (✨) indicates AI content
/// - Click lock icon to lock controls to toolbar
/// - Drag tabs from main sidebar to add references
/// - Close button removes individual reference tabs
/// - "+" button opens command lens to create new reference tab
///
/// ## Performance
/// - Sessions created lazily per reference tab
/// - Context tab session shared with parent content
/// - Suspended sessions after 30s of inactivity
struct ReferencePaneContentView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState
    @Environment(HistoryManager.self) private var historyManager
    @Environment(WebPagePool.self) private var pagePool

    @State private var isDropTargeted = false
    @State private var hoveredTabID: Tab.ID?

    /// Counter to force view refresh when returning from separate window.
    /// Incremented when reference pane mode changes to .docked.
    @State private var refreshToken = 0

    /// Whether this view is displayed in a separate reference pane window.
    /// When true, the window has its own toolbar with controls.
    var isInSeparateWindow: Bool = false

    /// Whether the inspector is currently collapsed.
    private var isInspectorCollapsed: Bool {
        windowState.isInspectorCollapsed
    }

    /// Height of the toolbar in the reference pane window.
    private static let toolbarHeight: CGFloat = 40

    // MARK: - Body

    /// Whether the docked view should force its WebViewContainers to be inactive.
    ///
    /// This is true when:
    /// - We're in the docked view (not separate window)
    /// - The inspector is collapsed (pane not visible)
    /// - No reference pane window is open (otherwise content is displayed there)
    private var shouldForceInactive: Bool {
        !isInSeparateWindow && isInspectorCollapsed && !windowState.hasReferencePaneWindow
    }

    var body: some View {
        // Read refreshToken to create a dependency that forces re-evaluation
        // swiftlint:disable:next redundant_discardable_let
        let _ = refreshToken

        // Read tabListVersion to establish observation dependency.
        // This ensures the view re-renders when reference tabs are added/removed,
        // since hasReferenceTabs uses computed properties on Space (@Model) which
        // don't participate in SwiftUI observation.
        // swiftlint:disable:next redundant_discardable_let
        let _ = tabManager.state.tabListVersion

        ZStack(alignment: Alignment(horizontal: .leading, vertical: .activeTab)) {
            mainContentView

            // Only show tab management control when a tab is actually selected
            // (not in the empty state tab selector view)
            if !isInSeparateWindow, activeReferenceContent != nil, !isInspectorCollapsed {
                tabManagementControl
            }
        }
        .webViewForcedInactive(shouldForceInactive)
        .onChange(of: isInspectorCollapsed) { wasCollapsed, isCollapsed in
            // Refresh when inspector expands (was collapsed, now not)
            if wasCollapsed, !isCollapsed {
                refreshToken += 1
            }
        }
        .overlay(dropTargetOverlay)
        .overlay {
            DragTrackingView(
                onDragMove: { _, pasteboard in
                    // Check if this is a valid Refrax tab drag
                    let hasTabID = DragPasteboardWriter.containsRefraxDragData(pasteboard)
                    withAnimation(.snappy(duration: 0.2)) {
                        isDropTargeted = hasTabID
                    }
                    return hasTabID ? .valid : .noTarget
                },
                onDragExit: {
                    withAnimation(.snappy(duration: 0.2)) {
                        isDropTargeted = false
                    }
                },
                onDrop: { pasteboard, _ in
                    isDropTargeted = false
                    return handleDrop(from: pasteboard)
                },
            )
        }
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        Group {
            if windowState.isAgentChatActive {
                AgentChatView()
            } else if let content = activeReferenceContent {
                referenceContentView(for: content)
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reference panel")
    }

    // MARK: - Tab Management Control

    /// The currently displayed reference tab.
    private var displayedReferenceTab: Tab? {
        windowState.activeReferenceTab
    }

    /// Reference tabs available in the current space.
    private var referenceTabs: [Tab] {
        windowState.activeSpace?.referenceTabs ?? []
    }

    private var tabManagementControl: some View {
        TabManagementControl(
            tabs: referenceTabs,
            activeTab: displayedReferenceTab,
            canAddTab: referenceTabs.count < 4,
            onSelectTab: { selectReferenceTab($0) },
            onCloseTab: { closeReferenceTab($0) },
            onAddTab: addEmptyReferenceTab,
            onOpenInWindow: openInSeparateWindow,
        )
    }

    // MARK: - Drop Target Overlay

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.appAccentColor, lineWidth: 3)
                .background(Color.appAccentColor.opacity(0.1))
                .padding(4)
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func referenceContentView(for tab: ReferenceContent) -> some View {
        if !isInSeparateWindow, isInspectorCollapsed {
            Color.clear
        } else {
            referenceTabContent(for: tab)
        }
    }

    @ViewBuilder
    private func referenceTabContent(for tab: Tab) -> some View {
        let activePage = tab.activePage

        if activePage.url.isDeepLink {
            deepLinkContent(for: activePage)
        } else {
            webPageContent(for: activePage)
        }
    }

    @ViewBuilder
    private func deepLinkContent(for page: TabPage) -> some View {
        if let deepLink = DeepLink(url: page.url) {
            DeepLinkView(deepLink: deepLink)
        } else {
            loadingPlaceholder
        }
    }

    @ViewBuilder
    private func webPageContent(for page: TabPage) -> some View {
        // Don't render WebViewContainer at all when docked and collapsed.
        // This prevents a SwiftUI environment propagation race where the environment
        // (isForcedInactive) updates before the view hierarchy does, causing
        // the WebViewContainer to briefly enter portal mode before being removed.
        if !isInSeparateWindow, isInspectorCollapsed {
            loadingPlaceholder
        } else if let webPage = pagePool.page(for: page) {
            WebViewContainer(page: webPage)
                .webViewTopContentInset(isInSeparateWindow ? Self.toolbarHeight : 0)
        } else {
            loadingPlaceholder
        }
    }

    /// Reusable loading placeholder view.
    private var loadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Material.regular)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text(referenceTabs.isEmpty ? "No Reference Tab" : "Select a Reference Tab")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            // Show available reference tabs if any exist but none is selected
            if !referenceTabs.isEmpty {
                availableTabsList
            }

            // Agent chat button
            Button {
                windowState.toggleAgentChat()
            } label: {
                Label("Agent Chat", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: 200)
            .accessibilityIdentifier("reference-pane-agent-chat")
            .accessibilityLabel("Open agent chat")

            if referenceTabs.count < 4 {
                Button(action: addEmptyReferenceTab) {
                    Label("Command Lens", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: 200)
                .accessibilityIdentifier("reference-pane-command-lens")
                .accessibilityLabel("Add reference tab via Command Lens")
            }

            Text("Tip: ⌘⌃S to toggle chat")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// List of available reference tabs shown in empty state.
    private var availableTabsList: some View {
        VStack(spacing: 2) {
            ForEach(referenceTabs) { tab in
                availableTabRow(tab)
            }
        }
        .frame(maxWidth: 300)
    }

    private func availableTabRow(_ tab: Tab) -> some View {
        let isHovered = hoveredTabID == tab.id

        return Button {
            selectReferenceTab(tab)
        } label: {
            HStack(spacing: Constants.Spacing.small2) {
                FaviconView(
                    data: tab.activePage.faviconData,
                    url: tab.activePage.url,
                    size: Constants.Layout.tabFaviconSize,
                )

                Text(tab.displayTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Close button - only visible on hover
                Button {
                    closeReferenceTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: Constants.Layout.tabButtonVisibleSize,
                            height: Constants.Layout.tabButtonVisibleSize,
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .help("Close reference tab")
            }
            .padding(.vertical, Constants.Spacing.small2)
            .padding(.horizontal, Constants.Spacing.small2)
            .frame(height: Constants.Layout.tabItemHeight)
            .adaptiveBackground(
                isHovered ? .subtle : .clear,
                in: RoundedRectangle(cornerRadius: Constants.Layout.tabCornerRadius),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
        .contextMenu {
            SidebarContextMenus.ReferenceTab(tab: tab)
        }
    }

    // MARK: - Computed Properties

    /// Returns the active reference tab, or nil if none is selected.
    ///
    /// Unlike main tabs, reference tabs don't auto-select on launch.
    /// The user must explicitly choose which reference tab to load.
    private var activeReferenceContent: ReferenceContent? {
        windowState.activeReferenceTab
    }

    private var hasReferenceTabs: Bool {
        !referenceTabs.isEmpty
    }

    // MARK: - Actions

    private func selectReferenceTab(_ tab: Tab) {
        tabManager.setActiveReferenceTab(tab, in: windowState)
        windowState.recordInteraction(with: tab.activePage.id)

        // When in separate window mode, claim ownership for the new tab's WebPage.
        // Without this, the new tab would have ownerID=nil and since isWindowKey
        // checks the main window (not the ref pane window), isOwner would be false.
        if windowState.hasReferencePaneWindow,
           let webPage = pagePool.existingPage(for: tab.activePage) {
            webPage.claimOwnership(for: windowState)
        }
    }

    private func closeReferenceTab(_ tab: Tab) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            tabManager.closeReferenceTab(tab)
        }
    }

    private func openInSeparateWindow() {
        guard let controller = tabManager.windowManager.activeWindowController else { return }
        tabManager.windowManager.createReferencePaneWindow(from: controller)
    }

    private func addEmptyReferenceTab() {
        windowState.isCreatingReferenceTab = true
        windowState.openCommandLens()
    }

    private func handleDrop(from pasteboard: NSPasteboard) -> Bool {
        // Extract tab IDs from the Refrax-specific pasteboard type
        let tabIDs = DragPasteboardWriter.extractTabIDs(from: pasteboard)

        guard let firstTabID = tabIDs.first,
              let draggedTab = tabManager.state.tab(for: firstTabID),
              canAcceptDroppedTab(draggedTab) else {
            return false
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            tabManager.moveTabToReferencePane(draggedTab)
        }

        return true
    }

    /// Validates whether a dropped tab can be accepted.
    private func canAcceptDroppedTab(_ tab: Tab) -> Bool {
        guard let space = windowState.activeSpace else { return false }
        return tab.pages.count == 1
            && space.referenceTabCount < 4
    }
}
