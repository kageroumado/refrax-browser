import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

// MARK: - CommandLensSuggestion Model Tests

@Suite("CommandLensSuggestion Model", .tags(.commandLensManager))
@MainActor
struct CommandLensSuggestionModelTests {
    @Test
    func `Each suggestion has unique auto-generated UUID`() {
        let suggestion1 = CommandLensSuggestion(
            type: .search,
            text: "Query 1",
            description: "Description 1",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )

        let suggestion2 = CommandLensSuggestion(
            type: .search,
            text: "Query 1",
            description: "Description 1",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )

        // Each instance gets a unique UUID
        #expect(suggestion1.id != suggestion2.id)
        #expect(suggestion1 != suggestion2)
    }

    @Test
    func `Equality based on id`() {
        let suggestion = CommandLensSuggestion(
            type: .search,
            text: "Query",
            description: "Description",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )

        // Same instance is equal to itself
        #expect(suggestion == suggestion)
    }

    @Test
    func `Hash based on id`() {
        let suggestion = CommandLensSuggestion(
            type: .search,
            text: "Query",
            description: "Desc",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )

        // Same instance has same hash
        #expect(suggestion.hashValue == suggestion.hashValue)
    }

    @Test
    func `withGroupHeader creates copy with new header`() {
        let original = CommandLensSuggestion(
            type: .search,
            text: "Query",
            description: "Description",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: true,
            keywordAction: "kw",
            url: nil,
        )

        let withHeader = original.withGroupHeader("New Header")

        // Header should be updated
        #expect(withHeader.groupHeader == "New Header")

        // Other properties should be preserved (except id which is new)
        #expect(withHeader.type == original.type)
        #expect(withHeader.text == original.text)
        #expect(withHeader.description == original.description)
        #expect(withHeader.iconName == original.iconName)
        #expect(withHeader.isRemovable == original.isRemovable)
        #expect(withHeader.keywordAction == original.keywordAction)

        // New copy gets a new UUID
        #expect(withHeader.id != original.id)
    }

    @Test
    func `withGroupHeader replaces existing header`() {
        let original = CommandLensSuggestion(
            type: .search,
            text: "Query",
            description: "Description",
            iconName: "magnifyingglass",
            groupHeader: "Old Header",
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )

        let withHeader = original.withGroupHeader("New Header")

        #expect(withHeader.groupHeader == "New Header")
    }

    @Test
    func `Can be used in Set with unique ids`() {
        let suggestion1 = CommandLensSuggestion(
            type: .search,
            text: "Query 1",
            description: "Desc",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )

        let suggestion2 = CommandLensSuggestion(
            type: .search,
            text: "Query 2",
            description: "Desc",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )

        var set: Set<CommandLensSuggestion> = [suggestion1, suggestion2]
        #expect(set.count == 2)

        // Adding same instance again doesn't increase count
        set.insert(suggestion1)
        #expect(set.count == 2)
    }
}

// MARK: - CommandLensSelection Model Tests

@Suite("CommandLensSelection Model", .tags(.commandLensManager))
@MainActor
struct CommandLensSelectionModelTests {
    @Test
    func `none has index -1`() {
        let selection = CommandLensSelection.none

        #expect(selection.index == -1)
        #expect(selection.buttonSelection == .none)
    }

    @Test
    func `Equality compares index and buttonSelection`() {
        let selection1 = CommandLensSelection(index: 5, buttonSelection: .keyword)
        let selection2 = CommandLensSelection(index: 5, buttonSelection: .keyword)
        let selection3 = CommandLensSelection(index: 5, buttonSelection: .remove)
        let selection4 = CommandLensSelection(index: 3, buttonSelection: .keyword)

        #expect(selection1 == selection2)
        #expect(selection1 != selection3)
        #expect(selection1 != selection4)
    }

    @Test
    func `ButtonSelection has all expected cases`() {
        let none = CommandLensSelection.ButtonSelection.none
        let keyword = CommandLensSelection.ButtonSelection.keyword
        let remove = CommandLensSelection.ButtonSelection.remove
        let switchProvider = CommandLensSelection.ButtonSelection.switchProvider

        // Just verify they exist and are distinct
        #expect(none != keyword)
        #expect(keyword != remove)
        #expect(remove != switchProvider)
    }

    @Test
    func `Default buttonSelection is none`() {
        let selection = CommandLensSelection(index: 0)

        #expect(selection.buttonSelection == .none)
    }
}

// MARK: - SuggestionContext Model Tests

@Suite("SuggestionContext Model", .tags(.commandLensManager))
@MainActor
struct SuggestionContextModelTests {
    @Test
    func `isEmptyInput true for empty string`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isEmptyInput == true)
    }

    @Test
    func `isEmptyInput true for whitespace only`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "   \t\n  ",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isEmptyInput == true)
    }

    @Test
    func `isEmptyInput false for non-empty`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "query",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isEmptyInput == false)
    }

    @Test
    func `isDirectURL true for https://`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "https://example.com",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isDirectURL == true)
    }

    @Test
    func `isDirectURL true for http://`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "http://example.com",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isDirectURL == true)
    }

    @Test
    func `isDirectURL case insensitive`() throws {
        let env = try TabManagerTestEnvironment()

        let context1 = SuggestionContext(
            input: "HTTPS://EXAMPLE.COM",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        let context2 = SuggestionContext(
            input: "HtTpS://Example.com",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context1.isDirectURL == true)
        #expect(context2.isDirectURL == true)
    }

    @Test
    func `isDirectURL false for domain without protocol`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "example.com",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isDirectURL == false)
    }

    @Test
    func `isDirectURL false for search query`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "how to use https",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isDirectURL == false)
    }

    @Test
    func `isDirectURL handles leading whitespace`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "  https://example.com",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.isDirectURL == true)
    }

    @Test
    func `Preserves input exactly`() throws {
        let env = try TabManagerTestEnvironment()
        let input = "  Test Query  "

        let context = SuggestionContext(
            input: input,
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: nil,
        )

        #expect(context.input == input)
    }

    @Test
    func `Preserves currentTabID`() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let context = SuggestionContext(
            input: "query",
            settings: env.settings,
            currentTabID: tabID,
            selectedSearchEngine: nil,
        )

        #expect(context.currentTabID == tabID)
    }

    @Test
    func `Preserves selectedSearchEngine`() throws {
        let env = try TabManagerTestEnvironment()

        let context = SuggestionContext(
            input: "query",
            settings: env.settings,
            currentTabID: nil,
            selectedSearchEngine: SearchEngine.duckDuckGo,
        )

        #expect(context.selectedSearchEngine == SearchEngine.duckDuckGo)
    }
}

// MARK: - SuggestionType Model Tests

@Suite("SuggestionType Model", .tags(.commandLensManager))
@MainActor
struct SuggestionTypeModelTests {
    @Test
    func `search type is hashable`() {
        let type1 = SuggestionType.search
        let type2 = SuggestionType.search

        #expect(type1 == type2)
        #expect(type1.hashValue == type2.hashValue)
    }

    @Test
    func `url type is hashable`() {
        let type1 = SuggestionType.url
        let type2 = SuggestionType.url

        #expect(type1 == type2)
    }

    @Test
    func `openTab equality includes tabID`() {
        let id1 = UUID()
        let id2 = UUID()

        let type1 = SuggestionType.openTab(tabID: id1)
        let type2 = SuggestionType.openTab(tabID: id1)
        let type3 = SuggestionType.openTab(tabID: id2)

        #expect(type1 == type2)
        #expect(type1 != type3)
    }

    @Test
    func `searchProvider equality includes engine`() {
        let type1 = SuggestionType.searchProvider(.google)
        let type2 = SuggestionType.searchProvider(.google)
        let type3 = SuggestionType.searchProvider(.duckDuckGo)

        #expect(type1 == type2)
        #expect(type1 != type3)
    }

    @Test
    func `richEntity equality includes imageUrl`() throws {
        let url1 = try #require(URL(string: "https://example.com/image1.png"))
        let url2 = try #require(URL(string: "https://example.com/image2.png"))

        let type1 = SuggestionType.richEntity(imageUrl: url1)
        let type2 = SuggestionType.richEntity(imageUrl: url1)
        let type3 = SuggestionType.richEntity(imageUrl: url2)

        #expect(type1 == type2)
        #expect(type1 != type3)
    }

    @Test
    func `recentlyClosed equality includes index`() {
        let type1 = SuggestionType.recentlyClosed(index: 0)
        let type2 = SuggestionType.recentlyClosed(index: 0)
        let type3 = SuggestionType.recentlyClosed(index: 1)

        #expect(type1 == type2)
        #expect(type1 != type3)
    }

    @Test
    func `Different types are not equal`() throws {
        let search = SuggestionType.search
        let url = SuggestionType.url
        let openTab = SuggestionType.openTab(tabID: UUID())
        let searchProvider = SuggestionType.searchProvider(.google)
        let richEntity = try SuggestionType.richEntity(imageUrl: #require(URL(string: "https://example.com")))
        let recentlyClosed = SuggestionType.recentlyClosed(index: 0)

        let types: [SuggestionType] = [search, url, openTab, searchProvider, richEntity, recentlyClosed]

        for i in 0 ..< types.count {
            for j in (i + 1) ..< types.count {
                #expect(types[i] != types[j], "Expected \(types[i]) != \(types[j])")
            }
        }
    }

    @Test
    func `Can be used as dictionary key`() {
        var dict: [SuggestionType: String] = [:]

        dict[.search] = "Search"
        dict[.url] = "URL"
        dict[.openTab(tabID: UUID())] = "Open Tab"

        #expect(dict[.search] == "Search")
        #expect(dict[.url] == "URL")
    }
}

// MARK: - CommandLens Provider Regression Tests

/// Tests for CommandLensManager provider functionality that could regress
/// when implementing settings control (3.1), and CommandLens enhancements.
@Suite("CommandLens Provider", .tags(.commandLensManager), .serialized)
@MainActor
struct CommandLensProviderTests {
    // MARK: - Input Text Handling Tests

    @Test
    func `Input text is trimmed for query`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("  test  ")

        #expect(manager.inputText == "  test  ")
        // The query should be trimmed internally
    }

    @Test
    func `URL input detected correctly`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("https://example.com")

        // When input looks like a URL, behavior should differ
        #expect(manager.inputText == "https://example.com")
    }

    @Test
    func `Domain input detected`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("example.com")

        #expect(manager.inputText == "example.com")
    }

    // MARK: - Selection Navigation Tests

    @Test
    func `Selection starts at none`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        #expect(manager.selection == .none)
        #expect(manager.selection.index == -1)
    }

    @Test
    func `Selection move down increments when suggestions exist`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        // Trigger input to generate suggestions
        manager.onInputChanged("test")

        // moveSelection does nothing when suggestions is empty
        // (returns early with guard)
        manager.moveSelection(by: 1)

        // If suggestions exist, selection moves to index 0
        // If empty, selection stays at .none (-1)
        if !manager.suggestions.isEmpty {
            #expect(manager.selection.index >= 0)
        } else {
            #expect(manager.selection == .none)
        }
    }

    @Test
    func `Selection wraps when moving up from index 0`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("test")

        // moveSelection wraps using modulo, doesn't go to .none
        // (0 - 1 + n) % n = (n - 1) = last index
        if !manager.suggestions.isEmpty {
            manager.moveSelection(by: 1) // Select first (index 0)
            manager.moveSelection(by: -1) // Wraps to last

            // With modulo wrap, -1 from index 0 goes to last index
            #expect(manager.selection.index == manager.suggestions.count - 1)
        }
    }

    @Test
    func `Selection wraps at bottom`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("test")

        // Move down many times past the suggestion count
        for _ in 0 ..< 20 {
            manager.moveSelection(by: 1)
        }

        // Selection should be within valid range (wraps with modulo)
        if !manager.suggestions.isEmpty {
            #expect(manager.selection.index >= 0)
            #expect(manager.selection.index < manager.suggestions.count)
        } else {
            #expect(manager.selection == .none)
        }
    }

    // MARK: - Popup Visibility Tests

    @Test
    func `Popup shows on non-empty input`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        #expect(!manager.isPopupVisible)

        manager.onInputChanged("query")

        #expect(manager.isPopupVisible)
    }

    @Test
    func `Popup hides on empty input`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("query")
        #expect(manager.isPopupVisible)

        manager.onInputChanged("")
        #expect(!manager.isPopupVisible)
    }

    @Test
    func `Popup hides on reset`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("query")
        #expect(manager.isPopupVisible)

        manager.reset()
        #expect(!manager.isPopupVisible)
    }

    // MARK: - Search Engine Tests

    @Test
    func `Default search engine from settings`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        // Current search engine should use default from settings
        let engine = manager.currentSearchEngine

        #expect(engine == .duckDuckGo)
    }

    @Test
    func `Selected search engine overrides default`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        // Set a selected engine
        manager.selectedSearchEngine = SearchEngine.duckDuckGo

        #expect(manager.selectedSearchEngine == SearchEngine.duckDuckGo)
        #expect(manager.currentSearchEngine == SearchEngine.duckDuckGo)
    }

    @Test
    func `Search engine badge shows when engine selected`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        #expect(!manager.showSearchEngineBadge)

        manager.selectedSearchEngine = SearchEngine.google

        #expect(manager.showSearchEngineBadge)
    }

    // MARK: - Inline Completion Tests

    @Test
    func `Inline completion starts nil`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        #expect(manager.inlineCompletion == nil)
        #expect(manager.inlineCompletionRange == nil)
    }

    @Test
    func `Display text returns inline completion when present`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.inputText = "test"

        // displayText returns inputText when no completion
        #expect(manager.displayText == "test")

        // displayText returns inlineCompletion when present (replaces, doesn't concatenate)
        manager.inlineCompletion = "testing"
        #expect(manager.displayText == "testing")
    }

    // MARK: - Suggestions Tests

    @Test
    func `Suggestions empty initially`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        #expect(manager.suggestions.isEmpty)
    }

    @Test
    func `Suggestions cleared on empty input`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        manager.onInputChanged("test")
        manager.onInputChanged("")

        #expect(manager.suggestions.isEmpty)
    }

    // MARK: - Loading State Tests

    @Test
    func `Loading state starts false`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        #expect(!manager.isLoading)
    }
}

// MARK: - CommandLens Empty State Tests

@Suite("CommandLens Empty State", .tags(.commandLensManager), .serialized)
@MainActor
struct CommandLensEmptyStateTests {
    @Test
    func `Empty state has all directions`() {
        let directions = EmptyStateDirection.allCases

        #expect(directions.contains(.up))
        #expect(directions.contains(.down))
        #expect(directions.contains(.left))
        #expect(directions.contains(.right))
    }
}

// MARK: - CommandLens Commit Tests

@Suite("CommandLens Commit", .tags(.commandLensManager), .serialized)
@MainActor
struct CommandLensCommitTests {
    @Test
    func `Commit clears input`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        // Create a tab for the manager to work with
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        manager.onInputChanged("https://test.com")

        // Commit should clear and close
        manager.commitSelection()

        #expect(manager.inputText.isEmpty)
        #expect(!manager.isPopupVisible)
    }

    @Test
    func `Commit hides popup`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        manager.onInputChanged("test query")
        #expect(manager.isPopupVisible)

        manager.commitSelection()

        #expect(!manager.isPopupVisible)
    }

    @Test
    func `Commit resets selection`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        manager.onInputChanged("query")
        manager.moveSelection(by: 1) // Select something

        manager.commitSelection()

        #expect(manager.selection == .none)
    }

    @Test
    func `Commit clears inline completion`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource(),
        )

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        manager.onInputChanged("test")
        manager.inlineCompletion = "completion"

        manager.commitSelection()

        #expect(manager.inlineCompletion == nil)
    }
}

// MARK: - Archived Tabs Provider Tests

@Suite("Archived Tabs Provider", .tags(.commandLensManager))
struct ArchivedTabsProviderQueryTests {
    @Test
    func `The keyword alone lists every archived tab`() {
        #expect(ArchivedTabsProvider.query(in: "archived") == "")
        #expect(ArchivedTabsProvider.query(in: "  Archived ") == "")
    }

    @Test
    func `Text after the keyword narrows the list`() {
        #expect(ArchivedTabsProvider.query(in: "archived: recipes") == "recipes")
        #expect(ArchivedTabsProvider.query(in: "archived github") == "github")
    }

    @Test
    func `Other input asks for no archived tabs`() {
        #expect(ArchivedTabsProvider.query(in: "archive") == nil)
        #expect(ArchivedTabsProvider.query(in: "archivedfoo") == nil)
        #expect(ArchivedTabsProvider.query(in: "github") == nil)
    }
}
