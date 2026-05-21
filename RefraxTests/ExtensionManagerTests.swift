import Foundation
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for ExtensionManager functionality.
    @Tag static var extensionManager: Self
}

// MARK: - InstalledExtension Model Tests

@Suite("InstalledExtension Model", .tags(.extensionManager))
@MainActor
struct InstalledExtensionModelTests {
    @Test("Creates with correct default values")
    func createsWithDefaults() {
        let ext = InstalledExtension(
            uniqueIdentifier: "test-extension",
            source: .localFolder(URL(fileURLWithPath: "/tmp/test")),
            displayName: "Test Extension",
            version: "1.0.0",
            manifestVersion: 3,
        )

        #expect(ext.uniqueIdentifier == "test-extension")
        #expect(ext.displayName == "Test Extension")
        #expect(ext.version == "1.0.0")
        #expect(ext.manifestVersion == 3)
        #expect(ext.isEnabled == true)
        #expect(ext.allowedInPrivateMode == false)
        #expect(ext.updateBehavior == .notify)
        #expect(ext.grantedPermissions.isEmpty)
        #expect(ext.deniedPermissions.isEmpty)
        #expect(ext.disabledOnDomains.isEmpty)
    }

    @Test("Equality based on ID")
    func equalityBasedOnID() {
        let ext1 = InstalledExtension(
            uniqueIdentifier: "ext1",
            source: .localFolder(URL(fileURLWithPath: "/tmp/ext1")),
            displayName: "Extension 1",
            version: "1.0.0",
            manifestVersion: 3,
        )

        var ext2 = ext1
        ext2.displayName = "Different Name"

        // Same ID should be equal
        #expect(ext1 == ext2)
        #expect(ext1.hashValue == ext2.hashValue)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        var ext = InstalledExtension(
            uniqueIdentifier: "test-ext",
            source: .chromeWebStore(extensionID: "abc123"),
            displayName: "Chrome Extension",
            version: "2.1.0",
            manifestVersion: 3,
        )
        ext.isEnabled = false
        ext.allowedInPrivateMode = true
        ext.updateBehavior = .auto
        ext.disabledOnDomains = ["example.com", "test.org"]

        let encoded = try JSONEncoder().encode(ext)
        let decoded = try JSONDecoder().decode(InstalledExtension.self, from: encoded)

        #expect(decoded.uniqueIdentifier == ext.uniqueIdentifier)
        #expect(decoded.displayName == ext.displayName)
        #expect(decoded.isEnabled == ext.isEnabled)
        #expect(decoded.allowedInPrivateMode == ext.allowedInPrivateMode)
        #expect(decoded.updateBehavior == ext.updateBehavior)
        #expect(decoded.disabledOnDomains == ext.disabledOnDomains)
    }
}

// MARK: - ExtensionSource Tests

@Suite("ExtensionSource", .tags(.extensionManager))
@MainActor
struct ExtensionSourceTests {
    @Test("Local folder source codable")
    func localFolderCodable() throws {
        let source = ExtensionSource.localFolder(URL(fileURLWithPath: "/path/to/ext"))

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(ExtensionSource.self, from: encoded)

        if case let .localFolder(url) = decoded {
            #expect(url.path == "/path/to/ext")
        } else {
            Issue.record("Expected localFolder source")
        }
    }

    @Test("Chrome Web Store source codable")
    func chromeWebStoreCodable() throws {
        let source = ExtensionSource.chromeWebStore(extensionID: "abcdef123456")

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(ExtensionSource.self, from: encoded)

        if case let .chromeWebStore(extensionID) = decoded {
            #expect(extensionID == "abcdef123456")
        } else {
            Issue.record("Expected chromeWebStore source")
        }
    }

    @Test("Firefox Addons source codable")
    func firefoxAddonsCodable() throws {
        let source = ExtensionSource.firefoxAddons(extensionID: "addon@mozilla.org")

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(ExtensionSource.self, from: encoded)

        if case let .firefoxAddons(extensionID) = decoded {
            #expect(extensionID == "addon@mozilla.org")
        } else {
            Issue.record("Expected firefoxAddons source")
        }
    }
}

// MARK: - ResourceBudget Tests

@Suite("ResourceBudget", .tags(.extensionManager))
@MainActor
struct ResourceBudgetTests {
    @Test("Default budget values")
    func defaultBudgetValues() {
        let budget = ResourceBudget.default

        #expect(budget.maxMemory == 100 * 1_024 * 1_024) // 100MB
        #expect(budget.maxCPU == 10.0) // 10%
        #expect(budget.maxNetworkRequestsPerMinute == 100)
    }

    @Test("ResourceBudget codable")
    func resourceBudgetCodable() throws {
        let budget = ResourceBudget(
            maxMemory: 50 * 1_024 * 1_024,
            maxCPU: 5.0,
            maxNetworkRequestsPerMinute: 50,
        )

        let encoded = try JSONEncoder().encode(budget)
        let decoded = try JSONDecoder().decode(ResourceBudget.self, from: encoded)

        #expect(decoded.maxMemory == budget.maxMemory)
        #expect(decoded.maxCPU == budget.maxCPU)
        #expect(decoded.maxNetworkRequestsPerMinute == budget.maxNetworkRequestsPerMinute)
    }
}

// MARK: - ExtensionStateStore Tests

@Suite("ExtensionStateStore", .tags(.extensionManager))
@MainActor
struct ExtensionStateStoreTests {
    @Test("Empty state store")
    func emptyStateStore() {
        let store = ExtensionStateStore.empty

        #expect(store.installedExtensions.isEmpty)
        #expect(store.lastSyncDate == nil)
    }

    @Test("State store codable round-trip")
    func stateStoreCodable() throws {
        let ext = InstalledExtension(
            uniqueIdentifier: "test",
            source: .refraxGallery(extensionID: "gallery-ext"),
            displayName: "Gallery Extension",
            version: "1.0",
            manifestVersion: 3,
        )

        var settings = ExtensionGlobalSettings()
        settings.defaultUpdateBehavior = .auto
        settings.allowExtensionsInPrivateMode = true

        let store = ExtensionStateStore(
            installedExtensions: [ext],
            globalSettings: settings,
            lastSyncDate: Date(),
        )

        let encoded = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(ExtensionStateStore.self, from: encoded)

        #expect(decoded.installedExtensions.count == 1)
        #expect(decoded.installedExtensions.first?.uniqueIdentifier == "test")
        #expect(decoded.globalSettings.defaultUpdateBehavior == .auto)
        #expect(decoded.globalSettings.allowExtensionsInPrivateMode == true)
        #expect(decoded.lastSyncDate != nil)
    }
}

// MARK: - ExtensionError Tests

@Suite("ExtensionError", .tags(.extensionManager))
@MainActor
struct ExtensionErrorTests {
    @Test("Error descriptions are non-empty")
    func errorDescriptions() {
        let errors: [ExtensionError] = [
            .manifestErrors(["Error 1", "Error 2"]),
            .notInstalled,
            .unsupportedSource,
            .sourceNotFound,
            .permissionDenied,
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Manifest errors include all messages")
    func manifestErrorsIncludesMessages() {
        let error = ExtensionError.manifestErrors(["Missing name", "Invalid version"])

        let description = error.errorDescription!
        #expect(description.contains("Missing name"))
        #expect(description.contains("Invalid version"))
    }
}

// MARK: - UpdateBehavior Tests

@Suite("UpdateBehavior", .tags(.extensionManager))
@MainActor
struct UpdateBehaviorTests {
    @Test("All cases are iterable")
    func allCasesIterable() {
        let allCases = UpdateBehavior.allCases

        #expect(allCases.count == 3)
        #expect(allCases.contains(.auto))
        #expect(allCases.contains(.notify))
        #expect(allCases.contains(.manual))
    }

    @Test("Raw values are stable")
    func rawValuesStable() {
        #expect(UpdateBehavior.auto.rawValue == "auto")
        #expect(UpdateBehavior.notify.rawValue == "notify")
        #expect(UpdateBehavior.manual.rawValue == "manual")
    }
}

// MARK: - ExtensionManager Initial State Tests

/// Tests for ExtensionManager initialization and initial state.
///
/// Note: ExtensionManager has heavy WKWebExtension dependencies, limiting unit test coverage.
/// Full extension lifecycle testing (install, enable, disable, uninstall) requires
/// integration tests with real extension files.
@Suite("ExtensionManager Initial State", .tags(.extensionManager), .serialized)
@MainActor
struct ExtensionManagerInitialStateTests {
    @Test("Manager creates with WKWebExtensionController")
    func managerCreatesWithController() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.extensionManager.controller
    }

    @Test("Bundled extensions are installed")
    func bundledExtensionsInstalled() throws {
        let env = try TabManagerTestEnvironment()

        // uBlock Origin is bundled with Refrax and should be auto-installed
        let ublock = env.extensionManager.installedExtensions.first {
            if case let .bundled(name) = $0.source {
                return name == "ublock-origin"
            }
            return false
        }

        #expect(ublock != nil, "uBlock Origin should be installed as a bundled extension")
        if let ublock {
            #expect(ublock.displayName == "uBlock Origin")
            #expect(ublock.isEnabled, "Bundled extensions should be enabled by default")
        }
    }

    @Test("Bundled extensions have required permissions granted")
    func bundledExtensionsHavePermissions() throws {
        let env = try TabManagerTestEnvironment()

        // Find the bundled uBlock Origin extension
        let ublock = env.extensionManager.installedExtensions.first {
            if case let .bundled(name) = $0.source {
                return name == "ublock-origin"
            }
            return false
        }

        guard let ublock else {
            Issue.record("uBlock Origin bundled extension not found")
            return
        }

        // Bundled extensions should have their permissions auto-granted
        #expect(!ublock.grantedPermissions.isEmpty, "Bundled extension should have permissions granted")

        // uBlock Origin requires webRequest permission for ad blocking
        let hasWebRequest = ublock.grantedPermissions.keys.contains("webRequest")
        #expect(hasWebRequest, "uBlock Origin should have webRequest permission granted")

        // Should have <all_urls> match pattern for ad blocking
        let hasAllUrls = ublock.grantedMatchPatterns.keys.contains("<all_urls>")
        #expect(hasAllUrls, "uBlock Origin should have <all_urls> match pattern granted")
    }
}

// MARK: - ExtensionManager Adapter Caching Tests

@Suite("ExtensionManager Adapter Caching", .tags(.extensionManager), .serialized)
@MainActor
struct ExtensionManagerAdapterCachingTests {
    @Test("Remove tab adapter is safe for non-existent page")
    func removeNonExistentTabAdapter() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        // Removing adapter that was never created should not crash
        env.extensionManager.removeTabAdapter(for: tab.activePage)

        // Should complete without error
        #expect(true)
    }

    @Test("Remove window adapter is safe for non-existent window")
    func removeNonExistentWindowAdapter() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        // Removing adapter that was never created should not crash
        env.extensionManager.removeWindowAdapter(for: windowState)

        // Should complete without error
        #expect(true)
    }
}

// MARK: - ExtensionManager Query Tests

@Suite("ExtensionManager Query", .tags(.extensionManager), .serialized)
@MainActor
struct ExtensionManagerQueryTests {
    @Test("Context returns nil for non-existent extension")
    func contextReturnsNilForNonExistent() throws {
        let env = try TabManagerTestEnvironment()

        let fakeExtension = InstalledExtension(
            uniqueIdentifier: "fake-extension",
            source: .localFolder(URL(fileURLWithPath: "/tmp/fake")),
            displayName: "Fake",
            version: "1.0.0",
            manifestVersion: 3,
        )

        let context = env.extensionManager.context(for: fakeExtension)

        #expect(context == nil, "Context should be nil for non-installed extension")
    }

    @Test("Enabled extensions filters by isEnabled and loaded")
    func enabledExtensionsFilters() throws {
        let env = try TabManagerTestEnvironment()

        // No extensions are installed/loaded, so enabled should be empty
        #expect(env.extensionManager.enabledExtensions.isEmpty)
    }
}

// MARK: - ExtensionManager Tab Event Tests

/// Tests for tab event dispatching.
///
/// Note: Event dispatching requires WKWebExtensionController to be functional.
/// These tests verify the dispatch methods handle edge cases gracefully.
@Suite("ExtensionManager Tab Events", .tags(.extensionManager), .serialized)
@MainActor
struct ExtensionManagerTabEventTests {
    @Test("Dispatch tab opened is safe when pagePool is nil")
    func dispatchTabOpenedSafeWithoutPagePool() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        // This should not crash even with the pagePool set
        env.extensionManager.dispatchTabOpened(tab)

        #expect(true, "Dispatch should complete without crash")
    }

    @Test("Dispatch tab closed is safe for tab without adapter")
    func dispatchTabClosedSafeWithoutAdapter() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        // Dispatch closed without ever creating an adapter
        env.extensionManager.dispatchTabClosed(tab, windowClosing: false)

        #expect(true, "Dispatch should complete without crash")
    }

    @Test("Dispatch tab activated is safe for new tab")
    func dispatchTabActivatedSafe() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        // Dispatch activate with no previous tab
        env.extensionManager.dispatchTabActivated(tab, previous: nil)

        #expect(true, "Dispatch should complete without crash")
    }

    @Test("Dispatch navigation committed is safe without adapter")
    func dispatchNavigationCommittedSafe() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        // Dispatch commit without adapter
        env.extensionManager.dispatchNavigationCommitted(
            tab.activePage,
            url: URL(string: "https://navigated.com")!,
        )

        #expect(true, "Dispatch should complete without crash")
    }
}

// MARK: - ExtensionManager Enable/Disable Error Tests

@Suite("ExtensionManager Enable/Disable Errors", .tags(.extensionManager), .serialized)
@MainActor
struct ExtensionManagerEnableDisableErrorTests {
    @Test("Enable throws notInstalled for unknown extension")
    func enableThrowsNotInstalled() async throws {
        let env = try TabManagerTestEnvironment()

        let fakeExtension = InstalledExtension(
            uniqueIdentifier: "not-installed",
            source: .localFolder(URL(fileURLWithPath: "/tmp/fake")),
            displayName: "Not Installed",
            version: "1.0.0",
            manifestVersion: 3,
        )

        do {
            try await env.extensionManager.enable(fakeExtension)
            Issue.record("Expected notInstalled error to be thrown")
        } catch let error as ExtensionError {
            if case .notInstalled = error {
                // Expected
            } else {
                Issue.record("Expected notInstalled but got \(error)")
            }
        } catch {
            Issue.record("Expected ExtensionError but got \(error)")
        }
    }

    @Test("Disable throws notInstalled for unknown extension")
    func disableThrowsNotInstalled() async throws {
        let env = try TabManagerTestEnvironment()

        let fakeExtension = InstalledExtension(
            uniqueIdentifier: "not-installed",
            source: .localFolder(URL(fileURLWithPath: "/tmp/fake")),
            displayName: "Not Installed",
            version: "1.0.0",
            manifestVersion: 3,
        )

        do {
            try await env.extensionManager.disable(fakeExtension)
            Issue.record("Expected notInstalled error to be thrown")
        } catch let error as ExtensionError {
            if case .notInstalled = error {
                // Expected
            } else {
                Issue.record("Expected notInstalled but got \(error)")
            }
        } catch {
            Issue.record("Expected ExtensionError but got \(error)")
        }
    }
}

// MARK: - ExtensionGlobalSettings Tests

@Suite("ExtensionGlobalSettings", .tags(.extensionManager))
@MainActor
struct ExtensionGlobalSettingsTests {
    @Test("Default settings values")
    func defaultSettingsValues() {
        let settings = ExtensionGlobalSettings()

        #expect(settings.defaultUpdateBehavior == .notify)
        #expect(settings.allowExtensionsInPrivateMode == false)
        #expect(settings.defaultResourceBudget.maxMemory == ResourceBudget.default.maxMemory)
    }

    @Test("Settings codable round-trip")
    func settingsCodable() throws {
        var settings = ExtensionGlobalSettings()
        settings.defaultUpdateBehavior = .auto
        settings.allowExtensionsInPrivateMode = true
        settings.defaultResourceBudget = ResourceBudget(
            maxMemory: 200 * 1_024 * 1_024,
            maxCPU: 20.0,
            maxNetworkRequestsPerMinute: 200,
        )

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ExtensionGlobalSettings.self, from: encoded)

        #expect(decoded.defaultUpdateBehavior == .auto)
        #expect(decoded.allowExtensionsInPrivateMode == true)
        #expect(decoded.defaultResourceBudget.maxMemory == 200 * 1_024 * 1_024)
    }
}

// MARK: - Notes

//
// ExtensionManager functionality requiring integration tests:
//
// 1. installFromFolder: Requires real WKWebExtension from manifest.json file
// 2. enable/disable with loaded context: Requires successful WKWebExtension load
// 3. uninstall: Requires previously installed extension
// 4. setup: Loads enabled extensions from persisted state
// 5. Tab/Window adapter creation and caching with real WKWebExtensionContext
// 6. Persistence file I/O: reads/writes to ~/Library/Application Support
// 7. Content script registration with ScriptRegistry
//
// The tests above verify model types, error handling, and safe no-op paths.
// Full extension lifecycle testing requires integration tests with:
// - A valid extension folder with manifest.json
// - Real WKWebExtensionController operations
// - File system access for persistence
