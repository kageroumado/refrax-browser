import Foundation
import JavaScriptCore
import Testing
@testable import Refrax

/// Runs the bundled extension shims in JavaScriptCore against a `browser` object that
/// behaves like WebKit's.
///
/// The model: `browser` is a plain global; each namespace is a getter on it whose object
/// comes from a weak cache, so `collectGarbage()` drops every cached object the page does
/// not hold and the next access builds a fresh one; API functions are own members that an
/// own property can override. Native `runtime.getURL` returns `undefined` unless called on
/// its namespace, as WebKit's does.
@Suite("Extension Shims")
@MainActor
struct ExtensionShimTests {
    private static let webKitModel = """
    var window = this;
    var self = this;
    var console = { debug() {}, info() {}, warn() {}, error() {}, log() {} };
    var setTimeout = function(callback) { return 0; };
    var clearTimeout = function() {};
    var webkit = { messageHandlers: { refraxShim: { postMessage() { return Promise.resolve({ success: true }); } } } };
    
    class NativeEvent {
        constructor() { this.listeners = []; }
        addListener(listener, filter) {
            if (filter && filter.urls && filter.urls.some(url => url.startsWith('ws'))) {
                throw new Error('Invalid call to addListener(): invalid match pattern');
            }
            this.listeners.push({ listener, filter });
        }
        removeListener(listener) { this.listeners = this.listeners.filter(entry => entry.listener !== listener); }
        hasListener(listener) { return this.listeners.some(entry => entry.listener === listener); }
        fire(details) {
            for (const { listener, filter } of this.listeners) {
                if (filter && filter.types && !filter.types.includes(details.type)) { continue; }
                listener(details);
            }
        }
    }
    const nativeFunctions = {
        runtime: {
            getURL(path) { return this && this.__kind === 'runtime' ? 'webkit-extension://test/' + path : undefined; },
            getManifest() {
                return { name: 'Model', version: '2.0', permissions: ['tabs'], optional_permissions: ['downloads'] };
            },
        },
        webNavigation: { getFrame() {} },
        webRequest: {},
        menus: {
            create(properties) {
                for (const pattern of properties.targetUrlPatterns || []) {
                    if (pattern !== '<all_urls>' && !/^(\\*|https?|file|ftp|webkit-extension):\\/\\//.test(pattern)) {
                        throw new Error('Invalid call to menus.create()');
                    }
                }
                return properties.id;
            },
            update() {},
            removeAll() {},
        },
        alarms: { create() {} },
        tabs: {
            query(info) {
                if (info && info.windowType && !['normal', 'popup'].includes(info.windowType)) {
                    throw new Error('Invalid call to tabs.query()');
                }
                return Promise.resolve(['tab']);
            },
        },
        permissions: {
            contains(query) {
                for (const permission of query.permissions || []) {
                    if (!['tabs', 'storage'].includes(permission)) {
                        throw new Error(`'${permission}' is not a valid permission.`);
                    }
                }
                return Promise.resolve(true);
            },
            getAll() { return Promise.resolve({ permissions: ['tabs'], origins: [] }); },
        },
        action: {
            setIcon(details) {
                if (details.path !== undefined && details.imageData !== undefined) {
                    throw new Error('cannot specify both path and imageData');
                }
                return Promise.resolve();
            },
        },
        notifications: { create() {} },
    };
    const wrapperCache = new Map();
    function wrapper(kind) {
        if (wrapperCache.has(kind)) { return wrapperCache.get(kind); }
        const object = {};
        Object.defineProperty(object, '__kind', { value: kind });
        for (const [name, fn] of Object.entries(nativeFunctions[kind])) {
            Object.defineProperty(object, name, { value: fn, configurable: true, writable: true, enumerable: true });
        }
        object.onCommitted = new NativeEvent();
        if (kind === 'webRequest') { object.onBeforeRequest = new NativeEvent(); }
        wrapperCache.set(kind, object);
        return object;
    }
    function collectGarbage() {
        const retained = window.__refraxRetainedNamespaces || new Set();
        for (const [kind, object] of wrapperCache) {
            if (!retained.has(object)) { wrapperCache.delete(kind); }
        }
    }
    var browser = {};
    for (const kind of Object.keys(nativeFunctions)) {
        Object.defineProperty(browser, kind, { get: () => wrapper(kind), enumerable: true, configurable: false });
    }
    var chrome = browser;
    """

    /// A context with the model and the shims loaded; `vAPI` stores `getURL` the way
    /// uBlock Origin does, before any collection.
    private func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        var exception: String?
        context.exceptionHandler = { _, value in
            exception = value?.toString()
        }
        context.evaluateScript(Self.webKitModel)
        context.evaluateScript(ShimInjector.loadShimScript())
        context.evaluateScript("var vAPI = { getURL: browser.runtime.getURL }; collectGarbage(); collectGarbage();")
        #expect(exception == nil)
        return context
    }

    private func evaluate(_ script: String, in context: JSContext) -> JSValue? {
        context.evaluateScript(script)
    }

    @Test
    func `Patches survive garbage collection`() throws {
        let context = try makeContext()
        #expect(evaluate("typeof browser.webRequest.handlerBehaviorChanged", in: context)?.toString() == "function")
        #expect(evaluate("typeof browser.webNavigation.onCreatedNavigationTarget.addListener", in: context)?.toString() == "function")
        #expect(evaluate("browser.menus === browser.menus", in: context)?.toBool() == true)
    }

    @Test
    func `webRequest reports a frame other than the main frame as sub_frame`() throws {
        let context = try makeContext()
        let result = evaluate("""
        (() => {
            const all = [];
            const subframes = [];
            const listener = details => all.push(details.type + ':' + details.frameId);
            browser.webRequest.onBeforeRequest.addListener(listener, { urls: ['<all_urls>'] });
            browser.webRequest.onBeforeRequest.addListener(
                details => subframes.push(details.frameId),
                { urls: ['<all_urls>'], types: ['sub_frame'] },
            );
            collectGarbage();
            const event = browser.webRequest.onBeforeRequest;
            event.fire({ type: 'main_frame', frameId: 0 });
            event.fire({ type: 'main_frame', frameId: 7 });
            const registered = event.hasListener(listener);
            event.removeListener(listener);
            event.fire({ type: 'main_frame', frameId: 8 });
            return [all.join(','), subframes.join(','), registered, event.hasListener(listener)].join('|');
        })()
        """, in: context)
        #expect(result?.toString() == "main_frame:0,sub_frame:7|7,8|true|false")
    }

    @Test
    func `Detached and re-homed API functions still reach their namespace`() throws {
        let context = try makeContext()
        #expect(evaluate("vAPI.getURL('')", in: context)?.toString() == "webkit-extension://test/")
        #expect(evaluate("(0, browser.runtime.getURL)('a')", in: context)?.toString() == "webkit-extension://test/a")
    }

    @Test
    func `Menu items with patterns WebKit cannot match are skipped, not thrown`() throws {
        let context = try makeContext()
        let result = evaluate("""
        (() => {
            try {
                browser.menus.create({ id: 'abp', targetUrlPatterns: ['abp:*'] });
                return browser.menus.create({ id: 'mixed', targetUrlPatterns: ['https://example.com/*', 'abp:*'] });
            } catch (error) {
                return 'threw: ' + error.message;
            }
        })()
        """, in: context)
        #expect(result?.toString() == "mixed")
    }

    @Test
    func `APIs WebKit lacks are provided: privacy, requestIdleCallback`() throws {
        let context = try makeContext()
        #expect(evaluate("typeof browser.privacy.network.webRTCIPHandlingPolicy.get", in: context)?.toString() == "function")
        #expect(evaluate("typeof requestIdleCallback", in: context)?.toString() == "function")
    }

    @Test
    func `Firefox and Chrome APIs WebKit lacks: getBrowserInfo, management.getSelf, webRequest enums`() throws {
        let context = try makeContext()
        evaluate("browser.runtime.getBrowserInfo().then(info => { globalThis.browserName = info.name; });", in: context)
        evaluate("browser.management.getSelf().then(info => { globalThis.selfVersion = info.version; });", in: context)
        #expect(evaluate("globalThis.browserName", in: context)?.toString() == "Refrax")
        #expect(evaluate("globalThis.selfVersion", in: context)?.toString() == "2.0")
        #expect(evaluate("browser.webRequest.OnHeadersReceivedOptions.EXTRA_HEADERS", in: context)?.toString() == "extraHeaders")
    }

    @Test
    func `A webRequest listener keeps the URL patterns WebKit can match and drops the rest`() throws {
        let context = try makeContext()
        let result = evaluate("""
        (() => {
            const both = () => {};
            const websocketOnly = () => {};
            try {
                browser.webRequest.onBeforeRequest.addListener(both, { urls: ['ws://*/*', '<all_urls>'] });
                browser.webRequest.onBeforeRequest.addListener(websocketOnly, { urls: ['wss://*/*'] });
            } catch (error) {
                return 'threw: ' + error.message;
            }
            const event = browser.webRequest.onBeforeRequest;
            return [event.hasListener(both), event.hasListener(websocketOnly)].join(',');
        })()
        """, in: context)
        #expect(result?.toString() == "true,false")
    }

    @Test
    func `Permissions WebKit does not know are answered: declared shimmed ones granted, others not`() throws {
        let context = try makeContext()
        evaluate("""
        globalThis.answers = {};
        browser.permissions.contains({ permissions: ['downloads'] }).then(value => { answers.downloads = value; });
        browser.permissions.contains({ permissions: ['history'] }).then(value => { answers.history = value; });
        browser.permissions.contains({ permissions: ['tabs', 'downloads'] }).then(value => { answers.mixed = value; });
        browser.permissions.getAll().then(all => { answers.all = all.permissions.join(','); });
        """, in: context)
        #expect(evaluate("[answers.downloads, answers.history, answers.mixed, answers.all].join('|')", in: context)?.toString()
            == "true|false|true|tabs,downloads")
    }

    @Test
    func `tabs.query for a window type Refrax lacks finds nothing; setIcon takes path and image data`() throws {
        let context = try makeContext()
        evaluate("""
        globalThis.results = {};
        browser.tabs.query({ windowType: 'app' }).then(tabs => { results.app = tabs.length; });
        browser.tabs.query({ windowType: 'normal' }).then(tabs => { results.normal = tabs.length; });
        browser.action.setIcon({ path: 'a.png', imageData: {} }).then(() => { results.icon = 'set'; });
        """, in: context)
        #expect(evaluate("[results.app, results.normal, results.icon].join('|')", in: context)?.toString() == "0|1|set")
    }

    @Test
    func `WebKit's own implementations stay in place`() throws {
        let context = try makeContext()
        #expect(evaluate("browser.alarms.__kind", in: context)?.toString() == "alarms")
        #expect(evaluate("browser.notifications.__kind", in: context)?.toString() == "notifications")
    }
}
