import Foundation
import Observation
import SwiftData

/// Manages tab archive operations including archiving, restoring, and expiration.
///
/// TabArchiveManager provides trash-like functionality for tabs. When a tab is closed
/// with archive enabled, it moves to the Archive group where it can be restored or
/// will be automatically deleted after a configurable period.
///
/// ## Archive Behavior
///
/// Archived tabs:
/// - Are moved to a special Archive group (one per space)
/// - Have their WebPage unloaded from memory
/// - Display with a trash icon indicator
/// - Are non-activatable (clicking shows restore prompt)
/// - Expire only after the user has activated the app post-archive
///
/// ## Expiration Logic
///
/// Tabs are only eligible for expiration when:
/// 1. The configured `archiveClearHours` have elapsed since `archivedAt`
/// 2. The app has been activated at least once since the tab was archived
///
/// This prevents tabs from silently disappearing during extended idle periods.
///
/// ## Integration
///
/// - ``ScheduledTasksManager`` calls ``clearExpiredTabs()`` hourly
/// - Tab close operations route through ``archive(_:)`` when archive is enabled
/// - UI shows restore popup via ``restoreTab(_:)``
@Observable
final class TabArchiveManager {
    // MARK: - Dependencies

    private unowned let state: BrowserState
    private unowned let settings: BrowserSettings

    /// WebPage pool for unloading archived tabs.
    unowned var pagePool: WebPagePool!

    /// App activation observer for expiration logic.
    unowned var activationObserver: AppActivationObserver!

    // MARK: - Initialization

    init(state: BrowserState, settings: BrowserSettings) {
        self.state = state
        self.settings = settings
    }

    // MARK: - Archive Operations

    /// Archives a tab, moving it to the Archive group.
    ///
    /// The tab's WebPage is unloaded from memory. The tab can be restored
    /// later via ``restoreTab(_:)`` or will be automatically deleted after
    /// expiration.
    ///
    /// - Parameter tab: The tab to archive.
    /// - Throws: `TabArchiveError.archiveDisabled` if archive feature is off,
    ///   `TabArchiveError.alreadyArchived` if tab is already in archive.
    func archive(_ tab: Tab) throws {
        guard settings.archiveEnabled else {
            throw TabArchiveError.archiveDisabled
        }

        guard !tab.isArchived else {
            throw TabArchiveError.alreadyArchived
        }

        guard let space = tab.space else {
            throw TabArchiveError.noSpace
        }

        // Get or create the archive group for this space
        let archiveGroup = getOrCreateArchiveGroup(in: space)

        // Set archive timestamp
        tab.archivedAt = Date()

        // Move to archive group
        tab.group = archiveGroup
        tab.groupID = archiveGroup.id

        // Position at end of archive
        tab.position = archiveGroup.tabs.count

        // Unload WebPage from memory
        pagePool.removePages(for: tab)

        // Invalidate cache since isArchived changed (count-based auto-invalidation won't trigger)
        space.invalidateTabCaches()

        state.incrementListVersion()

        Logger.debug(
            "Archived tab: \(tab.activePage.title)",
            category: Logger.tabs,
        )
    }

    /// Archives multiple tabs in a batch.
    ///
    /// - Parameter tabs: The tabs to archive.
    /// - Returns: Number of successfully archived tabs.
    @discardableResult
    func archiveBatch(_ tabs: [Tab]) -> Int {
        var count = 0
        for tab in tabs {
            do {
                try archive(tab)
                count += 1
            } catch {
                // Skip tabs that can't be archived
                Logger.debug(
                    "Failed to archive tab: \(error)",
                    category: Logger.tabs,
                )
            }
        }
        return count
    }

    /// Restores an archived tab to the space root.
    ///
    /// The tab is moved out of the Archive group and prepended to the space's
    /// tab list (like a new tab). Its WebPage will be lazily loaded when activated.
    ///
    /// - Parameter tab: The archived tab to restore.
    /// - Throws: `TabArchiveError.notArchived` if tab is not in archive.
    func restoreTab(_ tab: Tab) throws {
        guard tab.isArchived else {
            throw TabArchiveError.notArchived
        }

        guard let space = tab.space else {
            throw TabArchiveError.noSpace
        }

        // Clear archive timestamp
        tab.archivedAt = nil

        // Remove from archive group
        tab.group = nil
        tab.groupID = nil

        // Prepend to space root (position 0 for regular tabs)
        let regularTabs = space.tabs.filter { !$0.isPinned && !$0.isArchived }
        for existingTab in regularTabs {
            existingTab.position += 1
        }
        tab.position = 0

        // Invalidate cache since isArchived changed (count-based auto-invalidation won't trigger)
        space.invalidateTabCaches()

        state.incrementListVersion()

        Logger.debug(
            "Restored tab: \(tab.activePage.title)",
            category: Logger.tabs,
        )
    }

    /// Restores all tabs dragged out of the archive group.
    ///
    /// Called when tabs are dragged from archive to another location.
    /// - Parameter tabs: The tabs being dragged out.
    func restoreTabs(_ tabs: [Tab]) {
        for tab in tabs where tab.isArchived {
            try? restoreTab(tab)
        }
    }

    /// Permanently deletes an archived tab.
    ///
    /// - Parameter tab: The archived tab to delete.
    /// - Parameter context: The ModelContext for deletion.
    func deleteArchivedTab(_ tab: Tab, in context: ModelContext) {
        guard tab.isArchived else { return }

        // Remove from model context
        context.delete(tab)

        state.incrementListVersion()

        Logger.debug(
            "Permanently deleted archived tab: \(tab.activePage.title)",
            category: Logger.tabs,
        )
    }

    /// Clears all archived tabs in a space.
    ///
    /// - Parameter space: The space to clear archive for.
    /// - Parameter context: The ModelContext for deletion.
    func clearArchive(in space: Space, context: ModelContext) {
        let archivedTabs = space.tabs.filter(\.isArchived)

        for tab in archivedTabs {
            context.delete(tab)
        }

        // Delete the archive group itself
        if let archiveGroup = findArchiveGroup(in: space) {
            context.delete(archiveGroup)
        }

        state.incrementListVersion()

        Logger.debug(
            "Cleared archive in space: \(space.name)",
            category: Logger.tabs,
        )
    }

    /// Clears all archives across all spaces.
    ///
    /// Called when archive feature is disabled in settings.
    ///
    /// - Parameter context: The ModelContext for deletion.
    func clearAllArchives(context: ModelContext) {
        for space in state.spaces {
            clearArchive(in: space, context: context)
        }
    }

    // MARK: - Expiration

    /// Clears expired archived tabs based on settings.
    ///
    /// Called by ScheduledTasksManager on the hourly schedule.
    /// Tabs are only expired if:
    /// 1. `archiveClearHours` time has passed since archiving
    /// 2. The app has been activated at least once since archiving
    ///
    /// - Parameter context: The ModelContext for deletion.
    func clearExpiredTabs(context: ModelContext) {
        guard settings.archiveEnabled else { return }
        guard let clearHours = settings.archiveClearHours else { return }

        let lastActivation = activationObserver.lastActivationTime
        let expirationInterval = TimeInterval(clearHours) * 3_600

        var expiredCount = 0

        for space in state.spaces {
            let archivedTabs = space.tabs.filter(\.isArchived)

            for tab in archivedTabs {
                guard let archivedAt = tab.archivedAt else { continue }

                // Check if enough time has passed
                let elapsed = Date().timeIntervalSince(archivedAt)
                guard elapsed >= expirationInterval else { continue }

                // Check if app was activated after this tab was archived
                if let lastActivation, lastActivation > archivedAt {
                    context.delete(tab)
                    expiredCount += 1
                }
            }
        }

        if expiredCount > 0 {
            state.incrementListVersion()
            Logger.debug(
                "Cleared \(expiredCount) expired archived tabs",
                category: Logger.tabs,
            )
        }
    }

    // MARK: - Archive Group Management

    /// Gets or creates the Archive group for a space.
    ///
    /// Each space has at most one Archive group, positioned at the bottom
    /// of the tab list.
    ///
    /// - Parameter space: The space to get archive group for.
    /// - Returns: The existing or newly created Archive group.
    func getOrCreateArchiveGroup(in space: Space) -> TabGroup {
        if let existing = findArchiveGroup(in: space) {
            return existing
        }

        // Create new archive group at the end
        let maxPosition = space.groups.map(\.position).max() ?? -1

        let archiveGroup = TabGroup(
            space: space,
            name: String(localized: "Archive"),
            color: "#8E8E93", // System gray
            iconName: "trash",
            position: maxPosition + 1,
            isArchive: true,
        )

        // Insert into space
        space.groups.append(archiveGroup)

        return archiveGroup
    }

    /// Finds the existing Archive group in a space, if any.
    ///
    /// - Parameter space: The space to search.
    /// - Returns: The Archive group, or nil if none exists.
    func findArchiveGroup(in space: Space) -> TabGroup? {
        space.groups.first(where: \.isArchive)
    }

    /// Returns the count of archived tabs in a space.
    ///
    /// - Parameter space: The space to count archived tabs in.
    /// - Returns: Number of archived tabs.
    func archivedTabCount(in space: Space) -> Int {
        space.tabs.count(where: \.isArchived)
    }

    // MARK: - Drag Operations

    /// Archives tabs dropped into the archive group via drag.
    ///
    /// - Parameter tabs: Tabs dragged into archive.
    func archiveDroppedTabs(_ tabs: [Tab]) {
        archiveBatch(tabs)
    }

    /// Restores tabs dropped out of the archive group via drag.
    ///
    /// - Parameter tabs: Tabs dragged out of archive.
    func restoreDroppedTabs(_ tabs: [Tab]) {
        restoreTabs(tabs)
    }
}

// MARK: - Errors

/// Errors that can occur during archive operations.
enum TabArchiveError: Error, LocalizedError {
    case archiveDisabled
    case alreadyArchived
    case notArchived
    case noSpace

    var errorDescription: String? {
        switch self {
        case .archiveDisabled:
            String(localized: "Archive feature is disabled")
        case .alreadyArchived:
            String(localized: "Tab is already in the archive")
        case .notArchived:
            String(localized: "Tab is not in the archive")
        case .noSpace:
            String(localized: "Tab has no associated space")
        }
    }
}
