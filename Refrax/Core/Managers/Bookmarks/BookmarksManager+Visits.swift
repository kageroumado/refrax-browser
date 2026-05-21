import Foundation
import SwiftData

// MARK: - Visit Tracking

extension BookmarksManager {
    /// Record a visit to a bookmark.
    ///
    /// Increments visit count and updates last visited date. Call this when user opens
    /// a bookmark. Also triggers favicon loading if the bookmark doesn't have one.
    ///
    /// - Parameter bookmark: Bookmark that was visited
    func recordVisit(for bookmark: Bookmark) {
        bookmark.recordVisit()

        // Attempt to load favicon if missing (fire-and-forget)
        if bookmark.faviconData == nil {
            let bookmarkID = bookmark.id
            let url = bookmark.url
            Task.detached(priority: .utility) { [weak self] in
                await self?.loadFavicon(forID: bookmarkID, url: url)
            }
        }

        scheduleSave()
    }

    /// Synchronize visit counts from history manager.
    ///
    /// Queries history for each bookmark's URL and updates visit count and last visited date.
    /// Should be called periodically (e.g., on app launch, every hour).
    ///
    /// Uses paginated fetching to avoid memory spikes with large bookmark collections.
    func syncVisitCounts() async {
        var offset = 0
        let batchSize = 500
        var totalSynced = 0

        while true {
            var descriptor = FetchDescriptor<Bookmark>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset

            guard let bookmarks = try? _modelContext.fetch(descriptor), !bookmarks.isEmpty else {
                break
            }

            for bookmark in bookmarks {
                let domain = bookmark.domain
                let entries = await historyManager.entries(forDomain: domain)

                // Count visits for exact URL match (each entry is one visit)
                let matchingEntries = entries.filter { $0.url == bookmark.url }
                let visitCount = matchingEntries.count
                let lastVisit = matchingEntries.max(by: { $0.visitedAt < $1.visitedAt })?.visitedAt

                if bookmark.visitCount != visitCount || bookmark.lastVisited != lastVisit {
                    bookmark.visitCount = visitCount
                    bookmark.lastVisited = lastVisit
                }
            }

            totalSynced += bookmarks.count
            offset += bookmarks.count

            if bookmarks.count < batchSize { break }
        }

        try? _modelContext.save()

        Logger.info("Synced visit counts for \(totalSynced) bookmarks", category: Logger.data)
    }
}
