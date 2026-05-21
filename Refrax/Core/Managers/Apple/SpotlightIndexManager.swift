@preconcurrency import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Manages Core Spotlight indexing for tabs, bookmarks, and history.
///
/// Indexes browser content to make it searchable from system Spotlight.
/// Users can find and open tabs, bookmarks, and frequently visited sites
/// directly from Spotlight search.
///
/// ## Privacy
///
/// - Tabs in private spaces are not indexed
/// - Index entries expire automatically (tabs: 24h, history: 7d)
/// - Users can clear the index via Settings
///
/// ## Domain Identifiers
///
/// - `com.refrax.tabs`: Open tabs
/// - `com.refrax.bookmarks`: Bookmarks
/// - `com.refrax.history`: Frequently visited history

final class SpotlightIndexManager {
    // MARK: - Constants

    private enum Constants {
        static let tabsDomain = "com.refrax.tabs"
        static let bookmarksDomain = "com.refrax.bookmarks"
        static let historyDomain = "com.refrax.history"

        static let tabExpirationInterval: TimeInterval = 86_400 // 24 hours
        static let historyExpirationInterval: TimeInterval = 604_800 // 7 days
        static let historyIndexLimit = 100
    }

    // MARK: - Properties

    private let searchableIndex = CSSearchableIndex.default()
    private var indexedTabIDs: Set<String> = []
    private var isSetupComplete = false

    // MARK: - Dependencies

    private unowned let browserState: BrowserState
    private unowned let bookmarksManager: BookmarksManager
    private unowned let historyManager: HistoryManager

    // MARK: - Initialization

    init(
        browserState: BrowserState,
        bookmarksManager: BookmarksManager,
        historyManager: HistoryManager,
    ) {
        self.browserState = browserState
        self.bookmarksManager = bookmarksManager
        self.historyManager = historyManager
    }

    // MARK: - Setup

    /// Performs initial indexing of bookmarks and frequent history.
    func setup() {
        guard !isSetupComplete else { return }
        isSetupComplete = true

        // Index all bookmarks
        let bookmarks = bookmarksManager.allBookmarks(limit: 1_000)
        if !bookmarks.isEmpty {
            indexBookmarks(bookmarks)
        }

        // Index frequent history
        indexFrequentHistory()

        Logger.info("Spotlight indexing setup complete", category: Logger.data)
    }

    // MARK: - Tab Indexing

    /// Indexes a tab in Spotlight.
    ///
    /// Respects privacy by not indexing tabs in private spaces.
    ///
    /// - Parameter tab: The tab to index.
    func indexTab(_ tab: Tab) {
        // Skip private spaces
        guard let space = tab.space,
              space.dataStoreMode != .private else {
            return
        }

        guard tab.activePage.url.scheme == "http" || tab.activePage.url.scheme == "https" else {
            return
        }

        let identifier = tabIdentifier(for: tab)
        let attributeSet = CSSearchableItemAttributeSet(contentType: .url)

        attributeSet.title = tab.displayTitle
        attributeSet.contentDescription = tab.activePage.url.absoluteString
        attributeSet.url = tab.activePage.url
        attributeSet.domainIdentifier = Constants.tabsDomain

        // Add favicon if available
        if let faviconData = tab.activePage.faviconData {
            attributeSet.thumbnailData = faviconData
        }

        let item = CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: Constants.tabsDomain,
            attributeSet: attributeSet,
        )

        // Tabs expire after 24 hours (ephemeral)
        item.expirationDate = Date().addingTimeInterval(Constants.tabExpirationInterval)

        searchableIndex.indexSearchableItems([item]) { error in
            if let error {
                Logger.error("Failed to index tab in Spotlight: \(error)", category: Logger.data)
            }
        }

        indexedTabIDs.insert(identifier)
    }

    /// Removes a tab from the Spotlight index.
    ///
    /// - Parameter tab: The tab to remove.
    func removeTabFromIndex(_ tab: Tab) {
        let identifier = tabIdentifier(for: tab)
        searchableIndex.deleteSearchableItems(withIdentifiers: [identifier]) { _ in }
        indexedTabIDs.remove(identifier)
    }

    /// Updates the Spotlight index for a tab that changed.
    ///
    /// - Parameter tab: The tab that changed.
    func updateTab(_ tab: Tab) {
        // Re-index to update title/URL
        indexTab(tab)
    }

    private func tabIdentifier(for tab: Tab) -> String {
        "tab-\(tab.id.uuidString)"
    }

    // MARK: - Bookmark Indexing

    /// Indexes bookmarks in Spotlight.
    ///
    /// - Parameter bookmarks: The bookmarks to index.
    func indexBookmarks(_ bookmarks: [Bookmark]) {
        let items = bookmarks.map { bookmark -> CSSearchableItem in
            let url = bookmark.url
            let identifier = "bookmark-\(bookmark.id.uuidString)"
            let attributeSet = CSSearchableItemAttributeSet(contentType: .url)

            attributeSet.title = bookmark.title
            attributeSet.contentDescription = url.absoluteString
            attributeSet.url = url
            attributeSet.domainIdentifier = Constants.bookmarksDomain
            attributeSet.keywords = bookmark.tags

            if let faviconData = bookmark.faviconData {
                attributeSet.thumbnailData = faviconData
            }

            let item = CSSearchableItem(
                uniqueIdentifier: identifier,
                domainIdentifier: Constants.bookmarksDomain,
                attributeSet: attributeSet,
            )

            // Bookmarks don't expire
            item.expirationDate = nil

            return item
        }

        guard !items.isEmpty else { return }

        searchableIndex.indexSearchableItems(items) { error in
            if let error {
                Logger.error("Failed to index bookmarks in Spotlight: \(error)", category: Logger.data)
            } else {
                Logger.debug("Indexed \(items.count) bookmarks in Spotlight", category: Logger.data)
            }
        }
    }

    /// Removes a bookmark from the Spotlight index.
    ///
    /// - Parameter bookmark: The bookmark to remove.
    func removeBookmarkFromIndex(_ bookmark: Bookmark) {
        let identifier = "bookmark-\(bookmark.id.uuidString)"
        searchableIndex.deleteSearchableItems(withIdentifiers: [identifier]) { _ in }
    }

    // MARK: - History Indexing

    /// Indexes frequently visited history entries in Spotlight.
    func indexFrequentHistory() {
        // Get top destinations from the frequency cache
        let topDestinations = historyManager.frequentDestinations.topDestinations(
            limit: Constants.historyIndexLimit,
        )

        let items = topDestinations.map { destination -> CSSearchableItem in
            // Use URL hash for stable identifier
            let identifier = "history-\(destination.url.absoluteString.hashValue)"
            let attributeSet = CSSearchableItemAttributeSet(contentType: .url)

            attributeSet.title = destination.displayTitle
            attributeSet.contentDescription = destination.url.absoluteString
            attributeSet.url = destination.url
            attributeSet.domainIdentifier = Constants.historyDomain

            let item = CSSearchableItem(
                uniqueIdentifier: identifier,
                domainIdentifier: Constants.historyDomain,
                attributeSet: attributeSet,
            )

            // History expires after 7 days
            item.expirationDate = Date().addingTimeInterval(Constants.historyExpirationInterval)

            return item
        }

        guard !items.isEmpty else { return }

        searchableIndex.indexSearchableItems(items) { error in
            if let error {
                Logger.error("Failed to index history in Spotlight: \(error)", category: Logger.data)
            } else {
                Logger.debug("Indexed \(items.count) history entries in Spotlight", category: Logger.data)
            }
        }
    }

    // MARK: - Cleanup

    /// Removes all items indexed by Refrax from Spotlight.
    func removeAllIndexedItems() {
        searchableIndex.deleteAllSearchableItems { error in
            if let error {
                Logger.error("Failed to clear Spotlight index: \(error)", category: Logger.data)
            } else {
                Logger.info("Cleared all Spotlight indexed items", category: Logger.data)
            }
        }
        indexedTabIDs.removeAll()
    }

    /// Removes all tab entries from the index.
    func removeAllTabsFromIndex() {
        searchableIndex.deleteSearchableItems(
            withDomainIdentifiers: [Constants.tabsDomain],
        ) { _ in }
        indexedTabIDs.removeAll()
    }

    /// Removes all bookmark entries from the index.
    func removeAllBookmarksFromIndex() {
        searchableIndex.deleteSearchableItems(
            withDomainIdentifiers: [Constants.bookmarksDomain],
        ) { _ in }
    }

    /// Removes all history entries from the index.
    func removeAllHistoryFromIndex() {
        searchableIndex.deleteSearchableItems(
            withDomainIdentifiers: [Constants.historyDomain],
        ) { _ in }
    }

    // MARK: - Spotlight Result Handling

    /// Extracts the tab ID from a Spotlight continuation activity.
    ///
    /// - Parameter userActivity: The continuation activity from Spotlight.
    /// - Returns: The tab ID if the activity is for a Refrax tab.
    static func extractTabID(from userActivity: NSUserActivity) -> UUID? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("tab-")
        else {
            return nil
        }

        let uuidString = String(identifier.dropFirst(4))
        return UUID(uuidString: uuidString)
    }

    /// Extracts the bookmark ID from a Spotlight continuation activity.
    ///
    /// - Parameter userActivity: The continuation activity from Spotlight.
    /// - Returns: The bookmark ID if the activity is for a Refrax bookmark.
    static func extractBookmarkID(from userActivity: NSUserActivity) -> UUID? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("bookmark-")
        else {
            return nil
        }

        let uuidString = String(identifier.dropFirst(9))
        return UUID(uuidString: uuidString)
    }

    /// Checks if a Spotlight result is a history entry and extracts the URL.
    ///
    /// - Parameter userActivity: The continuation activity from Spotlight.
    /// - Returns: `true` if the activity is for a history entry.
    static func isHistoryEntry(from userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else {
            return false
        }

        return identifier.hasPrefix("history-")
    }
}
