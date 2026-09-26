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

    /**
     * Keeps a WebKit API object alive for the life of the page.
     *
     * `browser` and its namespaces are JavaScriptCore callback objects. WebKit caches the
     * object for each namespace weakly and makes a new one once the old is collected, so
     * members the shims define on it would disappear. Members must be defined on the
     * object itself: the class's own members are found before anything on the prototype.
     * Holding every patched object here keeps WebKit returning that same object.
     */
    const retainedNamespaces = new Set();
    Object.defineProperty(window, '__refraxRetainedNamespaces', { value: retainedNamespaces });

    function retain(object) {
        retainedNamespaces.add(object);
        return object;
    }

    function defineRetained(object, name, value) {
        try {
            Object.defineProperty(retain(object), name, { value, configurable: true, writable: true });
            return true;
        } catch (e) {
            window.__shimLog?.warn(`Could not add ${name}`, e);
            return false;
        }
    }

    /**
     * Makes every native API function callable without its namespace as `this`. Walks
     * two levels, so `storage.local.get` is covered.
     *
     * WebKit's native functions return `undefined` when called detached, while Chrome and
     * Firefox accept it, and extensions rely on that: uBlock Origin stores
     * `browser.runtime.getURL` in a variable, and its background page fails to start when
     * the call returns nothing. Each function is bound to its namespace, which stays
     * the object `browser` returns because it is retained.
     */
    function bindNamespaceFunctions(namespace, path) {
        if (!namespace || typeof namespace !== 'object' || path.length > 2) {
            return;
        }
        for (const key in namespace) {
            let value;
            try {
                value = namespace[key];
            } catch (e) {
                continue;
            }
            if (typeof value === 'function' && path.length > 0) {
                if (value.__refraxDetachable) {
                    continue;
                }
                const detachable = value.bind(namespace);
                detachable.__refraxDetachable = true;
                defineRetained(namespace, key, detachable);
            } else if (value && typeof value === 'object' && !key.startsWith('on')) {
                retain(value);
                bindNamespaceFunctions(value, [...path, key]);
            }
        }
    }

    if (typeof browser !== 'undefined') {
        bindNamespaceFunctions(browser, []);
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

    /** Defines `value` as `namespace[name]` when WebKit's namespace lacks it. */
    function addMissingMember(namespace, name, value) {
        if (!namespace || namespace[name] !== undefined) {
            return;
        }
        defineRetained(namespace, name, value);
    }

    /**
     * A `privacy` setting WebKit does not expose: reads report it as not controllable by
     * extensions, and writes are accepted and have no effect. uBlock Origin builds its
     * browser-settings helper only when `browser.privacy` exists, then reads that helper
     * unconditionally.
     */
    function uncontrollableSetting(value) {
        return {
            get: () => Promise.resolve({ value, levelOfControl: 'not_controllable' }),
            set: () => Promise.resolve(),
            clear: () => Promise.resolve(),
            onChange: new ShimEvent(),
        };
    }

    if (typeof browser !== 'undefined') {
        addMissingMember(browser, 'privacy', {
            network: {
                networkPredictionEnabled: uncontrollableSetting(true),
                webRTCIPHandlingPolicy: uncontrollableSetting('default'),
            },
            services: {
                passwordSavingEnabled: uncontrollableSetting(true),
            },
            websites: {
                hyperlinkAuditingEnabled: uncontrollableSetting(true),
                thirdPartyCookiesAllowed: uncontrollableSetting(false),
            },
        });

        // Chrome's cache flush after listener changes. WebKit's webRequest only observes,
        // so there is nothing to flush.
        addMissingMember(browser.webRequest, 'handlerBehaviorChanged', function(callback) {
            if (typeof callback === 'function') {
                callback();
            }
            return Promise.resolve();
        });
    }

    /**
     * Menu items whose URL patterns WebKit cannot match: it accepts only these schemes, and
     * rejects the whole `menus.create` call otherwise (uBlock Origin's `abp:*` item for
     * filter-list subscription links). Such patterns are dropped; an item left with none is
     * not created, since an item without patterns would show on every page.
     */
    const matchableSchemes = new Set(['*', 'http', 'https', 'file', 'ftp', 'webkit-extension']);
    const patternKeys = ['targetUrlPatterns', 'documentUrlPatterns'];

    function isMatchablePattern(pattern) {
        if (pattern === '<all_urls>') {
            return true;
        }
        const separator = pattern.indexOf('://');
        return separator > 0 && matchableSchemes.has(pattern.slice(0, separator));
    }

    function matchableProperties(properties) {
        if (!properties || typeof properties !== 'object') {
            return properties;
        }
        const result = { ...properties };
        for (const key of patternKeys) {
            if (!Array.isArray(result[key])) {
                continue;
            }
            const patterns = result[key].filter(isMatchablePattern);
            if (patterns.length === 0) {
                return null;
            }
            result[key] = patterns;
        }
        return result;
    }

    function wrapMenus(namespace) {
        if (!namespace || typeof namespace.create !== 'function') {
            return;
        }
        if (namespace.__refraxMenusWrapped) {
            return;
        }
        const create = namespace.create;
        const update = namespace.update;
        defineRetained(namespace, '__refraxMenusWrapped', true);
        defineRetained(namespace, 'create', function(properties, callback) {
            const matchable = matchableProperties(properties);
            if (matchable === null) {
                if (typeof callback === 'function') {
                    callback();
                }
                return properties.id;
            }
            return create.call(this, matchable, callback);
        });
        if (typeof update === 'function') {
            defineRetained(namespace, 'update', function(id, properties, callback) {
                return update.call(this, id, matchableProperties(properties) ?? {}, callback);
            });
        }
    }

    if (typeof browser !== 'undefined') {
        wrapMenus(browser.menus);
        wrapMenus(browser.contextMenus);
    }

    /**
     * `requestIdleCallback`, which WebKit keeps behind a feature flag. Extensions written
     * for Chrome and Firefox call it unguarded (uBlock Origin schedules badge updates with
     * it). Runs the callback on a short timer with a fixed time budget.
     */
    if (typeof self.requestIdleCallback !== 'function') {
        const idleBudgetMs = 50;
        self.requestIdleCallback = function(callback) {
            const start = Date.now();
            return setTimeout(() => {
                callback({
                    didTimeout: false,
                    timeRemaining: () => Math.max(0, idleBudgetMs - (Date.now() - start)),
                });
            }, 1);
        };
        self.cancelIdleCallback = function(handle) {
            clearTimeout(handle);
        };
    }

    /**
     * Events Chrome and Firefox provide that WebKit does not. They accept listeners and
     * never fire, so extensions that subscribe during startup keep loading: uBlock Origin
     * subscribes to `webNavigation.onCreatedNavigationTarget` while building its tab
     * tracker, and without the event its whole background page fails.
     */
    const missingEvents = {
        runtime: ['onUpdateAvailable'],
        webNavigation: [
            'onCreatedNavigationTarget',
            'onHistoryStateUpdated',
            'onReferenceFragmentUpdated',
            'onTabReplaced',
        ],
    };
    if (typeof browser !== 'undefined') {
        for (const [namespaceName, eventNames] of Object.entries(missingEvents)) {
            const namespace = browser[namespaceName];
            if (!namespace) {
                continue;
            }
            for (const eventName of eventNames) {
                if (namespace[eventName] !== undefined) {
                    continue;
                }
                defineRetained(namespace, eventName, new ShimEvent());
            }
        }
    }

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
