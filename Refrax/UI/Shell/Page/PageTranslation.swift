import SwiftUI
@preconcurrency import Translation

/// One page's translation as its presenter sees it: the language the page is in, whether to
/// offer Translate, and the session that translates it.
///
/// A presenter owns one, attaches ``SwiftUI/View/pageTranslation(_:for:)`` to a view that
/// stays on screen while the page does, and shows ``TranslationPopoverContent`` from its
/// control. The session runs in that view's `.translationTask`.
@Observable
final class PageTranslation {
    /// The page this translation follows.
    fileprivate(set) var webPage: WebPage?
    fileprivate(set) var detectedLanguage: Locale.Language?
    /// The session the presenter's `.translationTask` runs; setting it starts a translation.
    var configuration: TranslationSession.Configuration?
    var pendingRequests: [TranslationSession.Request] = []
    /// A translation is being prepared or run; the control waits for it.
    var isInProgress = false
    @ObservationIgnored private var hasAutoTranslated = false
    @ObservationIgnored private var isCheckingLanguage = false

    var isTranslated: Bool {
        webPage?.isTranslated == true
    }

    var isTranslating: Bool {
        webPage?.isTranslating == true
    }

    /// The page's language, as detected here or earlier by another presenter.
    var sourceLanguage: Locale.Language? {
        detectedLanguage ?? webPage?.detectedLanguage
    }

    /// Translate is offered: the page is translated, translating, or in a language other than
    /// the person's.
    func isRelevant(targeting target: Locale.Language) -> Bool {
        if isTranslated || isTranslating {
            return true
        }
        guard let sourceLanguage else { return false }
        return sourceLanguage.languageCode != target.languageCode
    }

    fileprivate func follow(_ page: WebPage?) {
        guard page !== webPage else { return }
        webPage = page
        detectedLanguage = nil
        hasAutoTranslated = false
    }

    fileprivate func pageChangedAddress(from oldURL: URL?, manager: TranslationManager) {
        if let oldURL {
            manager.clearCache(for: oldURL)
        }
        hasAutoTranslated = false
        detectedLanguage = nil
    }

    fileprivate func translationEnded() {
        pendingRequests = []
        configuration = nil
        isInProgress = false
    }

    /// Detects the page's language and translates it when the site or the language is set to
    /// translate automatically.
    fileprivate func detectLanguage(manager: TranslationManager, siteSettings: SiteSettingsManager) async {
        guard let webPage, !isCheckingLanguage else { return }
        isCheckingLanguage = true
        defer { isCheckingLanguage = false }

        detectedLanguage = await manager.detectPageLanguage(webPage: webPage)
        webPage.detectedLanguage = detectedLanguage
        await translateAutomatically(manager: manager, siteSettings: siteSettings)
    }

    private func translateAutomatically(manager: TranslationManager, siteSettings: SiteSettingsManager) async {
        guard let webPage, let detected = detectedLanguage, !hasAutoTranslated, let url = webPage.url,
              !webPage.isTranslated, !webPage.isTranslating, !isInProgress else { return }

        let target = manager.targetLanguage
        guard detected.languageCode != target.languageCode else { return }

        let settings = siteSettings.settings(for: url)
        switch settings?.translationPreference {
        case .always:
            break
        case .never:
            return
        default:
            guard let languageCode = detected.languageCode?.identifier,
                  settings?.alwaysTranslateLanguages.contains(languageCode) == true else { return }
        }
        guard await manager.canTranslate(from: detected, to: target) else { return }

        hasAutoTranslated = true
        isInProgress = true
        do {
            pendingRequests = try await manager.prepareTranslationRequests(for: webPage)
            configuration = TranslationSession.Configuration(source: detected, target: target)
        } catch {
            Logger.error("Auto-translate failed: \(error.localizedDescription)", category: Logger.tabs)
            isInProgress = false
        }
    }

    /// Captures main-actor values for the translation session, which runs off the main actor.
    /// `requests` holds only strings; `page` and `manager` are used through their main-actor
    /// methods.
    private nonisolated struct WorkItem: @unchecked Sendable {
        let requests: [TranslationSession.Request]
        let page: WebPage
        let manager: TranslationManager
    }

    /// Runs the pending requests through the session and writes the result into the page.
    fileprivate func translate(with session: TranslationSession, manager: TranslationManager) async {
        let workItem = await MainActor.run {
            guard let webPage, !pendingRequests.isEmpty else { return nil as WorkItem? }
            return WorkItem(requests: pendingRequests, page: webPage, manager: manager)
        }
        guard let workItem else { return }
        let targetLanguage = session.targetLanguage

        do {
            let responses = try await session.translations(from: workItem.requests)
            try await workItem.manager.completeTranslation(responses: responses, for: workItem.page, targetLanguage: targetLanguage)
        } catch {
            Logger.error("Translation failed: \(error.localizedDescription)", category: Logger.tabs)
            await MainActor.run { workItem.manager.cancelTranslation(for: workItem.page) }
        }

        await MainActor.run { translationEnded() }
    }
}

extension View {
    /// Keeps `translation` on `webPage`: detects the language when a load finishes (or on
    /// appear, for a page that loaded while no presenter watched it) and runs the session.
    func pageTranslation(_ translation: PageTranslation, for webPage: WebPage?) -> some View {
        modifier(PageTranslationModifier(translation: translation, webPage: webPage))
    }
}

private struct PageTranslationModifier: ViewModifier {
    let translation: PageTranslation
    let webPage: WebPage?
    @Environment(TranslationManager.self) private var translationManager
    @Environment(SiteSettingsManager.self) private var siteSettings

    private enum Timing {
        /// Lets the page settle after a load before its text is sampled.
        static let settle: Duration = .milliseconds(300)
    }

    func body(content: Content) -> some View {
        content
            .translationTask(translation.configuration) { session in
                await translation.translate(with: session, manager: translationManager)
            }
            .task(id: webPage.map(ObjectIdentifier.init)) {
                translation.follow(webPage)
                guard let webPage, !webPage.isLoading, webPage.detectedLanguage == nil else { return }
                await translation.detectLanguage(manager: translationManager, siteSettings: siteSettings)
            }
            .onChange(of: webPage?.isTranslating) { wasTranslating, nowTranslating in
                if wasTranslating == true, nowTranslating == false {
                    translation.translationEnded()
                }
            }
            .onChange(of: webPage?.url) { oldURL, _ in
                translation.pageChangedAddress(from: oldURL, manager: translationManager)
            }
            .onChange(of: webPage?.isLoading) { wasLoading, isLoading in
                guard wasLoading == true, isLoading == false else { return }
                Task(name: "Detect page language") {
                    try? await Task.sleep(for: Timing.settle)
                    await translation.detectLanguage(manager: translationManager, siteSettings: siteSettings)
                }
            }
    }
}

// MARK: - Translation Popover Content

/// Translate's popover: the language picker and the per-site choices before a translation,
/// and the way back to the original after one.
struct TranslationPopoverContent: View {
    let translation: PageTranslation

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

    private var webPage: WebPage? {
        translation.webPage
    }

    private var detectedLanguage: Locale.Language? {
        translation.sourceLanguage
    }

    private var isTranslated: Bool {
        translation.isTranslated
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
        translation.isInProgress = true

        do {
            translation.pendingRequests = try await translationManager.prepareTranslationRequests(for: webPage)
            translation.configuration = TranslationSession.Configuration(source: source, target: target)
            dismiss()
        } catch {
            Logger.error("Failed to prepare translation: \(error.localizedDescription)", category: Logger.tabs)
            isPreparingTranslation = false
            translation.isInProgress = false
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
