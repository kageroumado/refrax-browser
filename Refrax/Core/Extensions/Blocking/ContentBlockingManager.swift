import Foundation

/// Owns Shields' filter lists and builds: which lists are on, their downloaded text, the
/// resources file, and the last good build.
///
/// - Lists are fetched on their own schedule (``checkAndUpdateIfNeeded()``, from
///   `ScheduledTasksManager`) and cached as text in `Filters/<id>.txt`.
/// - The enabled lists build together, as one union (``ShieldsCompiler``): an exception in any
///   list lifts a block from any other, in both engines.
/// - A build is keyed by its inputs (``ShieldsKey``), so an unchanged launch compiles nothing.
/// - A failed fetch keeps the list's previous text; a failed build keeps the previous build
///   attached. Neither blocks launch: ``start(onChange:onBuild:)`` returns once the cached
///   build is published, and fetching and building continue in the background.
nonisolated enum ShieldsListError: LocalizedError {
    case insecureURL

    var errorDescription: String? {
        switch self {
        case .insecureURL: "Filter lists must be served over HTTPS."
        }
    }
}

actor ContentBlockingManager {
    private enum Constants {
        /// How long list changes settle before a rebuild, so toggling several lists builds once.
        static let rebuildDelay: Duration = .seconds(2)
        static let requestTimeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 120
        /// Larger downloads are not filter lists.
        static let maximumListBytes = 32 * 1_024 * 1_024
    }

    /// What the store shows.
    nonisolated struct Snapshot: Sendable {
        var lists: [FilterListSource]
        var artifacts: ShieldsArtifacts?
        var isUpdating: Bool
        var lastUpdate: Date?
        var lastError: String?
    }

    private let storageDirectory: URL
    private let urlSession: URLSession
    private let compiler = ShieldsCompiler()

    private(set) var filterLists: [FilterListSource] = []
    private(set) var artifacts: ShieldsArtifacts?
    /// The engine of ``artifacts`` with rule text, loaded on first use.
    private var engine: ShieldsEngine?
    private var isUpdating = false
    private var lastUpdate: Date?
    private var lastError: String?
    private var isStarted = false

    private var rebuildTask: Task<Void, Never>?
    private var onChange: (@MainActor @Sendable (Snapshot) -> Void)?
    private var onBuild: (@MainActor @Sendable (ShieldsArtifacts) async -> Void)?

    private var filterListsFile: URL {
        storageDirectory.appending(path: "filter-lists.json")
    }

    private var buildsDirectory: URL {
        storageDirectory.appending(path: "shields", directoryHint: .isDirectory)
    }

    private var resourcesDirectory: URL {
        storageDirectory.appending(path: "resources", directoryHint: .isDirectory)
    }

    init(storageDirectory: URL = Directories.appStorage.appending(path: "Filters", directoryHint: .isDirectory)) {
        self.storageDirectory = storageDirectory
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.requestTimeout
        configuration.timeoutIntervalForResource = Constants.resourceTimeout
        configuration.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Starting

    /// Publishes the cached build (compiling it first only when no build matches the cached
    /// lists), then fetches missing and stale lists in the background.
    ///
    /// - Parameters:
    ///   - onChange: Receives the state after every change.
    ///   - onBuild: Installs a new build; called once per build that differs from the last.
    func start(
        onChange: @escaping @MainActor @Sendable (Snapshot) -> Void,
        onBuild: @escaping @MainActor @Sendable (ShieldsArtifacts) async -> Void,
    ) async {
        guard !isStarted else { return }
        isStarted = true
        self.onChange = onChange
        self.onBuild = onBuild
        filterLists = loadFilterLists()
        saveFilterLists()
        await rebuild()
        Task(name: "Shields list refresh") { await self.updateFilterLists(force: false) }
    }

    // MARK: - Lists

    func setFilterListEnabled(_ id: String, enabled: Bool) async {
        guard let index = filterLists.firstIndex(where: { $0.id == id }) else { return }
        filterLists[index].isEnabled = enabled
        saveFilterLists()
        await publish()
        if enabled, cachedText(for: id) == nil {
            await fetch(filterLists[index])
        }
        scheduleRebuild()
    }

    /// Subscribes to a list at an HTTPS `url`; nil for any other URL.
    ///
    /// - Parameter allowsScriptlets: Whether the list may run scriptlets in pages.
    @discardableResult
    func addCustomFilterList(name: String, url: URL, allowsScriptlets: Bool = false) async -> FilterListSource? {
        var source = FilterListSource(
            id: "custom-\(UUID().uuidString.prefix(8).lowercased())",
            name: name,
            url: url,
            category: .custom,
            isEnabled: true,
            updateFrequency: FilterListSource.dailyUpdates,
        )
        source.allowsScriptlets = allowsScriptlets
        guard source.isFetchable else { return nil }
        filterLists.append(source)
        saveFilterLists()
        await publish()
        await fetch(source)
        scheduleRebuild()
        return source
    }

    func removeCustomFilterList(_ id: String) async {
        guard let index = filterLists.firstIndex(where: { $0.id == id && $0.category == .custom }) else { return }
        filterLists.remove(at: index)
        saveFilterLists()
        try? FileManager.default.removeItem(at: textURL(for: id))
        await publish()
        scheduleRebuild()
    }

    // MARK: - Updating

    /// Fetches the enabled lists that are due (all of them when `force`) and the resources
    /// file, then rebuilds if anything changed.
    func updateFilterLists(force: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        await publish()
        let now = Date.now
        var changed = false
        for list in filterLists where list.isEnabled {
            let isDue = list.lastUpdated.map { now.timeIntervalSince($0) >= list.updateFrequency } ?? true
            if force || isDue || cachedText(for: list.id) == nil {
                changed = await fetch(list) || changed
            }
        }
        if let refreshed = try? await ShieldsResources.refresh(into: resourcesDirectory) {
            changed = refreshed || changed
        }
        lastUpdate = .now
        isUpdating = false
        await publish()
        if changed {
            await rebuild()
        }
    }

    /// The scheduled check (`ScheduledTasksManager`): fetches only what is due.
    func checkAndUpdateIfNeeded() async {
        await updateFilterLists(force: false)
    }

    /// Downloads `list` and caches its text. A failed or implausible download keeps the
    /// previous text.
    ///
    /// - Returns: Whether the cached text changed.
    @discardableResult
    private func fetch(_ list: FilterListSource) async -> Bool {
        do {
            guard list.isFetchable else {
                throw ShieldsListError.insecureURL
            }
            let (data, response) = try await urlSession.data(from: list.url)
            guard response.url?.scheme?.lowercased() == "https" else {
                throw ShieldsListError.insecureURL
            }
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard data.count <= Constants.maximumListBytes,
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
            else { throw URLError(.cannotDecodeContentData) }
            let previous = cachedText(for: list.id)
            if previous != data {
                try data.write(to: textURL(for: list.id), options: .atomic)
            }
            if let index = filterLists.firstIndex(where: { $0.id == list.id }) {
                filterLists[index].lastUpdated = .now
                filterLists[index].lastError = nil
                saveFilterLists()
            }
            return previous != data
        } catch {
            Logger.warning("Shields could not fetch \(list.id): \(error.localizedDescription)", category: Logger.network)
            if let index = filterLists.firstIndex(where: { $0.id == list.id }) {
                filterLists[index].lastError = error.localizedDescription
                saveFilterLists()
            }
            return false
        }
    }

    // MARK: - Building

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task(name: "Shields rebuild") {
            try? await Task.sleep(for: Constants.rebuildDelay)
            guard !Task.isCancelled else { return }
            await self.rebuild()
        }
    }

    /// Builds the enabled lists (or finds the build on disk) and hands a new build to
    /// `onBuild`. On failure the previous build stays.
    private func rebuild() async {
        let lists = filterLists.filter(\.isEnabled).compactMap { source in
            cachedText(for: source.id).flatMap { Self.shieldsList(for: source, text: $0) }
        }
        guard !lists.isEmpty else {
            lastError = filterLists.contains(where: \.isEnabled) ? "No filter list has been downloaded yet." : nil
            await publish()
            return
        }
        let resources = ShieldsResources.current(in: resourcesDirectory)
        do {
            let (built, engine) = try await compiler.build(lists: lists, resources: resources, into: buildsDirectory)
            guard built.key != artifacts?.key else { return }
            artifacts = built
            self.engine = engine
            lastError = nil
            for list in built.manifest.lists {
                if let index = filterLists.firstIndex(where: { $0.id == list.id }) {
                    filterLists[index].ruleCount = list.stats.network + list.stats.cosmetic
                }
            }
            saveFilterLists()
            await publish()
            await onBuild?(built)
            Logger.info(
                "Shields build \(built.key.shortForm): \(lists.count) lists in \(String(format: "%.2f", built.manifest.buildSeconds)) s",
                category: Logger.tabs,
            )
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
            await publish()
            Logger.error("Shields build failed, keeping the previous build: \(error)", category: Logger.tabs)
        }
    }

    /// What a build reads from `source`: nothing from a list not fetched over HTTPS, and no
    /// scriptlets from a custom list the user did not trust.
    static func shieldsList(for source: FilterListSource, text: Data) -> ShieldsList? {
        guard source.isFetchable else { return nil }
        let text = source.contributesScriptlets ? text : ShieldsList.removingScriptlets(from: text)
        return ShieldsList(id: source.id, text: text, isTrusted: source.isTrusted)
    }

    // MARK: - Engine

    /// The current build's engine with rule text, for the request logger and `explain`.
    func debugEngine() async -> ShieldsEngine? {
        if let engine {
            return engine
        }
        guard let artifacts else { return nil }
        let engine = await Self.loadEngine(artifacts)
        if artifacts.key == self.artifacts?.key {
            self.engine = engine
        }
        return engine
    }

    @concurrent
    private static func loadEngine(_ artifacts: ShieldsArtifacts) async -> ShieldsEngine? {
        guard let dat = try? Data(contentsOf: artifacts.debugEngineURL),
              let resources = try? Data(contentsOf: artifacts.resourcesURL)
        else { return nil }
        return try? ShieldsEngine(dat: dat, resources: resources)
    }

    // MARK: - Persistence

    private func textURL(for id: String) -> URL {
        storageDirectory.appending(path: "\(id).txt")
    }

    private func cachedText(for id: String) -> Data? {
        try? Data(contentsOf: textURL(for: id))
    }

    private func loadFilterLists() -> [FilterListSource] {
        let saved = (try? Data(contentsOf: filterListsFile))
            .flatMap { try? JSONDecoder().decode([FilterListSource].self, from: $0) } ?? []
        return FilterListSource.reconciled(saved)
    }

    private func saveFilterLists() {
        do {
            try JSONEncoder().encode(filterLists).write(to: filterListsFile, options: .atomic)
        } catch {
            Logger.error("Failed to save filter lists: \(error)", category: Logger.tabs)
        }
    }

    private func publish() async {
        let snapshot = Snapshot(
            lists: filterLists,
            artifacts: artifacts,
            isUpdating: isUpdating,
            lastUpdate: lastUpdate ?? filterLists.compactMap(\.lastUpdated).max(),
            lastError: lastError,
        )
        await onChange?(snapshot)
    }
}
