import SwiftUI
import UniformTypeIdentifiers

/// Transferable bookmark drag item with multiple representations
///
/// Supports dragging bookmarks both within the app (custom type) and to external apps (URLs/text).
/// Transfer representations are tried in order:
/// 1. Custom bookmark type (internal, preserves all bookmark IDs)
/// 2. URL (for single bookmark - works with browsers, notes apps)
/// 3. Plain text (fallback - URL as text)
struct BookmarkDragItem: Codable, Transferable {
    let bookmarkIDs: [UUID]
    let primaryURL: URL? // For external drag (first bookmark's URL)
    let primaryTitle: String? // For external drag (first bookmark's title)
    
    init(bookmarkIDs: [UUID], primaryURL: URL? = nil, primaryTitle: String? = nil) {
        self.bookmarkIDs = bookmarkIDs
        self.primaryURL = primaryURL
        self.primaryTitle = primaryTitle
    }
    
    static var transferRepresentation: some TransferRepresentation {
        // Priority 1: Custom type for internal drags (preserves all bookmark IDs)
        CodableRepresentation(contentType: .refraxBookmark)
        
        // Priority 2: URL for external drags (single bookmark only)
        // Note: In practice, primaryURL is always provided when creating drag items from bookmarks.
        // The about:blank fallback is a safety measure that should never actually be used.
        ProxyRepresentation<BookmarkDragItem, URL> { (dragItem: BookmarkDragItem) in
            dragItem.primaryURL ?? .blank
        }
        
        // Priority 3: Plain text fallback
        ProxyRepresentation<BookmarkDragItem, String> { (dragItem: BookmarkDragItem) in
            if let url = dragItem.primaryURL {
                if let title = dragItem.primaryTitle {
                    return "\(title)\n\(url.absoluteString)"
                } else {
                    return url.absoluteString
                }
            }
            return "No URL available"
        }
    }
}
