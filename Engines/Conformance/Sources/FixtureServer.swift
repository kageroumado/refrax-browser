// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation
import Network

/// An HTTP/1.1 server on loopback (IPv4 and IPv6, one port) serving the fixtures the tests
/// load. Every name that resolves to loopback reaches it: `127.0.0.1`, `localhost`, and any
/// `*.localhost`, which gives the tests distinct hosts without DNS.
///
/// Routes:
/// - `/html/<name>`: a page from ``Fixtures/pages``
/// - `/asset/<name>`: a subresource from ``Fixtures/assets``
/// - `/status/<code>`: an HTML page with that status
/// - `/redirect?to=<path>`: 302 to `path`
/// - `/download/<name>?bytes=<n>`: an attachment of `n` bytes
/// - `/slow?ms=<n>`: a page after `n` milliseconds
/// - `/hang`: never answers
/// - `/echo`: the request's method, path and headers as JSON inside an HTML page
@MainActor
final class FixtureServer {
    private(set) var port: UInt16 = 0
    /// Every request path served, in arrival order.
    private(set) var requests: [String] = []
    private var listeners: [NWListener] = []
    private var hanging: [NWConnection] = []

    func start() async throws {
        let first = try listener(host: "127.0.0.1", port: .any)
        port = try await ready(first)
        let second = try listener(host: "::1", port: NWEndpoint.Port(rawValue: port)!)
        _ = try await ready(second)
        listeners = [first, second]
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        hanging.forEach { $0.cancel() }
    }

    /// `http://<host>:<port><path>`.
    func url(_ path: String, host: String = "127.0.0.1") -> String {
        "http://\(host):\(port)\(path)"
    }

    /// How many requests for `path` arrived (query ignored).
    func hits(_ path: String) -> Int {
        requests.count { $0.split(separator: "?").first.map(String.init) == path }
    }

    private func listener(host: NWEndpoint.Host, port: NWEndpoint.Port) throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated { self.accept(connection) }
        }
        return listener
    }

    private func ready(_ listener: NWListener) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case let .failed(error):
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            MainActor.assumeIsolated {
                var buffer = buffer
                if let data { buffer.append(data) }
                if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                    self.respond(to: Request(head: head), on: connection)
                } else if error == nil, !isComplete {
                    self.receive(on: connection, buffer: buffer)
                } else {
                    connection.cancel()
                }
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        requests.append(request.target)
        let path = request.path
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch segments.first {
        case "html" where segments.count == 2:
            if let page = Fixtures.pages[segments[1]] {
                send(Response(body: Data(page.utf8)), on: connection)
            } else {
                send(Response(status: 404, body: Data("<title>missing</title>".utf8)), on: connection)
            }
        case "asset" where segments.count == 2:
            if let asset = Fixtures.assets[segments[1]] {
                send(Response(contentType: asset.type, body: asset.body), on: connection)
            } else {
                send(Response(status: 404, body: Data()), on: connection)
            }
        case "status" where segments.count == 2:
            let code = Int(segments[1]) ?? 500
            send(Response(status: code, body: Data("<title>status \(code)</title>".utf8)), on: connection)
        case "redirect":
            let target = request.query["to"] ?? "/html/basic"
            send(Response(status: 302, headers: ["Location": target], body: Data()), on: connection)
        case "download" where segments.count == 2:
            let bytes = Int(request.query["bytes"] ?? "") ?? 1024
            send(
                Response(
                    contentType: "application/octet-stream",
                    headers: ["Content-Disposition": "attachment; filename=\"\(segments[1])\""],
                    body: Data(repeating: UInt8(ascii: "x"), count: bytes),
                ),
                on: connection,
            )
        case "slow":
            let milliseconds = Int(request.query["ms"] ?? "") ?? 1000
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                MainActor.assumeIsolated {
                    self.send(Response(body: Data("<title>slow</title><p>slow</p>".utf8)), on: connection)
                }
            }
        case "hang":
            hanging.append(connection)
        case "echo":
            let echo: [String: Any] = ["method": request.method, "path": request.target, "headers": request.headers]
            let json = String(decoding: try! JSONSerialization.data(withJSONObject: echo), as: UTF8.self)
            let page = "<title>echo</title><script id=echo type=application/json>\(json)</script>"
            send(Response(body: Data(page.utf8)), on: connection)
        default:
            send(Response(status: 404, body: Data("<title>not found</title>".utf8)), on: connection)
        }
    }

    private func send(_ response: Response, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct Request {
    let method: String
    /// Path and query, as requested.
    let target: String
    let headers: [String: String]

    init(head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        method = requestLine.first ?? "GET"
        target = requestLine.count > 1 ? requestLine[1] : "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
    }

    var path: String {
        String(target.split(separator: "?", maxSplits: 1).first ?? "/")
    }

    var query: [String: String] {
        guard let components = URLComponents(string: target) else { return [:] }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return query
    }
}

private struct Response {
    var status = 200
    var contentType = "text/html; charset=utf-8"
    var headers: [String: String] = [:]
    var body: Data

    var serialized: Data {
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n"
        head += "Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\nConnection: close\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
