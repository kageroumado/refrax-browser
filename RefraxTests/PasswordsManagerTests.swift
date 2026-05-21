import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for PasswordsManager operations.
    @Tag static var passwordsManager: Self
}

// MARK: - StoredCredential Tests

@Suite("StoredCredential", .tags(.passwordsManager))
@MainActor
struct StoredCredentialTests {
    @Test("Creates with required fields")
    func createsWithRequiredFields() {
        let credential = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "secret123",
        )

        #expect(credential.domain == "example.com")
        #expect(credential.username == "user@test.com")
        #expect(credential.password == "secret123")
        #expect(credential.dateCreated == nil)
        #expect(credential.dateModified == nil)
    }

    @Test("Creates with all fields")
    func createsWithAllFields() {
        let created = Date()
        let modified = Date().addingTimeInterval(3_600)

        let credential = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "secret123",
            dateCreated: created,
            dateModified: modified,
        )

        #expect(credential.dateCreated == created)
        #expect(credential.dateModified == modified)
    }

    @Test("Has unique ID")
    func hasUniqueID() {
        let cred1 = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        let cred2 = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        #expect(cred1.id != cred2.id)
    }

    @Test("Is Sendable")
    func isSendable() {
        let credential = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        let _: any Sendable = credential
        #expect(true)
    }
}

// MARK: - CredentialConflict Tests

@Suite("CredentialConflict", .tags(.passwordsManager))
@MainActor
struct CredentialConflictTests {
    @Test("Creates from existing and incoming credentials")
    func createsFromCredentials() {
        let existing = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "oldPassword",
        )

        let incoming = ImportedCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "newPassword",
        )

        let conflict = PasswordsManager.CredentialConflict(
            existing: existing,
            incoming: incoming,
        )

        #expect(conflict.domain == "example.com")
        #expect(conflict.username == "user@test.com")
        #expect(conflict.existing.password == "oldPassword")
        #expect(conflict.incoming.password == "newPassword")
        #expect(conflict.resolution == nil)
    }

    @Test("Has unique ID")
    func hasUniqueID() {
        let existing = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user",
            password: "old",
        )

        let incoming = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "new",
        )

        let conflict1 = PasswordsManager.CredentialConflict(
            existing: existing,
            incoming: incoming,
        )

        let conflict2 = PasswordsManager.CredentialConflict(
            existing: existing,
            incoming: incoming,
        )

        #expect(conflict1.id != conflict2.id)
    }

    @Test("Resolution can be set")
    func resolutionCanBeSet() {
        let existing = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user",
            password: "old",
        )

        let incoming = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "new",
        )

        var conflict = PasswordsManager.CredentialConflict(
            existing: existing,
            incoming: incoming,
        )

        #expect(conflict.resolution == nil)

        conflict.resolution = .keepExisting
        #expect(conflict.resolution == .keepExisting)

        conflict.resolution = .useImported
        #expect(conflict.resolution == .useImported)

        conflict.resolution = .keepBoth
        #expect(conflict.resolution == .keepBoth)
    }
}

// MARK: - ConflictResolution Tests

@Suite("ConflictResolution", .tags(.passwordsManager))
@MainActor
struct ConflictResolutionTests {
    @Test("All cases exist")
    func allCasesExist() {
        let resolutions: [PasswordsManager.ConflictResolution] = [
            .keepExisting,
            .useImported,
            .keepBoth,
        ]

        #expect(resolutions.count == 3)
    }

    @Test("Is Sendable")
    func isSendable() {
        let resolution: PasswordsManager.ConflictResolution = .keepExisting
        let _: any Sendable = resolution
        #expect(true)
    }
}

// MARK: - PasswordError Tests

@Suite("PasswordError", .tags(.passwordsManager))
@MainActor
struct PasswordErrorTests {
    @Test("Error descriptions are non-empty")
    func errorDescriptionsNonEmpty() {
        let errors: [PasswordsManager.PasswordError] = [
            .keychainError(-25_299),
            .credentialNotFound,
            .duplicateCredential,
            .invalidData,
            .accessDenied,
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Keychain error includes status code")
    func keychainErrorIncludesStatus() {
        let error = PasswordsManager.PasswordError.keychainError(-25_299)

        #expect(error.errorDescription!.contains("-25299"))
    }

    @Test("Is Sendable")
    func isSendable() {
        let error: PasswordsManager.PasswordError = .credentialNotFound
        let _: any Sendable = error
        #expect(true)
    }
}

// MARK: - ImportedCredential Tests

@Suite("ImportedCredential", .tags(.passwordsManager))
@MainActor
struct ImportedCredentialTests {
    @Test("Creates with required fields")
    func createsWithRequiredFields() {
        let credential = ImportedCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "secret123",
        )

        #expect(credential.domain == "example.com")
        #expect(credential.username == "user@test.com")
        #expect(credential.password == "secret123")
        #expect(credential.dateCreated == nil)
        #expect(credential.dateLastUsed == nil)
        #expect(credential.notes == nil)
    }

    @Test("Creates with all fields")
    func createsWithAllFields() {
        let created = Date()
        let lastUsed = Date().addingTimeInterval(3_600)

        let credential = ImportedCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "secret123",
            dateCreated: created,
            dateLastUsed: lastUsed,
            notes: "Test notes",
        )

        #expect(credential.dateCreated == created)
        #expect(credential.dateLastUsed == lastUsed)
        #expect(credential.notes == "Test notes")
    }

    @Test("Has unique ID")
    func hasUniqueID() {
        let cred1 = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        let cred2 = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        #expect(cred1.id != cred2.id)
    }

    @Test("Is Sendable")
    func isSendable() {
        let credential = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        let _: any Sendable = credential
        #expect(true)
    }
}

// MARK: - PasswordsManager URL Filtering Tests

@Suite("PasswordsManager URL Filtering", .tags(.passwordsManager), .serialized)
@MainActor
struct PasswordsManagerURLFilteringTests {
    @Test("Returns empty for HTTP URLs")
    func returnsEmptyForHTTP() {
        let manager = PasswordsManager()

        let httpURL = URL(string: "http://example.com")!
        let credentials = manager.findCredentials(for: httpURL)

        #expect(credentials.isEmpty, "HTTP URLs should not return credentials for security")
    }

    @Test("Returns empty for URLs without host")
    func returnsEmptyWithoutHost() {
        let manager = PasswordsManager()

        let fileURL = URL(string: "file:///path/to/file")!
        let credentials = manager.findCredentials(for: fileURL)

        #expect(credentials.isEmpty)
    }

    @Test("Returns empty for about URLs")
    func returnsEmptyForAbout() {
        let manager = PasswordsManager()

        let aboutURL = URL(string: "about:blank")!
        let credentials = manager.findCredentials(for: aboutURL)

        #expect(credentials.isEmpty)
    }

    @Test("Accepts HTTPS URLs")
    func acceptsHTTPS() {
        let manager = PasswordsManager()

        // This tests the URL filtering logic, not actual Keychain access
        // With no credentials in test Keychain, this returns empty but doesn't reject
        let httpsURL = URL(string: "https://example.com")!

        // We can't verify the result without Keychain access,
        // but we can verify it doesn't crash
        _ = manager.findCredentials(for: httpsURL)

        #expect(true, "Should process HTTPS URLs without error")
    }
}

// MARK: - PasswordsManager Initialization Tests

@Suite("PasswordsManager Initialization", .tags(.passwordsManager), .serialized)
@MainActor
struct PasswordsManagerInitializationTests {
    @Test("Find credential returns nil for non-existent")
    func findCredentialReturnsNil() {
        let manager = PasswordsManager()

        // This domain likely doesn't exist in test environment
        let credential = manager.findCredential(
            domain: "nonexistent-test-domain-\(UUID()).com",
            username: "nobody",
        )

        #expect(credential == nil)
    }
}

// MARK: - PasswordsManager Conflict Detection Tests

@Suite("PasswordsManager Conflict Detection", .tags(.passwordsManager), .serialized)
@MainActor
struct PasswordsManagerConflictDetectionTests {
    @Test("No conflict when credential doesn't exist")
    func noConflictWhenNotExists() {
        let manager = PasswordsManager()

        let imported = ImportedCredential(
            domain: "nonexistent-test-domain-\(UUID()).com",
            username: "user@test.com",
            password: "password123",
        )

        let conflict = manager.checkForConflict(imported)

        #expect(conflict == nil, "Should have no conflict for non-existent credential")
    }
}

// MARK: - PasswordsManager Third-Party Access Tests

@Suite("PasswordsManager Third-Party Access", .tags(.passwordsManager), .serialized)
@MainActor
struct PasswordsManagerThirdPartyTests {
    @Test("Request Keychain access throws access denied")
    func requestAccessThrowsDenied() async {
        let manager = PasswordsManager()

        // All browsers should currently throw accessDenied (stub implementation)
        do {
            _ = try await manager.requestKeychainAccess(for: .safari)
            Issue.record("Expected accessDenied error to be thrown")
        } catch let error as PasswordsManager.PasswordError {
            if case .accessDenied = error {
                // Expected
            } else {
                Issue.record("Expected accessDenied but got \(error)")
            }
        } catch {
            Issue.record("Expected PasswordError but got \(error)")
        }
    }
}

// MARK: - Notes

//
// PasswordsManager functionality requiring integration/Keychain tests:
//
// 1. saveCredential: Writes to real Keychain
// 2. updateCredential: Modifies Keychain entries
// 3. deleteCredential: Removes from Keychain
// 4. findCredentials with actual data: Requires Keychain entries
// 5. importCredential: Combines check + save/update
//
// The tests above verify:
// - Data model types (StoredCredential, CredentialConflict, ImportedCredential)
// - Error types and descriptions
// - URL scheme filtering (HTTPS-only requirement)
// - Safe behavior for non-existent credentials
//
// Full Keychain testing requires:
// - Test entitlements for Keychain access
// - Cleanup of test entries after each test
// - Potential sandbox environment
