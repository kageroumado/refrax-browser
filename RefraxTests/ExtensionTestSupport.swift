import CryptoKit
import Foundation
import Network
import Security
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
    func makeContext(installedID: String = UUID().uuidString, spaceID: UUID? = nil) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: write())
        let context = WKWebExtensionContext(for: webExtension)
        let identifier = ExtensionContextIdentifier.identifier(installedID: installedID, spaceID: spaceID)
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

    static let echoScript = #"""
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
    init(
        name: String = "refrax.test.echo",
        script: String = EchoHostFixture.echoScript,
        allowedOrigins: [String]? = nil,
        allowedExtensions: [String]? = nil,
    ) throws {
        self.name = name
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-native-host-\(UUID().uuidString)", isDirectory: true)
        self.directory = root.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        self.executable = root.appendingPathComponent("echo-host.pl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        var manifest: [String: Any] = ["name": name, "description": "Echo", "path": executable.path, "type": "stdio"]
        manifest["allowed_origins"] = allowedOrigins
        manifest["allowed_extensions"] = allowedExtensions
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("\(name).json"))
    }

    /// A host that announces a reply larger than a host may send, then waits.
    static let oversizedScript = """
    #!/usr/bin/perl
    binmode STDOUT;
    $| = 1;
    print pack("V", 2 * 1024 * 1024);
    sleep 30;
    """

    /// A host that closes its output at once, then waits.
    static let closingScript = """
    #!/usr/bin/perl
    close(STDOUT);
    sleep 30;
    """

    /// A host that reads and never answers.
    static let silentScript = """
    #!/usr/bin/perl
    my $header;
    read(STDIN, $header, 4);
    sleep 30;
    """

    var locator: NativeMessagingHostLocator {
        NativeMessagingHostLocator(refraxDirectory: nil, browserDirectories: [directory])
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

/// Builders for signed CRX3 files and ZIP archives.
enum TestArchives {
    static func lengthDelimited(_ field: UInt64, _ value: Data) -> Data {
        varint(field << 3 | 2) + varint(UInt64(value.count)) + value
    }

    static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            let byte = UInt8(value & 0x7F)
            value >>= 7
            bytes.append(value == 0 ? byte : byte | 0x80)
        } while value != 0
        return Data(bytes)
    }

    private static func derLength(_ count: Int) -> Data {
        count < 0x80 ? Data([UInt8(count)]) : Data([0x82, UInt8(count >> 8), UInt8(count & 0xFF)])
    }

    private static func spki(algorithm: Data, key: Data) -> Data {
        let bitString = Data([0x03]) + derLength(key.count + 1) + Data([0x00]) + key
        let body = algorithm + bitString
        return Data([0x30]) + derLength(body.count) + body
    }

    /// A signing key and its public key as a DER SubjectPublicKeyInfo.
    struct Signer {
        let privateKey: SecKey
        let spki: Data
        let isECDSA: Bool

        func sign(_ message: Data) throws -> Data {
            let algorithm: SecKeyAlgorithm = isECDSA ? .ecdsaSignatureMessageX962SHA256 : .rsaSignatureMessagePKCS1v15SHA256
            return try #require(SecKeyCreateSignature(privateKey, algorithm, message as CFData, nil) as Data?)
        }
    }

    static func rsaSigner() throws -> Signer {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2_048]
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let pkcs1 = try #require(SecKeyCopyPublicKey(privateKey).flatMap { SecKeyCopyExternalRepresentation($0, nil) as Data? })
        let algorithm = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        return Signer(privateKey: privateKey, spki: spki(algorithm: algorithm, key: pkcs1), isECDSA: false)
    }

    static func ecdsaSigner() throws -> Signer {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits: 256]
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let point = try #require(SecKeyCopyPublicKey(privateKey).flatMap { SecKeyCopyExternalRepresentation($0, nil) as Data? })
        let algorithm = Data([
            0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
        ])
        return Signer(privateKey: privateKey, spki: spki(algorithm: algorithm, key: point), isECDSA: true)
    }

    /// The signed header data naming `key`'s CRX ID.
    static func signedHeaderData(for key: Data) -> Data {
        lengthDelimited(1, Data(SHA256.hash(data: key).prefix(16)))
    }

    /// What every proof signs.
    static func signedMessage(signedHeaderData: Data, zip: Data) -> Data {
        var length = UInt32(signedHeaderData.count).littleEndian
        return Data("CRX3 SignedData\u{0}".utf8) + Data(bytes: &length, count: 4) + signedHeaderData + zip
    }

    /// A proof field: field 2 for RSA, 3 for ECDSA.
    static func proof(by signer: Signer, signature: Data) -> Data {
        lengthDelimited(signer.isECDSA ? 3 : 2, lengthDelimited(1, signer.spki) + lengthDelimited(2, signature))
    }

    /// A CRX3 file with `header` and `zip`.
    static func crx(header: Data, zip: Data) -> Data {
        var version = UInt32(3).littleEndian
        var length = UInt32(header.count).littleEndian
        return Data("Cr24".utf8) + Data(bytes: &version, count: 4) + Data(bytes: &length, count: 4) + header + zip
    }

    /// A CRX3 file whose ID is `developer`'s, signed by each of `signers`.
    static func crx(zip: Data, developer: Signer, signers: [Signer]) throws -> Data {
        let signed = signedHeaderData(for: developer.spki)
        let message = signedMessage(signedHeaderData: signed, zip: zip)
        let proofs = try signers.map { try proof(by: $0, signature: $0.sign(message)) }.reduce(Data(), +)
        return crx(header: proofs + lengthDelimited(10_000, signed), zip: zip)
    }

    /// `folder` zipped, as an XPI is.
    static func zip(_ folder: URL) throws -> Data {
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("refrax-archive-\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = folder
        process.arguments = ["-q", "-r", archive.path, "."]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: archive)
    }

    /// A ZIP central directory with entries named `names`, each `size` bytes, and Unix modes.
    static func centralDirectory(_ entries: [(name: String, mode: UInt32, size: UInt32)]) -> Data {
        func le16(_ value: Int) -> Data {
            Data([UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)])
        }
        func le32(_ value: UInt32) -> Data {
            Data((0 ..< 4).map { UInt8(value >> (8 * $0) & 0xFF) })
        }
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let parts: [Data] = [
                le32(0x0201_4B50), le16(0x031E), le16(20), le16(0), le16(0), le16(0), le16(0),
                le32(0), le32(entry.size), le32(entry.size), le16(name.count), le16(0), le16(0),
                le16(0), le16(0), le32(entry.mode << 16), le32(0), name,
            ]
            directory.append(contentsOf: parts.joined())
        }
        let end: [Data] = [
            le32(0x0605_4B50), le16(0), le16(0), le16(entries.count), le16(entries.count),
            le32(UInt32(directory.count)), le32(0), le16(0),
        ]
        return directory + Data(end.joined())
    }
}
