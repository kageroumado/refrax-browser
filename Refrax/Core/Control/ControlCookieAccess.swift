import Foundation
import RefraxProtocol

/// Rules for reading a space's cookie store over the control server.
///
/// Every read starts from the space's whole `WKHTTPCookieStore`, so this type decides
/// what a client may see:
///
/// | Space | HttpOnly cookies | Values (`--reveal`, export) |
/// |---|---|---|
/// | locked | refused | refused |
/// | exposes cookies | listed | allowed |
/// | does not expose cookies | hidden | refused |
///
/// Without exposure a client sees what `document.cookie` would show it anyway:
/// names and metadata of script-visible cookies.
nonisolated enum ControlCookieAccess {
    /// The space state a read is checked against.
    struct Gate: Equatable {
        /// Lock-enabled and not currently unlocked.
        let isLocked: Bool
        /// ``Space/exposesCookiesToControlServer``.
        let exposesCookies: Bool
    }

    /// What a permitted read may return.
    struct Grant: Equatable {
        let includesHTTPOnly: Bool
        let revealsValues: Bool

        /// Whether the read touches data the user opted into, and so is logged and announced.
        var isGated: Bool {
            includesHTTPOnly || revealsValues
        }
    }

    enum Refusal: Error, Equatable {
        case locked
        case notExposed
    }

    // MARK: - Gate

    /// Decides what a `dev cookies` read may return.
    static func authorizeRead(reveal: Bool, gate: Gate) throws(Refusal) -> Grant {
        guard !gate.isLocked else { throw .locked }
        if reveal, !gate.exposesCookies { throw .notExposed }
        return Grant(includesHTTPOnly: gate.exposesCookies, revealsValues: reveal)
    }

    /// Checks that an export, which always carries values, is allowed.
    static func authorizeExport(gate: Gate) throws(Refusal) {
        guard !gate.isLocked else { throw .locked }
        guard gate.exposesCookies else { throw .notExposed }
    }

    // MARK: - Filtering

    /// RFC 6265 domain matching against a filter such as `example.com`.
    ///
    /// Matches host-only cookies for `example.com`, domain cookies for `.example.com`,
    /// and cookies for any subdomain. `notexample.com` does not match.
    static func domain(_ cookieDomain: String, matches filter: String) -> Bool {
        let cookieHost = normalizedHost(cookieDomain)
        let filterHost = normalizedHost(filter)
        guard !filterHost.isEmpty else { return true }
        return cookieHost == filterHost || cookieHost.hasSuffix("." + filterHost)
    }

    /// The cookies a grant permits, filtered by domain, most specific first.
    ///
    /// Ordering follows RFC 6265 §5.4: longer paths first, then the more specific domain.
    static func visibleCookies(_ cookies: [HTTPCookie], domain filter: String?, grant: Grant) -> [HTTPCookie] {
        cookies
            .filter { cookie in
                guard grant.includesHTTPOnly || !cookie.isHTTPOnly else { return false }
                guard let filter else { return true }
                return domain(cookie.domain, matches: filter)
            }
            .sorted(by: isMoreSpecific)
    }

    /// Picks one cookie per requested name for export.
    ///
    /// When a name exists under several domains or paths, the most specific one wins,
    /// the cookie a browser would send first.
    ///
    /// - Returns: The selected cookies in the order requested, and the names with no match.
    static func exportSelection(
        _ cookies: [HTTPCookie],
        domain filter: String,
        names: [String],
    ) -> (selected: [HTTPCookie], missing: [String]) {
        let candidates = cookies
            .filter { domain($0.domain, matches: filter) }
            .sorted(by: isMoreSpecific)
        var selected: [HTTPCookie] = []
        var missing: [String] = []
        for name in names {
            if let cookie = candidates.first(where: { $0.name == name }) {
                selected.append(cookie)
            } else {
                missing.append(name)
            }
        }
        return (selected, missing)
    }

    // MARK: - Mapping

    /// Maps a cookie to its protocol representation, with the value only when revealed.
    static func cookieInfo(_ cookie: HTTPCookie, revealValue: Bool) -> CTL.CookieInfo {
        CTL.CookieInfo(
            name: cookie.name,
            value: revealValue ? cookie.value : nil,
            domain: cookie.domain,
            path: cookie.path,
            isSecure: cookie.isSecure,
            isHTTPOnly: cookie.isHTTPOnly,
            expiresDate: cookie.expiresDate?.formatted(.iso8601),
        )
    }

    // MARK: - Helpers

    private static func normalizedHost(_ domain: String) -> String {
        var host = domain.lowercased()
        while host.hasPrefix(".") {
            host.removeFirst()
        }
        return host
    }

    private static func isMoreSpecific(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
        if lhs.path.count != rhs.path.count {
            return lhs.path.count > rhs.path.count
        }
        let lhsHost = normalizedHost(lhs.domain)
        let rhsHost = normalizedHost(rhs.domain)
        if lhsHost.count != rhsHost.count {
            return lhsHost.count > rhsHost.count
        }
        return (lhsHost, lhs.name) < (rhsHost, rhs.name)
    }
}
