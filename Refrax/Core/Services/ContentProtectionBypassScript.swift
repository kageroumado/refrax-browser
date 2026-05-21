import Foundation

/// Generates JavaScript/CSS for content protection bypass.
///
/// Provides scripts that:
/// 1. Override `user-select: none` CSS with `!important`
/// 2. Neutralize event handlers (selectstart, contextmenu, copy, paste, etc.)
/// 3. Remove inline `on*` handlers via MutationObserver
/// 4. Restore keyboard shortcuts (Cmd+A, Cmd+C, etc.)
/// 5. Block hyperlink auditing (ping attribute on anchors)
/// 6. Block tracking beacons (navigator.sendBeacon returns true but doesn't send)
/// 7. Spoof Page Visibility API to always report visible
enum ContentProtectionBypassScript {
    private static let styleID = "refrax-content-protection-bypass"

    /// Combined JavaScript that enables text selection and copy functionality,
    /// plus privacy protections.
    ///
    /// Injected at document start to run before page scripts.
    static let script = """
    (function() {
        'use strict';
    
        const style = document.createElement('style');
        style.id = '\(styleID)';
        style.textContent = `
            *, *::before, *::after {
                user-select: text !important;
                -webkit-user-select: text !important;
                -moz-user-select: text !important;
                -ms-user-select: text !important;
            }
    
            /* Preserve legitimate non-selectable UI elements */
            button, [role="button"], input, select, textarea,
            [draggable="true"], .CodeMirror *, .monaco-editor * {
                user-select: auto !important;
            }
        `;
        (document.head || document.documentElement).appendChild(style);
    
        // Events to neutralize for copy protection bypass
        // Note: Do NOT include mousedown/mouseup/click - breaks site interactivity
        const neutralizedEvents = [
            'selectstart', 'contextmenu', 'copy', 'cut', 'paste', 'dragstart'
        ];
    
        neutralizedEvents.forEach(eventType => {
            document.addEventListener(eventType, e => e.stopPropagation(), true);
        });
    
        const handlerAttributes = [
            'onselectstart', 'oncontextmenu', 'oncopy', 'oncut', 'onpaste', 'ondragstart'
        ];
    
        function removeInlineHandlers() {
            const selector = handlerAttributes.map(attr => `[${attr}]`).join(', ');
            document.querySelectorAll(selector).forEach(el => {
                handlerAttributes.forEach(attr => el.removeAttribute(attr));
            });
        }
    
        removeInlineHandlers();
    
        new MutationObserver(removeInlineHandlers).observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: handlerAttributes
        });
    
        document.addEventListener('keydown', e => {
            if ((e.metaKey || e.ctrlKey) && ['a', 'c', 'v', 'x'].includes(e.key.toLowerCase())) {
                e.stopPropagation();
            }
        }, true);
    
        // --- Privacy Protections ---
    
        // Block hyperlink auditing: Remove ping attribute from anchors
        function removePingAttribute(el) {
            if (el.hasAttribute('ping')) {
                el.removeAttribute('ping');
            }
        }
        document.querySelectorAll('a[ping]').forEach(removePingAttribute);
        new MutationObserver(mutations => {
            for (const m of mutations) {
                // Handle attribute changes on existing elements
                if (m.type === 'attributes' && m.target.tagName === 'A') {
                    removePingAttribute(m.target);
                    continue;
                }
                // Handle new nodes
                for (const node of m.addedNodes) {
                    if (node.nodeType !== 1) continue;
                    if (node.matches && node.matches('a[ping]')) removePingAttribute(node);
                    if (node.querySelectorAll) {
                        node.querySelectorAll('a[ping]').forEach(removePingAttribute);
                    }
                }
            }
        }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['ping'] });
    
        // Block tracking beacons: Replace sendBeacon with no-op that returns success.
        // Use configurable: true to avoid errors if sites try to check/modify it.
        // The beacon appears to succeed but no data is actually sent.
        try {
            Object.defineProperty(Navigator.prototype, 'sendBeacon', {
                value: function(url, data) { return true; },
                writable: true,
                configurable: true
            });
        } catch (e) {}
    
        // Spoof Page Visibility API to always report visible.
        // This prevents tracking of tab switching while allowing legitimate
        // visibility handlers to run (they just see "visible" state).
        // Use configurable: true to avoid errors if sites check property descriptors.
        try {
            Object.defineProperty(Document.prototype, 'visibilityState', {
                get: function() { return 'visible'; },
                configurable: true
            });
            Object.defineProperty(Document.prototype, 'hidden', {
                get: function() { return false; },
                configurable: true
            });
        } catch (e) {}
        // Note: We intentionally do NOT block visibilitychange events.
        // Sites may have legitimate handlers that need to run for cleanup/state
        // management. When those handlers check document.hidden or visibilityState,
        // they'll see "visible" - so they won't trigger hidden-tab behaviors.
    })();
    """

    /// Script to remove the bypass (for sites where it's disabled).
    static let removeScript = """
    (function() {
        const style = document.getElementById('\(styleID)');
        if (style) style.remove();
    })();
    """
}
