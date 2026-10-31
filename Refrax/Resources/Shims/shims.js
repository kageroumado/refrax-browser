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
     * WebKit's webRequest reports a frame's document as `main_frame` whatever the frame:
     * an iframe's request arrives with `type: 'main_frame'` and its own nonzero `frameId`.
     * Chrome and Firefox call it `sub_frame`, and extensions act on the difference: uBlock
     * Origin answers a blocked `main_frame` by replacing the whole tab with its
     * "page blocked" warning, so a blocked tracking iframe (Pinterest's
     * `ct.pinterest.com/ct.html`) took over the tab. A main frame's `frameId` is always 0,
     * so listeners get `sub_frame` for any other frame. A filter asking for `sub_frame`
     * also asks WebKit for `main_frame`, and the listener only sees the types it asked for.
     */
    const webRequestEventNames = [
        'onBeforeRequest',
        'onBeforeSendHeaders',
        'onSendHeaders',
        'onHeadersReceived',
        'onAuthRequired',
        'onResponseStarted',
        'onBeforeRedirect',
        'onCompleted',
        'onErrorOccurred',
    ];

    function withFrameType(details) {
        if (details && details.type === 'main_frame' && details.frameId !== 0) {
            return Object.assign({}, details, { type: 'sub_frame' });
        }
        return details;
    }

    function wrapFrameTypes(event) {
        if (event.__refraxFrameTypes) {
            return;
        }
        const addListener = event.addListener.bind(event);
        const removeListener = event.removeListener.bind(event);
        const hasListener = event.hasListener.bind(event);
        const listeners = new Map();
        defineRetained(event, '__refraxFrameTypes', true);
        defineRetained(event, 'addListener', function(callback, filter, extraInfoSpec) {
            if (listeners.has(callback)) {
                return;
            }
            const types = filter && Array.isArray(filter.types) ? filter.types : null;
            let nativeFilter = filter;
            if (types && types.includes('sub_frame') && !types.includes('main_frame')) {
                nativeFilter = Object.assign({}, filter, { types: [...types, 'main_frame'] });
            }
            // WebKit rejects the whole listener over one URL pattern it cannot match
            // (Privacy Badger's `ws://*/*`), which stops the background page. The patterns
            // it can match stay; a listener left with none never fires anyway.
            if (nativeFilter && Array.isArray(nativeFilter.urls)) {
                const urls = nativeFilter.urls.filter(isMatchablePattern);
                if (urls.length === 0) {
                    return undefined;
                }
                if (urls.length !== nativeFilter.urls.length) {
                    nativeFilter = Object.assign({}, nativeFilter, { urls });
                }
            }
            const listener = function(details, ...rest) {
                const corrected = withFrameType(details);
                if (types && corrected && !types.includes(corrected.type)) {
                    return undefined;
                }
                return callback.call(this, corrected, ...rest);
            };
            listeners.set(callback, listener);
            return extraInfoSpec === undefined
                ? addListener(listener, nativeFilter)
                : addListener(listener, nativeFilter, extraInfoSpec);
        });
        defineRetained(event, 'removeListener', function(callback) {
            const listener = listeners.get(callback);
            listeners.delete(callback);
            return removeListener(listener ?? callback);
        });
        defineRetained(event, 'hasListener', function(callback) {
            const listener = listeners.get(callback);
            return listener ? hasListener(listener) : false;
        });
    }

    // The event objects themselves cannot be replaced: WebKit's own member wins over a
    // defined one. Their functions can, as with the namespaces' functions above.
    if (typeof browser !== 'undefined' && browser.webRequest) {
        for (const name of webRequestEventNames) {
            const event = browser.webRequest[name];
            if (event && typeof event.addListener === 'function') {
                wrapFrameTypes(event);
            }
        }
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
     * Chrome's `webRequest` option enums. Extensions read them unguarded when they add
     * listeners: Stylus's background page stops at
     * `chrome.webRequest.OnHeadersReceivedOptions.EXTRA_HEADERS`.
     */
    if (typeof browser !== 'undefined' && browser.webRequest) {
        const webRequestOptions = {
            OnBeforeRequestOptions: { BLOCKING: 'blocking', REQUEST_BODY: 'requestBody', EXTRA_HEADERS: 'extraHeaders' },
            OnBeforeSendHeadersOptions: { REQUEST_HEADERS: 'requestHeaders', BLOCKING: 'blocking', EXTRA_HEADERS: 'extraHeaders' },
            OnSendHeadersOptions: { REQUEST_HEADERS: 'requestHeaders', EXTRA_HEADERS: 'extraHeaders' },
            OnHeadersReceivedOptions: { BLOCKING: 'blocking', RESPONSE_HEADERS: 'responseHeaders', EXTRA_HEADERS: 'extraHeaders' },
            OnAuthRequiredOptions: { RESPONSE_HEADERS: 'responseHeaders', BLOCKING: 'blocking', ASYNC_BLOCKING: 'asyncBlocking', EXTRA_HEADERS: 'extraHeaders' },
            OnResponseStartedOptions: { RESPONSE_HEADERS: 'responseHeaders', EXTRA_HEADERS: 'extraHeaders' },
            OnBeforeRedirectOptions: { RESPONSE_HEADERS: 'responseHeaders', EXTRA_HEADERS: 'extraHeaders' },
            OnCompletedOptions: { RESPONSE_HEADERS: 'responseHeaders', EXTRA_HEADERS: 'extraHeaders' },
            OnErrorOccurredOptions: { EXTRA_HEADERS: 'extraHeaders' },
            ResourceType: {
                MAIN_FRAME: 'main_frame', SUB_FRAME: 'sub_frame', STYLESHEET: 'stylesheet', SCRIPT: 'script',
                IMAGE: 'image', FONT: 'font', OBJECT: 'object', XMLHTTPREQUEST: 'xmlhttprequest', PING: 'ping',
                CSP_REPORT: 'csp_report', MEDIA: 'media', WEBSOCKET: 'websocket', OTHER: 'other',
            },
        };
        for (const [name, values] of Object.entries(webRequestOptions)) {
            addMissingMember(browser.webRequest, name, Object.freeze(values));
        }
    }

    /**
     * Firefox's `runtime.getBrowserInfo`. Firefox add-ons call it unguarded at startup and
     * stop when it is missing (Vimium C's background page, Violentmonkey). The version is
     * empty: Refrax is not Firefox, and an add-on that gates features on the Firefox version
     * falls back to its default.
     */
    if (typeof browser !== 'undefined' && browser.runtime) {
        addMissingMember(browser.runtime, 'getBrowserInfo', function(callback) {
            const info = { name: 'Refrax', vendor: 'Refrax', version: '', buildID: '' };
            if (typeof callback === 'function') {
                callback(info);
            }
            return Promise.resolve(info);
        });
    }

    /**
     * `management.getSelf`, which any extension may call without the `management` permission;
     * Refined GitHub reads its own install type with it. The rest of `management` stays absent.
     */
    if (typeof browser !== 'undefined' && browser.runtime && browser.management === undefined) {
        const self = () => {
            const manifest = browser.runtime.getManifest();
            return {
                id: browser.runtime.id,
                name: manifest.name,
                shortName: manifest.short_name || manifest.name,
                description: manifest.description || '',
                version: manifest.version,
                versionName: manifest.version_name,
                mayDisable: true,
                enabled: true,
                installType: 'normal',
                type: 'extension',
                offlineEnabled: false,
                optionsUrl: '',
                permissions: (manifest.permissions || []).filter((permission) => !permission.includes('://')),
                hostPermissions: manifest.host_permissions || [],
            };
        };
        addMissingMember(browser, 'management', {
            getSelf(callback) {
                const info = self();
                if (typeof callback === 'function') {
                    callback(info);
                }
                return Promise.resolve(info);
            },
            onEnabled: new ShimEvent(),
            onDisabled: new ShimEvent(),
            onInstalled: new ShimEvent(),
            onUninstalled: new ShimEvent(),
        });
    }

    /**
     * Permissions WebKit does not know. It throws on a `permissions.contains` or `request`
     * naming one, where Chrome and Firefox answer: Violentmonkey's background page stops on
     * `contains({permissions: ['downloads']})`, Vimium C's options page on `bookmarks`.
     * Permissions Refrax provides with its own shims are answered by the browser, which keeps
     * their grants and asks the user on `request`; any other unknown permission is not
     * granted; WebKit answers for the rest.
     */
    const refraxPermissions = new Set(['downloads', 'downloads.open', 'idle', 'notifications', 'privacy']);

    function wrapPermissions(namespace) {
        if (!namespace || typeof namespace.contains !== 'function' || namespace.__refraxPermissionsWrapped) {
            return;
        }
        const native = {
            contains: namespace.contains,
            request: namespace.request,
            remove: namespace.remove,
            getAll: namespace.getAll,
        };
        defineRetained(namespace, '__refraxPermissionsWrapped', true);

        // The query split into Refrax's permissions and the rest.
        function split(query) {
            const permissions = (query && query.permissions) || [];
            const ours = permissions.filter((permission) => refraxPermissions.has(permission));
            const rest = Object.assign({}, query, {
                permissions: permissions.filter((permission) => !refraxPermissions.has(permission)),
            });
            const isEmpty = rest.permissions.length === 0 && !(rest.origins && rest.origins.length);
            return { ours, rest, isEmpty };
        }

        function settle(promise, callback) {
            if (typeof callback === 'function') {
                promise.then(callback, () => callback(false));
            }
            return promise;
        }

        function askNative(method, query) {
            let answer;
            try {
                answer = Promise.resolve(native[method].call(namespace, query));
            } catch (error) {
                answer = Promise.reject(error);
            }
            return answer.catch((error) => {
                if (/not a valid permission/.test(String(error && error.message))) {
                    return false;
                }
                throw error;
            });
        }

        function askRefrax(method, permissions) {
            return window.__refraxShimCall('permissions', method, { permissions });
        }

        for (const method of ['contains', 'request']) {
            if (typeof native[method] !== 'function') {
                continue;
            }
            defineRetained(namespace, method, function(query, callback) {
                const { ours, rest, isEmpty } = split(query);
                const answers = [];
                if (ours.length > 0) {
                    answers.push(askRefrax(method, ours));
                }
                if (!isEmpty) {
                    answers.push(askNative(method, rest));
                }
                const result = Promise.all(answers).then((values) => values.every(Boolean));
                return settle(result, callback);
            });
        }
        if (typeof native.remove === 'function') {
            defineRetained(namespace, 'remove', function(query, callback) {
                const { ours, rest, isEmpty } = split(query);
                const answers = [];
                if (ours.length > 0) {
                    answers.push(askRefrax('remove', ours));
                }
                if (!isEmpty) {
                    answers.push(Promise.resolve(native.remove.call(namespace, rest)));
                }
                const result = Promise.all(answers).then((values) => values.length > 0 && values.every(Boolean));
                return settle(result, callback);
            });
        }
        if (typeof native.getAll === 'function') {
            defineRetained(namespace, 'getAll', function(callback) {
                const result = Promise.all([Promise.resolve(native.getAll.call(namespace)), askRefrax('getAll', [])])
                    .then(([all, ours]) => {
                        return Object.assign({}, all, { permissions: [...new Set([...(all.permissions || []), ...ours])] });
                    });
                if (typeof callback === 'function') {
                    result.then(callback);
                }
                return result;
            });
        }
    }

    if (typeof browser !== 'undefined') {
        wrapPermissions(browser.permissions);
    }

    /**
     * `storage.managed`, the enterprise policy area: always empty in Refrax, which applies no
     * policies. uBlock Origin, Privacy Badger and Bitwarden read it at startup.
     */
    if (typeof browser !== 'undefined' && browser.storage && browser.storage.managed === undefined) {
        const answer = (value, callback) => {
            if (typeof callback === 'function') {
                callback(value);
            }
            return Promise.resolve(value);
        };
        addMissingMember(browser.storage, 'managed', {
            get: (keys, callback) => answer({}, typeof keys === 'function' ? keys : callback),
            getBytesInUse: (keys, callback) => answer(0, typeof keys === 'function' ? keys : callback),
            onChanged: new ShimEvent(),
        });
    }

    /**
     * `idle`, which WebKit lacks, backed by the system (IdleShim.swift): `locked` while the
     * screen is locked, `idle` after the detection interval without input. Password managers
     * lock their vaults on these. `onStateChanged` fires on each transition while it has
     * listeners: the page keeps one request open that the browser answers when the state
     * changes. Present only for extensions that declare the `idle` permission, as in Chrome
     * and Firefox; `getAutoLockDelay` is ChromeOS-only and stays absent.
     */
    const declaresIdle = typeof browser !== 'undefined' && browser.runtime && typeof browser.runtime.getManifest === 'function'
        && [...(browser.runtime.getManifest().permissions || []), ...(browser.runtime.getManifest().optional_permissions || [])]
            .includes('idle');
    if (declaresIdle) {
        const defaultDetectionInterval = 60;
        let detectionInterval = defaultDetectionInterval;
        const stateChanges = new ShimEvent();
        let isWatching = false;

        const watch = async () => {
            if (isWatching) {
                return;
            }
            isWatching = true;
            try {
                let state = await window.__refraxShimCall('idle', 'queryState', { detectionInterval });
                while (stateChanges.hasListeners()) {
                    const next = await window.__refraxShimCall('idle', 'waitForChange', { detectionInterval, state });
                    if (next !== state) {
                        state = next;
                        stateChanges._dispatch(state);
                    }
                }
            } catch (e) {
                window.__shimLog.warn('idle state watch stopped', e);
            } finally {
                isWatching = false;
            }
        };

        addMissingMember(browser, 'idle', {
            queryState(interval, callback) {
                const state = window.__refraxShimCall('idle', 'queryState', { detectionInterval: interval });
                if (typeof callback === 'function') {
                    state.then(callback);
                }
                return state;
            },
            setDetectionInterval(interval) {
                detectionInterval = Number(interval) || defaultDetectionInterval;
            },
            onStateChanged: {
                addListener(callback) {
                    stateChanges.addListener(callback);
                    watch();
                },
                removeListener: (callback) => stateChanges.removeListener(callback),
                hasListener: (callback) => stateChanges.hasListener(callback),
                hasListeners: () => stateChanges.hasListeners(),
            },
        });
    }

    /**
     * `setIcon` given both `path` and `imageData`, which Chrome and Firefox accept, preferring
     * the image data; WebKit throws. Violentmonkey's popup sets its icon that way.
     */
    for (const name of ['action', 'browserAction', 'pageAction']) {
        const namespace = typeof browser !== 'undefined' ? browser[name] : undefined;
        if (!namespace || typeof namespace.setIcon !== 'function' || namespace.setIcon.__refraxIconData) {
            continue;
        }
        const setIcon = namespace.setIcon;
        const wrapped = function(details, ...rest) {
            if (details && details.imageData !== undefined && details.path !== undefined) {
                const { path, ...imageOnly } = details;
                return setIcon.call(namespace, imageOnly, ...rest);
            }
            return setIcon.call(namespace, details, ...rest);
        };
        wrapped.__refraxIconData = true;
        wrapped.__refraxDetachable = true;
        defineRetained(namespace, 'setIcon', wrapped);
    }

    /**
     * `tabs.query` with a window type Refrax has no windows of. WebKit accepts only `normal`
     * and `popup` and throws on Chrome's `app` and `devtools`, which Dark Reader's popup asks
     * for while it looks for the active tab; no tab matches such a query.
     */
    if (typeof browser !== 'undefined' && browser.tabs && typeof browser.tabs.query === 'function'
        && !browser.tabs.query.__refraxWindowTypes) {
        const query = browser.tabs.query;
        const knownWindowTypes = new Set(['normal', 'popup']);
        const wrapped = function(queryInfo, callback) {
            if (queryInfo && queryInfo.windowType !== undefined && !knownWindowTypes.has(queryInfo.windowType)) {
                if (typeof callback === 'function') {
                    callback([]);
                }
                return Promise.resolve([]);
            }
            return query.apply(this, arguments);
        };
        wrapped.__refraxWindowTypes = true;
        wrapped.__refraxDetachable = true;
        defineRetained(browser.tabs, 'query', wrapped);
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
