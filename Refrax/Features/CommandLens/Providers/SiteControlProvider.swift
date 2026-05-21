import Foundation

/// Provides site-specific settings control suggestions.
///
/// When the user types queries like "block javascript", "allow popups",
/// or "disable content blockers", this provider shows per-site settings
/// that can be toggled for the current domain.
struct SiteControlProvider: CommandLensSuggestionProvider {
    let id = "site-control"
    let priority = 30 // Just below global settings
    let groupHeader: String? = nil // Will use domain as header
    let maxSuggestions = 5

    private let siteSettingsManager: SiteSettingsManager
    private let browserSettings: BrowserSettings

    init(siteSettingsManager: SiteSettingsManager, browserSettings: BrowserSettings) {
        self.siteSettingsManager = siteSettingsManager
        self.browserSettings = browserSettings
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        // Only provide when there's input and a current domain
        !context.isEmptyInput && !context.isDirectURL && context.currentDomain != nil
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        guard let domain = context.currentDomain else { return [] }

        let query = context.input.lowercased()

        // Get or create site settings for this domain
        let siteSettings = siteSettingsManager.settings(for: domain)

        // Score each site setting definition against the query
        var matches: [(definition: SiteSettingDefinition, score: Double)] = []

        for definition in SiteSettingDefinition.allSettings {
            let terms = [definition.displayName] + definition.synonyms
            let score = FuzzyMatcher.match(query: query, against: terms)

            if score >= FuzzyMatcher.minimumMatchScore {
                matches.append((definition, score))
            }
        }

        // Sort by score descending and take top results
        let topMatches = matches
            .sorted { $0.score > $1.score }
            .prefix(maxSuggestions)

        // Convert to suggestions
        return topMatches.enumerated().map { index, match -> CommandLensSuggestion in
            let definition = match.definition
            let currentValue = definition.getCurrentValue(siteSettings, browserSettings: browserSettings)

            return CommandLensSuggestion(
                type: .setting(key: definition.key, scope: .perSite(domain: domain)),
                text: "\(definition.displayName) for \(domain)",
                description: currentValue,
                iconName: definition.icon,
                groupHeader: index == 0 ? "Site Settings" : nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
    }
}

// MARK: - Site Setting Definitions

/// Defines a per-site setting that can be controlled via Command Lens.
struct SiteSettingDefinition: Sendable, Equatable {
    let key: String
    let displayName: String
    let synonyms: [String]
    let icon: String

    /// Gets the current value as a display string.
    func getCurrentValue(_ siteSettings: SiteSettings?, browserSettings _: BrowserSettings) -> String {
        guard let siteSettings else {
            return "Using Default"
        }

        switch key {
        case "allowJavaScript":
            return siteSettings.allowJavaScript ? "Allowed" : "Blocked"
        case "enableContentBlockers":
            return siteSettings.enableContentBlockers ? "Enabled" : "Disabled"
        case "popUpPolicy":
            return siteSettings.popUpPolicy.displayName
        case "autoPlayPolicy":
            return siteSettings.autoPlayPolicy.displayName
        case "useReaderWhenAvailable":
            return siteSettings.useReaderWhenAvailable ? "On" : "Off"
        case "disableAutoConsent":
            return siteSettings.disableAutoConsent ? "Disabled" : "Enabled"
        default:
            return ""
        }
    }

    /// Toggles the site setting value.
    func toggle(_ siteSettings: SiteSettings) {
        switch key {
        case "allowJavaScript":
            siteSettings.allowJavaScript.toggle()
        case "enableContentBlockers":
            siteSettings.enableContentBlockers.toggle()
        case "popUpPolicy":
            // Cycle through: blockAndNotify -> allow -> block -> blockAndNotify
            switch siteSettings.popUpPolicy {
            case .blockAndNotify:
                siteSettings.popUpPolicy = .allow
            case .allow:
                siteSettings.popUpPolicy = .block
            case .block:
                siteSettings.popUpPolicy = .blockAndNotify
            }
        case "autoPlayPolicy":
            // Cycle through: stopMediaWithSound -> neverAutoPlay -> allowAll -> stopMediaWithSound
            switch siteSettings.autoPlayPolicy {
            case .stopMediaWithSound:
                siteSettings.autoPlayPolicy = .neverAutoPlay
            case .neverAutoPlay:
                siteSettings.autoPlayPolicy = .allowAll
            case .allowAll:
                siteSettings.autoPlayPolicy = .stopMediaWithSound
            }
        case "useReaderWhenAvailable":
            siteSettings.useReaderWhenAvailable.toggle()
        case "disableAutoConsent":
            siteSettings.disableAutoConsent.toggle()
        default:
            break
        }
    }
}

// MARK: - All Site Settings

extension SiteSettingDefinition {
    /// All site settings available for control via Command Lens.
    static let allSettings: [SiteSettingDefinition] = [
        SiteSettingDefinition(
            key: "allowJavaScript",
            displayName: "JavaScript",
            synonyms: ["js", "javascript", "scripts", "enable javascript", "disable javascript", "block javascript"],
            icon: "curlybraces",
        ),
        SiteSettingDefinition(
            key: "enableContentBlockers",
            displayName: "Content Blockers",
            synonyms: ["ad blocker", "ads", "content blocking", "block ads", "tracking protection"],
            icon: "shield.fill",
        ),
        SiteSettingDefinition(
            key: "popUpPolicy",
            displayName: "Pop-ups",
            synonyms: ["popups", "pop ups", "popup windows", "allow popups", "block popups"],
            icon: "rectangle.on.rectangle",
        ),
        SiteSettingDefinition(
            key: "autoPlayPolicy",
            displayName: "Auto-play",
            synonyms: ["autoplay", "auto play", "video autoplay", "media autoplay"],
            icon: "play.fill",
        ),
        SiteSettingDefinition(
            key: "useReaderWhenAvailable",
            displayName: "Reader Mode",
            synonyms: ["reader", "reading mode", "reader view", "auto reader"],
            icon: "doc.text",
        ),
        SiteSettingDefinition(
            key: "disableAutoConsent",
            displayName: "Cookie Consent",
            synonyms: ["cookie consent", "gdpr", "cookie popup", "consent banner"],
            icon: "checkmark.shield.fill",
        ),
    ]

    /// Finds a site setting definition by key.
    static func find(key: String) -> SiteSettingDefinition? {
        allSettings.first { $0.key == key }
    }
}
