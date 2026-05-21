/// Tracks the user's current selection in the CommandLens suggestion list.
///
/// Selection has two components:
/// 1. **Index**: Which suggestion row is highlighted (-1 means none)
/// 2. **Button**: Which action button on that row is focused (for keyboard navigation)
///
/// ## Keyboard Navigation
///
/// - Up/Down arrows change `index`
/// - Tab cycles through `buttonSelection` options on the current row
/// - Enter/Return activates the current selection
///
/// ```swift
/// // Move to next suggestion
/// selection.index += 1
///
/// // Focus the remove button
/// selection.buttonSelection = .remove
/// ```
struct CommandLensSelection: Equatable, Sendable {
    /// Index of the selected suggestion row, or -1 if none selected.
    var index: Int

    /// Which action button is focused on the selected row.
    var buttonSelection: ButtonSelection = .none

    /// Action buttons that can be focused within a suggestion row.
    enum ButtonSelection: Sendable {
        /// No button focused; Enter activates the suggestion's default action.
        case none

        /// Keyword insertion button focused.
        case keyword

        /// Remove/delete button focused.
        case remove

        /// Search provider switch button focused.
        case switchProvider
    }

    /// Sentinel value indicating no selection.
    static let none = CommandLensSelection(index: -1)
}
