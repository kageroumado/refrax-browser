import AppKit
import SwiftUI

// MARK: - Context Menu Icons

/// Centralized icon definitions for sidebar context menus.
///
/// Using this enum instead of raw `Image(systemName:)` ensures consistency
/// across all menus and makes it easy to spot mismatches or missing icons.
enum ContextMenuIcon {
    // MARK: - Identity

    case edit
    case rename
    case info
    case changeIcon
    case changeColor

    // MARK: - Status

    case pin
    case unpin
    case favorite
    case markUnread
    case markRead

    // MARK: - Actions

    case reload
    case duplicateTab
    case newTab
    case newGroup
    case newSpace

    // MARK: - Organization

    case addToNewGroup
    case moveToGroup
    case moveToSpace
    case moveToReferencePane
    case moveToSidebar
    case removeFromGroup
    case nestInGroup
    case unnestGroup

    // MARK: - Copy/Share

    case copyURL
    case share

    // MARK: - Windows

    case reflectedWindow
    case openInWindow

    // MARK: - Sort

    case sort

    // MARK: - Selection

    case selectAll
    case clearSelection

    // MARK: - Collapse/Expand

    case collapseAll
    case expandAll
    case removeAllGroups

    // MARK: - Destructive

    case close
    case archive
    case deleteImmediately
    case delete
    case clear

    // MARK: - Favorites

    case convertToLiveTab
    case convertToShortcut
    case removeFromFavorites
    case openInNewTab

    // MARK: - Security

    case lock
    case unlock
    case requireTouchID

    // MARK: - Misc

    case open
    case showTab
    case reopenClosedTab

    var systemName: String {
        switch self {
        // Identity
        case .edit: "slider.horizontal.3"
        case .rename: "pencil"
        case .info: "info.circle"
        case .changeIcon: "photo"
        case .changeColor: "paintpalette"
        // Status
        case .pin: "pin"
        case .unpin: "pin.slash"
        case .favorite: "star"
        case .markUnread: "circlebadge.fill"
        case .markRead: "circlebadge"
        // Actions
        case .reload: "arrow.clockwise"
        case .duplicateTab: "document.on.document"
        case .newTab: "sparkle.magnifyingglass"
        case .newGroup: "folder.badge.plus"
        case .newSpace: "plus.square.on.square"
        // Organization
        case .addToNewGroup: "folder.badge.plus"
        case .moveToGroup: "arrow.forward.folder"
        case .moveToSpace: "square.stack.3d.up"
        case .moveToReferencePane: "arrow.right.to.line.square"
        case .moveToSidebar: "arrow.left.to.line.square"
        case .removeFromGroup: "folder.badge.minus"
        case .nestInGroup: "folder.fill.badge.plus"
        case .unnestGroup: "folder.badge.minus"
        // Copy/Share
        case .copyURL: "link"
        case .share: "square.and.arrow.up"
        // Windows
        case .reflectedWindow: "rectangle.inset.filled.on.rectangle"
        case .openInWindow: "macwindow.badge.plus"
        // Sort
        case .sort: "arrow.up.arrow.down"
        // Selection
        case .selectAll: "checkmark.circle"
        case .clearSelection: "xmark.circle"
        // Collapse/Expand
        case .collapseAll: "chevron.down.square"
        case .expandAll: "chevron.right.square"
        case .removeAllGroups: "folder.badge.minus"
        // Destructive
        case .close: "xmark"
        case .archive: "archivebox"
        case .deleteImmediately: "trash"
        case .delete: "trash"
        case .clear: "trash"
        // Favorites
        case .convertToLiveTab: "livephoto"
        case .convertToShortcut: "arrowshape.turn.up.right"
        case .removeFromFavorites: "star.slash"
        case .openInNewTab: "plus"
        // Security
        case .lock: "lock.fill"
        case .unlock: "lock.open.fill"
        case .requireTouchID: "touchid"
        // Misc
        case .open: "arrow.right.square"
        case .showTab: "eye"
        case .reopenClosedTab: "arrow.uturn.backward"
        }
    }

    var image: Image {
        Image(systemName: systemName)
    }

    /// Creates an NSImage for use in AppKit menus.
    var nsImage: NSImage? {
        NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
    }
}
