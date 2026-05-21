import SwiftUI

/// Detail view for a single credential.
///
/// Shows domain, username, and masked password with reveal toggle.
/// Supports editing and deletion.
struct PasswordDetailView: View {
    @Environment(PasswordsManager.self) private var passwordsManager
    @Environment(\.dismiss) private var dismiss

    let credential: PasswordsManager.StoredCredential

    @State private var isEditing = false
    @State private var showPassword = false
    @State private var editedUsername: String
    @State private var editedPassword = ""
    @State private var fetchedPassword: String?
    @State private var showDeleteConfirmation = false

    private var password: String {
        fetchedPassword ?? ""
    }

    init(credential: PasswordsManager.StoredCredential) {
        self.credential = credential
        self._editedUsername = State(initialValue: credential.username)
    }

    var body: some View {
        Form {
            // Domain section
            Section {
                LabeledContent("Website") {
                    Text(credential.domain)
                        .textSelection(.enabled)
                }
            }

            // Credentials section
            Section {
                if isEditing {
                    LabeledContent("Username") {
                        TextField("Username", text: $editedUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }

                    LabeledContent("Password") {
                        HStack {
                            if showPassword {
                                TextField("Password", text: $editedPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 250)
                            } else {
                                SecureField("Password", text: $editedPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 250)
                            }
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    LabeledContent("Username") {
                        HStack {
                            Text(credential.username)
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(credential.username, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Username")
                        }
                    }

                    LabeledContent("Password") {
                        HStack {
                            if fetchedPassword == nil {
                                ProgressView()
                                    .controlSize(.small)
                            } else if showPassword {
                                Text(password)
                                    .textSelection(.enabled)
                            } else {
                                Text(String(repeating: "•", count: min(password.count, 20)))
                            }
                            Spacer()
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(showPassword ? "Hide Password" : "Show Password")
                            .disabled(fetchedPassword == nil)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(password, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Password")
                            .disabled(fetchedPassword == nil)
                        }
                    }
                }
            }

            // Metadata section
            if !isEditing {
                Section {
                    if let dateCreated = credential.dateCreated {
                        LabeledContent("Created") {
                            Text(dateCreated, style: .date)
                        }
                    }
                    if let dateModified = credential.dateModified {
                        LabeledContent("Modified") {
                            Text(dateModified, style: .date)
                        }
                    }
                }
            }

            // Delete section
            if !isEditing {
                Section {
                    Button("Delete Password", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(credential.domain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button("Done") {
                        saveChanges()
                    }
                } else {
                    Button("Edit") {
                        startEditing()
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelEditing()
                    }
                }
            }
        }
        .onAppear { loadPassword() }
        .confirmationDialog(
            "Delete Password?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                deleteCredential()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the password for \(credential.domain).")
        }
    }

    // MARK: - Actions

    private func loadPassword() {
        if let pw = try? passwordsManager.fetchPassword(for: credential) {
            fetchedPassword = pw
        }
    }

    private func startEditing() {
        editedUsername = credential.username
        editedPassword = password
        isEditing = true
    }

    private func cancelEditing() {
        editedUsername = credential.username
        editedPassword = password
        isEditing = false
        showPassword = false
    }

    private func saveChanges() {
        let updated = PasswordsManager.StoredCredential(
            id: credential.id,
            domain: credential.domain,
            username: editedUsername,
            password: editedPassword,
            dateCreated: credential.dateCreated,
            dateModified: Date(),
        )

        do {
            try passwordsManager.updateCredential(updated)
            isEditing = false
            showPassword = false
        } catch {
            Logger.error("Failed to update credential: \(error)", category: Logger.autoFill)
        }
    }

    private func deleteCredential() {
        do {
            try passwordsManager.deleteCredential(credential)
        } catch {
            Logger.error("Failed to delete credential: \(error)", category: Logger.autoFill)
        }
    }
}
