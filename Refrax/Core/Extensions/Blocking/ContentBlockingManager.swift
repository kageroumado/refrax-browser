import Foundation
import os

nonisolated enum ShieldsListError: LocalizedError {
    case insecureURL

    var errorDescription: String? {
        switch self {
        case .insecureURL: "Filter lists must be served over HTTPS."
        }
    }
}

/// Refuses, and cancels the fetch on, any redirect to a URL that is not HTTPS, so no hop of a
/// list download can be read or rewritten on the network.
private final nonisolated class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let refused = OSAllocatedUnfairLock(initialState: false)

    var refusedInsecureRedirect: Bool {
        refused.withLock { $0 }
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void,
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            refused.withLock { $0 = true }
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }
}

/// Owns Shields' filter lists and builds: which lists are on, their downloaded text, the
/// resources file, and the last good build.
///
/// - Lists are fetched on their own schedule (``checkAndUpdateIfNeeded()``, from
///   `ScheduledTasksManager`) and cached as text in `Filters/<id>.txt`.
/// - The enabled lists build together, as one union (``ShieldsCompiler``): an exception in any
///   list lifts a block from any other, in both engines.
/// - A build is keyed by its inputs (``ShieldsKey``), so an unchanged launch compiles nothing.
/// - A fresh install builds from snapshots of the default lists the app ships, so it filters
///   before its first download.
/// - A failed fetch keeps the list's previous text; a failed build keeps the previous build
///   attached, and a build WebKit refuses is rebuilt from scratch after a delay.
/// - At launch the build WebKit last attached is attached again before anything is built, so
///   a launch whose inputs changed filters with the previous build while the new one compiles.
actor ContentBlockingManager {
    private enum Constants {
        /// How long list changes settle before a rebuild, so toggling several lists builds once.
        static let rebuildDelay: Duration = .seconds(2)
        static let requestTimeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 120
        /// Larger downloads are not filter lists.
        static let maximumListBytes = 32 * 1_024 * 1_024
        /// The first rebuild after WebKit refused a build; each later one waits four times longer.
        static let firstRetryDelay: Duration = .seconds(30)
        static let maximumRetries = 4
        /// How long the engine with rule text stays loaded after its last use.
        static let debugEngineIdleTime: Duration = .seconds(60)
        /// Names the build WebKit last attached, by key.
        static let installedBuildName = "installed-build"
        /// `shields-list-<id>.lzma` in the app bundle: a list's text as the app shipped it.
        static let snapshotPrefix = "shields-list-"
        static let snapshotExtension = "lzma"
    }

    /// What the store shows.
    nonisolated struct Snapshot: Sendable {
        var lists: [FilterListSource]
        var artifacts: ShieldsArtifacts?
        var isUpdating: Bool
        var lastUpdate: Date?
        var lastError: String?
    }

    /// What became of a build handed to the store.
    nonisolated enum InstallResult: Sendable {
        /// WebKit attached it.
        case attached
        /// Not attached, by choice: Shields is off, or a newer build superseded it.
        case skipped
        /// WebKit could not compile a list or a file failed its check.
        case failed
    }

    private let storageDirectory: URL
    private let urlSession: URLSession
    private let bundle: Bundle
    private let compiler = ShieldsCompiler()

    private(set) var filterLists: [FilterListSource] = []
    /// The newest build: the one the other engines get.
    private(set) var artifacts: ShieldsArtifacts?
    /// The build WebKit has attached, by key; pruning keeps it.
    private(set) var installedKey: String?
    /// The engine of ``artifacts`` with rule text: kept from a fresh build or loaded on use,
    /// released after ``Constants/debugEngineIdleTime`` unused.
    private var engine: ShieldsEngine?
    private var engineRelease: Task<Void, Never>?
    /// The plain engine of ``artifacts``, for top-level document checks.
    private var navigationEngine: (key: String, task: Task<ShieldsEngine?, Never>)?
    private var isUpdating = false
    /// An "Update now" asked for while an update ran; it runs when that one ends.
    private var forcedUpdateIsQueued = false
    private var lastUpdate: Date?
    private var lastError: String?
    private var isStarted = false

    private var rebuildTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retries = 0
    private var onChange: (@MainActor @Sendable (Snapshot) -> Void)?
    private var onBuild: (@MainActor @Sendable (ShieldsArtifacts) async -> InstallResult)?

    private var filterListsFile: URL {
        storageDirectory.appending(path: "filter-lists.json")
    }

    private var installedBuildFile: URL {
        storageDirectory.appending(path: Constants.installedBuildName)
    }

    var buildsDirectory: URL {
        storageDirectory.appending(path: "shields", directoryHint: .isDirectory)
    }

    private var resourcesDirectory: URL {
        storageDirectory.appending(path: "resources", directoryHint: .isDirectory)
    }

    /// - Parameters:
    ///   - configuration: How lists are fetched; tests give one with a stub protocol.
    ///   - bundle: Where the shipped list snapshots are.
    init(
        storageDirectory: URL = Directories.appStorage.appending(path: "Filters", directoryHint: .isDirectory),
        configuration: URLSessionConfiguration = .default,
        bundle: Bundle = .main,
    ) {
        self.storageDirectory = storageDirectory
        self.bundle = bundle
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        configuration.timeoutIntervalForRequest = Constants.requestTimeout
        configuration.timeoutIntervalForResource = Constants.resourceTimeout
        configuration.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Starting

    /// Attaches the build WebKit had at the last quit, then builds the current lists (from
    /// disk when nothing changed) and fetches missing and stale lists in the background.
    ///
    /// - Parameters:
    ///   - onChange: Receives the state after every change.
    ///   - onBuild: Publishes a build and attaches it to WebKit; called once per build that
    ///     differs from the last.
    func start(
        onChange: @escaping @MainActor @Sendable (Snapshot) -> Void,
        onBuild: @escaping @MainActor @Sendable (ShieldsArtifacts) async -> InstallResult,
    ) async {
        guard !isStarted else { return }
        isStarted = true
        self.onChange = onChange
        self.onBuild = onBuild
        filterLists = loadFilterLists()
        saveFilterLists()
        if let installed = installedBuild() {
            artifacts = installed
            await publish()
            await install(installed)
        }
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
    /// file, all at once, then rebuilds if anything changed. When the shipped lists arrive
    /// before the rest, they are built without waiting for the others.
    ///
    /// A forced update asked for while one runs runs once that one ends.
    func updateFilterLists(force: Bool) async {
        guard !isUpdating else {
            forcedUpdateIsQueued = forcedUpdateIsQueued || force
            return
        }
        isUpdating = true
        await publish()
        let now = Date.now
        let due = filterLists.filter { list in
            let isStale = list.lastUpdated.map { now.timeIntervalSince($0) >= list.updateFrequency } ?? true
            return list.isEnabled && (force || isStale || cachedText(for: list.id) == nil)
        }
        let session = urlSession
        let resourcesDirectory = resourcesDirectory
        async let resourcesChanged = (try? ShieldsResources.refresh(into: resourcesDirectory)) ?? false

        var awaitedCore = Set(due.map(\.id)).intersection(FilterListSource.bundledListIDs)
        let waitsForCore = !awaitedCore.isEmpty
        var remaining = due.count
        var changed = false
        await withTaskGroup(of: (FilterListSource, Result<Data, any Error>).self) { group in
            for list in due {
                group.addTask { await (list, Self.download(list, session: session)) }
            }
            for await (list, result) in group {
                changed = store(result, for: list) || changed
                remaining -= 1
                awaitedCore.remove(list.id)
                if waitsForCore, awaitedCore.isEmpty, remaining > 0, changed {
                    changed = false
                    await rebuild()
                }
            }
        }
        changed = await resourcesChanged || changed
        lastUpdate = .now
        isUpdating = false
        await publish()
        if changed {
            await rebuild()
        }
        if forcedUpdateIsQueued {
            forcedUpdateIsQueued = false
            await updateFilterLists(force: true)
        }
    }

    /// The scheduled check (`ScheduledTasksManager`): fetches only what is due.
    func checkAndUpdateIfNeeded() async {
        await updateFilterLists(force: false)
    }

    /// Downloads `list` and caches its text.
    ///
    /// - Returns: Whether the cached text changed.
    @discardableResult
    private func fetch(_ list: FilterListSource) async -> Bool {
        await store(Self.download(list, session: urlSession), for: list)
    }

    /// Caches a download's text and records the outcome on the list. A failure keeps the
    /// previous text.
    ///
    /// - Returns: Whether the cached text changed.
    private func store(_ result: Result<Data, any Error>, for list: FilterListSource) -> Bool {
        let index = filterLists.firstIndex { $0.id == list.id }
        switch result {
        case let .success(data):
            let previous = cachedText(for: list.id)
            do {
                if previous != data {
                    try data.write(to: textURL(for: list.id), options: .atomic)
                }
            } catch {
                return store(.failure(error), for: list)
            }
            if let index {
                filterLists[index].lastUpdated = .now
                filterLists[index].lastError = nil
                saveFilterLists()
            }
            return previous != data
        case let .failure(error):
            Logger.warning("Shields could not fetch \(list.id): \(error.localizedDescription)", category: Logger.network)
            if let index {
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
    ///
    /// - Parameter reusingCache: False rebuilds and reinstalls a build already on disk.
    private func rebuild(reusingCache: Bool = true) async {
        let lists = filterLists.filter(\.isEnabled).compactMap { source in
            listText(for: source.id).flatMap { Self.shieldsList(for: source, text: $0) }
        }
        guard !lists.isEmpty else {
            lastError = filterLists.contains(where: \.isEnabled) ? "No filter list has been downloaded yet." : nil
            await publish()
            return
        }
        let resources = ShieldsResources.current(in: resourcesDirectory)
        do {
            let (built, engine) = try await compiler.build(
                lists: lists,
                resources: resources,
                into: buildsDirectory,
                reusingCache: reusingCache,
                protecting: protectedKeys,
            )
            guard !reusingCache || built.key != artifacts?.key else { return }
            if built.key != artifacts?.key {
                navigationEngine = nil
            }
            artifacts = built
            if let engine {
                keepDebugEngine(engine)
            } else {
                releaseDebugEngine()
            }
            lastError = nil
            for list in built.manifest.lists {
                if let index = filterLists.firstIndex(where: { $0.id == list.id }) {
                    filterLists[index].ruleCount = list.stats.network + list.stats.cosmetic
                }
            }
            saveFilterLists()
            await publish()
            Logger.info(
                "Shields build \(built.key.shortForm): \(lists.count) lists in \(String(format: "%.2f", built.manifest.buildSeconds)) s",
                category: Logger.tabs,
            )
            await install(built)
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
            await publish()
            Logger.error("Shields build failed, keeping the previous build: \(error)", category: Logger.tabs)
        }
    }

    /// Hands the current build to the store again (Shields turned back on).
    func reinstall() async {
        if let artifacts {
            await install(artifacts)
        }
    }

    /// Builds pruning keeps: the published and the attached ones.
    private var protectedKeys: Set<String> {
        Set([artifacts?.key.hex, installedKey].compactMap(\.self))
    }

    /// Hands `built` to the store. Once WebKit attaches it, it is the build the next launch
    /// attaches first; when WebKit refuses it, it is rebuilt from scratch after a delay.
    private func install(_ built: ShieldsArtifacts) async {
        guard let onBuild else { return }
        switch await onBuild(built) {
        case .attached:
            installedKey = built.key.hex
            retries = 0
            retryTask?.cancel()
            do {
                try built.key.hex.write(to: installedBuildFile, atomically: true, encoding: .utf8)
            } catch {
                Logger.warning("Shields could not record the attached build: \(error)", category: Logger.tabs)
            }
            Task(name: "Shields navigation engine") { _ = await self.loadedNavigationEngine() }
        case .skipped:
            return
        case .failed:
            guard built.key == artifacts?.key else { return }
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retries < Constants.maximumRetries else {
            Logger.error("Shields stopped retrying a build WebKit refused \(retries) times", category: Logger.tabs)
            return
        }
        let delay = Constants.firstRetryDelay * (1 << (2 * retries))
        retries += 1
        retryTask?.cancel()
        retryTask = Task(name: "Shields rebuild after WebKit failure") {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.rebuild(reusingCache: false)
        }
    }

    /// The build named by the last-attached pointer, when it is still whole on disk.
    private func installedBuild() -> ShieldsArtifacts? {
        guard let hex = try? String(contentsOf: installedBuildFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let artifacts = ShieldsArtifacts(directory: buildsDirectory.appending(path: hex, directoryHint: .isDirectory))
        else { return nil }
        return artifacts
    }

    // MARK: - Engines

    /// The current build's engine with rule text, for the request logger and `explain`.
    func debugEngine() async -> ShieldsEngine? {
        defer { scheduleDebugEngineRelease() }
        if let engine {
            return engine
        }
        guard let artifacts else { return nil }
        let engine = await Self.loadEngine(artifacts, debug: true)
        if artifacts.key == self.artifacts?.key {
            self.engine = engine
        }
        return engine
    }

    /// Whether the current build blocks loading `url` as a page: the check WebKit's rule lists
    /// leave out, since they act only on a page's subresources.
    func blocksDocument(_ url: URL) async -> Bool {
        guard let engine = await loadedNavigationEngine() else { return false }
        return await Self.blocks(engine, document: url)
    }

    private func loadedNavigationEngine() async -> ShieldsEngine? {
        guard let artifacts else { return nil }
        if let navigationEngine, navigationEngine.key == artifacts.key.hex {
            return await navigationEngine.task.value
        }
        let task = Task(name: "Shields load navigation engine") { await Self.loadEngine(artifacts, debug: false) }
        navigationEngine = (artifacts.key.hex, task)
        return await task.value
    }

    private func keepDebugEngine(_ engine: ShieldsEngine) {
        self.engine = engine
        scheduleDebugEngineRelease()
    }

    private func scheduleDebugEngineRelease() {
        engineRelease?.cancel()
        engineRelease = Task(name: "Shields debug engine release") {
            try? await Task.sleep(for: Constants.debugEngineIdleTime)
            guard !Task.isCancelled else { return }
            self.releaseDebugEngine()
        }
    }

    private func releaseDebugEngine() {
        engine = nil
    }

    // MARK: - Persistence

    private func textURL(for id: String) -> URL {
        storageDirectory.appending(path: "\(id).txt")
    }

    private func cachedText(for id: String) -> Data? {
        try? Data(contentsOf: textURL(for: id))
    }

    /// A list's last download, else the snapshot the app ships of it.
    private func listText(for id: String) -> Data? {
        cachedText(for: id) ?? Self.bundledSnapshot(of: id, in: bundle)
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

// MARK: - Downloads, Snapshots and Engines

extension ContentBlockingManager {
    /// What a build reads from `source`: nothing from a list not fetched over HTTPS, and no
    /// scriptlets from a custom list the user did not trust.
    static func shieldsList(for source: FilterListSource, text: Data) -> ShieldsList? {
        guard source.isFetchable else { return nil }
        return ShieldsList(
            id: source.id,
            text: text,
            isTrusted: source.isTrusted,
            allowsScriptlets: source.contributesScriptlets,
        )
    }

    /// The text of list `id` as the app shipped it (``FilterListSource/bundledListIDs``), so a
    /// fresh install is protected before its first download.
    static func bundledSnapshot(of id: String, in bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: Constants.snapshotPrefix + id, withExtension: Constants.snapshotExtension),
              let compressed = try? Data(contentsOf: url)
        else { return nil }
        return try? (compressed as NSData).decompressed(using: .lzma) as Data
    }

    /// `list`'s text over HTTPS, every redirect included.
    @concurrent
    fileprivate static func download(_ list: FilterListSource, session: URLSession) async -> Result<Data, any Error> {
        let redirects = HTTPSOnlyRedirects()
        do {
            guard list.isFetchable else {
                throw ShieldsListError.insecureURL
            }
            let (data, response) = try await session.data(from: list.url, delegate: redirects)
            guard !redirects.refusedInsecureRedirect, response.url?.scheme?.lowercased() == "https" else {
                throw ShieldsListError.insecureURL
            }
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard data.count <= Constants.maximumListBytes,
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
            else { throw URLError(.cannotDecodeContentData) }
            return .success(data)
        } catch {
            return .failure(redirects.refusedInsecureRedirect ? ShieldsListError.insecureURL : error)
        }
    }

    /// The build's debug engine (rule text, redirect resources) or its plain one.
    @concurrent
    fileprivate static func loadEngine(_ artifacts: ShieldsArtifacts, debug: Bool) async -> ShieldsEngine? {
        let name = debug ? ShieldsArtifacts.debugEngineName : ShieldsArtifacts.engineName
        guard let dat = try? artifacts.verifiedContents(ofPath: name) else { return nil }
        let resources = debug ? (try? artifacts.verifiedContents(ofPath: ShieldsArtifacts.resourcesName)) : Data("[]".utf8)
        guard let resources else { return nil }
        return try? ShieldsEngine(dat: dat, resources: resources)
    }

    @concurrent
    fileprivate static func blocks(_ engine: ShieldsEngine, document url: URL) async -> Bool {
        engine.explain(url: url.absoluteString, source: url.absoluteString, type: "document")?.shouldBlock ?? false
    }
}
