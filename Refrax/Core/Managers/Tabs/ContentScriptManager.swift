import AppKit
import Foundation
import Observation
import WebKit

/// Manages content script injection and queries for web pages.
///
/// `ContentScriptManager` provides:
/// - Content blocking rules
/// - Global Privacy Control (GPC) DOM signal injection
/// - Form data detection via JavaScript queries
///
/// ## Overview
///
/// Form data state is queried on-demand (e.g., before closing a tab) rather than
/// continuously monitored. Media playback and capture states are handled natively
/// by WebKit's `mediaPlaybackState()`, `cameraCaptureState`, and `microphoneCaptureState`.
///
/// Autofill is handled by ``AutoFillManager`` using WebKit's `_WKInputDelegate` API.
///
/// ## Usage
///
/// ```swift
/// // During app initialization
/// await ContentScriptManager.shared.setup()
///
/// // Query form data before closing
/// let hasFormData = await ContentScriptManager.shared.queryFormDataState(for: webPage)
/// ```
final class ContentScriptManager {
    unowned let state: BrowserState

    // MARK: - Configuration

    /// Content world for scripts (isolated from page scripts).
    private let scriptWorld = WKContentWorld.world(name: "RefraxScripts")

    // MARK: - Content Blocking

    /// The content blocking manager for dynamic filter lists.
    let contentBlockingManager = ContentBlockingManager()

    // MARK: - State

    private var isSetUp = false
    private var thirdPartyCookieRuleList: WKContentRuleList?
    private var thirdPartyCookieBlockingEnabled = false
    private var gpcScriptID: UUID?
    private var gpcMessageHandler: GPCMessageHandler?
    private var gpcTelemetryHosts: Set<String> = []
    private var settingsObservationTask: Task<Void, Never>?

    // Content script IDs
    private var contentProtectionScriptID: UUID?
    private var darkModeScriptID: UUID?
    private var pageFilterScriptID: UUID?
    private var colorBlindnessScriptID: UUID?
    private var backgroundRemovalScriptID: UUID?
    private var credentialDetectionScriptID: UUID?

    // Web behavior protection script IDs
    private var beforeUnloadScriptID: UUID?
    private var scrollHijackingScriptID: UUID?
    private var videoControlsScriptID: UUID?
    private var hideSignInPromptsScriptID: UUID?

    // Credential submission detection
    private var credentialSubmitHandler: CredentialSubmitHandler?

    // Web store integration
    private var webStoreEarlyScriptID: UUID?
    private var webStoreScriptID: UUID?
    private var webStoreInstallHandler: WebStoreInstallHandler?

    // Appearance observation
    private var appearanceObserver: NSKeyValueObservation?

    // MARK: - Rule List Templates

    /// Content blocker rules that disable third-party cookie storage.
    ///
    /// Design rationale:
    /// - Use WebKit's content blocker engine so enforcement happens in the
    ///   network layer without injecting scripts into pages.
    /// - Keep the rule list minimal to avoid overhead or unintended blocking.
    private static let thirdPartyCookieRuleListJSON = """
    [
      {
        "trigger": {
          "url-filter": ".*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block-cookies"
        }
      }
    ]
    """

    /// JavaScript for the Global Privacy Control (GPC) DOM signal.
    ///
    /// Design rationale:
    /// - Define `navigator.globalPrivacyControl` at document start so sites can
    ///   read it synchronously during early page scripts.
    /// - Return `false` when disabled rather
    ///   than omitting the property, to reduce site variability.
    private static func gpcUserScriptSource(isEnabled: Bool, telemetryEnabled: Bool) -> String {
        let value = isEnabled ? "true" : "false"
        let telemetry = telemetryEnabled ? "true" : "false"
        return """
        (() => {
          try {
            const value = \(value);
            const telemetryEnabled = \(telemetry);
            const descriptor = Object.getOwnPropertyDescriptor(Navigator.prototype, "globalPrivacyControl");
            if (descriptor && descriptor.configurable === false) return;
            Object.defineProperty(Navigator.prototype, "globalPrivacyControl", {
              get: () => {
                try {
                  if (value && telemetryEnabled && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(Constants.App.gpcMessageHandlerName)) {
                    if (!window.__refraxGPCReported) {
                      window.webkit.messageHandlers.\(Constants.App.gpcMessageHandlerName).postMessage({
                        url: location.href
                      });
                      window.__refraxGPCReported = true;
                    }
                  }
                } catch {}
                return value;
              },
              configurable: true,
              enumerable: true
            });
          } catch {}
        })();
        """
    }

    /// JavaScript for detecting credential submissions in login forms.
    ///
    /// Design rationale:
    /// - Many modern login forms use JavaScript (fetch/XHR) instead of
    ///   traditional HTML form submission, bypassing WebKit's native
    ///   `_WKInputDelegate` form submission callbacks.
    /// - This script intercepts both traditional form submissions and
    ///   button clicks that may trigger AJAX logins.
    /// - Credentials are only captured when both username and password
    ///   fields are present and filled to avoid false positives.
    private static let credentialDetectionScript = """
    (() => {
      if (window.__refraxCredentialDetectorInstalled) return;
      window.__refraxCredentialDetectorInstalled = true;
    
      const handlerName = '\(Constants.App.credentialSubmitHandlerName)';
    
      function findCredentials(form) {
        let username = null;
        let password = null;
    
        const inputs = form ? form.querySelectorAll('input') : document.querySelectorAll('input');
        for (const input of inputs) {
          const type = (input.type || '').toLowerCase();
          const name = (input.name || '').toLowerCase();
          const id = (input.id || '').toLowerCase();
          const autocomplete = (input.autocomplete || '').toLowerCase();
    
          if (type === 'password' && input.value) {
            password = input.value;
          } else if (!password && type === 'hidden' && (name.includes('password') || id.includes('password'))) {
            // Some forms use hidden fields for password
          } else if (type === 'text' || type === 'email' || type === 'tel' || type === '') {
            if (autocomplete.includes('username') || autocomplete.includes('email') ||
                name.includes('user') || name.includes('email') || name.includes('login') ||
                id.includes('user') || id.includes('email') || id.includes('login')) {
              if (input.value && !username) {
                username = input.value;
              }
            }
          }
        }
    
        return { username, password };
      }
    
      function postCredentials(username, password) {
        if (!username || !password) return;
        if (!window.webkit?.messageHandlers?.[handlerName]) return;
    
        try {
          window.webkit.messageHandlers[handlerName].postMessage({
            username: username,
            password: password,
            url: location.href
          });
        } catch (e) {}
      }
    
      // Intercept form submissions
      document.addEventListener('submit', (e) => {
        const form = e.target;
        if (form.tagName !== 'FORM') return;
    
        const creds = findCredentials(form);
        postCredentials(creds.username, creds.password);
      }, true);
    
      // Intercept button clicks that might trigger AJAX login
      document.addEventListener('click', (e) => {
        const target = e.target.closest('button, input[type="submit"], [role="button"]');
        if (!target) return;
    
        const form = target.closest('form');
        if (!form) return;
    
        // Check if form has password field
        const hasPassword = form.querySelector('input[type="password"]');
        if (!hasPassword) return;
    
        // Delay slightly to let any form validation run
        setTimeout(() => {
          const creds = findCredentials(form);
          postCredentials(creds.username, creds.password);
        }, 100);
      }, true);
    })();
    """

    // MARK: - Initialization

    init(state: BrowserState) {
        self.state = state
    }

    // MARK: - Setup

    /// Performs async setup of content blocking rules.
    ///
    /// Call this during app initialization before creating any WebPages.
    func setup() async {
        guard !isSetUp else { return }
        isSetUp = true

        await setupContentBlocking()
        await updateThirdPartyCookieBlocking(isEnabled: state.settings.blockThirdPartyCookies)
        updateGlobalPrivacyControl(
            isEnabled: state.settings.enableGlobalPrivacyControl,
            telemetryEnabled: state.settings.enableGPCTelemetry,
        )
        updateContentProtectionBypass(isEnabled: state.settings.contentProtectionBypassEnabled)
        updateDarkModeScript(preference: state.settings.webpageDarkMode)
        updatePageFilters(
            filter: state.settings.pageFilter,
            bgMode: state.settings.backgroundRemovalMode,
            preserveMedia: state.settings.preserveMediaInFilter,
        )
        updateWebBehaviorProtections()
        updateHideSignInPrompts(isEnabled: state.settings.hideSignInPrompts)
        setupCredentialDetection()
        setupWebStoreIntegration()
        startSettingsObservation()
        startAppearanceObservation()

        Logger.info("ContentScriptManager setup complete", category: Logger.tabs)
    }

    // MARK: - Content Blocking

    private func setupContentBlocking() async {
        // Use the new dynamic content blocking manager
        await contentBlockingManager.setup(
            userContentController: state.webPageConfiguration.userContentController,
        )
        state.setContentBlockingReady(true)
        Logger.info("Content blocker enabled via ContentBlockingManager", category: Logger.tabs)
    }

    private func attachThirdPartyCookieRuleList(_ ruleList: WKContentRuleList) {
        if let existing = thirdPartyCookieRuleList {
            state.webPageConfiguration.userContentController.remove(existing)
        }

        thirdPartyCookieRuleList = ruleList
        state.webPageConfiguration.userContentController.add(ruleList)
        Logger.info("Third-party cookie blocking enabled", category: Logger.tabs)
    }

    private func compileRules(json: String, id: String) async throws -> WKContentRuleList? {
        try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: id,
            encodedContentRuleList: json,
        )
    }

    // MARK: - Third-Party Cookie Blocking

    /// Enables or disables third-party cookie blocking at runtime.
    ///
    /// WebKit applies content rule lists immediately to the shared
    /// `WKUserContentController`, so existing WebPages pick up the change
    /// without requiring re-creation.
    func updateThirdPartyCookieBlocking(isEnabled: Bool) async {
        guard isSetUp else { return }
        guard isEnabled != thirdPartyCookieBlockingEnabled else { return }

        if isEnabled {
            thirdPartyCookieBlockingEnabled = await enableThirdPartyCookieBlocking()
        } else {
            disableThirdPartyCookieBlocking()
            thirdPartyCookieBlockingEnabled = false
        }
    }

    private func enableThirdPartyCookieBlocking() async -> Bool {
        let id = Constants.App.thirdPartyCookieRuleListID
        let store = WKContentRuleListStore.default()

        if let cached = try? await store?.contentRuleList(forIdentifier: id) {
            attachThirdPartyCookieRuleList(cached)
            return true
        }

        do {
            if let ruleList = try await compileRules(json: Self.thirdPartyCookieRuleListJSON, id: id) {
                attachThirdPartyCookieRuleList(ruleList)
                return true
            } else {
                Logger.error("Third-party cookie rule list compile failed with no error", category: Logger.tabs)
            }
        } catch {
            Logger.error("Third-party cookie rule list compile failed: \(error)", category: Logger.tabs)
        }

        return false
    }

    private func disableThirdPartyCookieBlocking() {
        guard let ruleList = thirdPartyCookieRuleList else { return }
        state.webPageConfiguration.userContentController.remove(ruleList)
        thirdPartyCookieRuleList = nil
        Logger.info("Third-party cookie blocking disabled", category: Logger.tabs)
    }

    // MARK: - Settings Observation

    private func startSettingsObservation() {
        guard settingsObservationTask == nil else { return }

        let settings = state.settings
        let changes = Observations {
            (
                settings.blockThirdPartyCookies,
                settings.enableGlobalPrivacyControl,
                settings.enableGPCTelemetry,
                settings.contentProtectionBypassEnabled,
                settings.webpageDarkMode,
                settings.pageFilter,
                settings.backgroundRemovalMode,
                settings.preserveMediaInFilter,
                settings.disableBeforeUnloadAlerts,
                settings.disableScrollHijacking,
                settings.forceNativeVideoControls,
                settings.defaultVideoSpeed,
                settings.hideSignInPrompts,
            )
        }

        settingsObservationTask = Task { [weak self] in
            guard let self else { return }
            for await (
                blockCookies,
                gpcEnabled,
                gpcTelemetry,
                contentProtection,
                darkMode,
                pageFilter,
                bgRemoval,
                preserveMedia,
                beforeUnload,
                scrollHijacking,
                videoControls,
                videoSpeed,
                hideSignIn,
            ) in changes {
                await updateThirdPartyCookieBlocking(isEnabled: blockCookies)
                updateGlobalPrivacyControl(isEnabled: gpcEnabled, telemetryEnabled: gpcTelemetry)
                updateContentProtectionBypass(isEnabled: contentProtection)
                updateDarkModeScript(preference: darkMode)
                updatePageFilters(filter: pageFilter, bgMode: bgRemoval, preserveMedia: preserveMedia)
                updateWebBehaviorProtections(
                    beforeUnload: beforeUnload,
                    scrollHijacking: scrollHijacking,
                    videoControls: videoControls,
                    videoSpeed: videoSpeed,
                )
                updateHideSignInPrompts(isEnabled: hideSignIn)
            }
        }
    }

    private func startAppearanceObservation() {
        // Observe effectiveAppearance changes via KVO
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, self.state.settings.webpageDarkMode == .followSystem else { return }
                self.updateDarkModeScript(preference: .followSystem)
            }
        }
    }

    // MARK: - Global Privacy Control (GPC)

    private func updateGlobalPrivacyControl(isEnabled: Bool, telemetryEnabled: Bool) {
        updateGPCTelemetryHandler(isEnabled: telemetryEnabled)

        // Unregister previous GPC script if any
        if let id = gpcScriptID {
            state.scriptRegistry.unregister(id: id)
            gpcScriptID = nil
        }

        // Register new GPC script with high priority (runs early)
        let script = WKUserScript(
            source: Self.gpcUserScriptSource(isEnabled: isEnabled, telemetryEnabled: telemetryEnabled),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
        )
        gpcScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "gpc"),
            priority: ScriptRegistry.Priority.system,
        )

        rebuildUserScripts()
        Logger.info("Global Privacy Control script updated (enabled: \(isEnabled))", category: Logger.tabs)
    }

    private func updateGPCTelemetryHandler(isEnabled: Bool) {
        let controller = state.webPageConfiguration.userContentController

        if isEnabled {
            if gpcMessageHandler == nil {
                let handler = GPCMessageHandler { [weak self] urlString in
                    self?.recordGPCUsage(urlString: urlString)
                }
                gpcMessageHandler = handler
                controller.add(handler, name: Constants.App.gpcMessageHandlerName)
            }
        } else if gpcMessageHandler != nil {
            controller.removeScriptMessageHandler(forName: Constants.App.gpcMessageHandlerName)
            gpcMessageHandler = nil
            gpcTelemetryHosts.removeAll()
        }
    }
    private func rebuildUserScripts() {
        // ScriptRegistry is now the single source of truth for user scripts.
        // Apply all registered scripts to the controller in priority order.
        state.scriptRegistry.apply(to: state.webPageConfiguration.userContentController)
    }

    private func recordGPCUsage(urlString: String?) {
        guard let urlString,
              let url = URL(string: urlString),
              let host = url.host?.lowercased()
        else {
            return
        }

        // Log once per host to keep telemetry lightweight.
        if gpcTelemetryHosts.insert(host).inserted {
            Logger.info("GPC signal observed for host: \(host)", category: Logger.data)
        }
    }

    // MARK: - Content Protection Bypass

    /// Updates content protection bypass script based on global settings.
    private func updateContentProtectionBypass(isEnabled: Bool) {
        guard isSetUp else { return }

        // Unregister previous script if any
        if let id = contentProtectionScriptID {
            state.scriptRegistry.unregister(id: id)
            contentProtectionScriptID = nil
        }

        guard isEnabled else {
            rebuildUserScripts()
            return
        }

        // Register content protection bypass script
        let script = WKUserScript(
            source: ContentProtectionBypassScript.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
        )
        contentProtectionScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "contentProtectionBypass"),
            priority: ScriptRegistry.Priority.system,
        )

        rebuildUserScripts()
        Logger.info("Content protection bypass updated (enabled: \(isEnabled))", category: Logger.tabs)
    }

    // MARK: - Web Behavior Protection

    /// Updates all web behavior protection scripts.
    ///
    /// Called during setup and when any related setting changes.
    private func updateWebBehaviorProtections() {
        updateWebBehaviorProtections(
            beforeUnload: state.settings.disableBeforeUnloadAlerts,
            scrollHijacking: state.settings.disableScrollHijacking,
            videoControls: state.settings.forceNativeVideoControls,
            videoSpeed: state.settings.defaultVideoSpeed,
        )
    }

    /// Updates web behavior protection scripts based on specific values.
    private func updateWebBehaviorProtections(
        beforeUnload: Bool,
        scrollHijacking: Bool,
        videoControls: Bool,
        videoSpeed: Double,
    ) {
        guard isSetUp else { return }

        // Update all scripts, deferring rebuild until the end
        updateBeforeUnloadScript(isEnabled: beforeUnload)
        updateScrollHijackingScript(isEnabled: scrollHijacking)
        updateVideoControlsScript(isEnabled: videoControls, speed: videoSpeed)
        rebuildUserScripts()
    }

    private func updateBeforeUnloadScript(isEnabled: Bool) {
        if let id = beforeUnloadScriptID {
            state.scriptRegistry.unregister(id: id)
            beforeUnloadScriptID = nil
        }
        guard isEnabled else { return }

        beforeUnloadScriptID = state.scriptRegistry.register(
            WKUserScript(
                source: WebBehaviorProtectionScripts.beforeUnloadBlock,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
            ),
            source: .system(name: "beforeUnloadBlock"),
            priority: ScriptRegistry.Priority.system,
        )
    }

    private func updateScrollHijackingScript(isEnabled: Bool) {
        if let id = scrollHijackingScriptID {
            state.scriptRegistry.unregister(id: id)
            scrollHijackingScriptID = nil
        }
        guard isEnabled else { return }

        scrollHijackingScriptID = state.scriptRegistry.register(
            WKUserScript(
                source: WebBehaviorProtectionScripts.scrollHijackingBlock,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
            ),
            source: .system(name: "scrollHijackingBlock"),
            priority: ScriptRegistry.Priority.system,
        )
    }

    private func updateVideoControlsScript(isEnabled: Bool, speed: Double) {
        if let id = videoControlsScriptID {
            state.scriptRegistry.unregister(id: id)
            videoControlsScriptID = nil
        }
        guard isEnabled else { return }

        videoControlsScriptID = state.scriptRegistry.register(
            WKUserScript(
                source: WebBehaviorProtectionScripts.videoControlsWithSpeed(speed: speed),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
            ),
            source: .system(name: "videoControls"),
            priority: ScriptRegistry.Priority.system,
        )
    }

    // MARK: - Sign-In Prompt Hiding

    /// Updates sign-in prompt hiding script.
    private func updateHideSignInPrompts(isEnabled: Bool) {
        // Unregister previous script if any
        if let id = hideSignInPromptsScriptID {
            state.scriptRegistry.unregister(id: id)
            hideSignInPromptsScriptID = nil
        }

        guard isEnabled else {
            rebuildUserScripts()
            return
        }

        let script = WKUserScript(
            source: WebBehaviorProtectionScripts.hideSignInPrompts,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
        )
        hideSignInPromptsScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "hideSignInPrompts"),
            priority: ScriptRegistry.Priority.system,
        )

        rebuildUserScripts()
        Logger.debug("Sign-in prompt hiding updated (enabled: \(isEnabled))", category: Logger.tabs)
    }

    // MARK: - Dark Mode

    /// Updates dark mode script based on preference and system appearance.
    private func updateDarkModeScript(preference: DarkModePreference) {
        guard isSetUp else { return }

        // Unregister previous script if any
        if let id = darkModeScriptID {
            state.scriptRegistry.unregister(id: id)
            darkModeScriptID = nil
        }

        let shouldApply: Bool = switch preference {
        case .off: false
        case .followSystem: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua]) == .darkAqua
        case .always: true
        }

        guard shouldApply else {
            rebuildUserScripts()
            return
        }

        // Register dark mode detection script
        let preserveMedia = state.settings.preserveMediaInFilter
        let script = WKUserScript(
            source: DarkModeScript.detectionScript(preserveMedia: preserveMedia),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
        )
        darkModeScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "darkMode"),
            priority: ScriptRegistry.Priority.system,
        )

        rebuildUserScripts()
        Logger.info("Dark mode script updated (preference: \(preference))", category: Logger.tabs)
    }

    // MARK: - Page Filters

    /// Updates page filter scripts based on settings.
    private func updatePageFilters(
        filter: PageFilter,
        bgMode: BackgroundRemovalMode,
        preserveMedia: Bool,
    ) {
        guard isSetUp else { return }

        // Unregister existing scripts
        [pageFilterScriptID, colorBlindnessScriptID, backgroundRemovalScriptID]
            .compactMap(\.self)
            .forEach { state.scriptRegistry.unregister(id: $0) }

        pageFilterScriptID = nil
        colorBlindnessScriptID = nil
        backgroundRemovalScriptID = nil

        // Page filter CSS injection
        let filterScript = PageFilterCSS.injectionScript(for: filter, preserveMedia: preserveMedia)
        if !filterScript.isEmpty {
            let script = WKUserScript(
                source: filterScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
            )
            pageFilterScriptID = state.scriptRegistry.register(
                script,
                source: .system(name: "pageFilter"),
                priority: ScriptRegistry.Priority.system,
            )
        }

        // Color blindness SVG filter injection
        if filter.requiresSVGFilters {
            let script = WKUserScript(
                source: ColorBlindnessFilters.injectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
            )
            colorBlindnessScriptID = state.scriptRegistry.register(
                script,
                source: .system(name: "colorBlindnessFilters"),
                priority: ScriptRegistry.Priority.system,
            )
        }

        // Background removal CSS injection
        let bgScript = BackgroundRemovalCSS.injectionScript(for: bgMode)
        if !bgScript.isEmpty {
            let script = WKUserScript(
                source: bgScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
            )
            backgroundRemovalScriptID = state.scriptRegistry.register(
                script,
                source: .system(name: "backgroundRemoval"),
                priority: ScriptRegistry.Priority.system,
            )
        }

        rebuildUserScripts()
        Logger.info(
            "Page filters updated (filter: \(filter), bgMode: \(bgMode))",
            category: Logger.tabs,
        )
    }

    // MARK: - Credential Detection

    /// Sets up credential submission detection for password saving.
    ///
    /// This supplements WebKit's `_WKInputDelegate.willSubmitFormValues` which
    /// only fires for traditional HTML form submissions. Modern sites often
    /// use JavaScript (fetch/XHR) for login, which bypasses that delegate.
    private func setupCredentialDetection() {
        let controller = state.webPageConfiguration.userContentController

        // Register message handler
        let handler = CredentialSubmitHandler { [weak self] username, password, urlString in
            self?.handleCredentialSubmission(username: username, password: password, urlString: urlString)
        }
        credentialSubmitHandler = handler
        controller.add(handler, name: Constants.App.credentialSubmitHandlerName)

        // Register the detection script
        let script = WKUserScript(
            source: Self.credentialDetectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
        )
        credentialDetectionScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "credentialDetection"),
            priority: ScriptRegistry.Priority.system,
        )

        rebuildUserScripts()
        Logger.info("Credential detection script installed", category: Logger.tabs)
    }

    /// Handles credential submission detected by JavaScript.
    private func handleCredentialSubmission(username: String, password: String, urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else {
            Logger.debug("Credential submission ignored - invalid URL", category: Logger.autoFill)
            return
        }

        // Validate URL allows autofill (HTTPS only)
        guard url.allowsAutoFill else {
            Logger.debug("Credential submission ignored - non-HTTPS URL", category: Logger.autoFill)
            return
        }

        // Forward to AutoFillManager via the shared state
        state.autoFillManager.handleCredentialSubmissionFromJS(
            username: username,
            password: password,
            url: url,
        )
    }

    // MARK: - Web Store Integration

    /// Sets up content script and message handler for Chrome Web Store
    /// and Firefox Add-ons integration.
    ///
    /// Injects a script that replaces "Add to Chrome" / "Add to Firefox"
    /// buttons with "Add to Refrax" and intercepts clicks to trigger
    /// native extension installation.
    private func setupWebStoreIntegration() {
        let controller = state.webPageConfiguration.userContentController

        // Register message handler
        let handler = WebStoreInstallHandler { [weak self] store, extensionID, name, webView in
            self?.handleWebStoreInstall(store: store, extensionID: extensionID, name: name, webView: webView)
        }
        webStoreInstallHandler = handler
        controller.add(handler, name: WebStoreIntegrationScript.messageHandlerName)

        // Register early CSS override at document start (prevents white flash on CWS)
        let earlyScript = WKUserScript(
            source: WebStoreIntegrationScript.earlyStyleScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
        )
        webStoreEarlyScriptID = state.scriptRegistry.register(
            earlyScript,
            source: .system(name: "webStoreEarlyStyle"),
            priority: ScriptRegistry.Priority.system,
        )

        // Register the main content script at document end
        let script = WKUserScript(
            source: WebStoreIntegrationScript.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
        )
        webStoreScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "webStoreIntegration"),
            priority: ScriptRegistry.Priority.system,
        )

        rebuildUserScripts()
        Logger.info("Web store integration script installed", category: Logger.extensions)
    }

    /// Handles an extension install request from the web store content script.
    private func handleWebStoreInstall(store: String, extensionID: String, name: String?, webView: WKWebView) {
        guard let webStore = WebStore(rawValue: store) else {
            Logger.warning("Unknown web store: \(store)", category: Logger.extensions)
            return
        }

        // Check if already installed
        let existingSource: ExtensionSource = switch webStore {
        case .chrome: .chromeWebStore(extensionID: extensionID)
        case .firefox: .firefoxAddons(extensionID: extensionID)
        }

        if state.extensionManager.installedExtensions.contains(where: { $0.source == existingSource }) {
            Logger.info(
                "Extension '\(name ?? extensionID)' is already installed",
                category: Logger.extensions,
            )
            updateWebStoreButton(status: "already_installed", webView: webView)
            return
        }

        Logger.info(
            "Web store install requested: \(name ?? extensionID) from \(store)",
            category: Logger.extensions,
        )

        Task {
            do {
                let installed = try await state.extensionManager.installFromWebStore(
                    extensionID: extensionID,
                    store: webStore,
                )
                Logger.info(
                    "Successfully installed '\(installed.displayName)' from \(store) web store",
                    category: Logger.extensions,
                )
                updateWebStoreButton(status: "installed", webView: webView)
            } catch {
                Logger.error(
                    "Failed to install extension '\(extensionID)' from \(store): \(error)",
                    category: Logger.extensions,
                )
                updateWebStoreButton(status: "error", webView: webView)
            }
        }
    }

    /// Updates the web store install button via JavaScript evaluation.
    private func updateWebStoreButton(status: String, webView: WKWebView) {
        let js = "window.__refraxUpdateInstallButton && window.__refraxUpdateInstallButton('\(status)')"
        webView.evaluateJavaScript(js)
    }

    // MARK: - Form Data Queries

    /// Queries whether a page has unsaved form data.
    ///
    /// Checks input fields, textareas, selects, and contenteditable elements
    /// for values that differ from their defaults. Includes same-origin iframes
    /// (cross-origin iframes cannot be accessed due to browser security).
    ///
    /// - Parameter webPage: The page to query.
    /// - Returns: Whether the page has unsaved form data.
    func queryFormDataState(for webPage: WebPage) async -> Bool {
        do {
            let result = try await webPage.callJavaScript(
                JavaScriptSnippets.hasUnsavedFormData,
                in: nil,
                contentWorld: scriptWorld,
            )
            return result as? Bool ?? false
        } catch {
            return false
        }
    }
}

// MARK: - Script Message Handling

private final class GPCMessageHandler: NSObject, WKScriptMessageHandler {
    private let onMessage: (String?) -> Void

    init(onMessage: @escaping (String?) -> Void) {
        self.onMessage = onMessage
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        let urlString: String? = if let body = message.body as? [String: Any] {
            body["url"] as? String
        } else if let body = message.body as? String {
            body
        } else {
            nil
        }

        onMessage(urlString)
    }
}

/// Message handler for credential submission detection.
///
/// Receives messages from the credential detection JavaScript when
/// a login form is submitted (either via traditional form submission
/// or AJAX/fetch).
private final class CredentialSubmitHandler: NSObject, WKScriptMessageHandler {
    private let onCredentials: (String, String, String?) -> Void

    /// Creates a handler with a callback for credential submissions.
    ///
    /// - Parameter onCredentials: Callback with (username, password, url).
    init(onCredentials: @escaping (String, String, String?) -> Void) {
        self.onCredentials = onCredentials
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let username = body["username"] as? String,
              let password = body["password"] as? String
        else {
            return
        }

        let urlString = body["url"] as? String
        onCredentials(username, password, urlString)
    }
}

/// Message handler for web store extension installation.
///
/// Receives messages from the web store integration script when
/// the user clicks "Add to Refrax" on Chrome Web Store or Firefox Add-ons.
private final class WebStoreInstallHandler: NSObject, WKScriptMessageHandler {
    private let onInstall: (String, String, String?, WKWebView) -> Void

    /// Creates a handler with a callback for install requests.
    ///
    /// - Parameter onInstall: Callback with (store, extensionID, name, webView).
    init(onInstall: @escaping (String, String, String?, WKWebView) -> Void) {
        self.onInstall = onInstall
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let store = body["store"] as? String,
              let extensionID = body["extensionID"] as? String,
              let webView = message.webView
        else {
            return
        }

        let name = body["name"] as? String
        onInstall(store, extensionID, name, webView)
    }
}
