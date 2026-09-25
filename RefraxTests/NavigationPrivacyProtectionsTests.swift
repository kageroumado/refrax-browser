import Foundation
import SwiftData
import Testing
import WebKit

@testable import Refrax

private typealias PrivacyProtections = Refrax.WebPage.NavigationPreferences.PrivacyProtections

@Suite("Navigation Privacy Protections", .serialized)
@MainActor
struct NavigationPrivacyProtectionsTests {
    // MARK: - WebKit Mapping

    @Test("Fingerprinting maps to EnhancedTelemetry, link filtering to SanitizeLookalikeCharacters")
    func mapsToIntegrityPolicyFlags() {
        #expect(PrivacyProtections.fingerprinting.integrityPolicy == .enhancedTelemetry)
        #expect(PrivacyProtections.linkDecorationFiltering.integrityPolicy == .sanitizeLookalikeCharacters)
        #expect(PrivacyProtections([.enhancedTelemetry, .sanitizeLookalikeCharacters, .httpsFirst]) == .all)
        #expect(PrivacyProtections([.enabled, .requestValidation]).isEmpty)
    }

    @Test("WKWebpagePreferences round-trips the protections")
    func roundTripsThroughWebKit() {
        #expect(WKWebpagePreferences.supportsIntegrityPolicy)

        var preferences = Refrax.WebPage.NavigationPreferences()
        preferences.privacyProtections = .all
        let webKitPreferences = preferences.makeWKWebpagePreferences()
        #expect(webKitPreferences.privacyProtections == .all)
        #expect(Refrax.WebPage.NavigationPreferences(webKitPreferences).privacyProtections == .all)
    }

    @Test("Writing protections keeps unrelated policy flags")
    func keepsUnrelatedFlags() {
        let webKitPreferences = WKWebpagePreferences()
        webKitPreferences._networkConnectionIntegrityPolicy = [.httpsFirst, .enhancedTelemetry]
        webKitPreferences.privacyProtections = .linkDecorationFiltering
        #expect(webKitPreferences._networkConnectionIntegrityPolicy == [.httpsFirst, .sanitizeLookalikeCharacters])
    }

    // MARK: - Settings

    private func makeSettings() throws -> (ModelContainer, BrowserSettings) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, BrowserSettings.fetchOrCreate(in: container.mainContext))
    }

    @Test("Both protections are on by default")
    func defaultsOn() throws {
        let (_, settings) = try makeSettings()
        let url = URL(string: "https://example.com/?utm_source=x")
        #expect(settings.navigationPrivacyProtections(for: url) == .all)
    }

    @Test("Each setting turns its protection off")
    func settingsGateProtections() throws {
        let (_, settings) = try makeSettings()
        let url = URL(string: "https://example.com/")

        settings.enableFingerprintingProtection = false
        #expect(settings.navigationPrivacyProtections(for: url) == .linkDecorationFiltering)

        settings.enableFingerprintingProtection = true
        settings.privacyProtection.removeTrackingParameters = false
        #expect(settings.navigationPrivacyProtections(for: url) == .fingerprinting)

        settings.privacyProtection.removeTrackingParameters = true
        settings.privacyProtection.enableLinkProtection = false
        #expect(settings.navigationPrivacyProtections(for: url) == .fingerprinting)
    }

    @Test("Link protection exceptions skip link decoration filtering")
    func exceptionsSkipLinkFiltering() throws {
        let (_, settings) = try makeSettings()
        settings.privacyProtection.linkProtectionExceptions = ["example.com"]

        #expect(settings.navigationPrivacyProtections(for: URL(string: "https://shop.example.com/")) == .fingerprinting)
        #expect(settings.navigationPrivacyProtections(for: URL(string: "https://other.org/")) == .all)
    }
}
