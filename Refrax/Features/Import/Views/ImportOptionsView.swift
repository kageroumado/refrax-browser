import SwiftUI
import UniformTypeIdentifiers

/// View for configuring import options before starting the import.
///
/// Shows configuration options for each selected data type:
/// - History: Date range slider
/// - Passwords: CSV file selection
/// - Extensions: Information about what will be scanned
struct ImportOptionsView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                headerSection

                if viewModel.importOptions.importBookmarks {
                    bookmarksSection
                }

                if viewModel.importOptions.importHistory {
                    historySection
                }

                if viewModel.importOptions.importPasswords {
                    passwordsSection
                }

                if viewModel.importOptions.importExtensions {
                    extensionsSection
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 20
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 16
    }
}

// MARK: - Header

private extension ImportOptionsView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Review your import settings")
                .font(.headline)

            Text("Configure how data should be imported")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bookmarks Section

private extension ImportOptionsView {
    var bookmarksSection: some View {
        OptionSection(
            icon: "bookmark.fill",
            title: "Bookmarks",
            color: .blue,
        ) {
            Text("All bookmarks and folders will be imported.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Duplicates (matching URLs) will be skipped.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - History Section

private extension ImportOptionsView {
    var historySection: some View {
        OptionSection(
            icon: "clock.fill",
            title: "Browsing History",
            color: .orange,
        ) {
            historyRangeContent
        }
    }

    @ViewBuilder
    var historyRangeContent: some View {
        if let minDate = viewModel.importOptions.historyMinDate,
           let maxDate = viewModel.importOptions.historyMaxDate {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select time range:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HistoryDateRangeSlider(
                    minDate: minDate,
                    maxDate: maxDate,
                    selectedRange: Binding(
                        get: { viewModel.importOptions.historyTimeRange ?? (minDate ... maxDate) },
                        set: { viewModel.importOptions.historyTimeRange = $0 },
                    ),
                )

                if let range = viewModel.importOptions.historyTimeRange {
                    Text("\(range.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(range.upperBound.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if viewModel.importOptions.historyDateRangeUnavailable {
            VStack(alignment: .leading, spacing: 4) {
                Text("All browsing history will be imported.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Date range filtering requires Full Disk Access in System Settings > Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Loading history date range...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
}

// MARK: - History Date Range Slider

private struct HistoryDateRangeSlider: View {
    let minDate: Date
    let maxDate: Date
    @Binding var selectedRange: ClosedRange<Date>

    @State private var startValue: Double = 0
    @State private var endValue: Double = 1

    private var totalSeconds: Double {
        max(1, maxDate.timeIntervalSince(minDate))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("From")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $startValue, in: 0 ... 1)
                    .onChange(of: startValue) { _, newValue in
                        let newStart = minDate.addingTimeInterval(newValue * totalSeconds)
                        if newStart < selectedRange.upperBound {
                            selectedRange = newStart ... selectedRange.upperBound
                        }
                    }
            }

            HStack {
                Text("To")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                Slider(value: $endValue, in: 0 ... 1)
                    .onChange(of: endValue) { _, newValue in
                        let newEnd = minDate.addingTimeInterval(newValue * totalSeconds)
                        if newEnd > selectedRange.lowerBound {
                            selectedRange = selectedRange.lowerBound ... newEnd
                        }
                    }
            }
        }
        .onAppear {
            startValue = selectedRange.lowerBound.timeIntervalSince(minDate) / totalSeconds
            endValue = selectedRange.upperBound.timeIntervalSince(minDate) / totalSeconds
        }
    }
}

// MARK: - Passwords Section

private extension ImportOptionsView {
    var passwordsSection: some View {
        OptionSection(
            icon: "key.fill",
            title: "Passwords",
            color: .green,
        ) {
            passwordsContent
        }
    }

    @ViewBuilder
    var passwordsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.safariExportContents?.passwordsURL != nil {
                Text("Passwords from the Safari export will be imported.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.importOptions.passwordImportMethod == .direct {
                Text("Passwords will be imported directly from the browser's database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let csvURL = viewModel.importOptions.passwordCSVFileURL {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.green)
                    Text(csvURL.lastPathComponent)
                        .font(.subheadline)
                    Spacer()
                    Button("Change") {
                        // Will be handled by file picker
                    }
                    .font(.caption)
                }
            } else {
                Text("Select a CSV file exported from your browser or password manager.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                CSVFilePickerButton(selectedURL: $viewModel.importOptions.passwordCSVFileURL)
            }

            Text("Passwords will be stored securely in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("Conflicts will be shown for resolution before import.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - CSV File Picker Button

private struct CSVFilePickerButton: View {
    @Binding var selectedURL: URL?
    @State private var showingFilePicker = false

    var body: some View {
        Button {
            showingFilePicker = true
        } label: {
            Label("Select CSV File...", systemImage: "doc.badge.plus")
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText],
            onCompletion: handleFileSelection,
        )
    }

    private func handleFileSelection(_ result: Result<URL, any Error>) {
        switch result {
        case let .success(url):
            _ = url.startAccessingSecurityScopedResource()
            selectedURL = url
        case let .failure(error):
            Logger.error("Failed to select CSV file: \(error)", category: Logger.data)
        }
    }
}

// MARK: - Extensions Section

private extension ImportOptionsView {
    var extensionsSection: some View {
        OptionSection(
            icon: "puzzlepiece.extension.fill",
            title: "Extensions",
            color: .purple,
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extensions will be scanned and listed for your reference.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Extension import is not yet supported - this is informational only.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Option Section

private struct OptionSection<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)

                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03)),
        )
    }
}
