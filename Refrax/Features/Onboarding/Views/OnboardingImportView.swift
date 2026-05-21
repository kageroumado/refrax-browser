import SwiftData
import SwiftUI

/// Third onboarding screen: inline browser data import.
///
/// Detects installed browsers and shows them as expandable rows.
/// Clicking a browser expands it to reveal data type toggles.
/// Import runs inline with progress, then shows results before
/// completing onboarding.
///
/// Only browsers with detectable profiles (actual data on disk)
/// are shown — Launch Services registration alone is not sufficient.
struct OnboardingImportView: View {
    let onCompleted: () -> Void

    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(PasswordsManager.self) private var passwordsManager
    @Environment(\.modelContext) private var modelContext

    @State private var phase: Phase = .selection
    @State private var installedBrowsers: [ThirdPartyBrowser] = []
    @State private var expandedBrowsers: Set<ThirdPartyBrowser> = []
    @State private var browserProfiles: [ThirdPartyBrowser: BrowserProfile] = [:]
    @State private var browserOptions: [ThirdPartyBrowser: ImportOptions] = [:]
    @State private var progress: Double = 0
    @State private var progressMessage = ""
    @State private var importResult = ComprehensiveImportResult()
    @State private var importError: ImportError?

    enum Phase {
        case selection
        case importing
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .selection:
                selectionContent
            case .importing:
                importingContent
            case .complete:
                completeContent
            }
        }
        .onAppear {
            installedBrowsers = BrowserDetector.detectInstalledBrowsers()
        }
    }
}

// MARK: - Selection Phase

private extension OnboardingImportView {
    var selectionContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 32)

                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Text("Import Your Data")
                            .font(.title)
                            .fontWeight(.semibold)

                        Text("Bring your bookmarks, history, and passwords\nfrom another browser.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if installedBrowsers.isEmpty {
                        Text("No other browsers detected.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    } else {
                        browserList
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 40)
            }

            Divider()

            selectionFooter
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
        }
    }

    var browserList: some View {
        VStack(spacing: 6) {
            ForEach(installedBrowsers) { browser in
                browserRow(browser)
            }
        }
        .frame(maxWidth: .infinity)
    }

    func browserRow(_ browser: ThirdPartyBrowser) -> some View {
        let isExpanded = expandedBrowsers.contains(browser)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        collapseBrowser(browser)
                    } else {
                        expandBrowser(browser)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if let icon = browser.iconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "globe")
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    }

                    Text(browser.displayName)
                        .font(.body)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                dataTypeToggles(for: browser)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isExpanded ? AnyShapeStyle(Color.appAccentColor.opacity(0.06)) : AnyShapeStyle(.quaternary.opacity(0.5)))
        )
    }

    func dataTypeToggles(for browser: ThirdPartyBrowser) -> some View {
        let supported = browser.supportedImportTypes

        return VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)

            VStack(spacing: 8) {
                ForEach(ImportDataType.allCases) { dataType in
                    if supported.contains(dataType), dataType != .extensions {
                        HStack(spacing: 8) {
                            Image(systemName: dataType.iconName)
                                .font(.subheadline)
                                .frame(width: 16, alignment: .center)

                            Text(dataType.displayName)
                                .font(.subheadline)

                            Spacer()

                            Toggle(isOn: binding(for: dataType, browser: browser)) {
                                EmptyView()
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    func binding(for dataType: ImportDataType, browser: ThirdPartyBrowser) -> Binding<Bool> {
        Binding(
            get: {
                let options = browserOptions[browser] ?? ImportOptions()
                switch dataType {
                case .bookmarks: return options.importBookmarks
                case .history: return options.importHistory
                case .passwords: return options.importPasswords
                case .extensions: return options.importExtensions
                }
            },
            set: { newValue in
                var options = browserOptions[browser] ?? ImportOptions()
                switch dataType {
                case .bookmarks: options.importBookmarks = newValue
                case .history: options.importHistory = newValue
                case .passwords: options.importPasswords = newValue
                case .extensions: options.importExtensions = newValue
                }
                browserOptions[browser] = options
            }
        )
    }

    var selectionFooter: some View {
        HStack {
            if !installedBrowsers.isEmpty {
                Button("Skip") {
                    onCompleted()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if installedBrowsers.isEmpty {
                Button {
                    onCompleted()
                } label: {
                    Text("Start Browsing")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    startImport()
                } label: {
                    Text("Import & Continue")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(expandedBrowsers.isEmpty || !hasAnySelection)
            }
        }
    }
}

// MARK: - Importing Phase

private extension OnboardingImportView {
    var importingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            if progress < 1.0 {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(height: 48)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text("Importing Data")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(progressMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .frame(width: 280)

            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Complete Phase

private extension OnboardingImportView {
    var completeContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 32)

                    statusIcon

                    Text(importError != nil ? "Import Failed" : "Import Complete")
                        .font(.title)
                        .fontWeight(.semibold)

                    if importError == nil {
                        resultStats
                    }

                    if let error = importError {
                        errorBanner(error)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 40)
            }

            Divider()

            HStack {
                if importError != nil {
                    Button("Try Again") {
                        phase = .selection
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button {
                    onCompleted()
                } label: {
                    Text("Start Browsing")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    var statusIcon: some View {
        if importError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
        }
    }

    var resultStats: some View {
        VStack(spacing: 10) {
            if importResult.bookmarksImported > 0 || importResult.foldersCreated > 0 {
                statRow(
                    icon: "bookmark.fill",
                    color: .blue,
                    text: "\(importResult.bookmarksImported) bookmarks imported"
                )
            }
            if importResult.historyEntriesImported > 0 {
                statRow(
                    icon: "clock.fill",
                    color: .orange,
                    text: "\(importResult.historyEntriesImported) history entries imported"
                )
            }
            if importResult.credentialsImported > 0 {
                statRow(
                    icon: "key.fill",
                    color: .green,
                    text: "\(importResult.credentialsImported) passwords imported"
                )
            }
            if importResult.bookmarkDuplicatesSkipped > 0 {
                statRow(
                    icon: "arrow.triangle.2.circlepath",
                    color: .secondary,
                    text: "\(importResult.bookmarkDuplicatesSkipped) duplicates skipped"
                )
            }
        }
        .frame(maxWidth: 320)
    }

    func statRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }

    func errorBanner(_ error: ImportError) -> some View {
        VStack(spacing: 6) {
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }
}

// MARK: - Import Logic

private extension OnboardingImportView {
    var hasAnySelection: Bool {
        expandedBrowsers.contains { browser in
            guard let options = browserOptions[browser], options.hasSelection else { return false }
            return browserProfiles[browser] != nil
        }
    }

    func expandBrowser(_ browser: ThirdPartyBrowser) {
        expandedBrowsers.insert(browser)

        if browserOptions[browser] == nil {
            var options = ImportOptions()
            options.importBookmarks = false
            options.importHistory = false
            options.importPasswords = false
            options.importExtensions = false
            options.availableDataTypes = browser.supportedImportTypes
            browserOptions[browser] = options
        }

        if browserProfiles[browser] == nil {
            let profiles = BrowserDetector.detectProfiles(for: browser)
            browserProfiles[browser] = profiles.first
        }
    }

    func collapseBrowser(_ browser: ThirdPartyBrowser) {
        expandedBrowsers.remove(browser)
        browserOptions.removeValue(forKey: browser)
        browserProfiles.removeValue(forKey: browser)
    }

    func startImport() {
        let browsersToImport = expandedBrowsers.filter { browser in
            guard let options = browserOptions[browser], options.hasSelection else { return false }
            return browserProfiles[browser] != nil
        }
        guard !browsersToImport.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .importing
        }

        progress = 0
        progressMessage = "Preparing import..."

        Task {
            let totalBrowsers = Double(browsersToImport.count)
            var combinedResult = ComprehensiveImportResult()
            var lastError: ImportError?

            for (index, browser) in browsersToImport.enumerated() {
                guard let profile = browserProfiles[browser],
                      let options = browserOptions[browser]
                else { continue }

                let baseProgress = Double(index) / totalBrowsers
                let browserWeight = 1.0 / totalBrowsers

                progressMessage = "Importing from \(browser.displayName)..."

                let importer = ComprehensiveImporter(
                    browser: browser,
                    profile: profile,
                    options: options,
                    bookmarksManager: bookmarksManager,
                    passwordsManager: passwordsManager,
                    modelContainer: modelContext.container
                )

                let result = await importer.performImport { newProgress, message in
                    self.progress = baseProgress + newProgress * browserWeight
                    self.progressMessage = "\(browser.displayName): \(message)"
                }

                combinedResult.bookmarksImported += result.result.bookmarksImported
                combinedResult.foldersCreated += result.result.foldersCreated
                combinedResult.historyEntriesImported += result.result.historyEntriesImported
                combinedResult.credentialsImported += result.result.credentialsImported
                combinedResult.bookmarkDuplicatesSkipped += result.result.bookmarkDuplicatesSkipped

                if let error = result.error {
                    lastError = error
                }

                for conflict in result.pendingConflicts {
                    do {
                        try passwordsManager.importCredential(
                            conflict.incoming,
                            conflictResolution: .useImported
                        )
                        combinedResult.credentialsImported += 1
                    } catch {
                        Logger.error("Failed to resolve conflict during onboarding: \(error)", category: Logger.autoFill)
                    }
                }
            }

            importResult = combinedResult
            importError = lastError

            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .complete
            }
        }
    }
}
