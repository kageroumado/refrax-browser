import AppKit
import Foundation

/// Custom pasteboard types for Refrax drag operations.
///
/// These types enable:
/// 1. Re-entry detection when dragging back into sidebar
/// 2. Internal identification of dragged items
enum DragPasteboardType {
    /// Identifies a dragged tab for re-entry detection.
    ///
    /// Contains the tab's UUID as UTF-8 string.
    static let refraxTabID = NSPasteboard.PasteboardType("com.refrax.tab-id")

    /// Identifies a dragged favorite for re-entry detection.
    ///
    /// Contains the favorite's UUID as UTF-8 string.
    static let refraxFavoriteID = NSPasteboard.PasteboardType("com.refrax.favorite-id")
}

/// Provides pasteboard data lazily for drag operations.
///
/// When an AppKit drag session starts, this class provides data on-demand
/// for various pasteboard types. Data is generated lazily when the receiving
/// app requests a specific type.
///
/// ## Supported Types (in priority order)
///
/// 1. **Internal Refrax types** - For re-entry identification
/// 2. **URL type** - For browsers and URL-aware apps
/// 3. **String type** - Plain text fallback with title and URL
///
/// File promises (.webloc) are handled separately by ``WeblocFilePromiseProvider``.
///
/// ## Usage
///
/// ```swift
/// let writer = DragPasteboardWriter(items: coordinator.draggedItems)
/// let pasteboardItem = writer.createPasteboardItem()
/// // Use pasteboardItem in NSDraggingItem
/// ```
///
/// ## SwiftData Safety
///
/// This class captures all necessary data at initialization time rather than
/// holding references to SwiftData model objects. This prevents crashes when
/// the pasteboard requests data after a `ModelContext.reset()` has destroyed
/// the original models.
final class DragPasteboardWriter: NSObject, NSPasteboardItemDataProvider {
    /// Snapshot of data needed from a dragged item.
    private struct ItemSnapshot {
        enum Kind {
            case tab
            case favorite
            case group
        }

        let kind: Kind
        let id: UUID
        let url: URL?
        let title: String
    }

    /// Captured snapshots of dragged items (safe from SwiftData lifecycle).
    private let snapshots: [ItemSnapshot]

    /// Pasteboard types this writer supports.
    ///
    /// Types are listed in priority order - receiving apps check their
    /// registered types against this list and use the first match.
    let supportedTypes: [NSPasteboard.PasteboardType]

    init(items: [Sidebar.DragCoordinator.DraggedItem]) {
        // Capture all data eagerly to avoid accessing SwiftData models later
        var snapshots: [ItemSnapshot] = []
        var types: [NSPasteboard.PasteboardType] = []
        var hasURLs = false

        for item in items {
            switch item {
            case let .tab(tab):
                let url = tab.activePage.url
                let nonBlankURL = url == .blank ? nil : url
                snapshots.append(ItemSnapshot(
                    kind: .tab,
                    id: tab.id,
                    url: nonBlankURL,
                    title: tab.displayTitle,
                ))
                if !types.contains(DragPasteboardType.refraxTabID) {
                    types.append(DragPasteboardType.refraxTabID)
                }
                if nonBlankURL != nil {
                    hasURLs = true
                }

            case let .favorite(favorite):
                switch favorite.type {
                case .liveFavorite, .shortcut:
                    // Standard favorites: single URL
                    snapshots.append(ItemSnapshot(
                        kind: .favorite,
                        id: favorite.id,
                        url: favorite.url,
                        title: favorite.displayName,
                    ))
                    if favorite.url != nil {
                        hasURLs = true
                    }

                case let .folder(folder):
                    // Folders expand to multiple bookmarks (like tab groups)
                    for bookmark in folder.bookmarks {
                        snapshots.append(ItemSnapshot(
                            kind: .favorite,
                            id: bookmark.id,
                            url: bookmark.url,
                            title: bookmark.title,
                        ))
                        hasURLs = true
                    }

                case .appShortcut:
                    // App shortcuts are internal-only, skip for external handoff
                    break
                }

                if !types.contains(DragPasteboardType.refraxFavoriteID) {
                    types.append(DragPasteboardType.refraxFavoriteID)
                }

            case let .group(group):
                // Groups expand to their tabs' URLs (like folders expand to bookmarks)
                for tab in group.tabs {
                    let url = tab.activePage.url
                    let nonBlankURL = url == .blank ? nil : url
                    snapshots.append(ItemSnapshot(
                        kind: .tab,
                        id: tab.id,
                        url: nonBlankURL,
                        title: tab.displayTitle,
                    ))
                    if nonBlankURL != nil {
                        hasURLs = true
                    }
                }
            }
        }

        // Public types for external apps
        if hasURLs {
            types.append(.URL)
        }
        types.append(.string)

        self.snapshots = snapshots
        self.supportedTypes = types
        super.init()
    }

    /// Create a pasteboard item configured with this writer as data provider.
    ///
    /// - Returns: Configured pasteboard item ready for use in NSDraggingItem
    func createPasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setDataProvider(self, forTypes: supportedTypes)
        return item
    }

    // MARK: - NSPasteboardItemDataProvider

    func pasteboard(
        _: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType,
    ) {
        switch type {
        case DragPasteboardType.refraxTabID:
            // Provide tab IDs as newline-separated UUIDs
            let tabIDs = snapshots.filter { $0.kind == .tab }.map(\.id.uuidString)
            if let data = tabIDs.joined(separator: "\n").data(using: .utf8) {
                item.setData(data, forType: type)
            }

        case DragPasteboardType.refraxFavoriteID:
            // Provide favorite IDs as newline-separated UUIDs
            let favoriteIDs = snapshots.filter { $0.kind == .favorite }.map(\.id.uuidString)
            if let data = favoriteIDs.joined(separator: "\n").data(using: .utf8) {
                item.setData(data, forType: type)
            }

        case .URL:
            // Provide first URL (standard URL pasteboard behavior)
            if let url = snapshots.lazy.compactMap(\.url).first,
               let data = url.absoluteString.data(using: .utf8) {
                item.setData(data, forType: type)
            }

        case .string:
            // Provide title + URL for each item, newline separated
            let strings = snapshots.compactMap { snapshot -> String? in
                guard snapshot.kind != .group, let url = snapshot.url else { return nil }
                let title = snapshot.title.isEmpty ? url.host ?? url.absoluteString : snapshot.title
                return "\(title)\n\(url.absoluteString)"
            }
            if let data = strings.joined(separator: "\n\n").data(using: .utf8) {
                item.setData(data, forType: type)
            }

        default:
            break
        }
    }
}

// MARK: - Pasteboard Reading Helpers

extension DragPasteboardWriter {
    /// Check if a pasteboard contains Refrax internal drag data.
    ///
    /// Use this in `draggingEntered` to detect re-entry from an AppKit drag.
    ///
    /// - Parameter pasteboard: Pasteboard to check
    /// - Returns: True if pasteboard contains Refrax tab or favorite IDs
    static func containsRefraxDragData(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(DragPasteboardType.refraxTabID)
            || types.contains(DragPasteboardType.refraxFavoriteID)
    }

    /// Extract tab IDs from a pasteboard.
    ///
    /// - Parameter pasteboard: Pasteboard containing Refrax drag data
    /// - Returns: Array of tab UUIDs, empty if none found
    static func extractTabIDs(from pasteboard: NSPasteboard) -> [UUID] {
        guard let data = pasteboard.data(forType: DragPasteboardType.refraxTabID),
              let string = String(data: data, encoding: .utf8) else {
            return []
        }
        return string.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
    }

    /// Extract favorite IDs from a pasteboard.
    ///
    /// - Parameter pasteboard: Pasteboard containing Refrax drag data
    /// - Returns: Array of favorite UUIDs, empty if none found
    static func extractFavoriteIDs(from pasteboard: NSPasteboard) -> [UUID] {
        guard let data = pasteboard.data(forType: DragPasteboardType.refraxFavoriteID),
              let string = String(data: data, encoding: .utf8) else {
            return []
        }
        return string.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
    }
}
