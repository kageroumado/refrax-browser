import SwiftUI

/// A SwiftUI wrapper that displays a `_WKThumbnailView` for a tab.
///
/// `WebViewThumbnail` retrieves the thumbnail from `TabPreviewProvider` via
/// the environment. If no cached thumbnail exists, it creates one synchronously.
/// If the tab has no loaded WebPage, a placeholder view is shown.
///
/// ## Usage
///
/// ```swift
/// // For tab switcher (uses cache for MRU tabs)
/// WebViewThumbnail(tabID: tab.id)
///     .frame(width: 280, height: 175)
///
/// // For hover preview (doesn't pollute cache)
/// WebViewThumbnail(tabID: tab.id, useCache: false)
/// ```
struct WebViewThumbnail: NSViewRepresentable {
    @Environment(TabPreviewProvider.self) private var previewProvider

    let tabID: Tab.ID

    /// Whether to use/update the MRU cache. Defaults to `true`.
    /// Pass `false` for one-off previews like hover that shouldn't evict MRU entries.
    var useCache: Bool = true

    func makeNSView(context _: Context) -> ThumbnailAdapter {
        previewProvider.thumbnailView(for: tabID, useCache: useCache)
    }

    func updateNSView(_: ThumbnailAdapter, context _: Context) {
        // Thumbnail views are managed by the provider, no update needed
    }
}
