import Foundation
import Observation

/// Shields' state and intents for the app: the filter lists, the current build, and what
/// Shields did to each page.
///
/// ``ContentBlockingManager`` (an actor) owns lists and builds; ``ShieldsWebKit`` puts a
/// build into WebKit; this store connects them, publishes the `contentBlocking` policy to the
/// other engines, and answers the request logger.
///
/// A build reaches the other engines as soon as it exists, whatever WebKit makes of it. At
/// launch, page loads wait (``waitUntilReady(timeout:)``, at most 1.5 s) until WebKit has a
/// build attached; the one attached at the last quit usually is within milliseconds, since
/// WebKit keeps its compiled lists.
@Observable
final class ShieldsStore {
    private enum Constants {
        /// How long a page load waits at launch for Shields before it goes ahead unfiltered.
        static let readinessTimeout: Duration = .milliseconds(1_500)
    }

    /// The lists, with their state as of the last change.
    private(set) var lists: [FilterListSource] = []
    /// The newest build, sent to the other engines; WebKit's is ``ShieldsWebKit/artifacts``.
    private(set) var artifacts: ShieldsArtifacts?
    private(set) var isUpdating = false
    private(set) var lastUpdate: Date?
    /// Why the last fetch, build or WebKit install failed.
    var lastError: String? {
        installError ?? buildError
    }

    /// Whether Shields filters at all (``BrowserSettings/enableContentBlocking``).
    private(set) var isEnabled = true
    /// Sites the user turned Shields off for.
    private(set) var allowlistedHosts: [String] = []
    /// Whether a uBlock Origin extension is on. Shields then leaves cosmetic filtering and
    /// scriptlets to it and keeps its own network lists, which uBO cannot apply on WebKit.
    private(set) var isUBlockOriginActive = false
    /// Whether WebKit has a build attached, or Shields has nothing more to attach.
    private(set) var isReady = false

    private var buildError: String?
    private var installError: String?

    let webKit: ShieldsWebKit
    @ObservationIgnored let manager: ContentBlockingManager

    /// Receives the `contentBlocking` policy for engines other than WebKit.
    @ObservationIgnored var onPolicy: ((ContentBlockingPolicy) -> Void)? {
        didSet { onPolicy?(policy) }
    }

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var readinessWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Hosts whose blocked pages the user chose to open; kept until quit.
    @ObservationIgnored private var hostsOpenedAnyway: Set<String> = []

    init(webKit: ShieldsWebKit, manager: ContentBlockingManager = ContentBlockingManager()) {
        self.webKit = webKit
        self.manager = manager
    }

    // MARK: - Starting

    /// Attaches the build WebKit had at the last quit, builds the current lists and starts
    /// list updates. Returns without waiting for a download.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        await manager.start(
            onChange: { [weak self] snapshot in self?.apply(snapshot) },
            onBuild: { [weak self] artifacts in await self?.install(artifacts) ?? .skipped },
        )
        markReady()
    }

    private func apply(_ snapshot: ContentBlockingManager.Snapshot) {
        lists = snapshot.lists
        isUpdating = snapshot.isUpdating
        lastUpdate = snapshot.lastUpdate
        buildError = snapshot.lastError
    }

    /// Publishes `artifacts` to the other engines, then attaches it to WebKit.
    private func install(_ artifacts: ShieldsArtifacts) async -> ContentBlockingManager.InstallResult {
        self.artifacts = artifacts
        publishPolicy()
        guard isEnabled else { return .skipped }
        do {
            let attached = try await webKit.install(artifacts) { [weak self] in self?.isEnabled == true }
            guard attached else { return .skipped }
            installError = nil
            markReady()
            return .attached
        } catch {
            installError = "WebKit could not compile the rule lists: \(error.localizedDescription)"
            Logger.error("Shields WebKit install failed, keeping the previous build: \(error)", category: Logger.tabs)
            return .failed
        }
    }

    // MARK: - Readiness

    /// Waits until WebKit has Shields' lists attached, or `timeout` passes. Returns at once
    /// when Shields is off or ready.
    func waitUntilReady(timeout: Duration = Constants.readinessTimeout) async {
        guard isEnabled, !isReady else { return }
        let id = UUID()
        let timer = Task(name: "Shields readiness timeout") { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.resumeWaiter(id)
        }
        await withCheckedContinuation { continuation in
            readinessWaiters[id] = continuation
        }
        timer.cancel()
    }

    private func resumeWaiter(_ id: UUID) {
        readinessWaiters.removeValue(forKey: id)?.resume()
    }

    private func markReady() {
        isReady = true
        let waiters = readinessWaiters.values
        readinessWaiters = [:]
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - Intents

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            Task(name: "Shields re-attach") { await manager.reinstall() }
        } else {
            webKit.uninstall()
            markReady()
        }
        publishPolicy()
    }

    func setAllowlistedHosts(_ hosts: [String]) {
        guard hosts != allowlistedHosts else { return }
        allowlistedHosts = hosts
        webKit.setAllowlistedHosts(hosts)
        publishPolicy()
    }

    func setUBlockOriginActive(_ active: Bool) {
        guard active != isUBlockOriginActive else { return }
        isUBlockOriginActive = active
        webKit.setCosmeticsEnabled(!active)
    }

    func setListEnabled(_ id: String, enabled: Bool) {
        if let index = lists.firstIndex(where: { $0.id == id }) {
            lists[index].isEnabled = enabled
        }
        Task(name: "Shields list toggle") { await manager.setFilterListEnabled(id, enabled: enabled) }
    }

    /// Subscribes to a list over HTTPS; `allowsScriptlets` lets it run scriptlets in pages.
    func addCustomList(name: String, url: URL, allowsScriptlets: Bool) {
        Task(name: "Shields add list") {
            await manager.addCustomFilterList(name: name, url: url, allowsScriptlets: allowsScriptlets)
        }
    }

    func removeCustomList(_ id: String) {
        Task(name: "Shields remove list") { await manager.removeCustomFilterList(id) }
    }

    func updateNow() {
        Task(name: "Shields update") { await manager.updateFilterLists(force: true) }
    }

    // MARK: - Pages

    /// Whether Shields blocks opening `url` as a page: a filter matches it as a document, and
    /// neither the site's exemption nor the user's "open anyway" lets it through.
    func blocksPage(_ url: URL, siteIsExempt: Bool) async -> Bool {
        guard isEnabled, !siteIsExempt, url.isWebURL,
              !hostsOpenedAnyway.contains(url.host()?.lowercased() ?? "")
        else { return false }
        return await manager.blocksDocument(url)
    }

    /// Lets `url`'s site open pages Shields blocks, until quit.
    func openAnyway(_ url: URL) {
        if let host = url.host()?.lowercased() {
            hostsOpenedAnyway.insert(host)
        }
    }

    // MARK: - Policy

    /// The `contentBlocking` policy for the current build and settings.
    var policy: ContentBlockingPolicy {
        guard isEnabled, let artifacts else {
            return ContentBlockingPolicy(isEnabled: false, allowlistedHosts: allowlistedHosts)
        }
        let manifest = artifacts.manifest
        return ContentBlockingPolicy(
            isEnabled: true,
            engine: .init(path: artifacts.engineURL, sha256: manifest.engineSHA256, format: manifest.format),
            resources: .init(path: artifacts.resourcesURL, sha256: manifest.resourcesSHA256),
            lists: manifest.lists.map { .init(id: $0.id, sourceIndex: $0.sourceIndex) },
            allowlistedHosts: allowlistedHosts,
        )
    }

    private func publishPolicy() {
        onPolicy?(policy)
    }

    // MARK: - Request Logger

    /// List ids by their source index in the current build.
    var listIDsBySourceIndex: [Int: String] {
        Dictionary(uniqueKeysWithValues: (artifacts?.manifest.lists ?? []).map { ($0.sourceIndex, $0.id) })
    }

    /// Records what a WebKit rule list did to a load on `page`.
    func record(listIdentifier: String, blocked: Bool, redirected: Bool, url: URL, on page: WebPage) {
        guard ShieldsWebKit.isShieldsList(listIdentifier), blocked || redirected else { return }
        page.shieldsLog.record(url: url, frameURL: page.url, decision: blocked ? .blocked : .redirected)
    }

    /// `page`'s log after `sequence`.
    ///
    /// - Parameter attributed: Whether to name every entry's rule, which loads the engine with
    ///   rule text and asks it about each entry; the popover, which shows hosts, skips it.
    func requestLog(for page: WebPage, since sequence: Int64 = 0, attributed: Bool = true) async throws -> RequestLog {
        let log = if let enginePage = page.enginePage {
            try await enginePage.requestLog(since: sequence)
        } else {
            page.shieldsLog.log(since: sequence)
        }
        guard attributed else { return log }
        let engine = await manager.debugEngine()
        let lists = listIDsBySourceIndex
        return await Self.attribute(log, engine: engine, lists: lists)
    }

    @concurrent
    private static func attribute(_ log: RequestLog, engine: ShieldsEngine?, lists: [Int: String]) async -> RequestLog {
        log.attributed(using: engine, lists: lists)
    }

    /// Why `url`, requested by a document at `source`, is decided as it is.
    func explain(url: URL, source: URL, type: String) async -> (ShieldsExplanation, list: String?, exceptionList: String?)? {
        guard let engine = await manager.debugEngine(),
              let explanation = await Self.explain(engine, url: url, source: source, type: type)
        else { return nil }
        let lists = listIDsBySourceIndex
        return (
            explanation,
            explanation.rule?.sourceIndex.flatMap { lists[$0] },
            explanation.exception?.sourceIndex.flatMap { lists[$0] },
        )
    }

    @concurrent
    private static func explain(_ engine: ShieldsEngine, url: URL, source: URL, type: String) async -> ShieldsExplanation? {
        engine.explain(url: url.absoluteString, source: source.absoluteString, type: type)
    }
}
