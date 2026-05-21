import Foundation
import SwiftUI

extension Sidebar {
    /// Manages filter state and application for the sidebar tab list.
    ///
    /// Filters are applied only to the normal (unpinned) section. Pinned tabs
    /// and favorites are always visible regardless of filter criteria.
    ///
    /// ## Filter Types
    ///
    /// - **Text search**: Matches title or URL
    /// - **Quick filters**: Media playback, camera/mic usage, read status, pinned
    /// - **Saved filters**: Persistent filter configurations
    ///
    /// ## WebPage-Based Filters
    ///
    /// Some quick filters (media, camera, microphone) require access to `WebPage`
    /// state. These filters only match tabs with active pages. The manager receives
    /// a page lookup closure from `LayoutManager` during filtering.
    ///
    /// ## Performance
    ///
    /// Text search is debounced to avoid excessive filtering during fast typing.
    /// The signature property provides a cheap cache key for detecting changes.
    ///
    /// ## Observation Optimization
    ///
    /// `hasActiveFilter` is a stored property (not computed) to prevent excessive
    /// view updates. With `@Observable`, computed properties create observation
    /// dependencies on ALL stored properties they read. By making it stored, views
    /// that only care about whether ANY filter is active don't subscribe to every
    /// keystroke in the search field.
    @Observable
    final class FilterManager {
        // MARK: - Filter State

        /// Current search text entered by the user.
        ///
        /// Uses explicit `withMutation` instead of `didSet` because
        /// `@Observable` silently replaces `didSet` accessors.
        @ObservationIgnored
        private var _searchText: String = ""

        var searchText: String {
            get {
                access(keyPath: \.searchText)
                return _searchText
            }
            set {
                withMutation(keyPath: \.searchText) {
                    _searchText = newValue
                }
                scheduleDebounce()
            }
        }

        /// Debounced search text used for actual filtering.
        ///
        /// Updated after a short delay from `searchText` changes to avoid
        /// excessive filtering during fast typing.
        private(set) var debouncedSearchText: String = "" {
            didSet {
                updateHasActiveFilter()
                updateSignature()
            }
        }

        /// Whether to search in tab titles.
        var searchInTitle: Bool = true {
            didSet { updateSignature() }
        }

        /// Whether to search in tab URLs.
        var searchInURL: Bool = true {
            didSet { updateSignature() }
        }

        /// Currently active quick filter.
        ///
        /// Quick filters provide one-click access to common filter conditions.
        /// Setting a quick filter clears any applied saved filter.
        var quickFilter: QuickFilter? {
            didSet {
                updateHasActiveFilter()
                updateSignature()
            }
        }

        /// Currently applied saved filter.
        var appliedSavedFilter: SavedFilter? {
            didSet {
                updateHasActiveFilter()
                updateSignature()
            }
        }

        /// Whether the search toolbar is visible.
        var isToolbarVisible: Bool = false

        /// WebPage lookup closure provided by LayoutManager during filtering.
        ///
        /// Used by page-based filters (media, camera, microphone) to access
        /// WebPage state for each tab.
        @ObservationIgnored
        var pageLookup: ((TabPage) -> WebPage?)?

        /// Task for debouncing search text updates.
        @ObservationIgnored
        private var debounceTask: Task<Void, Never>?

        // MARK: - Observation-Optimized Properties

        /// Whether any filter is currently active.
        ///
        /// This is a stored property (not computed) to prevent observation issues.
        /// Views reading this property only subscribe to changes in this boolean,
        /// not to every change in the underlying filter state.
        private(set) var hasActiveFilter: Bool = false

        /// Cache key for detecting filter changes.
        ///
        /// This is a stored property (not computed) to prevent observation issues.
        /// Views reading this property only subscribe to changes in this value,
        /// not to all five constituent properties that determine it.
        private(set) var signature: Int = 0
        
        // MARK: - Filter Application
        
        /// Apply filters to a list of tab items
        func filterItems(_ items: [TabListItem]) -> [TabListItem] {
            guard hasActiveFilter else { return items }
            
            // Extract all tabs for filtering
            let allTabs = items.compactMap { item -> Tab? in
                if case let .tab(tab) = item { return tab }
                return nil
            }
            
            // Apply filters
            let matchingTabs = filterTabs(allTabs)
            let matchingTabIDs = Set(matchingTabs.map(\.id))
            
            // Build a map of group ID to parent group ID for ancestor lookup
            var groupParentMap: [UUID: UUID] = [:]
            for item in items {
                if let group = item.group, let parentID = group.parentGroupID {
                    groupParentMap[group.id] = parentID
                }
            }

            // Include groups that contain at least one matching tab, plus all ancestors
            var visibleGroupIDs = Set<UUID>()
            for item in items {
                if case let .tab(tab) = item, matchingTabIDs.contains(tab.id) {
                    var currentGroupID = tab.groupID
                    while let groupID = currentGroupID {
                        visibleGroupIDs.insert(groupID)
                        currentGroupID = groupParentMap[groupID]
                    }
                }
            }
            
            // Filter items
            return items.filter { item in
                switch item {
                case let .tab(tab):
                    matchingTabIDs.contains(tab.id)
                case let .group(group):
                    visibleGroupIDs.contains(group.id)
                }
            }
        }
        
        /// Filter tabs based on current criteria.
        func filterTabs(_ tabs: [Tab]) -> [Tab] {
            var filtered = tabs

            // Text search
            if !debouncedSearchText.isEmpty {
                filtered = filtered.filter { tab in
                    let page = tab.activePage
                    return (searchInTitle && page.title.localizedCaseInsensitiveContains(debouncedSearchText))
                        || (searchInURL && page.url.absoluteString.localizedCaseInsensitiveContains(debouncedSearchText))
                }
            }

            // Quick filter
            if let filter = quickFilter {
                filtered = applyQuickFilter(filter, to: filtered)
            }

            // Saved filter (if applied)
            if let savedFilter = appliedSavedFilter {
                if !savedFilter.searchText.isEmpty {
                    filtered = filtered.filter { tab in
                        let page = tab.activePage
                        return (savedFilter.searchInTitle && page.title.localizedCaseInsensitiveContains(savedFilter.searchText))
                            || (savedFilter.searchInURL && page.url.absoluteString.localizedCaseInsensitiveContains(savedFilter.searchText))
                    }
                }

                if let unread = savedFilter.searchUnread {
                    filtered = filtered.filter { $0.isUnread == unread }
                }
            }

            return filtered
        }

        /// Applies a quick filter to the given tabs.
        ///
        /// - Parameters:
        ///   - filter: The quick filter to apply.
        ///   - tabs: The tabs to filter.
        /// - Returns: Tabs matching the filter criteria.
        private func applyQuickFilter(_ filter: QuickFilter, to tabs: [Tab]) -> [Tab] {
            switch filter {
            case .unread:
                tabs.filter(\.isUnread)

            case .read:
                tabs.filter { !$0.isUnread }

            case .audible:
                tabs.filter { tab in
                    tab.pages.contains { page in
                        guard let webPage = pageLookup?(page) else { return false }
                        return webPage.isPlayingAudio || webPage.isAudioMuted
                    }
                }

            case .mediaCapture:
                tabs.filter { tab in
                    tab.pages.contains { page in
                        guard let webPage = pageLookup?(page) else { return false }
                        return webPage.hasActiveMediaCapture || webPage.hasMutedMediaCapture
                    }
                }
            }
        }
        
        // MARK: - Filter Actions

        /// Applies text search filter settings.
        ///
        /// - Parameters:
        ///   - searchText: Text to search for (optional).
        ///   - inTitle: Whether to search in titles.
        ///   - inURL: Whether to search in URLs.
        func applyQuickFilter(searchText: String? = nil, inTitle: Bool = true, inURL: Bool = true) {
            if let text = searchText {
                // Cancel debounce to apply immediately
                debounceTask?.cancel()
                debounceTask = nil
                self.searchText = text
                debouncedSearchText = text
            }
            searchInTitle = inTitle
            searchInURL = inURL
            appliedSavedFilter = nil
        }

        /// Sets the active quick filter.
        ///
        /// - Parameter filter: The quick filter to apply, or `nil` to clear.
        func setQuickFilter(_ filter: QuickFilter?) {
            quickFilter = filter
            appliedSavedFilter = nil
        }

        /// Applies a saved filter.
        ///
        /// - Parameter filter: The saved filter to apply.
        func applySavedFilter(_ filter: SavedFilter) {
            // Cancel debounce to apply immediately
            debounceTask?.cancel()
            debounceTask = nil
            quickFilter = nil
            appliedSavedFilter = filter
            searchText = filter.searchText
            debouncedSearchText = filter.searchText
            searchInTitle = filter.searchInTitle
            searchInURL = filter.searchInURL
        }

        /// Clears all active filters.
        func clearFilters() {
            debounceTask?.cancel()
            debounceTask = nil
            searchText = ""
            debouncedSearchText = ""
            quickFilter = nil
            appliedSavedFilter = nil
            isToolbarVisible = false
        }

        // MARK: - Private Helpers

        /// Schedules a debounced update to `debouncedSearchText`.
        ///
        /// Cancels any pending debounce and schedules a new one. This prevents
        /// excessive filtering during fast typing while still providing responsive
        /// feedback.
        private func scheduleDebounce() {
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                debouncedSearchText = searchText
            }
        }

        /// Updates the `hasActiveFilter` stored property.
        ///
        /// Called from didSet observers on filter properties. Only triggers
        /// observation updates when the boolean actually changes.
        private func updateHasActiveFilter() {
            let newValue = !debouncedSearchText.isEmpty || quickFilter != nil || appliedSavedFilter != nil
            if hasActiveFilter != newValue {
                hasActiveFilter = newValue
            }
        }

        /// Updates the `signature` stored property.
        ///
        /// Called from didSet observers on constituent properties. Only triggers
        /// observation updates when the signature actually changes.
        private func updateSignature() {
            var hasher = Hasher()
            hasher.combine(debouncedSearchText)
            hasher.combine(searchInTitle)
            hasher.combine(searchInURL)
            hasher.combine(quickFilter)
            hasher.combine(appliedSavedFilter?.id)
            let newValue = hasher.finalize()
            if signature != newValue {
                signature = newValue
            }
        }
    }
}
