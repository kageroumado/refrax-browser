import Foundation
import Observation
import SwiftData
import WebKit

/// Manages user-defined CSS styles for web pages.
///
/// `UserStyleManager` provides:
/// - CRUD operations for user styles
/// - URL matching to determine applicable styles
/// - CSS injection script generation
/// - Integration with ScriptRegistry for WebKit injection
/// - Live preview support for style editing
/// - Update checking for remote styles
///
/// ## Script Injection
///
/// User styles are injected at document-start via `WKUserScript`. The CSS is:
/// 1. Processed to add `!important` to all declarations
/// 2. Wrapped in a `<style>` element with a unique ID
/// 3. Injected early to prevent flash of unstyled content
///
/// ## Usage
///
/// ```swift
/// // Get styles for a URL
/// let styles = await manager.stylesForURL(url)
///
/// // Create a new style
/// let style = UserStyle(name: "Dark Mode", css: "body { background: #1a1a1a; }")
/// await manager.add(style)
///
/// // Preview CSS changes
/// await manager.previewStyle(editedCSS, id: style.id, in: webPage)
/// ```
@Observable
final class UserStyleManager {
    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let patternMatcher = StylePatternMatcher()
    private let importantInjector = CSSImportantInjector()

    // MARK: - State

    /// All loaded user styles.
    ///
    /// Kept in memory for fast URL matching. Updated when styles change.
    private(set) var styles: [UserStyle] = []

    /// Script ID for the combined user styles injection.
    private var styleScriptID: UUID?

    /// Reference to script registry for injection.
    private weak var scriptRegistry: ScriptRegistry?

    /// Reference to user content controller for script application.
    private weak var userContentController: WKUserContentController?

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Don't load styles synchronously - call performDeferredSetup() after first frame
    }

    /// Loads styles from the database.
    ///
    /// Call this after the first frame renders to avoid blocking app launch
    /// with synchronous SwiftData fetch on the main thread.
    func performDeferredSetup() {
        loadStyles()
    }

    /// Configures the manager with required dependencies.
    ///
    /// Call this after initialization to enable script injection.
    ///
    /// - Parameters:
    ///   - scriptRegistry: Registry for managing user scripts.
    ///   - userContentController: Controller to apply scripts to.
    func configure(
        scriptRegistry: ScriptRegistry,
        userContentController: WKUserContentController,
    ) {
        self.scriptRegistry = scriptRegistry
        self.userContentController = userContentController
    }

    // MARK: - Style Loading

    private func loadStyles() {
        let descriptor = FetchDescriptor<UserStyle>(sortBy: [SortDescriptor(\.installedAt)])
        do {
            styles = try modelContext.fetch(descriptor)
        } catch {
            Logger.error("Failed to load user styles: \(error)", category: Logger.tabs)
            styles = []
        }
    }

    // MARK: - CRUD Operations

    /// Adds a new user style.
    ///
    /// - Parameter style: The style to add.
    func add(_ style: UserStyle) {
        modelContext.insert(style)
        saveAndReload()
        Logger.info("Added user style: \(style.name)", category: Logger.tabs)
    }

    /// Updates an existing user style.
    ///
    /// Triggers script regeneration if the style is enabled.
    ///
    /// - Parameter style: The style that was modified.
    func update(_ style: UserStyle) {
        style.lastUpdatedAt = Date()
        saveAndReload()
        Logger.info("Updated user style: \(style.name)", category: Logger.tabs)
    }

    /// Deletes a user style.
    ///
    /// - Parameter style: The style to delete.
    func delete(_ style: UserStyle) {
        let name = style.name
        modelContext.delete(style)
        saveAndReload()
        Logger.info("Deleted user style: \(name)", category: Logger.tabs)
    }

    /// Toggles a style's enabled state.
    ///
    /// - Parameter style: The style to toggle.
    func toggleEnabled(_ style: UserStyle) {
        style.isEnabled.toggle()
        saveAndReload()
        Logger.info("Toggled user style: \(style.name) enabled=\(style.isEnabled)", category: Logger.tabs)
    }

    private func saveAndReload() {
        do {
            try modelContext.save()
            loadStyles()
            rebuildInjectionScript()
        } catch {
            Logger.error("Failed to save user styles: \(error)", category: Logger.tabs)
        }
    }

    // MARK: - URL Matching

    /// Returns all enabled styles that match a URL.
    ///
    /// Styles are returned in installation order (oldest first) to maintain
    /// consistent CSS cascade behavior.
    ///
    /// - Parameter url: The URL to match styles for.
    /// - Returns: Array of matching enabled styles.
    func stylesForURL(_ url: URL) -> [UserStyle] {
        patternMatcher.matchingStyles(styles, for: url, enabledOnly: true)
    }

    /// Returns all styles (enabled and disabled) that match a URL.
    ///
    /// - Parameter url: The URL to match styles for.
    /// - Returns: Array of all matching styles.
    func allStylesForURL(_ url: URL) -> [UserStyle] {
        patternMatcher.matchingStyles(styles, for: url, enabledOnly: false)
    }

    /// Checks if any enabled styles match a URL.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: Whether any enabled styles apply.
    func hasStylesForURL(_ url: URL) -> Bool {
        !stylesForURL(url).isEmpty
    }

    // MARK: - Style by ID

    /// Finds a style by its ID.
    ///
    /// - Parameter id: The style's unique identifier.
    /// - Returns: The style, or nil if not found.
    func style(for id: UUID) -> UserStyle? {
        styles.first { $0.id == id }
    }

    // MARK: - Script Injection

    /// Generates the CSS injection script for matching styles.
    ///
    /// Creates JavaScript that injects `<style>` elements for each style.
    /// Each style gets a unique ID for later updates or removal.
    ///
    /// - Parameter matchingStyles: Styles to inject.
    /// - Returns: JavaScript source code.
    func injectionScript(for matchingStyles: [UserStyle]) -> String {
        guard !matchingStyles.isEmpty else { return "" }

        return matchingStyles.map { styleInjectionScript(for: $0) }.joined(separator: "\n")
    }

    private func styleInjectionScript(for style: UserStyle) -> String {
        let escapedCSS = CSSImportantInjector.escapeForJavaScript(importantInjector.process(style.css))

        return """
        (function() {
            const style = document.createElement('style');
            style.id = 'refrax-userstyle-\(style.id.uuidString)';
            style.textContent = `\(escapedCSS)`;
            (document.head || document.documentElement).appendChild(style);
        })();
        """
    }

    /// Rebuilds the user script injection for all enabled styles.
    ///
    /// Called when styles change. Updates the script registry with new content.
    private func rebuildInjectionScript() {
        guard let scriptRegistry, let userContentController else { return }

        if let id = styleScriptID {
            scriptRegistry.unregister(id: id)
            styleScriptID = nil
        }

        let enabledStyles = styles.filter(\.isEnabled)
        let script = injectionScript(for: enabledStyles)

        if !script.isEmpty {
            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: WKContentWorld.world(name: "RefraxScripts"),
            )

            styleScriptID = scriptRegistry.register(
                userScript,
                source: .extension(id: "userStyles"),
                priority: ScriptRegistry.Priority.extension,
            )

            Logger.info("Rebuilt user style injection with \(enabledStyles.count) styles", category: Logger.tabs)
        }

        scriptRegistry.apply(to: userContentController)
    }

    // MARK: - Live Preview

    /// Injects preview CSS into a WebPage.
    ///
    /// Used during style editing to show live changes without saving.
    /// Call `removePreview` to revert.
    ///
    /// - Parameters:
    ///   - css: The CSS to preview (raw, not processed).
    ///   - id: Unique ID for the preview style element.
    ///   - webPage: The WebPage to inject into.
    func previewStyle(_ css: String, id: UUID, in webPage: WebPage) async {
        let processedCSS = importantInjector.process(css)
        let escapedCSS = CSSImportantInjector.escapeForJavaScript(processedCSS)

        let script = """
        (function() {
            let style = document.getElementById('refrax-userstyle-\(id.uuidString)');
            if (!style) {
                style = document.createElement('style');
                style.id = 'refrax-userstyle-\(id.uuidString)';
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = `\(escapedCSS)`;
        })();
        """

        do {
            try await webPage.callJavaScript(script, in: nil, contentWorld: nil)
        } catch {
            Logger.error("Failed to inject preview style: \(error)", category: Logger.tabs)
        }
    }

    /// Removes a preview style from a WebPage.
    ///
    /// - Parameters:
    ///   - id: ID of the preview style element.
    ///   - webPage: The WebPage to remove from.
    func removePreview(id: UUID, from webPage: WebPage) async {
        let script = """
        document.getElementById('refrax-userstyle-\(id.uuidString)')?.remove();
        """

        do {
            try await webPage.callJavaScript(script, in: nil, contentWorld: nil)
        } catch {
            Logger.error("Failed to remove preview style: \(error)", category: Logger.tabs)
        }
    }

    // MARK: - Import

    /// Imports a style from UserCSS source.
    ///
    /// Parses the UserCSS format and creates a new style with extracted metadata.
    ///
    /// - Parameters:
    ///   - source: Raw UserCSS file content.
    ///   - sourceURL: URL the style was downloaded from (for updates).
    /// - Returns: The created style, or nil if parsing failed.
    @discardableResult
    func importUserCSS(_ source: String, sourceURL: URL? = nil) -> UserStyle? {
        guard let metadata = UserStyleMetadata.parse(source: source) else {
            Logger.error("Failed to parse UserCSS", category: Logger.tabs)
            return nil
        }

        let (domains, urls) = metadata.convertToPatterns()

        let style = UserStyle(
            name: metadata.name,
            css: metadata.strippedCSS.isEmpty ? source : metadata.strippedCSS,
            domainPatterns: domains,
            urlPatterns: urls,
        )

        style.styleDescription = metadata.description
        style.author = metadata.author
        style.version = metadata.version
        style.sourceURL = sourceURL ?? metadata.homepageURL
        style.updateURL = metadata.updateURL

        add(style)
        return style
    }

    /// Imports a style from a file URL.
    ///
    /// - Parameter fileURL: Local file URL to import from.
    /// - Returns: The created style, or nil if import failed.
    @discardableResult
    func importFromFile(_ fileURL: URL) -> UserStyle? {
        do {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            return importUserCSS(source)
        } catch {
            Logger.error("Failed to read style file: \(error)", category: Logger.tabs)
            return nil
        }
    }

    // MARK: - Grouped Styles

    /// Returns styles grouped by primary domain.
    ///
    /// Used for the style manager UI organized by domain.
    func stylesGroupedByDomain() -> [(domain: String, styles: [UserStyle])] {
        var groups: [String: [UserStyle]] = [:]

        for style in styles {
            let domain = style.primaryDomain
            groups[domain, default: []].append(style)
        }

        // Sort: Global first, then alphabetically, Disabled last
        let sorted = groups.sorted { lhs, rhs in
            if lhs.key == "Global" { return true }
            if rhs.key == "Global" { return false }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }

        return sorted.map { ($0.key, $0.value) }
    }
}

// MARK: - Update Checking

extension UserStyleManager {
    /// Checks for updates to remote styles.
    ///
    /// Fetches update URLs for all styles with remote sources and compares
    /// content hashes to detect changes.
    func checkForUpdates() async {
        let remoteStyles = styles.filter { $0.updateURL != nil || $0.sourceURL != nil }
        guard !remoteStyles.isEmpty else { return }

        Logger.info("Checking updates for \(remoteStyles.count) remote styles", category: Logger.tabs)

        for style in remoteStyles {
            await checkUpdate(for: style)
        }
    }

    private func checkUpdate(for style: UserStyle) async {
        guard let updateURL = style.updateURL ?? style.sourceURL else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: updateURL)
            guard let source = String(data: data, encoding: .utf8) else { return }

            let newHash = UserStyle.computeHash(source)
            style.lastUpdateCheckAt = Date()

            if newHash != style.sourceHash {
                // Update available
                Logger.info("Update available for style: \(style.name)", category: Logger.tabs)

                // Parse and apply update
                if let metadata = UserStyleMetadata.parse(source: source) {
                    style.updateCSS(metadata.strippedCSS.isEmpty ? source : metadata.strippedCSS)
                    style.version = metadata.version

                    let (domains, urls) = metadata.convertToPatterns()
                    if !domains.isEmpty { style.domainPatterns = domains }
                    if !urls.isEmpty { style.urlPatterns = urls }

                    saveAndReload()
                }
            }
        } catch {
            Logger.debug("Update check failed for \(style.name): \(error)", category: Logger.tabs)
        }
    }
}
