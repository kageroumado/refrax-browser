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

    class NativeEvent { addListener() {} removeListener() {} hasListener() { return false; } }
    const nativeFunctions = {
        runtime: {
            getURL(path) { return this && this.__kind === 'runtime' ? 'webkit-extension://test/' + path : undefined; },
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

    @Test("Patches survive garbage collection")
    func patchesSurviveCollection() throws {
        let context = try makeContext()
        #expect(evaluate("typeof browser.webRequest.handlerBehaviorChanged", in: context)?.toString() == "function")
        #expect(evaluate("typeof browser.webNavigation.onCreatedNavigationTarget.addListener", in: context)?.toString() == "function")
        #expect(evaluate("browser.menus === browser.menus", in: context)?.toBool() == true)
    }

    @Test("Detached and re-homed API functions still reach their namespace")
    func detachedCalls() throws {
        let context = try makeContext()
        #expect(evaluate("vAPI.getURL('')", in: context)?.toString() == "webkit-extension://test/")
        #expect(evaluate("(0, browser.runtime.getURL)('a')", in: context)?.toString() == "webkit-extension://test/a")
    }

    @Test("Menu items with patterns WebKit cannot match are skipped, not thrown")
    func unmatchableMenuPatterns() throws {
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

    @Test("APIs WebKit lacks are provided: privacy, requestIdleCallback")
    func missingAPIs() throws {
        let context = try makeContext()
        #expect(evaluate("typeof browser.privacy.network.webRTCIPHandlingPolicy.get", in: context)?.toString() == "function")
        #expect(evaluate("typeof requestIdleCallback", in: context)?.toString() == "function")
    }

    @Test("WebKit's own implementations stay in place")
    func nativeImplementationsKept() throws {
        let context = try makeContext()
        #expect(evaluate("browser.alarms.__kind", in: context)?.toString() == "alarms")
        #expect(evaluate("browser.notifications.__kind", in: context)?.toString() == "notifications")
    }
}
