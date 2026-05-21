import AppKit

/// Provides macOS Services menu integration.
///
/// Exposes Refrax functionality to other apps through the Services menu:
/// - Search With Refrax: Search selected text using the default search engine
/// - Open URL in Refrax: Open selected URLs in a new tab
/// - Download with Refrax: Download files from selected URLs
/// - Add to Refrax Bookmarks: Bookmark selected URLs
///
/// Services are declared in Info.plist and handler methods are registered
/// via `NSApp.registerServicesMenuSendTypes`.
final class ServicesProvider: NSObject {
    private let tabManager: TabManager
    private let bookmarksManager: BookmarksManager
    private let downloadManager: DownloadManager
    private let windowManager: WindowManager
    private let settings: BrowserSettings

    init(
        tabManager: TabManager,
        bookmarksManager: BookmarksManager,
        downloadManager: DownloadManager,
        windowManager: WindowManager,
        settings: BrowserSettings,
    ) {
        self.tabManager = tabManager
        self.bookmarksManager = bookmarksManager
        self.downloadManager = downloadManager
        self.windowManager = windowManager
        self.settings = settings
        super.init()
    }

    /// Registers this provider as the services handler.
    func register() {
        NSApp.servicesProvider = self
        NSApp.registerServicesMenuSendTypes(
            [.string, .URL],
            returnTypes: [],
        )
    }

    // MARK: - Service Handlers

    /// Searches selected text using the default search engine.
    ///
    /// Triggered by "Search With Refrax" in the Services menu.
    @objc
    func searchWithWebSearchProvider(
        _ pboard: NSPasteboard,
        userData _: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>,
    ) {
        guard let text = extractText(from: pboard) else {
            errorPointer.pointee = "No text selected" as NSString
            return
        }

        guard let searchURL = settings.defaultSearchEngine.searchURL(for: text) else {
            errorPointer.pointee = "Could not create search URL" as NSString
            return
        }
        openURLInNewTab(searchURL)
    }

    /// Opens selected URLs in Refrax.
    ///
    /// Triggered by "Open URL in Refrax" in the Services menu.
    @objc
    func openURLFromService(
        _ pboard: NSPasteboard,
        userData _: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>,
    ) {
        guard let url = extractURL(from: pboard) else {
            errorPointer.pointee = "No valid URL selected" as NSString
            return
        }

        openURLInNewTab(url)
    }

    /// Downloads files from selected URLs.
    ///
    /// Triggered by "Download with Refrax" in the Services menu.
    @objc
    func downloadWithRefrax(
        _ pboard: NSPasteboard,
        userData _: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>,
    ) {
        guard let url = extractURL(from: pboard) else {
            errorPointer.pointee = "No valid URL selected" as NSString
            return
        }

        startDownloadAsync(url: url)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Adds selected URLs to bookmarks.
    ///
    /// Triggered by "Add to Refrax Bookmarks" in the Services menu.
    @objc
    func addToBookmarks(
        _ pboard: NSPasteboard,
        userData _: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>,
    ) {
        guard let url = extractURL(from: pboard) else {
            errorPointer.pointee = "No valid URL selected" as NSString
            return
        }

        // Extract title from URL if available
        let title = url.host ?? url.absoluteString
        bookmarksManager.createBookmark(url: url, title: title)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private Helpers

    private func extractText(from pboard: NSPasteboard) -> String? {
        pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractURL(from pboard: NSPasteboard) -> URL? {
        // Try URL type first
        if let urlString = pboard.string(forType: .URL),
           let url = URL(string: urlString) {
            return url
        }

        // Fall back to string type
        if let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: text),
           url.scheme != nil {
            return url
        }

        return nil
    }

    private func openURLInNewTab(_ url: URL) {
        windowManager.openURL(url)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startDownloadAsync(url: URL) {
        Task { @MainActor in
            _ = try? await downloadManager.startDownload(from: url)
        }
    }
}
