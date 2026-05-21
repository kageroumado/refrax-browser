import SwiftUI

/// Address bar dropdown prompting user to save or update credentials.
///
/// This view appears as a popover from the address bar key icon when
/// `AutoFillState.pendingSaveRequest` is set after form submission.
///
/// ## Actions
///
/// - **Save/Update**: Stores the credential via `PasswordsManager`
/// - **Not Now**: Dismisses the prompt (will ask again on next login)
/// - **Never**: Stores preference in `SiteSettings.neverSavePasswords`
///
/// ## Popover Behavior
///
/// The prompt uses NSPopover with `.applicationDefined` behavior to prevent
/// auto-dismiss on outside clicks. Users must explicitly click a button to close.
struct SavePasswordPromptView: View {
    let request: CredentialSaveRequest

    @Environment(AutoFillState.self) private var autoFillState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            credentialSection
            actionButtons
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(request.isUpdate ? "Update password for" : "Save password for")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    // MARK: - Credential Display

    private var credentialSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.username)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(request.domain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if request.isUpdate {
                // Update flow: Update / Keep Existing
                Button("Keep Existing") {
                    dismissPrompt()
                }
                .buttonStyle(.bordered)

                Button("Update") {
                    updateCredential()
                }
                .buttonStyle(.borderedProminent)
            } else {
                // New credential flow: Save / Not Now / Never
                Button("Never") {
                    neverSaveForDomain()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Not Now") {
                    dismissPrompt()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    saveCredential()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
    }

    // MARK: - Actions

    private func saveCredential() {
        autoFillState.onSaveCredential?(request)
        dismissPrompt()
    }

    private func updateCredential() {
        autoFillState.onUpdateCredential?(request)
        dismissPrompt()
    }

    private func neverSaveForDomain() {
        autoFillState.onNeverSaveForDomain?(request.domain)
        dismissPrompt()
    }

    private func dismissPrompt() {
        // Setting pendingSaveRequest to nil triggers the AddressBarSavePasswordButton
        // onChange handler to close the NSPopover
        autoFillState.dismissSavePrompt()
    }
}
