import Foundation
import Observation
import WebKit

/// Manages automatic dismissal of cookie consent banners.
///
/// `AutoConsentManager` automatically detects and dismisses cookie consent
/// popups by clicking "reject all" or "necessary only" buttons. This provides
/// a privacy-respecting default without requiring user interaction on every site.
///
/// ## Design Rationale
///
/// - Uses community-maintained rulesets covering major CMPs (OneTrust, CookieBot, etc.)
/// - Prioritizes "reject all" over "accept" for privacy-first behavior
/// - Silent operation: no UI unless the user wants to configure it
/// - Per-site bypass via `SiteSettings.disableAutoConsent`
///
/// ## Integration
///
/// Scripts are injected via `ScriptRegistry` with `.system` source priority.
/// The manager registers a message handler to receive detection events from
/// the injected JavaScript.
///
/// ```swift
/// // During app setup
/// await AutoConsentManager.shared.setup()
///
/// // Check if enabled for a domain
/// let shouldInject = autoConsentManager.isEnabled(for: "example.com")
/// ```
@Observable
final class AutoConsentManager {
    /// Reference to browser state for script registry access.
    unowned let state: BrowserState

    // MARK: - State

    /// Whether auto-consent is globally enabled.
    ///
    /// Controlled by `BrowserSettings.enableAutoConsent`.
    private(set) var isEnabled: Bool = true

    /// Currently loaded ruleset.
    private(set) var ruleset: AutoConsentRuleset = .empty

    /// Last time the ruleset was updated from remote.
    private(set) var lastUpdateCheck: Date?

    // MARK: - Private State

    private var isSetUp = false
    private var scriptID: UUID?
    private var settingsObservationTask: Task<Void, Never>?

    /// Content world for scripts (isolated from page scripts).
    private static let scriptWorldName = "RefraxScripts"
    private let scriptWorld = WKContentWorld.world(name: scriptWorldName)

    // MARK: - Constants

    private static let messageHandlerName = "autoConsent"

    // MARK: - Initialization

    init(state: BrowserState) {
        self.state = state
    }

    // MARK: - Setup

    /// Performs async setup of the auto-consent system.
    ///
    /// Loads the bundled ruleset and registers scripts. Call this during
    /// app initialization before creating any WebPages.
    func setup() async {
        guard !isSetUp else { return }
        isSetUp = true

        ruleset = AutoConsentRuleset.loadBundled()
        isEnabled = state.settings.enableAutoConsent

        if isEnabled {
            registerScripts()
        }

        startSettingsObservation()
        Logger.info(
            "AutoConsentManager setup complete (enabled: \(isEnabled), rules: \(ruleset.rules.count))",
            category: Logger.tabs,
        )
    }

    // MARK: - Settings Observation

    private func startSettingsObservation() {
        guard settingsObservationTask == nil else { return }

        let settings = state.settings
        let changes = Observations { settings.enableAutoConsent }

        settingsObservationTask = Task { [weak self] in
            guard let self else { return }
            for await enabled in changes {
                await MainActor.run {
                    self.updateEnabledState(enabled)
                }
            }
        }
    }

    private func updateEnabledState(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            registerScripts()
        } else {
            unregisterScripts()
        }

        Logger.info("AutoConsent state changed (enabled: \(enabled))", category: Logger.tabs)
    }

    // MARK: - Script Management

    private func registerScripts() {
        guard scriptID == nil else { return }

        state.scriptChannels.register(Self.messageHandlerName, world: .isolated(name: Self.scriptWorldName)) { [weak self] message, _ in
            self?.handleMessage(message) ?? .null
        }

        // Create and register the user script
        let scriptSource = generateInjectionScript()
        let script = WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
            in: scriptWorld,
        )

        scriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "autoconsent"),
            priority: ScriptRegistry.Priority.system,
            world: scriptWorld,
        )

        rebuildUserScripts()
    }

    private func unregisterScripts() {
        if let id = scriptID {
            state.scriptRegistry.unregister(id: id)
            scriptID = nil
        }

        state.scriptChannels.unregister(Self.messageHandlerName)

        rebuildUserScripts()
    }

    private func rebuildUserScripts() {
        state.scriptRegistry.apply(to: state.webPageConfiguration.userContentController)
    }

    // MARK: - Script Generation

    private func generateInjectionScript() -> String {
        // Encode rules as JSON for the script
        let rulesJSON: String
        do {
            let data = try JSONEncoder().encode(ruleset.rules)
            rulesJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            Logger.error("Failed to encode AutoConsent rules: \(error)", category: Logger.tabs)
            rulesJSON = "[]"
        }

        return """
        (() => {
          'use strict';
        
          const RULES = \(rulesJSON);
          const HANDLER_NAME = '\(Self.messageHandlerName)';
        
          // Track whether autoconsent is enabled for this page (checked with native)
          let siteEnabled = null;
          let processed = false;
          let observer = null;
        
          // Utility: Check if element is visible
          function isVisible(el) {
            if (!el) return false;
            const style = getComputedStyle(el);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
            const rect = el.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          }
        
          // Utility: Find first visible element matching any selector
          function findVisible(selectors, root = document) {
            for (const sel of selectors) {
              try {
                const els = root.querySelectorAll(sel);
                for (const el of els) {
                  if (isVisible(el)) return el;
                }
              } catch (e) {
                // Invalid selector, skip
              }
            }
            return null;
          }
        
          // Utility: Check if any selector matches
          function anyMatch(selectors, root = document) {
            for (const sel of selectors) {
              try {
                if (root.querySelector(sel)) return true;
              } catch (e) {
                // Invalid selector, skip
              }
            }
            return false;
          }
        
          // Utility: Hide elements matching selectors
          function hideElements(selectors, root = document) {
            for (const sel of selectors) {
              try {
                const els = root.querySelectorAll(sel);
                for (const el of els) {
                  el.style.setProperty('display', 'none', 'important');
                }
              } catch (e) {
                // Invalid selector, skip
              }
            }
          }
        
          // Post message to native; resolves with native's reply
          function postMessage(type, data) {
            try {
              return window.webkit.messageHandlers[HANDLER_NAME].postMessage({ type, ...data });
            } catch (e) {
              return Promise.reject(e);
            }
          }
        
          // Process a single rule
          function processRule(rule) {
            // Check if CMP is detected
            if (!anyMatch(rule.detect)) return false;
        
            // Get the context (might be an iframe)
            let context = document;
            if (rule.frame) {
              try {
                const frame = document.querySelector(rule.frame);
                if (frame && frame.contentDocument) {
                  context = frame.contentDocument;
                } else {
                  return false; // Frame not accessible
                }
              } catch (e) {
                return false; // Cross-origin frame
              }
            }
        
            // Try reject buttons first
            let clicked = findVisible(rule.reject, context);
            let action = 'reject';
        
            // Fall back to accept if no reject found
            if (!clicked && rule.accept && rule.accept.length > 0) {
              clicked = findVisible(rule.accept, context);
              action = 'accept';
            }
        
            if (clicked) {
              clicked.click();
              postMessage('action', {
                rule: rule.name,
                action: action,
                url: location.href
              }).catch(() => {});
        
              // Hide any remaining overlay elements
              if (rule.hide && rule.hide.length > 0) {
                setTimeout(() => hideElements(rule.hide, context), 100);
              }
        
              return true;
            }
        
            // No clickable button found, just hide if possible
            if (rule.hide && rule.hide.length > 0) {
              hideElements(rule.hide, context);
              postMessage('action', {
                rule: rule.name,
                action: 'hide',
                url: location.href
              }).catch(() => {});
              return true;
            }
        
            return false;
          }
        
          // Main processing function
          function processRules() {
            if (siteEnabled === false) return; // Disabled for this site
            for (const rule of RULES) {
              const delay = rule.delay || 0;
              if (delay > 0) {
                setTimeout(() => processRule(rule), delay);
              } else {
                if (processRule(rule)) return; // Stop after first match
              }
            }
          }
        
          // Start processing after site check completes
          function startProcessing() {
            // Initial check after page load
            if (document.readyState === 'complete') {
              setTimeout(processRules, 500);
            } else {
              window.addEventListener('load', () => setTimeout(processRules, 500));
            }
        
            // Watch for dynamically added banners
            observer = new MutationObserver(() => {
              if (processed || siteEnabled === false) return;
              for (const rule of RULES) {
                if (anyMatch(rule.detect)) {
                  const delay = rule.delay || 500;
                  setTimeout(() => {
                    if (!processed && siteEnabled !== false && processRule(rule)) {
                      processed = true;
                      observer.disconnect();
                    }
                  }, delay);
                  break;
                }
              }
            });
        
            observer.observe(document.documentElement, {
              childList: true,
              subtree: true
            });
        
            // Clean up observer after 30 seconds
            setTimeout(() => observer && observer.disconnect(), 30000);
          }
        
          // Ask native whether autoconsent runs on this site; run if native can't answer
          postMessage('checkEnabled', {}).then(
            (enabled) => {
              siteEnabled = enabled !== false;
              if (siteEnabled) startProcessing();
            },
            () => {
              siteEnabled = true;
              startProcessing();
            },
          );
        })();
        """
    }

    // MARK: - Message Handling

    /// Answers `checkEnabled` with whether auto-consent runs on the sending frame's site, and logs actions.
    private func handleMessage(_ message: ScriptMessage) -> ScriptValue {
        switch message.body["type"]?.stringValue {
        case "checkEnabled":
            guard let url = message.frameURL else { return .bool(isEnabled) }
            return .bool(isEnabled(for: url))

        case "action":
            if let rule = message.body["rule"]?.stringValue,
               let action = message.body["action"]?.stringValue,
               let url = message.body["url"]?.stringValue {
                Logger.info("AutoConsent: \(action) via '\(rule)' on \(url)", category: Logger.tabs)
            }
            return .null

        default:
            return .null
        }
    }

    // MARK: - Per-Site Bypass

    /// Checks if auto-consent is enabled for a specific domain.
    ///
    /// Returns false if:
    /// - Auto-consent is globally disabled
    /// - The site has `disableAutoConsent` set to true
    ///
    /// - Parameter domain: The domain to check.
    /// - Returns: Whether auto-consent should run for this domain.
    func isEnabled(for domain: String) -> Bool {
        isEnabled && state.siteSettingsManager.settings(for: domain)?.disableAutoConsent != true
    }

    /// Checks if auto-consent is enabled for a URL.
    func isEnabled(for url: URL) -> Bool {
        guard let host = url.host else { return isEnabled }
        return isEnabled(for: host)
    }
}
