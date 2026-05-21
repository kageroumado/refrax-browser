import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for SiteSettingsManager operations.
    @Tag static var siteSettingsManager: Self
}

// MARK: - SiteSettingsManager Lookup Tests

@Suite("SiteSettingsManager Lookup", .tags(.siteSettingsManager), .serialized)
@MainActor
struct SiteSettingsLookupTests {
    @Test("Settings returns nil for unknown domain")
    func settingsReturnsNilForUnknown() throws {
        let env = try TabManagerTestEnvironment()

        let settings = env.siteSettingsManager.settings(for: "unknown.com")

        #expect(settings == nil)
    }

    @Test("Settings returns existing settings")
    func settingsReturnsExisting() throws {
        let env = try TabManagerTestEnvironment()

        // Create settings first
        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")

        // Lookup should return them
        let settings = env.siteSettingsManager.settings(for: "example.com")

        #expect(settings != nil)
        #expect(settings?.domain == "example.com")
    }

    @Test("Settings lookup is case insensitive")
    func settingsLookupCaseInsensitive() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "EXAMPLE.COM")

        let settings = env.siteSettingsManager.settings(for: "example.com")

        #expect(settings != nil)
    }

    @Test("Settings for URL extracts domain")
    func settingsForURLExtractsDomain() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")

        let url = URL(string: "https://example.com/path/to/page")!
        let settings = env.siteSettingsManager.settings(for: url)

        #expect(settings != nil)
        #expect(settings?.domain == "example.com")
    }

    @Test("Settings inherits from parent domain")
    func settingsInheritsFromParent() throws {
        let env = try TabManagerTestEnvironment()

        // Create settings for parent domain
        let parentSettings = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        parentSettings.pageZoom = 150

        // Lookup subdomain should return parent's settings
        let subdomainSettings = env.siteSettingsManager.settings(for: "app.example.com")

        #expect(subdomainSettings != nil)
        #expect(subdomainSettings?.pageZoom == 150)
        #expect(subdomainSettings === parentSettings, "Should return same instance")
    }

    @Test("Settings uses negative cache for missing domains")
    func settingsUsesNegativeCache() throws {
        let env = try TabManagerTestEnvironment()

        // First lookup - misses and adds to negative cache
        _ = env.siteSettingsManager.settings(for: "missing.com")

        // Second lookup should use negative cache (we can't directly verify but it shouldn't crash)
        let settings = env.siteSettingsManager.settings(for: "missing.com")

        #expect(settings == nil)
    }
}

// MARK: - SiteSettingsManager Create Tests

@Suite("SiteSettingsManager Create", .tags(.siteSettingsManager), .serialized)
@MainActor
struct SiteSettingsCreateTests {
    @Test("Settings or create creates new settings")
    func settingsOrCreateCreatesNew() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.siteSettingsManager.isEmpty)

        let settings = env.siteSettingsManager.settingsOrCreate(for: "new.com")

        #expect(settings.domain == "new.com")
        #expect(env.siteSettingsManager.siteCount == 1)
    }

    @Test("Settings or create returns existing")
    func settingsOrCreateReturnsExisting() throws {
        let env = try TabManagerTestEnvironment()

        let original = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        original.pageZoom = 125

        let retrieved = env.siteSettingsManager.settingsOrCreate(for: "example.com")

        #expect(retrieved === original)
        #expect(retrieved.pageZoom == 125)
        #expect(env.siteSettingsManager.siteCount == 1, "Should not create duplicate")
    }

    @Test("Settings or create clears negative cache")
    func settingsOrCreateClearsNegativeCache() throws {
        let env = try TabManagerTestEnvironment()

        // First lookup adds to negative cache
        #expect(env.siteSettingsManager.settings(for: "new.com") == nil)

        // Create should clear negative cache
        _ = env.siteSettingsManager.settingsOrCreate(for: "new.com")

        // Lookup should now find it
        let lookup = env.siteSettingsManager.settings(for: "new.com")
        #expect(lookup != nil)
    }

    @Test("Settings or create for URL")
    func settingsOrCreateForURL() throws {
        let env = try TabManagerTestEnvironment()

        let url = URL(string: "https://example.com/page")!
        let settings = env.siteSettingsManager.settingsOrCreate(for: url)

        #expect(settings?.domain == "example.com")
    }

    @Test("Settings or create for URL returns nil for invalid URL")
    func settingsOrCreateForInvalidURL() throws {
        let env = try TabManagerTestEnvironment()

        let url = URL(string: "about:blank")!
        let settings = env.siteSettingsManager.settingsOrCreate(for: url)

        #expect(settings == nil)
    }
}

// MARK: - SiteSettingsManager Cache Tests

@Suite("SiteSettingsManager Cache", .tags(.siteSettingsManager), .serialized)
@MainActor
struct SiteSettingsCacheTests {
    @Test("Settings are cached after first lookup")
    func settingsAreCached() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")

        // First lookup populates cache
        let first = env.siteSettingsManager.settings(for: "example.com")

        // Second lookup should return same instance from cache
        let second = env.siteSettingsManager.settings(for: "example.com")

        #expect(first === second)
    }

    @Test("Clear cache removes all entries")
    func clearCacheRemovesAll() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        _ = env.siteSettingsManager.settings(for: "example.com") // Populate cache

        env.siteSettingsManager.clearCache()

        // After clear, should still be able to find (from database)
        let settings = env.siteSettingsManager.settings(for: "example.com")
        #expect(settings != nil)
    }

    @Test("Clear cache clears negative cache")
    func clearCacheClearsNegative() throws {
        let env = try TabManagerTestEnvironment()

        // Add to negative cache
        _ = env.siteSettingsManager.settings(for: "missing.com")

        env.siteSettingsManager.clearCache()

        // Now create - should work since negative cache is cleared
        let settings = env.siteSettingsManager.settingsOrCreate(for: "missing.com")
        #expect(settings.domain == "missing.com")
    }
}

// MARK: - SiteSettingsManager Delete Tests

@Suite("SiteSettingsManager Delete", .tags(.siteSettingsManager), .serialized)
@MainActor
struct SiteSettingsDeleteTests {
    @Test("Delete removes settings from database")
    func deleteRemovesFromDatabase() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        #expect(env.siteSettingsManager.siteCount == 1)

        env.siteSettingsManager.delete(for: "example.com")

        #expect(env.siteSettingsManager.isEmpty)
    }

    @Test("Delete invalidates cache")
    func deleteInvalidatesCache() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        _ = env.siteSettingsManager.settings(for: "example.com") // Populate cache

        env.siteSettingsManager.delete(for: "example.com")

        // Lookup should return nil after delete
        let settings = env.siteSettingsManager.settings(for: "example.com")
        #expect(settings == nil)
    }

    @Test("Delete invalidates subdomain cache entries")
    func deleteInvalidatesSubdomainCache() throws {
        let env = try TabManagerTestEnvironment()

        // Create parent settings
        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")

        // Lookup subdomain (caches with reference to parent)
        let subdomain = env.siteSettingsManager.settings(for: "app.example.com")
        #expect(subdomain != nil)

        // Delete parent
        env.siteSettingsManager.delete(for: "example.com")

        // Subdomain lookup should now return nil
        let afterDelete = env.siteSettingsManager.settings(for: "app.example.com")
        #expect(afterDelete == nil)
    }

    @Test("Delete adds to negative cache")
    func deleteAddsToNegativeCache() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        env.siteSettingsManager.delete(for: "example.com")

        // Lookup should return nil (from negative cache)
        let settings = env.siteSettingsManager.settings(for: "example.com")
        #expect(settings == nil)
    }

    @Test("Delete is no-op for non-existent domain")
    func deleteNoOpForNonExistent() throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash
        env.siteSettingsManager.delete(for: "nonexistent.com")

        #expect(env.siteSettingsManager.isEmpty)
    }
}

// MARK: - SiteSettingsManager Query Tests

@Suite("SiteSettingsManager Query", .tags(.siteSettingsManager), .serialized)
@MainActor
struct SiteSettingsQueryTests {
    @Test("All domains returns sorted list")
    func allDomainsSorted() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "zebra.com")
        _ = env.siteSettingsManager.settingsOrCreate(for: "apple.com")
        _ = env.siteSettingsManager.settingsOrCreate(for: "mango.com")

        let domains = env.siteSettingsManager.allDomains

        #expect(domains.count == 3)
        #expect(domains == ["apple.com", "mango.com", "zebra.com"])
    }

    @Test("Count returns correct number")
    func countReturnsCorrect() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.siteSettingsManager.isEmpty)

        _ = env.siteSettingsManager.settingsOrCreate(for: "one.com")
        #expect(env.siteSettingsManager.siteCount == 1)

        _ = env.siteSettingsManager.settingsOrCreate(for: "two.com")
        #expect(env.siteSettingsManager.siteCount == 2)
    }

    @Test("Fetch all site settings")
    func fetchAllSiteSettings() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "one.com")
        _ = env.siteSettingsManager.settingsOrCreate(for: "two.com")

        let all = env.siteSettingsManager.fetchAllSiteSettings()

        #expect(all.count == 2)
    }

    @Test("Fetch sites with JavaScript enabled")
    func fetchSitesWithJavaScriptEnabled() throws {
        let env = try TabManagerTestEnvironment()

        let enabled = env.siteSettingsManager.settingsOrCreate(for: "enabled.com")
        enabled.allowJavaScript = true

        let disabled = env.siteSettingsManager.settingsOrCreate(for: "disabled.com")
        disabled.allowJavaScript = false

        let results = env.siteSettingsManager.fetchSitesWithJavaScriptEnabled()

        #expect(results.count == 1)
        #expect(results.first?.domain == "enabled.com")
    }

    @Test("Fetch sites with JavaScript disabled")
    func fetchSitesWithJavaScriptDisabled() throws {
        let env = try TabManagerTestEnvironment()

        let enabled = env.siteSettingsManager.settingsOrCreate(for: "enabled.com")
        enabled.allowJavaScript = true

        let disabled = env.siteSettingsManager.settingsOrCreate(for: "disabled.com")
        disabled.allowJavaScript = false

        let results = env.siteSettingsManager.fetchSitesWithJavaScriptDisabled()

        #expect(results.count == 1)
        #expect(results.first?.domain == "disabled.com")
    }

    @Test("Fetch sites with GPC header overrides")
    func fetchSitesWithGPCOverrides() throws {
        let env = try TabManagerTestEnvironment()

        let overridden = env.siteSettingsManager.settingsOrCreate(for: "overridden.com")
        overridden.gpcHeaderOverride = .allow

        let defaultSettings = env.siteSettingsManager.settingsOrCreate(for: "default.com")
        // Default is .useAllowlist
        #expect(defaultSettings.gpcHeaderOverride == .useAllowlist)

        let results = env.siteSettingsManager.fetchSitesWithGPCHeaderOverrides()

        #expect(results.count == 1)
        #expect(results.first?.domain == "overridden.com")
    }
}

// MARK: - SiteSettingsManager Save Tests

@Suite("SiteSettingsManager Save", .tags(.siteSettingsManager), .serialized)
@MainActor
struct SiteSettingsSaveTests {
    @Test("Save persists settings changes")
    func savePersistsChanges() throws {
        let env = try TabManagerTestEnvironment()

        let settings = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        settings.pageZoom = 200
        env.siteSettingsManager.save(settings)

        // Verify settings can be retrieved with the new value
        let retrieved = env.siteSettingsManager.settings(for: "example.com")
        #expect(retrieved?.pageZoom == 200)
    }
}

// MARK: - SiteSettingsManager Edge Cases

@Suite("SiteSettingsManager Edge Cases", .tags(.siteSettingsManager), .serialized)
@MainActor
struct SiteSettingsEdgeCaseTests {
    @Test("Multiple lookups return same cached instance")
    func multipleLookupsSameInstance() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.siteSettingsManager.settingsOrCreate(for: "example.com")

        let lookup1 = env.siteSettingsManager.settings(for: "example.com")
        let lookup2 = env.siteSettingsManager.settings(for: "example.com")
        let lookup3 = env.siteSettingsManager.settings(for: "example.com")

        #expect(lookup1 === lookup2)
        #expect(lookup2 === lookup3)
    }

    @Test("Subdomain and parent share same settings instance")
    func subdomainSharesParentInstance() throws {
        let env = try TabManagerTestEnvironment()

        let parent = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        let subdomain = env.siteSettingsManager.settings(for: "www.example.com")

        #expect(subdomain === parent)
    }

    @Test("Subdomain inherits from immediate parent")
    func subdomainInheritsFromParent() throws {
        let env = try TabManagerTestEnvironment()

        // Note: parentDomain only looks one level up and requires the parent
        // to be a registrable domain (eTLD+1). So sub.example.com → example.com works,
        // but a.b.c.example.com → example.com does not (would need b.c.example.com first).
        let parent = env.siteSettingsManager.settingsOrCreate(for: "example.com")
        parent.pageZoom = 175

        let sub = env.siteSettingsManager.settings(for: "sub.example.com")

        #expect(sub?.pageZoom == 175)
    }

    @Test("Settings for file URL returns nil")
    func settingsForFileURL() throws {
        let env = try TabManagerTestEnvironment()

        let fileURL = URL(fileURLWithPath: "/tmp/test.html")
        let settings = env.siteSettingsManager.settings(for: fileURL)

        #expect(settings == nil)
    }
}
