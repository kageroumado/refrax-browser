import Foundation
import Observation

/// Shields' state and intents for the app: the filter lists, the current build, and what
/// Shields did to each page.
///
/// ``ContentBlockingManager`` (an actor) owns lists and builds; ``ShieldsWebKit`` puts a
/// build into WebKit; this store connects them, publishes the `contentBlocking` policy to the
/// other engines, and answers the request logger.
@Observable
final class ShieldsStore {
    /// The lists, with their state as of the last change.
    private(set) var lists: [FilterListSource] = []
    /// The build attached to WebKit and sent to the other engines.
    private(set) var artifacts: ShieldsArtifacts?
    private(set) var isUpdating = false
    private(set) var lastUpdate: Date?
    private(set) var lastError: String?
    /// Whether Shields filters at all (``BrowserSettings/enableContentBlocking``).
    private(set) var isEnabled = true
    private(set) var mode = ContentBlockingPolicy.Mode.standard
    /// Sites the user turned Shields off for.
    private(set) var allowlistedHosts: [String] = []
    /// Whether a uBlock Origin extension is on. Shields then leaves cosmetic filtering and
    /// scriptlets to it and keeps its own network lists, which uBO cannot apply on WebKit.
    private(set) var isUBlockOriginActive = false

    let webKit: ShieldsWebKit
    @ObservationIgnored let manager = ContentBlockingManager()

    /// Receives the `contentBlocking` policy for engines other than WebKit.
    @ObservationIgnored var onPolicy: ((ContentBlockingPolicy) -> Void)? {
        didSet { onPolicy?(policy) }
    }

    @ObservationIgnored private var isStarted = false

    init(webKit: ShieldsWebKit) {
        self.webKit = webKit
    }

    // MARK: - Starting

    /// Attaches the cached build and starts list updates. Returns without waiting for a
    /// download or a build.
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        await manager.start(
            onChange: { [weak self] snapshot in self?.apply(snapshot) },
            onBuild: { [weak self] artifacts in await self?.install(artifacts) },
        )
    }

    private func apply(_ snapshot: ContentBlockingManager.Snapshot) {
        lists = snapshot.lists
        isUpdating = snapshot.isUpdating
        lastUpdate = snapshot.lastUpdate
        lastError = snapshot.lastError
    }

    private func install(_ artifacts: ShieldsArtifacts) async {
        guard isEnabled else {
            self.artifacts = artifacts
            publishPolicy()
            return
        }
        do {
            try await webKit.install(artifacts)
            self.artifacts = artifacts
        } catch {
            lastError = "WebKit could not compile the rule lists: \(error.localizedDescription)"
            Logger.error("Shields WebKit install failed, keeping the previous build: \(error)", category: Logger.tabs)
            return
        }
        publishPolicy()
    }

    // MARK: - Intents

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            if let artifacts {
                Task(name: "Shields re-attach") { try? await webKit.install(artifacts) }
            }
        } else {
            webKit.uninstall()
        }
        publishPolicy()
    }

    func setMode(_ mode: ContentBlockingPolicy.Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
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

    func addCustomList(name: String, url: URL) {
        Task(name: "Shields add list") { await manager.addCustomFilterList(name: name, url: url) }
    }

    func removeCustomList(_ id: String) {
        Task(name: "Shields remove list") { await manager.removeCustomFilterList(id) }
    }

    func updateNow() {
        Task(name: "Shields update") { await manager.updateFilterLists(force: true) }
    }

    // MARK: - Policy

    /// The `contentBlocking` policy for the current build and settings.
    var policy: ContentBlockingPolicy {
        guard isEnabled, let artifacts else {
            return ContentBlockingPolicy(isEnabled: false, mode: mode, allowlistedHosts: allowlistedHosts)
        }
        let manifest = artifacts.manifest
        return ContentBlockingPolicy(
            isEnabled: true,
            mode: mode,
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

    /// `page`'s log after `sequence`, with every entry's rule named.
    func requestLog(for page: WebPage, since sequence: Int64 = 0) async throws -> RequestLog {
        let log = if let enginePage = page.enginePage {
            try await enginePage.requestLog(since: sequence)
        } else {
            page.shieldsLog.log(since: sequence)
        }
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
