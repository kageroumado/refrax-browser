import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar list of all stored credentials.
///
/// Features:
/// - Searchable by domain or username
/// - Sorted alphabetically by domain
/// - Shows credential count
struct PasswordsListView: View {
    @Environment(PasswordsManager.self) private var passwordsManager

    @Binding var selectedCredential: PasswordsManager.StoredCredential?

    @State private var credentials: [PasswordsManager.StoredCredential] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingAddSheet = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingImportGuide = false
    @State private var exportResult: ExportResult?
    @State private var loadError: String?

    private var filteredCredentials: [PasswordsManager.StoredCredential] {
        guard !searchText.isEmpty else { return credentials }

        let lowercasedSearch = searchText.lowercased()
        return credentials.filter { credential in
            credential.domain.lowercased().contains(lowercasedSearch) ||
                credential.username.lowercased().contains(lowercasedSearch)
        }
    }

    var body: some View {
        credentialsList
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .navigationTitle("Passwords")
            .toolbar { toolbarContent }
            .frame(minWidth: 250)
            .onAppear { loadCredentials() }
            .sheet(isPresented: $showingAddSheet) { addPasswordSheet }
            .sheet(isPresented: $showingImportGuide) { PasswordsAppImportGuideSheet() }
            .alert(item: $exportResult) { result in
                Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog(
                "Delete All Passwords?",
                isPresented: $showingDeleteAllConfirmation,
                titleVisibility: .visible,
            ) {
                Button("Delete All", role: .destructive) { deleteAllCredentials() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(credentials.count) saved passwords. This action cannot be undone.")
            }
            .overlay { emptyStateOverlay }
    }

    // MARK: - View Components

    private var credentialsList: some View {
        List(selection: $selectedCredential) {
            ForEach(filteredCredentials) { credential in
                CredentialRow(credential: credential)
                    .tag(credential)
                    .contextMenu { credentialContextMenu(for: credential) }
            }
        }
    }

    @ViewBuilder
    private func credentialContextMenu(for credential: PasswordsManager.StoredCredential) -> some View {
        Button("Copy Username") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(credential.username, forType: .string)
        }
        Button("Copy Password") {
            if let password = try? passwordsManager.fetchPassword(for: credential) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(password, forType: .string)
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            deleteCredential(credential)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Add Password")

            Menu {
                Button("Import from Passwords App...") { showingImportGuide = true }
                Divider()
                Button("Export to Another App...") { exportViaCredentialExchange() }
                    .disabled(credentials.isEmpty)
                Button("Export to CSV...") { exportToCSV() }
                    .disabled(credentials.isEmpty)
                Divider()
                Button("Delete All Passwords...", role: .destructive) {
                    showingDeleteAllConfirmation = true
                }
                .disabled(credentials.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("More Actions")
        }
    }

    private var addPasswordSheet: some View {
        AddPasswordSheet(onSave: { credential in
            do {
                try passwordsManager.saveCredential(credential)
                loadCredentials()
            } catch {
                // Error will be handled by the sheet
            }
        })
    }

    @ViewBuilder
    private var emptyStateOverlay: some View {
        if isLoading, credentials.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading passwords...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let loadError {
            ContentUnavailableView {
                Label("Error Loading Passwords", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            }
        } else if credentials.isEmpty {
            ContentUnavailableView {
                Label("No Saved Passwords", systemImage: "key.fill")
            } description: {
                Text("Passwords you save while browsing will appear here.")
            }
        } else if filteredCredentials.isEmpty, !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    // MARK: - Actions

    private func loadCredentials() {
        isLoading = true

        do {
            credentials = try passwordsManager.allCredentialMetadata()
            loadError = nil

            if let selected = selectedCredential,
               !credentials.contains(where: { $0.id == selected.id }) {
                selectedCredential = nil
            }
        } catch {
            loadError = error.localizedDescription
            credentials = []
        }

        isLoading = false
    }

    private func deleteCredential(_ credential: PasswordsManager.StoredCredential) {
        do {
            try passwordsManager.deleteCredential(credential)
            if selectedCredential?.id == credential.id {
                selectedCredential = nil
            }
            loadCredentials()
        } catch {
            // Could show an alert here
            Logger.error("Failed to delete credential: \(error)", category: Logger.autoFill)
        }
    }

    private func deleteAllCredentials() {
        do {
            try passwordsManager.deleteAllCredentials()
            selectedCredential = nil
            credentials = []
        } catch {
            Logger.error("Failed to delete all credentials: \(error)", category: Logger.autoFill)
        }
    }

    private func exportToCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "passwords.csv"
        panel.title = "Export Passwords"
        panel.message = "Choose a location to save your passwords."

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let csvContent = generateCSV()
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            } catch {
                Logger.error("Failed to export passwords: \(error)", category: Logger.autoFill)
            }
        }
    }

    private func generateCSV() -> String {
        var csv = "url,username,password\n"
        for credential in credentials {
            let password = (try? passwordsManager.fetchPassword(for: credential)) ?? ""
            let escapedDomain = credential.domain.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedUsername = credential.username.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedPassword = password.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(escapedDomain)\",\"\(escapedUsername)\",\"\(escapedPassword)\"\n"
        }
        return csv
    }

    /// Hands every stored login to another password manager over Apple's
    /// encrypted Credential Exchange. The system presents the destination
    /// picker and Refrax fills in the credentials once a format is agreed.
    private func exportViaCredentialExchange() {
        guard let anchor = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        let allCredentials = (try? passwordsManager.allCredentials()) ?? []
        guard !allCredentials.isEmpty else { return }

        Task {
            // Construct the manager inside the task so it stays in this
            // isolation region — it is not Sendable and must not cross one.
            let manager = ASCredentialExportManager(presentationAnchor: anchor)
            do {
                let options = try await manager.requestExport()
                let data = CredentialExchangeExporter.exportData(
                    from: allCredentials,
                    formatVersion: options.formatVersion,
                )
                try await manager.exportCredentials(data)

                let count = allCredentials.count
                exportResult = ExportResult(
                    title: "Exported \(count) password\(count == 1 ? "" : "s")",
                    message: "Your passwords were handed to the app you selected.",
                )
            } catch {
                guard !isCancellation(error) else { return }
                Logger.error("Credential Exchange export failed: \(error)", category: Logger.autoFill)
                exportResult = ExportResult(
                    title: "Export failed",
                    message: "Refrax couldn't complete the export. \(error.localizedDescription)",
                )
            }
        }
    }

    /// Whether an export error is really the user dismissing the system sheet,
    /// which should pass silently rather than surface a failure alert.
    private func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.Code.canceled.rawValue {
            return true
        }
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

// MARK: - Export Result

/// A one-shot alert payload for the outcome of a Credential Exchange export.
private struct ExportResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Credential Row

private struct CredentialRow: View {
    let credential: PasswordsManager.StoredCredential

    var body: some View {
        HStack(spacing: 10) {
            // Domain icon (favicon placeholder)
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(credential.domain)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(credential.username)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Password Sheet

private struct AddPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (PasswordsManager.StoredCredential) -> Void

    @State private var domain = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?

    private var isValid: Bool {
        !domain.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Password")
                .font(.headline)

            Form {
                TextField("Website (e.g., example.com)", text: $domain)
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
            }
            .formStyle(.grouped)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    savePassword()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 350)
    }

    private func savePassword() {
        let credential = PasswordsManager.StoredCredential(
            domain: domain.lowercased(),
            username: username,
            password: password,
        )
        onSave(credential)
        dismiss()
    }
}
