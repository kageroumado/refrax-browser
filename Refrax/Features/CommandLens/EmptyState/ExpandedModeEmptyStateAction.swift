import Foundation

/// Enters expanded mode when right arrow is pressed with empty input.
///
/// Expanded mode shows a row of quick-access buttons (History, Bookmarks,
/// Downloads, Settings) that can be navigated with arrow keys and activated
/// with Enter.
///
/// Unlike other empty state actions that return suggestions, this action
/// triggers a UI mode change in the CommandLensManager.
struct ExpandedModeEmptyStateAction: CommandLensEmptyStateAction {
    let direction = EmptyStateDirection.right
    let icon = "rectangle.3.group"
    let label = "Quick Actions"

    func isAvailable(context _: EmptyStateContext) -> Bool {
        // Always available when input is empty
        true
    }

    func execute(context _: EmptyStateContext) async -> EmptyStateResult {
        // This action is handled specially by CommandLensManager
        // to enter expanded mode rather than showing suggestions.
        // Return .none to signal the manager should handle it directly.
        .none
    }
}

// MARK: - Expanded Mode Data Types

/// A button displayed in expanded mode.
struct ExpandedModeButton: Identifiable, Equatable, Sendable {
    let id: String
    let icon: String
    let label: String
    let action: ExpandedModeAction

    static func == (lhs: ExpandedModeButton, rhs: ExpandedModeButton) -> Bool {
        lhs.id == rhs.id
    }
}

/// Action to perform when an expanded mode button is activated.
enum ExpandedModeAction: Equatable, Sendable {
    /// Opens the detail tray in a specific mode.
    case openDetailTray(DetailTrayMode)

    /// Opens the settings window.
    case openSettingsWindow
}

// MARK: - Button Definitions

extension ExpandedModeButton {
    /// All buttons shown in expanded mode, in display order.
    static let allButtons: [ExpandedModeButton] = [
        ExpandedModeButton(
            id: "history",
            icon: "clock.arrow.circlepath",
            label: "History",
            action: .openDetailTray(.history),
        ),
        ExpandedModeButton(
            id: "bookmarks",
            icon: "bookmark",
            label: "Bookmarks",
            action: .openDetailTray(.bookmarks),
        ),
        ExpandedModeButton(
            id: "downloads",
            icon: "arrow.down.circle",
            label: "Downloads",
            action: .openDetailTray(.downloads),
        ),
        ExpandedModeButton(
            id: "settings",
            icon: "gear",
            label: "Settings",
            action: .openSettingsWindow,
        ),
    ]
}
