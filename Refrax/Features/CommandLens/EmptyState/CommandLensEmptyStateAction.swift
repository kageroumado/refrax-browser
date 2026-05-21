import Foundation

/// Direction for triggering an empty state action.
///
/// When CommandLens is open with no input, arrow keys can trigger
/// quick actions instead of navigating suggestions.
enum EmptyStateDirection: Sendable, CaseIterable {
    case up
    case down
    case left
    case right
}

/// Result of executing an empty state action.
///
/// Actions can produce different outcomes depending on their purpose.
enum EmptyStateResult: Sendable {
    /// Display these suggestions in the CommandLens.
    case showSuggestions([CommandLensSuggestion])

    /// Navigate to a URL in the current or new tab.
    case navigate(URL)

    /// Switch to an existing tab.
    case switchToTab(UUID)

    /// Close the CommandLens.
    case dismiss

    /// Do nothing (action was not applicable).
    case none
}

/// Context passed to empty state actions.
///
/// Contains all dependencies needed to execute empty state actions.
struct EmptyStateContext: Sendable {
    let tabManager: TabManager
    let historyManager: HistoryManager
    let windowState: WindowState
    let settings: BrowserSettings
    let undoRedoManager: UndoRedoManager
}

/// A quick action available when CommandLens has no input.
///
/// Empty state actions provide keyboard shortcuts for common operations
/// when the user opens CommandLens but hasn't typed anything yet.
/// Each action is triggered by an arrow key press.
///
/// ## Built-in Actions
///
/// - **Up arrow**: Show recently closed tabs
/// - **Down arrow**: Show currently open tabs
/// - **Left arrow**: Navigate back in current tab (future)
/// - **Right arrow**: Navigate forward in current tab (future)
///
/// ## Example Implementation
///
/// ```swift
/// struct RecentlyClosedAction: CommandLensEmptyStateAction {
///     let direction = EmptyStateDirection.up
///     let icon = "arrow.uturn.backward"
///     let label = "Recently Closed"
///
///     func execute(context: EmptyStateContext) async -> EmptyStateResult {
///         let closed = context.historyManager.recentlyClosed
///         let suggestions = closed.map { /* convert to suggestion */ }
///         return .showSuggestions(suggestions)
///     }
/// }
/// ```
protocol CommandLensEmptyStateAction: Sendable {
    /// The arrow key direction that triggers this action.
    var direction: EmptyStateDirection { get }

    /// SF Symbol name for the action hint icon.
    var icon: String { get }

    /// Short label describing the action.
    var label: String { get }

    /// Whether this action is currently available.
    ///
    /// For example, "Recently Closed" might be unavailable if no tabs
    /// have been closed in the current session.
    ///
    /// - Parameter context: The current context.
    /// - Returns: `true` if the action can be executed.
    func isAvailable(context: EmptyStateContext) -> Bool

    /// Executes the action.
    ///
    /// - Parameter context: The current context with all dependencies.
    /// - Returns: The result of the action.
    func execute(context: EmptyStateContext) async -> EmptyStateResult
}

// MARK: - Default Implementations

extension CommandLensEmptyStateAction {
    /// By default, actions are always available.
    func isAvailable(context _: EmptyStateContext) -> Bool { true }
}
