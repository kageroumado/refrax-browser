import SwiftData
import SwiftUI

/// Multi-step wizard for importing data from other browsers.
///
/// The wizard guides users through:
/// 1. Selecting a source browser
/// 2. Selecting a profile (if multiple exist)
/// 3. Selecting data types to import (bookmarks, history, passwords, extensions)
/// 4. Configuring import options (e.g., history date range)
/// 5. Viewing progress
/// 6. Resolving credential conflicts
/// 7. Reviewing results
///
/// ## Usage
///
/// Present as a sheet from a parent view:
///
/// ```swift
/// .sheet(isPresented: $showImportWizard) {
///     ImportWizardView()
/// }
/// ```
struct ImportWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(HistoryManager.self) private var historyManager
    @Environment(PasswordsManager.self) private var passwordsManager
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = ImportWizardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Constants.windowWidth, height: Constants.windowHeight)
        .onAppear {
            viewModel.detectBrowsers()
        }
    }

    private enum Constants {
        static let windowWidth: CGFloat = 520
        static let windowHeight: CGFloat = 520
    }
}

// MARK: - Header

private extension ImportWizardView {
    var header: some View {
        HStack {
            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    var headerTitle: String {
        switch viewModel.currentStep {
        case .selectBrowser: "Import Data"
        case .selectProfile: "Select Profile"
        case .safariExportGuide: "Import from Safari"
        case .selectDataTypes: "Select Data"
        case .configureOptions: "Configure Import"
        case .importing: "Importing..."
        case .credentialConflicts: "Resolve Conflicts"
        case .summary: "Import Complete"
        case .failedBookmarks: "Failed Imports"
        case .extensionPreview: "Extensions Found"
        }
    }
}

// MARK: - Content

private extension ImportWizardView {
    @ViewBuilder
    var content: some View {
        switch viewModel.currentStep {
        case .selectBrowser:
            BrowserSelectionView(viewModel: viewModel)
        case .selectProfile:
            ProfileSelectionView(viewModel: viewModel)
        case .safariExportGuide:
            SafariExportGuideView(viewModel: viewModel)
        case .selectDataTypes:
            DataTypeSelectionView(viewModel: viewModel)
        case .configureOptions:
            ImportOptionsView(viewModel: viewModel)
        case .importing:
            ImportProgressView(viewModel: viewModel)
        case .credentialConflicts:
            CredentialConflictView(viewModel: viewModel)
        case .summary:
            ImportSummaryView(viewModel: viewModel)
        case .failedBookmarks:
            FailedBookmarksView(viewModel: viewModel)
        case .extensionPreview:
            ExtensionPreviewView(viewModel: viewModel)
        }
    }
}

// MARK: - Footer

private extension ImportWizardView {
    var footer: some View {
        HStack {
            if viewModel.canGoBack {
                Button("Back") {
                    viewModel.goBack()
                }
            }

            Spacer()

            footerButtons
        }
        .padding()
    }

    @ViewBuilder
    var footerButtons: some View {
        switch viewModel.currentStep {
        case .selectBrowser, .selectProfile, .safariExportGuide:
            EmptyView()
        case .selectDataTypes:
            Button("Continue") {
                viewModel.proceedFromDataTypeSelection()
            }
            .disabled(!viewModel.importOptions.hasSelection)
            .keyboardShortcut(.defaultAction)
        case .configureOptions:
            Button("Start Import") {
                viewModel.startImport(
                    bookmarksManager: bookmarksManager,
                    passwordsManager: passwordsManager,
                    modelContainer: modelContext.container,
                )
            }
            .keyboardShortcut(.defaultAction)
        case .importing:
            EmptyView()
        case .credentialConflicts:
            Button("Continue") {
                viewModel.resolveConflictsAndContinue(passwordsManager: passwordsManager)
            }
            .disabled(!viewModel.allConflictsResolved)
            .keyboardShortcut(.defaultAction)
        case .summary:
            HStack(spacing: 12) {
                if viewModel.hasFailedBookmarks {
                    Button("View Failed") {
                        viewModel.currentStep = .failedBookmarks
                    }
                }
                if !viewModel.comprehensiveResult.extensionsList.isEmpty {
                    Button("View Extensions") {
                        viewModel.currentStep = .extensionPreview
                    }
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        case .failedBookmarks, .extensionPreview:
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - View Model

/// State management for the comprehensive import wizard flow.
@Observable
final class ImportWizardViewModel {
    // MARK: - Navigation State

    /// Current step in the wizard.
    var currentStep: ImportStep = .selectBrowser

    /// Whether the back button should be shown.
    var canGoBack: Bool {
        switch currentStep {
        case .selectProfile, .safariExportGuide, .selectDataTypes, .configureOptions, .failedBookmarks, .extensionPreview:
            true
        default:
            false
        }
    }

    // MARK: - Browser Selection

    /// Selected browser for import.
    var selectedBrowser: ThirdPartyBrowser?

    /// Selected profile within the browser.
    var selectedProfile: BrowserProfile?

    /// Browsers detected as installed on the system.
    var installedBrowsers: [ThirdPartyBrowser] = []

    /// Available profiles for the selected browser.
    var profiles: [BrowserProfile] = []

    // MARK: - Import Options

    /// User's selections for what to import.
    var importOptions = ImportOptions()

    /// URL of the HTML file to import (when importing from HTML file).
    var htmlFileURL: URL?

    /// Parsed contents of a Safari export zip file.
    var safariExportContents: SafariExportContents?

    // MARK: - Progress State

    /// Import progress (0.0 to 1.0).
    var progress: Double = 0

    /// Current progress message.
    var progressMessage = ""

    // MARK: - Results

    /// Result of the import operation (legacy, for backwards compatibility).
    var result: ImportResult?

    /// Comprehensive result covering all data types.
    var comprehensiveResult = ComprehensiveImportResult()

    /// Error that occurred during import.
    var error: ImportError?

    // MARK: - Credential Conflicts

    /// Credential conflicts requiring user resolution.
    var pendingConflicts: [PasswordsManager.CredentialConflict] = []

    /// Whether all conflicts have been resolved.
    var allConflictsResolved: Bool {
        pendingConflicts.allSatisfy { $0.resolution != nil }
    }

    // MARK: - Computed Properties

    /// Whether there are failed bookmarks to view.
    var hasFailedBookmarks: Bool {
        !comprehensiveResult.failedBookmarks.isEmpty
    }

    // MARK: - Public Methods

    /// Detects installed browsers on the system.
    func detectBrowsers() {
        installedBrowsers = BrowserDetector.detectInstalledBrowsers()
    }

    /// Selects a browser and advances to the next step.
    func selectBrowser(_ browser: ThirdPartyBrowser) {
        selectedBrowser = browser
        importOptions.availableDataTypes = browser.supportedImportTypes

        if browser == .htmlFile {
            importOptions = .bookmarksOnly
            currentStep = .importing
            return
        }

        if browser == .safari {
            currentStep = .safariExportGuide
            return
        }

        profiles = BrowserDetector.detectProfiles(for: browser)

        if profiles.count == 1 {
            selectedProfile = profiles.first
            currentStep = .selectDataTypes
        } else if profiles.isEmpty {
            error = .noBookmarksFound
            currentStep = .summary
        } else {
            currentStep = .selectProfile
        }
    }

    /// Handles a Safari export zip being selected.
    func handleSafariExportSelected(_ contents: SafariExportContents) {
        safariExportContents = contents
        selectedBrowser = .safari
        importOptions.availableDataTypes = contents.availableDataTypes

        // Enable all available types by default
        importOptions.importBookmarks = contents.bookmarksURL != nil
        importOptions.importHistory = contents.historyURL != nil
        importOptions.importPasswords = contents.passwordsURL != nil
        importOptions.importExtensions = contents.extensionsURL != nil

        currentStep = .selectDataTypes
    }

    /// Selects a profile and advances to data type selection.
    func selectProfile(_ profile: BrowserProfile) {
        selectedProfile = profile
        currentStep = .selectDataTypes
    }

    /// Proceeds from data type selection to options or import.
    func proceedFromDataTypeSelection() {
        if importOptions.importHistory {
            if let safariExport = safariExportContents, let historyURL = safariExport.historyURL {
                loadSafariExportHistoryDateRange(historyURL: historyURL)
            } else if let browser = selectedBrowser, let profile = selectedProfile {
                loadHistoryDateRange(browser: browser, profile: profile)
            }
        }
        currentStep = .configureOptions
    }

    /// Starts the comprehensive import.
    func startImport(
        bookmarksManager: BookmarksManager,
        passwordsManager: PasswordsManager,
        modelContainer: ModelContainer,
    ) {
        currentStep = .importing

        // Import runs async via ComprehensiveImporter service.
        Task {
            await performImportWithService(
                bookmarksManager: bookmarksManager,
                passwordsManager: passwordsManager,
                modelContainer: modelContainer,
            )
        }
    }

    /// Resolves all pending credential conflicts and continues.
    func resolveConflictsAndContinue(passwordsManager: PasswordsManager) {
        for conflict in pendingConflicts {
            guard let resolution = conflict.resolution else { continue }
            do {
                try passwordsManager.importCredential(
                    conflict.incoming,
                    conflictResolution: resolution,
                )
                comprehensiveResult.credentialConflictsResolved += 1
            } catch {
                Logger.error("Failed to resolve conflict: \(error)", category: Logger.autoFill)
            }
        }
        currentStep = .summary
    }

    /// Navigates back to the previous step.
    func goBack() {
        switch currentStep {
        case .selectProfile:
            selectedBrowser = nil
            selectedProfile = nil
            currentStep = .selectBrowser
        case .safariExportGuide:
            selectedBrowser = nil
            currentStep = .selectBrowser
        case .selectDataTypes:
            if safariExportContents != nil {
                // Safari export: go back to the guide
                safariExportContents?.cleanup()
                safariExportContents = nil
                currentStep = .safariExportGuide
            } else if profiles.count > 1 {
                currentStep = .selectProfile
            } else {
                selectedBrowser = nil
                selectedProfile = nil
                currentStep = .selectBrowser
            }
        case .configureOptions:
            currentStep = .selectDataTypes
        case .failedBookmarks, .extensionPreview:
            currentStep = .summary
        default:
            break
        }
    }
}

// MARK: - Import Logic

private extension ImportWizardViewModel {
    func loadSafariExportHistoryDateRange(historyURL: URL) {
        Task {
            do {
                if let dateRange = try await SafariHistoryJSONImporter.getDateRange(from: historyURL) {
                    importOptions.historyMinDate = dateRange.min
                    importOptions.historyMaxDate = dateRange.max
                    importOptions.historyTimeRange = dateRange.min ... dateRange.max
                } else {
                    importOptions.historyDateRangeUnavailable = true
                }
            } catch {
                Logger.warning("Could not load Safari export history date range: \(error)", category: Logger.data)
                importOptions.historyDateRangeUnavailable = true
            }
        }
    }

    func loadHistoryDateRange(browser: ThirdPartyBrowser, profile: BrowserProfile) {
        Task {
            guard let importer = HistoryImporterFactory.createImporter(for: browser) else {
                // No importer available — skip date range, import all history
                importOptions.historyDateRangeUnavailable = true
                return
            }

            do {
                if let dateRange = try await importer.getHistoryDateRange(from: profile) {
                    importOptions.historyMinDate = dateRange.min
                    importOptions.historyMaxDate = dateRange.max
                    importOptions.historyTimeRange = dateRange.min ... dateRange.max
                } else {
                    importOptions.historyDateRangeUnavailable = true
                }
            } catch {
                Logger.warning("Could not load history date range: \(error)", category: Logger.data)
                importOptions.historyDateRangeUnavailable = true
            }
        }
    }

    func performImportWithService(
        bookmarksManager: BookmarksManager,
        passwordsManager: PasswordsManager,
        modelContainer: ModelContainer,
    ) async {
        progress = 0
        progressMessage = "Preparing import..."
        comprehensiveResult = ComprehensiveImportResult()

        // Create the appropriate importer based on source type
        let importer: ComprehensiveImporter
        if let safariExport = safariExportContents {
            importer = ComprehensiveImporter(
                safariExport: safariExport,
                options: importOptions,
                bookmarksManager: bookmarksManager,
                passwordsManager: passwordsManager,
                modelContainer: modelContainer,
            )
        } else if let htmlURL = htmlFileURL {
            importer = ComprehensiveImporter(
                htmlFileURL: htmlURL,
                bookmarksManager: bookmarksManager,
                passwordsManager: passwordsManager,
                modelContainer: modelContainer,
            )
        } else if let browser = selectedBrowser, let profile = selectedProfile {
            importer = ComprehensiveImporter(
                browser: browser,
                profile: profile,
                options: importOptions,
                bookmarksManager: bookmarksManager,
                passwordsManager: passwordsManager,
                modelContainer: modelContainer,
            )
        } else {
            error = .noBookmarksFound
            currentStep = .summary
            return
        }

        // Perform import with progress reporting
        let importResult = await importer.performImport { [weak self] newProgress, message in
            self?.progress = newProgress
            self?.progressMessage = message
        }

        // Clean up Safari export temp files
        safariExportContents?.cleanup()

        // Update state with results
        comprehensiveResult = importResult.result
        pendingConflicts = importResult.pendingConflicts
        error = importResult.error
        result = comprehensiveResult.asBookmarkResult

        // Navigate to appropriate next step
        if importResult.hasConflicts {
            currentStep = .credentialConflicts
        } else {
            currentStep = .summary
        }
    }
}
