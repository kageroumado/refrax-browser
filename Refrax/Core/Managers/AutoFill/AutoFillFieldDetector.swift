import Foundation

/// Detects whether form fields are suitable for autofill.
///
/// Uses heuristics to identify username, email, password, credit card, and contact fields.
/// Supports multilingual field labels based on Apple iCloud Keychain patterns.
///
/// ## Overview
///
/// The detector analyzes field properties (label, placeholder, name, autocomplete) to determine:
/// - Whether a field is suitable for credential autofill (username/password)
/// - Whether a field is a credit card field (number, CVV, expiry, cardholder)
/// - Whether a field is a contact/address field (name, phone, address)
///
/// ## Usage
///
/// ```swift
/// let fieldType = AutoFillFieldDetector.detectFieldType(
///     label: "Card Number",
///     placeholder: "1234 5678 9012 3456",
///     name: "cc-number",
///     autocomplete: "cc-number",
///     inputType: .text
/// )
/// // Returns .creditCard
/// ```
enum AutoFillFieldDetector {
    /// The type of autofill field detected.
    enum FieldType {
        /// Username, email, or password field - use Passwords picker.
        case credential
        /// Credit card field (number, CVV, expiry, cardholder) - use Credit Cards picker.
        case creditCard
        /// Contact/address field (name, phone, address) - use Contacts picker.
        case contact
        /// OTP/2FA verification code field - use Passwords picker for TOTP.
        case oneTimeCode
        /// Not an autofillable field.
        case none
    }

    // MARK: - Field Detection

    /// Detects the type of autofill field.
    ///
    /// - Parameters:
    ///   - label: The field's label text (from `<label>` element).
    ///   - placeholder: The field's placeholder text.
    ///   - name: The field's name attribute.
    ///   - autocomplete: The field's autocomplete attribute value.
    ///   - inputType: The WebKit input type.
    /// - Returns: The detected field type for autofill.
    static func detectFieldType(
        label: String?,
        placeholder: String?,
        name: String?,
        autocomplete: String?,
        inputType: WKInputType,
    ) -> FieldType {
        // Respect explicit autocomplete disable or search hints
        // Note: "search" is non-standard but commonly used to indicate search fields
        let disabledValues: Set<String> = ["off", "nope", "no", "false", "search"]
        if let ac = autocomplete?.lowercased(), disabledValues.contains(ac) {
            return .none
        }

        // Password fields are always credential fields
        if inputType == .password {
            return .credential
        }

        let searchableText = buildSearchableText(label: label, placeholder: placeholder, name: name)
        let autocompleteTokens = parseAutocompleteTokens(autocomplete)

        // Check autocomplete tokens first - they are the most reliable signal

        // OTP fields use Passwords picker for TOTP codes
        if autocompleteTokens.contains("one-time-code") {
            return .oneTimeCode
        }

        // Credential autocomplete tokens take highest priority
        if hasCredentialAutocompleteToken(autocompleteTokens) {
            return .credential
        }

        // Credit card autocomplete tokens
        if hasCreditCardAutocompleteToken(autocompleteTokens) {
            return .creditCard
        }

        // Contact/address autocomplete tokens
        if hasContactAutocompleteToken(autocompleteTokens) {
            return .contact
        }

        // Fall back to heuristics based on labels/names

        // Check for credit card fields via labels/names
        if isCreditCardField(searchableText: searchableText, placeholder: placeholder) {
            return .creditCard
        }

        // Check for OTP/verification codes before input type guard
        // OTP fields can be text, number, or tel type
        if matchesAnyPattern(searchableText, patterns: oneTimeCodeFieldLabels) {
            return .oneTimeCode
        }

        // Check for credential fields (only text/email types)
        guard inputType == .text || inputType == .email else {
            // For other input types, check contact fields
            if isContactField(searchableText: searchableText) {
                return .contact
            }
            return .none
        }

        // Exclude non-username fields
        if matchesAnyPattern(searchableText, patterns: nonUsernameFieldLabels) {
            return .none
        }

        // Check for email field - prioritize as credential over contact
        if matchesAnyPattern(searchableText, patterns: emailFieldLabels) {
            return .credential
        }

        // Check for username field
        if matchesAnyPattern(searchableText, patterns: usernameFieldLabels) {
            return .credential
        }

        // Check for contact/address fields via labels/names
        // This comes after credential checks to avoid false positives on login forms
        if isContactField(searchableText: searchableText) {
            return .contact
        }

        return .none
    }

    /// Determines if a field is suitable for credential autofill.
    ///
    /// - Parameters:
    ///   - label: The field's label text (from `<label>` element).
    ///   - placeholder: The field's placeholder text.
    ///   - name: The field's name attribute.
    ///   - autocomplete: The field's autocomplete attribute value.
    ///   - inputType: The WebKit input type.
    /// - Returns: `true` if the field should trigger credential autofill.
    static func isAutoFillableCredentialField(
        label: String?,
        placeholder: String?,
        name: String?,
        autocomplete: String?,
        inputType: WKInputType,
    ) -> Bool {
        detectFieldType(
            label: label,
            placeholder: placeholder,
            name: name,
            autocomplete: autocomplete,
            inputType: inputType,
        ) == .credential
    }

    /// Checks if a form appears to be a login form based on surrounding context.
    ///
    /// - Parameter formText: Combined text from form labels, buttons, and headings.
    /// - Returns: `true` if the form appears to be a login form.
    static func isLoginForm(formText: String) -> Bool {
        let normalizedText = formText.lowercased()
        for keyword in loginFormTypeKeywords {
            if normalizedText.contains(keyword) {
                return true
            }
        }
        return false
    }

    // MARK: - Private Helpers

    private static func buildSearchableText(label: String?, placeholder: String?, name: String?) -> String {
        [label, placeholder, name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
    }

    private static func matchesAnyPattern(_ text: String, patterns: [String]) -> Bool {
        guard !text.isEmpty else { return false }
        for pattern in patterns {
            if text.contains(pattern.lowercased()) {
                return true
            }
        }
        return false
    }

    // MARK: - Autocomplete Token Parsing

    /// Parses the autocomplete attribute into individual tokens.
    /// The autocomplete attribute can contain multiple space-separated tokens (e.g., "username webauthn").
    private static func parseAutocompleteTokens(_ autocomplete: String?) -> Set<String> {
        guard let autocomplete = autocomplete?.lowercased(), !autocomplete.isEmpty else {
            return []
        }
        return Set(autocomplete.split(separator: " ").map { String($0) })
    }

    /// Checks if any token indicates a credential field.
    private static func hasCredentialAutocompleteToken(_ tokens: Set<String>) -> Bool {
        let credentialTokens: Set<String> = [
            "username", "current-password", "new-password",
            "webauthn", // Often paired with username for passkey support
        ]
        return !tokens.isDisjoint(with: credentialTokens)
    }

    /// Checks if any token indicates a credit card field.
    private static func hasCreditCardAutocompleteToken(_ tokens: Set<String>) -> Bool {
        let ccTokens: Set<String> = [
            "cc-number", "cc-name", "cc-given-name", "cc-additional-name", "cc-family-name",
            "cc-exp", "cc-exp-month", "cc-exp-year", "cc-csc", "cc-type",
        ]
        return !tokens.isDisjoint(with: ccTokens)
    }

    /// Checks if any token indicates a contact/address field.
    private static func hasContactAutocompleteToken(_ tokens: Set<String>) -> Bool {
        let contactTokens: Set<String> = [
            "name", "given-name", "family-name", "additional-name",
            "honorific-prefix", "honorific-suffix", "nickname",
            "tel", "tel-country-code", "tel-national", "tel-area-code", "tel-local",
            "tel-extension",
            "street-address", "address-line1", "address-line2", "address-line3",
            "address-level1", "address-level2", "address-level3", "address-level4",
            "postal-code", "country", "country-name",
            "organization", "organization-title",
            "bday", "bday-day", "bday-month", "bday-year",
            "sex", "language",
        ]
        return !tokens.isDisjoint(with: contactTokens)
    }

    // MARK: - Credit Card Detection

    private static func isCreditCardField(searchableText: String, placeholder: String?) -> Bool {
        // Check for non-credit-card patterns first (gift cards, etc.)
        if matchesAnyPattern(searchableText, patterns: nonCreditCardLabels) {
            return false
        }

        // Check card number patterns
        if matchesAnyPattern(searchableText, patterns: creditCardNumberLabels) {
            return true
        }

        // Check CVV/security code patterns
        if matchesAnyPattern(searchableText, patterns: creditCardSecurityCodeLabels) {
            return true
        }

        // Check cardholder name patterns
        if matchesAnyPattern(searchableText, patterns: creditCardholderLabels) {
            return true
        }

        // Check expiration patterns
        if matchesAnyPattern(searchableText, patterns: creditCardExpirationLabels) {
            return true
        }

        // Check placeholder for card number format (e.g., "1234 5678 9012 3456")
        if let placeholder = placeholder?.lowercased() {
            let cardNumberPattern = #"[0-9]{4}[ -][0-9]{4}[ -][0-9]{4}[ -][0-9]{4}"#
            if placeholder.range(of: cardNumberPattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Contact Detection

    private static func isContactField(searchableText: String) -> Bool {
        // Check address patterns
        if matchesAnyPattern(searchableText, patterns: addressFieldLabels) {
            return true
        }

        // Check phone patterns
        if matchesAnyPattern(searchableText, patterns: phoneFieldLabels) {
            return true
        }

        // Check name patterns (but not username which is for credentials)
        if matchesAnyPattern(searchableText, patterns: nameFieldLabels) {
            // Exclude if it also matches username patterns
            if matchesAnyPattern(searchableText, patterns: usernameFieldLabels) {
                return false
            }
            return true
        }

        return false
    }

    // MARK: - Keywords (Based on Apple iCloud Keychain patterns)

    /// Keywords indicating a login form type.
    private static let loginFormTypeKeywords: [String] = [
        // English
        "log in", "login", "log on", "sign in", "signin", "sign on", "signon",
        "welcome back", "enter your password", "reauth",
        // German
        "anmelden", "absenden",
        // French
        "connexion",
        // Spanish
        "iniciar sesión",
        // Norwegian
        "logg inn",
        // Chinese
        "登录", "登入",
    ]

    /// Labels indicating a username field.
    private static let usernameFieldLabels: [String] = [
        // English
        "username", "user name", "screenname", "screen name",
        "loginname", "login name", "account name",
        "userid", "user id", "loginid", "login id", "accountid", "account id",
        "online id", "gmailaddress", "gmail address",
        // German
        "benutzername", "anmeldename",
        // Spanish
        "usuario", "nombre de usuario",
        // French
        "nom d'utilisateur", "identifiant",
        // Italian
        "nome utente",
        // Portuguese
        "nome de usuário", "nome de utilizador",
        // Japanese
        "ユーザー名", "ユーザーネーム", "アカウント名",
        // Korean
        "사용자 이름", "사용자이름", "아이디",
        // Chinese
        "用户名", "用戶名", "帳號", "账号",
        // Russian
        "имя пользователя", "логин",
    ]

    /// Labels indicating an email field.
    private static let emailFieldLabels: [String] = [
        // English
        "email", "e-mail", "emailaddr", "emailaddress", "email address",
        // German
        "e-mail adresse", "e-mail-adresse",
        // French
        "courriel", "adresse e-mail", "adresse électronique", "adresse de messagerie",
        "courrier électronique", "messagerie électronique",
        // Spanish
        "correo electrónico", "dirección de correo",
        // Italian
        "posta elettronica", "indirizzo e-mail", "indirizzo di posta elettronica",
        // Portuguese
        "correio eletrônico", "endereço de e-mail",
        // Japanese
        "メール", "メールアドレス", "emailアドレス", "email アドレス",
        "電子メール", "eメールアドレス", "メアド", "メルアド",
        // Korean
        "이메일", "이메일 주소", "이메일주소", "email 주소", "email주소",
        "e-mail 주소", "e-mail주소",
        // Chinese
        "电子邮件", "电子邮件地址", "電子郵件", "電子郵件位址",
        "電子郵件地址", "電子郵件信箱", "電子信箱", "電子郵箱", "電郵",
        // Russian
        "адрес электронной почты", "электронный адрес", "адрес e-mail", "адрес email",
        // Arabic
        "البريد الإلكتروني",
        // Hebrew
        "דוא״ל", "מייל",
        // Turkish
        "e-posta", "eposta", "e-posta adresi", "eposta adresi",
        // Thai
        "อีเมล", "อีเมลที่อยู่", "ที่อยู่อีเมล", "อี-เมล",
        // Ukrainian
        "електронна пошта", "електроннапошта", "ел.пошта", "ел. пошта",
        "електронна адреса", "електроннаадреса", "ел.адреса", "ел. адреса",
        // Romanian
        "adresăemail",
        // Croatian
        "e-mail adresa", "adresa e-pošte", "e-pošta",
        // Finnish
        "sähköposti", "s-posti", "sähköpostiosoite",
        // Swedish
        "e-postadress", "epostadress", "emejl", "mejl", "mejladress",
        // Norwegian
        "e-post", "e-postadr", "e-postadresse", "epost",
        // Catalan
        "correu electrònic",
        // Vietnamese
        "email",
    ]

    /// Labels indicating fields that should NOT be treated as username fields.
    private static let nonUsernameFieldLabels: [String] = [
        // Authentication/verification
        "login code", "otpcode", "otp code", "password", "captcha", "recaptcha",
        "sound", "answer", "confirmation code", "verification code",
        "security question",
        // Search/filter fields (often have "email" or "username" in placeholder)
        // English
        "search", "find", "filter", "query", "lookup", "keyword", "keywords",
        "search for", "search by", "search email", "search user",
        // German
        "suche", "suchen", "suchbegriff", "suchfeld",
        // French
        "recherche", "rechercher", "chercher",
        // Spanish
        "buscar", "búsqueda", "busqueda",
        // Italian
        "cerca", "ricerca", "ricercare",
        // Portuguese
        "pesquisa", "pesquisar", "busca",
        // Japanese
        "検索", "サーチ",
        // Chinese
        "搜索", "搜尋", "查找", "查詢",
        // Korean
        "검색", "찾기",
        // Russian
        "поиск", "искать",
        // Location codes (could match "code" patterns)
        "zip code", "postal code", "area code",
        // Other non-credential contexts
        "stock symbol", "chart", "table", "certificate",
        "cash card number", "gift card", "coupon", "promo code", "discount code",
        "reference number", "tracking number", "order number", "invoice",
        "comment", "message", "feedback", "review", "description", "notes",
        "subject", "title", "headline", "caption",
        "url", "link", "website", "domain",
        "tag", "tags", "label", "category",
    ]

    /// Labels indicating one-time code / 2FA fields.
    private static let oneTimeCodeFieldLabels: [String] = [
        // English
        "security code", "login code", "enter the code", "enter code",
        "otp", "onetimecode", "onetimepasscode", "one time password", "one time passcode",
        "verification code", "verificationcode", "confirmation code",
        "identification code", "identificationcode", "activation code", "access code",
        "sms", "digit code", "2fa", "twofactor", "two-factor", "two factor",
        "authentication code", "two step sign in", "two-step sign in",
        "mfa code", "sign-in code", "passcode texted", "passcode expires",
        // Chinese
        "验证码", "校验码", "驗證碼", "驗証碼", "確認碼", "認證碼",
        // Japanese
        "確認コード", "認証コード",
        // Korean
        "인증번호", "확인코드",
        // French
        "code de sécurité", "code de vérification", "code de validation",
        "code d'identification", "code d'authentification", "code d'autorisation",
        "code de confirmation", "code sms de vérification", "code de connexion",
        // German
        "authorisierungscode", "sicherheitscode", "überprüfungscode",
        "bestätigungscode", "bestatigungscode", "verifizierungscode", "aktivierungscode",
        // Italian
        "codice di sicurezza", "codice attivazione", "codice di attivazione",
        "codice di conferma", "codice di verifica",
        // Polish
        "kod bezpieczeństwa", "kod autoryzacyjny", "kod weryfikacyjny",
        // Spanish
        "código de seguridad", "código de confirmación",
        // Portuguese
        "código de seguranca", "digite o codigo", "código de verificación",
        "código de verificação", "código de confirmacao",
        // Russian
        "код проверки", "код безопасности", "код подтверждения", "код аутентификации",
        // Ukrainian
        "код підтвердження",
        // Turkish
        "dogrulama kodu",
        // Vietnamese
        "mã bảo mật", "mã xác minh", "mã kích hoạt",
        // Thai
        "รหัสความปลอดภัย", "รหัสยืนยัน", "รหัสotp", "รหัสการตรวจสอบยืนยัน", "รหัสการยืนยัน",
        // Indonesian
        "kode keamanan", "kode konfirmasi", "kode verifikasi",
        // Hindi
        "सत्यापन कोड",
        // Malay
        "kod pengesahan", "masukkan kod",
        // Romanian
        "codul de confirmare",
    ]

    // MARK: - Credit Card Keywords (Based on Apple iCloud Keychain patterns)

    /// Labels indicating a credit card number field.
    private static let creditCardNumberLabels: [String] = [
        "card number", "cardnumber", "cardnum",
        "creditcardnumber", "credit card number", "newcreditcardnumber",
        "creditcardno", "credit card no", "card#", "card #",
        // Italian
        "numero carta di credito", "numero della carta di credito",
        // Spanish
        "número de tarjeta", "numero de tarjeta",
        // French
        "numéro de carte", "numero de carte",
        // German
        "kartennummer", "kreditkartennummer",
        // Portuguese
        "número do cartão",
    ]

    /// Labels indicating a CVV/security code field.
    private static let creditCardSecurityCodeLabels: [String] = [
        "cvv", "cvc", "cvc2", "cvv2", "card verification", "cvvx",
        "security code", "card security", "verification number",
        // Italian
        "codice di sicurezza",
        // Spanish
        "código de seguridad",
        // French
        "cryptogramme", "code de sécurité",
        // German
        "prüfnummer", "sicherheitscode",
    ]

    /// Labels indicating a cardholder name field.
    private static let creditCardholderLabels: [String] = [
        "name on credit card", "name on card", "nameoncard",
        "cardholder", "card holder", "cardholder name",
        // Italian
        "titolare della carta di credito", "titolare della carta",
        // Spanish
        "titular de la tarjeta",
        // French
        "titulaire de la carte",
        // German
        "karteninhaber",
    ]

    /// Labels indicating an expiration date field.
    private static let creditCardExpirationLabels: [String] = [
        "expiration date", "expirationdate", "expiration",
        "expiry", "expires", "expire", "exp date", "expdate",
        "valid thru", "valid through", "valid until",
        // French
        "date d'expiration",
        // Spanish
        "expira", "fecha de expiración", "expiración",
        // Portuguese
        "expiração", "validade",
        // German
        "gültig bis", "ablaufdatum",
        // Italian
        "scadenza", "data di scadenza",
    ]

    /// Labels indicating non-credit-card fields (gift cards, etc.).
    private static let nonCreditCardLabels: [String] = [
        "gift card", "giftcard", "rewards card", "rewardscard",
        "loyalty card", "loyaltycard", "health card", "library card",
        "service card", "membership card", "member card",
    ]

    // MARK: - Contact/Address Keywords

    /// Labels indicating an address field.
    private static let addressFieldLabels: [String] = [
        // English
        "address", "street address", "street", "address line",
        "address1", "address2", "addr", "addrstreet",
        "city", "state", "province", "region",
        "zip", "zip code", "zipcode", "postal code", "postalcode", "postcode",
        "country",
        // French
        "adresse", "adresse postale", "rue", "ville", "code postal",
        // Spanish
        "dirección", "calle", "ciudad", "código postal",
        // German
        "adresse", "straße", "strasse", "stadt", "postleitzahl", "plz",
        // Italian
        "indirizzo", "via", "città", "cap", "codice postale",
        // Portuguese
        "endereço", "rua", "cidade", "cep", "código postal",
    ]

    /// Labels indicating a phone field.
    private static let phoneFieldLabels: [String] = [
        // English
        "phone", "phone number", "phonenumber", "telephone", "tel",
        "mobile", "mobile number", "cell", "cell phone", "cellphone",
        "home phone", "work phone", "fax",
        // French
        "téléphone", "numéro de téléphone", "portable", "mobile",
        // Spanish
        "teléfono", "número de teléfono", "móvil", "celular",
        // German
        "telefon", "telefonnummer", "handy", "mobiltelefon",
        // Italian
        "telefono", "numero di telefono", "cellulare",
        // Portuguese
        "telefone", "número de telefone", "celular",
        // Japanese
        "電話", "電話番号",
        // Chinese
        "电话", "电话号码", "手机",
    ]

    /// Labels indicating a name field (first name, last name, full name).
    private static let nameFieldLabels: [String] = [
        // English
        "first name", "firstname", "given name", "givenname",
        "last name", "lastname", "family name", "familyname", "surname",
        "full name", "fullname", "your name", "name",
        "middle name", "middlename",
        // French
        "prénom", "nom", "nom de famille",
        // Spanish
        "nombre", "apellido", "nombre completo",
        // German
        "vorname", "nachname", "name",
        // Italian
        "nome", "cognome",
        // Portuguese
        "nome", "sobrenome",
        // Japanese
        "名前", "氏名", "姓", "名",
        // Chinese
        "姓名", "名字",
    ]
}
