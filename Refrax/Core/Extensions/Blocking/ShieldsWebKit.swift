import Foundation
import Observation
import Shields
import WebKit

/// Puts a Shields build into WebKit: content rule lists on the shared user content controller,
/// and scriptlet/procedural user scripts through the ``ScriptRegistry``.
///
/// A new build is compiled (or found in `WKContentRuleListStore` by identifier) completely
/// before any list is swapped, so a failed compile leaves the previous build attached. Each
/// install takes a generation; a newer install or an uninstall makes an older one stop at its
/// next suspension point, so installs that finish out of order never attach a stale build.
///
/// Shields' user scripts queue their work and two small dispatcher scripts, registered after
/// them, run the queue unless the frame's site is exempt or cosmetics are off. Exempting a site
/// or handing cosmetics to uBlock Origin replaces only the dispatchers, not the scripts.
@Observable
final class ShieldsWebKit {
    private enum Constants {
        /// Patterns whose loads may take a network list's redirect actions.
        static let actionPatterns: Set<String> = ["*://*/*"]
        /// The isolated world procedural filters run in.
        static let worldName = "RefraxShields"
        /// The global Shields' scripts queue their work under (`bundles.rs`).
        static let pendingKey = "refrax.shields.pending"
        /// Set once the per-list rule lists Refrax compiled before Shields are gone from the store.
        static let legacyListsRemovedKey = "ShieldsRemovedPerListRuleLists"
        /// Dispatchers sort after every other Shields script.
        static let dispatcherPriority = Int.max
    }

    /// Every Shields rule list identifier starts with this.
    nonisolated static let identifierPrefix = "shields."

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
    @ObservationIgnored private var dispatchers: [(id: UUID, script: WKUserScript)] = []
    @ObservationIgnored private var generation = 0
    /// Lists installs are reading or compiling, with how many; stale-list removal leaves them
    /// alone.
    @ObservationIgnored private var compilingIdentifiers: [String: Int] = [:]

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
        identifier.hasPrefix(identifierPrefix)
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
    ///
    /// - Parameter shouldAttach: Asked right before anything is attached, with no suspension
    ///   after it; false leaves the current build in place.
    /// - Returns: Whether the build is attached (false when superseded or refused).
    /// - Throws: When a list does not compile or a file fails its manifest check, unless a
    ///   newer install superseded this one meanwhile.
    @discardableResult
    func install(_ artifacts: ShieldsArtifacts, shouldAttach: () -> Bool = { true }) async throws -> Bool {
        generation += 1
        guard artifacts.key != self.artifacts?.key else { return true }
        let installGeneration = generation
        let manifest = artifacts.manifest.webKit
        let paths = (0 ..< manifest.networkLists).map(ShieldsArtifacts.networkRulesPath)
            + (0 ..< manifest.cosmeticLists).map(ShieldsArtifacts.cosmeticRulesPath)
        let identifiers = paths.compactMap(artifacts.ruleListIdentifier(forPath:))
        for identifier in identifiers {
            compilingIdentifiers[identifier, default: 0] += 1
        }
        defer {
            for identifier in identifiers {
                compilingIdentifiers[identifier] = compilingIdentifiers[identifier].flatMap { $0 > 1 ? $0 - 1 : nil }
            }
        }

        var lists: [WKContentRuleList] = []
        let scripts: [UserScript]
        do {
            for path in paths {
                try await lists.append(ruleList(artifacts, path: path))
                guard installGeneration == generation else { return false }
            }
            scripts = try await Self.loadScripts(of: artifacts)
        } catch {
            guard installGeneration == generation else { return false }
            throw error
        }
        guard installGeneration == generation, shouldAttach() else { return false }
        let network = Array(lists.prefix(manifest.networkLists))
        let cosmetic = Array(lists.dropFirst(manifest.networkLists))

        for list in network {
            userContentController.add(list)
        }
        for list in networkLists where !network.contains(where: { $0.identifier == list.identifier }) {
            userContentController.remove(list)
        }
        if cosmeticsEnabled {
            for list in cosmetic {
                userContentController.add(list)
            }
        }
        for list in cosmeticLists where !cosmetic.contains(where: { $0.identifier == list.identifier }) {
            userContentController.remove(list)
        }
        networkLists = network
        cosmeticLists = cosmetic
        self.artifacts = artifacts
        actionPatterns = Dictionary(uniqueKeysWithValues: network.map { ($0.identifier, Constants.actionPatterns) })
        registerScripts(scripts)
        Logger.info(
            "Shields \(artifacts.key.shortForm): \(network.count) network + \(cosmetic.count) cosmetic lists, \(manifest.counts.totalRules) rules, \(scripts.count) scripts",
            category: Logger.tabs,
        )
        await removeStaleLists()
        return true
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
        replaceDispatchers()
    }

    /// Keeps Shields' scripts off these sites (and their subdomains).
    func setAllowlistedHosts(_ hosts: [String]) {
        guard hosts != allowlistedHosts else { return }
        allowlistedHosts = hosts
        replaceDispatchers()
    }

    /// Detaches everything (content blocking turned off) and stops any install in flight.
    func uninstall() {
        generation += 1
        for list in networkLists + cosmeticLists {
            userContentController.remove(list)
        }
        networkLists = []
        cosmeticLists = []
        artifacts = nil
        actionPatterns = [:]
        registerScripts([])
    }

    // MARK: - Scripts

    /// Registers a build's scripts and the dispatchers after them; the one full reapply.
    private func registerScripts(_ scripts: [UserScript]) {
        scriptRegistry.unregisterAll(for: .shields)
        dispatchers = []
        let shieldsWorld = WKContentWorld.world(name: Constants.worldName)
        for script in scripts where !script.includes.isEmpty {
            let world = script.world == "page" ? WKContentWorld.page : shieldsWorld
            let userScript = makeMatchPatternUserScript(
                source: script.source,
                forMainFrameOnly: false,
                includes: script.includes,
                excludes: [],
                world: world,
            )
            scriptRegistry.register(userScript, source: .shields, priority: ScriptRegistry.Priority.system, world: world)
        }
        if !scripts.isEmpty {
            for world in [WKContentWorld.page, shieldsWorld] {
                let script = dispatcher(in: world)
                let id = scriptRegistry.register(script, source: .shields, priority: Constants.dispatcherPriority, world: world)
                dispatchers.append((id, script))
            }
        }
        scriptRegistry.apply(to: userContentController)
    }

    /// Swaps the dispatchers for ones with the current switches. Only they reach the web
    /// processes again; they stay last because a new user script is appended.
    private func replaceDispatchers() {
        guard !dispatchers.isEmpty else { return }
        let shieldsWorld = WKContentWorld.world(name: Constants.worldName)
        for old in dispatchers {
            scriptRegistry.unregister(id: old.id)
            userContentController._removeUserScript(old.script)
        }
        dispatchers = [WKContentWorld.page, shieldsWorld].map { world in
            let script = dispatcher(in: world)
            let id = scriptRegistry.register(script, source: .shields, priority: Constants.dispatcherPriority, world: world)
            userContentController.addUserScript(script)
            return (id, script)
        }
    }

    /// The script that runs the queued Shields work in `world` unless the frame's site is
    /// exempt or cosmetics are off. It removes the queue first, so no page script sees it, and
    /// then relays the work into the frame's hostless children (``Self/relay``).
    private func dispatcher(in world: WKContentWorld) -> WKUserScript {
        let hosts = (try? JSONEncoder().encode(allowlistedHosts)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let key = (try? JSONEncoder().encode(Constants.pendingKey)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        let source = """
        (function() {
        const key = Symbol.for(\(key));
        const queue = globalThis[key];
        delete globalThis[key];
        if (!queue || !\(cosmeticsEnabled)) { return; }
        const exempt = new Set(\(hosts));
        let host = location.hostname;
        while (host) {
        if (exempt.has(host)) { return; }
        const dot = host.indexOf('.');
        if (dot < 0) { break; }
        host = host.slice(dot + 1);
        }
        const toSource = Function.prototype.toString;
        const sources = queue.map((run) => toSource.call(run));
        for (const run of queue) { try { run(); } catch (error) { } }
        (\(Self.relay))(sources, \(world == .page));
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)
    }

    /// Carries a frame's Shields work into the same-origin frames it creates without a host of
    /// their own: `about:blank`, `about:srcdoc` and `javascript:` frames. WebKit runs no user
    /// script in an iframe's initial empty document (`ShouldInjectUserScriptsInInitialEmptyDocument`
    /// is off, and no WebKit API sets it), and a match pattern never matches a hostless URL
    /// (WebKit's `UserContentMatchParentFrame` is reserved to its own extension runtime), so
    /// without this a page takes pristine `setTimeout` or `fetch` from a new frame's
    /// `contentWindow` and skips every main-world scriptlet, and an ad filled into such a frame
    /// escapes procedural filters. Generic hides reach these frames on their own: WebKit adds
    /// each rule list's global display-none sheet to `about:blank` and `about:srcdoc` subframes
    /// (`SubframeLoader.cpp`).
    ///
    /// The work runs in the child's realm, through its `Function`, with the same sources, and
    /// installs the relay there for grandchildren; the bundles find their host through the
    /// creator chain (`bundles.rs`). A child is reached when the page reads its `contentWindow`
    /// or `contentDocument` (main world: the getters are wrapped, so the pristine-globals grab
    /// is caught before it returns), when a frame element is inserted (a mutation observer),
    /// and when a frame loads. A page whose content security policy forbids `eval` keeps its
    /// main-world children unreached; the isolated world is not bound by it.
    private static let relay = """
    function relay(sources, wrapsGetters) {
        const mark = Symbol.for('refrax.shields.relayed');
        const relaySource = Function.prototype.toString.call(relay);
        globalThis[mark] = true;
        const reach = (win) => {
            try {
                if (!win || win[mark]) { return; }
                const href = win.location.href;
                if (!href.startsWith('about:') && !href.startsWith('javascript:')) { return; }
                win[mark] = true;
                win.Function('sources', 'wrapsGetters',
                    '(' + relaySource + ')(sources, wrapsGetters);\\n' +
                    'for (const source of sources) { try { Function("(" + source + ")()")(); } catch (error) { } }',
                )(sources, wrapsGetters);
            } catch (error) { }
        };
        const windowOf = new Map();
        for (const type of [globalThis.HTMLIFrameElement, globalThis.HTMLFrameElement, globalThis.HTMLObjectElement]) {
            if (!type) { continue; }
            const windowGetter = Object.getOwnPropertyDescriptor(type.prototype, 'contentWindow');
            const documentGetter = Object.getOwnPropertyDescriptor(type.prototype, 'contentDocument');
            if (windowGetter && windowGetter.get) { windowOf.set(type, windowGetter.get); }
            if (!wrapsGetters) { continue; }
            for (const [name, descriptor] of [['contentWindow', windowGetter], ['contentDocument', documentGetter]]) {
                if (!descriptor || !descriptor.get) { continue; }
                const get = new Proxy(descriptor.get, {
                    apply(target, self, args) {
                        const value = Reflect.apply(target, self, args);
                        if (value) { reach(name === 'contentWindow' ? value : value.defaultView); }
                        return value;
                    },
                });
                Object.defineProperty(type.prototype, name, { ...descriptor, get });
            }
        }
        const frameWindow = (element) => {
            for (const [type, get] of windowOf) {
                if (element instanceof type) { return get.call(element); }
            }
            return null;
        };
        const seen = new WeakSet();
        const hook = (element) => {
            if (seen.has(element)) { return; }
            seen.add(element);
            reach(frameWindow(element));
            element.addEventListener('load', () => reach(frameWindow(element)), true);
        };
        const scan = (node) => {
            if (node.nodeType !== 1) { return; }
            if (node.matches('iframe, frame, object')) { hook(node); }
            for (const element of node.querySelectorAll('iframe, frame, object')) { hook(element); }
        };
        new MutationObserver((records) => {
            for (const record of records) {
                for (const node of record.addedNodes) { scan(node); }
            }
        }).observe(document, { childList: true, subtree: true });
        if (document.documentElement) { scan(document.documentElement); }
    }
    """

    @concurrent
    private static func loadScripts(of artifacts: ShieldsArtifacts) async throws -> [UserScript] {
        try JSONDecoder().decode([UserScript].self, from: artifacts.verifiedContents(ofPath: ShieldsArtifacts.scriptsPath))
    }

    // MARK: - Rule Lists

    /// The compiled list for a rules file, from WebKit's store or compiled from the file once
    /// it matches its manifest hash.
    private func ruleList(_ artifacts: ShieldsArtifacts, path: String) async throws -> WKContentRuleList {
        guard let identifier = artifacts.ruleListIdentifier(forPath: path) else {
            throw ShieldsError.status(SHIELDS_INVALID_DATA, operation: "manifest entry for \(path)")
        }
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return cached
        }
        let json = try await Self.readRules(artifacts, path: path)
        guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
            throw ShieldsError.status(-1, operation: "compile \(identifier)")
        }
        return list
    }

    @concurrent
    private static func readRules(_ artifacts: ShieldsArtifacts, path: String) async throws -> String {
        try String(decoding: artifacts.verifiedContents(ofPath: path), as: UTF8.self)
    }

    /// Removes the Shields lists neither the attached build nor an install in flight uses from
    /// WebKit's store, and, once, the per-list rule lists (`<list id>-<n>`) that Refrax compiled
    /// before Shields.
    private func removeStaleLists() async {
        let identifiers: [String] = await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
        }
        let removesLegacyLists = !UserDefaults.standard.bool(forKey: Constants.legacyListsRemovedKey)
        for identifier in identifiers where !ruleListIdentifiers.contains(identifier) && compilingIdentifiers[identifier] == nil {
            if Self.isShieldsList(identifier) || (removesLegacyLists && Self.isLegacyPerListIdentifier(identifier)) {
                try? await store.removeContentRuleList(forIdentifier: identifier)
            }
        }
        if removesLegacyLists {
            UserDefaults.standard.set(true, forKey: Constants.legacyListsRemovedKey)
        }
    }

    /// The identifiers the per-list compiler used: a built-in list id, or `custom-` with eight
    /// uppercase hex digits, then `-` and a chunk number.
    static func isLegacyPerListIdentifier(_ identifier: String) -> Bool {
        let builtIn = FilterListSource.allAvailableLists.map { NSRegularExpression.escapedPattern(for: $0.id) }
        let pattern = "^(?:\(builtIn.joined(separator: "|"))|custom-[0-9A-F]{8})-[0-9]+$"
        return identifier.range(of: pattern, options: .regularExpression) != nil
    }
}
