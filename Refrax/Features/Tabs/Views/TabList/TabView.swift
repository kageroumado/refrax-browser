import SwiftUI

/// A single tab row in the sidebar displaying favicon, title, and action buttons.
///
/// This view adapts its appearance based on state:
/// - Shows different materials for selected vs hover states
/// - Displays pin icon for pinned tabs (changes to unpin on hover)
/// - Shows close button for unpinned tabs on hover
/// - Uses thicker materials for pinned tabs to differentiate them
///
/// ## Visual Hierarchy
/// - No background: default state
/// - Regular material: unpinned tab hover
/// - Thick material: pinned tab hover, button backgrounds
/// - Ultra thick material: selected tab
///
/// ## Performance Notes
/// - Animations scoped to background only
/// - Cached string computations in Tab model
/// - HStack-based favicon layout for proper sizing
/// - Simplified MultiPageTitleView animations
///
/// Note: Equatable conformance was intentionally removed. With SwiftData reference
/// types, comparing `lhs.tab` to `rhs.tab` always reads from the same object,
/// causing comparisons to always return `true` and blocking SwiftData observation.
/// SwiftUI's default field-by-field comparison is fast enough for this view.
struct TabView: View {
    @Environment(SidebarCellEnvironment.self) private var env

    // MARK: - Public Properties

    /// The tab model containing URL, title, favicon, and pin state
    let tab: Tab

    /// Whether this tab is currently active/selected
    let isSelected: Bool

    /// Whether this tab is being dragged (keeps hover state visible during drag)
    let isDragging: Bool
    
    // MARK: - Private State

    /// Tracks whether the mouse is hovering over the trailing button
    @State private var buttonIsHovered = false
    @State private var isLocallyHovered = false

    /// Whether the Get Info popover is showing
    @State private var isShowingInfoPopover = false

    /// Whether the preview popover is showing
    @State private var isShowingPreviewPopover = false

    /// Whether to show the multi-page tooltip
    @State private var showsMultiPageTooltip = false

    /// Task for managing tooltip hover delay
    @State private var tooltipTask: Task<Void, any Error>?

    // MARK: - Cached Display Values

    /// Cached title to prevent flash during deletion animation.
    /// Updated only when the tab has valid pages.
    @State private var cachedTitle: String = ""

    /// Cached title-is-URL flag to preserve styling during deletion.
    @State private var cachedTitleIsURL: Bool = false

    // MARK: - Loading State

    /// The WebPage for this tab's active page, if loaded.
    private var existingWebPage: WebPage? {
        env.pagePool.existingPage(for: tab.activePage)
    }

    /// Whether to show the back-to-origin button for navigation containment.
    ///
    /// Shows when a pinned tab or live favorite has navigated away from its
    /// home URL (within the same domain due to containment).
    private var showBackToOriginButton: Bool {
        (tab.isPinned || tab.isLiveFavorite) && tab.hasNavigatedFromHome
    }

    /// Whether this tab's page is currently loading.
    private var isLoading: Bool {
        existingWebPage?.isLoading == true
    }

    /// The loading progress (0.0 to 1.0).
    private var loadingProgress: Double {
        existingWebPage?.estimatedProgress ?? 0
    }

    // MARK: - Body

    var body: some View {
        // Observe selectionVersion to re-render when selection changes.
        // This creates a direct observation dependency at the TabView level,
        // bypassing ForEach's identity-based diffing which doesn't re-invoke
        // its closure when the underlying array is unchanged.
        let _ = env.selectionManager.selectionVersion
        let isMultiSelected = env.selectionManager.isSelected(tab)

        // Cache frequently-accessed computed values to avoid redundant evaluations
        let isMultiPage = tab.isMultiPage
        let hoverState = effectiveHoverState

        HStack(spacing: 0) {
            // Multi-page favicon stack or single favicon
            if isMultiPage {
                faviconStack
            } else {
                TabFaviconView(tab: tab)
            }

            // Status indicators (unread, age, audio, mic, etc.)
            TabStatusIndicators(tab: tab)

            // Title with expandable dots for multi-page tabs
            if isMultiPage {
                multiPageTitleView(hoverState: hoverState)
                    .padding(.leading, Constants.Spacing.xSmall)
            } else {
                tabTitle
                    .padding(.leading, Constants.Spacing.xSmall)
            }

            // Back-to-origin button for pinned tabs that have navigated away
            if showBackToOriginButton, hoverState {
                BackToOriginButton(tab: tab, isSelected: isSelected)
                    .padding(.leading, Constants.Spacing.small)
            }

            if hoverState {
                trailingButton(hoverState: hoverState)
                    .padding(.leading, Constants.Spacing.small)
            }
        }
        .padding(.vertical, 6)
        .frame(height: Constants.Layout.tabItemHeight)
        .contentShape(Rectangle())
        .padding(.horizontal, Constants.Spacing.small2)
        .adaptiveBackground(highlightState(isMultiSelected: isMultiSelected), in: RoundedRectangle(cornerRadius: Constants.Layout.tabCornerRadius))
        .overlay(alignment: .bottom) {
            // Show loading indicator for non-active tabs that are loading
            if !isSelected {
                TabLoadingIndicator(webPage: existingWebPage)
                    .padding(.horizontal, 4)
            }
        }
        .onHover { hovering in
            isLocallyHovered = hovering

            // Preview logic moved here - no separate onChange observation needed
            let shouldShowPreview = hovering && !isDragging && !isSelected
            if shouldShowPreview, let frame = env.geometryState.itemFrame(for: tab.id) {
                env.tabPreviewManager.startHover(tab: tab, globalFrame: frame)
            } else if !hovering {
                env.tabPreviewManager.endHover(for: tab)
            }

            // Multi-page tooltip logic
            handleMultiPageTooltipHover(hovering: hovering)
        }
        // Multi-page tooltip overlay - placed after clipShape so it won't be clipped
        .overlay(alignment: .top) {
            if showsMultiPageTooltip, isMultiPage {
                MultiPageTooltip(tab: tab, activePageID: tab.activePage.id)
                    .offset(y: -8) // Position above the tab
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showsMultiPageTooltip)
        .contextMenu {
            contextMenuContent
        }
        .if(isShowingInfoPopover) { view in
            view.popover(isPresented: $isShowingInfoPopover, arrowEdge: .trailing) {
                TabInfoPopover(tab: tab, isPresented: $isShowingInfoPopover)
            }
        }
        .if(isShowingPreviewPopover) { view in
            view.popover(isPresented: $isShowingPreviewPopover, arrowEdge: .trailing) {
                if let webPage = existingWebPage {
                    SnapshotPreviewView(webPage: webPage)
                }
            }
        }
        .if(env.tabManager.showingRestorePopoverForTabID == tab.id) { view in
            view.popover(
                isPresented: Binding(
                    get: { env.tabManager.showingRestorePopoverForTabID == tab.id },
                    set: { if !$0 { env.tabManager.showingRestorePopoverForTabID = nil } },
                ),
                arrowEdge: .trailing,
            ) {
                RestoreTabPopover(tab: tab, tabManager: env.tabManager)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(tabAccessibilityID)
        .accessibilityLabel(cachedTitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear { updateCachedDisplayValues() }
        .onChange(of: tab.displayInfo) { _, _ in updateCachedDisplayValues() }
        // Explicit observation of layoutConfigurationData for multi-page tabs.
        // displayInfo depends on activePage which is computed from this data,
        // but SwiftUI doesn't track through the computed property chain reliably.
        .onChange(of: tab.layoutConfigurationData) { _, _ in updateCachedDisplayValues() }
    }
    
    // MARK: - Computed Properties

    /// Accessibility identifier based on sanitized title for UI automation.
    /// Uses title truncated to 30 chars with special characters replaced.
    private var tabAccessibilityID: String {
        let title = cachedTitle.isEmpty ? "untitled" : cachedTitle
        let sanitized = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
            .prefix(30)
        return "tab-\(sanitized)"
    }

    /// Combines dragging and hover states to prevent visual flicker during drag operations.
    private var effectiveHoverState: Bool {
        isDragging || isLocallyHovered
    }

    /// Dynamic context menu that shows multi-tab operations when multiple tabs are selected.
    ///
    /// Only shows the multi-tab menu if this tab is part of the selection.
    /// Right-clicking an unselected tab shows the single-tab menu.
    /// Archived tabs show a simplified context menu.
    @ViewBuilder
    private var contextMenuContent: some View {
        if tab.isArchived {
            SidebarContextMenus.ArchivedTab(tab: tab, onGetInfo: {
                isShowingInfoPopover = true
            })
        } else if env.selectionManager.hasSelection, env.selectionManager.isSelected(tab) {
            SidebarContextMenus.MultiTab(
                selectedTabs: env.selectionManager.selectedTabs,
                onOperationComplete: {
                    env.selectionManager.clearSelection()
                },
            )
        } else {
            SidebarContextMenus.Tab(
                tab: tab,
                onRename: startRename,
                onGetInfo: { isShowingInfoPopover = true },
                onPreview: !isSelected && existingWebPage != nil ? { isShowingPreviewPopover = true } : nil,
            )
        }
    }

    /// Whether this tab is in rename mode (derived from centralized state)
    private var isEditing: Bool {
        env.tabManager.renamingItemID == tab.id
    }

    /// The tab title - either static text or rename field.
    /// The rename field is a separate struct to isolate @FocusState overhead.
    @ViewBuilder
    private var tabTitle: some View {
        if isEditing {
            // Separate view struct isolates @FocusState - only instantiated when renaming
            TabRenameField(
                tab: tab,
                isSelected: isSelected,
                onCommit: { newName in
                    env.tabManager.setCustomName(newName, for: tab)
                    env.tabManager.renamingItemID = nil
                },
                onCancel: {
                    env.tabManager.renamingItemID = nil
                },
            )
        } else {
            Text(cachedTitle)
                .font(.system(size: Constants.Typography.bodySize))
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(cachedTitleIsURL ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(displayOpacity)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("\(tabAccessibilityID)-title")
        }
    }

    // MARK: - Rename Action

    /// Start editing the tab name
    private func startRename() {
        env.tabManager.renamingItemID = tab.id
    }

    /// Updates cached display values only when the tab has valid pages.
    ///
    /// This prevents visual flash during deletion animation, where SwiftData's
    /// cascade delete clears the pages array while SwiftUI still renders the view.
    private func updateCachedDisplayValues() {
        guard !tab.pages.isEmpty else { return }
        cachedTitle = tab.displayTitle
        cachedTitleIsURL = tab.displayTitleIsURL
    }

    /// Determines text opacity based on tab state for visual hierarchy.
    private var displayOpacity: Double {
        if isDragging { return 1 }
        if isSelected { return Constants.Opacity.tabSelected }
        if effectiveHoverState { return Constants.Opacity.tabHover }
        return Constants.Opacity.tabDefault
    }

    /// The background style for the tab item.
    private func highlightState(isMultiSelected: Bool) -> AdaptiveBackgroundStyle {
        if isSelected, isMultiSelected { return .emphasizedSecondary }
        if isSelected { return .emphasized }
        if isMultiSelected { return .secondary }
        if effectiveHoverState { return .subtle }
        return .clear
    }
    
    /// Trailing button that shows pin/unpin for pinned tabs or close for unpinned tabs on hover.
    ///
    /// Note: Tabs in groups don't show pin buttons - only the group header can be pinned.
    private func trailingButton(hoverState: Bool) -> some View {
        Group {
            // Don't show pin button for tabs in groups
            if tab.isPinned, tab.groupID == nil {
                pinButton(hoverState: hoverState)
            } else if hoverState {
                closeButton
            }
        }
        .frame(width: Constants.Layout.tabButtonVisibleSize, height: Constants.Layout.tabButtonHitTargetSize)
        .onHover { buttonIsHovered = $0 }
    }
    
    /// Background style for button hover state - subtle for selected tabs, muted for non-selected.
    private var buttonHoverStyle: AdaptiveBackgroundStyle {
        isSelected ? .subtle : .muted
    }

    /// Pin/unpin button for pinned tabs.
    private func pinButton(hoverState: Bool) -> some View {
        Button(action: { env.tabManager.togglePinTab(tab) }) {
            Image(systemName: hoverState ? "pin.slash.fill" : "pin.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: Constants.Layout.tabButtonVisibleSize, height: Constants.Layout.tabButtonVisibleSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .adaptiveBackground(
            hoverState && buttonIsHovered ? buttonHoverStyle : .clear,
            in: Circle(),
        )
        .help(hoverState ? "Unpin Tab" : "Pinned")
        .accessibilityIdentifier("\(tabAccessibilityID)-pin")
        .accessibilityLabel(hoverState ? "Unpin Tab" : "Pinned Tab")
    }

    /// Close button for unpinned tabs on hover.
    private var closeButton: some View {
        Button(action: { env.tabManager.requestCloseTab(tab) }) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: Constants.Layout.tabButtonVisibleSize, height: Constants.Layout.tabButtonVisibleSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .adaptiveBackground(
            buttonIsHovered ? buttonHoverStyle : .clear,
            in: Circle(),
        )
        .help("Close Tab")
        .accessibilityIdentifier("\(tabAccessibilityID)-close")
        .accessibilityLabel("Close Tab")
    }
    
    /// Spacer to maintain layout when no button is visible.
    private var spacer: some View {
        Color.clear
            .frame(width: Constants.Layout.tabButtonVisibleSize, height: Constants.Layout.tabButtonVisibleSize)
    }
    
    // MARK: - Multi-Page Views
    
    /// Stacked favicons for multi-page tabs (up to 4 visible).
    ///
    /// Uses HStack with negative spacing instead of ZStack + offset for proper layout semantics.
    /// This eliminates manual frame calculations and prevents overlapping with adjacent views.
    private var faviconStack: some View {
        HStack(spacing: -8) { // 24pt icon - 8pt spacing = 16pt overlap
            ForEach(Array(tab.sortedPages.prefix(4).enumerated()), id: \.element.id) { index, page in
                TabFaviconView(tab: tab, page: page)
                    .zIndex(Double(3 - index)) // Earlier favicons appear on top
            }
        }
    }
    
    /// Multi-page title view
    private func multiPageTitleView(hoverState _: Bool) -> some View {
        MultiPageTitleView(
            displayTitle: cachedTitle,
            isSelected: isSelected,
            displayOpacity: displayOpacity,
        )
    }

    // MARK: - Multi-Page Tooltip

    /// Handles hover state for multi-page tooltip with delay.
    private func handleMultiPageTooltipHover(hovering: Bool) {
        // Only show tooltip for multi-page tabs
        guard tab.isMultiPage else {
            tooltipTask?.cancel()
            tooltipTask = nil
            if showsMultiPageTooltip {
                showsMultiPageTooltip = false
            }
            return
        }

        if hovering {
            // Start delay timer for tooltip appearance
            tooltipTask?.cancel()
            tooltipTask = Task {
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                showsMultiPageTooltip = true
            }
        } else {
            // Cancel pending tooltip and dismiss immediately
            tooltipTask?.cancel()
            tooltipTask = nil
            if showsMultiPageTooltip {
                showsMultiPageTooltip = false
            }
        }
    }
}

// MARK: - Multi-Page Title View

/// Title view for multi-page tabs showing the last focused page title.
///
/// For multi-page tabs, displays the title of the active (last focused) page.
/// A tooltip overlay shows all page titles when hovering the tab.
///
/// The title is passed from the parent to ensure proper observation - computing
/// it from `tab.activePage.title` doesn't work because SwiftUI can't track
/// through the computed property chain that depends on decoded JSON data.
private struct MultiPageTitleView: View {
    let displayTitle: String
    let isSelected: Bool
    let displayOpacity: Double

    var body: some View {
        Text(displayTitle)
            .font(.system(size: Constants.Typography.bodySize))
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundColor(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(displayOpacity)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Multi-Page Tooltip

/// Layout constants for multi-page tooltip.
private enum MultiPageTooltipLayout {
    static let fontSize: CGFloat = 11
    static let cornerRadius: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 6
    static let itemSpacing: CGFloat = 4
    static let maxWidth: CGFloat = 220
}

/// A tooltip showing all page titles for a multi-page tab.
///
/// Displays as a VStack of page titles with frosted glass background.
/// Similar in style to the SpaceTooltip used in the space picker.
///
/// The activePageID is passed explicitly to avoid observation issues with
/// computed properties that depend on decoded JSON data.
private struct MultiPageTooltip: View {
    let tab: Tab
    let activePageID: UUID

    private typealias Layout = MultiPageTooltipLayout

    /// Pages to display in the tooltip.
    private var pagesToShow: [TabPage] {
        Array(tab.sortedPages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            ForEach(pagesToShow) { page in
                HStack(spacing: 6) {
                    // Small favicon
                    if let faviconData = page.faviconData,
                       let nsImage = NSImage(data: faviconData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                    }

                    // Page title
                    Text(page.title.isEmpty ? page.url.host ?? "Untitled" : page.title)
                        .font(.system(size: Layout.fontSize, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Active indicator
                    if page.id == activePageID {
                        Circle()
                            .fill(Color.appAccentColor)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .frame(maxWidth: Layout.maxWidth, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .fixedSize()
    }
}

// MARK: - Tab Loading Indicator

/// A loading indicator that directly observes a WebPage's loading state.
///
/// This wrapper is necessary because SwiftUI's observation doesn't automatically
/// propagate through dictionary lookups on @Observable objects. By accepting the
/// WebPage directly and accessing its properties in this view's body, we establish
/// proper observation tracking.
private struct TabLoadingIndicator: View {
    let webPage: WebPage?

    var body: some View {
        // Access properties directly to establish observation
        let isLoading = webPage?.isLoading ?? false
        let progress = webPage?.estimatedProgress ?? 0

        LoadingIndicatorBar(isLoading: isLoading, progress: progress, height: 2)
    }
}

// MARK: - Restore Tab Popover

/// Confirmation popover for restoring an archived tab.
///
/// Shows when the user clicks an archived tab (which are non-activatable).
/// Provides Cancel and Restore options.
private struct RestoreTabPopover: View {
    let tab: Tab
    let tabManager: TabManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore this tab?")
                .font(.headline)

            HStack(spacing: 8) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Restore") {
                    restore()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }

    private func dismiss() {
        tabManager.showingRestorePopoverForTabID = nil
    }

    private func restore() {
        do {
            try tabManager.archiveManager.restoreTab(tab)
        } catch {
            Logger.debug("Failed to restore tab: \(error)", category: Logger.tabs)
        }
        dismiss()
    }
}

// MARK: - Tab Rename Field

/// Isolated rename text field to avoid @FocusState overhead in every TabView.
///
/// By putting @FocusState in this separate struct, focus tracking infrastructure
/// is only created when this view is actually instantiated (during rename).
/// This eliminates ~36,000 unnecessary FocusStore/LazyLayoutCacheItem updates
/// that occurred when @FocusState was in every TabView.
private struct TabRenameField: View {
    let tab: Tab
    let isSelected: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        TextField("Tab name", text: $editingText)
            .font(.system(size: Constants.Typography.bodySize))
            .fontWeight(isSelected ? .semibold : .regular)
            .textFieldStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focused($isTextFieldFocused)
            .onSubmit { commitRename() }
            .onExitCommand { onCancel() }
            .onAppear {
                editingText = tab.customName ?? tab.displayTitle
                // Defer focus to ensure field is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTextFieldFocused = true
                    selectAllText()
                }
            }
            .onChange(of: isTextFieldFocused) { _, focused in
                if !focused { onCancel() }
            }
            .accessibilityIdentifier("tab-title-edit-\(tab.id)")
    }

    private func commitRename() {
        let trimmedName = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            onCommit(trimmedName)
        } else {
            onCancel()
        }
    }

    private func selectAllText() {
        if let window = NSApp.keyWindow,
           let fieldEditor = window.fieldEditor(false, for: nil) as? NSTextView {
            fieldEditor.selectAll(nil)
        }
    }
}

// MARK: - Back to Origin Button

/// Button to navigate a pinned/live-favorite tab back to its home URL.
///
/// Shown when a pinned tab or live favorite has navigated within its domain
/// away from the original pinned URL. Allows users to quickly return to their
/// designated starting point (Arc-style behavior).
private struct BackToOriginButton: View {
    @Environment(WebPagePool.self) private var pagePool

    let tab: Tab
    let isSelected: Bool

    @State private var isHovered = false

    /// Background style for button hover state - subtle for selected tabs, muted for non-selected.
    private var buttonHoverStyle: AdaptiveBackgroundStyle {
        isSelected ? .subtle : .muted
    }

    var body: some View {
        Button(action: navigateToOrigin) {
            Image(systemName: "house.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: Constants.Layout.tabButtonVisibleSize, height: Constants.Layout.tabButtonVisibleSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .adaptiveBackground(
            isHovered ? buttonHoverStyle : .clear,
            in: Circle(),
        )
        .onHover { isHovered = $0 }
        .help("Go back to \(tab.homeURL?.host ?? "origin")")
        .accessibilityIdentifier("tab-home-\(tab.id)")
        .accessibilityLabel("Go back to origin")
    }

    private func navigateToOrigin() {
        guard let homeURL = tab.homeURL,
              let webPage = pagePool.existingPage(for: tab.activePage)
        else { return }
        webPage.load(homeURL)
    }
}
