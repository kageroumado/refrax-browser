import WebKit

/// Routes messages from Refrax-injected scripts to their handlers, whichever engine ran the script.
///
/// A channel is a named inbox a script posts to (`window.webkit.messageHandlers.<name>`
/// in WebKit; the same call shape in other engines, see `Engines/CONTRACT.md` §4.4).
/// `postMessage` returns a promise: it resolves with a replying handler's value, or with
/// `null` once a one-way handler has run. Handlers see an engine-neutral ``ScriptMessage``
/// and the page it came from, so a handler is written once for every engine.
///
/// Messages arrive from page context and are untrusted: handlers validate `body`.
final class ScriptChannelRouter {
    typealias Handler = (_ message: ScriptMessage, _ page: WebPage?) -> Void
    typealias ReplyingHandler = (_ message: ScriptMessage, _ page: WebPage?) async throws -> ScriptValue

    private enum Kind {
        case oneWay(Handler)
        case replying(ReplyingHandler)
    }

    private struct Channel {
        let world: ScriptRequest.World
        let kind: Kind
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
        open(name, world: world, kind: .oneWay(handler))
    }

    /// Opens a channel whose `postMessage` promise resolves with `handler`'s value,
    /// or rejects with the error it throws. Replaces a channel with the same name.
    func register(_ name: String, world: ScriptRequest.World = .page, replyingWith handler: @escaping ReplyingHandler) {
        open(name, world: world, kind: .replying(handler))
    }

    func unregister(_ name: String) {
        guard let channel = channels.removeValue(forKey: name) else { return }
        userContentController.removeScriptMessageHandler(forName: name, contentWorld: channel.world.webKitWorld)
    }

    /// The channels scripts in `world` may post to.
    func channelNames(in world: ScriptRequest.World) -> [String] {
        channels.filter { $0.value.world == world }.keys.sorted()
    }

    /// Delivers a message to its channel's handler and settles the script's promise through `reply`,
    /// exactly once. Messages for unknown channels are rejected.
    func dispatch(_ message: ScriptMessage, from page: WebPage?, reply: @escaping @Sendable (ScriptReply) -> Void = { _ in }) {
        guard let channel = channels[message.channel] else {
            Logger.warning("Dropped a script message for unknown channel \(message.channel)", category: Logger.engines)
            reply(.error(message: "Unknown channel"))
            return
        }
        switch channel.kind {
        case let .oneWay(handler):
            handler(message, page)
            reply(.value(value: .null))
        case let .replying(handler):
            Task.immediate(name: "Script channel \(message.channel)") {
                do {
                    try await reply(.value(value: handler(message, page)))
                } catch {
                    reply(.error(message: error.localizedDescription))
                }
            }
        }
    }

    private func open(_ name: String, world: ScriptRequest.World, kind: Kind) {
        unregister(name)
        let bridge = WebKitChannelBridge(name: name) { [weak self] message, webView, reply in
            guard let self else {
                reply(.error(message: "Unknown channel"))
                return
            }
            dispatch(message, from: webView.flatMap { self.pageResolver?($0) }, reply: reply)
        }
        userContentController.addScriptMessageHandler(bridge, contentWorld: world.webKitWorld, name: name)
        channels[name] = Channel(world: world, kind: kind, bridge: bridge)
    }
}

// MARK: - WebKit Bridge

/// Delivers a WebKit script message as a ``ScriptMessage`` and settles its promise with the reply.
private final class WebKitChannelBridge: NSObject, WKScriptMessageHandlerWithReply {
    typealias Deliver = (ScriptMessage, WKWebView?, @escaping @Sendable (ScriptReply) -> Void) -> Void

    private let name: String
    private let deliver: Deliver

    init(name: String, deliver: @escaping Deliver) {
        self.name = name
        self.deliver = deliver
    }

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void,
    ) {
        let scriptMessage = ScriptMessage(
            channel: name,
            body: ScriptValue(foundation: message.body),
            frameURL: message.frameInfo.request.url,
            isMainFrame: message.frameInfo.isMainFrame,
        )
        deliver(scriptMessage, message.webView) { reply in
            MainActor.assumeIsolated {
                switch reply {
                case let .value(value): replyHandler(value.foundationValue, nil)
                case let .error(message): replyHandler(nil, message)
                }
            }
        }
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
