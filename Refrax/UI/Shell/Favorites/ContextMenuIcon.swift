import SwiftUI

// MARK: - Context Menu Icons

/// Symbols for the favorites grid's context menus.
///
/// Using this enum instead of raw `Image(systemName:)` keeps the menus consistent.
enum ContextMenuIcon {
    case info
    case open
    case openInNewTab
    case openInWindow
    case copyURL
    case share
    case convertToLiveTab
    case convertToShortcut
    case removeFromFavorites
    case delete

    var systemName: String {
        switch self {
        case .info: "info.circle"
        case .open: "arrow.right.square"
        case .openInNewTab: "plus"
        case .openInWindow: "macwindow.badge.plus"
        case .copyURL: "link"
        case .share: "square.and.arrow.up"
        case .convertToLiveTab: "livephoto"
        case .convertToShortcut: "arrowshape.turn.up.right"
        case .removeFromFavorites: "star.slash"
        case .delete: "trash"
        }
    }
}
