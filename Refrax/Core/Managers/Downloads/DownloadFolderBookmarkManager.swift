import Foundation

/// Manages security-scoped bookmarks for custom download folders.
///
/// In a sandboxed app, access to user-selected folders persists only for the
/// current session unless we store a security-scoped bookmark. This manager
/// handles bookmark creation, storage, and resolution.
///
/// ## Usage
///
/// ```swift
/// // When user selects a folder
/// if let bookmark = DownloadFolderBookmarkManager.shared.createBookmark(for: selectedURL) {
///     // Store bookmark - automatically handled by storeBookmark
/// }
///
/// // When accessing the folder later
/// if let url = DownloadFolderBookmarkManager.shared.resolveBookmark(for: path) {
///     _ = url.startAccessingSecurityScopedResource()
///     defer { url.stopAccessingSecurityScopedResource() }
///     // Use the folder
/// }
/// ```
final class DownloadFolderBookmarkManager {
    static let shared = DownloadFolderBookmarkManager()

    private let bookmarksKey = "downloadFolderBookmarks"
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Bookmark Creation

    /// Creates and stores a security-scoped bookmark for a folder URL.
    ///
    /// - Parameter url: The folder URL selected by the user via NSOpenPanel.
    /// - Returns: The bookmark data if successful, nil otherwise.
    @discardableResult
    func createBookmark(for url: URL) -> Data? {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil,
            )
            storeBookmark(bookmark, for: url.path)
            return bookmark
        } catch {
            Logger.error(
                "Failed to create bookmark for \(url.path): \(error)",
                category: Logger.downloads,
            )
            return nil
        }
    }

    /// Stores a bookmark for a path.
    private func storeBookmark(_ data: Data, for path: String) {
        var bookmarks = loadBookmarks()
        bookmarks[path] = data
        defaults.set(bookmarks, forKey: bookmarksKey)
    }

    /// Removes a stored bookmark for a path.
    func removeBookmark(for path: String) {
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)
        defaults.set(bookmarks, forKey: bookmarksKey)
    }

    // MARK: - Bookmark Resolution

    /// Resolves a stored bookmark to a usable URL.
    ///
    /// If the bookmark is stale but the URL is still accessible, a new bookmark
    /// is automatically created.
    ///
    /// - Parameter path: The original path used when creating the bookmark.
    /// - Returns: The resolved URL, or nil if resolution fails.
    func resolveBookmark(for path: String) -> URL? {
        let bookmarks = loadBookmarks()
        guard let data = bookmarks[path] else {
            Logger.warning(
                "No bookmark found for path: \(path)",
                category: Logger.downloads,
            )
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale,
            )

            if isStale {
                Logger.info(
                    "Bookmark is stale, recreating: \(path)",
                    category: Logger.downloads,
                )
                // Re-create bookmark if we still have access
                if let newData = try? url.bookmarkData(options: .withSecurityScope) {
                    storeBookmark(newData, for: path)
                }
            }

            return url
        } catch {
            Logger.error(
                "Failed to resolve bookmark for \(path): \(error)",
                category: Logger.downloads,
            )
            return nil
        }
    }

    // MARK: - Access Control

    /// Starts accessing a security-scoped resource.
    ///
    /// Call this before performing file operations on a bookmarked URL.
    /// Always pair with `stopAccessing(_:)` when done.
    ///
    /// - Parameter url: The URL returned from `resolveBookmark(for:)`.
    /// - Returns: True if access was granted.
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        let success = url.startAccessingSecurityScopedResource()
        if !success {
            Logger.warning(
                "Failed to start accessing security-scoped resource: \(url.path)",
                category: Logger.downloads,
            )
        }
        return success
    }

    /// Stops accessing a security-scoped resource.
    ///
    /// - Parameter url: The URL previously passed to `startAccessing(_:)`.
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: - Validation

    /// Checks if a path has a valid, accessible bookmark.
    ///
    /// - Parameter path: The path to check.
    /// - Returns: True if the path has a bookmark and it resolves successfully.
    func hasValidBookmark(for path: String) -> Bool {
        guard let url = resolveBookmark(for: path) else { return false }
        let success = startAccessing(url)
        if success {
            stopAccessing(url)
        }
        return success
    }

    /// Validates that a URL is writable.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: True if the app can write to this location.
    func isWritable(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    // MARK: - Private

    private func loadBookmarks() -> [String: Data] {
        defaults.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }
}
