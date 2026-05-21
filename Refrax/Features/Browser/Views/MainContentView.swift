import SwiftUI

struct MainContentView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(ClipboardMonitor.self) private var clipboardMonitor
    @Environment(WindowState.self) private var windowState

    @State private var showClipboardToast = false

    /// Calculates leading padding based on sidebar state and mode.
    ///
    /// - Compact mode with collapsed sidebar: 56px (compact sidebar width + glass padding)
    /// - Other collapsed states: 0px
    /// - Expanded sidebar: 8px
    private var leadingPadding: CGFloat {
        if isCompactModeActive {
            return Constants.compactSidebarPadding
        }
        return windowState.isSidebarCollapsed ? 0 : Constants.leadingPadding
    }

    /// Whether compact sidebar mode is active (collapsed + compact mode).
    private var isCompactModeActive: Bool {
        windowState.effectiveSidebarMode == .compact && windowState.isSidebarCollapsed
    }

    var body: some View {
        ZStack(alignment: .leading) {
            contentRouter

            AutoFillOverlayView()
            AgentCursorOverlay()
        }
        .clipShape(contentShape)
        .padding(.leading, leadingPadding)
        .ignoresSafeArea(edges: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Note: Space swipe gesture is now sidebar-only via sidebarSpaceSwipeGesture()
        // The main content area is reserved for page back/forward navigation
        .overlay(alignment: .bottom) {
            clipboardToastOverlay
        }
        .overlay(alignment: .top) {
            HumanInterventionBanner()
        }
        .onChange(of: clipboardMonitor.detectedURL) { _, url in
            showClipboardToast = url != nil
        }
        .onChange(of: settings.clipboardLinkMonitoring) { _, _ in
            clipboardMonitor.syncWithSettings()
        }
    }

    private var contentShape: some InsettableShape {
        // In compact mode, no rounded corners - content extends under edge extension
        let leadingRadius = isCompactModeActive ? 0 : Constants.cornerRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: leadingRadius,
            bottomLeadingRadius: leadingRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
        )
    }

    @ViewBuilder
    private var contentRouter: some View {
        if let activeTab = windowState.activeTab {
            UnifiedContentView(tab: activeTab)
        } else if settings.showSidebarHints {
            SidebarHintsView()
        } else {
            emptyStateView
        }
    }

    @ViewBuilder
    private var clipboardToastOverlay: some View {
        if showClipboardToast, let url = clipboardMonitor.detectedURL {
            ClipboardURLToast(url: url) {
                showClipboardToast = false
            }
            .padding(.bottom, Constants.clipboardToastBottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: showClipboardToast)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: Constants.emptyStateIconSize))
                .foregroundStyle(.tertiary)

            Text("No Active Tab")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Constants

private extension MainContentView {
    enum Constants {
        static let cornerRadius: CGFloat = 26
        static let leadingPadding: CGFloat = 8
        /// Leading padding when compact sidebar mode is active (compactWidth + glassEffectPadding - 1px to have a nice edge)
        static let compactSidebarPadding: CGFloat = 55
        static let emptyStateSpacing: CGFloat = 20
        static let emptyStateIconSize: CGFloat = 64
        static let clipboardToastBottomPadding: CGFloat = 24
    }
}

// MARK: - AutoFill Overlay

/// Isolated view for autofill menu overlay.
///
/// Displays a SwiftUI-based autofill menu positioned below the focused field.
/// Uses overlay positioning based on field rect from JavaScript.
///
/// By extracting AutoFillState observation into a separate view struct,
/// changes to autofill context only invalidate this view, not the entire
/// MainContentView hierarchy.
private struct AutoFillOverlayView: View {
    @Environment(AutoFillState.self) private var autoFillState

    var body: some View {
        if let context = autoFillState.context, context.hasContent {
            Color.clear
                .overlay(alignment: .topLeading) {
                    // Position menu below the field
                    AutoFillMenuView(context: context)
                        .offset(
                            x: context.rect.minX,
                            y: context.rect.maxY + Constants.menuVerticalOffset,
                        )
                }
                .overlay(alignment: .topLeading) {
                    // Key icon at the trailing edge of credential fields
                    if context.fieldType == .credential {
                        AutoFillFieldKeyIcon(rect: context.rect)
                    }
                }
        }
    }

    private enum Constants {
        static let menuVerticalOffset: CGFloat = 4
    }
}
