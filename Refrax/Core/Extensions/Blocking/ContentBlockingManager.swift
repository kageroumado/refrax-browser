import Foundation
import WebKit

/// Manages content blocking via WebKit content rules.
///
/// This manager handles:
/// - Fetching filter lists from URLs (EasyList, EasyPrivacy, etc.)
/// - Parsing AdBlock Plus / uBlock filter syntax
/// - Compiling rules to WebKit content rule format
/// - Applying rules to WKUserContentController
/// - Updating rules on a schedule
///
/// ## Architecture
///
/// Content blocking uses a dual-path system:
/// - **Network blocking**: Handled by this manager via WKContentRuleList
/// - **Cosmetic filtering**: Handled by uBlock Origin extension via content scripts
///
/// This separation allows us to leverage WebKit's efficient native blocking
/// while still getting uBlock's advanced cosmetic and scriptlet features.
///
/// ## Usage
///
/// ```swift
/// let manager = ContentBlockingManager()
/// await manager.setup(userContentController: controller)
///
/// // Later: trigger manual update
/// await manager.updateFilterLists()
/// ```
actor ContentBlockingManager {
    // MARK: - Constants

    /// Maximum chunks to clean up per filter list during reset.
    private static let maxChunksPerList = 10

    // MARK: - Storage

    /// Directory for storing filter lists and compiled rules.
    private let storageDirectory: URL

    /// File for persisting filter list metadata.
    private var filterListsFile: URL {
        storageDirectory.appendingPathComponent("filter-lists.json")
    }

    // MARK: - State

    /// Current filter list sources.
    private(set) var filterLists: [FilterListSource] = []

    /// Compiled WebKit rule lists (keyed by filter list ID + chunk index).
    private var compiledRuleLists: [String: WKContentRuleList] = [:]

    /// Whether initial setup has completed.
    private var isSetUp = false

    /// Closure to add rule lists (runs on MainActor).
    private var addRuleList: (@MainActor (WKContentRuleList) -> Void)?

    /// Closure to remove rule lists (runs on MainActor).
    private var removeRuleList: (@MainActor (WKContentRuleList) -> Void)?

    // MARK: - Dependencies

    private let parser = FilterParser()
    private let compiler = WebKitRuleCompiler()
    private let urlSession: URLSession

    // MARK: - Update Scheduling

    /// Tracks whether an update is currently in progress.
    private var isUpdating = false

    // MARK: - Statistics

    /// Total number of active blocking rules.
    private(set) var totalRuleCount: Int = 0

    /// Timestamp of last successful update.
    private(set) var lastUpdateTime: Date?

    // MARK: - Initialization

    init() {
        // Create storage directory
        self.storageDirectory = Directories.appStorage.appendingPathComponent("Filters", isDirectory: true)

        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        // Configure URL session for filter fetching
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Setup

    /// Performs initial setup of content blocking.
    ///
    /// - Parameter userContentController: The controller to add rules to.
    func setup(userContentController: WKUserContentController) async {
        guard !isSetUp else { return }
        isSetUp = true

        // Capture the controller in closures for MainActor-safe access
        addRuleList = { @MainActor [weak userContentController] ruleList in
            userContentController?.add(ruleList)
        }
        removeRuleList = { @MainActor [weak userContentController] ruleList in
            userContentController?.remove(ruleList)
        }

        // Load persisted filter list state
        await loadFilterListState()

        // If no lists configured, use defaults
        if filterLists.isEmpty {
            filterLists = FilterListSource.defaultLists
            saveFilterListState()
        }

        // Load cached compiled rules or compile from cached filter data
        await loadOrCompileRules()

        Logger.info("ContentBlockingManager setup complete (\(totalRuleCount) rules)", category: Logger.tabs)
    }

    // MARK: - Filter List Management

    /// Enables or disables a filter list.
    ///
    /// - Parameters:
    ///   - id: The filter list identifier.
    ///   - enabled: Whether to enable the list.
    func setFilterListEnabled(_ id: String, enabled: Bool) async {
        guard let index = filterLists.firstIndex(where: { $0.id == id }) else { return }

        filterLists[index].isEnabled = enabled
        saveFilterListState()

        if enabled {
            // Fetch and compile the list
            await updateFilterList(filterLists[index])
        } else {
            // Remove compiled rules for this list
            await removeCompiledRules(forListID: id)
        }
    }

    /// Adds a custom filter list.
    ///
    /// - Parameters:
    ///   - name: Display name for the list.
    ///   - url: URL to fetch the filter list from.
    /// - Returns: The created filter list source.
    func addCustomFilterList(name: String, url: URL) async -> FilterListSource {
        let id = "custom-\(UUID().uuidString.prefix(8))"
        let source = FilterListSource(
            id: id,
            name: name,
            url: url,
            category: .custom,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        )

        filterLists.append(source)
        saveFilterListState()

        await updateFilterList(source)

        return source
    }

    /// Removes a custom filter list.
    ///
    /// - Parameter id: The filter list identifier.
    func removeCustomFilterList(_ id: String) async {
        guard let index = filterLists.firstIndex(where: { $0.id == id && $0.category == .custom }) else { return }

        await removeCompiledRules(forListID: id)

        filterLists.remove(at: index)
        saveFilterListState()

        // Delete cached filter data
        let cacheFile = storageDirectory.appendingPathComponent("\(id).txt")
        try? FileManager.default.removeItem(at: cacheFile)
    }

    // MARK: - Update

    /// Updates all enabled filter lists.
    func updateFilterLists() async {
        Logger.info("Starting filter list update", category: Logger.tabs)

        for list in filterLists where list.isEnabled {
            await updateFilterList(list)
        }

        lastUpdateTime = Date()
        Logger.info("Filter list update complete (\(totalRuleCount) rules)", category: Logger.tabs)
    }

    /// Updates a single filter list.
    private func updateFilterList(_ list: FilterListSource) async {
        guard list.isEnabled else { return }

        Logger.debug("Updating filter list: \(list.name)", category: Logger.tabs)

        // Fetch filter list
        guard let content = await fetchFilterList(list) else {
            Logger.warning("Failed to fetch filter list: \(list.name)", category: Logger.tabs)
            return
        }

        // Cache the raw content
        cacheFilterContent(content, forListID: list.id)

        // Parse and compile
        await compileAndApplyRules(content: content, listID: list.id)

        // Update metadata
        if let index = filterLists.firstIndex(where: { $0.id == list.id }) {
            filterLists[index].lastUpdated = Date()
            saveFilterListState()
        }
    }

    // MARK: - Fetching

    private func fetchFilterList(_ list: FilterListSource) async -> String? {
        do {
            let (data, response) = try await urlSession.data(from: list.url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else {
                return nil
            }

            return String(data: data, encoding: .utf8)
        } catch {
            Logger.error("Failed to fetch \(list.url): \(error)", category: Logger.tabs)
            return nil
        }
    }

    // MARK: - Caching

    private func cacheFilterContent(_ content: String, forListID id: String) {
        let file = storageDirectory.appendingPathComponent("\(id).txt")
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    private func loadCachedFilterContent(forListID id: String) -> String? {
        let file = storageDirectory.appendingPathComponent("\(id).txt")
        return try? String(contentsOf: file, encoding: .utf8)
    }

    // MARK: - Compilation

    private func compileAndApplyRules(content: String, listID: String) async {
        // Remove existing rules for this list
        await removeCompiledRules(forListID: listID)

        // Parse filter rules (network + cosmetic)
        let parseResult = parser.parse(content)
        let totalRules = parseResult.networkRules.count + parseResult.cosmeticRules.count
        Logger.debug(
            "Parsed \(parseResult.networkRules.count) network + \(parseResult.cosmeticRules.count) cosmetic rules from \(listID)",
            category: Logger.tabs,
        )

        // Compile to WebKit format (in chunks)
        let chunks = compiler.compileInChunks(parseResult)

        // Compile each chunk, tracking success/failure
        var compiledChunks = 0
        var failedChunks = 0

        for (chunkIndex, chunk) in chunks.enumerated() {
            let identifier = "\(listID)-\(chunkIndex)"

            do {
                if let ruleList = try await Self.compileOnMainActor(json: chunk, identifier: identifier) {
                    compiledRuleLists[identifier] = ruleList
                    await addRuleList?(ruleList)
                    compiledChunks += 1
                }
            } catch {
                failedChunks += 1
                Logger.error("Failed to compile chunk \(chunkIndex) for \(listID): \(error)", category: Logger.tabs)
            }
        }

        // Update metadata
        if let index = filterLists.firstIndex(where: { $0.id == listID }) {
            filterLists[index].ruleCount = totalRules
            filterLists[index].chunkCount = chunks.count
            saveFilterListState()
        }

        recalculateTotalRuleCount()

        // Log with accurate success/failure breakdown
        if failedChunks == 0 {
            Logger.info("Compiled \(totalRules) rules for \(listID) in \(compiledChunks) chunks", category: Logger.tabs)
        } else {
            Logger.warning(
                "Compiled \(totalRules) rules for \(listID): \(compiledChunks)/\(chunks.count) chunks succeeded, \(failedChunks) failed (unsupported regex patterns)",
                category: Logger.tabs,
            )
        }
    }

    @MainActor
    private static func compileOnMainActor(json: String, identifier: String) async throws -> WKContentRuleList? {
        try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: json,
        )
    }

    private func removeCompiledRules(forListID listID: String) async {
        let keysToRemove = Array(compiledRuleLists.keys.filter { $0.hasPrefix(listID) })

        for key in keysToRemove {
            if let ruleList = compiledRuleLists.removeValue(forKey: key) {
                await removeRuleList?(ruleList)
            }
        }

        // Batch remove from WebKit's persistent store (single MainActor hop)
        await Self.removeRulesOnMainActor(identifiers: keysToRemove)

        recalculateTotalRuleCount()
    }

    @MainActor
    private static func removeRulesOnMainActor(identifiers: [String]) async {
        for identifier in identifiers {
            try? await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier)
        }
    }

    private func recalculateTotalRuleCount() {
        totalRuleCount = filterLists
            .filter(\.isEnabled)
            .compactMap(\.ruleCount)
            .reduce(0, +)
    }

    // MARK: - Initial Load

    private func loadOrCompileRules() async {
        for list in filterLists where list.isEnabled {
            // Determine how many chunks to try loading (use stored count or default to max)
            let expectedChunks = list.chunkCount ?? Self.maxChunksPerList

            // Try to load all chunks from WebKit's cache
            var loadedFromCache = false
            var loadedChunks = 0

            for chunkIndex in 0 ..< expectedChunks {
                let identifier = "\(list.id)-\(chunkIndex)"
                let cached = await Self.loadCachedRuleOnMainActor(identifier: identifier)

                if let cached {
                    compiledRuleLists[identifier] = cached
                    await addRuleList?(cached)
                    loadedChunks += 1
                } else if chunkIndex == 0 {
                    // If even chunk 0 isn't cached, stop trying
                    break
                } else {
                    // No more chunks in cache
                    break
                }
            }

            if loadedChunks > 0 {
                loadedFromCache = true
                Logger.info("Loaded \(list.ruleCount ?? 0) cached rules for \(list.id) (\(loadedChunks) chunks)", category: Logger.tabs)
            }

            if loadedFromCache {
                continue
            }

            // Fall back to compiling from cached filter data
            if let content = loadCachedFilterContent(forListID: list.id) {
                await compileAndApplyRules(content: content, listID: list.id)
            } else {
                // Need to fetch fresh
                await updateFilterList(list)
            }
        }

        recalculateTotalRuleCount()
    }

    @MainActor
    private static func loadCachedRuleOnMainActor(identifier: String) async -> WKContentRuleList? {
        try? await WKContentRuleListStore.default().contentRuleList(forIdentifier: identifier)
    }

    // MARK: - Persistence

    private func loadFilterListState() async {
        let url = filterListsFile

        // Move file I/O and JSON decoding to background to avoid blocking actor
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[FilterListSource], any Error> in
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .success([])
            }
            do {
                let data = try Data(contentsOf: url)
                let lists = try JSONDecoder().decode([FilterListSource].self, from: data)
                return .success(lists)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case let .success(lists):
            if !lists.isEmpty {
                filterLists = lists
            }
        case let .failure(error):
            Logger.error("Failed to load filter list state: \(error)", category: Logger.tabs)
        }
    }

    private func saveFilterListState() {
        do {
            let data = try JSONEncoder().encode(filterLists)
            try data.write(to: filterListsFile, options: .atomic)
        } catch {
            Logger.error("Failed to save filter list state: \(error)", category: Logger.tabs)
        }
    }

    // MARK: - Scheduled Update Check

    /// Checks if any filter lists need updating and updates them if necessary.
    ///
    /// This method is designed to be called from `ScheduledTasksManager` on an hourly
    /// schedule. It checks each enabled filter list's `lastUpdated` timestamp against
    /// its configured `updateFrequency` and updates any lists that are stale.
    ///
    /// The method is idempotent and safe to call frequently - it will only perform
    /// network requests when lists actually need updating.
    func checkAndUpdateIfNeeded() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let now = Date()
        let listsToUpdate = filterLists.filter { list in
            guard list.isEnabled else { return false }
            guard let lastUpdated = list.lastUpdated else { return true }
            return now.timeIntervalSince(lastUpdated) >= list.updateFrequency
        }

        guard !listsToUpdate.isEmpty else { return }

        Logger.debug("Checking \(listsToUpdate.count) filter lists for updates", category: Logger.tabs)

        for list in listsToUpdate {
            await updateFilterList(list)
        }
    }

    // MARK: - Cleanup

    /// Removes all compiled rules and cached data.
    func reset() async {
        // Remove from content controller
        for ruleList in compiledRuleLists.values {
            await removeRuleList?(ruleList)
        }
        compiledRuleLists.removeAll()

        // Clear WebKit's cache (batched to avoid per-item MainActor dispatch)
        let identifiersToRemove = filterLists.flatMap { list in
            (0 ..< Self.maxChunksPerList).map { "\(list.id)-\($0)" }
        }
        await Self.removeRulesOnMainActor(identifiers: identifiersToRemove)

        // Clear local cache
        try? FileManager.default.removeItem(at: storageDirectory)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        // Reset to defaults
        filterLists = FilterListSource.defaultLists
        saveFilterListState()
        totalRuleCount = 0
        lastUpdateTime = nil

        addRuleList = nil
        removeRuleList = nil
        isSetUp = false
    }
}
