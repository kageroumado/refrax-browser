import AppKit
import Foundation
import WebKit

// Autofill manager using WebKit's `_WKInputDelegate` API.
//
// This manager provides Safari-style autofill functionality by hooking directly into
// WebKit's form input events, eliminating the need for JavaScript injection.
//
// ## Overview
//
// `AutoFillManager` uses WebKit's private APIs to:
// - Detect when users focus on form fields (especially password fields)
// - Intercept form submissions to offer credential saving
// - Fill credentials without JavaScript bridge overhead
//
// ## Hybrid Credential Lookup
//
// The manager implements a hybrid approach for credential retrieval:
// 1. First checks the local Keychain via `PasswordsManager`
// 2. Offers the option to use system Passwords app via `SystemPasswordsManager`
// 3. If no local credentials exist, the "Use Passwords App" option is still available
//
// ## Usage
//
// ```swift
// let autoFillManager = AutoFillManager(
//     passwordsManager: passwordsManager,
//     autoFillState: autoFillState
// )
// autoFillManager.attach(to: wkWebView, url: url)
// ```

final class AutoFillManager: NSObject, _WKInputDelegate {
    // MARK: - Properties

    private let settings: BrowserSettings
    private let passwordsManager: PasswordsManager
    private let siteSettingsManager: SiteSettingsManager
    private let autoFillState: AutoFillState

    /// Reference to the attached WKWebView.
    private weak var webView: WKWebView?

    /// Current URL being viewed.
    private var currentURL: URL?

    /// The current form input session, if active.
    private var currentInputSession: AnyObject?

    /// The field ID for the current password field (for system passwords callback).
    private var currentFieldId: String?

    /// The username field ID associated with the current password field.
    private var currentUsernameFieldId: String?

    // MARK: - Initialization

    init(
        settings: BrowserSettings,
        passwordsManager: PasswordsManager,
        siteSettingsManager: SiteSettingsManager,
        autoFillState: AutoFillState,
    ) {
        self.settings = settings
        self.passwordsManager = passwordsManager
        self.siteSettingsManager = siteSettingsManager
        self.autoFillState = autoFillState
        super.init()

        autoFillState.onCredentialSelected = { [weak self] credential in
            self?.fillCredential(credential)
        }

        autoFillState.onSystemPasswordsRequested = { [weak self] in
            self?.triggerSystemPasswordsPicker()
        }

        autoFillState.onSystemCreditCardsRequested = { [weak self] in
            self?.triggerSystemCreditCardsPicker()
        }

        autoFillState.onSystemContactsRequested = { [weak self] in
            self?.triggerSystemContactsPicker()
        }

        autoFillState.onSuggestNewPassword = { [weak self] fieldId, usernameFieldId in
            self?.generateAndFillPassword(fieldId: fieldId, usernameFieldId: usernameFieldId)
        }

        autoFillState.onFillGeneratedPassword = { [weak self] password, fieldId, usernameFieldId in
            self?.fillGeneratedPassword(password, fieldId: fieldId, usernameFieldId: usernameFieldId)
        }

        autoFillState.onSaveCredential = { [weak self] request in
            self?.saveNewCredential(request)
        }

        autoFillState.onUpdateCredential = { [weak self] request in
            self?.updateExistingCredential(request)
        }

        autoFillState.onNeverSaveForDomain = { [weak self] domain in
            self?.setNeverSaveForDomain(domain)
        }

        // Hide overlay when focus moves away from autofillable field
        WKWebView.onAutoFillFieldFocusLost = { [weak self] in
            self?.autoFillState.hide()
        }
    }

    // MARK: - Attachment

    /// Attaches the autofill manager to a WKWebView.
    ///
    /// - Parameters:
    ///   - webView: The WKWebView to attach to.
    ///   - url: The initial URL being viewed.
    func attach(to webView: WKWebView, url: URL) {
        self.webView = webView
        currentURL = url

        webView._setInputDelegate(self)
    }

    /// Detaches from the current WKWebView.
    func detach() {
        guard let webView else { return }

        webView._setInputDelegate(nil)

        self.webView = nil
        currentURL = nil
        currentInputSession = nil
    }

    /// Updates the current URL (call when navigation occurs).
    func updateURL(_ url: URL) {
        currentURL = url
        autoFillState.hide()
    }

    // MARK: - Credential Filling

    /// Fills a credential into the form fields.
    ///
    /// The JavaScript function finds the appropriate fields automatically:
    /// - Password: Currently focused element or first password input in form
    /// - Username: Text/email input with username-related attributes
    private func fillCredential(_ credential: PasswordsManager.StoredCredential) {
        guard let webView else { return }
        let host = currentURL?.host ?? "unknown host"

        let js = JavaScriptSnippets.fillCredentials(
            password: credential.password,
            username: credential.username,
        )

        Task {
            do {
                if let result = try await webView.evaluateJavaScript(js) as? [String: Bool] {
                    let filledUser = result["filledUsername"] ?? false
                    let filledPass = result["filledPassword"] ?? false
                    Logger.debug("Filled credentials for \(host): username=\(filledUser), password=\(filledPass)", category: Logger.autoFill)
                }
            } catch {
                Logger.error("Failed to fill credentials: \(error)", category: Logger.autoFill)
            }
        }

        autoFillState.hide()
    }

    /// Triggers the system Passwords picker.
    ///
    /// Used for both credential fields and credit card fields (cards are stored in Passwords app).
    private func triggerSystemPasswordsPicker() {
        autoFillState.hide()

        var domains: [String] = []
        guard let url = currentURL, url.allowsAutoFill else {
            Logger.debug("Ignoring system Passwords picker on non-HTTPS site", category: Logger.autoFill)
            return
        }

        if let host = url.host?.lowercased() {
            domains.append(host)
            if let registrable = url.registrableDomain?.lowercased(), registrable != host {
                domains.append(registrable)
            }
        }

        SystemAutoFillManager.shared.showPasswordPicker(forDomains: domains)
    }

    /// Triggers the system Credit Cards picker.
    private func triggerSystemCreditCardsPicker() {
        autoFillState.hide()
        guard let url = currentURL, url.allowsAutoFill else {
            Logger.debug("Ignoring system Credit Cards picker on non-HTTPS site", category: Logger.autoFill)
            return
        }
        SystemAutoFillManager.shared.showCreditCardPicker()
    }

    /// Triggers the system Contacts picker.
    private func triggerSystemContactsPicker() {
        autoFillState.hide()
        guard let url = currentURL, url.allowsAutoFill else {
            Logger.debug("Ignoring system Contacts picker on non-HTTPS site", category: Logger.autoFill)
            return
        }
        SystemAutoFillManager.shared.showContactsPicker()
    }

    /// Generates a new strong password and fills all password fields in the form.
    ///
    /// Fetches website-specific password rules from Apple's quirks database
    /// before generating a password that meets the site's requirements.
    /// Fills all password fields in the form (both password and confirm password).
    private func generateAndFillPassword(fieldId _: String, usernameFieldId _: String?) {
        guard let url = currentURL, url.allowsAutoFill, let host = url.host, let webView else {
            Logger.debug("Ignoring password generation on non-HTTPS site", category: Logger.autoFill)
            return
        }
        let domain = url.registrableDomain ?? host

        Task {
            // Fetch website-specific password rules from quirks database
            let rules = await PasswordQuirksManager.shared.rules(for: host)

            let password = GeneratedPasswordStore.shared.generatePassword(for: domain, rules: rules)

            // Fill all password fields in the form (password + confirm password)
            let fillAllJS = JavaScriptSnippets.fillAllPasswordFields(password)
            do {
                if let count = try await webView.evaluateJavaScript(fillAllJS) as? Int, count > 0 {
                    Logger.info("Generated and filled \(count) password field(s) for \(domain)", category: Logger.autoFill)
                }
            } catch {
                Logger.error("Failed to fill password fields: \(error)", category: Logger.autoFill)
            }

            autoFillState.hide()
        }
    }

    /// Fills a previously generated password into all password fields.
    private func fillGeneratedPassword(_ password: String, fieldId _: String, usernameFieldId _: String?) {
        guard let url = currentURL, url.allowsAutoFill, let webView else {
            Logger.debug("Ignoring generated password fill on non-HTTPS site", category: Logger.autoFill)
            return
        }

        // Fill all password fields in the form (password + confirm password)
        let fillAllJS = JavaScriptSnippets.fillAllPasswordFields(password)
        Task {
            do {
                if let count = try await webView.evaluateJavaScript(fillAllJS) as? Int, count > 0 {
                    Logger.debug("Filled \(count) password field(s) with generated password", category: Logger.autoFill)
                }
            } catch {
                Logger.error("Failed to fill password fields: \(error)", category: Logger.autoFill)
            }
        }

        autoFillState.hide()
    }

    /// Fills only the password field (no username).
    ///
    /// First attempts to fill the focused element directly (more reliable),
    /// then falls back to ID-based fill if that fails.
    private func fillPasswordOnly(_ password: String, fieldId: String) {
        guard let webView else { return }

        Task {
            // First try filling the focused element directly (more reliable)
            let focusedFillJS = JavaScriptSnippets.fillFocusedPassword(password)

            do {
                if let success = try await webView.evaluateJavaScript(focusedFillJS) as? Bool, success {
                    Logger.debug("Filled password using focused element", category: Logger.autoFill)
                    return
                }
            } catch {
                // Continue to fallback
            }

            // Fallback to ID-based fill
            let js = JavaScriptSnippets.fillPassword(password, fieldId: fieldId)
            do {
                _ = try await webView.evaluateJavaScript(js)
                Logger.debug("Filled password using field ID fallback", category: Logger.autoFill)
            } catch {
                Logger.error("Failed to fill password: \(error)", category: Logger.autoFill)
            }
        }
    }

    // MARK: - Form Submission Handling

    /// Handles credential submission detected by JavaScript.
    ///
    /// This is called by `ContentScriptManager` when the credential detection
    /// script detects a login form submission (traditional or AJAX-based).
    /// This supplements the `_WKInputDelegate.willSubmitFormValues` which
    /// only fires for traditional HTML form submissions.
    ///
    /// - Parameters:
    ///   - username: The detected username/email.
    ///   - password: The detected password.
    ///   - url: The URL where the form was submitted.
    func handleCredentialSubmissionFromJS(username: String, password: String, url: URL) {
        // Credential saving only happens in builtIn mode
        guard settings.autoFillMode == .builtIn else { return }

        // Reuse the existing form submission logic
        let values: [String: Any] = [
            "username": username,
            "password": password,
        ]
        currentURL = url
        handleFormSubmission(values: values) {
            // No-op completion - JS submission doesn't need to wait
        }
    }

    /// Called when a form is about to be submitted.
    ///
    /// This is the opportunity to offer to save new credentials.
    private func handleFormSubmission(values: [String: Any], completion: @escaping () -> Void) {
        guard let url = currentURL, url.allowsAutoFill else {
            completion()
            return
        }

        let domain = (url.registrableDomain ?? url.host ?? "").lowercased()

        // Check if user has opted out of saving passwords for this domain
        if let settings = siteSettingsManager.settings(for: domain),
           settings.neverSavePasswords {
            Logger.debug("Skipping password save prompt - user opted out for \(domain)", category: Logger.autoFill)
            completion()
            return
        }

        var username: String?
        var password: String?

        for (key, value) in values {
            guard let stringValue = value as? String, !stringValue.isEmpty else { continue }

            let keyLower = key.lowercased()

            if password == nil, keyLower.contains("password") || keyLower.contains("passwd") {
                password = stringValue
            } else if username == nil, keyLower.contains("user") || keyLower.contains("email") || keyLower.contains("login") {
                username = stringValue
            }
        }

        // Security requirement: need both username and password
        guard let username, let password else {
            completion()
            return
        }

        // Check for existing credentials
        let existingCredentials = passwordsManager.findCredentials(for: url)

        // Check if this exact credential already exists
        if existingCredentials.contains(where: { $0.username == username && $0.password == password }) {
            // Credential already saved - no action needed
            completion()
            return
        }

        // Check if this is an update (same username, different password)
        if let existingCredential = existingCredentials.first(where: { $0.username == username }) {
            // Password changed for existing username - offer to update
            let request = CredentialSaveRequest(
                domain: domain,
                username: username,
                password: password,
                isUpdate: true,
                existingCredential: existingCredential,
            )
            autoFillState.showSavePrompt(request)
            Logger.info("Detected password update for \(username) on \(domain)", category: Logger.autoFill)
        } else {
            // New credential - offer to save
            let request = CredentialSaveRequest(
                domain: domain,
                username: username,
                password: password,
                isUpdate: false,
                existingCredential: nil,
            )
            autoFillState.showSavePrompt(request)
            Logger.info("Detected new credential for \(username) on \(domain)", category: Logger.autoFill)
        }

        completion()
    }

    // MARK: - Credential Save Actions

    /// Saves a new credential to the Keychain.
    private func saveNewCredential(_ request: CredentialSaveRequest) {
        let credential = PasswordsManager.StoredCredential(
            domain: request.domain,
            username: request.username,
            password: request.password,
            dateCreated: Date(),
            dateModified: Date(),
        )

        do {
            try passwordsManager.saveCredential(credential)
            Logger.info("Saved new credential for \(request.username) on \(request.domain)", category: Logger.autoFill)

            // Security: clear generated password from RAM after successful save
            GeneratedPasswordStore.shared.clearPassword(for: request.domain)
        } catch {
            Logger.error("Failed to save credential: \(error)", category: Logger.autoFill)
        }
    }

    /// Updates an existing credential in the Keychain.
    private func updateExistingCredential(_ request: CredentialSaveRequest) {
        let credential = PasswordsManager.StoredCredential(
            domain: request.domain,
            username: request.username,
            password: request.password,
            dateCreated: request.existingCredential?.dateCreated,
            dateModified: Date(),
        )

        do {
            try passwordsManager.updateCredential(credential)
            Logger.info("Updated credential for \(request.username) on \(request.domain)", category: Logger.autoFill)

            // Security: clear generated password from RAM after successful save
            GeneratedPasswordStore.shared.clearPassword(for: request.domain)
        } catch {
            Logger.error("Failed to update credential: \(error)", category: Logger.autoFill)
        }
    }

    /// Sets the "never save passwords" preference for a domain.
    private func setNeverSaveForDomain(_ domain: String) {
        let settings = siteSettingsManager.settingsOrCreate(for: domain)
        settings.neverSavePasswords = true
        siteSettingsManager.save(settings)
        Logger.info("Set never-save-passwords for \(domain)", category: Logger.autoFill)
    }
}

// MARK: - _WKInputDelegate Conformance

extension AutoFillManager {
    /// Called when an input session starts (user focuses a form field).
    @objc(_webView:didStartInputSession:)
    func _webView(_ webView: WKWebView, didStartInputSession inputSession: any _WKFormInputSession) {
        // Skip all autofill when disabled - don't interfere with extensions
        guard settings.autoFillMode != .disabled else { return }

        currentInputSession = inputSession

        guard let focusedElementInfo = inputSession.focusedElementInfo else {
            Logger.debug("Could not get focused element info from input session", category: Logger.autoFill)
            return
        }

        let inputType = focusedElementInfo.type
        let label = focusedElementInfo.label
        let placeholder = focusedElementInfo.placeholder

        // Extract additional properties if available from our custom implementation
        let elementImpl = focusedElementInfo as? FocusedElementInfoImpl
        let name = elementImpl?.name
        let autocomplete = elementImpl?.autocomplete

        let fieldType = AutoFillFieldDetector.detectFieldType(
            label: label,
            placeholder: placeholder,
            name: name,
            autocomplete: autocomplete,
            inputType: inputType,
        )

        switch fieldType {
        case .credential:
            handleCredentialFieldFocus(webView: webView, inputType: inputType)
        case .creditCard:
            handleCreditCardFieldFocus(webView: webView)
        case .contact:
            handleContactFieldFocus(webView: webView)
        case .oneTimeCode:
            handleOneTimeCodeFieldFocus(webView: webView)
        case .none:
            // For unknown fields, don't show autofill
            Logger.debug("Ignoring non-autofillable field", category: Logger.autoFill)
        }
    }

    /// Handles focus on a credential field (username/email/password).
    private func handleCredentialFieldFocus(webView: WKWebView, inputType: WKInputType) {
        guard let url = currentURL, url.allowsAutoFill else {
            Logger.debug("Ignoring credential field focus on non-HTTPS site", category: Logger.autoFill)
            return
        }

        let mode = settings.autoFillMode

        // In systemOnly mode, don't lookup credentials or generated passwords
        let credentials: [PasswordsManager.StoredCredential] = mode == .builtIn
            ? passwordsManager.findCredentials(for: url)
            : []

        let fieldId = generateFieldId()
        currentFieldId = fieldId

        let isPasswordField = inputType == .password

        // For password fields, try to find the associated username field
        // For username/email fields, this will be nil
        currentUsernameFieldId = isPasswordField ? nil : fieldId

        Task {
            guard let rect = await getFieldRect(in: webView) else { return }

            // Get full form context including field value and confirm password detection
            let formContext = await getFormContext(in: webView)

            // Don't show overlay if field already has content
            if formContext.fieldHasValue {
                Logger.debug("Ignoring field focus - field already has content", category: Logger.autoFill)
                return
            }

            // Check for recently generated password for this domain (builtIn mode only)
            let recentPassword: String? = {
                guard mode == .builtIn, isPasswordField else { return nil }
                guard let domain = url.registrableDomain ?? url.host else { return nil }
                return GeneratedPasswordStore.shared.recentlyGeneratedPassword(for: domain)
            }()

            let context = AutoFillContext(
                autoFillMode: mode,
                fieldType: .credential,
                isPasswordField: isPasswordField,
                isLoginForm: formContext.isLoginForm,
                isConfirmPasswordField: formContext.isConfirmPasswordField,
                credentials: credentials,
                recentlyGeneratedPassword: recentPassword,
                rect: rect,
                fieldId: fieldId,
                usernameFieldId: isPasswordField ? currentUsernameFieldId : nil,
                url: url,
                requireAuthForAutoFill: settings.requireAuthForAutoFill,
            )

            // Show the overlay via state
            autoFillState.show(context: context)

            let fieldTypeDesc = isPasswordField ? "password" : "username/email"
            let formTypeDesc = formContext.isLoginForm ? "login" : "registration"
            let confirmDesc = formContext.isConfirmPasswordField ? " (confirm)" : ""
            if credentials.isEmpty {
                Logger.debug("Showing auto-fill overlay for \(fieldTypeDesc)\(confirmDesc) field (\(formTypeDesc) form) with system Passwords option only", category: Logger.autoFill)
            } else {
                Logger.debug("Showing auto-fill overlay for \(fieldTypeDesc)\(confirmDesc) field (\(formTypeDesc) form) with \(credentials.count) credential(s)", category: Logger.autoFill)
            }
        }
    }

    /// Handles focus on a credit card field.
    private func handleCreditCardFieldFocus(webView: WKWebView) {
        guard let url = currentURL, url.allowsAutoFill else {
            Logger.debug("Ignoring credit card field focus on non-HTTPS site", category: Logger.autoFill)
            return
        }

        let fieldId = generateFieldId()
        currentFieldId = fieldId

        Task {
            guard let rect = await getFieldRect(in: webView) else { return }

            // Get form context to check if field has content
            let formContext = await getFormContext(in: webView)
            if formContext.fieldHasValue {
                Logger.debug("Ignoring credit card field focus - field already has content", category: Logger.autoFill)
                return
            }

            let context = AutoFillContext(
                autoFillMode: settings.autoFillMode,
                fieldType: .creditCard,
                credentials: [],
                rect: rect,
                fieldId: fieldId,
                usernameFieldId: nil,
                url: url,
            )

            // Show the overlay via state
            autoFillState.show(context: context)
            Logger.debug("Showing auto-fill overlay for credit card field", category: Logger.autoFill)
        }
    }

    /// Handles focus on a contact/address field.
    private func handleContactFieldFocus(webView: WKWebView) {
        guard let url = currentURL, url.allowsAutoFill else {
            Logger.debug("Ignoring contact field focus on non-HTTPS site", category: Logger.autoFill)
            return
        }

        let fieldId = generateFieldId()
        currentFieldId = fieldId

        Task {
            guard let rect = await getFieldRect(in: webView) else { return }

            // Get form context to check if field has content
            let formContext = await getFormContext(in: webView)
            if formContext.fieldHasValue {
                Logger.debug("Ignoring contact field focus - field already has content", category: Logger.autoFill)
                return
            }

            let context = AutoFillContext(
                autoFillMode: settings.autoFillMode,
                fieldType: .contact,
                credentials: [],
                rect: rect,
                fieldId: fieldId,
                usernameFieldId: nil,
                url: url,
            )

            // Show the overlay via state
            autoFillState.show(context: context)
            Logger.debug("Showing auto-fill overlay for contact field", category: Logger.autoFill)
        }
    }

    /// Handles focus on a one-time code / 2FA field.
    private func handleOneTimeCodeFieldFocus(webView: WKWebView) {
        guard let url = currentURL, url.allowsAutoFill else {
            Logger.debug("Ignoring OTP field focus on non-HTTPS site", category: Logger.autoFill)
            return
        }

        let fieldId = generateFieldId()
        currentFieldId = fieldId

        Task {
            guard let rect = await getFieldRect(in: webView) else { return }

            let formContext = await getFormContext(in: webView)
            if formContext.fieldHasValue {
                Logger.debug("Ignoring OTP field focus - field already has content", category: Logger.autoFill)
                return
            }

            let context = AutoFillContext(
                autoFillMode: settings.autoFillMode,
                fieldType: .oneTimeCode,
                rect: rect,
                fieldId: fieldId,
                usernameFieldId: nil,
                url: url,
            )

            autoFillState.show(context: context)
            Logger.debug("Showing auto-fill overlay for OTP field", category: Logger.autoFill)
        }
    }

    /// Called when a form is about to be submitted.
    @objc(_webView:willSubmitFormValues:userObject:submissionHandler:)
    func _webView(
        _: WKWebView,
        willSubmitFormValues values: [AnyHashable: Any],
        userObject _: (any NSSecureCoding & NSObjectProtocol)?,
        submissionHandler: @escaping () -> Void,
    ) {
        var stringKeyedValues: [String: Any] = [:]
        for (key, value) in values {
            if let stringKey = key as? String {
                stringKeyedValues[stringKey] = value
            }
        }
        handleFormSubmission(values: stringKeyedValues, completion: submissionHandler)
    }

    // MARK: - Helper Methods

    /// Generates a unique field ID for the current focused field.
    private func generateFieldId() -> String {
        "autofill_\(UUID().uuidString.prefix(8))"
    }

    /// Gets the rect of the currently focused field using JavaScript.
    private func getFieldRect(in webView: WKWebView) async -> CGRect? {
        do {
            let result = try await webView.evaluateJavaScript(JavaScriptSnippets.activeElementRect)
            guard let dict = result as? [String: Any],
                  let x = dict["x"] as? CGFloat,
                  let y = dict["y"] as? CGFloat,
                  let width = dict["width"] as? CGFloat,
                  let height = dict["height"] as? CGFloat
            else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        } catch {
            return nil
        }
    }

    /// Parsed form context from JavaScript.
    private struct FormContext {
        let isLoginForm: Bool
        let isConfirmPasswordField: Bool
        let fieldHasValue: Bool
        let passwordFieldCount: Int
    }

    /// Gets form context information from the focused field.
    ///
    /// Returns parsed form context with login/registration detection,
    /// confirm password field detection, and field value check.
    private func getFormContext(in webView: WKWebView) async -> FormContext {
        do {
            let result = try await webView.evaluateJavaScript(JavaScriptSnippets.formContext)
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let context = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                // Default values when context unavailable
                return FormContext(isLoginForm: true, isConfirmPasswordField: false, fieldHasValue: false, passwordFieldCount: 1)
            }

            let fieldHasValue = context["fieldHasValue"] as? Bool ?? false
            let isConfirmPasswordField = context["isConfirmPasswordField"] as? Bool ?? false
            let passwordFieldCount = context["passwordFieldCount"] as? Int ?? 1

            // Determine if login form
            var isLoginForm = true

            // Priority 1: autocomplete="current-password" indicates login
            if context["hasCurrentPasswordHint"] as? Bool == true {
                isLoginForm = true
            }
            // Priority 2: autocomplete="new-password" indicates registration
            else if context["hasNewPasswordHint"] as? Bool == true {
                isLoginForm = false
            }
            // Priority 3: Multiple password fields suggest registration (with confirmation)
            else if passwordFieldCount >= 2 {
                isLoginForm = false
            }
            // Priority 4: Check form text for login keywords
            else if let formText = context["formText"] as? String,
                    AutoFillFieldDetector.isLoginForm(formText: formText) {
                isLoginForm = true
            }

            return FormContext(
                isLoginForm: isLoginForm,
                isConfirmPasswordField: isConfirmPasswordField,
                fieldHasValue: fieldHasValue,
                passwordFieldCount: passwordFieldCount,
            )
        } catch {
            // Default values on error
            return FormContext(isLoginForm: true, isConfirmPasswordField: false, fieldHasValue: false, passwordFieldCount: 1)
        }
    }
}
