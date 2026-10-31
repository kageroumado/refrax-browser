// Records what an extension asks of the browser that the browser does not give it: API
// members it reads that are absent, API calls that throw or reject, and uncaught errors.
// The compatibility harness injects it at document start, after Refrax's shims, into
// extension pages (role "page") and into the extension's content script world on a web
// page (role "content"). Records go to webkit.messageHandlers.refraxCompatProbe.
(function () {
    'use strict';
    const g = globalThis;
    if (g.__refraxCompatProbe) {
        return;
    }
    Object.defineProperty(g, '__refraxCompatProbe', { value: true });

    const role = '__ROLE__';
    function post(record) {
        try {
            record.role = role;
            record.page = String(g.location && g.location.href);
            g.webkit.messageHandlers.refraxCompatProbe.postMessage(record);
        } catch (e) {
            // The page has no handler: nothing to report to.
        }
    }
    function describe(error) {
        return String((error && error.message) || error);
    }

    // The members Chrome and Firefox extensions commonly use, by namespace.
    const expected = {
        action: ['setBadgeText', 'getBadgeText', 'setBadgeBackgroundColor', 'getBadgeBackgroundColor', 'setBadgeTextColor',
            'setTitle', 'getTitle', 'setIcon', 'setPopup', 'getPopup', 'enable', 'disable', 'isEnabled', 'openPopup',
            'getUserSettings', 'onClicked'],
        browserAction: ['setBadgeText', 'getBadgeText', 'setBadgeBackgroundColor', 'setTitle', 'getTitle', 'setIcon',
            'setPopup', 'getPopup', 'enable', 'disable', 'openPopup', 'onClicked'],
        pageAction: ['show', 'hide', 'setIcon', 'setTitle', 'setPopup', 'onClicked'],
        alarms: ['create', 'get', 'getAll', 'clear', 'clearAll', 'onAlarm'],
        bookmarks: ['get', 'getTree', 'search', 'create', 'update', 'remove', 'onCreated', 'onRemoved', 'onChanged'],
        browsingData: ['remove', 'removeCache', 'removeCookies'],
        commands: ['getAll', 'onCommand'],
        contextMenus: ['create', 'update', 'remove', 'removeAll', 'onClicked'],
        menus: ['create', 'update', 'remove', 'removeAll', 'refresh', 'onClicked', 'onShown', 'onHidden'],
        cookies: ['get', 'getAll', 'set', 'remove', 'getAllCookieStores', 'onChanged'],
        declarativeNetRequest: ['updateDynamicRules', 'getDynamicRules', 'updateSessionRules', 'getSessionRules',
            'updateEnabledRulesets', 'getEnabledRulesets', 'updateStaticRules', 'isRegexSupported',
            'setExtensionActionOptions', 'getMatchedRules', 'testMatchOutcome', 'onRuleMatchedDebug'],
        downloads: ['download', 'search', 'cancel', 'open', 'show', 'erase', 'onCreated', 'onChanged'],
        extension: ['getURL', 'getBackgroundPage', 'getViews', 'isAllowedIncognitoAccess'],
        history: ['search', 'getVisits', 'addUrl', 'deleteUrl', 'deleteAll', 'onVisited'],
        i18n: ['getMessage', 'getUILanguage', 'getAcceptLanguages', 'detectLanguage'],
        identity: ['getRedirectURL', 'launchWebAuthFlow'],
        idle: ['queryState', 'setDetectionInterval', 'onStateChanged'],
        management: ['getSelf', 'getAll', 'onEnabled', 'onDisabled'],
        notifications: ['create', 'clear', 'getAll', 'onClicked', 'onClosed', 'onButtonClicked'],
        offscreen: ['createDocument', 'closeDocument', 'hasDocument'],
        permissions: ['contains', 'getAll', 'request', 'remove', 'onAdded', 'onRemoved'],
        privacy: ['network', 'services', 'websites'],
        runtime: ['getURL', 'getManifest', 'sendMessage', 'connect', 'onMessage', 'onConnect', 'onInstalled',
            'onStartup', 'onSuspend', 'getPlatformInfo', 'getBrowserInfo', 'openOptionsPage', 'setUninstallURL',
            'reload', 'getContexts', 'sendNativeMessage', 'connectNative', 'onMessageExternal', 'onConnectExternal',
            'onUpdateAvailable', 'requestUpdateCheck', 'getBackgroundPage'],
        scripting: ['executeScript', 'insertCSS', 'removeCSS', 'registerContentScripts', 'unregisterContentScripts',
            'getRegisteredContentScripts', 'updateContentScripts'],
        search: ['query', 'search'],
        sessions: ['getRecentlyClosed', 'restore', 'onChanged'],
        sidePanel: ['setOptions', 'setPanelBehavior', 'open'],
        sidebarAction: ['open', 'close', 'toggle', 'setPanel'],
        storage: ['local', 'sync', 'session', 'managed', 'onChanged'],
        'storage.local': ['get', 'set', 'remove', 'clear', 'getBytesInUse', 'onChanged'],
        'storage.sync': ['get', 'set', 'remove', 'clear', 'getBytesInUse', 'onChanged'],
        'storage.session': ['get', 'set', 'remove', 'clear', 'setAccessLevel'],
        tabs: ['query', 'get', 'getCurrent', 'create', 'update', 'remove', 'reload', 'duplicate', 'sendMessage',
            'connect', 'executeScript', 'insertCSS', 'removeCSS', 'captureVisibleTab', 'detectLanguage', 'getZoom',
            'setZoom', 'move', 'highlight', 'discard', 'goBack', 'goForward', 'group', 'ungroup', 'onCreated',
            'onUpdated', 'onRemoved', 'onActivated', 'onMoved', 'onReplaced', 'onHighlighted', 'onAttached',
            'onDetached', 'onZoomChange'],
        tabGroups: ['query', 'get', 'update', 'onUpdated'],
        theme: ['getCurrent', 'update', 'onUpdated'],
        topSites: ['get'],
        tts: ['speak', 'stop'],
        userScripts: ['register', 'getScripts', 'unregister', 'update', 'configureWorld'],
        webNavigation: ['getFrame', 'getAllFrames', 'onBeforeNavigate', 'onCommitted', 'onDOMContentLoaded',
            'onCompleted', 'onErrorOccurred', 'onCreatedNavigationTarget', 'onHistoryStateUpdated',
            'onReferenceFragmentUpdated', 'onTabReplaced'],
        webRequest: ['onBeforeRequest', 'onBeforeSendHeaders', 'onSendHeaders', 'onHeadersReceived', 'onAuthRequired',
            'onResponseStarted', 'onBeforeRedirect', 'onCompleted', 'onErrorOccurred', 'handlerBehaviorChanged'],
        windows: ['get', 'getCurrent', 'getLastFocused', 'getAll', 'create', 'update', 'remove', 'onCreated',
            'onRemoved', 'onFocusChanged'],
    };
    // What a content script may use in Chrome and Firefox; anything else is absent there too.
    const contentNamespaces = new Set(['runtime', 'storage', 'storage.local', 'storage.sync', 'storage.session',
        'i18n', 'extension']);

    const retained = [];
    Object.defineProperty(g, '__refraxCompatRetained', { value: retained });

    function resolve(root, path) {
        let object = root;
        for (const key of path.split('.')) {
            try {
                object = object == null ? undefined : object[key];
            } catch (e) {
                return undefined;
            }
        }
        return object;
    }

    function recordWhenRead(object, key, api) {
        try {
            Object.defineProperty(object, key, {
                configurable: true,
                get() {
                    post({ type: 'missing', api });
                    return undefined;
                },
            });
        } catch (e) {
            // A namespace that refuses new members cannot report reads.
        }
    }

    function wrap(object, key, api) {
        const original = object[key];
        const wrapped = function (...args) {
            const last = args.length - 1;
            if (last >= 0 && typeof args[last] === 'function') {
                const callback = args[last];
                args[last] = function (...results) {
                    const error = (g.chrome && g.chrome.runtime && g.chrome.runtime.lastError)
                        || (g.browser && g.browser.runtime && g.browser.runtime.lastError);
                    if (error) {
                        post({ type: 'lastError', api, message: describe(error) });
                    }
                    return callback.apply(this, results);
                };
            }
            let result;
            try {
                result = original.apply(object, args);
            } catch (error) {
                post({ type: 'throw', api, message: describe(error) });
                throw error;
            }
            if (result && typeof result.then === 'function') {
                result.then(undefined, (error) => post({ type: 'reject', api, message: describe(error) }));
            }
            return result;
        };
        try {
            Object.defineProperty(object, key, { configurable: true, writable: true, value: wrapped });
        } catch (e) {
            // A member that cannot be replaced is left unobserved.
        }
    }

    function instrument(root) {
        for (const [path, members] of Object.entries(expected)) {
            if (role === 'content' && !contentNamespaces.has(path)) {
                continue;
            }
            const parentPath = path.split('.').slice(0, -1).join('.');
            const name = path.split('.').pop();
            const parent = parentPath ? resolve(root, parentPath) : root;
            const namespace = resolve(root, path);
            if (namespace == null) {
                if (parent != null) {
                    recordWhenRead(parent, name, path);
                }
                continue;
            }
            retained.push(namespace);
            for (const member of members) {
                let value;
                try {
                    value = namespace[member];
                } catch (e) {
                    value = undefined;
                }
                if (value === undefined) {
                    recordWhenRead(namespace, member, path + '.' + member);
                } else if (typeof value === 'function') {
                    wrap(namespace, member, path + '.' + member);
                }
            }
        }
    }

    const roots = [g.browser, g.chrome].filter((root, index, all) => root && all.indexOf(root) === index);
    if (roots.length === 0) {
        post({ type: 'noBrowserNamespace' });
    }
    roots.forEach(instrument);

    if (typeof g.addEventListener === 'function') {
        g.addEventListener('error', (event) => {
            post({
                type: 'uncaught',
                message: describe(event.error || event.message),
                source: String(event.filename || ''),
                line: event.lineno || 0,
            });
        });
        g.addEventListener('unhandledrejection', (event) => {
            post({ type: 'unhandledRejection', message: describe(event.reason) });
        });
    }
    post({ type: 'alive' });
})();
