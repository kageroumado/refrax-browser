import Foundation
import WebKit

/// Carries extensions' `runtime.sendNativeMessage` and `runtime.connectNative` traffic to
/// native messaging hosts.
///
/// A host is either in-process, a handler Refrax registers under a host name (its own
/// `refrax.*` API is one), or an executable a host manifest names, found by
/// ``NativeMessagingHostLocator`` and run as ``NativeMessagingHostProcess``. A one-off message
/// starts the executable, waits for its first reply and stops it; a port keeps it running
/// until either side disconnects.
///
/// An executable host that admits the extension only by an identity the extension claims
/// (see ``ExtensionIdentity``) starts only once the user has allowed it for that extension.
/// A one-off message waits for the answer. A port is refused while the answer is pending,
/// because WebKit needs a port connected synchronously (see
/// `ExtensionControllerDelegate`'s `connectUsing`); the question is asked, and the
/// extension's next connection gets the answer.
final class NativeMessagingRouter {
    /// What the user is asked before a claimed identity starts a host.
    struct ConsentRequest: Equatable {
        let hostName: String
        let executablePath: String
        let extensionName: String
        /// The Chrome origin or Firefox add-on ID the extension claims, unverified.
        let claimedIdentity: String
    }

    /// How long a one-off message waits for its host's reply before the host is stopped.
    var oneOffTimeout = Duration.seconds(30)

    /// The identity of an extension, with the Chrome ID its installation verified.
    var identity: (WKWebExtensionContext) -> ExtensionIdentity = { context in
        ExtensionIdentity(manifest: context.webExtension.manifest, verifiedChromeID: nil, refraxOrigin: context.baseURL.absoluteString)
    }

    /// The user's stored answer for a request, or `nil` when never asked.
    var storedConsent: (ConsentRequest, WKWebExtensionContext) -> Bool? = { _, _ in nil }

    /// Asks the user, stores the answer, and returns it.
    var askConsent: (ConsentRequest, WKWebExtensionContext) async -> Bool = { _, _ in false }

    /// Answers one message from an extension. A port to an in-process host calls it for each
    /// message and posts back each non-`nil` reply.
    typealias InProcessHost = (_ message: Any, _ context: WKWebExtensionContext) async throws -> Any?

    /// Where executable hosts are looked up.
    var locator: NativeMessagingHostLocator

    private var inProcessHosts: [String: InProcessHost] = [:]
    /// Ports in use, held as WebKit requires: releasing a port disconnects it.
    private var connections: [ObjectIdentifier: Connection] = [:]
    /// One-off exchanges waiting for their host's reply.
    private var exchanges: [ObjectIdentifier: OneOffExchange] = [:]

    private struct Connection {
        let port: WKWebExtension.MessagePort
        let process: NativeMessagingHostProcess?
        let context: ObjectIdentifier
    }

    init(locator: NativeMessagingHostLocator = .standard()) {
        self.locator = locator
    }

    /// Makes `host` answer for `name` ahead of any host manifest.
    func register(_ host: @escaping InProcessHost, named name: String) {
        inProcessHosts[name] = host
    }

    func unregister(named name: String) {
        inProcessHosts[name] = nil
    }

    /// The number of open ports, for diagnostics and tests.
    var connectionCount: Int {
        connections.count
    }

    // MARK: - One-off messages

    /// Sends `message` to the host `applicationID` names and returns its first reply.
    ///
    /// - Throws: ``NativeMessagingError`` when the host cannot be found or started, or exits
    ///   without replying.
    func send(_ message: Any, to applicationID: String?, from context: WKWebExtensionContext) async throws -> Any? {
        try Self.requirePermission(of: context)
        let name = try Self.hostName(applicationID)
        if let inProcess = inProcessHosts[name] {
            return try await inProcess(message, context)
        }

        let host = try resolve(name, for: context)
        if host.requiresConsent {
            let request = Self.consentRequest(for: host, context: context)
            let allowed = if let stored = storedConsent(request, context) {
                stored
            } else {
                await askConsent(request, context)
            }
            guard allowed else { throw NativeMessagingError.forbidden }
        }
        let exchange = OneOffExchange(context: ObjectIdentifier(context))
        let key = ObjectIdentifier(exchange)
        let process = NativeMessagingHostProcess(host: host) { [weak self] event in
            switch event {
            case let .message(body): exchange.finish(.success(body))
            case let .closed(error): exchange.finish(.failure(error))
            }
            self?.exchanges[key] = nil
        }
        exchange.process = process
        try process.start()
        exchanges[key] = exchange
        do {
            try process.send(message)
        } catch {
            exchange.finish(.failure(error))
            exchanges[key] = nil
        }
        let timeout = oneOffTimeout
        Task(name: "Native message timeout") { [weak self] in
            try? await Task.sleep(for: timeout)
            exchange.finish(.failure(NativeMessagingError.timedOut))
            self?.exchanges[key] = nil
        }
        let reply = try await withCheckedThrowingContinuation { continuation in
            exchange.wait(with: continuation)
        }
        return try NativeMessageFraming.decode(reply)
    }

    /// A one-off message's host and the caller waiting for its first reply; the host stops
    /// once the exchange finishes, and a result that arrives before the caller waits is kept
    /// for it.
    private final class OneOffExchange {
        let context: ObjectIdentifier
        var process: NativeMessagingHostProcess?

        init(context: ObjectIdentifier) {
            self.context = context
        }

        private var continuation: CheckedContinuation<Data, any Error>?
        private var result: Result<Data, any Error>?

        func wait(with continuation: CheckedContinuation<Data, any Error>) {
            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }

        func finish(_ result: Result<Data, any Error>) {
            guard self.result == nil else { return }
            self.result = result
            process?.terminate()
            process = nil
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    // MARK: - Ports

    /// Connects `port` to the host its application identifier names.
    ///
    /// - Throws: ``NativeMessagingError`` when the host cannot be found or started.
    func connect(_ port: WKWebExtension.MessagePort, from context: WKWebExtensionContext) throws {
        try Self.requirePermission(of: context)
        let name = try Self.hostName(port.applicationIdentifier)
        let key = ObjectIdentifier(port)

        if let inProcess = inProcessHosts[name] {
            port.messageHandler = { [weak port] message, error in
                guard let port, error == nil, let message else { return }
                Task(name: "Native message to \(name)") {
                    do {
                        if let reply = try await inProcess(message, context) {
                            try await port.sendMessage(reply)
                        }
                    } catch {
                        port.disconnect(throwing: error)
                    }
                }
            }
            port.disconnectHandler = { [weak self] _ in
                self?.connections[key] = nil
            }
            connections[key] = Connection(port: port, process: nil, context: ObjectIdentifier(context))
            return
        }

        let host = try resolve(name, for: context)
        if host.requiresConsent {
            let request = Self.consentRequest(for: host, context: context)
            switch storedConsent(request, context) {
            case true?:
                break
            case false?:
                throw NativeMessagingError.forbidden
            case nil:
                Task(name: "Ask to start native host \(name)") {
                    _ = await self.askConsent(request, context)
                }
                throw NativeMessagingError.forbidden
            }
        }
        let process = NativeMessagingHostProcess(host: host) { [weak self, weak port] event in
            switch event {
            case let .message(body):
                do {
                    try port?.sendMessage(NativeMessageFraming.decode(body), completionHandler: nil)
                } catch {
                    Logger.warning("Native host \(name) sent a message that is not JSON", category: Logger.extensions)
                }
            case let .closed(error):
                self?.connections[key] = nil
                port?.disconnect(throwing: error)
            }
        }
        port.messageHandler = { [weak self, weak port] message, error in
            guard error == nil else { return }
            do {
                try process.send(message ?? NSNull())
            } catch {
                self?.connections.removeValue(forKey: key)?.process?.terminate()
                port?.disconnect(throwing: error)
            }
        }
        port.disconnectHandler = { [weak self] _ in
            self?.connections.removeValue(forKey: key)?.process?.terminate()
        }
        try process.start()
        connections[key] = Connection(port: port, process: process, context: ObjectIdentifier(context))
    }

    /// Ends everything `context` has open: its ports disconnect and their hosts stop, and its
    /// one-off messages fail. Called when the context unloads, since WebKit then forgets its
    /// ports without telling the app.
    func disconnectAll(for context: WKWebExtensionContext) {
        let owner = ObjectIdentifier(context)
        for (key, connection) in connections where connection.context == owner {
            connections[key] = nil
            connection.process?.terminate()
            connection.port.disconnect()
        }
        for (key, exchange) in exchanges where exchange.context == owner {
            exchanges[key] = nil
            exchange.finish(.failure(NativeMessagingError.hostExited))
        }
    }

    // MARK: - Resolution

    private static func consentRequest(for host: ResolvedNativeMessagingHost, context: WKWebExtensionContext) -> ConsentRequest {
        ConsentRequest(
            hostName: host.name,
            executablePath: host.executableURL.path,
            extensionName: context.webExtension.displayName ?? context.uniqueIdentifier,
            claimedIdentity: host.matchedIdentity,
        )
    }

    /// WebKit checks the `nativeMessaging` permission in the page; this checks it again here,
    /// where a page cannot reach around it.
    private static func requirePermission(of context: WKWebExtensionContext) throws {
        guard context.hasPermission(.nativeMessaging) else { throw NativeMessagingError.forbidden }
    }

    private func resolve(_ name: String, for context: WKWebExtensionContext) throws -> ResolvedNativeMessagingHost {
        do {
            return try locator.host(named: name, for: identity(context))
        } catch {
            Logger.warning(
                "Native messaging host '\(name)' unavailable to '\(context.webExtension.displayName ?? "extension")': \(error.localizedDescription)",
                category: Logger.extensions,
            )
            throw error
        }
    }

    private static func hostName(_ applicationID: String?) throws -> String {
        guard let applicationID, !applicationID.isEmpty else { throw NativeMessagingError.invalidHostName }
        return applicationID
    }
}
