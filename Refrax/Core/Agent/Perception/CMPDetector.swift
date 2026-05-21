import Foundation
import WebKit

/// Detects and dismisses Cookie Management Platform (CMP) consent banners.
///
/// Supports both iframe-based CMPs (Cookiebot, OneTrust, etc.) detected by origin pattern,
/// and page-level CMPs detected by JavaScript API presence. The dismiss strategy is
/// **privacy-first**: reject non-essential cookies first, fall back to accept only if
/// no reject option exists.
///
/// ## Supported CMPs
///
/// | CMP | Detection | Dismiss Strategy |
/// |-----|-----------|-----------------|
/// | IAB TCF | `__tcfapi` global | `rejectAll` first, `acceptAll` fallback |
/// | Cookiebot | `Cookiebot` global or iframe origin | `submitCustomConsent(false,false,false)` |
/// | OneTrust | `OneTrust` global or `cdn.cookielaw.org` iframe | `RejectAll()` first, `AllowAll()` fallback |
/// | Usercentrics | `UC_UI` global or iframe origin | `denyAllConsent()` |
/// | Quantcast | iframe origin pattern | `rejectAll` via TCF |
/// | Didomi | `Didomi` global or iframe origin | `setUserDisagreeToAll()` |
/// | Generic | Button text matching | Click "Reject"/"Decline" first, "Accept" fallback |
///
/// ## Usage
///
/// ```swift
/// let result = try await CMPDetector.dismiss(
///     on: webPage,
///     acceptAll: false  // privacy-first: try reject first
/// )
/// ```
@MainActor
enum CMPDetector {
    // MARK: - Types

    enum CMPType: String, Sendable {
        case tcf = "IAB TCF"
        case cookiebot = "Cookiebot"
        case oneTrust = "OneTrust"
        case usercentrics = "Usercentrics"
        case quantcast = "Quantcast"
        case didomi = "Didomi"
        case generic = "Generic"
    }

    struct DismissResult: Sendable {
        let success: Bool
        let cmpType: CMPType
        let action: String
        let message: String
    }

    // MARK: - Dismiss

    /// Attempts to dismiss cookie consent banners on the current page.
    ///
    /// The dismiss strategy is privacy-first by default:
    /// 1. Try CMP-specific API calls to reject non-essential cookies
    /// 2. If no API found, search for "reject"/"decline" buttons
    /// 3. If `acceptAll` is true, skip reject attempts and accept everything
    /// 4. Fall back to "accept" buttons only if no reject option exists
    ///
    /// - Parameters:
    ///   - webPage: The web page to dismiss cookies on.
    ///   - acceptAll: If true, accept all cookies instead of rejecting. Default is false.
    /// - Returns: A result describing what was done.
    static func dismiss(
        on webPage: WebPage,
        acceptAll: Bool = false,
    ) async throws -> DismissResult {
        // Phase 1: Try CMP-specific JavaScript APIs
        if let result = try await dismissViaAPI(on: webPage, acceptAll: acceptAll) {
            return result
        }

        // Phase 2: Try generic button clicking
        return try await dismissViaButtons(on: webPage, acceptAll: acceptAll)
    }

    // MARK: - API-Based Dismiss

    /// Tries CMP-specific JavaScript APIs in priority order.
    private static func dismissViaAPI(
        on webPage: WebPage,
        acceptAll: Bool,
    ) async throws -> DismissResult? {
        // Detect which CMP APIs are present
        let detection = try await webPage.callJavaScript("""
        return (function() {
            var apis = [];
            if (typeof __tcfapi === 'function') apis.push('tcf');
            if (typeof Cookiebot !== 'undefined') apis.push('cookiebot');
            if (typeof OneTrust !== 'undefined') apis.push('onetrust');
            if (typeof UC_UI !== 'undefined') apis.push('usercentrics');
            if (typeof Didomi !== 'undefined') apis.push('didomi');
            if (typeof quantserve !== 'undefined' || typeof __cmp === 'function') apis.push('quantcast');
            return apis.join(',');
        })()
        """)

        guard let apisString = detection as? String, !apisString.isEmpty else {
            return nil
        }

        let apis = apisString.split(separator: ",").map(String.init)

        // Try each detected CMP
        for api in apis {
            switch api {
            case "tcf":
                return try await dismissTCF(on: webPage, acceptAll: acceptAll)
            case "cookiebot":
                return try await dismissCookiebot(on: webPage, acceptAll: acceptAll)
            case "onetrust":
                return try await dismissOneTrust(on: webPage, acceptAll: acceptAll)
            case "usercentrics":
                return try await dismissUsercentrics(on: webPage, acceptAll: acceptAll)
            case "didomi":
                return try await dismissDidomi(on: webPage, acceptAll: acceptAll)
            case "quantcast":
                return try await dismissTCF(on: webPage, acceptAll: acceptAll)
            default:
                continue
            }
        }

        return nil
    }

    // MARK: - CMP-Specific Dismiss Methods

    private static func dismissTCF(
        on webPage: WebPage,
        acceptAll: Bool,
    ) async throws -> DismissResult {
        let script: String
        let action: String

        if acceptAll {
            script = """
            return new Promise(function(resolve) {
                __tcfapi('acceptAll', 2, function(success) { resolve(success ? 'accepted' : 'failed'); });
                setTimeout(function() { resolve('timeout'); }, 3000);
            });
            """
            action = "accept"
        } else {
            script = """
            return new Promise(function(resolve) {
                if (typeof __tcfapi === 'function') {
                    // Try rejectAll first (TCF 2.2+)
                    __tcfapi('rejectAll', 2, function(success) {
                        if (success) { resolve('rejected'); return; }
                        // Fallback to acceptAll
                        __tcfapi('acceptAll', 2, function(s) { resolve(s ? 'accepted_fallback' : 'failed'); });
                    });
                } else {
                    resolve('no_api');
                }
                setTimeout(function() { resolve('timeout'); }, 3000);
            });
            """
            action = "reject"
        }

        let result = try await webPage.callJavaScript(script) as? String ?? "failed"
        return DismissResult(
            success: result != "failed" && result != "no_api",
            cmpType: .tcf,
            action: result.contains("reject") ? "rejected" : (result.contains("accept") ? "accepted" : action),
            message: "IAB TCF: \(result)",
        )
    }

    private static func dismissCookiebot(
        on webPage: WebPage,
        acceptAll: Bool,
    ) async throws -> DismissResult {
        let script: String
        let action: String

        if acceptAll {
            script = """
            return (function() {
                try { Cookiebot.submitCustomConsent(true, true, true); return 'accepted'; }
                catch(e) { return 'failed: ' + e.message; }
            })();
            """
            action = "accepted"
        } else {
            script = """
            return (function() {
                try {
                    // Reject all non-essential: preferences=false, statistics=false, marketing=false
                    Cookiebot.submitCustomConsent(false, false, false);
                    return 'rejected';
                } catch(e) {
                    return 'failed: ' + e.message;
                }
            })();
            """
            action = "rejected"
        }

        let result = try await webPage.callJavaScript(script) as? String ?? "failed"
        return DismissResult(
            success: !result.hasPrefix("failed"),
            cmpType: .cookiebot,
            action: action,
            message: "Cookiebot: \(result)",
        )
    }

    private static func dismissOneTrust(
        on webPage: WebPage,
        acceptAll: Bool,
    ) async throws -> DismissResult {
        let script = if acceptAll {
            """
            return (function() {
                try {
                    if (OneTrust.AllowAll) { OneTrust.AllowAll(); return 'accepted'; }
                    return 'no_method';
                } catch(e) { return 'failed: ' + e.message; }
            })();
            """
        } else {
            """
            return (function() {
                try {
                    // Try RejectAll first
                    if (OneTrust.RejectAll) { OneTrust.RejectAll(); return 'rejected'; }
                    // Fallback to AllowAll
                    if (OneTrust.AllowAll) { OneTrust.AllowAll(); return 'accepted_fallback'; }
                    return 'no_method';
                } catch(e) { return 'failed: ' + e.message; }
            })();
            """
        }

        let result = try await webPage.callJavaScript(script) as? String ?? "failed"
        return DismissResult(
            success: !result.hasPrefix("failed") && result != "no_method",
            cmpType: .oneTrust,
            action: result.contains("reject") ? "rejected" : "accepted",
            message: "OneTrust: \(result)",
        )
    }

    private static func dismissUsercentrics(
        on webPage: WebPage,
        acceptAll: Bool,
    ) async throws -> DismissResult {
        let script = if acceptAll {
            """
            return (function() {
                try {
                    if (UC_UI && UC_UI.acceptAllConsent) { UC_UI.acceptAllConsent(); return 'accepted'; }
                    return 'no_method';
                } catch(e) { return 'failed: ' + e.message; }
            })();
            """
        } else {
            """
            return (function() {
                try {
                    if (UC_UI && UC_UI.denyAllConsent) { UC_UI.denyAllConsent(); return 'rejected'; }
                    if (UC_UI && UC_UI.acceptAllConsent) { UC_UI.acceptAllConsent(); return 'accepted_fallback'; }
                    return 'no_method';
                } catch(e) { return 'failed: ' + e.message; }
            })();
            """
        }

        let result = try await webPage.callJavaScript(script) as? String ?? "failed"
        return DismissResult(
            success: !result.hasPrefix("failed") && result != "no_method",
            cmpType: .usercentrics,
            action: result.contains("reject") ? "rejected" : "accepted",
            message: "Usercentrics: \(result)",
        )
    }

    private static func dismissDidomi(
        on webPage: WebPage,
        acceptAll: Bool,
    ) async throws -> DismissResult {
        let script = if acceptAll {
            """
            return (function() {
                try {
                    if (Didomi && Didomi.setUserAgreeToAll) { Didomi.setUserAgreeToAll(); return 'accepted'; }
                    return 'no_method';
                } catch(e) { return 'failed: ' + e.message; }
            })();
            """
        } else {
            """
            return (function() {
                try {
                    if (Didomi && Didomi.setUserDisagreeToAll) { Didomi.setUserDisagreeToAll(); return 'rejected'; }
                    if (Didomi && Didomi.setUserAgreeToAll) { Didomi.setUserAgreeToAll(); return 'accepted_fallback'; }
                    return 'no_method';
                } catch(e) { return 'failed: ' + e.message; }
            })();
            """
        }

        let result = try await webPage.callJavaScript(script) as? String ?? "failed"
        return DismissResult(
            success: !result.hasPrefix("failed") && result != "no_method",
            cmpType: .didomi,
            action: result.contains("reject") ? "rejected" : "accepted",
            message: "Didomi: \(result)",
        )
    }

    // MARK: - Generic Button Dismiss

    /// Finds and clicks consent buttons by text matching.
    ///
    /// Searches for visible buttons/links containing known consent-related text.
    /// Privacy-first: looks for reject/decline buttons first, falls back to accept.
    private static func dismissViaButtons(
        on webPage: WebPage,
        acceptAll: Bool,
    ) async throws -> DismissResult {
        let rejectPatterns = [
            "reject all", "reject", "decline", "deny", "refuse",
            "only necessary", "necessary only", "essential only",
            "only essential", "manage preferences", "customize",
            "ablehnen", "nur notwendige", "refuser", "rechazar",
            "rifiuta", "weigeren", "neka",
        ]

        let acceptPatterns = [
            "accept all", "accept", "agree", "allow all", "allow",
            "got it", "i understand", "ok", "okay", "continue",
            "akzeptieren", "alle akzeptieren", "accepter", "aceptar",
            "accetta", "accepteren", "acceptera",
        ]

        let patterns = acceptAll ? acceptPatterns : (rejectPatterns + acceptPatterns)
        let patternsData = try JSONSerialization.data(withJSONObject: patterns)
        let patternsJSON = String(data: patternsData, encoding: .utf8) ?? "[]"

        let rejectCount = acceptAll ? 0 : rejectPatterns.count

        let script = """
        return (function() {
            var patterns = \(patternsJSON);
            var rejectCount = \(rejectCount);
            var selectors = 'button, a, [role="button"], input[type="submit"], input[type="button"]';
            var elements = document.querySelectorAll(selectors);
        
            function isVisible(el) {
                if (!el) return false;
                var s = getComputedStyle(el);
                if (s.display === 'none' || s.visibility === 'hidden' || s.opacity === '0') return false;
                var r = el.getBoundingClientRect();
                return r.width > 0 && r.height > 0;
            }
        
            // Search both main document and shadow DOMs
            function findConsentButton(root) {
                var allElements = root.querySelectorAll(selectors);
                for (var i = 0; i < patterns.length; i++) {
                    var pattern = patterns[i].toLowerCase();
                    for (var el of allElements) {
                        if (!isVisible(el)) continue;
                        var text = (el.textContent || el.value || '').trim().toLowerCase();
                        if (text === pattern || text.includes(pattern)) {
                            return { element: el, patternIndex: i };
                        }
                    }
                }
                return null;
            }
        
            var match = findConsentButton(document);
        
            // Also check shadow DOMs
            if (!match) {
                var shadows = document.querySelectorAll('*');
                for (var host of shadows) {
                    if (host.shadowRoot) {
                        match = findConsentButton(host.shadowRoot);
                        if (match) break;
                    }
                }
            }
        
            if (match) {
                match.element.click();
                var isReject = match.patternIndex < rejectCount;
                return (isReject ? 'rejected' : 'accepted') + ':' + patterns[match.patternIndex];
            }
        
            return 'not_found';
        })();
        """

        let result = try await webPage.callJavaScript(script) as? String ?? "not_found"

        if result == "not_found" {
            return DismissResult(
                success: false,
                cmpType: .generic,
                action: "none",
                message: "No cookie consent banner found",
            )
        }

        let parts = result.split(separator: ":", maxSplits: 1)
        let action = String(parts.first ?? "unknown")
        let pattern = parts.count > 1 ? String(parts[1]) : ""

        return DismissResult(
            success: true,
            cmpType: .generic,
            action: action,
            message: "Clicked \(action == "rejected" ? "reject" : "accept") button matching \"\(pattern)\"",
        )
    }
}
