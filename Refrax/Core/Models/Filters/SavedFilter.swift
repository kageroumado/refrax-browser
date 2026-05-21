import Foundation
import SwiftData

/// Represents a saved filter configuration for filtering tabs.
///
/// Saved filters allow users to create reusable filter presets that can be quickly
/// applied to show only tabs matching specific criteria. Filters are persisted globally
/// across the app using SwiftData.
///
/// ## Filter Matching
/// - Text matching is case-insensitive and accent-insensitive (e.g., "café" matches "cafe")
/// - Uses substring matching (contains) rather than exact match
/// - When multiple conditions are enabled, uses OR logic (match any)
///
/// ## Extensibility
/// The model is designed to accommodate future filter conditions by adding new
/// Boolean properties for each condition type.
@Model
final class SavedFilter {
    #Index<SavedFilter>([\.createdAt], [\.lastUsed])

    // MARK: - Properties

    /// Unique identifier for the filter
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID
    
    /// User-visible name for the saved filter
    var name: String
    
    /// Search text to match against tab properties
    var searchText: String
    
    /// Whether to search in tab title (includes both title and customName)
    var searchInTitle: Bool
    
    /// Whether to search in tab URL
    var searchInURL: Bool
    
    /// Unread status filter for tabs
    ///
    /// Controls filtering based on tab read/unread status:
    /// - `nil`: Show all tabs regardless of read status (no filtering)
    /// - `true`: Show only unread tabs
    /// - `false`: Show only read tabs
    ///
    /// ## Usage with Text Filters
    /// When combined with `searchText`, both conditions must be satisfied (AND logic).
    /// The unread filter is applied first as a hard constraint, then text matching
    /// is performed on the remaining tabs.
    ///
    /// ## Example
    /// ```swift
    /// // Filter for unread tabs containing "apple" in title or URL
    /// let filter = SavedFilter(
    ///     name: "Unread Apple tabs",
    ///     searchText: "apple",
    ///     searchUnread: true
    /// )
    /// ```
    var searchUnread: Bool?
    
    /// Timestamp when filter was created
    var createdAt: Date
    
    /// Timestamp when filter was last used
    var lastUsed: Date
    
    // MARK: - Future Filter Conditions

    // Add new filter conditions here as booleans:
    // var filterByPinned: Bool = false
    // var filterByGroup: UUID? = nil
    // var filterByDateRange: DateInterval? = nil
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String,
        searchText: String,
        searchInTitle: Bool = true,
        searchInURL: Bool = true,
        searchUnread: Bool? = nil,
        createdAt: Date = Date(),
        lastUsed: Date = Date(),
    ) {
        self.id = id
        self.name = name
        self.searchText = searchText
        self.searchInTitle = searchInTitle
        self.searchInURL = searchInURL
        self.searchUnread = searchUnread
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }
}

// MARK: - Computed Properties

extension SavedFilter {
    /// Display name for the filter, suitable for UI presentation.
    var displayName: String {
        name.isEmpty ? "Untitled Filter" : name
    }
    
    /// Whether this filter has any active conditions.
    var isActive: Bool {
        let hasTextFilter = !searchText.isEmpty && (searchInTitle || searchInURL)
        let hasUnreadFilter = searchUnread != nil
        return hasTextFilter || hasUnreadFilter
    }
}
