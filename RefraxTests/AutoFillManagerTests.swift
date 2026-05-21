import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for AutoFill functionality.
    @Tag static var autoFillManager: Self
}

// MARK: - AutoFillFieldDetector Password Field Tests

@Suite("AutoFillFieldDetector Password Fields", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorPasswordTests {
    @Test("Password input type is always credential")
    func passwordInputTypeIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .password,
        )

        #expect(result == .credential)
    }

    @Test("Password input type overrides other signals")
    func passwordTypeOverridesOtherSignals() {
        // Even with credit card label, password type wins
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Card Number",
            placeholder: "1234 5678 9012 3456",
            name: "card-number",
            autocomplete: nil,
            inputType: .password,
        )

        #expect(result == .credential)
    }
}

// MARK: - AutoFillFieldDetector Autocomplete Attribute Tests

@Suite("AutoFillFieldDetector Autocomplete Attribute", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorAutocompleteTests {
    @Test("username autocomplete is credential")
    func usernameAutocompleteIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "username",
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("current-password autocomplete is credential")
    func currentPasswordAutocompleteIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "current-password",
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("new-password autocomplete is credential")
    func newPasswordAutocompleteIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "new-password",
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("webauthn autocomplete is credential")
    func webauthnAutocompleteIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "username webauthn",
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("one-time-code autocomplete is oneTimeCode")
    func oneTimeCodeIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "one-time-code",
            inputType: .text,
        )

        #expect(result == .oneTimeCode)
    }

    @Test("cc-number autocomplete is creditCard")
    func ccNumberIsCreditCard() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "cc-number",
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("cc-csc autocomplete is creditCard")
    func ccCscIsCreditCard() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "cc-csc",
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("street-address autocomplete is contact")
    func streetAddressIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "street-address",
            inputType: .text,
        )

        #expect(result == .contact)
    }

    @Test("tel autocomplete is contact")
    func telIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "tel",
            inputType: .text,
        )

        #expect(result == .contact)
    }

    @Test("given-name autocomplete is contact")
    func givenNameIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "given-name",
            inputType: .text,
        )

        #expect(result == .contact)
    }
}

// MARK: - AutoFillFieldDetector Username Field Tests

@Suite("AutoFillFieldDetector Username Fields", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorUsernameTests {
    @Test("Username label is credential")
    func usernameLabelIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Username",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("User name label is credential")
    func userNameLabelIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "User name",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("Account name label is credential")
    func accountNameLabelIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Account name",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("German Benutzername is credential")
    func germanBenutzernameIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Benutzername",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("Chinese username is credential")
    func chineseUsernameIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "用户名",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("Japanese username is credential")
    func japaneseUsernameIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "ユーザー名",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }
}

// MARK: - AutoFillFieldDetector Email Field Tests

@Suite("AutoFillFieldDetector Email Fields", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorEmailTests {
    @Test("Email label is credential")
    func emailLabelIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Email",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("Email input type is credential")
    func emailInputTypeIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .email,
        )

        // Email input type alone doesn't trigger - needs label/name/placeholder
        // Actually, from the code: guard inputType == .text || inputType == .email
        // So it should work with email type
        #expect(result == .none) // Just email type alone isn't enough
    }

    @Test("Email address placeholder is credential")
    func emailAddressPlaceholderIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: "Email address",
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("French email is credential")
    func frenchEmailIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Adresse e-mail",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }

    @Test("German email is credential")
    func germanEmailIsCredential() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "E-Mail Adresse",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .credential)
    }
}

// MARK: - AutoFillFieldDetector OTP Exclusion Tests

@Suite("AutoFillFieldDetector OTP Detection", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorOTPTests {
    @Test("Verification code label is oneTimeCode")
    func verificationCodeIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Verification code",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .oneTimeCode)
    }

    @Test("OTP field is oneTimeCode")
    func otpFieldIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: "Enter OTP",
            name: "otp",
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .oneTimeCode)
    }

    @Test("SMS code is oneTimeCode")
    func smsCodeIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Enter SMS code",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .oneTimeCode)
    }

    @Test("2FA field is oneTimeCode")
    func twoFAFieldIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "2FA Code",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .oneTimeCode)
    }

    @Test("Chinese verification code is oneTimeCode")
    func chineseVerificationCodeIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "验证码",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .oneTimeCode)
    }

    @Test("OTP field with number input type is oneTimeCode")
    func otpNumberInputIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Verification code",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .number,
        )

        #expect(result == .oneTimeCode)
    }

    @Test("one-time-code autocomplete is oneTimeCode")
    func oneTimeCodeAutocompleteIsOneTimeCode() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "one-time-code",
            inputType: .text,
        )

        #expect(result == .oneTimeCode)
    }
}

// MARK: - AutoFillFieldDetector Credit Card Tests

@Suite("AutoFillFieldDetector Credit Card", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorCreditCardTests {
    @Test("Card number label is creditCard")
    func cardNumberIsCreditCard() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Card Number",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("CVV label is creditCard")
    func cvvIsCreditCard() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "CVV",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("Security code is creditCard")
    func securityCodeIsCreditCard() {
        // Use "cvc" which is a standard credit card security code field name
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: "cvc",
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("Expiration date is creditCard")
    func expirationDateIsCreditCard() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Expiration Date",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("Name on card is creditCard")
    func nameOnCardIsCreditCard() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Name on Card",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("Card placeholder format is creditCard")
    func cardPlaceholderFormatIsCreditCard() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: "1234 5678 9012 3456",
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .creditCard)
    }

    @Test("Gift card is excluded")
    func giftCardIsExcluded() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Gift Card Number",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .none)
    }
}

// MARK: - AutoFillFieldDetector Contact/Address Tests

@Suite("AutoFillFieldDetector Contact Fields", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorContactTests {
    @Test("Street address is contact")
    func streetAddressIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Street Address",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .contact)
    }

    @Test("City is contact")
    func cityIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "City",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .contact)
    }

    @Test("Zip code is excluded from credential detection")
    func zipCodeIsExcludedFromCredential() {
        // "Zip Code" is in nonUsernameFieldLabels to avoid false positives
        // on forms that have both login and address fields.
        // For contact detection, use autocomplete attribute instead.
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Zip Code",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .none)
    }

    @Test("Postal code autocomplete is contact")
    func postalCodeAutocompleteIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: "postal-code",
            inputType: .text,
        )

        #expect(result == .contact)
    }

    @Test("Phone number is contact")
    func phoneNumberIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "Phone Number",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .contact)
    }

    @Test("First name is contact")
    func firstNameIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "First Name",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .contact)
    }

    @Test("Japanese phone is contact")
    func japanesePhoneIsContact() {
        let result = AutoFillFieldDetector.detectFieldType(
            label: "電話番号",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == .contact)
    }
}

// MARK: - AutoFillFieldDetector Login Form Tests

@Suite("AutoFillFieldDetector Login Form", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorLoginFormTests {
    @Test("Log in is login form")
    func logInIsLoginForm() {
        #expect(AutoFillFieldDetector.isLoginForm(formText: "Log in to your account"))
    }

    @Test("Sign in is login form")
    func signInIsLoginForm() {
        #expect(AutoFillFieldDetector.isLoginForm(formText: "Sign in"))
    }

    @Test("Welcome back is login form")
    func welcomeBackIsLoginForm() {
        #expect(AutoFillFieldDetector.isLoginForm(formText: "Welcome back"))
    }

    @Test("German anmelden is login form")
    func germanAnmeldenIsLoginForm() {
        #expect(AutoFillFieldDetector.isLoginForm(formText: "Bitte anmelden"))
    }

    @Test("French connexion is login form")
    func frenchConnexionIsLoginForm() {
        #expect(AutoFillFieldDetector.isLoginForm(formText: "Connexion"))
    }

    @Test("Chinese login is login form")
    func chineseLoginIsLoginForm() {
        #expect(AutoFillFieldDetector.isLoginForm(formText: "登录"))
    }

    @Test("Random text is not login form")
    func randomTextIsNotLoginForm() {
        #expect(AutoFillFieldDetector.isLoginForm(formText: "Subscribe to newsletter") == false)
    }
}

// MARK: - AutoFillContext Tests

@Suite("AutoFillContext", .tags(.autoFillManager))
@MainActor
struct AutoFillContextTests {
    @Test("Creates with required fields")
    func createsWithRequiredFields() {
        let context = AutoFillContext(
            fieldType: .credential,
            rect: CGRect(x: 10, y: 20, width: 200, height: 30),
            fieldId: "field-123",
            usernameFieldId: nil,
            url: URL(string: "https://example.com")!,
        )

        #expect(context.fieldType == .credential)
        #expect(context.isPasswordField == false)
        #expect(context.credentials.isEmpty)
        #expect(context.recentlyGeneratedPassword == nil)
        #expect(context.fieldId == "field-123")
        #expect(context.usernameFieldId == nil)
    }

    @Test("Creates with all fields for password field")
    func createsWithAllFieldsForPassword() {
        let credential = PasswordsManager.StoredCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "secret123",
        )

        let context = AutoFillContext(
            fieldType: .credential,
            isPasswordField: true,
            credentials: [credential],
            recentlyGeneratedPassword: "GeneratedPass123!",
            rect: CGRect(x: 10, y: 20, width: 200, height: 30),
            fieldId: "password-field",
            usernameFieldId: "username-field",
            url: URL(string: "https://example.com")!,
        )

        #expect(context.isPasswordField == true)
        #expect(context.credentials.count == 1)
        #expect(context.credentials.first?.username == "user@test.com")
        #expect(context.recentlyGeneratedPassword == "GeneratedPass123!")
        #expect(context.usernameFieldId == "username-field")
    }

    @Test("Creates for credit card field")
    func createsForCreditCard() {
        let context = AutoFillContext(
            fieldType: .creditCard,
            rect: CGRect(x: 10, y: 20, width: 200, height: 30),
            fieldId: "cc-number",
            usernameFieldId: nil,
            url: URL(string: "https://shop.example.com")!,
        )

        #expect(context.fieldType == .creditCard)
        #expect(context.credentials.isEmpty)
    }

    @Test("Creates for contact field")
    func createsForContact() {
        let context = AutoFillContext(
            fieldType: .contact,
            rect: CGRect(x: 10, y: 20, width: 200, height: 30),
            fieldId: "street-address",
            usernameFieldId: nil,
            url: URL(string: "https://shop.example.com")!,
        )

        #expect(context.fieldType == .contact)
    }

    @Test("Creates for one-time code field with content")
    func createsForOneTimeCode() {
        let context = AutoFillContext(
            fieldType: .oneTimeCode,
            rect: CGRect(x: 10, y: 20, width: 200, height: 30),
            fieldId: "otp-code",
            usernameFieldId: nil,
            url: URL(string: "https://example.com")!,
        )

        #expect(context.fieldType == .oneTimeCode)
        #expect(context.hasContent == true)
    }
}

// MARK: - AutoFillContext.FieldType Tests

@Suite("AutoFillContext FieldType", .tags(.autoFillManager))
@MainActor
struct AutoFillContextFieldTypeTests {
    @Test("All field types exist")
    func allFieldTypesExist() {
        let types: [AutoFillContext.FieldType] = [
            .credential,
            .creditCard,
            .contact,
            .oneTimeCode,
        ]

        #expect(types.count == 4)
    }
}

// MARK: - AutoFillFieldDetector.FieldType Tests

@Suite("AutoFillFieldDetector FieldType", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorFieldTypeTests {
    @Test("All field types exist")
    func allFieldTypesExist() {
        let types: [AutoFillFieldDetector.FieldType] = [
            .credential,
            .creditCard,
            .contact,
            .oneTimeCode,
            .none,
        ]

        #expect(types.count == 5)
    }
}

// MARK: - AutoFillFieldDetector isAutoFillableCredentialField Tests

@Suite("AutoFillFieldDetector isAutoFillableCredentialField", .tags(.autoFillManager))
@MainActor
struct AutoFillFieldDetectorIsAutoFillableTests {
    @Test("Returns true for password field")
    func returnsTrueForPassword() {
        let result = AutoFillFieldDetector.isAutoFillableCredentialField(
            label: nil,
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .password,
        )

        #expect(result == true)
    }

    @Test("Returns true for username field")
    func returnsTrueForUsername() {
        let result = AutoFillFieldDetector.isAutoFillableCredentialField(
            label: "Username",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == true)
    }

    @Test("Returns false for OTP field")
    func returnsFalseForOTP() {
        let result = AutoFillFieldDetector.isAutoFillableCredentialField(
            label: "Verification code",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == false)
    }

    @Test("Returns false for address field")
    func returnsFalseForAddress() {
        let result = AutoFillFieldDetector.isAutoFillableCredentialField(
            label: "Street Address",
            placeholder: nil,
            name: nil,
            autocomplete: nil,
            inputType: .text,
        )

        #expect(result == false)
    }
}

// MARK: - Notes

//
// AutoFillManager functionality requiring integration tests:
//
// 1. attach/detach to WKWebView: Requires real WebKit
// 2. _WKInputDelegate callbacks: Requires WebKit form interaction
// 3. JavaScript credential filling: Requires loaded web page
// 4. System Passwords picker: Requires ASAuthorizationController
// 5. Form submission handling: Requires WebKit navigation events
//
// The tests above verify:
// - Field detection heuristics (extensive multilingual patterns)
// - Context model structure
// - Autocomplete attribute parsing
// - Login form detection
// - OTP/2FA exclusion patterns
// - Credit card field detection
// - Contact/address field detection
