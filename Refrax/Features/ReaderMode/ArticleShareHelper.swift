import AppKit

/// Helper for sharing article content via system share sheet.
///
/// Provides static functions for presenting share sheets with
/// article content in various formats (rich text, markdown, URL).
enum ArticleShareHelper {
    /// Presents the system share sheet for an article.
    ///
    /// Shows the share picker with rich content (attributed string for Notes),
    /// plain text fallback, and source URL.
    ///
    /// - Parameters:
    ///   - article: The article to share.
    ///   - anchorView: The view to anchor the popover to.
    ///   - preferredEdge: The preferred edge for the popover.
    static func showShareSheet(
        for article: ExtractedArticle,
        relativeTo anchorView: NSView,
        preferredEdge: NSRectEdge = .minY,
    ) {
        let service = ReaderExportService(article: article)
        let items = service.createShareItems()

        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: preferredEdge)
    }

    /// Presents the system share sheet at a specific position in a window.
    ///
    /// - Parameters:
    ///   - article: The article to share.
    ///   - position: Position in window coordinates for the popover anchor.
    ///   - window: The window to present in.
    static func showShareSheet(
        for article: ExtractedArticle,
        at position: CGPoint,
        in window: NSWindow,
    ) {
        guard let contentView = window.contentView else { return }

        let service = ReaderExportService(article: article)
        let items = service.createShareItems()

        let picker = NSSharingServicePicker(items: items)
        let rect = NSRect(origin: position, size: CGSize(width: 1, height: 1))
        picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
    }
}
