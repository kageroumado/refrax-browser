import Foundation
import Network
import Testing
import WebKit
@testable import Refrax

/// A small extension written out from source strings, loaded with every permission and site
/// its manifest asks for, as an install grants them.
struct ExtensionFixture {
    /// File paths inside the extension, `manifest.json` among them, and their contents.
    let files: [String: String]

    /// Writes the files into a new temporary folder.
    func write() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-extension-fixture-\(UUID().uuidString)", isDirectory: true)
        for (path, contents) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return folder
    }

    /// Loads the extension into `env`'s default controller under `installedID`, with its
    /// background started.
    @MainActor
    func load(into env: TabManagerTestEnvironment, installedID: String = UUID().uuidString) async throws -> WKWebExtensionContext {
        let context = try await makeContext(installedID: installedID)
        try env.extensionManager.defaultController.load(context)
        env.extensionManager.actions.refresh(context)
        try await context.loadBackgroundContent()
        return context
    }

    /// A context for the extension with its permissions granted and its identity set, not
    /// yet loaded.
    @MainActor
    func makeContext(installedID: String = UUID().uuidString) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: write())
        let context = WKWebExtensionContext(for: webExtension)
        let identifier = ExtensionContextIdentifier.identifier(installedID: installedID, spaceID: nil)
        context.uniqueIdentifier = identifier
        context.baseURL = ExtensionContextIdentifier.baseURL(for: identifier)
        Self.grantEverything(to: context)
        return context
    }

    /// Grants every permission and site the extension requests, optional ones included.
    @MainActor
    static func grantEverything(to context: WKWebExtensionContext) {
        let webExtension = context.webExtension
        for permission in webExtension.requestedPermissions.union(webExtension.optionalPermissions) {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
    }
}

/// An in-process native messaging host that fixture backgrounds report to with
/// `runtime.sendNativeMessage(ProbeHost.name, message)`.
@MainActor
final class ProbeHost {
    static let name = "refrax.test.probe"

    private(set) var messages: [[String: Any]] = []

    init(router: NativeMessagingRouter) {
        router.register({ [weak self] message, _ in
            if let message = message as? [String: Any] {
                self?.messages.append(message)
            }
            return ["received": true]
        }, named: Self.name)
    }

    /// Waits for a message whose `kind` is `kind`.
    func message(kind: String, timeout: Duration = .seconds(10)) async throws -> [String: Any] {
        try await waitFor(timeout: timeout, "a probe message of kind \(kind)") {
            messages.first { $0["kind"] as? String == kind }
        }
    }
}

/// Waits until `value` returns non-`nil`, polling the main actor.
///
/// - Throws: ``TimedOut`` after `timeout`.
@MainActor
func waitFor<T>(timeout: Duration = .seconds(10), _ description: String, value: () -> T?) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = value() {
            return value
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw TimedOut(description: description)
}

struct TimedOut: Error, CustomStringConvertible {
    let description: String
}

/// A native messaging host written in Perl that answers each message with
/// `{"echo": <message>, "argv": [<its arguments>]}`, registered in a temporary
/// `NativeMessagingHosts` directory.
struct EchoHostFixture {
    let name: String
    let directory: URL
    let executable: URL

    private static let script = #"""
    #!/usr/bin/perl
    use strict;
    use warnings;
    binmode STDIN;
    binmode STDOUT;
    $| = 1;
    my $arguments = join(",", map { my $a = $_; $a =~ s/(["\\])/\\$1/g; "\"$a\"" } @ARGV);
    while (1) {
        my $header;
        my $count = read(STDIN, $header, 4);
        last unless defined $count && $count == 4;
        my $length = unpack("V", $header);
        my $body = "";
        while (length($body) < $length) {
            my $chunk;
            my $read = read(STDIN, $chunk, $length - length($body));
            last unless $read;
            $body .= $chunk;
        }
        my $reply = "{\"echo\":$body,\"argv\":[$arguments]}";
        print pack("V", length($reply)) . $reply;
    }
    """#

    /// Writes the host and a manifest for it.
    ///
    /// - Parameters:
    ///   - allowedOrigins: The manifest's Chrome-format `allowed_origins`.
    ///   - allowedExtensions: The manifest's Firefox-format `allowed_extensions`.
    init(name: String = "refrax.test.echo", allowedOrigins: [String]? = nil, allowedExtensions: [String]? = nil) throws {
        self.name = name
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-native-host-\(UUID().uuidString)", isDirectory: true)
        self.directory = root.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        self.executable = root.appendingPathComponent("echo-host.pl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        var manifest: [String: Any] = ["name": name, "description": "Echo", "path": executable.path, "type": "stdio"]
        manifest["allowed_origins"] = allowedOrigins
        manifest["allowed_extensions"] = allowedExtensions
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("\(name).json"))
    }

    var locator: NativeMessagingHostLocator {
        NativeMessagingHostLocator(directories: [directory])
    }
}

/// An HTTP server on 127.0.0.1 that serves fixed responses and records the paths requested.
@MainActor
final class LoopbackHTTPServer {
    struct Response {
        let contentType: String
        let body: String
    }

    private let listener: NWListener
    private let responses: [String: Response]
    private(set) var requestedPaths: [String] = []
    private(set) var port: UInt16 = 0

    init(responses: [String: Response]) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        self.listener = try NWListener(using: parameters)
        self.responses = responses
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    /// Starts listening and returns once the port is known.
    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.serve(connection) }
        }
        let started: AsyncStream<UInt16?> = AsyncStream { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.yield(listener.port?.rawValue)
                case .failed, .cancelled: continuation.yield(nil)
                default: return
                }
                continuation.finish()
            }
        }
        listener.start(queue: .main)
        for await port in started {
            guard let port else { throw TimedOut(description: "the loopback server to start") }
            self.port = port
        }
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                self?.requestedPaths.append(path)
                let response = self?.responses[path] ?? Response(contentType: "text/plain", body: "Not found")
                let status = self?.responses[path] == nil ? "404 Not Found" : "200 OK"
                let body = Data(response.body.utf8)
                let head = "HTTP/1.1 \(status)\r\nContent-Type: \(response.contentType)\r\n" +
                    "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
}
