/**
 * Refrax Extension Shims - Base Module
 *
 * Provides namespace normalization and utility functions for WebExtension
 * API compatibility. This script runs at document start in extension contexts.
 *
 * Features:
 * - Normalizes `chrome.*` APIs to `browser.*` for Firefox-style extensions
 * - Provides promise wrappers for callback-based APIs
 * - Sets up the native bridge for shimmed APIs
 *
 * @version 1.0.0
 */

(function() {
    'use strict';

    // Avoid double-initialization
    if (window.__refraxShimsInitialized) {
        return;
    }
    window.__refraxShimsInitialized = true;

    // =========================================================================
    // Native Bridge
    // =========================================================================

    /**
     * Sends a message to the native shim handler and returns a promise.
     *
     * @param {string} api - The API namespace (e.g., 'storage.sync')
     * @param {string} method - The method name (e.g., 'get')
     * @param {object} args - Arguments to pass to the native handler
     * @returns {Promise<any>} The result from the native handler
     */
    window.__refraxShimCall = async function(api, method, args = {}) {
        return new Promise((resolve, reject) => {
            if (!window.webkit?.messageHandlers?.refraxShim) {
                reject(new Error('Refrax shim bridge not available'));
                return;
            }

            window.webkit.messageHandlers.refraxShim.postMessage({
                api: api,
                method: method,
                args: args
            }).then(response => {
                if (response && response.success) {
                    resolve(response.result);
                } else {
                    reject(new Error(response?.error || 'Unknown shim error'));
                }
            }).catch(error => {
                reject(error);
            });
        });
    };

    // =========================================================================
    // Namespace Normalization
    // =========================================================================

    /**
     * Ensures both `browser` and `chrome` namespaces exist.
     * WebKit provides `browser.*` natively; we alias `chrome.*` to it.
     */
    if (typeof browser !== 'undefined' && typeof chrome === 'undefined') {
        window.chrome = browser;
    } else if (typeof chrome !== 'undefined' && typeof browser === 'undefined') {
        window.browser = chrome;
    }

    // =========================================================================
    // Promise Utilities
    // =========================================================================

    /**
     * Wraps a callback-style function to return a Promise.
     * Used for normalizing Chrome-style callback APIs to Firefox-style promises.
     *
     * @param {Function} fn - The function to wrap
     * @param {any} thisArg - The `this` context for the function
     * @returns {Function} A function that returns a Promise
     */
    window.__promisify = function(fn, thisArg) {
        return function(...args) {
            return new Promise((resolve, reject) => {
                const callback = (result) => {
                    const err = chrome?.runtime?.lastError || browser?.runtime?.lastError;
                    if (err) {
                        reject(new Error(err.message || err));
                    } else {
                        resolve(result);
                    }
                };
                fn.apply(thisArg, [...args, callback]);
            });
        };
    };

    // =========================================================================
    // Event Emitter Utility
    // =========================================================================

    /**
     * Simple event emitter for shim events.
     * Implements the WebExtensions event interface (addListener, removeListener, hasListener).
     */
    class ShimEvent {
        constructor() {
            this._listeners = new Set();
        }

        addListener(callback) {
            this._listeners.add(callback);
        }

        removeListener(callback) {
            this._listeners.delete(callback);
        }

        hasListener(callback) {
            return this._listeners.has(callback);
        }

        hasListeners() {
            return this._listeners.size > 0;
        }

        _dispatch(...args) {
            for (const listener of this._listeners) {
                try {
                    listener(...args);
                } catch (e) {
                    console.error('[RefraxShim] Event listener error:', e);
                }
            }
        }
    }

    window.__ShimEvent = ShimEvent;

    // =========================================================================
    // Error Utilities
    // =========================================================================

    /**
     * Creates a standardized extension error.
     *
     * @param {string} message - The error message
     * @returns {Error} An error object with runtime.lastError semantics
     */
    window.__shimError = function(message) {
        const error = new Error(message);
        // Set lastError for APIs that check it
        if (typeof chrome !== 'undefined' && chrome.runtime) {
            chrome.runtime.lastError = { message };
        }
        if (typeof browser !== 'undefined' && browser.runtime) {
            browser.runtime.lastError = { message };
        }
        return error;
    };

    /**
     * Clears the lastError after an API call completes successfully.
     */
    window.__clearLastError = function() {
        if (typeof chrome !== 'undefined' && chrome.runtime) {
            chrome.runtime.lastError = undefined;
        }
        if (typeof browser !== 'undefined' && browser.runtime) {
            browser.runtime.lastError = undefined;
        }
    };

    // =========================================================================
    // Logging
    // =========================================================================

    const SHIM_PREFIX = '[RefraxShim]';

    window.__shimLog = {
        debug: (...args) => console.debug(SHIM_PREFIX, ...args),
        info: (...args) => console.info(SHIM_PREFIX, ...args),
        warn: (...args) => console.warn(SHIM_PREFIX, ...args),
        error: (...args) => console.error(SHIM_PREFIX, ...args)
    };

    // =========================================================================
    // Initialization Complete
    // =========================================================================

    window.__shimLog.debug('Base shims initialized');

})();
