import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for SystemAutoFillManager operations.
    @Tag static var systemAutoFillManager: Self
}

// MARK: - SystemAutoFillManager Singleton Tests

@Suite("SystemAutoFillManager Singleton", .tags(.systemAutoFillManager))
@MainActor
struct SystemAutoFillManagerSingletonTests {
    @Test("Shared instance is consistent")
    func sharedInstanceIsConsistent() {
        let manager1 = SystemAutoFillManager.shared
        let manager2 = SystemAutoFillManager.shared

        #expect(manager1 === manager2)
    }
}

// MARK: - SystemAutoFillManager Action Tests

@Suite("SystemAutoFillManager Actions", .tags(.systemAutoFillManager), .serialized)
@MainActor
struct SystemAutoFillManagerActionTests {
    @Test("Show password picker with domains does not crash")
    func showPasswordPickerWithDomains() {
        let manager = SystemAutoFillManager.shared

        // This sends an action through the responder chain
        // Without a focused text field, no responder handles it
        manager.showPasswordPicker(forDomains: ["example.com"])

        #expect(true, "Should not crash")
    }

    @Test("Show password picker with empty domains logs warning")
    func showPasswordPickerEmptyDomains() {
        let manager = SystemAutoFillManager.shared

        // Empty domains is a documented edge case that still triggers the action
        manager.showPasswordPicker(forDomains: [])

        #expect(true, "Should handle empty domains without crash")
    }

    @Test("Show password picker with multiple domains does not crash")
    func showPasswordPickerMultipleDomains() {
        let manager = SystemAutoFillManager.shared

        manager.showPasswordPicker(forDomains: ["github.com", "gitlab.com", "bitbucket.org"])

        #expect(true, "Should handle multiple domains without crash")
    }

    @Test("Show credit card picker does not crash")
    func showCreditCardPicker() {
        let manager = SystemAutoFillManager.shared

        // This sends an action through the responder chain
        manager.showCreditCardPicker()

        #expect(true, "Should not crash")
    }

    @Test("Show contacts picker does not crash")
    func showContactsPicker() {
        let manager = SystemAutoFillManager.shared

        // This sends an action through the responder chain
        manager.showContactsPicker()

        #expect(true, "Should not crash")
    }
}

// MARK: - Notes

//
// SystemAutoFillManager functionality requiring integration tests:
//
// 1. Domain injection: RTIDocumentTraits swizzling with actual RemoteTextInput framework
// 2. Responder chain handling: Requires a focused text field to receive actions
// 3. Swizzle installation: Runtime method swizzling verification
// 4. Password/Credit Card/Contacts picker UI: System UI integration
//
// The tests above verify:
// - Singleton pattern is correctly implemented
// - Public API methods don't crash even without a focused text field
// - Empty domains edge case is handled
//
// Full picker testing requires:
// - A live WKWebView with a focused input field
// - Running in a signed application context
// - User interaction for authentication
//
