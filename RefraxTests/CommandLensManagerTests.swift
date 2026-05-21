import Foundation
import Testing
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for CommandLensManager operations.
    @Tag static var commandLensManager: Self
}

// MARK: - CommandLensSelection Tests

@Suite("CommandLensSelection", .tags(.commandLensManager))
@MainActor
struct CommandLensSelectionTests {
    @Test("None selection has index -1")
    func noneCase() {
        let selection = CommandLensSelection.none

        #expect(selection.index == -1)
    }

    @Test("Selection with index has correct index")
    func selectionWithIndex() {
        let selection = CommandLensSelection(index: 5)

        #expect(selection.index == 5)
    }

    @Test("Default button selection is none")
    func defaultButtonSelectionIsNone() {
        let selection = CommandLensSelection(index: 0)

        #expect(selection.buttonSelection == .none)
    }
}

// MARK: - EmptyStateDirection Tests

@Suite("EmptyStateDirection", .tags(.commandLensManager))
@MainActor
struct EmptyStateDirectionTests {
    @Test("All directions exist")
    func allDirectionsExist() {
        let directions: [EmptyStateDirection] = [.up, .down, .left, .right]

        #expect(directions.count == 4)
    }

    @Test("Direction has all cases")
    func directionHasAllCases() {
        #expect(EmptyStateDirection.allCases.count == 4)
        #expect(EmptyStateDirection.allCases.contains(.up))
        #expect(EmptyStateDirection.allCases.contains(.down))
        #expect(EmptyStateDirection.allCases.contains(.left))
        #expect(EmptyStateDirection.allCases.contains(.right))
    }
}

// MARK: - CommandLensManager Initialization Tests

@Suite("CommandLensManager Initialization", .tags(.commandLensManager))
@MainActor
struct CommandLensManagerInitializationTests {
    @Test("Initial input text is empty")
    func initialInputTextEmpty() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.inputText.isEmpty)
    }

    @Test("Initial suggestions are empty")
    func initialSuggestionsEmpty() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.suggestions.isEmpty)
    }

    @Test("Initial selection is none")
    func initialSelectionNone() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.selection == CommandLensSelection.none)
    }

    @Test("Initial popup is hidden")
    func initialPopupHidden() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.isPopupVisible == false)
    }

    @Test("Initial loading is false")
    func initialLoadingFalse() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.isLoading == false)
    }

    @Test("Initial inline completion is nil")
    func initialInlineCompletionNil() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.inlineCompletion == nil)
        #expect(manager.inlineCompletionRange == nil)
    }

    @Test("Initial search engine is nil")
    func initialSearchEngineNil() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.selectedSearchEngine == nil)
    }
}

// MARK: - CommandLensManager Computed Properties Tests

@Suite("CommandLensManager Computed Properties", .tags(.commandLensManager))
@MainActor
struct CommandLensManagerComputedPropertiesTests {
    @Test("Display text returns input when no completion")
    func displayTextWithoutCompletion() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        manager.inputText = "test query"

        #expect(manager.displayText == "test query")
    }

    @Test("Show search engine badge is false initially")
    func showSearchEngineBadgeFalse() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        #expect(manager.showSearchEngineBadge == false)
    }

    @Test("Current search engine uses default")
    func currentSearchEngineUsesDefault() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        // Should use default search engine from browserSettings
        _ = manager.currentSearchEngine
    }
}

// MARK: - CommandLensManager Input Handling Tests

@Suite("CommandLensManager Input Handling", .tags(.commandLensManager))
@MainActor
struct CommandLensManagerInputHandlingTests {
    @Test("Empty input hides popup")
    func emptyInputHidesPopup() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        manager.onInputChanged("")

        #expect(manager.isPopupVisible == false)
        #expect(manager.suggestions.isEmpty)
    }

    @Test("Non-empty input shows popup")
    func nonEmptyInputShowsPopup() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        manager.onInputChanged("test")

        #expect(manager.isPopupVisible == true)
    }

    @Test("Input change updates input text")
    func inputChangeUpdatesInputText() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        manager.onInputChanged("hello world")

        #expect(manager.inputText == "hello world")
    }

    @Test("Empty input clears inline completion")
    func emptyInputClearsInlineCompletion() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let manager = CommandLensManager(
            tabManager: env.tabManager,
            historyManager: env.historyManager,
            windowState: windowState,
            browserSettings: env.settings,
            siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager,
            referencePaneManager: env.referencePaneManager,
            agentChatManager: AgentChatManager(settings: env.settings),
            extensionManager: env.extensionManager,
            customSearchEngineManager: env.customSearchEngineManager,
        )

        // Simulate having a completion
        manager.onInputChanged("test")

        // Clear input
        manager.onInputChanged("")

        #expect(manager.inlineCompletion == nil)
        #expect(manager.inlineCompletionRange == nil)
    }
}

// MARK: - Notes

//
// CommandLensManager functionality requiring integration tests:
//
// 1. Provider queries: Async suggestion fetching from multiple providers
// 2. Network debounce: Timing-based network provider queries
// 3. Inline completion: Requires history data for completion suggestions
// 4. Empty state actions: Requires tab manager state for action availability
// 5. Commit actions: Requires WebPage for navigation
//
