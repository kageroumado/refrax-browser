import Foundation

/// Generates JavaScript for opt-in web behavior protections.
///
/// These scripts modify webpage behavior and are disabled by default.
/// Users can enable them globally or per-site through settings.
enum WebBehaviorProtectionScripts {
    // MARK: - Sign-In Prompt Hiding

    /// CSS that hides common sign-in prompts and browser recommendation banners.
    ///
    /// Targets:
    /// - Google One Tap sign-in
    /// - "Google recommends Chrome" banners
    /// - Common notification permission prompts
    static let hideSignInPrompts = """
    (function() {
        'use strict';
    
        const style = document.createElement('style');
        style.id = 'refrax-hide-signin-prompts';
        style.textContent = `
            /* Google One Tap sign-in */
            #credential_picker_container,
            #credential_picker_iframe,
            .g_id_signin,
            [data-g-id="credential_picker"],
            iframe[src*="accounts.google.com/gsi"] {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
                pointer-events: none !important;
            }
    
            /* Google Chrome recommendation banners */
            [class*="browser-banner"],
            [class*="chrome-banner"],
            [class*="BrowserBanner"],
            [class*="ChromeBanner"],
            [id*="browser-banner"],
            [id*="chrome-banner"],
            .browser-update-banner,
            .chrome-promo,
            .chrome-download-banner {
                display: none !important;
            }
    
            /* Common notification permission prompts */
            [class*="notification-prompt"],
            [class*="NotificationPrompt"],
            [class*="push-prompt"],
            [class*="PushPrompt"],
            [class*="subscribe-prompt"],
            [class*="SubscribePrompt"],
            [data-testid*="notification-prompt"],
            .notification-banner,
            .push-notification-prompt {
                display: none !important;
            }
    
            /* YouTube-specific Google sign-in prompts */
            /* Hide both the dialog AND its backdrop to prevent stuck overlays */
            ytd-popup-container:has([aria-label*="Sign in"]),
            tp-yt-paper-dialog:has([aria-label*="Sign in"]),
            body:has(tp-yt-paper-dialog:has([aria-label*="Sign in"])) tp-yt-iron-overlay-backdrop,
            body:has(ytd-popup-container:has([aria-label*="Sign in"])) tp-yt-iron-overlay-backdrop {
                display: none !important;
            }
    
            /* Generic overlay prompts with sign-in mentions */
            [role="dialog"]:has([data-g-id]),
            [role="dialog"]:has(.g_id_signin) {
                display: none !important;
            }
        `;
        (document.head || document.documentElement).appendChild(style);
    
        // Also handle dynamically added Google One Tap elements
        new MutationObserver(mutations => {
            for (const m of mutations) {
                for (const node of m.addedNodes) {
                    if (node.nodeType !== 1) continue;
                    // Remove Google One Tap container if it appears
                    if (node.id === 'credential_picker_container' ||
                        node.id === 'credential_picker_iframe') {
                        node.remove();
                    }
                }
            }
        }).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """

    /// Removes the sign-in prompt hiding styles.
    ///
    /// Note: The MutationObserver cannot be stopped, but without the styles,
    /// removed elements would need to be re-created by the page anyway.
    static let removeHideSignInPrompts = """
    (function() {
        const style = document.getElementById('refrax-hide-signin-prompts');
        if (style) style.remove();
    })();
    """

    // MARK: - beforeunload Alert Blocking

    /// Script that blocks beforeunload alerts from web pages.
    ///
    /// Prevents sites from showing "Are you sure you want to leave?" dialogs
    /// while preserving the browser's native media playback checks.
    static let beforeUnloadBlock = """
    (function() {
        'use strict';
    
        // Intercept onbeforeunload assignment
        Object.defineProperty(window, 'onbeforeunload', {
            get: function() { return null; },
            set: function() { /* Silently ignore */ },
            configurable: true
        });
    
        // Intercept addEventListener for beforeunload
        const originalAddEventListener = window.addEventListener;
        window.addEventListener = function(type, listener, options) {
            if (type === 'beforeunload') {
                return; // Silently ignore beforeunload listeners
            }
            return originalAddEventListener.call(this, type, listener, options);
        };
    
        // Also handle returnValue assignment in existing handlers
        window.addEventListener('beforeunload', function(e) {
            e.stopImmediatePropagation();
            delete e.returnValue;
        }, true);
    })();
    """

    // MARK: - Scroll Hijacking Prevention

    /// Script that disables custom scroll behaviors.
    ///
    /// Forces native scrolling by:
    /// - Overriding scroll-behavior CSS to 'auto'
    /// - Removing scroll-snap properties
    /// - Making wheel/scroll event listeners passive
    static let scrollHijackingBlock = """
    (function() {
        'use strict';
    
        // Inject CSS to override scroll behaviors
        const style = document.createElement('style');
        style.id = 'refrax-scroll-protection';
        style.textContent = `
            *, html, body {
                scroll-behavior: auto !important;
                scroll-snap-type: none !important;
                scroll-snap-align: none !important;
                scroll-snap-stop: normal !important;
                overscroll-behavior: auto !important;
            }
        `;
        (document.head || document.documentElement).appendChild(style);
    
        // Force wheel events to be passive to prevent preventDefault
        const originalAddEventListener = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, listener, options) {
            if (type === 'wheel' || type === 'scroll' || type === 'touchmove') {
                // Force passive: true to prevent scroll blocking
                let newOptions = options;
                if (typeof options === 'boolean') {
                    newOptions = { capture: options, passive: true };
                } else if (typeof options === 'object') {
                    newOptions = { ...options, passive: true };
                } else {
                    newOptions = { passive: true };
                }
                return originalAddEventListener.call(this, type, listener, newOptions);
            }
            return originalAddEventListener.call(this, type, listener, options);
        };
    })();
    """

    /// Removes the scroll hijacking prevention styles.
    ///
    /// Note: The addEventListener override cannot be undone without a page reload.
    /// This only removes the CSS overrides.
    static let removeScrollHijackingBlock = """
    (function() {
        const style = document.getElementById('refrax-scroll-protection');
        if (style) style.remove();
    })();
    """

    // MARK: - Video Controls

    /// Generates a script for native controls and optional speed control.
    ///
    /// Shows browser controls for AirPlay, Picture-in-Picture, and standard
    /// playback even on sites that hide them.
    ///
    /// - Parameter speed: The playback rate (1.0 for normal, clamped to 0.25-4.0).
    /// - Returns: JavaScript that applies native controls and speed settings.
    static func videoControlsWithSpeed(speed: Double) -> String {
        let clampedSpeed = min(max(speed, 0.25), 4.0)
        return """
        (function() {
            'use strict';
        
            const targetSpeed = \(clampedSpeed);
            const videoState = new WeakMap();
        
            const style = document.createElement('style');
            style.id = 'refrax-video-controls';
            style.textContent = `
                video::-webkit-media-controls {
                    display: flex !important;
                    opacity: 1 !important;
                    visibility: visible !important;
                }
                video::-webkit-media-controls-panel,
                video::-webkit-media-controls-enclosure {
                    display: flex !important;
                }
            `;
            (document.head || document.documentElement).appendChild(style);
        
            function setSpeed(video, speed) {
                const state = videoState.get(video) || { settingSpeed: false, userOverride: false };
                if (state.userOverride) return;
                state.settingSpeed = true;
                videoState.set(video, state);
                video.playbackRate = speed;
                // Reset flag after current event loop to catch any resulting ratechange
                setTimeout(() => { state.settingSpeed = false; }, 0);
            }
        
            function setupVideo(video) {
                if (videoState.has(video)) return;
                videoState.set(video, { settingSpeed: false, userOverride: false });
        
                video.controls = true;
                video.removeAttribute('controlsList');
        
                // Track user speed changes vs our programmatic changes
                video.addEventListener('ratechange', () => {
                    const state = videoState.get(video);
                    if (state && !state.settingSpeed && video.playbackRate !== targetSpeed) {
                        state.userOverride = true;
                    }
                });
        
                setSpeed(video, targetSpeed);
        
                video.addEventListener('loadedmetadata', () => {
                    setSpeed(video, targetSpeed);
                });
        
                new MutationObserver(mutations => {
                    for (const m of mutations) {
                        if (m.attributeName === 'controls' && !video.controls) {
                            video.controls = true;
                        } else if (m.attributeName === 'controlsList') {
                            video.removeAttribute('controlsList');
                        }
                    }
                }).observe(video, { attributes: true, attributeFilter: ['controls', 'controlsList'] });
            }
        
            function processNodes(nodes) {
                for (const node of nodes) {
                    if (node.nodeType !== 1) continue;
                    if (node.tagName === 'VIDEO') setupVideo(node);
                    node.querySelectorAll?.('video').forEach(setupVideo);
                }
            }
        
            document.querySelectorAll('video').forEach(setupVideo);
        
            new MutationObserver(mutations => {
                for (const m of mutations) processNodes(m.addedNodes);
            }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
    }

    /// Removes the video controls styles.
    ///
    /// Note: Individual video element modifications (controls attribute, playbackRate)
    /// cannot be easily reverted. This removes the CSS forcing controls visibility.
    static let removeVideoControls = """
    (function() {
        const style = document.getElementById('refrax-video-controls');
        if (style) style.remove();
    })();
    """
}
