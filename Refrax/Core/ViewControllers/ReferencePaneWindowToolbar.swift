import SwiftUI

// MARK: - Toolbar Button Style

/// View modifier that applies consistent styling to reference pane toolbar buttons.
///
/// Provides:
/// - Glass effect background
/// - Secondary color hover highlight
/// - Fixed frame dimensions
private struct ReferencePaneToolbarButtonStyle: ViewModifier {
    @State private var isHovered = false

    let width: CGFloat
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: width, height: height)
            .glassEffect()
            .background {
                Capsule()
                    .fill(.secondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Applies the reference pane toolbar button styling to an icon.
    func referencePaneToolbarButtonStyle(
        width: CGFloat = 33.5,
        height: CGFloat = 24,
    ) -> some View {
        modifier(ReferencePaneToolbarButtonStyle(width: width, height: height))
    }
}

// MARK: - Reference Pane Window Toolbar

/// SwiftUI toolbar for the reference pane window.
///
/// Positioned at top of window with centered address bar layout:
/// ```
/// [Traffic Lights][Dock]     [Address Bar]     [Tabs▼][Add]
/// ```
struct ReferencePaneWindowToolbar: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState

    let onReturnToDock: () -> Void

    private enum Layout {
        static let horizontalPadding: CGFloat = 12
        static let trafficLightWidth: CGFloat = 78
        static let spacing: CGFloat = 8
        static let buttonWidth: CGFloat = 33.5
        static let buttonHeight: CGFloat = 24
    }

    private var displayedTab: Tab? {
        windowState.activeReferenceTab
    }

    private var activeWebPage: WebPage? {
        guard let tab = displayedTab else { return nil }
        return tabManager.pagePool.existingPage(for: tab.activePage)
    }

    private var referenceTabs: [Tab] {
        windowState.activeSpace?.referenceTabs ?? []
    }

    private var canAddTab: Bool {
        (windowState.activeSpace?.referenceTabCount ?? 0) < 4
    }

    private var addressBarContext: AddressBarContext {
        AddressBarContext(
            webPage: activeWebPage,
            tabPage: displayedTab?.activePage,
            onOpenLens: { windowState.openReferencePaneLens() },
            isLensVisible: windowState.showsReferencePaneLens,
            onShowFindNavigator: {},
        )
    }

    var body: some View {
        // Read tabListVersion to establish observation dependency.
        // This ensures the view re-renders when reference tabs change,
        // since referenceTabs uses computed properties on Space (@Model) which
        // don't participate in SwiftUI observation.
        // swiftlint:disable:next redundant_discardable_let
        let _ = tabManager.state.tabListVersion

        CenteredMiddleLayout {
            leadingContent
            centerContent
            trailingContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            windowState.webViewsShouldIgnoreAllEvents = hovering
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }

    // MARK: - Layout Sections

    private var leadingContent: some View {
        HStack(spacing: Layout.spacing) {
            Color.clear.frame(width: Layout.trafficLightWidth)

            Button(action: onReturnToDock) {
                Image(systemName: "arrow.right.to.line.square")
                    .referencePaneToolbarButtonStyle(width: Layout.buttonWidth, height: Layout.buttonHeight)
            }
            .buttonStyle(.plain)
            .help("Dock the Reference Pane")
        }
    }

    private var centerContent: some View {
        AddressBar()
            .environment(\.addressBarContext, addressBarContext)
            .environment(\.addressBarIsFloating, true)
            .frame(height: Layout.buttonHeight)
            .frame(minWidth: 150, maxWidth: 400)
            .glassEffect()
    }

    private var trailingContent: some View {
        HStack(spacing: Layout.spacing) {
            ToolbarTabSelector(
                tabs: referenceTabs,
                activeTab: displayedTab,
                onSelectTab: { selectTab($0) },
                onCloseTab: { closeTab($0) },
            )

            if canAddTab {
                addTabButton
            }
        }
        .padding(.trailing, Layout.horizontalPadding)
    }

    private var addTabButton: some View {
        Button {
            windowState.openReferencePaneLens(forNewTab: true)
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
                .referencePaneToolbarButtonStyle(width: Layout.buttonWidth, height: Layout.buttonHeight)
        }
        .buttonStyle(.plain)
        .help("Add Reference Tab")
    }

    // MARK: - Actions

    private func selectTab(_ tab: Tab) {
        tabManager.setActiveReferenceTab(tab, in: windowState)
        windowState.recordInteraction(with: tab.activePage.id)

        // Claim ownership for the new tab's WebPage since this toolbar
        // is always in the separate window.
        if let webPage = tabManager.pagePool.existingPage(for: tab.activePage) {
            webPage.claimOwnership(for: windowState)
        }
    }

    private func closeTab(_ tab: Tab) {
        tabManager.closeReferenceTab(tab)
    }
}
