import Foundation

/// Centralized JavaScript snippets for on-demand evaluation.
///
/// All JavaScript strings used with `evaluateJavaScript()` or `callJavaScript()`
/// are consolidated here for maintainability and consistency.
///
/// ## Usage
///
/// ```swift
/// // For static scripts:
/// let result = try await webPage.callJavaScript(JavaScriptSnippets.visibleViewport)
///
/// // For parameterized scripts:
/// let script = JavaScriptSnippets.setMediaVolume(0.5)
/// try await webView.evaluateJavaScript(script)
/// ```
///
/// ## Script Types
///
/// - **Static properties**: Scripts with no parameters
/// - **Static methods**: Scripts that require runtime values (use JSON encoding for safety)
///
/// ## Note
///
/// For persistent content scripts registered at document start/end, use ``ScriptRegistry`` instead.
///
/// This enum is `nonisolated` and `Sendable` since it only contains static string constants
/// and pure functions, allowing safe use from any actor context.
nonisolated enum JavaScriptSnippets: Sendable {
    // MARK: - Form Fill Helper

    /// JavaScript helper that uses the native HTMLInputElement/HTMLTextAreaElement value
    /// setter to bypass React/Vue/Angular framework interceptors, then dispatches
    /// proper input and change events so frameworks detect the value change.
    ///
    /// Defines `__refraxSetValue(el, value)` — call after interpolating into an IIFE.
    private static let nativeSetValue = """
    function __refraxSetValue(el, value) {
        var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set
            || Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
        if (setter) { setter.call(el, value); } else { el.value = value; }
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertReplacementText' }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
    }
    """

    // MARK: - Viewport & Scroll

    /// Queries the visible viewport dimensions and scroll position.
    ///
    /// Use with `callJavaScript()` (function body style).
    ///
    /// Returns: `{ scrollX, scrollY, innerWidth, innerHeight }`
    static let visibleViewport = """
    return {
        scrollX: window.scrollX,
        scrollY: window.scrollY,
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight
    };
    """

    /// Queries viewport as JSON string (for use with `callJavaScript`).
    ///
    /// Returns: JSON string of `{ x, y, width, height }`
    static let visibleViewportJSON = """
    JSON.stringify({
        x: window.scrollX,
        y: window.scrollY,
        width: window.innerWidth,
        height: window.innerHeight
    })
    """

    /// Scrolls the page to a specific Y position.
    ///
    /// Used to restore scroll position after tab restore or app restart.
    /// Uses `scrollTo` with instant behavior to avoid animation during restoration.
    ///
    /// - Parameter y: The vertical scroll offset in pixels.
    /// - Returns: JavaScript code to execute.
    static func scrollToY(_ y: Double) -> String {
        "window.scrollTo({ top: \(y), behavior: 'instant' });"
    }

    // MARK: - Form Data Detection

    /// Checks for unsaved form data on the page.
    ///
    /// Queries input fields, textareas, selects, and contenteditable elements
    /// for values that differ from defaults. Includes same-origin iframes.
    ///
    /// Use with `callJavaScript()` in an isolated content world.
    ///
    /// Returns: `true` if unsaved form data exists
    static let hasUnsavedFormData = """
    (function() {
        function checkFrame(win) {
            try {
                const doc = win.document;
                const inputs = doc.querySelectorAll('input, textarea, select');
                for (const input of inputs) {
                    const type = input.type?.toLowerCase() || '';
                    if (['hidden', 'submit', 'button', 'reset', 'image'].includes(type)) continue;
    
                    if (input.tagName === 'SELECT') {
                        const defaultIndex = Array.from(input.options).findIndex(o => o.defaultSelected);
                        if (input.selectedIndex !== defaultIndex && defaultIndex !== -1) return true;
                    } else if (type === 'checkbox' || type === 'radio') {
                        if (input.checked !== input.defaultChecked) return true;
                    } else {
                        if (input.value !== input.defaultValue && input.value.length > 0) return true;
                    }
                }
    
                const editables = doc.querySelectorAll('[contenteditable="true"]');
                for (const el of editables) {
                    if (el.textContent.trim().length > 0) return true;
                }
    
                // Recursively check same-origin iframes
                for (let i = 0; i < win.frames.length; i++) {
                    try {
                        if (checkFrame(win.frames[i])) return true;
                    } catch (e) {
                        // Cross-origin frame - skip (security restriction)
                    }
                }
    
                return false;
            } catch (e) {
                // Frame access denied (cross-origin)
                return false;
            }
        }
        return checkFrame(window);
    })();
    """

    // MARK: - Media Control

    /// Sets volume on all media elements.
    ///
    /// Applies to all `<video>` and `<audio>` elements, including same-origin iframes.
    ///
    /// - Parameter volume: Volume level from 0.0 to 1.0
    /// - Returns: Script for use with `evaluateJavaScript()`
    static func setMediaVolume(_ volume: Double) -> String {
        let clampedVolume = max(0.0, min(1.0, volume))
        return """
        (function() {
            const volume = \(clampedVolume);
            let count = 0;
        
            // Set volume on existing media elements
            document.querySelectorAll('video, audio').forEach(el => {
                el.volume = volume;
                count++;
            });
        
            // Also try same-origin iframes
            try {
                const frames = document.querySelectorAll('iframe');
                frames.forEach(frame => {
                    try {
                        const frameDoc = frame.contentDocument || frame.contentWindow?.document;
                        if (frameDoc) {
                            frameDoc.querySelectorAll('video, audio').forEach(el => {
                                el.volume = volume;
                                count++;
                            });
                        }
                    } catch (e) {
                        // Cross-origin frame, skip
                    }
                });
            } catch (e) {}
        
            return count;
        })();
        """
    }

    // MARK: - Picture-in-Picture

    /// Enters Picture-in-Picture on the page's predominant video.
    ///
    /// Prefers a playing video, breaking ties by on-screen area. Includes
    /// same-origin iframes; cross-origin frames are unreachable from here —
    /// the native SPI path covers those when its playback session exists.
    ///
    /// Requires a user gesture (`mediaSession().fullscreenPermitted()`), so
    /// evaluate with the gesture-forcing `evaluateJavaScript()`.
    ///
    /// Returns: `"ok"`, `"already-active"`, or `"no-video"`.
    static let enterPictureInPicture = """
    (() => {
        const collect = (doc) => {
            let vids = Array.from(doc.querySelectorAll('video'));
            for (const frame of doc.querySelectorAll('iframe')) {
                try {
                    const frameDoc = frame.contentDocument;
                    if (frameDoc) vids = vids.concat(collect(frameDoc));
                } catch (e) {}
            }
            return vids;
        };
        const all = collect(document);
        if (all.some(v => v.webkitPresentationMode === 'picture-in-picture')) return 'already-active';
        const candidates = all.filter(v =>
            v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture'));
        if (!candidates.length) return 'no-video';
        const playing = candidates.filter(v => !v.paused && !v.ended);
        const pick = (playing.length ? playing : candidates).reduce((a, b) =>
            a.clientWidth * a.clientHeight >= b.clientWidth * b.clientHeight ? a : b);
        pick.webkitSetPresentationMode('picture-in-picture');
        return 'ok';
    })();
    """

    /// Exits Picture-in-Picture if any video is presenting in it.
    ///
    /// Returns: `"ok"` or `"not-active"`.
    static let exitPictureInPicture = """
    (() => {
        const collect = (doc) => {
            let vids = Array.from(doc.querySelectorAll('video'));
            for (const frame of doc.querySelectorAll('iframe')) {
                try {
                    const frameDoc = frame.contentDocument;
                    if (frameDoc) vids = vids.concat(collect(frameDoc));
                } catch (e) {}
            }
            return vids;
        };
        const active = collect(document).find(v => v.webkitPresentationMode === 'picture-in-picture');
        if (!active) return 'not-active';
        active.webkitSetPresentationMode('inline');
        return 'ok';
    })();
    """

    /// Reports the page's PiP-relevant video state.
    ///
    /// Returns: JSON `{ active: Bool, playing: Bool, eligible: Bool }` —
    /// whether a video is in PiP, whether any video is playing, and whether
    /// any video supports PiP.
    static let pictureInPictureState = """
    (() => {
        const collect = (doc) => {
            let vids = Array.from(doc.querySelectorAll('video'));
            for (const frame of doc.querySelectorAll('iframe')) {
                try {
                    const frameDoc = frame.contentDocument;
                    if (frameDoc) vids = vids.concat(collect(frameDoc));
                } catch (e) {}
            }
            return vids;
        };
        const all = collect(document);
        return JSON.stringify({
            active: all.some(v => v.webkitPresentationMode === 'picture-in-picture'),
            playing: all.some(v => !v.paused && !v.ended),
            eligible: all.some(v =>
                v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture')),
        });
    })();
    """

    // MARK: - Link Detection

    /// Performs a hit test to find a link at the given coordinates.
    ///
    /// - Parameters:
    ///   - x: X coordinate in viewport
    ///   - y: Y coordinate in viewport
    /// - Returns: Script that returns HTTP(S) URL string or null
    static func linkHitTest(x: Double, y: Double) -> String {
        """
        (function() {
            const x = \(x);
            const y = \(y);
            const element = document.elementFromPoint(x, y);
            if (!element) return null;
        
            // Find the nearest anchor element
            const anchor = element.closest('a');
            if (!anchor) return null;
        
            const href = anchor.href;
            if (!href) return null;
        
            // Only return HTTP(S) URLs for previewing
            if (href.startsWith('http://') || href.startsWith('https://')) {
                return href;
            }
        
            return null;
        })();
        """
    }

    // MARK: - Active Element

    /// Gets the bounding rect of the currently focused element.
    ///
    /// Returns: `{ x, y, width, height }` or null if no active element
    static let activeElementRect = """
    (function() {
        const el = document.activeElement;
        if (!el) return null;
    
        const rect = el.getBoundingClientRect();
        return {
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height
        };
    })();
    """

    // MARK: - AutoFill

    /// Extracts form context information to determine login vs registration form.
    ///
    /// Use with `evaluateJavaScript()`.
    ///
    /// Returns: JSON object with:
    /// - `formText`: Combined text from form labels, buttons, and headings
    /// - `passwordFieldCount`: Number of password fields in the form (2+ suggests registration with confirmation)
    /// - `hasNewPasswordHint`: Whether autocomplete="new-password" is present
    /// - `hasCurrentPasswordHint`: Whether autocomplete="current-password" is present
    /// - `fieldHasValue`: Whether the focused field already has a value
    /// - `isConfirmPasswordField`: Whether this is a confirm/verify password field
    /// - `passwordFieldIndex`: Index of this password field (0 = first, 1 = second/confirm, -1 = not password)
    static let formContext = """
    (function() {
        const el = document.activeElement;
        if (!el) return null;
    
        const form = el.closest('form');
        let formText = document.title;
        let passwordFieldCount = document.querySelectorAll('input[type="password"]').length;
        let hasNewPassword = !!document.querySelector('input[autocomplete="new-password"]');
        let hasCurrentPassword = !!document.querySelector('input[autocomplete="current-password"]');
    
        // Check if current field has a value
        const fieldHasValue = el.value && el.value.length > 0;
    
        // Determine if this is a confirm password field
        let isConfirmPasswordField = false;
        let passwordFieldIndex = -1;
    
        if (el.type === 'password') {
            // Check name/id/placeholder for confirm indicators
            const fieldId = (el.id || '').toLowerCase();
            const fieldName = (el.name || '').toLowerCase();
            const placeholder = (el.placeholder || '').toLowerCase();
            const autocomplete = (el.autocomplete || '').toLowerCase();
    
            const confirmPatterns = ['confirm', 'verify', 'repeat', 'retype', 're-type', 're_type', 'password2', 'pass2', 'pwd2'];
            const combined = fieldId + ' ' + fieldName + ' ' + placeholder + ' ' + autocomplete;
    
            for (const pattern of confirmPatterns) {
                if (combined.includes(pattern)) {
                    isConfirmPasswordField = true;
                    break;
                }
            }
    
            // Also check if this is the second password field in the form
            const passwordFields = form ? Array.from(form.querySelectorAll('input[type="password"]')) : Array.from(document.querySelectorAll('input[type="password"]'));
            passwordFieldIndex = passwordFields.indexOf(el);
    
            // If there are 2+ password fields and this is the second one, it's likely a confirm field
            if (passwordFields.length >= 2 && passwordFieldIndex >= 1) {
                isConfirmPasswordField = true;
            }
        }
    
        if (form) {
            const labels = Array.from(form.querySelectorAll('label')).map(l => l.textContent).join(' ');
            const buttons = Array.from(form.querySelectorAll('button, input[type="submit"]')).map(b => b.textContent || b.value).join(' ');
            const headings = Array.from(form.querySelectorAll('h1, h2, h3, h4')).map(h => h.textContent).join(' ');
            formText = labels + ' ' + buttons + ' ' + headings + ' ' + document.title;
            passwordFieldCount = form.querySelectorAll('input[type="password"]').length;
            hasNewPassword = !!form.querySelector('input[autocomplete="new-password"]');
            hasCurrentPassword = !!form.querySelector('input[autocomplete="current-password"]');
        }
    
        return JSON.stringify({
            formText: formText,
            passwordFieldCount: passwordFieldCount,
            hasNewPasswordHint: hasNewPassword,
            hasCurrentPasswordHint: hasCurrentPassword,
            fieldHasValue: fieldHasValue,
            isConfirmPasswordField: isConfirmPasswordField,
            passwordFieldIndex: passwordFieldIndex
        });
    })();
    """

    /// Fills the currently focused password field directly.
    ///
    /// This is more reliable than ID-based filling because it targets
    /// the field that actually has focus, avoiding DOM ID mismatch issues.
    ///
    /// - Parameter password: The password to fill (will be JSON encoded)
    /// - Returns: Script that returns `true` if fill succeeded, `false` otherwise
    static func fillFocusedPassword(_ password: String) -> String {
        let escaped = jsonEncode(password)
        return """
        (function() {
            const el = document.activeElement;
            if (!el || el.type !== 'password') return false;
            \(nativeSetValue)
            __refraxSetValue(el, \(escaped));
            return true;
        })();
        """
    }

    /// Fills all password fields in the form containing the focused element.
    ///
    /// This is useful for registration forms where both the password and
    /// confirm password fields should be filled with the same value.
    ///
    /// - Parameter password: The password to fill (will be JSON encoded)
    /// - Returns: Script that returns the number of fields filled
    static func fillAllPasswordFields(_ password: String) -> String {
        let escaped = jsonEncode(password)
        return """
        (function() {
            const el = document.activeElement;
            if (!el) return 0;
            \(nativeSetValue)

            // Find the form containing the focused element
            const form = el.closest('form');

            // Get all password fields (in form or entire document)
            const container = form || document;
            const passwordFields = container.querySelectorAll('input[type="password"]');

            let filled = 0;
            for (const field of passwordFields) {
                __refraxSetValue(field, \(escaped));
                filled++;
            }

            return filled;
        })();
        """
    }

    /// Fills form fields with credentials.
    ///
    /// Follows WHATWG autofill spec (https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#autofill):
    /// - Prioritizes `autocomplete` attribute for field detection
    /// - Respects existing field values (won't overwrite non-empty username)
    /// - Password field: Currently focused element if it's a password input, otherwise searches form
    /// - Username field: Searches for inputs with autocomplete="username" or "email", then fallback patterns
    ///
    /// - Parameters:
    ///   - password: The password to fill
    ///   - username: The username to fill
    /// - Returns: Script for use with `evaluateJavaScript()`
    static func fillCredentials(
        password: String,
        username: String,
    ) -> String {
        let passwordJSON = jsonEncode(password)
        let usernameJSON = jsonEncode(username)

        return """
        (function() {
            \(nativeSetValue)
            function fillField(el, value) {
                if (!el) return false;
                __refraxSetValue(el, value);
                return true;
            }

            const focused = document.activeElement;
            const form = focused ? focused.closest('form') : null;
            const container = form || document;
        
            // Find password field - prefer focused element if it's a password input
            // Per WHATWG spec: autocomplete="current-password" indicates login flow
            let passwordField = null;
            if (focused && focused.type === 'password') {
                passwordField = focused;
            } else {
                // Prioritize current-password autocomplete per spec
                passwordField = container.querySelector('input[autocomplete="current-password"]')
                    || container.querySelector('input[type="password"]');
            }
        
            // Find username field per WHATWG autofill spec
            // Priority: autocomplete attribute > name/id patterns > type fallback
            let usernameField = null;
            const usernameSelectors = [
                // WHATWG spec: autocomplete="username" is the canonical identifier
                'input[autocomplete="username"]',
                // WHATWG spec: email is a valid contact field for login
                'input[autocomplete="email"]',
                // Type-based detection
                'input[type="email"]',
                // Name/ID pattern matching (common conventions)
                'input[name="username"]',
                'input[name="user"]',
                'input[name="login"]',
                'input[name="email"]',
                'input[id="username"]',
                'input[id="user"]',
                'input[id="login"]',
                'input[id="email"]',
                // Broader patterns (less specific)
                'input[name*="user"]:not([type="hidden"])',
                'input[name*="login"]:not([type="hidden"])',
                'input[id*="user"]:not([type="hidden"])',
                'input[id*="login"]:not([type="hidden"])',
                // Last resort: first visible text input before password
                'input[type="text"]'
            ];
        
            for (const selector of usernameSelectors) {
                const candidates = container.querySelectorAll(selector);
                for (const el of candidates) {
                    // Skip password fields, hidden fields, and disabled fields
                    if (el.type === 'password' || el.type === 'hidden' || el.disabled) continue;
        
                    // Skip fields with autocomplete="off" per WHATWG spec
                    const ac = el.autocomplete?.toLowerCase();
                    if (ac === 'off' || ac === 'nope' || ac === 'no' || ac === 'false') continue;
        
                    // Skip if this field comes AFTER the password field in DOM order
                    // (username typically precedes password in login forms)
                    if (passwordField) {
                        const position = passwordField.compareDocumentPosition(el);
                        if (position & Node.DOCUMENT_POSITION_FOLLOWING) continue;
                    }
        
                    usernameField = el;
                    break;
                }
                if (usernameField) break;
            }
        
            // Fill the fields
            let filledUsername = false;
            let filledPassword = false;
        
            // Only fill username if the field is empty (don't overwrite user input)
            if (usernameField && !usernameField.value) {
                filledUsername = fillField(usernameField, \(usernameJSON));
            }
        
            if (passwordField) {
                filledPassword = fillField(passwordField, \(passwordJSON));
            }
        
            // Focus the submit button if we filled the password
            if (filledPassword && form) {
                const submit = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
                if (submit) {
                    submit.focus();
                }
            }
        
            return { filledUsername, filledPassword };
        })();
        """
    }

    /// Fills only a password field.
    ///
    /// - Parameters:
    ///   - password: The password to fill
    ///   - fieldId: ID or name of the password field
    /// - Returns: Script for use with `evaluateJavaScript()`
    static func fillPassword(_ password: String, fieldId: String) -> String {
        let passwordJSON = jsonEncode(password)
        let fieldIdJSON = jsonEncode(fieldId)

        return """
        (function() {
            \(nativeSetValue)
            function fillField(id, value) {
                let el = document.getElementById(id) || document.querySelector('[name="' + id + '"]');
                if (!el) {
                    const inputs = document.querySelectorAll('input');
                    for (const input of inputs) {
                        if (input.id === id || input.name === id) {
                            el = input;
                            break;
                        }
                    }
                }
                if (el) {
                    __refraxSetValue(el, value);
                    return true;
                }
                return false;
            }

            fillField(\(fieldIdJSON), \(passwordJSON));
        })();
        """
    }

    // MARK: - Media Session

    /// Fetches Media Session metadata from the page.
    ///
    /// The Media Session API allows websites to customize media notifications
    /// with title, artist, album, and artwork. This snippet extracts that data.
    ///
    /// Use with `evaluateJavaScript()`.
    ///
    /// Returns: JSON string with `{ title, artist, album, artworkURL }` or null if unavailable
    static let mediaSessionMetadata = """
    (function() {
        try {
            const metadata = navigator.mediaSession?.metadata;
            if (!metadata) return null;
    
            // Get the best artwork URL (prefer larger sizes)
            let artworkURL = null;
            if (metadata.artwork && metadata.artwork.length > 0) {
                // Sort by size (largest first) and pick the best one
                const sortedArtwork = [...metadata.artwork].sort((a, b) => {
                    const sizeA = parseInt(a.sizes?.split('x')[0] || '0', 10);
                    const sizeB = parseInt(b.sizes?.split('x')[0] || '0', 10);
                    return sizeB - sizeA;
                });
    
                // Find a reasonable size (not too large, not too small)
                for (const art of sortedArtwork) {
                    const size = parseInt(art.sizes?.split('x')[0] || '0', 10);
                    // Prefer sizes between 96 and 512
                    if (size >= 96 && size <= 512) {
                        artworkURL = art.src;
                        break;
                    }
                }
                // Fallback to first available
                if (!artworkURL && sortedArtwork[0]?.src) {
                    artworkURL = sortedArtwork[0].src;
                }
            }
    
            const result = {
                title: metadata.title || null,
                artist: metadata.artist || null,
                album: metadata.album || null,
                artworkURL: artworkURL
            };
    
            // Only return if we have at least some data
            if (!result.title && !result.artist && !result.artworkURL) {
                return null;
            }
    
            return JSON.stringify(result);
        } catch (e) {
            return null;
        }
    })();
    """

    // MARK: - Content Extraction

    /// Extracts text content from the page body.
    ///
    /// Use with `callJavaScript()`.
    ///
    /// Returns: Plain text content of the page
    static let extractTextContent = """
    return document.body?.textContent || "";
    """

    /// Extracts main content HTML from the page.
    ///
    /// Attempts to find the main content element, falling back to body.
    ///
    /// Use with `callJavaScript()`.
    ///
    /// Returns: HTML string of the main content
    static let extractMainHTML = """
    return (document.querySelector('main') || document.querySelector('article') || document.body)?.outerHTML || "";
    """

    // MARK: - Extension Popup

    /// Gets the scroll dimensions of the document body.
    ///
    /// Use with `evaluateJavaScript()`.
    ///
    /// Returns: JSON string of `{ width, height }`
    static let popupContentSize = """
    JSON.stringify({width: document.body.scrollWidth, height: document.body.scrollHeight})
    """

    // MARK: - Screenshot Element Selection

    /// Injects an element selection overlay for screenshot capture.
    ///
    /// Creates an interactive overlay that:
    /// - Highlights block-level elements on hover
    /// - Dims non-highlighted areas
    /// - Captures element bounds on click
    /// - Cancels on ESC key
    ///
    /// Returns: JSON string of selected element bounds `{ x, y, width, height }` or "cancelled"
    static let elementSelectionOverlay = """
        return new Promise((resolve) => {
            // Create overlay container
            const overlay = document.createElement('div');
            overlay.id = '__refrax_screenshot_overlay__';
            overlay.style.cssText = `
                position: fixed;
                top: 0; left: 0; right: 0; bottom: 0;
                z-index: 2147483647;
                pointer-events: none;
                cursor: crosshair;
            `;
    
            // Dimming layer (covers everything)
            const dimLayer = document.createElement('div');
            dimLayer.style.cssText = `
                position: fixed;
                top: 0; left: 0; right: 0; bottom: 0;
                background: rgba(0, 0, 0, 0.5);
                pointer-events: all;
                cursor: crosshair;
            `;
            overlay.appendChild(dimLayer);
    
            // Highlight box (cuts through the dim layer)
            const highlight = document.createElement('div');
            highlight.style.cssText = `
                position: fixed;
                pointer-events: none;
                border: 2px solid #007AFF;
                border-radius: 4px;
                box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.5);
                background: transparent;
                transition: all 0.1s ease-out;
                display: none;
            `;
            overlay.appendChild(highlight);
    
            // Instructions tooltip
            const tooltip = document.createElement('div');
            tooltip.style.cssText = `
                position: fixed;
                top: 20px;
                left: 50%;
                transform: translateX(-50%);
                background: rgba(0, 0, 0, 0.8);
                color: white;
                padding: 8px 16px;
                border-radius: 8px;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                pointer-events: none;
                z-index: 2147483647;
            `;
            tooltip.textContent = 'Click an element to capture • Press ESC to cancel';
            overlay.appendChild(tooltip);
    
            document.body.appendChild(overlay);
    
            let currentElement = null;
    
            // Find the best block element under cursor
            function findBlockElement(x, y) {
                // Temporarily hide overlay to hit-test real elements
                overlay.style.display = 'none';
                const element = document.elementFromPoint(x, y);
                overlay.style.display = '';
    
                if (!element || element === document.body || element === document.documentElement) {
                    return null;
                }
    
                // Walk up to find a suitable block container
                let el = element;
                const blockTags = ['DIV', 'SECTION', 'ARTICLE', 'MAIN', 'HEADER', 'FOOTER', 'NAV',
                                   'ASIDE', 'FIGURE', 'FORM', 'TABLE', 'UL', 'OL', 'P', 'BLOCKQUOTE',
                                   'PRE', 'CODE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'IMG', 'VIDEO',
                                   'CANVAS', 'SVG', 'IFRAME'];
    
                while (el && el !== document.body) {
                    const style = window.getComputedStyle(el);
                    const display = style.display;
                    const isBlock = blockTags.includes(el.tagName) ||
                                    display === 'block' ||
                                    display === 'flex' ||
                                    display === 'grid' ||
                                    display === 'table';
    
                    if (isBlock) {
                        const rect = el.getBoundingClientRect();
                        // Ensure element has reasonable size
                        if (rect.width > 20 && rect.height > 20) {
                            return el;
                        }
                    }
                    el = el.parentElement;
                }
    
                return element;
            }
    
            function updateHighlight(element) {
                if (!element) {
                    highlight.style.display = 'none';
                    dimLayer.style.background = 'rgba(0, 0, 0, 0.5)';
                    return;
                }
    
                const rect = element.getBoundingClientRect();
                highlight.style.display = 'block';
                highlight.style.left = rect.left + 'px';
                highlight.style.top = rect.top + 'px';
                highlight.style.width = rect.width + 'px';
                highlight.style.height = rect.height + 'px';
    
                // Make the dim layer transparent so highlight box-shadow creates the effect
                dimLayer.style.background = 'transparent';
            }
    
            function cleanup() {
                document.removeEventListener('mousemove', onMouseMove);
                document.removeEventListener('click', onClick, true);
                document.removeEventListener('keydown', onKeyDown, true);
                overlay.remove();
            }
    
            function onMouseMove(e) {
                const element = findBlockElement(e.clientX, e.clientY);
                if (element !== currentElement) {
                    currentElement = element;
                    updateHighlight(element);
                }
            }
    
            function onClick(e) {
                e.preventDefault();
                e.stopPropagation();
    
                if (currentElement) {
                    const rect = currentElement.getBoundingClientRect();
                    // Convert to page coordinates (account for scroll)
                    const result = {
                        x: rect.left + window.scrollX,
                        y: rect.top + window.scrollY,
                        width: rect.width,
                        height: rect.height
                    };
                    cleanup();
                    resolve(JSON.stringify(result));
                }
            }
    
            function onKeyDown(e) {
                if (e.key === 'Escape') {
                    e.preventDefault();
                    e.stopPropagation();
                    cleanup();
                    resolve('cancelled');
                }
            }
    
            document.addEventListener('mousemove', onMouseMove);
            document.addEventListener('click', onClick, true);
            document.addEventListener('keydown', onKeyDown, true);
    
            // Start with current mouse position
            // We can't know initial position, so wait for first move
        });
    """

    /// Removes the element selection overlay if it exists.
    static let removeElementSelectionOverlay = """
    (function() {
        const overlay = document.getElementById('__refrax_screenshot_overlay__');
        if (overlay) overlay.remove();
    })();
    """

    // MARK: - GIF Insertion

    /// Inserts a GIF into the currently focused input field.
    ///
    /// Handles both contenteditable elements (rich text editors) and standard
    /// input/textarea fields. For contenteditable, inserts an `<img>` element.
    /// For inputs, inserts the URL as text.
    ///
    /// - Parameters:
    ///   - gifURL: The URL of the GIF to insert
    ///   - altText: Alt text for the image (will be escaped)
    /// - Returns: Script that returns `true` if insertion succeeded, `false` otherwise
    static func insertGIF(url gifURL: String, altText: String) -> String {
        let urlJSON = jsonEncode(gifURL)
        let altJSON = jsonEncode(altText)

        return """
        (function() {
            const activeElement = document.activeElement;
            if (!activeElement) return false;
        
            // For contenteditable elements, insert as image
            if (activeElement.isContentEditable) {
                const img = document.createElement('img');
                img.src = \(urlJSON);
                img.alt = \(altJSON);
                img.style.maxWidth = '300px';
        
                const selection = window.getSelection();
                if (selection.rangeCount > 0) {
                    const range = selection.getRangeAt(0);
                    range.deleteContents();
                    range.insertNode(img);
                    range.setStartAfter(img);
                    range.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(range);
                    return true;
                }
            }
        
            // For input/textarea, insert URL as text
            if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
                const start = activeElement.selectionStart || 0;
                const end = activeElement.selectionEnd || 0;
                const url = \(urlJSON);
                activeElement.value = activeElement.value.substring(0, start) + url + activeElement.value.substring(end);
                activeElement.selectionStart = activeElement.selectionEnd = start + url.length;
                activeElement.dispatchEvent(new Event('input', { bubbles: true }));
                return true;
            }
        
            return false;
        })()
        """
    }

    // MARK: - Sticky Header Detection

    /// Detects if the page has a sticky or fixed position header that will stick at the top.
    ///
    /// Scans for elements with `position: sticky; top: 0` or `position: fixed` that span
    /// the viewport width. This detects sticky headers even before they've "stuck" -
    /// for example, a sticky nav below a hero section will be detected at page load.
    ///
    /// Use with `evaluateJavaScript()`.
    ///
    /// Returns: JSON object with detection result:
    /// ```json
    /// {
    ///   "hasStickyHeader": true,
    ///   "headerColor": "#ffffff",  // Sampled background color or null
    ///   "headerHeight": 64         // Height in pixels or null
    /// }
    /// ```
    static let detectStickyHeader = """
    (function() {
        let hasStickyHeader = false;
        let headerColor = null;
        let headerHeight = null;
        let stickyElement = null;
    
        const minWidth = window.innerWidth * 0.5;
    
        // Check if an element is inside a nested scroll container (modal, sidebar, etc.)
        // Sticky elements only stick within their scroll container, so we need to ensure
        // the sticky element is in the main page scroll context.
        function isInNestedScrollContainer(el) {
            let parent = el.parentElement;
            while (parent && parent !== document.body && parent !== document.documentElement) {
                const style = window.getComputedStyle(parent);
                const overflow = style.overflow + style.overflowY + style.overflowX;
                // Check for scroll/auto overflow (indicates nested scroll container)
                if (overflow.includes('scroll') || overflow.includes('auto')) {
                    // Exception: if the parent is nearly full viewport width, it's likely the main content
                    const rect = parent.getBoundingClientRect();
                    if (rect.width < window.innerWidth * 0.9) {
                        return true; // Nested in a narrower scroll container
                    }
                }
                parent = parent.parentElement;
            }
            return false;
        }
    
        // Scan all elements for sticky/fixed positioning that would stick at top
        const allElements = document.querySelectorAll('*');
        for (const el of allElements) {
            const style = window.getComputedStyle(el);
            const position = style.position;
    
            if (position === 'sticky' || position === 'fixed') {
                // Check visibility - skip hidden elements
                if (style.display === 'none') continue;
                if (style.visibility === 'hidden') continue;
                if (parseFloat(style.opacity) === 0) continue;
    
                // Check if it would stick at the top (top: 0 or small value)
                const topValue = parseFloat(style.top);
                if (isNaN(topValue) || topValue > 50) continue; // Skip if top is auto or > 50px
    
                const rect = el.getBoundingClientRect();
    
                // Must have actual dimensions (filter out collapsed elements)
                if (rect.width === 0 || rect.height === 0) continue;
    
                // Must span enough width (filter out sidebars, floating buttons)
                if (rect.width < minWidth) continue;
    
                // Must have reasonable height (filter out thin lines, borders)
                if (rect.height < 20) continue;
    
                // For fixed elements, check if at top of viewport
                if (position === 'fixed' && rect.top > 100) continue;
    
                // For sticky elements, ensure they're in the main page scroll context
                if (position === 'sticky' && isInNestedScrollContainer(el)) continue;
    
                // Found a sticky/fixed header candidate
                hasStickyHeader = true;
                stickyElement = el;
                headerHeight = rect.height;
                break;
            }
        }
    
        // Sample background color if we found a sticky header
        if (stickyElement) {
            const style = window.getComputedStyle(stickyElement);
            let bgColor = style.backgroundColor;
    
            // If transparent, try to find a visible background in children
            if (bgColor === 'rgba(0, 0, 0, 0)' || bgColor === 'transparent') {
                for (const child of stickyElement.children) {
                    const childStyle = window.getComputedStyle(child);
                    const childBg = childStyle.backgroundColor;
                    if (childBg && childBg !== 'rgba(0, 0, 0, 0)' && childBg !== 'transparent') {
                        bgColor = childBg;
                        break;
                    }
                }
            }
    
            if (bgColor && bgColor !== 'rgba(0, 0, 0, 0)' && bgColor !== 'transparent') {
                headerColor = bgColor;
            }
        }
    
        return JSON.stringify({
            hasStickyHeader: hasStickyHeader,
            headerColor: headerColor,
            headerHeight: headerHeight
        });
    })();
    """

    /// Quick check for sticky headers - returns just a boolean.
    ///
    /// Scans for elements with `position: sticky; top: 0` or `position: fixed`
    /// that span the viewport width. More efficient than `detectStickyHeader`
    /// when you only need yes/no.
    ///
    /// Use with `evaluateJavaScript()`.
    ///
    /// Returns: `true` if a sticky/fixed header exists that will stick at top
    static let hasStickyHeader = """
    (function() {
        const minWidth = window.innerWidth * 0.5;
    
        // Check if sticky element is in a nested scroll container
        function isInNestedScrollContainer(el) {
            let parent = el.parentElement;
            while (parent && parent !== document.body && parent !== document.documentElement) {
                const style = window.getComputedStyle(parent);
                const overflow = style.overflow + style.overflowY + style.overflowX;
                if (overflow.includes('scroll') || overflow.includes('auto')) {
                    const rect = parent.getBoundingClientRect();
                    if (rect.width < window.innerWidth * 0.9) return true;
                }
                parent = parent.parentElement;
            }
            return false;
        }
    
        const allElements = document.querySelectorAll('*');
        for (const el of allElements) {
            const style = window.getComputedStyle(el);
            const position = style.position;
    
            if (position === 'sticky' || position === 'fixed') {
                // Check visibility
                if (style.display === 'none') continue;
                if (style.visibility === 'hidden') continue;
                if (parseFloat(style.opacity) === 0) continue;
    
                const topValue = parseFloat(style.top);
                if (isNaN(topValue) || topValue > 50) continue;
    
                const rect = el.getBoundingClientRect();
                if (rect.width === 0 || rect.height === 0) continue;
                if (rect.width < minWidth || rect.height < 20) continue;
    
                if (position === 'fixed' && rect.top > 100) continue;
                if (position === 'sticky' && isInNestedScrollContainer(el)) continue;
    
                return true;
            }
        }
        return false;
    })();
    """

    // MARK: - Helpers

    /// JSON-encodes a string for safe embedding in JavaScript.
    private static func jsonEncode(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return jsonString
    }
}
