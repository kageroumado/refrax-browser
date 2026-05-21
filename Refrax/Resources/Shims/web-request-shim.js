/**
 * Refrax Extension Shims - webRequest API
 *
 * Provides a noop shim for browser.webRequest API. This allows extensions like
 * uBlock Origin to load and function for cosmetic filtering and scriptlet
 * injection, while network blocking is handled natively by WebKit content rules.
 *
 * Why this approach:
 * - WebKit has no webRequest API equivalent
 * - Network blocking MUST use WKContentRuleList (declarative rules)
 * - uBlock's cosmetic filtering and scriptlets work via content scripts
 * - This shim lets uBlock load without errors and handle cosmetic/scriptlets
 * - Refrax's native filter compiler handles actual network blocking
 *
 * @version 1.0.0
 */

(function() {
    'use strict';

    // Avoid double-initialization
    if (window.__refraxWebRequestShimInitialized) {
        return;
    }
    window.__refraxWebRequestShimInitialized = true;

    const ShimEvent = window.__ShimEvent;
    const shimLog = window.__shimLog;

    // =========================================================================
    // webRequest Event Class
    // =========================================================================

    /**
     * A noop webRequest event that accepts listeners but never fires them.
     * Listeners are stored in case extensions check hasListener().
     */
    class WebRequestEvent {
        constructor(name) {
            this._name = name;
            this._listeners = new Map();  // callback -> { filter, extraInfoSpec }
        }

        /**
         * Adds a listener. The callback will never be invoked.
         *
         * @param {Function} callback - The listener function
         * @param {Object} filter - URL filter (urls, types, etc.)
         * @param {Array} extraInfoSpec - Extra info options (e.g., ['blocking'])
         */
        addListener(callback, filter = {}, extraInfoSpec = []) {
            this._listeners.set(callback, { filter, extraInfoSpec });
            shimLog.debug(`webRequest.${this._name}.addListener (noop)`, filter);
        }

        /**
         * Removes a listener.
         *
         * @param {Function} callback - The listener to remove
         */
        removeListener(callback) {
            this._listeners.delete(callback);
        }

        /**
         * Checks if a listener is registered.
         *
         * @param {Function} callback - The listener to check
         * @returns {boolean} True if the listener is registered
         */
        hasListener(callback) {
            return this._listeners.has(callback);
        }

        /**
         * Checks if any listeners are registered.
         *
         * @returns {boolean} True if any listeners are registered
         */
        hasListeners() {
            return this._listeners.size > 0;
        }
    }

    // =========================================================================
    // Resource Types
    // =========================================================================

    /**
     * WebRequest resource types.
     * These match the values used by Chrome/Firefox webRequest API.
     */
    const ResourceType = Object.freeze({
        MAIN_FRAME: 'main_frame',
        SUB_FRAME: 'sub_frame',
        STYLESHEET: 'stylesheet',
        SCRIPT: 'script',
        IMAGE: 'image',
        FONT: 'font',
        OBJECT: 'object',
        XMLHTTPREQUEST: 'xmlhttprequest',
        PING: 'ping',
        CSP_REPORT: 'csp_report',
        MEDIA: 'media',
        WEBSOCKET: 'websocket',
        WEBTRANSPORT: 'webtransport',
        WEBBUNDLE: 'webbundle',
        OTHER: 'other'
    });

    // =========================================================================
    // webRequest API
    // =========================================================================

    const webRequest = {
        // Event objects - all are noop implementations
        onBeforeRequest: new WebRequestEvent('onBeforeRequest'),
        onBeforeSendHeaders: new WebRequestEvent('onBeforeSendHeaders'),
        onSendHeaders: new WebRequestEvent('onSendHeaders'),
        onHeadersReceived: new WebRequestEvent('onHeadersReceived'),
        onAuthRequired: new WebRequestEvent('onAuthRequired'),
        onResponseStarted: new WebRequestEvent('onResponseStarted'),
        onBeforeRedirect: new WebRequestEvent('onBeforeRedirect'),
        onCompleted: new WebRequestEvent('onCompleted'),
        onErrorOccurred: new WebRequestEvent('onErrorOccurred'),

        // Resource types
        ResourceType: ResourceType,

        /**
         * Filter response data (Firefox only).
         * Returns undefined since WebKit doesn't support response body modification.
         *
         * @param {string} requestId - The request ID
         * @returns {undefined} Always returns undefined
         */
        filterResponseData: function(requestId) {
            shimLog.debug('webRequest.filterResponseData called (not supported)');
            return undefined;
        },

        /**
         * Handoff request (Firefox only).
         * Returns undefined since not supported.
         *
         * @param {string} requestId - The request ID
         * @returns {undefined} Always returns undefined
         */
        handoffRequest: function(requestId) {
            shimLog.debug('webRequest.handoffRequest called (not supported)');
            return undefined;
        },

        /**
         * Gets security info for a request (Firefox only).
         * Returns a rejected promise since not supported.
         *
         * @param {string} requestId - The request ID
         * @param {Object} options - Options for the call
         * @returns {Promise} Rejected promise
         */
        getSecurityInfo: function(requestId, options) {
            shimLog.debug('webRequest.getSecurityInfo called (not supported)');
            return Promise.reject(new Error('Not supported'));
        },

        // Constants
        MAX_HANDLER_BEHAVIOR_CHANGED_CALLS_PER_10_MINUTES: 20
    };

    // =========================================================================
    // Install webRequest on browser/chrome namespaces
    // =========================================================================

    // Ensure browser namespace exists
    if (typeof browser === 'undefined') {
        window.browser = {};
    }
    if (typeof chrome === 'undefined') {
        window.chrome = window.browser;
    }

    // Install webRequest
    browser.webRequest = webRequest;
    chrome.webRequest = webRequest;

    shimLog.debug('webRequest shim initialized (network blocking via native WebKit)');

})();
