import SwiftUI

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case tabs
    case favorites
    case privacy
    case search
    case extensions
    case userCustomization
    case storage
    case sync
    case advanced
    case featureFlags

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .tabs: "Tabs"
        case .favorites: "Favorites"
        case .privacy: "Privacy"
        case .search: "Search"
        case .extensions: "Extensions"
        case .userCustomization: "User Content"
        case .storage: "Storage"
        case .sync: "iCloud Sync"
        case .advanced: "Advanced"
        case .featureFlags: "Feature Flags"
        }
    }

    /// SF Symbol name for the category icon.
    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .tabs: "square.stack.fill"
        case .favorites: "star.fill"
        case .privacy: "hand.raised.fill"
        case .search: "magnifyingglass"
        case .extensions: "puzzlepiece.extension.fill"
        case .userCustomization: "wand.and.stars"
        case .storage: "internaldrive"
        case .sync: "icloud.fill"
        case .advanced: "slider.horizontal.3"
        case .featureFlags: "flag.fill"
        }
    }

    /// Rendering mode for the sidebar icon.
    var iconRenderingMode: SymbolRenderingMode { .monochrome }

    var description: String {
        switch self {
        case .general:
            "Gestures, media, email links, downloads, and widgets."
        case .appearance:
            "Theme, colors, sidebar, and page appearance."
        case .tabs:
            "Previews, archive, snapshots, and time tracking."
        case .favorites:
            "App shortcuts in the favorites grid."
        case .privacy:
            "Tracking protection, history, cookies, and site settings."
        case .search:
            "Search engine and search shortcuts."
        case .extensions:
            "Browser extensions and their permissions."
        case .userCustomization:
            "User styles (CSS) and scripts (JavaScript) for websites."
        case .storage:
            "Storage usage, offline content, logs, and website caches."
        case .sync:
            "Sync tabs, bookmarks, history, and settings across your Macs."
        case .advanced:
            "JavaScript, pop-ups, security, and developer tools."
        case .featureFlags:
            "Experimental WebKit and browser feature flags."
        }
    }

    var searchableItems: [SearchableSettingItem] {
        // Derive from the registry for this category
        let fromRegistry = BrowserSettingKey.allCases
            .filter { $0.metadata.category == self }
            .map { key in
                let meta = key.metadata
                return SearchableSettingItem(
                    id: meta.highlightID,
                    title: meta.displayName,
                    keywords: meta.keywords,
                )
            }

        return fromRegistry + additionalItems
    }

    /// Non-setting searchable items (navigation targets, UI-only elements).
    private var additionalItems: [SearchableSettingItem] {
        switch self {
        case .general:
            [
                SearchableSettingItem(id: "general.mailHandler", title: "Email link handler", keywords: ["mail", "mailto", "email", "handler", "app"]),
                SearchableSettingItem(id: "general.calendarLookAhead", title: "Calendar look-ahead", keywords: ["calendar", "look", "ahead", "hours", "events"]),
                SearchableSettingItem(id: "general.calendarAutoExpand", title: "Calendar auto-expand", keywords: ["calendar", "auto", "expand", "imminent", "events"]),
                SearchableSettingItem(id: "general.downloadDirectory", title: "Download location", keywords: ["download", "downloads", "folder", "directory", "save", "location"]),
                SearchableSettingItem(id: "external.enable", title: "External URL handling", keywords: ["external", "url", "handling", "links", "default browser"]),
                SearchableSettingItem(id: "external.defaultBehavior", title: "External URL default behavior", keywords: ["external", "url", "default", "behavior", "window", "glimpse", "space"]),
                SearchableSettingItem(id: "external.urlRules", title: "External URL rules", keywords: ["external", "url", "rules", "domain", "pattern"]),
                SearchableSettingItem(id: "external.sourceAppRules", title: "Source app rules", keywords: ["external", "source", "app", "application", "rules"]),
            ]
        case .appearance:
            [
                SearchableSettingItem(id: "appearance.theme", title: "Appearance theme", keywords: ["theme", "appearance", "light", "dark", "mode"]),
                SearchableSettingItem(id: "appearance.accentColor", title: "Accent color", keywords: ["accent", "color", "tint", "theme"]),
                SearchableSettingItem(id: "appearance.sidebarMode", title: "Default sidebar mode", keywords: ["sidebar", "mode", "compact", "overlay"]),
                SearchableSettingItem(id: "appearance.windowBackground", title: "Window background color", keywords: ["window", "background", "color"]),
                SearchableSettingItem(id: "appearance.mixAmount", title: "Color blend strength", keywords: ["mix", "amount", "strength", "intensity", "blend"]),
                SearchableSettingItem(id: "appearance.mixMode", title: "Color blend mode", keywords: ["blend", "mode", "mixing", "overlay", "soft light"]),
            ]
        case .tabs:
            [
                SearchableSettingItem(id: "tabs.archiveExpiration", title: "Archive expiration", keywords: ["archive", "expiration", "clear", "hours", "days"]),
                SearchableSettingItem(id: "tabs.manageRules", title: "Manage auto-archive rules", keywords: ["manage", "rules", "edit", "add", "delete"]),
                SearchableSettingItem(id: "tabs.snapshotRetention", title: "Snapshot retention", keywords: ["snapshot", "retention", "days", "keep"]),
                SearchableSettingItem(id: "tabs.maxSnapshots", title: "Maximum snapshots", keywords: ["snapshot", "maximum", "limit", "count"]),
                SearchableSettingItem(id: "tabs.timeLimits", title: "Daily time limits", keywords: ["time", "limit", "daily", "site", "domain"]),
            ]
        case .privacy:
            [
                SearchableSettingItem(id: "privacy.siteSettings", title: "Site settings", keywords: ["site", "settings", "domain", "permissions", "zoom", "javascript", "per-site"]),
                SearchableSettingItem(id: "privacy.gpcHeaderSites", title: "GPC header sites", keywords: ["gpc", "header", "sites", "allowed", "blocked"]),
                SearchableSettingItem(id: "privacy.nativeVideoControls", title: "Force native video controls", keywords: ["video", "controls", "native", "airplay", "pip"]),
                SearchableSettingItem(id: "privacy.videoSpeed", title: "Default video speed", keywords: ["video", "speed", "playback", "rate"]),
                SearchableSettingItem(id: "privacy.linkProtection", title: "Link protection", keywords: ["link", "protection", "tracking", "utm", "parameters"]),
                SearchableSettingItem(id: "privacy.trackingParameters", title: "Remove tracking parameters", keywords: ["tracking", "parameters", "utm", "fbclid", "gclid"]),
                SearchableSettingItem(id: "privacy.ampLinks", title: "Convert AMP links", keywords: ["amp", "google", "convert", "publisher"]),
                SearchableSettingItem(id: "privacy.urlShorteners", title: "Expand URL shorteners", keywords: ["url", "shortener", "bit.ly", "t.co", "expand"]),
                SearchableSettingItem(id: "privacy.customRedirects", title: "Custom redirects", keywords: ["redirect", "custom", "nitter", "twitter"]),
                SearchableSettingItem(id: "privacy.appRedirects", title: "App redirects", keywords: ["app", "redirect", "open", "external"]),
                SearchableSettingItem(id: "privacy.routingRules", title: "URL routing rules", keywords: ["routing", "rules", "url", "redirect", "space", "group", "glimpse", "automatic"]),
                SearchableSettingItem(id: "privacy.lockTimeout", title: "Space locking timeout", keywords: ["lock", "touch id", "space", "timeout", "auto-lock", "password", "authentication"]),
                SearchableSettingItem(id: "privacy.retentionPeriod", title: "History retention period", keywords: ["history", "retention", "days", "week", "month", "year"]),
                SearchableSettingItem(id: "privacy.clearHistory", title: "Clear all history", keywords: ["history", "clear", "delete", "remove", "all"]),
                SearchableSettingItem(id: "privacy.clearDomainHistory", title: "Clear history for site", keywords: ["history", "clear", "delete", "domain", "site"]),
                SearchableSettingItem(id: "privacy.cookieInspector", title: "Cookie inspector", keywords: ["cookie", "inspect", "view", "manage", "delete"]),
            ]
        case .favorites:
            [
                SearchableSettingItem(id: "favorites.appShortcuts", title: "App shortcuts", keywords: ["shortcuts", "downloads", "bookmarks", "history", "settings", "app"]),
                SearchableSettingItem(id: "favorites.downloadsShortcut", title: "Downloads shortcut", keywords: ["downloads", "shortcut", "tray"]),
                SearchableSettingItem(id: "favorites.bookmarksShortcut", title: "Bookmarks shortcut", keywords: ["bookmarks", "shortcut", "tray"]),
                SearchableSettingItem(id: "favorites.historyShortcut", title: "History shortcut", keywords: ["history", "shortcut", "tray"]),
                SearchableSettingItem(id: "favorites.settingsShortcut", title: "Settings shortcut", keywords: ["settings", "shortcut", "preferences"]),
            ]
        case .search:
            [
                SearchableSettingItem(id: "search.engine", title: "Default search engine", keywords: ["search", "engine", "default", "google", "duckduckgo", "abbreviation", "tab"]),
            ]
        case .extensions:
            [
                SearchableSettingItem(id: "extensions.installed", title: "Installed extensions", keywords: ["extensions", "installed", "plugins", "addons"]),
                SearchableSettingItem(id: "extensions.gallery", title: "Extension gallery", keywords: ["gallery", "browse", "chrome", "firefox"]),
                SearchableSettingItem(id: "extensions.install", title: "Install extension", keywords: ["install", "add", "extension", "crx", "xpi"]),
            ]
        case .userCustomization:
            [
                SearchableSettingItem(id: "userStyles.installed", title: "Installed styles", keywords: ["styles", "css", "installed", "custom"]),
                SearchableSettingItem(id: "userStyles.create", title: "Create new style", keywords: ["create", "new", "style", "css"]),
                SearchableSettingItem(id: "userStyles.import", title: "Import style", keywords: ["import", "install", "userstyles", "usercss"]),
                SearchableSettingItem(id: "userScripts.installed", title: "Installed scripts", keywords: ["scripts", "javascript", "js", "installed", "greasemonkey", "tampermonkey"]),
                SearchableSettingItem(id: "userScripts.create", title: "Create new script", keywords: ["create", "new", "script", "javascript"]),
                SearchableSettingItem(id: "userScripts.import", title: "Import script", keywords: ["import", "install", "userscript", "user.js"]),
            ]
        case .sync:
            [
                SearchableSettingItem(id: "sync.enabled", title: "Sync with iCloud", keywords: ["icloud", "sync", "cloud", "enabled"]),
                SearchableSettingItem(id: "sync.status", title: "Sync status", keywords: ["sync", "status", "last", "synced"]),
                SearchableSettingItem(id: "sync.account", title: "iCloud account", keywords: ["icloud", "account", "apple"]),
                SearchableSettingItem(id: "sync.reset", title: "Reset sync data", keywords: ["reset", "sync", "data", "clear"]),
            ]
        case .storage:
            [
                SearchableSettingItem(id: "storage.total", title: "Total storage used", keywords: ["storage", "total", "size", "disk", "space"]),
                SearchableSettingItem(id: "storage.offline", title: "Offline content", keywords: ["offline", "saved", "pages", "content"]),
                SearchableSettingItem(id: "storage.logs", title: "Logs", keywords: ["logs", "diagnostic", "debug"]),
                SearchableSettingItem(id: "storage.extensions", title: "Extensions storage", keywords: ["extensions", "plugins", "addons"]),
                SearchableSettingItem(id: "storage.conversations", title: "Agent conversations", keywords: ["agent", "conversations", "ai", "chat", "history"]),
                SearchableSettingItem(id: "storage.database", title: "Database", keywords: ["database", "tabs", "bookmarks", "history", "settings"]),
                SearchableSettingItem(id: "storage.clearCaches", title: "Clear website caches", keywords: ["website", "cache", "webkit", "clear", "service", "workers"]),
                SearchableSettingItem(id: "storage.clearCookies", title: "Clear cookies and sessions", keywords: ["cookies", "sessions", "login", "localStorage", "indexedDB", "clear"]),
                SearchableSettingItem(id: "storage.clearAllData", title: "Clear all website data", keywords: ["clear", "all", "website", "data", "offline", "logs"]),
                SearchableSettingItem(id: "storage.fullReset", title: "Full reset", keywords: ["reset", "erase", "factory", "fresh", "install", "wipe", "nuclear"]),
            ]
        case .advanced:
            [
                SearchableSettingItem(id: "advanced.javascriptSites", title: "Manage JavaScript sites", keywords: ["javascript", "js", "whitelist", "sites", "domains"]),
                SearchableSettingItem(id: "advanced.crashThreshold", title: "Crash threshold", keywords: ["crash", "threshold", "limit", "count"]),
                SearchableSettingItem(id: "advanced.crashTimeWindow", title: "Crash time window", keywords: ["crash", "time", "window", "seconds"]),
                SearchableSettingItem(id: "advanced.reset", title: "Reset all settings", keywords: ["reset", "restore", "defaults", "clear"]),
            ]
        case .featureFlags:
            FeatureFlagDefinition.all.map { flag in
                SearchableSettingItem(
                    id: "featureFlags.\(flag.key)",
                    title: flag.name,
                    keywords: flag.name.lowercased().split(separator: " ").map(String.init) + ["feature", "flag", "experimental"]
                )
            }
        }
    }

    func matches(searchText: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        let lowercasedSearch = searchText.lowercased()
        return title.lowercased().contains(lowercasedSearch) ||
            searchableItems.contains { $0.matches(searchText: lowercasedSearch) }
    }
}

// MARK: - Searchable Setting Item

struct SearchableSettingItem: Identifiable, Equatable {
    let id: String
    let title: String
    let keywords: [String]

    func matches(searchText: String) -> Bool {
        let lowercasedSearch = searchText.lowercased()
        return title.lowercased().contains(lowercasedSearch) ||
            keywords.contains { $0.contains(lowercasedSearch) }
    }
}

// MARK: - Sidebar View

struct SettingsSidebarView: View {
    @Binding var selectedCategory: SettingsCategory
    @Binding var searchText: String
    @Binding var highlightedItemId: String?

    private var searchResults: [(category: SettingsCategory, items: [SearchableSettingItem])] {
        guard !searchText.isEmpty else {
            return SettingsCategory.allCases.map { ($0, []) }
        }

        return SettingsCategory.allCases.compactMap { category in
            let matchedItems = category.searchableItems.filter { $0.matches(searchText: searchText.lowercased()) }
            return matchedItems.isEmpty ? nil : (category, matchedItems)
        }
    }

    var body: some View {
        List(selection: $selectedCategory) {
            if searchText.isEmpty {
                // Show all categories when not searching
                ForEach(SettingsCategory.allCases) { category in
                    Label {
                        Text(category.title)
                    } icon: {
                        Image(systemName: category.icon)
                            .symbolRenderingMode(category.iconRenderingMode)
                            .foregroundStyle(Color.appAccentColor)
                    }
                    .tag(category)
                }
            } else {
                // Show categories with matching items
                ForEach(searchResults, id: \.category.id) { result in
                    Section {
                        ForEach(result.items) { item in
                            Button {
                                selectedCategory = result.category
                                highlightedItemId = item.id
                                // Clear highlight after animation completes
                                Task {
                                    try? await Task.sleep(for: .seconds(1.8))
                                    highlightedItemId = nil
                                }
                            } label: {
                                HStack {
                                    Text(item.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label(result.category.title, systemImage: result.category.icon)
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search Settings")
        .navigationTitle("Settings")
        .frame(minWidth: 220)
        .tint(Color.appAccentColor)
    }
}

// MARK: - Content View

struct SettingsContentView: View {
    let selectedCategory: SettingsCategory
    let highlightedItemId: String?

    var body: some View {
        Group {
            switch selectedCategory {
            case .general:
                GeneralSettingsView(highlightedItemId: highlightedItemId)
            case .appearance:
                AppearanceSettingsView(highlightedItemId: highlightedItemId)
            case .tabs:
                TabsSettingsView(highlightedItemId: highlightedItemId)
            case .favorites:
                FavoritesSettingsView(highlightedItemId: highlightedItemId)
            case .privacy:
                PrivacySettingsView(highlightedItemId: highlightedItemId)
            case .search:
                SearchSettingsView(highlightedItemId: highlightedItemId)
            case .extensions:
                ExtensionSettingsView(highlightedItemId: highlightedItemId)
            case .userCustomization:
                UserCustomizationSettingsView(highlightedItemId: highlightedItemId)
            case .storage:
                StorageSettingsView(highlightedItemId: highlightedItemId)
            case .sync:
                SyncSettingsView(highlightedItemId: highlightedItemId)
            case .advanced:
                AdvancedSettingsView(highlightedItemId: highlightedItemId)
            case .featureFlags:
                FeatureFlagsSettingsView(highlightedItemId: highlightedItemId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) {
            // Needs to have something to trigger the `scrollEdgeEffectStyle`
            Text(" ")
                .frame(width: 1, height: 42)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle(selectedCategory.title)
        .ignoresSafeArea(edges: .vertical)
    }
}

// MARK: - Highlight Modifier

private struct HighlightModifier: ViewModifier {
    let itemId: String
    let highlightedItemId: String?

    @State private var isAnimating = false

    private var isHighlighted: Bool {
        highlightedItemId == itemId
    }

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.appAccentColor.opacity(0.15) : Color.clear)
                    .animation(.easeInOut(duration: 0.3), value: isHighlighted),
            )
            .onChange(of: highlightedItemId) { _, newValue in
                if newValue == itemId {
                    withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true)) {
                        isAnimating = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.8))
                        isAnimating = false
                    }
                }
            }
    }
}

extension View {
    func highlightable(id: String, highlightedItemId: String?) -> some View {
        modifier(HighlightModifier(itemId: id, highlightedItemId: highlightedItemId))
    }
}
