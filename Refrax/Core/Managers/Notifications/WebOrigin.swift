import Foundation
import WebKit

/// A web security origin in WebKit's serialization: `scheme://host[:port]`, lowercase, with
/// the scheme's default port left out.
///
/// Notification permissions are keyed by this string, the same form WebKit uses for the
/// permission maps it hands to web processes (`SecurityOriginData::toString`), so a stored
/// key and a WebKit key compare equal.
nonisolated struct WebOrigin: Hashable, Sendable, Comparable, CustomStringConvertible {
    let scheme: String
    let host: String
    /// Nil for the scheme's default port.
    let port: Int?

    /// Schemes whose pages can ask to show notifications.
    static let supportedSchemes: Set<String> = ["http", "https", "file"]

    private static let defaultPorts = ["http": 80, "https": 443]

    init?(scheme: String, host: String, port: Int?) {
        let scheme = scheme.lowercased()
        guard Self.supportedSchemes.contains(scheme) else { return nil }
        let host = host.lowercased()
        guard scheme == "file" || !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = scheme == "file" ? "" : host
        if let port, port > 0, port != Self.defaultPorts[scheme], scheme != "file" {
            self.port = port
        } else {
            self.port = nil
        }
    }

    /// The origin of `url`, ignoring its path, query, and fragment.
    init?(url: URL) {
        guard let scheme = url.scheme else { return nil }
        self.init(scheme: scheme, host: url.host(percentEncoded: false) ?? "", port: url.port)
    }

    /// Parses an origin or any URL string (`HTTPS://Example.com:443/a` → `https://example.com`).
    init?(string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(url: url)
    }

    /// The origin WebKit reports for a request.
    @MainActor
    init?(_ securityOrigin: WKSecurityOrigin) {
        self.init(scheme: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
    }

    /// The serialized origin, e.g. `https://example.com` or `http://localhost:8000`.
    var string: String {
        if scheme == "file" {
            return "file://"
        }
        return port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    /// The origin as a URL, for opening it in a tab.
    var url: URL? {
        scheme == "file" ? nil : URL(string: string)
    }

    /// What lists of origins show: the host, its port when not the default, and the scheme
    /// only for plain HTTP, so `http://` and `https://` rows for one host stay distinct.
    var displayName: String {
        scheme == "http" && !host.isEmpty ? "http://\(siteName)" : siteName
    }

    /// The site as Safari names it in prompts and notifications: the host and its port when
    /// not the default (`example.com`, `localhost:8765`).
    var siteName: String {
        if scheme == "file" {
            return "Local Files"
        }
        return port.map { "\(host):\($0)" } ?? host
    }

    var description: String {
        string
    }

    /// Ordered for lists: by host, then scheme, then port.
    static func < (lhs: WebOrigin, rhs: WebOrigin) -> Bool {
        (lhs.host, lhs.scheme, lhs.port ?? 0) < (rhs.host, rhs.scheme, rhs.port ?? 0)
    }
}
