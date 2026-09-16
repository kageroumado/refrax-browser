import SwiftUI

// MARK: - NewTabViewLabel

/// Extracted label for NewTabView that only observes the minimal environment values needed.
///
/// This reduces observation overhead: NewTabView has 10 @Environment declarations for its context menu,
/// but the label only needs `modifierKeys` and `windowState`. By extracting the label, changes to
/// other environment values (tabManager, groupManager, etc.) won't trigger label re-evaluation.
private struct NewTabViewLabel: View {
    @Environment(SidebarCellEnvironment.self) private var env

    /// The background style for the new tab button: highlighted while the Command Lens is open.
    private var highlightState: AdaptiveBackgroundStyle {
        env.windowState.showsCommandLens ? .subtle : .clear
    }

    /// Lens icon matching the size and style of tab favicons.
    private var lensIcon: some View {
        Image(systemName: env.modifierKeysState.isOptionPressed ? "folder.badge.plus" : "sparkle.magnifyingglass")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: Constants.Layout.tabFaviconSize, height: Constants.Layout.tabFaviconSize)
    }

    var body: some View {
        HStack(spacing: Constants.Spacing.small) {
            lensIcon

            Text(env.modifierKeysState.isOptionPressed ? "Add Tab Group" : "Command Lens")
                .font(.system(size: Constants.Typography.bodySize))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(height: Constants.Layout.tabItemHeight)
        .contentShape(Rectangle())
        .padding(.horizontal, Constants.Spacing.small2)
        .adaptiveBackground(highlightState, in: RoundedRectangle(cornerRadius: Constants.Layout.tabCornerRadius))
    }
}

// MARK: - NewTabView

/// A button row styled identically to `TabView` for creating new tabs or tab groups.
///
/// This view mirrors the visual appearance of tab rows in the sidebar:
/// - Same height, padding, and corner radius as `TabView`
/// - Plus icon styled consistently with tab favicons
///
/// ## Usage
///
/// Place in the tab list between the divider and normal section:
///
/// ```swift
/// LazyVStack(spacing: Constants.Layout.tabSpacing) {
///     pinnedSection
///     Divider()
///     NewTabView()
///     normalSection
/// }
/// ```
///
/// ## Behavior
///
/// - **Click**: Opens the command lens for URL entry or search.
/// - **Option + Click**: Creates a new tab group.
///
/// The view does not participate in drag-and-drop operations.
struct NewTabView: View {
    @Environment(SidebarCellEnvironment.self) private var env

    // MARK: - Body

    var body: some View {
        Button(action: performAction) {
            NewTabViewLabel()
        }
        .buttonStyle(.plain)
        .onKeyPress(.return) {
            performAction()
            return .handled
        }
        .padding(.horizontal, Constants.Layout.tabHorizontalPadding)
        .refraxContextMenu {
            SidebarContextMenus.buildEmptyAreaMenu(dependencies: env.dependencyContainer)
        }
        .accessibilityIdentifier("command-lens-button")
        .accessibilityLabel(env.modifierKeysState.isOptionPressed ? "Add Tab Group" : "Command Lens")
        .accessibilityHint(
            env.modifierKeysState.isOptionPressed
                ? "Creates a new tab group"
                : "Opens command lens to create a new tab",
        )
    }

    // MARK: - Actions

    private func performAction() {
        if env.modifierKeysState.isOptionPressed {
            _ = try? env.dependencyContainer.groupManager.createGroup(name: "New Group", startEditing: true)
        } else {
            env.windowState.openCommandLens()
        }
    }
}
