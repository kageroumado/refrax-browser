import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Sidebar.FilterManager operations.
    @Tag static var sidebarFilterManager: Self
}

// MARK: - FilterManager Initialization Tests

@Suite("Sidebar.FilterManager Initialization", .tags(.sidebarFilterManager))
@MainActor
struct FilterManagerInitializationTests {
    @Test("Initial search text is empty")
    func initialSearchTextEmpty() {
        let manager = Sidebar.FilterManager()

        #expect(manager.searchText.isEmpty)
        #expect(manager.debouncedSearchText.isEmpty)
    }

    @Test("Initial search flags are true")
    func initialSearchFlagsTrue() {
        let manager = Sidebar.FilterManager()

        #expect(manager.searchInTitle == true)
        #expect(manager.searchInURL == true)
    }

    @Test("Initial quick filter is nil")
    func initialQuickFilterNil() {
        let manager = Sidebar.FilterManager()

        #expect(manager.quickFilter == nil)
    }

    @Test("Initial saved filter is nil")
    func initialSavedFilterNil() {
        let manager = Sidebar.FilterManager()

        #expect(manager.appliedSavedFilter == nil)
    }

    @Test("Initial toolbar is hidden")
    func initialToolbarHidden() {
        let manager = Sidebar.FilterManager()

        #expect(manager.isToolbarVisible == false)
    }

    @Test("Initial page lookup is nil")
    func initialPageLookupNil() {
        let manager = Sidebar.FilterManager()

        #expect(manager.pageLookup == nil)
    }
}

// MARK: - FilterManager hasActiveFilter Tests

@Suite("Sidebar.FilterManager hasActiveFilter", .tags(.sidebarFilterManager))
@MainActor
struct FilterManagerHasActiveFilterTests {
    @Test("No active filter initially")
    func noActiveFilterInitially() {
        let manager = Sidebar.FilterManager()

        #expect(manager.hasActiveFilter == false)
    }

    @Test("Has active filter with search text")
    func hasActiveFilterWithSearchText() {
        let manager = Sidebar.FilterManager()

        // Use applyQuickFilter to set text immediately (bypasses debounce)
        manager.applyQuickFilter(searchText: "test")

        #expect(manager.hasActiveFilter == true)
    }

    @Test("Has active filter with quick filter")
    func hasActiveFilterWithQuickFilter() {
        let manager = Sidebar.FilterManager()

        manager.quickFilter = .unread

        #expect(manager.hasActiveFilter == true)
    }

    @Test("No active filter when search text cleared")
    func noActiveFilterWhenCleared() {
        let manager = Sidebar.FilterManager()

        manager.applyQuickFilter(searchText: "test")
        #expect(manager.hasActiveFilter == true)

        manager.clearFilters()
        #expect(manager.hasActiveFilter == false)
    }
}

// MARK: - FilterManager Signature Tests

@Suite("Sidebar.FilterManager Signature", .tags(.sidebarFilterManager))
@MainActor
struct FilterManagerSignatureTests {
    @Test("Signature is consistent for same state")
    func signatureConsistent() {
        let manager = Sidebar.FilterManager()

        let sig1 = manager.signature
        let sig2 = manager.signature

        #expect(sig1 == sig2)
    }

    @Test("Signature changes with search text")
    func signatureChangesWithSearchText() {
        let manager = Sidebar.FilterManager()

        let initial = manager.signature

        // Use applyQuickFilter to set text immediately (bypasses debounce)
        manager.applyQuickFilter(searchText: "new search")

        #expect(manager.signature != initial)
    }

    @Test("Signature changes with search flags")
    func signatureChangesWithSearchFlags() {
        let manager = Sidebar.FilterManager()

        let initial = manager.signature

        manager.searchInTitle = false

        #expect(manager.signature != initial)
    }

    @Test("Signature changes with quick filter")
    func signatureChangesWithQuickFilter() {
        let manager = Sidebar.FilterManager()

        let initial = manager.signature

        manager.quickFilter = .read

        #expect(manager.signature != initial)
    }
}

// MARK: - FilterManager Search Configuration Tests

@Suite("Sidebar.FilterManager Search Configuration", .tags(.sidebarFilterManager))
@MainActor
struct FilterManagerSearchConfigurationTests {
    @Test("Search text updates debounced text after delay")
    func searchTextUpdatesDebounced() async throws {
        let manager = Sidebar.FilterManager()

        manager.searchText = "query"

        // debouncedSearchText is updated after a short delay (150ms)
        #expect(manager.debouncedSearchText.isEmpty)

        // Wait for debounce to complete (add margin for CI timing variance)
        try await Task.sleep(for: .milliseconds(300))

        #expect(manager.debouncedSearchText == "query")
    }

    @Test("applyQuickFilter sets debounced text immediately")
    func applyQuickFilterSetsImmediately() {
        let manager = Sidebar.FilterManager()

        manager.applyQuickFilter(searchText: "immediate")

        #expect(manager.debouncedSearchText == "immediate")
    }

    @Test("Search in title toggle")
    func searchInTitleToggle() {
        let manager = Sidebar.FilterManager()

        manager.searchInTitle = false

        #expect(manager.searchInTitle == false)
    }

    @Test("Search in URL toggle")
    func searchInURLToggle() {
        let manager = Sidebar.FilterManager()

        manager.searchInURL = false

        #expect(manager.searchInURL == false)
    }

    @Test("Both search flags can be disabled")
    func bothSearchFlagsDisabled() {
        let manager = Sidebar.FilterManager()

        manager.searchInTitle = false
        manager.searchInURL = false

        #expect(manager.searchInTitle == false)
        #expect(manager.searchInURL == false)
    }
}

// MARK: - FilterManager Toolbar Tests

@Suite("Sidebar.FilterManager Toolbar", .tags(.sidebarFilterManager))
@MainActor
struct FilterManagerToolbarTests {
    @Test("Toolbar visibility can be toggled")
    func toolbarVisibilityToggle() {
        let manager = Sidebar.FilterManager()

        manager.isToolbarVisible = true

        #expect(manager.isToolbarVisible == true)

        manager.isToolbarVisible = false

        #expect(manager.isToolbarVisible == false)
    }
}

// MARK: - QuickFilter Model Tests

@Suite("QuickFilter Model", .tags(.sidebarFilterManager))
@MainActor
struct QuickFilterModelTests {
    @Test("All cases are defined")
    func allCasesDefined() {
        let allCases = QuickFilter.allCases

        #expect(allCases.contains(.unread))
        #expect(allCases.contains(.read))
        #expect(allCases.contains(.audible))
        #expect(allCases.contains(.mediaCapture))
        #expect(allCases.count == 4)
    }

    @Test("displayName is non-empty for all cases")
    func displayNameNonEmpty() {
        for filter in QuickFilter.allCases {
            #expect(!filter.displayName.isEmpty, "displayName should not be empty for \(filter)")
        }
    }

    @Test("iconName is non-empty for all cases")
    func iconNameNonEmpty() {
        for filter in QuickFilter.allCases {
            #expect(!filter.iconName.isEmpty, "iconName should not be empty for \(filter)")
        }
    }

    @Test("requiresWebPage is false for unread and read")
    func requiresWebPageForReadFilters() {
        #expect(QuickFilter.unread.requiresWebPage == false)
        #expect(QuickFilter.read.requiresWebPage == false)
    }

    @Test("requiresWebPage is true for media filters")
    func requiresWebPageForMediaFilters() {
        #expect(QuickFilter.audible.requiresWebPage == true)
        #expect(QuickFilter.mediaCapture.requiresWebPage == true)
    }

    @Test("autocompleteKeywords are non-empty for all cases")
    func autocompleteKeywordsNonEmpty() {
        for filter in QuickFilter.allCases {
            #expect(!filter.autocompleteKeywords.isEmpty, "keywords should not be empty for \(filter)")
        }
    }

    @Test("id returns self (Identifiable conformance)")
    func idReturnsSelf() {
        for filter in QuickFilter.allCases {
            #expect(filter.id == filter)
        }
    }
}

// MARK: - QuickFilter Matching Tests

@Suite("QuickFilter Matching", .tags(.sidebarFilterManager))
@MainActor
struct QuickFilterMatchingTests {
    @Test("matching returns unread for 'unread' prefix")
    func matchingUnread() {
        #expect(QuickFilter.matching(searchText: "unread") == .unread)
        #expect(QuickFilter.matching(searchText: "unr") == .unread)
        #expect(QuickFilter.matching(searchText: "u") == .unread)
    }

    @Test("matching returns read for 'read' prefix")
    func matchingRead() {
        #expect(QuickFilter.matching(searchText: "read") == .read)
        #expect(QuickFilter.matching(searchText: "rea") == .read)
    }

    @Test("matching returns audible for audio keywords")
    func matchingAudible() {
        #expect(QuickFilter.matching(searchText: "audible") == .audible)
        #expect(QuickFilter.matching(searchText: "audio") == .audible)
        #expect(QuickFilter.matching(searchText: "sound") == .audible)
        #expect(QuickFilter.matching(searchText: "playing") == .audible)
        #expect(QuickFilter.matching(searchText: "music") == .audible)
        #expect(QuickFilter.matching(searchText: "aud") == .audible)
    }

    @Test("matching returns mediaCapture for capture keywords")
    func matchingMediaCapture() {
        #expect(QuickFilter.matching(searchText: "mic") == .mediaCapture)
        #expect(QuickFilter.matching(searchText: "microphone") == .mediaCapture)
        #expect(QuickFilter.matching(searchText: "camera") == .mediaCapture)
        #expect(QuickFilter.matching(searchText: "video") == .mediaCapture)
        #expect(QuickFilter.matching(searchText: "recording") == .mediaCapture)
        #expect(QuickFilter.matching(searchText: "capture") == .mediaCapture)
    }

    @Test("matching is case insensitive")
    func matchingCaseInsensitive() {
        #expect(QuickFilter.matching(searchText: "UNREAD") == .unread)
        #expect(QuickFilter.matching(searchText: "Audible") == .audible)
        #expect(QuickFilter.matching(searchText: "MIC") == .mediaCapture)
    }

    @Test("matching returns nil for non-matching text")
    func matchingReturnsNilForNoMatch() {
        #expect(QuickFilter.matching(searchText: "foo") == nil)
        #expect(QuickFilter.matching(searchText: "xyz") == nil)
        #expect(QuickFilter.matching(searchText: "google.com") == nil)
    }

    @Test("matching returns first filter for empty text (prefix always matches)")
    func matchingReturnsFirstForEmpty() {
        // Empty string matches first keyword of first filter because "".hasPrefix("") is true
        // This behavior means autocomplete activates immediately on focus
        #expect(QuickFilter.matching(searchText: "") == .unread)
    }

    @Test("matching returns first match (unread before read)")
    func matchingReturnsFirstMatch() {
        // 'r' could match both 'read' and 'recording' but the order matters
        // 'unread' comes before 'read' in allCases, so 'u' matches unread
        // 'r' would match 'read' first (comes before audible/mediaCapture)
        let result = QuickFilter.matching(searchText: "r")

        #expect(result == .read)
    }
}

// MARK: - FilterSuggestion Tests

@Suite("FilterSuggestion", .tags(.sidebarFilterManager))
@MainActor
struct FilterSuggestionTests {
    @Test("quickFilter displayName matches filter displayName")
    func quickFilterDisplayName() {
        let suggestion = FilterSuggestion.quickFilter(.unread)

        #expect(suggestion.displayName == QuickFilter.unread.displayName)
    }

    @Test("quickFilter iconName matches filter iconName")
    func quickFilterIconName() {
        let suggestion = FilterSuggestion.quickFilter(.audible)

        #expect(suggestion.iconName == QuickFilter.audible.iconName)
    }

    @Test("savedFilter displayName matches filter displayName")
    func savedFilterDisplayName() {
        let savedFilter = SavedFilter(
            name: "Test Filter",
            searchText: "query",
            searchInTitle: true,
            searchInURL: true,
            searchUnread: nil,
        )
        let suggestion = FilterSuggestion.savedFilter(savedFilter)

        #expect(suggestion.displayName == savedFilter.displayName)
    }

    @Test("savedFilter iconName is consistent")
    func savedFilterIconName() {
        let savedFilter = SavedFilter(
            name: "Test",
            searchText: "",
            searchInTitle: true,
            searchInURL: true,
            searchUnread: nil,
        )
        let suggestion = FilterSuggestion.savedFilter(savedFilter)

        #expect(suggestion.iconName == "line.3.horizontal.decrease.circle")
    }

    @Test("Equality compares by case and value")
    func equalityComparison() {
        let quick1 = FilterSuggestion.quickFilter(.unread)
        let quick2 = FilterSuggestion.quickFilter(.unread)
        let quick3 = FilterSuggestion.quickFilter(.read)

        #expect(quick1 == quick2)
        #expect(quick1 != quick3)
    }
}

// MARK: - Notes

//
// Sidebar.FilterManager functionality requiring integration tests:
//
// 1. filterItems: Requires TabListItem array with tabs
// 2. Page-based filters: Requires pageLookup closure and WebPage state
// 3. SavedFilter application: Requires SavedFilter model
// 4. Group visibility: Requires group hierarchy for ancestor inclusion
//
// The tests above verify:
// - Initial state is empty/default
// - hasActiveFilter reflects filter state correctly
// - Signature changes with any filter change (cache key behavior)
// - Search configuration can be modified
// - Toolbar visibility is toggleable
//
// Full filtering tests require:
// - TabListItem arrays with various tab configurations
// - WebPage mock for page-based filters
// - Tab groups for hierarchy testing
//
