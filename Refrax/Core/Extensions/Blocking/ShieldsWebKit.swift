import Foundation
import Observation
import WebKit

/// Puts a Shields build into WebKit: content rule lists on the shared user content controller,
/// and scriptlet/procedural user scripts through the ``ScriptRegistry``.
///
/// A new build is compiled (or found in `WKContentRuleListStore` by identifier) completely
/// before any list is swapped, so a failed compile leaves the previous build attached and no
/// page goes unprotected.
@Observable
final class ShieldsWebKit {
    private enum Constants {
        static let identifierPrefix = "shields."
        /// Patterns whose loads may take a network list's redirect actions.
        static let actionPatterns: Set<String> = ["*://*/*"]
        /// The isolated world procedural filters run in.
        static let worldName = "RefraxShields"
    }

    /// A user script entry in `scripts.json`.
    nonisolated struct UserScript: Codable, Hashable, Sendable {
        let name: String
        /// `page` or `shields`.
        let world: String
        let source: String
        let includes: [String]
    }

    private let userContentController: WKUserContentController
    private let scriptRegistry: ScriptRegistry
    private let store: WKContentRuleListStore

    /// The build whose lists are attached.
    private(set) var artifacts: ShieldsArtifacts?
    /// Whether cosmetic lists and user scripts are on; off while uBlock Origin runs, which
    /// brings its own.
    private(set) var cosmeticsEnabled = true
    /// Sites that get no Shields scripts; their rule lists are off per navigation.
    private(set) var allowlistedHosts: [String] = []

    @ObservationIgnored private var networkLists: [WKContentRuleList] = []
    @ObservationIgnored private var cosmeticLists: [WKContentRuleList] = []
    @ObservationIgnored private var scripts: [UserScript] = []

    /// Identifier → patterns, for `WKWebpagePreferences._activeContentRuleListActionPatterns`:
    /// only the network lists carry redirect actions.
    private(set) var actionPatterns: [String: Set<String>] = [:]

    /// - Parameter store: Where compiled rule lists live; WebKit's default store unless a test
    ///   gives its own.
    init(
        userContentController: WKUserContentController,
        scriptRegistry: ScriptRegistry,
        store: WKContentRuleListStore = .default(),
    ) {
        self.userContentController = userContentController
        self.scriptRegistry = scriptRegistry
        self.store = store
    }

    /// Whether `identifier` names a Shields rule list.
    static func isShieldsList(_ identifier: String) -> Bool {
        identifier.hasPrefix(Constants.identifierPrefix)
    }

    /// The identifiers of the attached Shields rule lists.
    var ruleListIdentifiers: Set<String> {
        Set((networkLists + cosmeticLists).map(\.identifier))
    }

    /// Sets a navigation's Shields preferences: network lists may redirect, and on a site the
    /// user exempted only Shields' lists are skipped. Every other rule list (extensions'
    /// declarativeNetRequest rules, Refrax's cookie rules) still applies there.
    func configure(_ preferences: WKWebpagePreferences, siteIsExempt: Bool) {
        if !actionPatterns.isEmpty {
            preferences._activeContentRuleListActionPatterns = actionPatterns
        }
        if siteIsExempt {
            preferences._setContentRuleListsEnabled(true, exceptions: ruleListIdentifiers)
        }
    }

    // MARK: - Installing

    /// Attaches `artifacts`, compiling any rule list WebKit's store lacks.
    func install(_ artifacts: ShieldsArtifacts) async throws {
        guard artifacts.key != self.artifacts?.key else { return }
        let manifest = artifacts.manifest.webKit
        var network: [WKContentRuleList] = []
        for index in 0 ..< manifest.networkLists {
            try await network.append(ruleList(
                identifier: Self.identifier(artifacts.key, "network", index),
                file: artifacts.networkRulesURL(index),
            ))
        }
        var cosmetic: [WKContentRuleList] = []
        for index in 0 ..< manifest.cosmeticLists {
            try await cosmetic.append(ruleList(
                identifier: Self.identifier(artifacts.key, "cosmetic", index),
                file: artifacts.cosmeticRulesURL(index),
            ))
        }
        let scripts = try await Self.loadScripts(from: artifacts.scriptsURL)

        for list in network {
            userContentController.add(list)
        }
        for list in networkLists {
            userContentController.remove(list)
        }
        if cosmeticsEnabled {
            for list in cosmetic {
                userContentController.add(list)
            }
        }
        for list in cosmeticLists {
            userContentController.remove(list)
        }
        networkLists = network
        cosmeticLists = cosmetic
        self.scripts = scripts
        self.artifacts = artifacts
        actionPatterns = Dictionary(uniqueKeysWithValues: network.map { ($0.identifier, Constants.actionPatterns) })
        applyScripts()
        await removeStaleLists(keeping: Set(network.map(\.identifier) + cosmetic.map(\.identifier)))
        let ruleCount = artifacts.manifest.webKit.counts.totalRules
        Logger.info(
            "Shields \(artifacts.key.shortForm): \(network.count) network + \(cosmetic.count) cosmetic lists, \(ruleCount) rules, \(scripts.count) scripts",
            category: Logger.tabs,
        )
    }

    /// Turns the cosmetic lists and user scripts on or off (off while uBlock Origin runs).
    func setCosmeticsEnabled(_ enabled: Bool) {
        guard enabled != cosmeticsEnabled else { return }
        cosmeticsEnabled = enabled
        for list in cosmeticLists {
            if enabled {
                userContentController.add(list)
            } else {
                userContentController.remove(list)
            }
        }
        applyScripts()
    }

    /// Keeps Shields' scripts off these sites (and their subdomains).
    func setAllowlistedHosts(_ hosts: [String]) {
        guard hosts != allowlistedHosts else { return }
        allowlistedHosts = hosts
        applyScripts()
    }

    /// Detaches everything (content blocking turned off).
    func uninstall() {
        for list in networkLists + cosmeticLists {
            userContentController.remove(list)
        }
        networkLists = []
        cosmeticLists = []
        scripts = []
        artifacts = nil
        actionPatterns = [:]
        applyScripts()
    }

    // MARK: - Scripts

    private func applyScripts() {
        scriptRegistry.unregisterAll(for: .shields)
        if cosmeticsEnabled {
            let excludes = allowlistedHosts.flatMap { ["*://\($0)/*", "*://*.\($0)/*"] }
            let world = WKContentWorld.world(name: Constants.worldName)
            for script in scripts where !script.includes.isEmpty {
                let scriptWorld = script.world == "page" ? WKContentWorld.page : world
                let userScript = makeMatchPatternUserScript(
                    source: script.source,
                    forMainFrameOnly: false,
                    includes: script.includes,
                    excludes: excludes,
                    world: scriptWorld,
                )
                scriptRegistry.register(userScript, source: .shields, priority: ScriptRegistry.Priority.system, world: scriptWorld)
            }
        }
        scriptRegistry.apply(to: userContentController)
    }

    @concurrent
    private static func loadScripts(from url: URL) async throws -> [UserScript] {
        try JSONDecoder().decode([UserScript].self, from: Data(contentsOf: url))
    }

    // MARK: - Rule Lists

    private static func identifier(_ key: ShieldsKey, _ kind: String, _ index: Int) -> String {
        "\(Constants.identifierPrefix)\(key.shortForm).\(kind)-\(index)"
    }

    /// The compiled list for `identifier`, from WebKit's store or compiled from `file`.
    private func ruleList(identifier: String, file: URL) async throws -> WKContentRuleList {
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return cached
        }
        let json = try await Self.readText(file)
        guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
            throw ShieldsError.status(-1, operation: "compile \(identifier)")
        }
        return list
    }

    @concurrent
    private static func readText(_ url: URL) async throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Removes from WebKit's store the Shields lists of other builds, and per-list chunks named
    /// `<list id>-<n>`, which nothing attaches.
    private func removeStaleLists(keeping current: Set<String>) async {
        let identifiers: [String] = await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
        }
        let filterListIDs = Set(FilterListSource.allAvailableLists.map(\.id))
        for identifier in identifiers where !current.contains(identifier) {
            let isShields = Self.isShieldsList(identifier)
            let isPerListChunk = identifier.lastIndex(of: "-").map { dash in
                Int(identifier[identifier.index(after: dash)...]) != nil
                    && (filterListIDs.contains(String(identifier[..<dash])) || identifier.hasPrefix("custom-"))
            } ?? false
            if isShields || isPerListChunk {
                try? await store.removeContentRuleList(forIdentifier: identifier)
            }
        }
    }
}
