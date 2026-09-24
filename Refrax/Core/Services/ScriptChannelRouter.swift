import WebKit

/// Routes messages from Refrax-injected scripts to their handlers, whichever engine ran the script.
///
/// A channel is a named inbox a script posts to (`window.webkit.messageHandlers.<name>`
/// in WebKit; the same call shape in other engines, see `Engines/CONTRACT.md` §4.4).
/// Handlers see an engine-neutral ``ScriptMessage`` and the page it came from, so a
/// handler is written once for every engine.
///
/// Messages arrive from page context and are untrusted: handlers validate `body`.
final class ScriptChannelRouter {
    typealias Handler = (_ message: ScriptMessage, _ page: WebPage?) -> Void

    private struct Channel {
        let world: ScriptRequest.World
        let handler: Handler
        let bridge: WebKitChannelBridge
    }

    private let userContentController: WKUserContentController
    private var channels: [String: Channel] = [:]

    /// Finds the page a WebKit message came from. Set by the page pool.
    var pageResolver: ((WKWebView) -> WebPage?)?

    init(userContentController: WKUserContentController) {
        self.userContentController = userContentController
    }

    /// Opens a channel scripts in `world` can post to. Replaces a channel with the same name.
    func register(_ name: String, world: ScriptRequest.World = .page, handler: @escaping Handler) {
        unregister(name)
        let bridge = WebKitChannelBridge(name: name) { [weak self] message, webView in
            self?.dispatch(message, from: webView.flatMap { self?.pageResolver?($0) })
        }
        userContentController.add(bridge, contentWorld: world.webKitWorld, name: name)
        channels[name] = Channel(world: world, handler: handler, bridge: bridge)
    }

    func unregister(_ name: String) {
        guard let channel = channels.removeValue(forKey: name) else { return }
        userContentController.removeScriptMessageHandler(forName: name, contentWorld: channel.world.webKitWorld)
    }

    /// The channels scripts in `world` may post to.
    func channelNames(in world: ScriptRequest.World) -> [String] {
        channels.filter { $0.value.world == world }.keys.sorted()
    }

    /// Delivers a message to its channel's handler. Messages for unknown channels are dropped.
    func dispatch(_ message: ScriptMessage, from page: WebPage?) {
        guard let channel = channels[message.channel] else {
            Logger.warning("Dropped a script message for unknown channel \(message.channel)", category: Logger.engines)
            return
        }
        channel.handler(message, page)
    }
}

// MARK: - WebKit Bridge

/// Delivers a WebKit script message as a ``ScriptMessage``.
private final class WebKitChannelBridge: NSObject, WKScriptMessageHandler {
    private let name: String
    private let deliver: (ScriptMessage, WKWebView?) -> Void

    init(name: String, deliver: @escaping (ScriptMessage, WKWebView?) -> Void) {
        self.name = name
        self.deliver = deliver
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        deliver(
            ScriptMessage(
                channel: name,
                body: ScriptValue(foundation: message.body),
                frameURL: message.frameInfo.request.url,
                isMainFrame: message.frameInfo.isMainFrame,
            ),
            message.webView,
        )
    }
}

extension ScriptRequest.World {
    /// The WebKit content world for this contract world.
    var webKitWorld: WKContentWorld {
        switch self {
        case .page: .page
        case let .isolated(name): .world(name: name)
        }
    }
}
