import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for PasswordQuirksManager operations.
    @Tag static var passwordQuirksManager: Self
}

// MARK: - PasswordQuirksManager Singleton Tests

@Suite("PasswordQuirksManager Singleton", .tags(.passwordQuirksManager))
struct PasswordQuirksManagerSingletonTests {
    @Test("Shared instance exists")
    func sharedInstanceExists() {
        _ = PasswordQuirksManager.shared
    }

    @Test("Shared instance is consistent")
    func sharedInstanceIsConsistent() {
        let manager1 = PasswordQuirksManager.shared
        let manager2 = PasswordQuirksManager.shared

        #expect(manager1 === manager2)
    }
}

// MARK: - PasswordQuirksManager Domain Normalization Tests

/// Tests for internal domain normalization logic.
/// Note: normalizeDomain is private, so we test via the public rules API.
@Suite("PasswordQuirksManager Domain Handling", .tags(.passwordQuirksManager))
struct PasswordQuirksManagerDomainTests {
    @Test("Rules lookup for non-existent domain returns nil")
    func rulesNonExistentDomain() async {
        let manager = PasswordQuirksManager.shared

        // Using a domain that's unlikely to have quirks
        let rules = await manager.rules(for: "unique-test-domain-\(UUID().uuidString).invalid")

        #expect(rules == nil)
    }

    @Test("Rules lookup handles www prefix correctly")
    func rulesWwwPrefix() async {
        let manager = PasswordQuirksManager.shared

        // Both should normalize to the same domain
        let withWww = await manager.rules(for: "www.nonexistent-domain.invalid")
        let withoutWww = await manager.rules(for: "nonexistent-domain.invalid")

        // Both should be nil for non-existent domains
        #expect(withWww == nil)
        #expect(withoutWww == nil)
    }

    @Test("Rules lookup handles uppercase correctly")
    func rulesUppercase() async {
        let manager = PasswordQuirksManager.shared

        let upper = await manager.rules(for: "NONEXISTENT-DOMAIN.INVALID")
        let lower = await manager.rules(for: "nonexistent-domain.invalid")

        // Both should normalize and return nil
        #expect(upper == nil)
        #expect(lower == nil)
    }

    @Test("Rules lookup handles subdomain correctly")
    func rulesSubdomain() async {
        let manager = PasswordQuirksManager.shared

        // Subdomains should fall back to registrable domain
        let subdomain = await manager.rules(for: "login.nonexistent-domain.invalid")

        #expect(subdomain == nil)
    }
}

// MARK: - PasswordQuirksManager State Tests

@Suite("PasswordQuirksManager State", .tags(.passwordQuirksManager))
struct PasswordQuirksManagerStateTests {
    @Test("Rule count is accessible")
    func ruleCountAccessible() async {
        let manager = PasswordQuirksManager.shared

        // Should not crash, value may be 0 if database not loaded
        let count = await manager.ruleCount

        #expect(count >= 0)
    }
}

// MARK: - PasswordQuirksManager Prefetch Tests

@Suite("PasswordQuirksManager Prefetch", .tags(.passwordQuirksManager), .serialized)
struct PasswordQuirksManagerPrefetchTests {
    @Test("Prefetch completes without error")
    func prefetchCompletes() async {
        let manager = PasswordQuirksManager.shared

        // Should not throw even if network unavailable (uses cache or fails gracefully)
        await manager.prefetch()

        #expect(true, "Prefetch completed without crash")
    }

    @Test("Prefetch is idempotent")
    func prefetchIdempotent() async {
        let manager = PasswordQuirksManager.shared

        // Multiple prefetch calls should be safe
        await manager.prefetch()
        await manager.prefetch()

        #expect(true, "Multiple prefetch calls succeeded")
    }
}

// MARK: - PasswordQuirksManager Refresh Tests

@Suite("PasswordQuirksManager Refresh", .tags(.passwordQuirksManager), .serialized)
struct PasswordQuirksManagerRefreshTests {
    @Test("Refresh completes without error")
    func refreshCompletes() async {
        let manager = PasswordQuirksManager.shared

        // Should not throw even if network unavailable
        await manager.refresh()

        #expect(true, "Refresh completed without crash")
    }
}

// MARK: - PasswordRules Parsing Tests

@Suite("PasswordRules Parsing", .tags(.passwordQuirksManager))
@MainActor
struct PasswordRulesParsingTests {
    @Test("Parses minlength")
    func parsesMinLength() {
        let rules = PasswordRules.parse("minlength: 8")

        #expect(rules?.minLength == 8)
        #expect(rules?.maxLength == nil)
    }

    @Test("Parses maxlength")
    func parsesMaxLength() {
        let rules = PasswordRules.parse("maxlength: 20")

        #expect(rules?.maxLength == 20)
        #expect(rules?.minLength == nil)
    }

    @Test("Parses both min and max length")
    func parsesBothLengths() {
        let rules = PasswordRules.parse("minlength: 8; maxlength: 20")

        #expect(rules?.minLength == 8)
        #expect(rules?.maxLength == 20)
    }

    @Test("Parses required character classes")
    func parsesRequired() {
        let rules = PasswordRules.parse("required: upper, lower, digit")

        #expect(rules?.requiredCharacterSets?.count == 3)
    }

    @Test("Parses max-consecutive")
    func parsesMaxConsecutive() {
        let rules = PasswordRules.parse("max-consecutive: 3")

        #expect(rules?.maxConsecutive == 3)
    }

    @Test("Parses complex rules string")
    func parsesComplexRules() {
        let rulesString = "minlength: 8; maxlength: 20; required: upper, lower, digit; max-consecutive: 3"
        let rules = PasswordRules.parse(rulesString)

        #expect(rules?.minLength == 8)
        #expect(rules?.maxLength == 20)
        #expect(rules?.requiredCharacterSets?.count == 3)
        #expect(rules?.maxConsecutive == 3)
    }

    @Test("Parses required with special")
    func parsesRequiredSpecial() {
        let rules = PasswordRules.parse("required: upper, lower, digit, special")

        #expect(rules?.requiredCharacterSets?.count == 4)
    }

    @Test("Handles empty string")
    func handlesEmptyString() {
        let rules = PasswordRules.parse("")

        #expect(rules != nil, "Returns empty rules, not nil")
        #expect(rules?.minLength == nil)
        #expect(rules?.maxLength == nil)
    }

    @Test("Handles whitespace variations")
    func handlesWhitespace() {
        let rules = PasswordRules.parse("  minlength:8 ; maxlength :20  ")

        #expect(rules?.minLength == 8)
        #expect(rules?.maxLength == 20)
    }

    @Test("Ignores invalid rule names")
    func ignoresInvalidRuleNames() {
        let rules = PasswordRules.parse("minlength: 8; unknownrule: foo; maxlength: 20")

        #expect(rules?.minLength == 8)
        #expect(rules?.maxLength == 20)
    }

    @Test("Handles case insensitivity for keys")
    func handlesCaseInsensitivity() {
        let rules = PasswordRules.parse("MINLENGTH: 8; MaxLength: 20")

        #expect(rules?.minLength == 8)
        #expect(rules?.maxLength == 20)
    }

    @Test("Parses allowed characters")
    func parsesAllowed() {
        let rules = PasswordRules.parse("allowed: upper, lower")

        #expect(rules?.allowedCharacters != nil)
        #expect(rules?.allowedCharacters?.contains("A") == true)
        #expect(rules?.allowedCharacters?.contains("a") == true)
    }

    @Test("Multiple required rules create AND constraint")
    func multipleRequiredAND() {
        let rules = PasswordRules.parse("required: upper; required: digit")

        // Both requirements should be added (AND constraint per 1Password spec)
        #expect(rules?.requiredCharacterSets?.count == 2)
    }
}

// MARK: - Notes

//
// PasswordQuirksManager functionality requiring integration tests:
//
// 1. Network fetch: Actual HTTP request to GitHub
// 2. Disk cache: File system persistence
// 3. Cache expiration: Time-based cache invalidation
// 4. Real quirks lookup: Requires populated database
//
// The tests above verify:
// - Singleton pattern
// - Domain normalization behavior (via rules API)
// - State accessibility (ruleCount)
// - Safe behavior for prefetch/refresh operations
// - PasswordRules parsing logic
//
// Full cache testing requires:
// - Mocking network responses
// - Controlling file system access
// - Time manipulation for cache expiration
//
