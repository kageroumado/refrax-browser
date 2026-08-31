import AppKit
import Foundation
import UniformTypeIdentifiers

/// Manages the command lens state and logic for a single window.
///
/// The command lens is a unified search/navigation interface that handles:
/// - URL navigation
/// - Search queries with multiple engine support
/// - Open tab switching
/// - History suggestions with inline completion
/// - Empty state actions (arrow key shortcuts)
///
/// This manager is created per-window and injected via environment.
/// The state is automatically reset when the command lens is dismissed.
///
/// ## Architecture
///
/// The manager uses a provider-based architecture for extensibility:
/// - ``CommandLensSuggestionProvider``: Sources for suggestions (tabs, history, search)
/// - ``CommandLensEmptyStateAction``: Quick actions when input is empty
///
/// Providers are queried in parallel and results are merged by priority.
@Observable
final class CommandLensManager {
    // MARK: - Public State

    var inputText: String = ""
    var suggestions: [CommandLensSuggestion] = []
    var selection: CommandLensSelection = .none
    var isPopupVisible: Bool = false
    var isLoading: Bool = false
    var hoveredSuggestionID: UUID?

    /// Inline completion text (Arc-style).
    var inlineCompletion: String?

    /// Range of the inline completion within the display text.
    var inlineCompletionRange: NSRange?

    /// The currently selected search engine (when using keyword mode).
    var selectedSearchEngine: SearchEngine?

    /// Available empty state actions for the current context.
    var availableEmptyStateActions: [EmptyStateDirection: any CommandLensEmptyStateAction] = [:]

    // MARK: - Expanded Mode State

    /// Whether the category buttons are visible (shown after 2 seconds of no interaction).
    var showCategoryButtons: Bool = false

    /// Index of the currently selected button (-1 means no selection, cursor in text field).
    var expandedSelection: Int = -1

    /// Whether the user has had a meaningful interaction (prevents auto-show buttons).
    ///
    /// Set to true when:
    /// - Arrow keys trigger an empty state action (left/up/down showing suggestions)
    /// - User starts typing
    ///
    /// Reset when the lens is reset.
    var hadUserInteraction: Bool = false

    /// Whether a category button is currently selected (vs just visible).
    var hasCategorySelection: Bool {
        showCategoryButtons && expandedSelection >= 0
    }

    /// Backwards compatibility alias.
    var isExpandedMode: Bool {
        get { showCategoryButtons }
        set { showCategoryButtons = newValue }
    }

    /// Active category search mode (nil = normal mode).
    ///
    /// When set, the command lens searches within that category only.
    var categorySearchMode: CategorySearchMode?

    /// Buttons available in expanded mode.
    var expandedModeButtons: [ExpandedModeButton] {
        ExpandedModeButton.allButtons
    }

    // MARK: - AI Mode State

    /// Whether AI mode is active (showing AI response area).
    var isAIMode: Bool = false

    /// Whether the AI is currently generating a response.
    var isAILoading: Bool = false

    /// The current AI response text.
    var aiResponse: String?

    /// Error message if AI request failed.
    var aiError: String?

    /// The original query sent to AI.
    var aiQuery: String?

    /// Whether the current input looks like an AI query.
    var isAIIntent: Bool {
        AIIntentDetector.isAIIntent(inputText)
    }

    // MARK: - Computed Properties

    /// The active search engine (selected or default from settings).
    var currentSearchEngine: SearchEngine {
        selectedSearchEngine ?? browserSettings.defaultSearchEngine
    }

    /// Whether to show the search engine badge.
    var showSearchEngineBadge: Bool {
        selectedSearchEngine != nil
    }

    /// Full text including inline completion.
    var displayText: String {
        inlineCompletion ?? inputText
    }

    // MARK: - Private State

    private var rejectedCompletion: String?
    private var rejectedAtInputLength: Int = 0
    private var commandKeyHeldDuringCommit: Bool = false
    private var optionKeyHeldDuringCommit: Bool = false
    private var searchTask: Task<Void, any Error>?

    // MARK: - Dependencies

    private let tabManager: TabManager
    private let historyManager: HistoryManager
    private let windowState: WindowState
    private let browserSettings: BrowserSettings
    private let siteSettingsManager: SiteSettingsManager
    private let downloadManager: DownloadManager
    private let referencePaneManager: ReferencePaneManager
    private let agentChatManager: AgentChatManager
    private let extensionManager: ExtensionManager
    private let customSearchEngineManager: CustomSearchEngineManager

    @ObservationIgnored private var aiStreamingTask: Task<Void, Never>?

    // MARK: - Providers

    private let suggestionProviders: [any CommandLensSuggestionProvider]
    private let networkProvider: NetworkSearchProvider
    private let emptyStateActions: [any CommandLensEmptyStateAction]
    private let categorySearchDebouncer = AdaptiveDebouncer()

    // MARK: - Constants

    private enum Constants {
        static let networkDebounceInterval: Duration = .milliseconds(300)
    }

    // MARK: - Initialization

    init(
        tabManager: TabManager,
        historyManager: HistoryManager,
        windowState: WindowState,
        browserSettings: BrowserSettings,
        siteSettingsManager: SiteSettingsManager,
        downloadManager: DownloadManager,
        referencePaneManager: ReferencePaneManager,
        agentChatManager: AgentChatManager,
        extensionManager: ExtensionManager,
        customSearchEngineManager: CustomSearchEngineManager,
    ) {
        self.tabManager = tabManager
        self.historyManager = historyManager
        self.windowState = windowState
        self.browserSettings = browserSettings
        self.siteSettingsManager = siteSettingsManager
        self.downloadManager = downloadManager
        self.referencePaneManager = referencePaneManager
        self.agentChatManager = agentChatManager
        self.extensionManager = extensionManager
        self.customSearchEngineManager = customSearchEngineManager

        // Initialize providers
        self.suggestionProviders = [
            SettingsControlProvider(settings: browserSettings),
            SiteControlProvider(siteSettingsManager: siteSettingsManager, browserSettings: browserSettings),
            ExtensionControlProvider(extensionManager: extensionManager),
            OpenTabsProvider(tabManager: tabManager),
            SearchEngineProvider(customSearchEngineManager: customSearchEngineManager),
            BaseDomainSynthesisProvider(frequentDestinations: historyManager.frequentDestinations),
            HistoryProvider(historyManager: historyManager),
            PopularWebsitesProvider(frequentDestinations: historyManager.frequentDestinations),
            ActionsProvider(),
        ]

        self.networkProvider = NetworkSearchProvider()

        self.emptyStateActions = [
            RecentlyClosedEmptyStateAction(),
            OpenTabsEmptyStateAction(),
            RecentPagesEmptyStateAction(),
            ExpandedModeEmptyStateAction(),
        ]
    }
    
    func setup() {
        updateAvailableEmptyStateActions()
    }

    // MARK: - Input Handling

    /// Reacts to user typing in the command lens.
    ///
    /// Cancels any ongoing fetch, queries all suggestion providers concurrently,
    /// and updates the UI with merged results sorted by priority.
    ///
    /// If a category button is selected when typing starts, enters category search mode.
    /// In category search mode, only searches within the selected category.
    func onInputChanged(_ text: String) {
        inputText = text

        searchTask?.cancel()

        // If a category button is selected and user starts typing, enter category search mode
        if hasCategorySelection, !text.isEmpty {
            if let mode = categoryModeForSelectedButton() {
                enterCategorySearchMode(mode)
                // Don't return - let handleCategorySearchInput process the text
            }
        }

        // Hide category buttons when user starts typing (if not entering category mode)
        if showCategoryButtons, categorySearchMode == nil {
            showCategoryButtons = false
            expandedSelection = -1
        }

        // Handle category search mode
        if let mode = categorySearchMode {
            handleCategorySearchInput(text, mode: mode)
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            isPopupVisible = false
            suggestions = []
            inlineCompletion = nil
            inlineCompletionRange = nil
            updateAvailableEmptyStateActions()
            return
        }

        isPopupVisible = true
        isLoading = true

        searchTask = Task { [weak self] in
            guard let self else { return }

            let context = createContext()

            // Query all local providers concurrently
            let allSuggestions = await fetchLocalSuggestions(context: context)

            if Task.isCancelled { return }

            // Calculate inline completion from local results
            calculateInlineCompletion(for: text, from: allSuggestions)

            // Sort suggestions with heuristics (URL nav first, search second, then rest)
            suggestions = sortSuggestionsWithHeuristics(allSuggestions)
            isLoading = false
            selection = suggestions.isEmpty ? .none : CommandLensSelection(index: 0)

            // Skip network search for direct URLs
            guard !context.isDirectURL else { return }

            // Debounce network request
            try await Task.sleep(for: Constants.networkDebounceInterval)

            // Fetch network suggestions
            guard networkProvider.shouldProvide(for: context) else { return }

            let networkSuggestions = await networkProvider.suggestions(for: context)

            if Task.isCancelled { return }

            if !networkSuggestions.isEmpty {
                suggestions.append(contentsOf: networkSuggestions)
            }
        }
    }

    // MARK: - Empty State Actions

    /// Handles an arrow key press when input is empty.
    ///
    /// - Parameter direction: The arrow key direction.
    /// - Returns: `true` if the action was handled.
    func handleEmptyStateAction(direction: EmptyStateDirection) async -> Bool {
        guard inputText.isEmpty else { return false }

        // Handle navigation when category buttons are visible
        if showCategoryButtons {
            switch direction {
            case .right:
                if expandedSelection < 0 {
                    // No selection yet - select first button
                    expandedSelection = 0
                } else {
                    // Move selection right with wrapping
                    let buttonCount = expandedModeButtons.count
                    expandedSelection = (expandedSelection + 1) % buttonCount
                }
                return true

            case .left:
                if expandedSelection > 0 {
                    // Move selection left
                    expandedSelection -= 1
                    return true
                } else if expandedSelection == 0 {
                    // At first button - deselect (back to text field)
                    expandedSelection = -1
                    return true
                }
                // No selection - hide buttons and fall through to execute left action
                showCategoryButtons = false
                expandedSelection = -1
                // Continue below to execute the left arrow action

            case .up, .down:
                // Hide category buttons and continue to execute action
                showCategoryButtons = false
                expandedSelection = -1
                // Continue below to execute the up/down action
            }
        }

        // Right arrow shows buttons and selects first
        if direction == .right {
            enterExpandedMode()
            hadUserInteraction = true
            return true
        }

        guard let action = availableEmptyStateActions[direction],
              action.isAvailable(context: createEmptyStateContext()) else {
            return false
        }

        let result = await action.execute(context: createEmptyStateContext())

        switch result {
        case let .showSuggestions(newSuggestions):
            suggestions = newSuggestions
            isPopupVisible = true
            selection = newSuggestions.isEmpty ? .none : CommandLensSelection(index: 0)
            hadUserInteraction = true
            return true

        case let .navigate(url):
            navigateToURL(url, makeActive: true)
            reset()
            return true

        case let .switchToTab(tabID):
            if let tab = tabManager.state.tab(for: tabID) {
                tabManager.setActiveTab(tab, in: windowState)
                closeCurrentLens()
                reset()
            }
            return true

        case .dismiss:
            closeCurrentLens()
            reset()
            return true

        case .none:
            return false
        }
    }

    // MARK: - Expanded Mode

    /// Shows category buttons without selecting any (for discoverability).
    ///
    /// Called automatically 2 seconds after the lens appears if the user hasn't typed.
    /// Buttons are visible but no selection - cursor remains in text field.
    ///
    /// Does nothing if the user has already interacted (typing, arrow keys showing suggestions).
    func showCategoryButtonsForDiscoverability() {
        // Don't show buttons if user has already interacted
        guard !hadUserInteraction else { return }
        // Don't show buttons if suggestions are already visible
        guard !isPopupVisible || suggestions.isEmpty else { return }

        showCategoryButtons = true
        expandedSelection = -1 // No selection yet
        isPopupVisible = false
        suggestions = []
    }

    /// Enters expanded mode with the first button selected.
    ///
    /// Called when user presses right arrow to navigate to buttons.
    func enterExpandedMode() {
        showCategoryButtons = true
        expandedSelection = 0
        isPopupVisible = false
        suggestions = []
    }

    /// Exits expanded mode without performing any action.
    func exitExpandedMode() {
        showCategoryButtons = false
        expandedSelection = -1
    }

    /// Deselects the current button, returning focus to the text field.
    ///
    /// Buttons remain visible but no selection.
    func deselectCategoryButton() {
        expandedSelection = -1
    }

    /// Commits the currently selected expanded mode button.
    ///
    /// Opens the corresponding detail tray or settings window.
    /// Category search mode is entered separately when the user starts typing
    /// while a button is selected (see ``onInputChanged``).
    func commitExpandedModeSelection() {
        guard isExpandedMode else { return }

        let buttons = expandedModeButtons
        guard expandedSelection >= 0, expandedSelection < buttons.count else { return }

        let button = buttons[expandedSelection]

        switch button.action {
        case let .openDetailTray(mode):
            windowState.showDetailTray(mode)
            closeCurrentLens()
            reset()

        case .openSettingsWindow:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            closeCurrentLens()
            reset()
        }
    }

    /// Returns the category search mode for the currently selected button, if applicable.
    private func categoryModeForSelectedButton() -> CategorySearchMode? {
        guard expandedSelection >= 0, expandedSelection < expandedModeButtons.count else {
            return nil
        }

        let button = expandedModeButtons[expandedSelection]

        switch button.action {
        case let .openDetailTray(mode):
            switch mode {
            case .history: return .history
            case .bookmarks: return .bookmarks
            case .downloads: return .downloads
            default: return nil
            }
        case .openSettingsWindow:
            return .settings
        }
    }

    /// Enters category search mode for a specific category.
    ///
    /// Transforms the command lens into a category-specific search interface.
    /// The placeholder changes to indicate the mode, and input is searched
    /// within that category only.
    ///
    /// Called when user starts typing while a category button is selected.
    func enterCategorySearchMode(_ mode: CategorySearchMode) {
        categorySearchMode = mode
        showCategoryButtons = false
        expandedSelection = -1
        hadUserInteraction = true

        // For downloads, immediately show the list
        if mode == .downloads {
            Task {
                await loadDownloadsList()
            }
        }
    }

    /// Exits category search mode and returns to normal mode.
    func exitCategorySearchMode() {
        categorySearchMode = nil
        suggestions = []
        isPopupVisible = false
        selection = .none
    }

    /// Loads the downloads list for category search mode.
    private func loadDownloadsList() async {
        let downloads = downloadManager.downloads
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(20)

        suggestions = downloads.map { download in
            CommandLensSuggestion(
                type: .download(fileURL: download.finalFileURL, state: download.state),
                text: download.destinationFilename,
                description: download.state.displayName + " • " + formatFileSize(download.bytesReceived),
                iconName: iconForDownload(download),
                groupHeader: "Downloads",
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }

        isPopupVisible = !suggestions.isEmpty
        selection = suggestions.isEmpty ? .none : CommandLensSelection(index: 0)
    }

    /// Formats file size for display.
    private func formatFileSize(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// Returns appropriate icon for download based on state and file type.
    private func iconForDownload(_ download: Download) -> String {
        switch download.state {
        case .downloading, .pending:
            return "arrow.down.circle"
        case .paused:
            return "pause.circle"
        case .failed:
            return "exclamationmark.circle"
        case .completed:
            if let type = download.contentType {
                if type.conforms(to: .image) { return "photo" }
                if type.conforms(to: .movie) { return "film" }
                if type.conforms(to: .audio) { return "music.note" }
                if type.conforms(to: .pdf) { return "doc.richtext" }
                if type.conforms(to: .archive) { return "archivebox" }
            }
            return "doc"
        }
    }

    // MARK: - Category Search

    /// Handles input changes while in category search mode.
    ///
    /// Searches within the selected category (history, bookmarks, downloads, or settings)
    /// and displays results in the suggestion list.
    ///
    /// History searches use adaptive debouncing since they involve async database queries.
    /// Bookmarks, downloads, and settings are fast in-memory operations and don't need debouncing.
    private func handleCategorySearchInput(_ text: String, mode: CategorySearchMode) {
        if text.isEmpty {
            categorySearchDebouncer.cancel()
            // Show default list for the category
            switch mode {
            case .history:
                Task { await loadRecentHistory() }
            case .bookmarks:
                loadRecentBookmarks()
            case .downloads:
                Task { await loadDownloadsList() }
            case .settings:
                loadAllSettings()
            }
            return
        }

        searchTask?.cancel()

        switch mode {
        case .history:
            // History uses async database queries - use adaptive debouncing
            isLoading = true
            categorySearchDebouncer.debounce(for: text) { [weak self] in
                guard let self else { return }
                let results = await searchHistory(query: text)
                suggestions = results
                isPopupVisible = !results.isEmpty
                selection = results.isEmpty ? .none : CommandLensSelection(index: 0)
                isLoading = false
            }

        case .bookmarks, .downloads, .settings:
            // Fast in-memory searches - no debounce needed
            isLoading = true
            searchTask = Task { [weak self] in
                guard let self else { return }

                let results: [CommandLensSuggestion] = switch mode {
                case .bookmarks:
                    searchBookmarks(query: text)
                case .downloads:
                    searchDownloads(query: text)
                case .settings:
                    searchSettings(query: text)
                case .history:
                    [] // Already handled above
                }

                suggestions = results
                isPopupVisible = !results.isEmpty
                selection = results.isEmpty ? .none : CommandLensSelection(index: 0)
                isLoading = false
            }
        }
    }

    /// Loads recent history entries for display when history mode has empty input.
    private func loadRecentHistory() async {
        let entries = await historyManager.search(query: "", limit: 20)
        suggestions = entries.map { entry in
            CommandLensSuggestion(
                type: .url,
                text: entry.title ?? entry.url.absoluteString,
                description: entry.url.absoluteString,
                iconName: "clock",
                groupHeader: "Recent History",
                isRemovable: true,
                keywordAction: nil,
                url: entry.url,
            )
        }
        isPopupVisible = !suggestions.isEmpty
        selection = suggestions.isEmpty ? .none : CommandLensSelection(index: 0)
    }

    /// Searches history with the given query.
    private func searchHistory(query: String) async -> [CommandLensSuggestion] {
        let entries = await historyManager.search(query: query, limit: 20)
        return entries.map { entry in
            CommandLensSuggestion(
                type: .url,
                text: entry.title ?? entry.url.absoluteString,
                description: entry.url.absoluteString,
                iconName: "clock",
                groupHeader: "History",
                isRemovable: true,
                keywordAction: nil,
                url: entry.url,
            )
        }
    }

    /// Loads recent bookmarks for display when bookmarks mode has empty input.
    private func loadRecentBookmarks() {
        guard let bookmarksManager = tabManager.bookmarksManager else {
            suggestions = []
            isPopupVisible = false
            return
        }

        let bookmarks = bookmarksManager.search(query: "", limit: 20)
        suggestions = bookmarks.map { bookmark in
            CommandLensSuggestion(
                type: .url,
                text: bookmark.title,
                description: bookmark.url.host ?? bookmark.url.absoluteString,
                iconName: "bookmark",
                groupHeader: "Bookmarks",
                isRemovable: false,
                keywordAction: nil,
                url: bookmark.url,
            )
        }
        isPopupVisible = !suggestions.isEmpty
        selection = suggestions.isEmpty ? .none : CommandLensSelection(index: 0)
    }

    /// Searches bookmarks with the given query.
    private func searchBookmarks(query: String) -> [CommandLensSuggestion] {
        guard let bookmarksManager = tabManager.bookmarksManager else {
            return []
        }

        let bookmarks = bookmarksManager.search(query: query, limit: 20)
        return bookmarks.map { bookmark in
            CommandLensSuggestion(
                type: .url,
                text: bookmark.title,
                description: bookmark.url.host ?? bookmark.url.absoluteString,
                iconName: "bookmark",
                groupHeader: "Bookmarks",
                isRemovable: false,
                keywordAction: nil,
                url: bookmark.url,
            )
        }
    }

    /// Searches downloads with the given query.
    private func searchDownloads(query: String) -> [CommandLensSuggestion] {
        let lowercaseQuery = query.lowercased()
        let downloads = downloadManager.downloads
            .filter { $0.destinationFilename.lowercased().contains(lowercaseQuery) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(20)

        return downloads.map { download in
            CommandLensSuggestion(
                type: .download(fileURL: download.finalFileURL, state: download.state),
                text: download.destinationFilename,
                description: download.state.displayName + " • " + formatFileSize(download.bytesReceived),
                iconName: iconForDownload(download),
                groupHeader: "Downloads",
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
    }

    /// Loads all settings for display when settings mode has empty input.
    private func loadAllSettings() {
        suggestions = BrowserSettingKey.allCases.map { key in
            let meta = key.metadata
            return CommandLensSuggestion(
                type: .setting(key: key.rawValue, scope: .global),
                text: meta.displayName,
                description: meta.description,
                iconName: meta.icon,
                groupHeader: "Settings",
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
        isPopupVisible = !suggestions.isEmpty
        selection = suggestions.isEmpty ? .none : CommandLensSelection(index: 0)
    }

    /// Searches settings with the given query.
    private func searchSettings(query: String) -> [CommandLensSuggestion] {
        let lowercaseQuery = query.lowercased()

        return BrowserSettingKey.allCases
            .filter { key in
                let meta = key.metadata
                return meta.displayName.lowercased().contains(lowercaseQuery) ||
                    key.rawValue.lowercased().contains(lowercaseQuery) ||
                    meta.keywords.contains { $0.lowercased().contains(lowercaseQuery) }
            }
            .map { key in
                let meta = key.metadata
                return CommandLensSuggestion(
                    type: .setting(key: key.rawValue, scope: .global),
                    text: meta.displayName,
                    description: meta.description,
                    iconName: meta.icon,
                    groupHeader: "Settings",
                    isRemovable: false,
                    keywordAction: nil,
                    url: nil,
                )
            }
    }

    // MARK: - AI Mode

    /// Whether the AI response is actively streaming.
    var isAIStreaming: Bool {
        isAIMode && aiResponse != nil && agentChatManager.isStreaming
    }

    /// Sends the current input as an AI query via the agent chat system.
    ///
    /// The query flows through `AgentChatManager`, so the conversation is
    /// automatically available in the Reference Pane when transferring.
    func sendAIQuery() {
        let query = AIIntentDetector.extractQuery(inputText)
        guard !query.isEmpty else { return }

        guard ClaudeCredentialStore.hasCredential else {
            isAIMode = true
            aiError = "Set up Claude API key in Settings"
            return
        }

        guard !agentChatManager.isStreaming else {
            isAIMode = true
            aiError = "Agent is busy — continue in Reference Pane"
            return
        }

        isAIMode = true
        isAILoading = true
        aiQuery = query
        aiResponse = nil
        aiError = nil

        aiStreamingTask?.cancel()

        Task {
            // Ensure connection
            if !agentChatManager.connectionState.isConnected {
                await agentChatManager.connect()
            }

            // Build browser context
            let context = BrowserContextProvider.shouldIncludeContext(for: query)
                ? BrowserContextProvider.extractContext(from: windowState)
                : nil

            // Send through the agent chat pipeline
            await agentChatManager.sendMessage(query, context: context)

            // Observe streaming response
            let manager = agentChatManager
            aiStreamingTask = Task { [weak self] in
                let changes = Observations {
                    (manager.messages.count, manager.isStreaming)
                }

                for await _ in changes {
                    guard let self, isAIMode else { return }

                    // Extract latest assistant message
                    if let lastAssistant = manager.messages.last(where: { $0.role == .assistant }) {
                        let text = lastAssistant.textContent
                        if !text.isEmpty {
                            isAILoading = false
                            aiResponse = text
                        }
                    }

                    // Check for errors
                    if let chatError = manager.error {
                        isAILoading = false
                        aiError = chatError.message
                        return
                    }

                    // Streaming complete
                    if !manager.isStreaming, aiResponse != nil {
                        isAILoading = false
                        return
                    }
                }
            }
        }
    }

    /// Transfers the current AI conversation to the Reference Pane.
    ///
    /// The conversation is already in `AgentChatManager`, so no state
    /// transfer is needed — just open the pane and close the lens.
    func transferToReferencePane() {
        aiStreamingTask?.cancel()
        aiStreamingTask = nil

        // Open Reference Pane in agent chat mode if not already active
        if !windowState.isAgentChatActive {
            windowState.toggleAgentChat()
        } else if windowState.isInspectorCollapsed {
            windowState.isInspectorCollapsed = false
        }

        closeCurrentLens()
        reset()
    }

    /// Clears AI mode state without dismissing the lens.
    func clearAIState() {
        aiStreamingTask?.cancel()
        aiStreamingTask = nil
        isAIMode = false
        isAILoading = false
        aiResponse = nil
        aiError = nil
        aiQuery = nil
    }

    // MARK: - Provider Management

    private func fetchLocalSuggestions(context: SuggestionContext) async -> [CommandLensSuggestion] {
        await withTaskGroup(of: (Int, [CommandLensSuggestion]).self) { group in
            for provider in suggestionProviders where provider.shouldProvide(for: context) {
                let priority = provider.priority
                group.addTask {
                    let suggestions = await provider.suggestions(for: context)
                    return (priority, suggestions)
                }
            }

            var results: [(priority: Int, suggestions: [CommandLensSuggestion])] = []
            for await result in group {
                results.append(result)
            }

            // Sort by priority and flatten
            return results
                .sorted { $0.priority < $1.priority }
                .flatMap(\.suggestions)
        }
    }

    private func createContext() -> SuggestionContext {
        SuggestionContext(
            input: inputText,
            settings: browserSettings,
            currentTabID: windowState.activeWebPage?.id,
            selectedSearchEngine: selectedSearchEngine,
            currentURL: windowState.activePage?.url,
        )
    }

    private func createEmptyStateContext() -> EmptyStateContext {
        EmptyStateContext(
            tabManager: tabManager,
            historyManager: historyManager,
            windowState: windowState,
            settings: browserSettings,
            undoRedoManager: tabManager.undoRedoManager,
        )
    }

    private func updateAvailableEmptyStateActions() {
        let context = createEmptyStateContext()
        var actions: [EmptyStateDirection: any CommandLensEmptyStateAction] = [:]

        for action in emptyStateActions where action.isAvailable(context: context) {
            actions[action.direction] = action
        }

        availableEmptyStateActions = actions
    }

    // MARK: - Inline Completion

    /// Creates a URL navigation suggestion for the current input or inline completion.
    ///
    /// This handles two cases:
    /// 1. Inline completion: "de" → "developer.apple.com" (shows completed URL)
    /// 2. Direct URL input: "dd.com" (shows the typed URL)
    ///
    /// Returns nil if neither case applies.
    private func createURLNavigationSuggestion() -> CommandLensSuggestion? {
        // Priority 1: Inline completion URL
        if let completion = inlineCompletion,
           let url = normalizeURLString(completion) {
            return CommandLensSuggestion(
                type: .url,
                text: completion,
                description: "Go to website",
                iconName: "globe",
                groupHeader: nil,
                isRemovable: false,
                keywordAction: nil,
                url: url,
            )
        }

        // Priority 2: Direct URL input (e.g., "dd.com")
        if isValidURL(inputText),
           let url = normalizeURLString(inputText) {
            return CommandLensSuggestion(
                type: .url,
                text: inputText,
                description: url.isFileURL ? "Open local file" : "Go to website",
                iconName: url.isFileURL ? "doc" : "globe",
                groupHeader: nil,
                isRemovable: false,
                keywordAction: nil,
                url: url,
            )
        }

        return nil
    }

    /// Creates a search suggestion for the current input.
    ///
    /// Always available when there's input, allowing the user to search for their query
    /// with the current search engine.
    private func createSearchSuggestion() -> CommandLensSuggestion? {
        guard !inputText.isEmpty else { return nil }

        return CommandLensSuggestion(
            type: .search,
            text: inputText,
            description: "Search with \(currentSearchEngine.name)",
            iconName: "magnifyingglass",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )
    }

    /// Creates an "Ask Claude" suggestion when the input looks like an AI query.
    ///
    /// Shown after the search suggestion so users can choose between
    /// searching the web or asking the AI assistant.
    private func createAskAISuggestion() -> CommandLensSuggestion? {
        guard !inputText.isEmpty, isAIIntent else { return nil }

        let query = AIIntentDetector.extractQuery(inputText)
        return CommandLensSuggestion(
            type: .askAI,
            text: query,
            description: "Ask Claude",
            iconName: "sparkles",
            groupHeader: nil,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )
    }

    /// Sorts suggestions based on heuristics.
    ///
    /// Order:
    /// 1. URL navigation suggestion (from inline completion or direct URL input) - if available
    /// 2. Search suggestion for raw input - always available
    /// 3. Ask AI suggestion - when input looks like an AI query
    /// 4. All other suggestions in their original order (by provider priority)
    private func sortSuggestionsWithHeuristics(_ suggestions: [CommandLensSuggestion]) -> [CommandLensSuggestion] {
        var result: [CommandLensSuggestion] = []

        // 1. URL navigation suggestion first (if valid URL from completion or direct input)
        if let urlSuggestion = createURLNavigationSuggestion() {
            result.append(urlSuggestion)
        }

        // 2. Search suggestion second
        if let searchSuggestion = createSearchSuggestion() {
            result.append(searchSuggestion)
        }

        // 3. Ask AI suggestion (when input looks like a question/intent)
        if let aiSuggestion = createAskAISuggestion() {
            result.append(aiSuggestion)
        }

        // 4. All other suggestions in original order
        result.append(contentsOf: suggestions)

        return result
    }

    private func calculateInlineCompletion(for input: String, from suggestions: [CommandLensSuggestion]) {
        guard !input.isEmpty else {
            inlineCompletion = nil
            inlineCompletionRange = nil
            return
        }

        if let rejected = rejectedCompletion,
           input.count <= rejectedAtInputLength,
           rejected.hasPrefix(normalizeForCompletion(input)) {
            inlineCompletion = nil
            inlineCompletionRange = nil
            return
        }

        if input.count > rejectedAtInputLength {
            rejectedCompletion = nil
            rejectedAtInputLength = 0
        }

        let urlSuggestions = suggestions.filter { suggestion in
            switch suggestion.type {
            case .url, .openTab:
                let normalizedURL = normalizeForCompletion(suggestion.description)
                let normalizedInput = normalizeForCompletion(input)
                return normalizedURL.hasPrefix(normalizedInput)
            default:
                return false
            }
        }

        if let bestMatch = urlSuggestions.first {
            let completionText = normalizeForCompletion(bestMatch.description)
            let normalizedInput = normalizeForCompletion(input)

            if completionText.hasPrefix(normalizedInput) {
                inlineCompletion = completionText
                let inputLength = input.count
                let completionLength = completionText.count
                inlineCompletionRange = NSRange(location: inputLength, length: completionLength - inputLength)
                return
            }
        }

        inlineCompletion = nil
        inlineCompletionRange = nil
    }

    private func normalizeForCompletion(_ urlString: String) -> String {
        let lowercased = urlString.lowercased()
        var startIndex = lowercased.startIndex
        var endIndex = lowercased.endIndex

        if lowercased.hasPrefix("https://") {
            startIndex = lowercased.index(startIndex, offsetBy: 8)
        } else if lowercased.hasPrefix("http://") {
            startIndex = lowercased.index(startIndex, offsetBy: 7)
        }

        let afterProtocol = lowercased[startIndex...]
        if afterProtocol.hasPrefix("www.") {
            startIndex = lowercased.index(startIndex, offsetBy: 4)
        }

        if endIndex > startIndex, lowercased[lowercased.index(before: endIndex)] == "/" {
            endIndex = lowercased.index(before: endIndex)
        }

        return String(lowercased[startIndex ..< endIndex])
    }

    /// Accept the inline completion.
    func acceptInlineCompletion() {
        if let completion = inlineCompletion {
            inputText = completion
            inlineCompletion = nil
            inlineCompletionRange = nil
            onInputChanged(inputText)
        }
    }

    /// Reject the inline completion.
    func rejectInlineCompletion() {
        if let completion = inlineCompletion {
            rejectedCompletion = completion
            rejectedAtInputLength = inputText.count
        }
        inlineCompletion = nil
        inlineCompletionRange = nil
    }

    // MARK: - URL Helpers

    private func extractMultipleURLs(from input: String) -> [URL]? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let protocolPattern = /https?:\/\//
        let protocolMatches = trimmed.matches(of: protocolPattern)

        guard protocolMatches.count > 1 else {
            return nil
        }

        var urls: [URL] = []

        for (index, match) in protocolMatches.enumerated() {
            let startIndex = match.range.lowerBound
            let endIndex: String.Index = if index + 1 < protocolMatches.count {
                protocolMatches[index + 1].range.lowerBound
            } else {
                trimmed.endIndex
            }

            var urlString = String(trimmed[startIndex ..< endIndex])
            urlString = urlString.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")),
            )

            if let url = URL(string: urlString), url.host != nil {
                urls.append(url)
            }
        }

        return urls.count > 1 ? urls : nil
    }

    /// Checks if a string looks like a valid URL using PublicSuffixList.
    ///
    /// Uses proper TLD validation instead of simple regex patterns.
    /// For example, "dd.com" is valid (com is a public suffix), but
    /// "something.something" is not (something is not a public suffix).
    /// Also recognizes IP addresses (IPv4 and IPv6).
    private func isValidURL(_ string: String) -> Bool {
        // Already a full URL with scheme
        if let url = URL(string: string), url.scheme != nil, url.host != nil {
            return true
        }

        // file://, about:, and data: URLs are navigable but have no host,
        // so the host-based check above misclassifies them as searches.
        // An explicit scheme is navigation intent, never a query.
        if hasHostlessNavigableScheme(string) {
            return true
        }

        // Check if it's an IP address (with optional port)
        if isIPAddress(string) {
            return true
        }

        // Check if it's a local address (localhost, .local, private IPs)
        if isLocalAddress(string) {
            return true
        }

        // Check if it looks like a domain with a valid TLD
        return isLikelyDomain(string)
    }

    /// Checks if a string is an IP address (IPv4 or IPv6), optionally with a port.
    ///
    /// Handles formats like:
    /// - `127.0.0.1`
    /// - `127.0.0.1:8080`
    /// - `192.168.1.1:18789`
    /// - `[::1]`
    /// - `[::1]:8080`
    /// - `[2001:db8::1]:443`
    private func isIPAddress(_ string: String) -> Bool {
        // Remove any path/query for validation
        let hostPart = string.split(separator: "/").first.map(String.init) ?? string

        // IPv6 with brackets: [::1] or [::1]:8080
        if hostPart.hasPrefix("[") {
            guard let closeBracket = hostPart.firstIndex(of: "]") else { return false }
            let ipv6 = String(hostPart[hostPart.index(after: hostPart.startIndex) ..< closeBracket])
            return isValidIPv6(ipv6)
        }

        // Check for IPv4: may have port suffix
        let components = hostPart.split(separator: ":", maxSplits: 1)
        let ipPart = String(components[0])

        // Validate port if present
        if components.count == 2 {
            guard let port = Int(components[1]), port >= 1, port <= 65_535 else {
                return false
            }
        }

        return isValidIPv4(ipPart)
    }

    /// Validates an IPv4 address string.
    private func isValidIPv4(_ string: String) -> Bool {
        let octets = string.split(separator: ".")
        guard octets.count == 4 else { return false }

        for octet in octets {
            guard let value = Int(octet), value >= 0, value <= 255 else {
                return false
            }
            // Reject leading zeros (e.g., "01" or "001") except for "0" itself
            if octet.count > 1, octet.first == "0" {
                return false
            }
        }

        return true
    }

    /// Validates an IPv6 address string (without brackets).
    private func isValidIPv6(_ string: String) -> Bool {
        // Use inet_pton for proper IPv6 validation
        var addr = in6_addr()
        return string.withCString { cString in
            inet_pton(AF_INET6, cString, &addr) == 1
        }
    }

    /// Checks if a string looks like a domain with a valid public suffix.
    ///
    /// Validates that the TLD portion is a known public suffix (e.g., com, co.uk, org).
    private func isLikelyDomain(_ string: String) -> Bool {
        // Remove any path/query components for validation
        let domainPart = string.split(separator: "/").first.map(String.init) ?? string

        // Must contain at least one dot
        guard domainPart.contains(".") else { return false }

        // Split into labels
        let labels = domainPart.lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return false }

        // All labels must be valid (alphanumeric and hyphens, not starting/ending with hyphen)
        let validLabelPattern = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/
        for label in labels {
            guard label.firstMatch(of: validLabelPattern) != nil else { return false }
        }

        // Check if any suffix combination is a public suffix
        // Try from longest to shortest: co.uk, then uk
        let psl = PublicSuffixList.shared
        for i in 0 ..< labels.count - 1 {
            let suffix = labels[(i + 1)...].joined(separator: ".")
            if psl.isPublicSuffix(suffix) {
                return true
            }
        }

        return false
    }

    private func normalizeURLString(_ string: String) -> URL? {
        if let url = URL(string: string), url.scheme != nil, url.host != nil {
            return url
        }

        if hasHostlessNavigableScheme(string) {
            if let url = URL(string: string) {
                return url
            }
            // Recover file:// paths typed with unescaped spaces,
            // which make URL(string:) fail.
            if string.lowercased().hasPrefix("file://") {
                let path = String(string.dropFirst("file://".count))
                return URL(fileURLWithPath: path)
            }
            return nil
        }

        if isValidURL(string) {
            // Use http:// for localhost and private IP addresses (local dev servers)
            let scheme = isLocalAddress(string) ? "http" : "https"
            return URL(string: "\(scheme)://\(string)")
        }

        return nil
    }

    /// Whether the input starts with a navigable scheme that has no host.
    ///
    /// `URL.host` is nil for these schemes, so host-based URL validation
    /// cannot recognize them.
    private func hasHostlessNavigableScheme(_ string: String) -> Bool {
        let lowercased = string.lowercased()
        return lowercased.hasPrefix("file://")
            || lowercased.hasPrefix("about:")
            || lowercased.hasPrefix("data:")
    }

    /// Checks if a string represents a local/private network address.
    ///
    /// Returns true for:
    /// - `localhost`
    /// - `127.x.x.x` (loopback)
    /// - `10.x.x.x` (private class A)
    /// - `172.16.x.x` - `172.31.x.x` (private class B)
    /// - `192.168.x.x` (private class C)
    /// - `::1` and other IPv6 loopback/link-local
    private func isLocalAddress(_ string: String) -> Bool {
        let hostPart = string.split(separator: "/").first.map(String.init) ?? string
        let lowerHost = hostPart.lowercased()

        // localhost keyword
        if lowerHost.hasPrefix("localhost") {
            return true
        }

        // Bonjour/mDNS .local domains
        if lowerHost.hasSuffix(".local") || lowerHost.contains(".local:") {
            return true
        }

        // IPv6 in brackets
        if lowerHost.hasPrefix("[") {
            guard let closeBracket = lowerHost.firstIndex(of: "]") else { return false }
            let ipv6 = String(lowerHost[lowerHost.index(after: lowerHost.startIndex) ..< closeBracket])
            // ::1 is loopback, fe80:: is link-local
            return ipv6 == "::1" || ipv6.hasPrefix("fe80:")
        }

        // Extract IP part (remove port if present)
        let ipPart = String(hostPart.split(separator: ":", maxSplits: 1)[0])

        // Check IPv4 private ranges
        let octets = ipPart.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }

        let first = octets[0]
        let second = octets[1]

        // 127.x.x.x - loopback
        if first == 127 { return true }
        // 10.x.x.x - private class A
        if first == 10 { return true }
        // 172.16.0.0 - 172.31.255.255 - private class B
        if first == 172, second >= 16, second <= 31 { return true }
        // 192.168.x.x - private class C
        if first == 192, second == 168 { return true }

        return false
    }

    // MARK: - Search Provider Actions

    /// Select a search provider (keyword mode).
    func selectSearchProvider(_ engine: SearchEngine) {
        selectedSearchEngine = engine
        inputText = ""
        inlineCompletion = nil
        inlineCompletionRange = nil
        isPopupVisible = false
        suggestions = []
        selection = .none
    }

    /// Clear the selected search provider.
    func clearSearchProvider() {
        selectedSearchEngine = nil
        isPopupVisible = false
        suggestions = []
        selection = .none
        inlineCompletion = nil
        inlineCompletionRange = nil
    }

    /// Remove a suggestion from the list.
    func removeSuggestion(_ suggestion: CommandLensSuggestion) {
        if case .url = suggestion.type {
            Task {
                Logger.debug("Requested deletion of history entry: \(suggestion.id)", category: Logger.data)
            }
        }

        suggestions.removeAll { $0.id == suggestion.id }
        if selection.index >= suggestions.count {
            selection = suggestions.isEmpty ? .none : CommandLensSelection(index: suggestions.count - 1)
        }

        calculateInlineCompletion(for: inputText, from: suggestions)
    }

    /// Resets all state.
    func reset() {
        inputText = ""
        isPopupVisible = false
        suggestions = []
        selection = .none
        selectedSearchEngine = nil
        inlineCompletion = nil
        inlineCompletionRange = nil
        commandKeyHeldDuringCommit = false
        rejectedCompletion = nil
        rejectedAtInputLength = 0
        hoveredSuggestionID = nil
        showCategoryButtons = false
        expandedSelection = -1
        hadUserInteraction = false
        categorySearchMode = nil
        aiStreamingTask?.cancel()
        aiStreamingTask = nil
        isAIMode = false
        isAILoading = false
        aiResponse = nil
        aiError = nil
        aiQuery = nil
        searchTask?.cancel()
        searchTask = nil
        updateAvailableEmptyStateActions()
    }

    // MARK: - Keyboard Navigation

    func moveSelection(by offset: Int) {
        guard !suggestions.isEmpty else { return }

        let newIndex = (selection.index + offset + suggestions.count) % suggestions.count
        selection = CommandLensSelection(index: newIndex)
    }

    func selectNextButton() {
        if selection.index == -1 {
            if !suggestions.isEmpty {
                selection = CommandLensSelection(index: 0)
            }
            return
        }

        guard let suggestion = suggestions[safe: selection.index] else { return }

        switch selection.buttonSelection {
        case .none:
            if case .searchProvider = suggestion.type {
                selection.buttonSelection = .switchProvider
            } else if suggestion.keywordAction != nil {
                selection.buttonSelection = .keyword
            } else if suggestion.isRemovable {
                selection.buttonSelection = .remove
            }
        case .switchProvider:
            if suggestion.isRemovable {
                selection.buttonSelection = .remove
            } else {
                selection.buttonSelection = .none
            }
        case .keyword:
            if suggestion.isRemovable {
                selection.buttonSelection = .remove
            } else {
                selection.buttonSelection = .none
            }
        case .remove:
            selection.buttonSelection = .none
        }
    }

    // MARK: - Commit Actions

    /// Executes the action associated with the selected suggestion.
    ///
    /// - Parameters:
    ///   - commandKeyHeld: If `true`, the new tab will not be made active.
    ///   - optionKeyHeld: If `true`, opens the URL in a Glimpse window instead of a tab.
    func commitSelection(commandKeyHeld: Bool = false, optionKeyHeld: Bool = false) {
        commandKeyHeldDuringCommit = commandKeyHeld
        optionKeyHeldDuringCommit = optionKeyHeld

        guard selection.index != -1, let suggestion = suggestions[safe: selection.index] else {
            if !inputText.isEmpty {
                commitInput(inputText)
            }
            return
        }

        switch selection.buttonSelection {
        case .switchProvider:
            if case let .searchProvider(engine) = suggestion.type {
                selectSearchProvider(engine)
                selection.buttonSelection = .none
            }

        case .keyword:
            if let keyword = suggestion.keywordAction {
                inputText = "\(keyword) "
                inlineCompletion = nil
                inlineCompletionRange = nil
            }

        case .remove:
            removeSuggestion(suggestion)

        case .none:
            commitSuggestion(suggestion)
        }
    }

    private func commitSuggestion(_ suggestion: CommandLensSuggestion) {
        let makeActive = !commandKeyHeldDuringCommit

        switch suggestion.type {
        case let .openTab(tabID):
            if let tab = tabManager.state.tab(for: tabID) {
                if let targetPosition = windowState.layoutModeTargetPosition,
                   let activeTab = windowState.activeTab {
                    if tab.isMultiPage || tab.pages.count > 1 {
                        closeCurrentLens()
                        reset()
                        return
                    }

                    tabManager.moveTabToLayout(tab, into: activeTab, at: targetPosition)
                    windowState.layoutModeTargetPosition = nil
                } else {
                    tabManager.setActiveTab(tab, in: windowState)
                }
                closeCurrentLens()
                reset()
            }

        case let .referenceTab(tabID):
            if let tab = tabManager.state.tab(for: tabID) {
                // Open reference pane if closed
                if windowState.isInspectorCollapsed {
                    windowState.isInspectorCollapsed = false
                }
                // Activate the reference tab
                referencePaneManager.setActiveReferenceTab(tab, in: windowState)
                closeCurrentLens()
                reset()
            }

        case let .searchProvider(engine):
            selectSearchProvider(engine)

        case .url:
            if let url = suggestion.url {
                navigateToURL(url, makeActive: makeActive)
                reset()
            }

        case .search:
            if let completion = inlineCompletion {
                commitInput(completion)
            } else {
                performSearch(suggestion.text, makeActive: makeActive)
                reset()
            }

        case .richEntity:
            if let url = suggestion.url {
                navigateToURL(url, makeActive: makeActive)
                reset()
            }

        case let .recentlyClosed(index):
            tabManager.undoRedoManager.reopenClosedTab(at: index)
            closeCurrentLens()
            reset()

        case let .setting(key, scope):
            // Toggle the setting and refresh suggestions (stay open)
            switch scope {
            case .global:
                if key.hasPrefix("ext:") {
                    let uuidString = String(key.dropFirst(4))
                    if let uuid = UUID(uuidString: uuidString),
                       let ext = extensionManager.installedExtensions.first(where: { $0.id == uuid }) {
                        Task {
                            if ext.isEnabled {
                                try? await extensionManager.disable(ext)
                            } else {
                                try? await extensionManager.enable(ext)
                            }
                        }
                    }
                } else if let settingKey = BrowserSettingKey(rawValue: key) {
                    settingKey.toggle(in: browserSettings)
                }
            case let .perSite(domain):
                if let definition = SiteSettingDefinition.find(key: key) {
                    let siteSettings = siteSettingsManager.settingsOrCreate(for: domain)
                    definition.toggle(siteSettings)
                }
            }
            // Refresh suggestions to show updated value
            onInputChanged(inputText)

        case let .download(fileURL, state):
            // Reveal completed downloads in Finder
            if state == .completed {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } else {
                // For in-progress downloads, open downloads window
                NSApp.typedDelegate.downloadsWindowController.showWindow()
            }
            closeCurrentLens()
            reset()

        case .askAI:
            sendAIQuery()

        case let .appAction(action):
            switch action {
            case .feedback:
                NSApp.typedDelegate.feedbackWindowController.showWindow()
            case .checkForUpdates:
                Task {
                    await NSApp.typedDelegate.appUpdateManager.checkForUpdates(manual: true)
                }
            case .importBrowserData:
                windowState.showsBrowserImport = true
            case .openPasswords:
                NSApp.typedDelegate.passwordsWindowController.showWindow()
            }
            closeCurrentLens()
            reset()
        }
    }

    private func commitInput(_ input: String) {
        let makeActive = !commandKeyHeldDuringCommit
        let finalInput = inlineCompletion ?? input

        if let multipleURLs = extractMultipleURLs(from: finalInput) {
            navigateToMultipleURLs(multipleURLs, makeActive: makeActive)
            reset()
            return
        }

        if let url = normalizeURLString(finalInput) {
            navigateToURL(url, makeActive: makeActive)
        } else {
            performSearch(finalInput, makeActive: makeActive)
        }
        reset()
    }

    // MARK: - Navigation

    /// Whether the command lens is in address bar mode (navigate current tab, not create new).
    private var isAddressMode: Bool {
        windowState.showsAddressLens
    }

    /// Whether the command lens is in reference pane address mode.
    /// This is when the reference pane lens is shown but NOT for creating a new tab
    /// (i.e., opened from the address bar, not the + button).
    private var isReferencePaneAddressMode: Bool {
        windowState.showsReferencePaneLens && !windowState.isCreatingReferenceTab
    }

    private func navigateToURL(_ url: URL, makeActive: Bool) {
        // Deep links (sslError, focusBlocked) render in-tab — no special handling needed

        // Option+Enter opens in Glimpse window
        if optionKeyHeldDuringCommit {
            tabManager.windowManager.createGlimpseWindow(url: url)
            closeCurrentLens()
            return
        }

        if windowState.isCreatingReferenceTab {
            tabManager.addReferenceTab(url: url, title: url.host ?? "New Tab")
            windowState.isCreatingReferenceTab = false
        } else if let targetPosition = windowState.layoutModeTargetPosition,
                  let activeTab = windowState.activeTab {
            let newPage = tabManager.addPageToTab(activeTab, url: url, at: targetPosition)
            newPage.title = url.host ?? "New Page"
            windowState.layoutModeTargetPosition = nil
        } else if isReferencePaneAddressMode,
                  let refTab = windowState.activeReferenceTab,
                  let webPage = tabManager.pagePool.page(for: refTab.activePage) {
            // Navigate the current reference tab when opened from address bar
            webPage.load(url)
        } else if isAddressMode, makeActive, let activePage = windowState.activePage {
            if let webPage = tabManager.pagePool.page(for: activePage) {
                webPage.load(url)
            }
        } else {
            tabManager.createTab(url: url, makeActive: makeActive, loadImmediately: true)
        }
        closeCurrentLens()
    }

    private func navigateToMultipleURLs(_ urls: [URL], makeActive: Bool) {
        if isReferencePaneAddressMode,
           let firstURL = urls.first,
           let refTab = windowState.activeReferenceTab,
           let webPage = tabManager.pagePool.page(for: refTab.activePage) {
            // Navigate the current reference tab with first URL
            webPage.load(firstURL)
            // Additional URLs create main tabs
            for url in urls.dropFirst() {
                tabManager.createTab(url: url, makeActive: false, loadImmediately: true)
            }
        } else if isAddressMode, makeActive, let firstURL = urls.first, let activePage = windowState.activePage {
            if let webPage = tabManager.pagePool.page(for: activePage) {
                webPage.load(firstURL)
            }
            for url in urls.dropFirst() {
                tabManager.createTab(url: url, makeActive: false, loadImmediately: true)
            }
        } else {
            for (index, url) in urls.enumerated() {
                tabManager.createTab(url: url, makeActive: makeActive && index == 0, loadImmediately: true)
            }
        }
        closeCurrentLens()
    }

    private func performSearch(_ query: String, makeActive: Bool) {
        let searchEngine = currentSearchEngine
        guard let url = searchEngine.searchURL(for: query) else { return }

        // Option+Enter opens in Glimpse window
        if optionKeyHeldDuringCommit {
            tabManager.windowManager.createGlimpseWindow(url: url)
            closeCurrentLens()
            return
        }

        if windowState.isCreatingReferenceTab {
            tabManager.addReferenceTab(url: url, title: query)
            windowState.isCreatingReferenceTab = false
        } else if let targetPosition = windowState.layoutModeTargetPosition,
                  let activeTab = windowState.activeTab {
            let newPage = tabManager.addPageToTab(activeTab, url: url, at: targetPosition)
            newPage.title = query
            windowState.layoutModeTargetPosition = nil
        } else if isReferencePaneAddressMode,
                  let refTab = windowState.activeReferenceTab,
                  let webPage = tabManager.pagePool.page(for: refTab.activePage) {
            // Navigate the current reference tab when opened from address bar
            webPage.load(url)
        } else if isAddressMode, makeActive, let activePage = windowState.activePage {
            if let webPage = tabManager.pagePool.page(for: activePage) {
                webPage.load(url)
            }
        } else {
            tabManager.createTab(url: url, makeActive: makeActive, loadImmediately: true)
        }
        closeCurrentLens()
    }

    private func closeCurrentLens() {
        // Clear contextual creation flags
        windowState.isCreatingReferenceTab = false
        windowState.layoutModeTargetPosition = nil

        if windowState.showsCommandLens {
            windowState.closeCommandLens()
        }
        if windowState.showsAddressLens {
            windowState.closeAddressLens()
        }
        if windowState.showsReferencePaneLens {
            windowState.closeReferencePaneLens()
        }
    }
}

// MARK: - Category Search Mode

/// Mode for searching within a specific category.
///
/// Entered when the user starts typing while a category button is selected.
/// The command lens transforms into a category-specific search interface.
enum CategorySearchMode: Equatable, Sendable {
    /// Search within browsing history.
    case history

    /// Search within bookmarks.
    case bookmarks

    /// Show downloads list (search filters by filename).
    case downloads

    /// Search within browser settings.
    case settings
}
