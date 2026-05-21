import Foundation
import Observation

/// Manages multi-bookmark selection state for batch operations.
///
/// Supports macOS-standard selection behavior:
/// - **Command+Click**: Toggle individual bookmark selection
/// - **Shift+Click**: Range selection from anchor to clicked bookmark
/// - **Regular Click**: Clear selection (caller handles primary action)
///
/// ## Usage
///
/// ```swift
/// @State private var selectionManager = BookmarkSelectionManager()
///
/// // In view:
/// BookmarkGridCard(bookmark: bookmark) {
///     if selectionManager.handleClick(
///         on: bookmark.id,
///         in: sortedBookmarks.map(\.id),
///         commandDown: NSEvent.modifierFlags.contains(.command),
///         shiftDown: NSEvent.modifierFlags.contains(.shift)
///     ) {
///         openBookmark(bookmark)
///     }
/// }
/// ```
///
/// ## Selection Anchor
///
/// The anchor is the starting point for Shift+Click range selection.
/// It's set when:
/// - User Command+Clicks a bookmark (that bookmark becomes anchor)
/// - User makes a regular click (that bookmark becomes anchor)
@Observable
final class BookmarkSelectionManager {
    // MARK: - Selection State

    /// Set of currently selected bookmark IDs.
    ///
    /// This is public to allow binding for SwiftUI Table selection.
    var selectedIDs: Set<Bookmark.ID> = []

    /// Anchor bookmark ID for Shift+Click range selection.
    ///
    /// When user Shift+Clicks, all bookmarks between anchor and clicked bookmark
    /// are selected.
    private var anchorID: Bookmark.ID?

    // MARK: - Computed Properties

    /// Whether any bookmarks are currently selected.
    var hasSelection: Bool {
        !selectedIDs.isEmpty
    }

    /// Number of selected bookmarks.
    var selectionCount: Int {
        selectedIDs.count
    }

    // MARK: - Selection Queries

    /// Whether a specific bookmark is in the selection set.
    ///
    /// - Parameter bookmarkID: The bookmark ID to check.
    /// - Returns: True if the bookmark is selected.
    func isSelected(_ bookmarkID: Bookmark.ID) -> Bool {
        selectedIDs.contains(bookmarkID)
    }

    // MARK: - Selection Actions

    /// Handles a click on a bookmark with modifier keys.
    ///
    /// - Parameters:
    ///   - bookmarkID: The clicked bookmark's ID.
    ///   - orderedIDs: All bookmark IDs in display order (for range selection).
    ///   - commandDown: Whether Command key is held.
    ///   - shiftDown: Whether Shift key is held.
    /// - Returns: Whether the caller should perform the primary action (e.g., open bookmark).
    func handleClick(
        on bookmarkID: Bookmark.ID,
        in orderedIDs: [Bookmark.ID],
        commandDown: Bool,
        shiftDown: Bool,
    ) -> Bool {
        if commandDown {
            handleCommandClick(on: bookmarkID)
            return false
        } else if shiftDown {
            handleShiftClick(on: bookmarkID, in: orderedIDs)
            return false
        } else {
            handleRegularClick(on: bookmarkID)
            return true
        }
    }

    /// Toggles selection for a single bookmark (Command+Click).
    ///
    /// - Parameter bookmarkID: The bookmark to toggle.
    private func handleCommandClick(on bookmarkID: Bookmark.ID) {
        if selectedIDs.contains(bookmarkID) {
            selectedIDs.remove(bookmarkID)
            // If we deselected the anchor, update it
            if anchorID == bookmarkID {
                anchorID = selectedIDs.first
            }
        } else {
            selectedIDs.insert(bookmarkID)
            anchorID = bookmarkID
        }
    }

    /// Selects a range of bookmarks from anchor to clicked bookmark (Shift+Click).
    ///
    /// - Parameters:
    ///   - bookmarkID: The end of the range.
    ///   - orderedIDs: All bookmark IDs in display order.
    private func handleShiftClick(on bookmarkID: Bookmark.ID, in orderedIDs: [Bookmark.ID]) {
        // Determine anchor: use explicit anchor or clicked bookmark
        let effectiveAnchor = anchorID ?? bookmarkID

        guard let anchorIndex = orderedIDs.firstIndex(of: effectiveAnchor),
              let clickIndex = orderedIDs.firstIndex(of: bookmarkID) else {
            // Fallback: just select the clicked bookmark
            selectedIDs.insert(bookmarkID)
            anchorID = bookmarkID
            return
        }

        // Select all bookmarks in range
        let range = min(anchorIndex, clickIndex) ... max(anchorIndex, clickIndex)
        for index in range {
            selectedIDs.insert(orderedIDs[index])
        }

        // Keep the original anchor (don't change it on shift-click)
        if anchorID == nil {
            anchorID = effectiveAnchor
        }
    }

    /// Clears selection on regular click and updates anchor.
    ///
    /// - Parameter bookmarkID: The clicked bookmark (becomes new anchor).
    private func handleRegularClick(on bookmarkID: Bookmark.ID) {
        clearSelection()
        anchorID = bookmarkID
    }

    /// Clears all selected bookmarks.
    func clearSelection() {
        selectedIDs.removeAll()
        anchorID = nil
    }

    /// Removes a bookmark from selection if present.
    ///
    /// Used when a bookmark is deleted.
    ///
    /// - Parameter bookmarkID: The ID of the bookmark to remove.
    func removeFromSelection(_ bookmarkID: Bookmark.ID) {
        selectedIDs.remove(bookmarkID)
        if anchorID == bookmarkID {
            anchorID = selectedIDs.first
        }
    }

    /// Selects all bookmarks from the provided ordered list.
    ///
    /// - Parameter orderedIDs: All bookmark IDs in display order.
    func selectAll(from orderedIDs: [Bookmark.ID]) {
        selectedIDs = Set(orderedIDs)
        anchorID = orderedIDs.first
    }

    /// Inverts the current selection.
    ///
    /// - Parameter orderedIDs: All bookmark IDs in display order.
    func invertSelection(from orderedIDs: [Bookmark.ID]) {
        let allIDs = Set(orderedIDs)
        selectedIDs = allIDs.subtracting(selectedIDs)
    }
}
