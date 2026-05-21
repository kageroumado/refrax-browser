import Foundation
import SwiftUI

/// Observable state for auto-fill UI.
///
/// This state is observed by views to display the auto-fill popover when
/// an autofillable field gains focus.
@Observable
final class AutoFillState {
    /// Current auto-fill context (when popover should be shown).
    private(set) var context: AutoFillContext?

    /// Whether the popover is currently visible.
    var isPopoverVisible: Bool {
        context != nil
    }

    /// Whether a system autofill request is in progress.
    private(set) var isRequestingSystemAutoFill = false

    /// Pending credential save request (when user submits a login form).
    ///
    /// When set, the address bar shows a key icon that opens the save password prompt.
    /// This is set by `AutoFillManager` when a form submission is detected with credentials.
    private(set) var pendingSaveRequest: CredentialSaveRequest?

    /// Whether there's a pending save request to show.
    var hasPendingSaveRequest: Bool {
        pendingSaveRequest != nil
    }

    /// Shows the save password prompt for the given credentials.
    func showSavePrompt(_ request: CredentialSaveRequest) {
        pendingSaveRequest = request
    }

    /// Dismisses the save password prompt.
    func dismissSavePrompt() {
        pendingSaveRequest = nil
    }

    /// Shows the auto-fill popover with the given context.
    ///
    /// Deduplicates updates - if the new context matches the current one,
    /// no observation update is triggered.
    func show(context: AutoFillContext) {
        guard self.context != context else { return }
        self.context = context
    }

    /// Hides the auto-fill popover.
    func hide() {
        context = nil
        isRequestingSystemAutoFill = false
    }

    /// Sets the system autofill request state.
    func setRequestingSystemAutoFill(_ requesting: Bool) {
        isRequestingSystemAutoFill = requesting
    }

    // MARK: - Callbacks

    /// Callback to execute when a credential is selected from the list.
    @ObservationIgnored var onCredentialSelected: ((PasswordsManager.StoredCredential) -> Void)?

    /// Callback to execute when the user requests system Passwords app (for credentials).
    @ObservationIgnored var onSystemPasswordsRequested: (() -> Void)?

    /// Callback to execute when the user requests system Credit Cards picker.
    @ObservationIgnored var onSystemCreditCardsRequested: (() -> Void)?

    /// Callback to execute when the user requests system Contacts app.
    @ObservationIgnored var onSystemContactsRequested: (() -> Void)?

    /// Callback to execute when the user wants to generate a new password.
    ///
    /// Parameters are: fieldId, usernameFieldId
    @ObservationIgnored var onSuggestNewPassword: ((String, String?) -> Void)?

    /// Callback to execute when the user wants to fill a recently generated password.
    ///
    /// Parameters are: password, fieldId, usernameFieldId
    @ObservationIgnored var onFillGeneratedPassword: ((String, String, String?) -> Void)?

    /// Callback when user saves a credential from the save prompt.
    @ObservationIgnored var onSaveCredential: ((CredentialSaveRequest) -> Void)?

    /// Callback when user updates an existing credential from the save prompt.
    @ObservationIgnored var onUpdateCredential: ((CredentialSaveRequest) -> Void)?

    /// Callback when user chooses "Never" for a domain.
    @ObservationIgnored var onNeverSaveForDomain: ((String) -> Void)?
}

// MARK: - Credential Save Request

/// A pending request to save or update credentials after form submission.
///
/// This is created when `AutoFillManager` detects a form submission containing
/// username/password fields. The request is shown to the user as a prompt
/// in the address bar.
struct CredentialSaveRequest: Identifiable, Equatable {
    let id: UUID = .init()

    /// The domain the credentials are for (e.g., "github.com").
    let domain: String

    /// The username being saved.
    let username: String

    /// The password being saved.
    let password: String

    /// Whether this is an update to an existing credential (vs. new credential).
    let isUpdate: Bool

    /// The existing credential being updated, if any.
    let existingCredential: PasswordsManager.StoredCredential?

    init(
        domain: String,
        username: String,
        password: String,
        isUpdate: Bool = false,
        existingCredential: PasswordsManager.StoredCredential? = nil,
    ) {
        self.domain = domain
        self.username = username
        self.password = password
        self.isUpdate = isUpdate
        self.existingCredential = existingCredential
    }
}
