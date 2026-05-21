import CoreSpotlight
import SwiftUI
import WebKit

// MARK: - Storage Settings

struct StorageSettingsView: View {
    let highlightedItemId: String?

    @Environment(BrowserSettings.self) private var settings

    @State private var storageItems: [StorageItem] = []
    @State private var isCalculating = true
    @State private var totalSize: Int64 = 0
    @State private var isClearing = false
    @State private var activeClearTier: ClearTier?

    @State private var showClearCachesAlert = false
    @State private var showClearCookiesAlert = false
    @State private var showClearAllDataAlert = false
    @State private var showFullResetAlert = false

    var body: some View {
        Form {
            storageBreakdownSection
            clearCachesSection
            clearCookiesSection
            clearAllDataSection
            fullResetSection
        }
        .formStyle(.grouped)
        .task { await calculateStorage() }
        .alert("Clear Website Caches", isPresented: $showClearCachesAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Caches", role: .destructive) {
                Task { await performTieredClear(.caches) }
            }
        } message: {
            Text("Removes cached pages, images, service workers, and other temporary data. Pages may load slower until caches are rebuilt.")
        }
        .alert("Clear Cookies & Login Sessions", isPresented: $showClearCookiesAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Cookies", role: .destructive) {
                Task { await performTieredClear(.cookies) }
            }
        } message: {
            Text("You will be logged out of all websites. Cached data is not affected, so pages will still load quickly.")
        }
        .alert("Clear All Website Data", isPresented: $showClearAllDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Data", role: .destructive) {
                Task { await performTieredClear(.allWebsiteData) }
            }
        } message: {
            Text("Removes all website data (caches, cookies, local storage), offline content, logs, and agent conversations. This cannot be undone.")
        }
        .alert("Erase All Content and Settings", isPresented: $showFullResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Erase Everything and Restart", role: .destructive) {
                Task { await performFullReset() }
            }
        } message: {
            Text("All tabs, bookmarks, history, settings, extensions, user scripts, and website data will be permanently deleted. Your activation status is preserved. Refrax will quit and relaunch.")
        }
    }

    // MARK: - Sections

    private var storageBreakdownSection: some View {
        Group {
            Section {
                if isCalculating {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating storage usage…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text("Total Storage Used")
                        Spacer()
                        Text(formattedSize(totalSize))
                            .foregroundStyle(.secondary)
                    }
                    .highlightable(id: "storage.total", highlightedItemId: highlightedItemId)
                }
            }

            Section("Storage Breakdown") {
                ForEach(storageItems) { item in
                    storageRow(item)
                }
            }
        }
    }

    private var clearCachesSection: some View {
        Section {
            clearButton(
                title: "Clear Website Caches…",
                tier: .caches,
                alert: $showClearCachesAlert,
                highlightID: "storage.clearCaches"
            )
        } header: {
            Text("Website Caches")
        } footer: {
            Text("Removes cached pages, images, service workers, and other temporary data from all websites. Cookies, localStorage, and login sessions are not affected.")
        }
    }

    private var clearCookiesSection: some View {
        Section {
            clearButton(
                title: "Clear Cookies & Login Sessions…",
                tier: .cookies,
                alert: $showClearCookiesAlert,
                highlightID: "storage.clearCookies"
            )
        } footer: {
            Text("Removes all cookies, localStorage, IndexedDB, and session data. You will be logged out of all websites. Cached data is not affected.")
        }
    }

    private var clearAllDataSection: some View {
        Section {
            clearButton(
                title: "Clear All Website Data…",
                tier: .allWebsiteData,
                isDestructive: true,
                alert: $showClearAllDataAlert,
                highlightID: "storage.clearAllData"
            )
        } footer: {
            Text("Removes all website data, offline content, logs, and agent conversations. Does not delete bookmarks, tabs, history, settings, or extensions.")
        }
    }

    private var fullResetSection: some View {
        Section {
            clearButton(
                title: "Erase All Content and Settings…",
                tier: .fullReset,
                isDestructive: true,
                alert: $showFullResetAlert,
                highlightID: "storage.fullReset"
            )
        } footer: {
            Text("Returns Refrax to a fresh install state. Everything is deleted except your activation status. Refrax will quit and relaunch.")
        }
    }

    @ViewBuilder
    private func clearButton(
        title: String,
        tier: ClearTier,
        isDestructive: Bool = false,
        alert: Binding<Bool>,
        highlightID: String,
    ) -> some View {
        if activeClearTier == tier {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(tier.progressLabel)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button(title, role: isDestructive ? .destructive : nil) {
                alert.wrappedValue = true
            }
            .disabled(isClearing)
            .highlightable(id: highlightID, highlightedItemId: highlightedItemId)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func storageRow(_ item: StorageItem) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: item.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            Spacer()
            if item.isClearing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(formattedSize(item.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if item.clearAction != nil {
                Button {
                    Task { await clearItem(item) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(item.size == 0 || isClearing)
                .help("Clear \(item.name.lowercased())")
            }
        }
        .highlightable(id: "storage.\(item.id)", highlightedItemId: highlightedItemId)
    }

    // MARK: - Calculation

    @MainActor
    private func calculateStorage() async {
        isCalculating = true

        let items = await Task.detached {
            var results: [StorageItem] = []

            let offlineSize = Self.directorySize(
                Directories.appStorage.appendingPathComponent("OfflineContent")
            )
            results.append(StorageItem(
                id: "offline",
                name: "Offline Content",
                detail: "Saved web pages for offline reading",
                icon: "arrow.down.circle",
                size: offlineSize,
                clearAction: { await Self.clearDirectory("OfflineContent") }
            ))

            let logsSize = Self.directorySize(
                Directories.appStorage.appendingPathComponent("Logs")
            )
            results.append(StorageItem(
                id: "logs",
                name: "Logs",
                detail: "Diagnostic logs (auto-pruned after 7 days)",
                icon: "doc.text",
                size: logsSize,
                clearAction: { await Self.clearDirectory("Logs") }
            ))

            let extensionsSize = Self.directorySize(
                Directories.appStorage.appendingPathComponent("Extensions")
            )
            results.append(StorageItem(
                id: "extensions",
                name: "Extensions",
                detail: "Installed browser extensions",
                icon: "puzzlepiece.extension",
                size: extensionsSize,
                clearAction: nil
            ))

            let conversationsSize = Self.directorySize(
                Directories.appStorage
                    .appendingPathComponent("agent")
                    .appendingPathComponent("conversations")
            )
            results.append(StorageItem(
                id: "conversations",
                name: "Agent Conversations",
                detail: "Saved AI conversation history",
                icon: "bubble.left.and.bubble.right",
                size: conversationsSize,
                clearAction: { await Self.clearDirectory("agent/conversations") }
            ))

            let dbSize = Self.fileSize(
                Directories.appStorage.appendingPathComponent("default.store")
            )
            results.append(StorageItem(
                id: "database",
                name: "Database",
                detail: "Tabs, bookmarks, history, and settings",
                icon: "cylinder",
                size: dbSize,
                clearAction: nil
            ))

            return results
        }.value

        storageItems = items
        totalSize = items.reduce(0) { $0 + $1.size }
        isCalculating = false
    }

    // MARK: - Tiered Clear Actions

    private func clearItem(_ item: StorageItem) async {
        guard let action = item.clearAction else { return }
        isClearing = true
        if let idx = storageItems.firstIndex(where: { $0.id == item.id }) {
            storageItems[idx].isClearing = true
        }
        await action()
        await calculateStorage()
        isClearing = false
    }

    private func performTieredClear(_ tier: ClearTier) async {
        isClearing = true
        activeClearTier = tier
        defer {
            isClearing = false
            activeClearTier = nil
        }

        switch tier {
        case .caches:
            await clearWebsiteCaches()
        case .cookies:
            await clearCookiesAndSessions()
        case .allWebsiteData:
            await clearAllWebsiteData()
        case .fullReset:
            break
        }

        await calculateStorage()
    }

    /// Tier 1: Clear website caches only (disk cache, memory cache, service workers, fetch cache).
    private func clearWebsiteCaches() async {
        let dataTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]

        await clearWebsiteDataFromAllStores(types: dataTypes)
        Logger.info("Cleared website caches (Tier 1)", category: Logger.storage)
    }

    /// Tier 2: Clear cookies, localStorage, IndexedDB, session data.
    private func clearCookiesAndSessions() async {
        let dataTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
        ]

        await clearWebsiteDataFromAllStores(types: dataTypes)
        Logger.info("Cleared cookies and login sessions (Tier 2)", category: Logger.storage)
    }

    /// Tier 3: Clear ALL WebKit data plus app storage directories.
    private func clearAllWebsiteData() async {
        // All WebKit data types from default store
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )

        // Remove all per-space data stores entirely (not just clear — remove)
        let identifiers = await fetchAllSpaceDataStoreIdentifiers()
        for identifier in identifiers {
            let store = WKWebsiteDataStore(forIdentifier: identifier)
            await store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            )
        }

        // Also wipe the WebKit cache directory on disk as a fallback.
        // WKWebsiteDataStore.removeData sometimes doesn't fully flush disk caches.
        let bundleID = Bundle.main.bundleIdentifier ?? "website.refrax.browser"
        let webkitCacheDir = Directories.caches.appendingPathComponent(bundleID)
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: webkitCacheDir, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fm.removeItem(at: item)
            }
        }

        // App storage directories
        await Self.clearDirectory("OfflineContent")
        await Self.clearDirectory("Logs")
        await Self.clearDirectory("agent/conversations")
        await Self.clearDirectory("Filters")

        Logger.info("Cleared all website data (Tier 3)", category: Logger.storage)
    }

    /// Clears the given WebKit data types from the default store and all per-space stores.
    private func clearWebsiteDataFromAllStores(types: Set<String>) async {
        // Default store
        await WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: .distantPast
        )

        // Per-space stores
        let identifiers = await fetchAllSpaceDataStoreIdentifiers()
        for identifier in identifiers {
            let store = WKWebsiteDataStore(forIdentifier: identifier)
            await store.removeData(ofTypes: types, modifiedSince: .distantPast)
        }
    }

    private func fetchAllSpaceDataStoreIdentifiers() async -> [UUID] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.fetchAllDataStoreIdentifiers { identifiers in
                continuation.resume(returning: identifiers)
            }
        }
    }

    // MARK: - Full Reset (Tier 4)

    private func performFullReset() async {
        isClearing = true
        activeClearTier = .fullReset

        // 1. Clear all WebKit data from all stores
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )

        // Remove all per-space data stores entirely
        let identifiers = await fetchAllSpaceDataStoreIdentifiers()
        for identifier in identifiers {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in
                    continuation.resume()
                }
            }
        }

        // 3. Clear Spotlight index
        try? await CSSearchableIndex.default().deleteAllSearchableItems()

        // 4. Wipe the entire app storage directory (SwiftData DB, logs, extensions, everything)
        let fm = FileManager.default
        let appStorage = Directories.appStorage
        if let contents = try? fm.contentsOfDirectory(at: appStorage, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fm.removeItem(at: item)
            }
        }

        // 5. Clear UserDefaults (window restoration state, preferences)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        Logger.info("Full reset completed (Tier 4), relaunching", category: Logger.storage)

        // 6. Relaunch
        AppDelegate.relaunchApp()
    }

    // MARK: - Helpers

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64
        else { return 0 }
        return size
    }

    @MainActor
    private static func clearDirectory(_ relativePath: String) async {
        let url = Directories.appStorage.appendingPathComponent(relativePath)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        for item in contents {
            try? fm.removeItem(at: item)
        }
        Logger.info("Cleared storage: \(relativePath)", category: Logger.storage)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Types

private enum ClearTier {
    case caches
    case cookies
    case allWebsiteData
    case fullReset

    var progressLabel: String {
        switch self {
        case .caches: "Clearing website caches…"
        case .cookies: "Clearing cookies and sessions…"
        case .allWebsiteData: "Clearing all website data…"
        case .fullReset: "Erasing all content and settings…"
        }
    }
}

private struct StorageItem: Identifiable {
    let id: String
    let name: String
    let detail: String
    let icon: String
    let size: Int64
    var isClearing = false
    let clearAction: (@Sendable () async -> Void)?
}
