import SwiftUI
import UniformTypeIdentifiers

/// Guide view shown when importing from Safari.
///
/// Explains how to use Safari's File > Export Browsing Data feature
/// and provides a button to select the exported zip file.
struct SafariExportGuideView: View {
    @Bindable var viewModel: ImportWizardViewModel

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introSection
                stepsSection
                selectFileSection
                securityNote
            }
            .padding(20)
        }
    }

    // MARK: - Intro

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let icon = ThirdPartyBrowser.safari.iconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                }

                Text("Import from Safari")
                    .font(.headline)
            }

            Text("Safari can export all your browsing data as a single file. Follow the steps below to create the export, then select it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepRow(
                number: 1,
                title: "Open Safari",
                description: "Launch Safari if it isn't already open.",
            )

            stepRow(
                number: 2,
                title: "Export Browsing Data",
                description: "Go to **File → Export Browsing Data to File...**",
            )

            stepRow(
                number: 3,
                title: "Authenticate",
                description: "Enter your Mac password or use Touch ID when prompted.",
            )

            stepRow(
                number: 4,
                title: "Save the export",
                description: "Choose what to include and click **Export**. Save the zip file somewhere accessible.",
            )
        }
    }

    private func stepRow(
        number: Int,
        title: String,
        description: LocalizedStringKey,
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.appAccentColor)
                    .frame(width: 24, height: 24)

                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - File Selection

    private var selectFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select the exported file")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Choose the zip file you saved from Safari.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showFilePicker()
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Select File...")
                    }
                }
                .disabled(isLoading)
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Security Note

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.callout)

            Text("The export file may contain passwords. After importing, consider deleting it for security.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.06)),
        )
    }

    // MARK: - File Picker

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the Safari export zip file"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        errorMessage = nil
        isLoading = true

        _ = url.startAccessingSecurityScopedResource()

        Task {
            do {
                let contents = try await SafariExportParser.parse(zipURL: url)
                isLoading = false
                viewModel.handleSafariExportSelected(contents)
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
