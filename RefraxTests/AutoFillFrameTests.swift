import CoreGraphics
import Foundation
import Testing
import WebKit

@testable import Refrax

// Tests for autofill across frame boundaries — the logic that lets a login form
// served from a cross-origin iframe (Apple ID's idmsa.apple.com widget inside
// appleid.apple.com, embedded SSO) fill and position correctly. The WebKit-bound
// pieces (frame-targeted eval, message routing) need integration coverage; the
// pure translations below are unit-tested here.

// MARK: - Sub-Frame Geometry

@Suite("AutoFillFrameGeometry", .tags(.autoFillManager))
struct AutoFillFrameGeometryTests {
    @Test("Field rect shifts by the iframe content origin")
    func rectShiftsByFrameOrigin() {
        let field = CGRect(x: 12, y: 40, width: 220, height: 30)
        let result = AutoFillFrameGeometry.rectInTopView(
            fieldRectInFrame: field,
            frameOrigin: CGPoint(x: 100, y: 260),
        )

        #expect(result == CGRect(x: 112, y: 300, width: 220, height: 30))
    }

    @Test("Zero origin leaves the rect unchanged (main-frame fallback)")
    func zeroOriginIsIdentity() {
        let field = CGRect(x: 5, y: 5, width: 100, height: 20)
        let result = AutoFillFrameGeometry.rectInTopView(fieldRectInFrame: field, frameOrigin: .zero)

        #expect(result == field)
    }

    @Test("Size is preserved, only the origin moves")
    func sizePreserved() {
        let field = CGRect(x: 0, y: 0, width: 300, height: 44)
        let result = AutoFillFrameGeometry.rectInTopView(
            fieldRectInFrame: field,
            frameOrigin: CGPoint(x: -20, y: 15),
        )

        #expect(result.size == field.size)
        #expect(result.origin == CGPoint(x: -20, y: 15))
    }
}

// MARK: - Sub-Frame Domain Resolution

@Suite("AutoFillDomain", .tags(.autoFillManager))
@MainActor
struct AutoFillDomainTests {
    @Test("Same-site sub-frame keys to the top-level host (Apple ID)")
    func sameSiteUsesTopLevel() {
        let top = URL(string: "https://appleid.apple.com/sign-in")!
        let frame = URL(string: "https://idmsa.apple.com/appleauth/auth/authorize/signin")!

        let result = AutoFillDomain.submissionURL(topLevel: top, frame: frame)

        #expect(result == top)
    }

    @Test("Third-party sub-frame keeps its own host")
    func thirdPartyUsesFrame() {
        let top = URL(string: "https://shop.example.com/checkout")!
        let frame = URL(string: "https://accounts.google.com/signin/oauth")!

        let result = AutoFillDomain.submissionURL(topLevel: top, frame: frame)

        #expect(result == frame)
    }

    @Test("Missing top-level falls back to the frame")
    func nilTopLevelUsesFrame() {
        let frame = URL(string: "https://idmsa.apple.com/appleauth")!

        let result = AutoFillDomain.submissionURL(topLevel: nil, frame: frame)

        #expect(result == frame)
    }

    @Test("Same host resolves to the top-level URL")
    func sameHostUsesTopLevel() {
        let top = URL(string: "https://example.com/login")!
        let frame = URL(string: "https://example.com/embedded/form")!

        let result = AutoFillDomain.submissionURL(topLevel: top, frame: frame)

        #expect(result == top)
    }
}

// MARK: - HTML Input Type Mapping

@Suite("WKInputType from HTML type", .tags(.autoFillManager))
struct WKInputTypeMappingTests {
    @Test("Known HTML input types map to their WebKit equivalents")
    func knownTypesMap() {
        #expect(WKInputType(htmlType: "password") == .password)
        #expect(WKInputType(htmlType: "email") == .email)
        #expect(WKInputType(htmlType: "tel") == .phone)
        #expect(WKInputType(htmlType: "url") == .URL)
        #expect(WKInputType(htmlType: "number") == .number)
        #expect(WKInputType(htmlType: "search") == .search)
    }

    @Test("Case is ignored")
    func caseInsensitive() {
        #expect(WKInputType(htmlType: "PASSWORD") == .password)
        #expect(WKInputType(htmlType: "Email") == .email)
    }

    @Test("Unknown or empty types default to text")
    func unknownDefaultsToText() {
        #expect(WKInputType(htmlType: "") == .text)
        #expect(WKInputType(htmlType: "checkbox") == .text)
        #expect(WKInputType(htmlType: "made-up") == .text)
    }
}

// MARK: - Apple Sign-In Field Shape

// The two fields on Apple's sign-in widget, exactly as their descriptors arrive
// from the sub-frame reporter. These regress the specific page that motivated
// frame-aware autofill.
@Suite("Apple sign-in field detection", .tags(.autoFillManager))
@MainActor
struct AppleSignInFieldTests {
    @Test("'Email or Phone Number' label is a credential field")
    func emailOrPhoneLabelIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Email or Phone Number",
            placeholder: nil,
            name: "accountName",
            autocomplete: "username",
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("The password field is a credential field")
    func passwordIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Password",
            placeholder: nil,
            name: "password",
            autocomplete: "current-password",
            inputType: .password,
        )

        #expect(result == .credential)
    }
}
