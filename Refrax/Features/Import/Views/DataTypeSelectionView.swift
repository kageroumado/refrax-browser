import SwiftUI
import UniformTypeIdentifiers

/// View for selecting which data types to import from the browser.
///
/// Displays checkboxes for each available data type (bookmarks, history, passwords,
/// extensions) with descriptions of what will be imported.
struct DataTypeSelectionView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            headerSection
            dataTypeList
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 16
        static let itemSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
    }
}

// MARK: - Sections

private extension DataTypeSelectionView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let browser = viewModel.selectedBrowser {
                HStack(spacing: 8) {
                    if let icon = browser.iconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    Text(browser.displayName)
                        .font(.headline)
                }
            }

        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
    }

    var dataTypeList: some View {
        ScrollView {
            LazyVStack(spacing: Constants.itemSpacing) {
                ForEach(ImportDataType.allCases) { dataType in
                    if viewModel.importOptions.availableDataTypes.contains(dataType) {
                        if dataType == .passwords, viewModel.safariExportContents == nil {
                            PasswordImportRow(
                                isSelected: $viewModel.importOptions.importPasswords,
                                importMethod: $viewModel.importOptions.passwordImportMethod,
                                csvFileURL: $viewModel.importOptions.passwordCSVFileURL,
                                supportsDirectImport: viewModel.selectedBrowser?.supportsDirectPasswordImport ?? false,
                                browserName: viewModel.selectedBrowser?.displayName ?? "Browser",
                                isSafari: viewModel.selectedBrowser == .safari,
                            )
                        } else {
                            DataTypeRow(
                                dataType: dataType,
                                isSelected: binding(for: dataType),
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.bottom, Constants.bottomPadding)
        }
    }

    func binding(for dataType: ImportDataType) -> Binding<Bool> {
        switch dataType {
        case .bookmarks:
            $viewModel.importOptions.importBookmarks
        case .history:
            $viewModel.importOptions.importHistory
        case .passwords:
            $viewModel.importOptions.importPasswords
        case .extensions:
            $viewModel.importOptions.importExtensions
        }
    }
}

// MARK: - Data Type Row

/// A row displaying a data type option with toggle and description.
private struct DataTypeRow: View {
    let dataType: ImportDataType
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: Constants.iconSpacing) {
                Image(systemName: dataType.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.appAccentColor : .secondary)
                    .frame(width: Constants.iconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dataType.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(dataType.importDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(isSelected ? Color.appAccentColor.opacity(0.08) : Color.primary.opacity(0.03)),
        )
    }

    private enum Constants {
        static let iconSpacing: CGFloat = 12
        static let iconSize: CGFloat = 28
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 10
    }
}

// MARK: - Password Import Row

/// A specialized row for password import with method selection.
///
/// Displays options for direct import (if supported) or CSV import,
/// with appropriate guidance for each method.
private struct PasswordImportRow: View {
    @Binding var isSelected: Bool
    @Binding var importMethod: PasswordImportMethod
    @Binding var csvFileURL: URL?
    let supportsDirectImport: Bool
    let browserName: String
    let isSafari: Bool

    @State private var showingFilePicker = false
    @State private var showingSafariGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mainToggle
            if isSelected {
                if isSafari {
                    safariImportSection
                } else {
                    methodSelectionSection
                }
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(isSelected ? Color.appAccentColor.opacity(0.08) : Color.primary.opacity(0.03)),
        )
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText],
            onCompletion: handleFileSelection,
        )
        .sheet(isPresented: $showingSafariGuide) {
            SafariExportInstructionsSheet()
        }
        .onAppear {
            // Force CSV method for Safari since direct import isn't available
            if isSafari {
                importMethod = .csv
            }
        }
    }

    private var mainToggle: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: Constants.iconSpacing) {
                Image(systemName: ImportDataType.passwords.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.appAccentColor : .secondary)
                    .frame(width: Constants.iconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ImportDataType.passwords.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(ImportDataType.passwords.importDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
        }
        .toggleStyle(.switch)
    }

    private var safariImportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                Text("Safari passwords require manual export")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Button("How to export") {
                    showingSafariGuide = true
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .padding(.leading, Constants.iconSize + Constants.iconSpacing)

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
                    Text("Select exported CSV file")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button(csvFileURL == nil ? "Select CSV..." : "Change...") {
                    showingFilePicker = true
                }
                .font(.caption)
            }
            .padding(.leading, Constants.iconSize + Constants.iconSpacing)
        }
    }

    private var methodSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import method:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, Constants.iconSize + Constants.iconSpacing)

            VStack(spacing: 8) {
                if supportsDirectImport {
                    directImportOption
                }
                csvImportOption
            }
            .padding(.leading, Constants.iconSize + Constants.iconSpacing)
        }
    }

    private var directImportOption: some View {
        HStack {
            Button {
                importMethod = .direct
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: importMethod == .direct ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(importMethod == .direct ? Color.appAccentColor : .secondary)
                        .font(.body)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.caption)
                            Text("Import Directly")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("(Recommended)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Text("Securely import from \(browserName)'s database")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(importMethod == .direct ? Color.appAccentColor.opacity(0.12) : Color.clear),
        )
    }

    private var csvImportOption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                importMethod = .csv
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: importMethod == .csv ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(importMethod == .csv ? Color.appAccentColor : .secondary)
                        .font(.body)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.fill")
                                .font(.caption)
                            Text("Import from CSV")
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                        Text("Export passwords from browser settings first")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if importMethod == .csv {
                csvFilePickerButton
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(importMethod == .csv ? Color.appAccentColor.opacity(0.12) : Color.clear),
        )
    }

    private var csvFilePickerButton: some View {
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
        .padding(.leading, 24)
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

    private enum Constants {
        static let iconSpacing: CGFloat = 12
        static let iconSize: CGFloat = 28
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 10
    }
}
