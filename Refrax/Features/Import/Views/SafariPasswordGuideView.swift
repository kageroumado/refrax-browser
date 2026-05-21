import SwiftUI
import UniformTypeIdentifiers

/// View displaying instructions for exporting passwords from Safari.
///
/// Safari passwords are stored in iCloud Keychain and cannot be accessed
/// programmatically. This view guides users through the export process.
struct SafariPasswordGuideView: View {
    @Binding var csvFileURL: URL?
    @State private var showingFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            headerSection
            instructionsSection
            filePickerSection
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.cornerRadius)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1),
                ),
        )
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText],
            onCompletion: handleFileSelection,
        )
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 12
        static let cornerRadius: CGFloat = 12
    }
}

// MARK: - Sections

private extension SafariPasswordGuideView {
    var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            Text("Safari passwords require manual export")
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }

    var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Follow these steps to export your Safari passwords:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                instructionStep(1, "In Safari, go to **File** → **Export Browsing Data to File...**")
                instructionStep(2, "Make sure **Passwords** is toggled on")
                instructionStep(3, "Click **Export** and save the file")
                instructionStep(4, "Select the exported CSV file below")
            }
            .font(.callout)
        }
    }

    var filePickerSection: some View {
        HStack {
            if let url = csvFileURL {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showingFilePicker = true
            } label: {
                Label(
                    csvFileURL == nil ? "Select CSV File" : "Change File",
                    systemImage: "doc.badge.plus",
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    func instructionStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .foregroundStyle(.primary)
        }
    }

    func handleFileSelection(_ result: Result<URL, any Error>) {
        switch result {
        case let .success(url):
            _ = url.startAccessingSecurityScopedResource()
            csvFileURL = url
        case let .failure(error):
            Logger.error("Failed to select CSV file: \(error)", category: Logger.data)
        }
    }
}

// MARK: - Compact Variant

/// A compact version of the Safari password guide for inline display.
struct SafariPasswordGuideCompact: View {
    @Binding var csvFileURL: URL?
    @State private var showingFilePicker = false
    @State private var showingDetailedGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                Text("Safari requires CSV export")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Button("How to export") {
                    showingDetailedGuide = true
                }
                .font(.caption)
                .buttonStyle(.link)
            }

            HStack {
                if let url = csvFileURL {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Select a CSV file")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button(csvFileURL == nil ? "Select CSV..." : "Change...") {
                    showingFilePicker = true
                }
                .font(.caption)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText],
            onCompletion: handleFileSelection,
        )
        .sheet(isPresented: $showingDetailedGuide) {
            SafariExportInstructionsSheet()
        }
    }

    private func handleFileSelection(_ result: Result<URL, any Error>) {
        switch result {
        case let .success(url):
            _ = url.startAccessingSecurityScopedResource()
            csvFileURL = url
        case let .failure(error):
            Logger.error("Failed to select CSV file: \(error)", category: Logger.data)
        }
    }
}

// MARK: - Instructions Sheet

/// Detailed sheet showing step-by-step Safari export instructions.
struct SafariExportInstructionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 380)
    }

    private var header: some View {
        HStack {
            Text("Export Safari Passwords")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                instructionGroup(
                    step: 1,
                    title: "Open Safari",
                    description: "Launch **Safari** if it isn't already open",
                )

                instructionGroup(
                    step: 2,
                    title: "Export Browsing Data",
                    description: "Go to **File** → **Export Browsing Data to File...**",
                    note: "Authenticate with Touch ID or your Mac password when prompted",
                )

                instructionGroup(
                    step: 3,
                    title: "Enable Passwords",
                    description: "Make sure the **Passwords** toggle is turned on in the export dialog",
                    note: "You can also export bookmarks and history at the same time",
                )

                instructionGroup(
                    step: 4,
                    title: "Save the File",
                    description: "Click **Export** and choose where to save the file",
                )

                instructionGroup(
                    step: 5,
                    title: "Select the CSV",
                    description: "Return here and select the exported CSV file",
                )

                securityNote
            }
            .padding()
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Got it") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func instructionGroup(
        step: Int,
        title: String,
        description: LocalizedStringKey,
        note: String? = nil,
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appAccentColor)
                    .frame(width: 28, height: 28)

                Text("\(step)")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Security Note")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("The exported CSV file contains your passwords in plain text. After importing, we recommend deleting the CSV file for security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08)),
        )
    }
}
