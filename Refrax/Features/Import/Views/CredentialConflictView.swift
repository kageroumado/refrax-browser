import SwiftUI

/// View for resolving credential conflicts during password import.
///
/// When importing passwords, if a credential with the same domain and username
/// already exists with a different password, the user must choose how to resolve
/// the conflict before continuing.
struct CredentialConflictView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            headerSection
            conflictList
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
    }
}

// MARK: - Header

private extension CredentialConflictView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text("\(viewModel.pendingConflicts.count) Conflict\(viewModel.pendingConflicts.count == 1 ? "" : "s") Found")
                    .font(.headline)
            }

            Text("The following credentials already exist with different passwords. Choose how to handle each conflict.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
    }
}

// MARK: - Conflict List

private extension CredentialConflictView {
    var conflictList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.pendingConflicts.indices, id: \.self) { index in
                    ConflictRow(
                        conflict: viewModel.pendingConflicts[index],
                        resolution: Binding(
                            get: { viewModel.pendingConflicts[index].resolution },
                            set: { viewModel.pendingConflicts[index].resolution = $0 },
                        ),
                    )
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.bottom, Constants.bottomPadding)
        }
    }
}

// MARK: - Conflict Row

private struct ConflictRow: View {
    let conflict: PasswordsManager.CredentialConflict
    @Binding var resolution: PasswordsManager.ConflictResolution?

    @State private var showExistingPassword = false
    @State private var showIncomingPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            credentialHeader
            Divider()
            comparisonSection
            Divider()
            resolutionPicker
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 1),
        )
    }

    private var backgroundColor: Color {
        resolution == nil ? Color.orange.opacity(0.05) : Color.green.opacity(0.05)
    }

    private var borderColor: Color {
        resolution == nil ? Color.orange.opacity(0.3) : Color.green.opacity(0.3)
    }

    private var credentialHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.domain)
                    .font(.headline)

                Text(conflict.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if resolution != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var comparisonSection: some View {
        HStack(spacing: 16) {
            passwordColumn(
                title: "Existing",
                password: conflict.existing.password,
                date: conflict.existing.dateModified,
                showPassword: $showExistingPassword,
            )

            Divider()
                .frame(height: 60)

            passwordColumn(
                title: "Importing",
                password: conflict.incoming.password,
                date: conflict.incoming.dateLastUsed,
                showPassword: $showIncomingPassword,
            )
        }
    }

    private func passwordColumn(
        title: String,
        password: String,
        date: Date?,
        showPassword: Binding<Bool>,
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack {
                if showPassword.wrappedValue {
                    Text(password)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text(String(repeating: "•", count: min(12, password.count)))
                        .font(.system(.caption, design: .monospaced))
                }

                Button {
                    showPassword.wrappedValue.toggle()
                } label: {
                    Image(systemName: showPassword.wrappedValue ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let date {
                Text("Modified: \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolutionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resolution:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                resolutionButton(
                    title: "Keep Existing",
                    icon: "checkmark.shield",
                    resolution: .keepExisting,
                )

                resolutionButton(
                    title: "Use Imported",
                    icon: "arrow.down.circle",
                    resolution: .useImported,
                )

                resolutionButton(
                    title: "Keep Both",
                    icon: "rectangle.stack",
                    resolution: .keepBoth,
                )
            }
        }
    }

    private func resolutionButton(
        title: String,
        icon: String,
        resolution resolutionOption: PasswordsManager.ConflictResolution,
    ) -> some View {
        Button {
            resolution = resolutionOption
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)

                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(resolution == resolutionOption ? Color.appAccentColor.opacity(0.15) : Color.clear),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        resolution == resolutionOption ? Color.appAccentColor : Color.secondary.opacity(0.3),
                        lineWidth: 1,
                    ),
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(resolution == resolutionOption ? Color.appAccentColor : .secondary)
    }
}
