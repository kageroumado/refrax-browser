import Combine
import Foundation
import SwiftUI

/// Observable state manager for tab filtering with debounced search and saved filter management.
///
/// This class coordinates all filtering logic, including:
/// - Real-time text search with debouncing
/// - Quick filters (by title, by URL)
/// - Saved filter management
/// - Computed filtered tab list
///
/// ## Performance
/// - Uses 300ms debounce to avoid excessive filtering during typing
/// - Filters computed on-demand via property observers
/// - Case and accent-insensitive matching using `localizedStandardContains`
///
/// ## Usage
/// ```swift
/// let filterState = TabFilterState()
/// filterState.applyQuickFilter(searchText: "github", inTitle: true, inURL: false)
/// ```
@Observable
final class TabFilterState {
    // MARK: - Properties
    
    /// Current search text (may be actively typing, pre-debounce)
    var searchText: String = "" {
        didSet {
            scheduleDebounce()
        }
    }
    
    /// Debounced search text used for actual filtering
    private(set) var debouncedSearchText: String = ""
    
    /// Whether to search in tab titles (includes customName and title)
    var searchInTitle: Bool = false
    
    /// Whether to search in tab URLs
    var searchInURL: Bool = false
    
    /// Unread status filter for quick filtering
    ///
    /// Filters tabs based on their read/unread status:
    /// - `nil`: No filtering by read status (default)
    /// - `true`: Show only unread tabs
    /// - `false`: Show only read tabs
    ///
    /// When a saved filter is active, its `searchUnread` value takes precedence.
    var searchUnread: Bool?
    
    /// Currently applied saved filter, if any
    var appliedSavedFilter: SavedFilter?
    
    /// Integer signature to cheaply detect meaningful changes for caching.
    var signature: Int {
        var h = Hasher()
        h.combine(hasActiveFilter)
        h.combine(appliedSavedFilter?.id)
        h.combine(searchUnread)
        h.combine(debouncedSearchText)
        h.combine(searchInTitle)
        h.combine(searchInURL)
        return h.finalize()
    }
    
    // MARK: - Private State
    
    private var debounceTask: Task<Void, any Error>?
    private let debounceDelay: Duration = .milliseconds(300)
    
    // MARK: - Computed Properties
    
    /// Whether any filter is currently active.
    var hasActiveFilter: Bool {
        let hasTextFilter = !debouncedSearchText.isEmpty && (searchInTitle || searchInURL)
        let hasSavedFilter = appliedSavedFilter != nil
        let hasUnreadFilter = (appliedSavedFilter?.searchUnread ?? searchUnread) != nil
        return hasSavedFilter || hasTextFilter || hasUnreadFilter
    }
    
    /// Summary text describing the current filter state.
    var filterSummary: String {
        if let saved = appliedSavedFilter {
            return "Filter: \(saved.displayName)"
        } else if hasActiveFilter {
            var parts: [String] = []
            if searchInTitle { parts.append("Title") }
            if searchInURL { parts.append("URL") }
            return "Filter by \(parts.joined(separator: ", ")): \"\(debouncedSearchText)\""
        } else {
            return "No filters"
        }
    }
    
    // MARK: - Filtering
    
    /// Filters a list of tabs based on current filter criteria.
    ///
    /// Applies both unread status filtering and text-based search. The unread filter
    /// acts as a hard constraint (applied first), followed by optional text matching.
    ///
    /// ## Filter Logic
    /// 1. **Unread Filter** (if set): Tabs must match the read/unread status
    /// 2. **Text Search** (if not empty): Tabs must match text in title OR URL (OR logic)
    /// 3. Both conditions use AND logic: unread filter AND (title OR URL)
    ///
    /// ## Examples
    /// ```swift
    /// // Only unread tabs (no text search)
    /// searchUnread = true
    /// debouncedSearchText = ""
    /// // Result: All unread tabs
    ///
    /// // Unread tabs containing "apple"
    /// searchUnread = true
    /// debouncedSearchText = "apple"
    /// searchInTitle = true
    /// // Result: Unread tabs with "apple" in title
    /// ```
    ///
    /// - Parameter tabs: All tabs to filter
    /// - Returns: Filtered list of tabs matching criteria
    func filterTabs(_ tabs: [Tab]) -> [Tab] {
        // No filter active - return all tabs
        guard hasActiveFilter else { return tabs }
        
        let inTitle = appliedSavedFilter?.searchInTitle ?? searchInTitle
        let inURL = appliedSavedFilter?.searchInURL ?? searchInURL
        let unreadFilter = appliedSavedFilter?.searchUnread ?? searchUnread
        
        return tabs.filter { tab in
            // Apply unread filter first (hard constraint)
            if let unreadFilter {
                if tab.isUnread != unreadFilter {
                    return false
                }
            }
            
            // If there's no text search, tab passes if it matched unread filter
            let searchString = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if searchString.isEmpty {
                return true // Already passed unread filter above
            }
            
            // Check title (both customName and page title)
            if inTitle {
                let displayTitle = [tab.customName]
                let otherTitles = tab.pages.map(\.title)
                let titles = (displayTitle + otherTitles).compactMap(\.self)
                if titles.contains(where: { $0.localizedStandardContains(searchString) }) {
                    return true
                }
            }
            
            // Check URL
            if inURL {
                let urlStrings = tab.pages.map(\.url.absoluteString)
                if urlStrings.contains(where: { $0.localizedStandardContains(searchString) }) {
                    return true
                }
            }
            
            return false
        }
    }
    
    // MARK: - Quick Filters
    
    /// Applies a quick filter with the specified criteria.
    ///
    /// This clears any saved filter and sets up text-based filtering.
    ///
    /// - Parameters:
    ///   - searchText: Text to search for
    ///   - inTitle: Whether to search in titles
    ///   - inURL: Whether to search in URLs
    func applyQuickFilter(searchText: String, inTitle: Bool, inURL: Bool) {
        appliedSavedFilter = nil
        self.searchText = searchText
        searchInTitle = inTitle
        searchInURL = inURL
    }
    
    /// Applies a saved filter configuration.
    ///
    /// - Parameter filter: The saved filter to apply
    func applySavedFilter(_ filter: SavedFilter) {
        appliedSavedFilter = filter
        searchText = filter.searchText
        searchInTitle = filter.searchInTitle
        searchInURL = filter.searchInURL
        searchUnread = filter.searchUnread
        filter.lastUsed = Date()
    }
    
    /// Clears all active filters and resets to default state.
    func clearFilters() {
        appliedSavedFilter = nil
        searchText = ""
        debouncedSearchText = ""
        searchInTitle = false
        searchInURL = false
        searchUnread = nil
        debounceTask?.cancel()
    }
    
    // MARK: - Debouncing
    
    /// Schedules a debounced update of the search text.
    private func scheduleDebounce() {
        debounceTask?.cancel()

        let currentText = searchText
        debounceTask = Task {
            try await Task.sleep(for: debounceDelay)

            await MainActor.run {
                self.debouncedSearchText = currentText
            }
        }
    }
}
