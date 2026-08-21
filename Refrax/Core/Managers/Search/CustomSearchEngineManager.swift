import Foundation
import Observation
import SwiftData

/// Manages custom search engines with CRUD operations and an in-memory cache.
///
/// Maintains a synchronized cache of ``SearchEngine`` values for fast access
/// by the Command Lens provider pipeline. Mutations persist to SwiftData and
/// refresh the cache immediately.
///
/// ## Architecture
///
/// This is a `@MainActor` `@Observable` manager (not a `@ModelActor`) because
/// it needs to be available synchronously in the CommandLens provider pipeline.
/// It holds an in-memory `cachedEngines` array that's refreshed on every mutation.
///
/// ## Deduplication
///
/// Auto-detected engines are deduplicated by `sourceDomain` to prevent
/// re-prompting for sites the user has already declined or added.
@Observable
final class CustomSearchEngineManager {
    /// Cached search engines for fast access by providers.
    private(set) var cachedEngines: [SearchEngine] = []

    /// The underlying SwiftData model context.
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshCache()
    }

    // MARK: - Queries

    /// Whether an engine already exists for the given source domain.
    func engineExists(forDomain domain: String) -> Bool {
        let descriptor = FetchDescriptor<CustomSearchEngine>(
            predicate: #Predicate { $0.sourceDomain == domain },
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    /// Whether an alias is already in use (custom or built-in).
    func aliasExists(_ alias: String) -> Bool {
        let lowercased = alias.lowercased()

        // Check built-in engine short names
        if SearchEngine.builtIns.contains(where: { $0.shortName.lowercased() == lowercased }) {
            return true
        }

        // Check custom engines
        let descriptor = FetchDescriptor<CustomSearchEngine>(
            predicate: #Predicate { $0.alias == lowercased },
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    /// All custom engine models, sorted by sort order then name.
    func allModels() -> [CustomSearchEngine] {
        var descriptor = FetchDescriptor<CustomSearchEngine>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.name),
            ],
        )
        descriptor.fetchLimit = 100
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Mutations

    /// Adds a new custom search engine.
    @discardableResult
    func add(
        name: String,
        alias: String,
        searchURLTemplate: String,
        suggestionURLTemplate: String? = nil,
        parserKind: SuggestionParserKind = .openSearch,
        iconName: String = "globe",
        sourceDomain: String? = nil,
        isAutoDetected: Bool = false,
    ) -> CustomSearchEngine {
        let nextOrder = (allModels().last?.sortOrder ?? -1) + 1

        let engine = CustomSearchEngine(
            name: name,
            alias: alias.lowercased(),
            searchURLTemplate: searchURLTemplate,
            suggestionURLTemplate: suggestionURLTemplate,
            parserKind: parserKind,
            iconName: iconName,
            sourceDomain: sourceDomain,
            sortOrder: nextOrder,
            isAutoDetected: isAutoDetected,
        )

        modelContext.insert(engine)
        save()
        refreshCache()

        return engine
    }

    /// Deletes a custom search engine by ID.
    func delete(id: UUID) {
        let descriptor = FetchDescriptor<CustomSearchEngine>(
            predicate: #Predicate { $0.id == id },
        )

        guard let engine = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(engine)
        save()
        refreshCache()
    }

    /// Updates a custom search engine's properties.
    func update(
        id: UUID,
        name: String? = nil,
        alias: String? = nil,
        searchURLTemplate: String? = nil,
        suggestionURLTemplate: String?? = nil,
        iconName: String? = nil,
    ) {
        let descriptor = FetchDescriptor<CustomSearchEngine>(
            predicate: #Predicate { $0.id == id },
        )

        guard let engine = try? modelContext.fetch(descriptor).first else { return }

        if let name { engine.name = name }
        if let alias { engine.alias = alias.lowercased() }
        if let searchURLTemplate { engine.searchURLTemplate = searchURLTemplate }
        if let suggestionURLTemplate { engine.suggestionURLTemplate = suggestionURLTemplate }
        if let iconName { engine.iconName = iconName }

        save()
        refreshCache()
    }

    // MARK: - Cache Management

    private func refreshCache() {
        cachedEngines = allModels().map { $0.makeSearchEngine() }
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - Detection Opt-Out

extension CustomSearchEngineManager {
    /// UserDefaults key storing domains the user opted out of detection prompts for.
    private static let ignoredDetectionDomainsKey = "searchEngineDetectionIgnoredDomains"

    /// Whether the user opted out of search engine detection prompts for a domain.
    func isDetectionIgnored(forDomain domain: String) -> Bool {
        let domains = UserDefaults.standard.stringArray(forKey: Self.ignoredDetectionDomainsKey) ?? []
        return domains.contains(domain)
    }

    /// Permanently suppresses search engine detection prompts for a domain.
    func ignoreDetection(forDomain domain: String) {
        var domains = UserDefaults.standard.stringArray(forKey: Self.ignoredDetectionDomainsKey) ?? []
        guard !domains.contains(domain) else { return }
        domains.append(domain)
        UserDefaults.standard.set(domains, forKey: Self.ignoredDetectionDomainsKey)
    }
}

// MARK: - Alias Generation

extension CustomSearchEngineManager {
    /// Well-known domain aliases for sites whose domain labels are too short
    /// or don't match their common name.
    private static let domainAliases: [String: String] = [
        "x": "twitter",
        "t": "tumblr",
    ]

    /// Generates a unique alias from a domain name.
    ///
    /// Uses well-known aliases for special domains (e.g., `x.com` → `twitter`),
    /// then falls back to the full domain label (e.g., `youtube.com` → `youtube`).
    /// If that alias is taken, appends a digit.
    func generateAlias(from domain: String) -> String {
        let label = domainLabel(from: domain)

        // Use well-known alias for domains with short/ambiguous labels
        if let knownAlias = Self.domainAliases[label], !aliasExists(knownAlias) {
            return knownAlias
        }

        if !aliasExists(label) {
            return label
        }

        // Append digits to disambiguate
        for i in 2 ... 9 {
            let candidate = "\(label)\(i)"
            if !aliasExists(candidate) {
                return candidate
            }
        }

        return label
    }

    /// Extracts the main label from a domain (e.g., "youtube" from "youtube.com").
    private func domainLabel(from domain: String) -> String {
        let parts = domain.lowercased().split(separator: ".")
        return String(parts.first ?? Substring(domain.lowercased()))
    }
}
