import Foundation
import Observation
import SwiftData
import WebKit

/// Manages user-installed JavaScript scripts.
///
/// `UserScriptManager` provides:
/// - CRUD operations for user scripts
/// - URL matching to determine applicable scripts
/// - Script injection via ScriptRegistry
/// - GM_* API shim generation
/// - Update checking for remote scripts
///
/// ## Script Injection
///
/// Scripts are injected via `WKUserScript` with:
/// 1. GM API shim injected first (provides GM_* functions)
/// 2. User script wrapped and injected at specified run-at time
/// 3. Scripts isolated by @namespace using WKContentWorld
///
/// ## Usage
///
/// ```swift
/// let manager = UserScriptManager(modelContext: context)
///
/// // Install from source
/// let script = try manager.install(from: source, sourceURL: url)
///
/// // Get scripts for a URL
/// let scripts = manager.scriptsForURL(url)
///
/// // Configure injection
/// manager.configure(scriptRegistry: registry, userContentController: controller)
/// ```
@Observable
final class UserScriptManager {
    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let patternMatcher = ScriptURLPatternMatcher()

    // MARK: - State

    /// All loaded user scripts.
    private(set) var scripts: [UserScript] = []

    /// Script IDs registered with ScriptRegistry.
    private var registeredScriptIDs: [UUID] = []

    /// Reference to script registry for injection.
    private weak var scriptRegistry: ScriptRegistry?

    /// Reference to user content controller for script application.
    private weak var userContentController: WKUserContentController?

    /// Message handler for GM_* API calls.
    private var messageHandler: UserScriptMessageHandler?

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadScripts()
    }

    /// Configures the manager with required dependencies.
    ///
    /// Call this after initialization to enable script injection.
    ///
    /// - Parameters:
    ///   - scriptRegistry: Registry for managing user scripts.
    ///   - userContentController: Controller to apply scripts to.
    ///   - storageManager: Storage manager for GM_* value storage.
    func configure(
        scriptRegistry: ScriptRegistry,
        userContentController: WKUserContentController,
        storageManager: UserScriptStorageManager,
    ) {
        self.scriptRegistry = scriptRegistry
        self.userContentController = userContentController
        messageHandler = UserScriptMessageHandler(
            scriptManager: self,
            storageManager: storageManager,
        )

        rebuildInjectionScripts()
    }

    // MARK: - Script Loading

    private func loadScripts() {
        let descriptor = FetchDescriptor<UserScript>(
            sortBy: [SortDescriptor(\.installedAt)],
        )
        do {
            scripts = try modelContext.fetch(descriptor)
        } catch {
            Logger.error("Failed to load user scripts: \(error)", category: Logger.tabs)
            scripts = []
        }
    }

    // MARK: - CRUD Operations

    /// Installs a new script from source.
    ///
    /// - Parameters:
    ///   - source: Raw JavaScript with ==UserScript== metadata block.
    ///   - sourceURL: URL the script was downloaded from.
    /// - Throws: `UserScriptMetadataError` if parsing fails.
    /// - Returns: The installed script.
    @discardableResult
    func install(from source: String, sourceURL: URL?) throws -> UserScript {
        let script = try UserScript.create(from: source, sourceURL: sourceURL)
        modelContext.insert(script)
        saveAndReload()
        Logger.info("Installed user script: \(script.name)", category: Logger.tabs)
        return script
    }

    /// Adds a pre-configured script.
    func add(_ script: UserScript) {
        modelContext.insert(script)
        saveAndReload()
        Logger.info("Added user script: \(script.name)", category: Logger.tabs)
    }

    /// Updates a script's source with new content.
    ///
    /// Re-parses metadata and updates all fields.
    func update(_ script: UserScript, newSource: String) throws {
        let metadata = try UserScriptMetadataParser.parse(source: newSource)

        script.updateSource(newSource)
        script.name = metadata.name
        script.version = metadata.version
        script.scriptDescription = metadata.description
        script.author = metadata.author
        script.matchPatterns = metadata.matchPatterns
        script.includePatterns = metadata.includePatterns
        script.excludePatterns = metadata.excludePatterns
        script.runAt = metadata.runAt
        script.runAtFrames = metadata.runAtFrames
        script.grantsRequested = metadata.grants
        script.connectDomains = metadata.connectDomains

        saveAndReload()
        Logger.info("Updated user script: \(script.name)", category: Logger.tabs)
    }

    /// Deletes a user script.
    func delete(_ script: UserScript) {
        let name = script.name
        modelContext.delete(script)
        saveAndReload()
        Logger.info("Deleted user script: \(name)", category: Logger.tabs)
    }

    /// Toggles a script's enabled state.
    func toggleEnabled(_ script: UserScript) {
        script.isEnabled.toggle()
        saveAndReload()
        Logger.info("Toggled user script: \(script.name) enabled=\(script.isEnabled)", category: Logger.tabs)
    }

    private func saveAndReload() {
        do {
            try modelContext.save()
            loadScripts()
            rebuildInjectionScripts()
        } catch {
            Logger.error("Failed to save user scripts: \(error)", category: Logger.tabs)
        }
    }

    // MARK: - URL Matching

    /// Returns all enabled scripts that match a URL.
    func scriptsForURL(_ url: URL) -> [UserScript] {
        patternMatcher.matchingScripts(scripts, for: url, enabledOnly: true)
    }

    /// Returns all scripts (enabled and disabled) that match a URL.
    func allScriptsForURL(_ url: URL) -> [UserScript] {
        patternMatcher.matchingScripts(scripts, for: url, enabledOnly: false)
    }

    /// Checks if any enabled scripts match a URL.
    func hasScriptsForURL(_ url: URL) -> Bool {
        !scriptsForURL(url).isEmpty
    }

    /// Finds a script by its ID.
    func script(for id: UUID) -> UserScript? {
        scripts.first { $0.id == id }
    }

    // MARK: - Script Injection

    /// Rebuilds injection scripts for all enabled scripts.
    private func rebuildInjectionScripts() {
        guard let scriptRegistry, let userContentController else { return }

        // Unregister existing scripts
        for id in registeredScriptIDs {
            scriptRegistry.unregister(id: id)
        }
        registeredScriptIDs.removeAll()

        let enabledScripts = scripts.filter(\.isEnabled)
        guard !enabledScripts.isEmpty else {
            scriptRegistry.apply(to: userContentController)
            return
        }

        // Group by namespace for content world isolation
        let byNamespace = Dictionary(grouping: enabledScripts, by: \.namespace)

        for (namespace, namespaceScripts) in byNamespace {
            let worldName = sanitizeWorldName(namespace)
            let world = WKContentWorld.world(name: "userscript.\(worldName)")

            // Register message handler for this world
            registerMessageHandler(for: world, userContentController: userContentController)

            // Inject GM API shim for this namespace
            injectGMAPIShim(for: namespaceScripts, in: world, registry: scriptRegistry)

            // Inject each script
            for script in namespaceScripts.sorted(by: { $0.name < $1.name }) {
                injectScript(script, in: world, registry: scriptRegistry)
            }
        }

        scriptRegistry.apply(to: userContentController)
        Logger.info("Rebuilt user script injection with \(enabledScripts.count) scripts", category: Logger.tabs)
    }

    private func sanitizeWorldName(_ namespace: String) -> String {
        // Remove characters that might cause issues in world names
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return namespace.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
    }

    private func registerMessageHandler(for world: WKContentWorld, userContentController: WKUserContentController) {
        guard let messageHandler else { return }

        // Remove existing handler if present (safe to call even if not registered)
        userContentController.removeScriptMessageHandler(forName: "userscript", contentWorld: world)

        userContentController.addScriptMessageHandler(
            messageHandler,
            contentWorld: world,
            name: "userscript",
        )
    }

    private func injectGMAPIShim(
        for scripts: [UserScript],
        in world: WKContentWorld,
        registry: ScriptRegistry,
    ) {
        // Collect all grants needed by scripts in this namespace
        let allGrants = Set(scripts.flatMap(\.grantsRequested))
        let namespace = scripts.first?.namespace ?? "default"

        let shimSource = GMAPIShimGenerator.generate(
            for: Array(allGrants),
            namespace: namespace,
        )

        guard !shimSource.isEmpty else { return }

        let userScript = WKUserScript(
            source: shimSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: world,
        )

        let id = registry.register(
            userScript,
            source: .extension(id: "userscript.shim.\(namespace)"),
            priority: ScriptRegistry.Priority.agent - 1, // Shim runs before scripts
        )
        registeredScriptIDs.append(id)
    }

    private func injectScript(_ script: UserScript, in world: WKContentWorld, registry: ScriptRegistry) {
        let wrappedSource = wrapScript(script)

        let userScript = WKUserScript(
            source: wrappedSource,
            injectionTime: script.runAt.wkInjectionTime,
            forMainFrameOnly: !script.runAtFrames,
            in: world,
        )

        let id = registry.register(
            userScript,
            source: .extension(id: "userscript.\(script.id.uuidString)"),
            priority: ScriptRegistry.Priority.agent,
        )
        registeredScriptIDs.append(id)
    }

    /// Wraps user script source with IIFE and metadata.
    private func wrapScript(_ script: UserScript) -> String {
        let escapedName = script.name.escapedForJS(quoteStyle: .double)
        let escapedNamespace = script.namespace.escapedForJS(quoteStyle: .double)
        let escapedVersion = (script.version ?? "1.0").escapedForJS(quoteStyle: .double)
        let escapedDescription = (script.scriptDescription ?? "").escapedForJS(quoteStyle: .double)

        return """
        (function() {
            'use strict';
            const GM_info = {
                script: {
                    name: "\(escapedName)",
                    namespace: "\(escapedNamespace)",
                    version: "\(escapedVersion)",
                    description: "\(escapedDescription)"
                },
                scriptHandler: "Refrax",
                version: "1.0"
            };
        
            \(script.source)
        })();
        """
    }

    // MARK: - Grouped Scripts

    /// Returns scripts grouped by primary domain.
    func scriptsGroupedByDomain() -> [(domain: String, scripts: [UserScript])] {
        var groups: [String: [UserScript]] = [:]

        for script in scripts {
            let domain = script.primaryDomain
            groups[domain, default: []].append(script)
        }

        // Sort: All Sites first, then alphabetically
        let sorted = groups.sorted { lhs, rhs in
            if lhs.key == "All Sites" { return true }
            if rhs.key == "All Sites" { return false }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }

        return sorted.map { ($0.key, $0.value) }
    }
}

// MARK: - Update Checking

extension UserScriptManager {
    /// Checks for updates to remote scripts.
    func checkForUpdates() async {
        let remoteScripts = scripts.filter { $0.updateURL != nil || $0.sourceURL != nil }
        guard !remoteScripts.isEmpty else { return }

        Logger.info("Checking updates for \(remoteScripts.count) remote user scripts", category: Logger.tabs)

        for script in remoteScripts {
            await checkUpdate(for: script)
        }
    }

    private func checkUpdate(for script: UserScript) async {
        guard let updateURL = script.updateURL ?? script.sourceURL else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: updateURL)
            guard let source = String(data: data, encoding: .utf8) else { return }

            let newHash = UserScript.computeHash(source)
            script.lastUpdateCheckAt = Date()

            if newHash != script.sourceHash {
                Logger.info("Update available for user script: \(script.name)", category: Logger.tabs)

                // Apply update
                try update(script, newSource: source)
            }
        } catch {
            Logger.debug("Update check failed for \(script.name): \(error)", category: Logger.tabs)
        }
    }
}
