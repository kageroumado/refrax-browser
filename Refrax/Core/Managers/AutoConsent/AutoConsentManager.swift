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
    private var messageHandler: AutoConsentMessageHandler?
    private var settingsObservationTask: Task<Void, Never>?

    /// Content world for scripts (isolated from page scripts).
    private let scriptWorld = WKContentWorld.world(name: "RefraxScripts")

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

        // Register message handler
        let handler = AutoConsentMessageHandler { [weak self] event in
            self?.handleConsentEvent(event)
        }
        handler.siteSettingsManager = state.siteSettingsManager
        messageHandler = handler
        state.webPageConfiguration.userContentController.add(
            handler,
            contentWorld: scriptWorld,
            name: Self.messageHandlerName,
        )

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
        )

        rebuildUserScripts()
    }

    private func unregisterScripts() {
        if let id = scriptID {
            state.scriptRegistry.unregister(id: id)
            scriptID = nil
        }

        if messageHandler != nil {
            state.webPageConfiguration.userContentController.removeScriptMessageHandler(
                forName: Self.messageHandlerName,
                contentWorld: scriptWorld,
            )
            messageHandler = nil
        }

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
        
          // Post message to native
          function postMessage(type, data) {
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER_NAME]) {
                window.webkit.messageHandlers[HANDLER_NAME].postMessage({ type, ...data });
              }
            } catch (e) {}
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
              });
        
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
              });
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
        
          // Callback from native with enabled status
          window.__autoConsentCallback = function(enabled) {
            siteEnabled = enabled;
            if (enabled) {
              startProcessing();
            } else if (observer) {
              observer.disconnect();
            }
          };
        
          // Ask native if autoconsent is enabled for this site
          postMessage('checkEnabled', {});
        
          // Fallback: if native doesn't respond within 100ms, assume enabled
          setTimeout(() => {
            if (siteEnabled === null) {
              siteEnabled = true;
              startProcessing();
            }
          }, 100);
        })();
        """
    }

    // MARK: - Event Handling

    private func handleConsentEvent(_ event: AutoConsentEvent) {
        switch event {
        case let .action(ruleName, action, url):
            Logger.info(
                "AutoConsent: \(action) via '\(ruleName)' on \(url)",
                category: Logger.tabs,
            )
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

// MARK: - Event Types

enum AutoConsentEvent {
    case action(ruleName: String, action: String, url: String)
}

// MARK: - Message Handler

final class AutoConsentMessageHandler: NSObject, WKScriptMessageHandler {
    private let onEvent: (AutoConsentEvent) -> Void

    /// Site settings manager for per-site disable checking.
    ///
    /// Set when handler needs to respond to `checkEnabled` messages.
    weak var siteSettingsManager: SiteSettingsManager?

    init(onEvent: @escaping (AutoConsentEvent) -> Void) {
        self.onEvent = onEvent
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        switch type {
        case "checkEnabled":
            handleCheckEnabled(message: message)

        case "action":
            if let ruleName = body["rule"] as? String,
               let action = body["action"] as? String,
               let url = body["url"] as? String {
                onEvent(.action(ruleName: ruleName, action: action, url: url))
            }

        default:
            break
        }
    }

    /// Handles `checkEnabled` messages by checking site settings and responding via callback.
    private func handleCheckEnabled(message: WKScriptMessage) {
        guard let webView = message.webView else { return }

        let domain = message.frameInfo.securityOrigin.host
        var enabled = true

        // Check if site has autoconsent disabled
        if siteSettingsManager?.settings(for: domain)?.disableAutoConsent == true {
            enabled = false
            Logger.debug("AutoConsent disabled for \(domain) via site settings", category: Logger.tabs)
        }

        // Respond to JavaScript via callback
        let script = "window.__autoConsentCallback && window.__autoConsentCallback(\(enabled));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}
