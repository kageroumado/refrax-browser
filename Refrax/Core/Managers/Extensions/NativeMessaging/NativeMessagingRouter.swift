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
final class NativeMessagingRouter {
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
        let name = try Self.hostName(applicationID)
        if let inProcess = inProcessHosts[name] {
            return try await inProcess(message, context)
        }

        let host = try resolve(name, for: context)
        let exchange = OneOffExchange()
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
        let reply = try await withCheckedThrowingContinuation { continuation in
            exchange.wait(with: continuation)
        }
        return try NativeMessageFraming.decode(reply)
    }

    /// A one-off message's host and the caller waiting for its first reply; the host stops
    /// once the exchange finishes, and a result that arrives before the caller waits is kept
    /// for it.
    private final class OneOffExchange {
        var process: NativeMessagingHostProcess?
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
            connections[key] = Connection(port: port, process: nil)
            return
        }

        let host = try resolve(name, for: context)
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
        connections[key] = Connection(port: port, process: process)
    }

    // MARK: - Resolution

    private func resolve(_ name: String, for context: WKWebExtensionContext) throws -> ResolvedNativeMessagingHost {
        let identity = ExtensionIdentity(manifest: context.webExtension.manifest)
        do {
            return try locator.host(named: name, for: identity)
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
