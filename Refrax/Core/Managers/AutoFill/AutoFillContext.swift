import Foundation

/// Represents the position and context for showing the auto-fill popover.
///
/// This context is created when an autofillable field gains focus. It contains
/// all information needed to display the appropriate auto-fill popover based
/// on the field type (credentials, credit card, or contact).
struct AutoFillContext: Equatable {
    /// The type of autofill field.
    enum FieldType: Equatable {
        /// Username, email, or password field.
        case credential
        /// Credit card field (number, CVV, expiry, cardholder).
        case creditCard
        /// Contact/address field (name, phone, address).
        case contact
        /// OTP/2FA verification code field.
        case oneTimeCode
    }

    /// The autofill mode setting.
    ///
    /// Determines what content to show in the autofill menu:
    /// - `.disabled`: Should never create context (hasContent always false)
    /// - `.systemOnly`: Only system picker options
    /// - `.builtIn`: Full credentials, generation, and system pickers
    let autoFillMode: AutoFillMode

    /// The type of field that triggered the autofill.
    let fieldType: FieldType

    /// Whether this is specifically a password field (as opposed to username/email).
    ///
    /// When true, shows the "Suggest New Password" option and any recently
    /// generated passwords for this domain.
    let isPasswordField: Bool

    /// Whether this appears to be a login form (as opposed to registration/signup).
    ///
    /// When true on a password field, saved credentials are shown.
    /// When false, only "Suggest New Password" is shown (no existing credentials).
    /// Determined by form context analysis (autocomplete hints, password field count, form text).
    let isLoginForm: Bool

    /// Whether this is a confirm/verify password field (second password field in a registration form).
    ///
    /// When true, only "Fill Password Again" is shown (using the recently generated password).
    /// "Suggest New Password" is never shown for confirm fields.
    let isConfirmPasswordField: Bool

    /// Credentials available from local Keychain for the current URL.
    ///
    /// Only populated for `.credential` field type.
    let credentials: [PasswordsManager.StoredCredential]

    /// Recently generated password for this domain, if any.
    ///
    /// Only populated for `.credential` field type with `isPasswordField` true.
    let recentlyGeneratedPassword: String?

    /// Position of the focused field in web view coordinates.
    let rect: CGRect

    /// ID of the focused field.
    let fieldId: String

    /// ID of the associated username field, if detected.
    ///
    /// Only relevant for `.credential` field type.
    let usernameFieldId: String?

    /// URL of the current page.
    let url: URL

    /// Whether biometric/password authentication is required before filling credentials.
    let requireAuthForAutoFill: Bool

    init(
        autoFillMode: AutoFillMode = .builtIn,
        fieldType: FieldType,
        isPasswordField: Bool = false,
        isLoginForm: Bool = true,
        isConfirmPasswordField: Bool = false,
        credentials: [PasswordsManager.StoredCredential] = [],
        recentlyGeneratedPassword: String? = nil,
        rect: CGRect,
        fieldId: String,
        usernameFieldId: String?,
        url: URL,
        requireAuthForAutoFill: Bool = false,
    ) {
        self.autoFillMode = autoFillMode
        self.fieldType = fieldType
        self.isPasswordField = isPasswordField
        self.isLoginForm = isLoginForm
        self.isConfirmPasswordField = isConfirmPasswordField
        self.credentials = credentials
        self.recentlyGeneratedPassword = recentlyGeneratedPassword
        self.rect = rect
        self.fieldId = fieldId
        self.usernameFieldId = usernameFieldId
        self.url = url
        self.requireAuthForAutoFill = requireAuthForAutoFill
    }

    /// Whether this context has content to display in the autofill menu.
    ///
    /// Returns false for cases where the menu would be empty, such as:
    /// - Autofill mode is disabled
    /// - Registration forms with username/email fields (no credentials to show)
    /// - Confirm password fields without a recently generated password
    ///
    /// This is used to avoid showing an empty autofill popover.
    var hasContent: Bool {
        // Disabled mode never shows any autofill UI
        guard autoFillMode != .disabled else { return false }

        switch fieldType {
        case .credential:
            return hasCredentialContent

        case .creditCard, .contact, .oneTimeCode:
            // Always show system picker options
            return true
        }
    }

    /// Whether credential field type has content to display.
    ///
    /// Separated for clarity since credential logic differs by mode and form type.
    private var hasCredentialContent: Bool {
        switch autoFillMode {
        case .disabled:
            return false

        case .systemOnly:
            // System picker available on login forms and username/email fields
            // Not available on password fields in registration forms (can't generate)
            if isPasswordField, !isLoginForm {
                return false
            }
            return true

        case .builtIn:
            // Username/email fields: only show on login forms
            if !isPasswordField {
                return isLoginForm
            }
            // Primary password field: always has content (generate or fill options)
            if !isConfirmPasswordField {
                return true
            }
            // Confirm password field: only if there's a recent password to fill
            return recentlyGeneratedPassword != nil
        }
    }

    /// Custom equality that compares field identity rather than position.
    ///
    /// The rect is excluded because WebKit may fire repeated focus events
    /// for the same field with slightly different positions. We consider
    /// contexts "equal" if they represent the same logical field with
    /// the same available autofill data.
    static func == (lhs: AutoFillContext, rhs: AutoFillContext) -> Bool {
        lhs.autoFillMode == rhs.autoFillMode &&
            lhs.fieldId == rhs.fieldId &&
            lhs.url == rhs.url &&
            lhs.fieldType == rhs.fieldType &&
            lhs.isPasswordField == rhs.isPasswordField &&
            lhs.isLoginForm == rhs.isLoginForm &&
            lhs.isConfirmPasswordField == rhs.isConfirmPasswordField &&
            lhs.credentials == rhs.credentials &&
            lhs.recentlyGeneratedPassword == rhs.recentlyGeneratedPassword &&
            lhs.usernameFieldId == rhs.usernameFieldId &&
            lhs.requireAuthForAutoFill == rhs.requireAuthForAutoFill
    }
}
