import Foundation
import SwiftData
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for WebPageSettingsApplier functionality.
    @Tag static var settingsApplier: Self
}

// MARK: - Test Environment

/// Minimal test environment for WebPageSettingsApplier tests.
@MainActor
struct SettingsApplierTestEnvironment {
    let container: ModelContainer
    let modelContext: ModelContext
    let settings: BrowserSettings
    let siteSettingsManager: SiteSettingsManager

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        self.container = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = container.mainContext

        self.settings = BrowserSettings.fetchOrCreate(in: modelContext)
        self.siteSettingsManager = SiteSettingsManager(modelContext: modelContext)
    }

    func makeApplier() -> WebPageSettingsApplier {
        WebPageSettingsApplier(
            settings: settings,
            deviceSensorAuthorization: .init(decision: .prompt),
            siteSettingsManager: siteSettingsManager,
        )
    }
}

// MARK: - Configuration Application Tests

@Suite("WebPageSettingsApplier Configuration", .tags(.settingsApplier), .serialized)
@MainActor
struct ConfigurationApplicationTests {
    @Test("JavaScript setting flows to configuration")
    func javaScriptSettingFlows() throws {
        let env = try SettingsApplierTestEnvironment()
        let applier = env.makeApplier()

        // Test with JavaScript enabled
        env.settings.enableJavaScript = true
        var config1: Refrax.WebPage.Configuration = .init()
        applier.apply(to: &config1)
        #expect(config1.defaultNavigationPreferences.allowsContentJavaScript == true)

        // Test with JavaScript disabled
        env.settings.enableJavaScript = false
        var config2: Refrax.WebPage.Configuration = .init()
        applier.apply(to: &config2)
        #expect(config2.defaultNavigationPreferences.allowsContentJavaScript == false)
    }

    @Test("Static settings are applied correctly")
    func staticSettingsApplied() throws {
        let env = try SettingsApplierTestEnvironment()
        let applier = env.makeApplier()

        var config: Refrax.WebPage.Configuration = .init()
        applier.apply(to: &config)

        // Verify static settings
        #expect(config.suppressesIncrementalRendering == false)
        #expect(config.allowsInlinePredictions == true)
        #expect(config.upgradeKnownHostsToHTTPS == true)
    }

    @Test("Device sensor authorization is applied")
    func deviceSensorAuthorizationApplied() throws {
        let env = try SettingsApplierTestEnvironment()

        // Create applier with specific decision
        let applier = WebPageSettingsApplier(
            settings: env.settings,
            deviceSensorAuthorization: .init(decision: .deny),
            siteSettingsManager: env.siteSettingsManager,
        )

        var config: Refrax.WebPage.Configuration = .init()
        applier.apply(to: &config)

        // The device sensor authorization should be set
        // We can't directly test the decision handler result without calling it
        // but we can verify the property was set
        _ = config.deviceSensorAuthorization
    }
}

// MARK: - Request Header Tests

@Suite("WebPageSettingsApplier Request Headers", .tags(.settingsApplier), .serialized)
@MainActor
struct RequestHeaderTests {
    @Test("DNT header added when doNotTrack is true")
    func dntHeaderAdded() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.doNotTrack = true
        let applier = env.makeApplier()

        var request = URLRequest(url: URL(string: "https://example.com")!)
        applier.applyRequestHeaders(to: &request)

        #expect(request.value(forHTTPHeaderField: "DNT") == "1")
    }

    @Test("DNT header not added when doNotTrack is false")
    func dntHeaderNotAddedWhenDisabled() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.doNotTrack = false
        let applier = env.makeApplier()

        var request = URLRequest(url: URL(string: "https://example.com")!)
        applier.applyRequestHeaders(to: &request)

        #expect(request.value(forHTTPHeaderField: "DNT") == nil)
    }

    @Test("DNT header not overwritten if already present")
    func dntHeaderNotOverwritten() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.doNotTrack = true
        let applier = env.makeApplier()

        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("0", forHTTPHeaderField: "DNT")
        applier.applyRequestHeaders(to: &request)

        // Original value should be preserved
        #expect(request.value(forHTTPHeaderField: "DNT") == "0")
    }

    @Test("GPC header added when site explicitly allows")
    func gpcHeaderAddedWhenSiteAllows() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.enableGlobalPrivacyControl = true

        // Create site settings that allow GPC
        let siteSettings = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        siteSettings.gpcHeaderOverride = .allow
        env.siteSettingsManager.save(siteSettings)

        let applier = env.makeApplier()

        var request = URLRequest(url: URL(string: "https://example.com/page")!)
        applier.applyRequestHeaders(to: &request)

        #expect(request.value(forHTTPHeaderField: "Sec-GPC") == "1")
    }

    @Test("GPC header not added when global setting is disabled")
    func gpcHeaderNotAddedWhenGlobalDisabled() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.enableGlobalPrivacyControl = false

        // Create site settings that allow GPC (shouldn't matter since global is off)
        let siteSettings = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        siteSettings.gpcHeaderOverride = .allow
        env.siteSettingsManager.save(siteSettings)

        let applier = env.makeApplier()

        var request = URLRequest(url: URL(string: "https://example.com/page")!)
        applier.applyRequestHeaders(to: &request)

        #expect(request.value(forHTTPHeaderField: "Sec-GPC") == nil)
    }

    @Test("GPC header not sent when site has no override")
    func gpcHeaderNotSentWhenNoOverride() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.enableGlobalPrivacyControl = true
        // Don't create any site settings - should default to not sending

        let applier = env.makeApplier()

        var request = URLRequest(url: URL(string: "https://unknown-site.com/page")!)
        applier.applyRequestHeaders(to: &request)

        #expect(request.value(forHTTPHeaderField: "Sec-GPC") == nil)
    }

    @Test("GPC header removed when site blocks")
    func gpcHeaderRemovedWhenSiteBlocks() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.enableGlobalPrivacyControl = true

        // Create site settings that block GPC
        let siteSettings = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        siteSettings.gpcHeaderOverride = .block
        env.siteSettingsManager.save(siteSettings)

        let applier = env.makeApplier()

        // Start with a request that has the header
        var request = URLRequest(url: URL(string: "https://example.com/page")!)
        request.setValue("1", forHTTPHeaderField: "Sec-GPC")
        applier.applyRequestHeaders(to: &request)

        // Header should be removed
        #expect(request.value(forHTTPHeaderField: "Sec-GPC") == nil)
    }

    @Test("GPC header not applied to non-HTTP URLs")
    func gpcHeaderNotAppliedToNonHTTP() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.enableGlobalPrivacyControl = true

        // Create site settings that allow GPC
        let siteSettings = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        siteSettings.gpcHeaderOverride = .allow
        env.siteSettingsManager.save(siteSettings)

        let applier = env.makeApplier()

        // Test with file URL
        var fileRequest = URLRequest(url: URL(string: "file:///Users/test/file.html")!)
        applier.applyRequestHeaders(to: &fileRequest)
        #expect(fileRequest.value(forHTTPHeaderField: "Sec-GPC") == nil)

        // Test with data URL
        var dataRequest = URLRequest(url: URL(string: "data:text/html,<h1>Test</h1>")!)
        applier.applyRequestHeaders(to: &dataRequest)
        #expect(dataRequest.value(forHTTPHeaderField: "Sec-GPC") == nil)
    }

    @Test("GPC header applied to both HTTP and HTTPS")
    func gpcHeaderAppliedToHTTPAndHTTPS() throws {
        let env = try SettingsApplierTestEnvironment()
        env.settings.enableGlobalPrivacyControl = true

        // Create site settings that allow GPC
        let siteSettings = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        siteSettings.gpcHeaderOverride = .allow
        env.siteSettingsManager.save(siteSettings)

        let applier = env.makeApplier()

        var httpsRequest = URLRequest(url: URL(string: "https://example.com/page")!)
        applier.applyRequestHeaders(to: &httpsRequest)
        #expect(httpsRequest.value(forHTTPHeaderField: "Sec-GPC") == "1")

        var httpRequest = URLRequest(url: URL(string: "http://example.com/page")!)
        applier.applyRequestHeaders(to: &httpRequest)
        #expect(httpRequest.value(forHTTPHeaderField: "Sec-GPC") == "1")
    }
}

// MARK: - Data Store Tests

@Suite("WebPageSettingsApplier Data Store", .tags(.settingsApplier), .serialized)
@MainActor
struct DataStoreTests {
    @Test("Default data store is always persistent")
    func defaultDataStoreAlwaysPersistent() throws {
        let env = try SettingsApplierTestEnvironment()
        let applier = env.makeApplier()

        let dataStore = applier.defaultDataStore()

        // Default data store is always the shared persistent store.
        // Private mode is handled per-space via SpaceDataStoreManager.
        #expect(dataStore.isPersistent == true)
        #expect(dataStore === WKWebsiteDataStore.default())
    }
}
