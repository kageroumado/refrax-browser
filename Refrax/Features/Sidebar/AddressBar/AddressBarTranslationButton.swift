import SwiftUI
@preconcurrency import Translation

/// Button indicating translation availability in the address bar.
///
/// Shows when the page is in a foreign language. Tapping opens a popover
/// to translate the page or view the original if already translated.
struct AddressBarTranslationButton: View {
    @Environment(TranslationManager.self) private var translationManager
    @Environment(SiteSettingsManager.self) private var siteSettingsManager

    /// The WebPage to translate.
    let webPage: WebPage?

    @State private var isHovered = false
    @State private var showsPopover = false
    @State private var detectedLanguage: Locale.Language?
    @State private var isCheckingLanguage = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var pendingRequests: [TranslationSession.Request] = []
    @State private var hasAutoTranslated = false
    @State private var isTranslationInProgress = false

    private var isTranslated: Bool {
        webPage?.isTranslated == true
    }

    private var isTranslating: Bool {
        webPage?.isTranslating == true
    }

    /// Whether to show the translation button.
    private var shouldShow: Bool {
        if isTranslated || isTranslating {
            return true
        }
        guard let detected = detectedLanguage ?? webPage?.detectedLanguage else {
            return false
        }
        return detected.languageCode != translationManager.targetLanguage.languageCode
    }

    private var foregroundColor: Color {
        if isTranslated {
            return .appAccentColor
        }
        return isHovered ? .primary : .secondary
    }

    var body: some View {
        buttonContent
            .translationTask(translationConfiguration, action: handleTranslation)
            .onChange(of: webPage?.isTranslating, handleTranslatingChange)
            .onChange(of: webPage?.url, handleURLChange)
            .onChange(of: webPage?.isLoading, handleLoadingChange)
    }

    // MARK: - View Components

    private var buttonContent: some View {
        Button {
            guard !isTranslationInProgress else { return }
            showsPopover = true
        } label: {
            buttonLabel
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("addressbar-translate")
        .accessibilityLabel(isTranslated ? "View original page" : "Translate page")
        .disabled(isTranslationInProgress)
        .opacity(shouldShow ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: shouldShow)
        .help(isTranslated ? "View original page" : "Translate page")
        .if(showsPopover) { view in
            view.popover(isPresented: $showsPopover, arrowEdge: .bottom) {
                TranslationPopoverContent(
                    webPage: webPage,
                    detectedLanguage: detectedLanguage ?? webPage?.detectedLanguage,
                    translationConfiguration: $translationConfiguration,
                    pendingRequests: $pendingRequests,
                    isTranslationInProgress: $isTranslationInProgress,
                )
            }
        }
    }

    private var buttonLabel: some View {
        ZStack {
            Image(systemName: "translate")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)

            if isTranslating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Translation Task

    /// Captures MainActor-isolated values for use in the translation task.
    /// Safe to mark as Sendable because:
    /// - `requests` contains only Sendable types (String, String?)
    /// - `page` and `manager` are only accessed via their @MainActor methods
    private nonisolated struct TranslationWorkItem: @unchecked Sendable {
        let requests: [TranslationSession.Request]
        let page: WebPage
        let manager: TranslationManager
    }

    private func handleTranslation(_ session: TranslationSession) async {
        let workItem = await MainActor.run {
            guard let page = webPage, !pendingRequests.isEmpty else { return nil as TranslationWorkItem? }
            return TranslationWorkItem(
                requests: pendingRequests,
                page: page,
                manager: translationManager,
            )
        }

        guard let workItem else { return }
        let targetLanguage = session.targetLanguage

        do {
            let responses = try await session.translations(from: workItem.requests)
            try await workItem.manager.completeTranslation(
                responses: responses,
                for: workItem.page,
                targetLanguage: targetLanguage,
            )
        } catch {
            Logger.error("Translation failed: \(error.localizedDescription)", category: Logger.tabs)
            await MainActor.run { workItem.manager.cancelTranslation(for: workItem.page) }
        }

        await MainActor.run {
            pendingRequests = []
            translationConfiguration = nil
            isTranslationInProgress = false
        }
    }

    // MARK: - Change Handlers

    private func handleTranslatingChange(_ wasTranslating: Bool?, _ nowTranslating: Bool?) {
        if wasTranslating == true, nowTranslating == false {
            pendingRequests = []
            translationConfiguration = nil
            isTranslationInProgress = false
        }
    }

    private func handleURLChange(_ oldURL: URL?, _: URL?) {
        if let oldURL {
            translationManager.clearCache(for: oldURL)
        }
        hasAutoTranslated = false
        detectedLanguage = nil
    }

    private func handleLoadingChange(_ wasLoading: Bool?, _ isLoading: Bool?) {
        if wasLoading == true, isLoading == false {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await detectLanguage()
            }
        }
    }

    // MARK: - Language Detection

    private func detectLanguage() async {
        guard let webPage, !isCheckingLanguage else { return }
        isCheckingLanguage = true
        defer { isCheckingLanguage = false }

        detectedLanguage = await translationManager.detectPageLanguage(webPage: webPage)
        webPage.detectedLanguage = detectedLanguage

        await checkAutoTranslate()
    }

    private func checkAutoTranslate() async {
        guard let webPage, let detected = detectedLanguage, !hasAutoTranslated else { return }
        guard let url = webPage.url else { return }
        guard !webPage.isTranslated, !webPage.isTranslating, !isTranslationInProgress else { return }

        let target = translationManager.targetLanguage
        guard detected.languageCode != target.languageCode else { return }

        let settings = siteSettingsManager.settings(for: url)

        let shouldAutoTranslate: Bool
        if settings?.translationPreference == .always {
            shouldAutoTranslate = true
        } else if settings?.translationPreference == .never {
            return
        } else if let languageCode = detected.languageCode?.identifier,
                  settings?.alwaysTranslateLanguages.contains(languageCode) == true {
            shouldAutoTranslate = true
        } else {
            shouldAutoTranslate = false
        }

        guard shouldAutoTranslate else { return }
        guard await translationManager.canTranslate(from: detected, to: target) else { return }

        hasAutoTranslated = true
        isTranslationInProgress = true
        do {
            let requests = try await translationManager.prepareTranslationRequests(for: webPage)
            pendingRequests = requests
            translationConfiguration = TranslationSession.Configuration(source: detected, target: target)
        } catch {
            Logger.error("Auto-translate failed: \(error.localizedDescription)", category: Logger.tabs)
            isTranslationInProgress = false
        }
    }
}

// MARK: - Translation Popover Content

struct TranslationPopoverContent: View {
    let webPage: WebPage?
    let detectedLanguage: Locale.Language?
    @Binding var translationConfiguration: TranslationSession.Configuration?
    @Binding var pendingRequests: [TranslationSession.Request]
    @Binding var isTranslationInProgress: Bool

    @Environment(TranslationManager.self) private var translationManager
    @Environment(SiteSettingsManager.self) private var siteSettingsManager
    @Environment(\.dismiss) private var dismiss

    // Index into availableLanguages array - avoids identifier matching issues
    @State private var selectedLanguageIndex: Int = 0
    @State private var isAvailable = true
    @State private var needsDownload = false
    @State private var isPreparingTranslation = false
    @State private var alwaysTranslateLanguage = false
    @State private var neverTranslateSite = false

    private var isTranslated: Bool {
        webPage?.isTranslated == true
    }

    private var selectedTargetLanguage: Locale.Language? {
        let languages = translationManager.availableLanguages
        guard selectedLanguageIndex >= 0, selectedLanguageIndex < languages.count else { return nil }
        return languages[selectedLanguageIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isTranslated {
                translatedStateContent
            } else {
                untranslatedStateContent
            }
        }
        .padding()
        .frame(width: 260)
        .task {
            // Find matching language index from available list
            let targetCode = translationManager.targetLanguage.languageCode
            if let index = translationManager.availableLanguages.firstIndex(where: { $0.languageCode == targetCode }) {
                selectedLanguageIndex = index
            }
            loadSitePreferences()
            await checkAvailability()
        }
        .onChange(of: selectedLanguageIndex) { _, _ in
            Task { await checkAvailability() }
        }
    }

    // MARK: - Untranslated State

    @ViewBuilder
    private var untranslatedStateContent: some View {
        Label("Translate Page", systemImage: "translate")
            .font(.headline)

        if let source = detectedLanguage {
            Text("This page appears to be in \(TranslationManager.displayName(for: source)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Divider()

        languagePicker

        if needsDownload {
            Label("Language pack will be downloaded", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        translateButton

        sitePreferences
    }

    private var languagePicker: some View {
        HStack {
            Text("Translate to:")
            Spacer()
            Picker("", selection: $selectedLanguageIndex) {
                ForEach(Array(translationManager.availableLanguages.enumerated()), id: \.offset) { index, lang in
                    Text(TranslationManager.displayName(for: lang))
                        .tag(index)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }

    private var translateButton: some View {
        Button {
            Task { await startTranslation() }
        } label: {
            if isPreparingTranslation {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Translate Page")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isAvailable || isPreparingTranslation)
    }

    @ViewBuilder
    private var sitePreferences: some View {
        if webPage?.url != nil {
            Divider()

            if let source = detectedLanguage {
                Toggle("Always translate \(TranslationManager.displayName(for: source))", isOn: $alwaysTranslateLanguage)
                    .font(.subheadline)
                    .onChange(of: alwaysTranslateLanguage) { _, newValue in
                        updateAlwaysTranslatePreference(newValue, for: source)
                    }
            }

            Toggle("Never translate this website", isOn: $neverTranslateSite)
                .font(.subheadline)
                .onChange(of: neverTranslateSite) { _, newValue in
                    updateNeverTranslatePreference(newValue)
                }
        }
    }

    // MARK: - Translated State

    @ViewBuilder
    private var translatedStateContent: some View {
        Label("Page Translated", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.green)

        if let original = webPage?.originalLanguage,
           let translated = webPage?.translatedToLanguage {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Original", value: TranslationManager.displayName(for: original))
                LabeledContent("Translated to", value: TranslationManager.displayName(for: translated))
            }
            .font(.subheadline)
        }

        Divider()

        Button {
            guard let webPage else { return }
            translationManager.restoreOriginalPage(webPage)
            dismiss()
        } label: {
            Text("View Original Page")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Actions

    private func checkAvailability() async {
        guard let source = detectedLanguage,
              let target = selectedTargetLanguage else {
            isAvailable = false
            return
        }

        isAvailable = await translationManager.canTranslate(from: source, to: target)
        needsDownload = await translationManager.needsDownload(from: source, to: target)
    }

    private func startTranslation() async {
        guard let webPage,
              let source = detectedLanguage,
              let target = selectedTargetLanguage else { return }

        isPreparingTranslation = true
        isTranslationInProgress = true

        do {
            let requests = try await translationManager.prepareTranslationRequests(for: webPage)
            pendingRequests = requests
            translationConfiguration = TranslationSession.Configuration(source: source, target: target)
            dismiss()
        } catch {
            Logger.error("Failed to prepare translation: \(error.localizedDescription)", category: Logger.tabs)
            isPreparingTranslation = false
            isTranslationInProgress = false
        }
    }

    // MARK: - Preferences

    private func loadSitePreferences() {
        guard let url = webPage?.url else { return }
        let settings = siteSettingsManager.settings(for: url)

        if let source = detectedLanguage,
           let languageCode = source.languageCode?.identifier {
            alwaysTranslateLanguage = settings?.alwaysTranslateLanguages.contains(languageCode) ?? false
        }

        neverTranslateSite = settings?.translationPreference == .never
    }

    private func updateAlwaysTranslatePreference(_ enabled: Bool, for language: Locale.Language) {
        guard let url = webPage?.url,
              let languageCode = language.languageCode?.identifier,
              let settings = siteSettingsManager.settingsOrCreate(for: url) else { return }

        if enabled {
            if !settings.alwaysTranslateLanguages.contains(languageCode) {
                settings.alwaysTranslateLanguages.append(languageCode)
            }
        } else {
            settings.alwaysTranslateLanguages.removeAll { $0 == languageCode }
        }
        settings.markModified()
        siteSettingsManager.save(settings)
    }

    private func updateNeverTranslatePreference(_ enabled: Bool) {
        guard let url = webPage?.url,
              let settings = siteSettingsManager.settingsOrCreate(for: url) else { return }

        settings.translationPreference = enabled ? .never : .ask
        settings.markModified()
        siteSettingsManager.save(settings)

        if enabled {
            alwaysTranslateLanguage = false
        }
    }
}
