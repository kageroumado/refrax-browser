import Foundation

extension URL {
    // MARK: - Local Network Detection

    /// Whether this URL points to a local/private network address.
    ///
    /// Used to display a warning color in the address bar for local network
    /// connections, which may have self-signed certificates or no HTTPS.
    ///
    /// Detects RFC 1918 private addresses and other local patterns:
    /// - 10.0.0.0/8 (Class A private)
    /// - 172.16.0.0/12 (Class B private)
    /// - 192.168.0.0/16 (Class C private)
    /// - 127.0.0.0/8 (Loopback)
    /// - 169.254.0.0/16 (Link-local)
    /// - localhost
    /// - .local domains (Bonjour/mDNS)
    ///
    /// Reference: https://www.iana.org/assignments/iana-ipv4-special-registry
    var isLocalNetworkAddress: Bool {
        guard let host = host?.lowercased() else { return false }

        // Check for localhost
        if host == "localhost" || host == "localhost.localdomain" {
            return true
        }

        // Check for .local domains (Bonjour/mDNS)
        if host.hasSuffix(".local") {
            return true
        }

        // Check for IPv4 private/local ranges
        let components = host.split(separator: ".").compactMap { Int($0) }
        if components.count == 4 {
            let (a, b, _, _) = (components[0], components[1], components[2], components[3])

            // 10.0.0.0/8 - Class A private network
            if a == 10 {
                return true
            }

            // 172.16.0.0/12 - Class B private network (172.16.x.x - 172.31.x.x)
            if a == 172, (16 ... 31).contains(b) {
                return true
            }

            // 192.168.0.0/16 - Class C private network
            if a == 192, b == 168 {
                return true
            }

            // 127.0.0.0/8 - Loopback
            if a == 127 {
                return true
            }

            // 169.254.0.0/16 - Link-local (APIPA)
            if a == 169, b == 254 {
                return true
            }
        }

        // Check for IPv6 localhost
        if host == "::1" || host == "[::1]" {
            return true
        }

        return false
    }

    // MARK: - Registrable Domain

    /// Whether autofill should be allowed for this URL.
    ///
    /// Autofill is allowed on HTTPS and on local network addresses over HTTP.
    var allowsAutoFill: Bool {
        guard let scheme = scheme?.lowercased() else { return false }

        if scheme == "https" {
            return true
        }

        if scheme == "http", isLocalNetworkAddress {
            return true
        }

        return false
    }

    /// Extracts the registrable domain using PublicSuffixList.
    ///
    /// Returns the eTLD+1 (e.g., "example.com" from "sub.example.com").
    /// Falls back to host if PublicSuffixList is not loaded.
    ///
    /// ## Examples
    ///
    /// - `sub.example.com` → `example.com`
    /// - `www.example.co.uk` → `example.co.uk`
    /// - `localhost` → `localhost`
    var registrableDomain: String? {
        guard let host else { return nil }

        // Use PublicSuffixList for accurate extraction
        if let registrable = PublicSuffixList.shared.registrableDomain(for: host) {
            return registrable
        }

        // Fallback: return host as-is
        return host
    }

    // MARK: - Display Domain

    /// Returns a display-safe domain string.
    ///
    /// Handles special schemes (file, data, blob, about) and returns the full
    /// host for web URLs, with `www.` prefix stripped for cleaner display.
    ///
    /// The full host is returned to ensure subdomains like `account.google.com`
    /// are displayed correctly. Truncation (if needed) should be handled at
    /// the view layer with leading ellipsis to prevent subdomain spoofing.
    var safeDisplayDomain: String {
        switch scheme {
        case "file":
            let name = lastPathComponent
            return name.isEmpty ? "Local File" : name
        case "data", "blob":
            return scheme?.capitalized ?? "Data"
        case "about":
            return absoluteString
        default:
            break
        }

        guard let host = host?.lowercased() else {
            return absoluteString
        }

        // Strip www. prefix for cleaner display
        let display = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        // Append port for localhost so devs can distinguish between services
        if host == "localhost" || host == "127.0.0.1" || host == "::1", let port {
            return "\(display):\(port)"
        }

        return display
    }
}

extension URL {
    /// A blank webpage for WebKit. Will be displayed as solid white background.
    nonisolated static let blank = URL.staticRequired("about:blank")

    /// Whether this URL represents a blank page (`about:blank`).
    var isBlank: Bool {
        self == .blank || absoluteString == "about:blank"
    }

    var isDeepLink: Bool {
        scheme == DeepLink.scheme
    }

    /// URL formatted for display (protocol and www prefix removed).
    ///
    /// Used for consistent URL display across tabs, bookmarks, and drag overlays.
    ///
    /// ## Examples
    ///
    /// - `https://www.example.com/` → `example.com`
    /// - `https://docs.swift.org/guide` → `docs.swift.org/guide`
    /// - `http://localhost:3000/api` → `localhost:3000/api`
    nonisolated var displayString: String {
        var urlString = absoluteString

        // Remove protocol (most common first for performance)
        if urlString.hasPrefix("https://www.") {
            urlString.removeFirst(12)
        } else if urlString.hasPrefix("https://") {
            urlString.removeFirst(8)
        } else if urlString.hasPrefix("http://www.") {
            urlString.removeFirst(11)
        } else if urlString.hasPrefix("http://") {
            urlString.removeFirst(7)
        } else if urlString.hasPrefix("ftp://") {
            urlString.removeFirst(6)
        }

        // Remove trailing slash for bare domains only
        if urlString.hasSuffix("/"), !urlString.dropLast().contains("/") {
            urlString.removeLast()
        }

        return urlString
    }
}
